#!/usr/bin/env bash
# Mock aux reviewer for hermetic e2e tests (spec 0052).
#
# Installed as both `codex` and `opencode` by install-mock-agents.sh. It is a
# STANDALONE FILE rather than a heredoc inside the installer so that
# tests/hooks/e2e-mock-reviewer.bats can exercise it directly — the alternative
# is discovering its defects only from a ten-minute devcontainer job, which is
# exactly how this file came to need rewriting.
#
# WHY IT READS THE PAYLOAD AT ALL. Before spec 0052 these mocks did
# `exec </dev/null` and emitted a canned verdict, ignoring their input. Under
# 0052 a verdict that does not return a matching SHA-256 for every reference
# path counts toward NEITHER round predicate — the same rule as a timeout — so
# the canned verdict was rejected as `attestation-failed`, the round went inert,
# `review.md` was never written, and the e2e's step 4 failed. The product was
# behaving exactly as specified; the mock was a reviewer that could not prove it
# had read anything.
#
# So this mock now does the one thing the reference tier actually requires: it
# opens each referenced path at the dispatched cwd and reports a real digest.
# That makes the e2e a genuine end-to-end proof of the tier — the reference-read
# contract was booked in the plan as "not fully testable at the bats layer" and
# this is where it becomes testable.
set -euo pipefail

self="$(basename "$0")"

# Per-agent response override, e.g. SPECCRAFT_MOCK_CODEX_RESPONSE_FILE.
# Emitted VERBATIM: a test that supplies its own fixture owns its content,
# including whether it attests. That is how the inert-round path is exercised.
override_var="SPECCRAFT_MOCK_$(printf '%s' "$self" | tr '[:lower:]-' '[:upper:]_')_RESPONSE_FILE"
override_path="$(eval "printf '%s' \"\${$override_var:-}\"")"
if [ -n "$override_path" ] && [ -f "$override_path" ]; then
  cat "$override_path"
  exit 0
fi

# Read the payload ONLY when stdin is a regular file.
#
# Load-bearing, and the reason the original mock detached stdin outright: the
# driver dispatches `cmd < "$artifact"`, so stdin is the artifact and EOFs at
# once — but when a mock is invoked with stdin inherited from a `claude -p`
# session, that pipe NEVER EOFs and an unconditional `cat` hangs the whole
# round. `-f` distinguishes the two precisely, so the payload is read where it
# exists and no read is attempted where it would block.
payload=""
if [ -f /dev/stdin ]; then
  payload="$(cat || true)"
fi

# The reference records the composer emitted, as repo-relative paths. Anchored
# to the section so a `- path:` line anywhere else in the payload (a spec that
# quotes one, say) cannot be mistaken for a reference record.
refs=""
if [ -n "$payload" ]; then
  refs="$(printf '%s\n' "$payload" | awk '
    /^## Reference files/ { inref = 1; next }
    /^## /                { inref = 0 }
    inref && /^- path: /  { sub(/^- path: /, ""); print }
  ')"
fi

emit_attestation() {
  local p digest access="" failures=""
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    if [ -r "$p" ]; then
      # `shasum -a 256`, never the GNU-only tool: this runs on the macOS runner
      # too, and it must agree byte-for-byte with what the composer computed.
      digest="$(shasum -a 256 < "$p" | cut -d' ' -f1)"
      access="${access}  - path: \"${p}\"
    sha256: \"${digest}\"
"
    else
      failures="${failures}  - path: \"${p}\"
    reason: \"not readable from the dispatched cwd\"
"
    fi
  done <<EOF
$refs
EOF

  # Always emit the key, even with nothing to report: an ABSENT block is
  # `invalid:absent` to the validator, which is a different finding from "there
  # were no reference files this round".
  if [ -z "$access" ]; then
    printf 'reference_access: []\n'
  else
    printf 'reference_access:\n%s' "$access"
  fi
  if [ -z "$failures" ]; then
    printf 'reference_access_failures: []\n'
  else
    printf 'reference_access_failures:\n%s' "$failures"
  fi
}

case "$self" in
  opencode)
    cat <<'RESP'
verdict: approve
concerns: []
suggestions:
  - "Consider table-driven tests."
guardrail_violations: []
convention_violations: []
RESP
    emit_attestation
    printf '\n(mock opencode response)\n'
    ;;
  *)
    cat <<'RESP'
verdict: approve-with-comments
concerns:
  - "Acceptance criterion phrasing could be more observable."
suggestions:
  - "Add explicit error-path test."
guardrail_violations: []
convention_violations: []
RESP
    emit_attestation
    printf '\n(mock codex response)\n'
    ;;
esac
