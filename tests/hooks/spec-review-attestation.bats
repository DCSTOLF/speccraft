#!/usr/bin/env bats
# Spec 0054 ACs 16 / 16a — the attestation extension and every template's schema.
#
# Two additions over spec 0052's reference-digest attestation:
#
#   payload_sha256 — a `subagent` reviewer reads the payload from a FILE in the
#     round dir rather than receiving it on a transport speccraft controls. So
#     it attests which bytes it read: without that, a subagent that opened the
#     wrong file, or a stale payload from a previous round, produces a verdict
#     about something other than what was sent.
#
#   permission_denied — a subagent runs under the orchestrator's permission
#     model and can be refused a tool mid-review. That is a DISPATCH failure,
#     not an unreadable reference, and conflating the two sends an operator to
#     look at file permissions when the fix is a tool grant.
#
# AC16a: every dispatchable template must DOCUMENT a reference_access block
# that round-trips through the very parser that reads reviewer responses. A
# template teaching a shape the parser cannot read means no reviewer using it
# can ever attest — the defect this branch already fixed once for re-review.md.

setup() {
  PLUGIN_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  LIB="$PLUGIN_DIR/commands/spec/review.lib.sh"
  TPL="$PLUGIN_DIR/templates/prompts"
  export PATH="$PLUGIN_DIR/bin:$PATH"
  TEST_DIR="$(mktemp -d)"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# ALL dispatchable templates. implement.md is excluded: it is not a review
# prompt and carries no verdict.
dispatchable_templates() {
  printf '%s\n' review re-review review-code arch-review pm-review
}

# extract_access_block <template> <out> — pull the documented reference_access
# block out of a template and fill its placeholders with plausible values, so
# it can be fed to the real parser.
extract_access_block() {
  local tpl="$1" out="$2"
  awk '
    /^reference_access:/ { inblk = 1 }
    inblk { print }
    inblk && /^[A-Za-z_]/ && !/^reference_access/ && NR > 1 { }
  ' "$tpl" > "$out.raw"
  # Replace the angle-bracket placeholders with a real path and digest.
  awk '
    { line = $0
      gsub(/"<[^>]*>"/, "\"PLACEHOLDER\"", line)
      print line }
  ' "$out.raw" > "$out"
  rm -f "$out.raw"
}

@test "every dispatchable template exists" {
  local t
  for t in $(dispatchable_templates); do
    [ -f "$TPL/$t.md" ] || {
      echo "missing template: templates/prompts/$t.md" >&2
      return 1
    }
  done
}

@test "every dispatchable template's reference_access block round-trips through the parser" {
  source "$LIB"
  # AC16a. The template teaches a shape; the parser reads it. If they disagree,
  # no reviewer using that template can attest at all — and the round reports
  # a fleet of unreadable references rather than a schema bug.
  local t out
  for t in $(dispatchable_templates); do
    [ -f "$TPL/$t.md" ] || { echo "missing template $t.md" >&2; return 1; }
    out="$TEST_DIR/$t.access"
    extract_access_block "$TPL/$t.md" "$out"
    [ -s "$out" ] || {
      echo "$t.md documents no reference_access block" >&2
      return 1
    }

    run _review_parse_reference_access "$out"
    [ "$status" -eq 0 ] || {
      echo "$t.md: the parser failed on its own documented block" >&2
      return 1
    }
    printf '%s\n' "$output" | grep -qF 'ACCESS-PATH ' || {
      echo "$t.md: documented block yields no ACCESS-PATH; got:" >&2
      printf '%s\n' "$output" >&2
      return 1
    }
    printf '%s\n' "$output" | grep -qF 'ACCESS-SHA ' || {
      echo "$t.md: documented block yields no ACCESS-SHA; got:" >&2
      printf '%s\n' "$output" >&2
      return 1
    }
  done
}

@test "every dispatchable template documents payload_sha256 in its attested block" {
  local t
  for t in $(dispatchable_templates); do
    [ -f "$TPL/$t.md" ] || { echo "missing template $t.md" >&2; return 1; }
    grep -qF 'payload_sha256' "$TPL/$t.md" || {
      echo "$t.md does not document payload_sha256" >&2
      return 1
    }
  done
}

@test "the YAML-map shape is rejected, per template" {
  source "$LIB"
  # The round-3 regression, re-pinned across all five: `<path>: <digest>` as a
  # YAML map reads as a key, not a list entry, so the parser yields no
  # ACCESS-PATH at all and every verdict silently fails attestation.
  local f="$TEST_DIR/map.yml"
  printf 'reference_access:\n  .speccraft/architecture.md: abc123\n' > "$f"
  run _review_parse_reference_access "$f"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF 'ACCESS-PATH ' && {
    echo "the YAML-map shape must not yield an ACCESS-PATH" >&2
    return 1
  }

  # And no template may teach it.
  local t
  for t in $(dispatchable_templates); do
    [ -f "$TPL/$t.md" ] || continue
    if grep -qE '^[[:space:]]+[^ #-][^:]*\.md:[[:space:]]*["<]' "$TPL/$t.md"; then
      echo "$t.md appears to document the YAML-map shape:" >&2
      grep -nE '^[[:space:]]+[^ #-][^:]*\.md:[[:space:]]*["<]' "$TPL/$t.md" >&2
      return 1
    fi
  done
  return 0
}

@test "the one-line - path: X, sha256: Y shape is rejected" {
  source "$LIB"
  # The other near-miss: both fields on one line. `- path: X, sha256: Y` parses
  # the whole remainder as the path and never emits a digest.
  local f="$TEST_DIR/oneline.yml"
  printf 'reference_access:\n  - path: a.md, sha256: abc123\n' > "$f"
  run _review_parse_reference_access "$f"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF 'ACCESS-SHA ' && {
    echo "the one-line shape must not yield an ACCESS-SHA" >&2
    return 1
  }
  return 0
}

@test "a template documenting no reference_access block fails the round trip" {
  source "$LIB"
  # So a SIXTH template added later cannot pass vacuously: the round-trip row
  # above must fail on a template that teaches nothing.
  local bare="$TEST_DIR/bare.md"
  printf 'You are reviewing something.\n\nverdict: approve\n' > "$bare"
  local out="$TEST_DIR/bare.access"
  extract_access_block "$bare" "$out"
  [ ! -s "$out" ] || {
    echo "a template with no block must extract to nothing; got:" >&2
    cat "$out" >&2
    return 1
  }
}

# ---------------------------------------------------------------------------
# AC16 — the validator's subagent arm
# ---------------------------------------------------------------------------

# mkpayload — a round payload plus its true digest.
mkpayload() {
  printf 'payload bytes for this round\n' > "$TEST_DIR/payload.md"
  PAYLOAD_SHA="$(review_digest "$TEST_DIR/payload.md" | awk '{print $1}')"
}

mkexpected() {
  printf '%s  .speccraft/architecture.md\n' "aaaa" > "$TEST_DIR/digests.txt"
}

@test "a subagent response missing payload_sha256 is attestation-failed missing-payload-digest" {
  source "$LIB"
  mkpayload
  mkexpected
  printf 'verdict: approve\nreference_access:\n  - path: ".speccraft/architecture.md"\n    sha256: "aaaa"\n' \
    > "$TEST_DIR/resp.out"

  run review_validate_reference_access "$TEST_DIR/resp.out" "$TEST_DIR/digests.txt" subagent "$TEST_DIR/payload.md"
  [ "$status" -ne 0 ]
  printf '%s\n' "$output" | grep -qF 'missing-payload-digest' || {
    echo "expected missing-payload-digest; got: $output" >&2
    return 1
  }
}

@test "the RECORDED outcome for a missing payload digest is exactly attestation-failed missing-payload-digest" {
  source "$LIB"
  mkpayload
  mkexpected
  printf 'verdict: approve\nreference_access:\n  - path: ".speccraft/architecture.md"\n    sha256: "aaaa"\n' \
    > "$TEST_DIR/resp.out"

  # EXACT, not a substring. The row above greps for the reason alone, which the
  # raw validator token `invalid:missing-payload-digest` also satisfies — so it
  # passed while every recorded outcome carried a spurious `invalid:` prefix
  # that AC16 does not name. Only the whole-line form can tell them apart.
  local tok out
  tok="$(review_validate_reference_access "$TEST_DIR/resp.out" "$TEST_DIR/digests.txt" subagent "$TEST_DIR/payload.md" || true)"
  out="$(review_attestation_outcome "$tok")"
  [ "$out" = "attestation-failed missing-payload-digest" ] || {
    echo "expected exactly 'attestation-failed missing-payload-digest'; got '$out' (from token '$tok')" >&2
    return 1
  }
}

@test "the RECORDED outcome for a wrong payload digest is exactly attestation-failed payload-digest-mismatch" {
  source "$LIB"
  mkpayload
  mkexpected
  printf 'verdict: approve\npayload_sha256: "deadbeef"\nreference_access:\n  - path: ".speccraft/architecture.md"\n    sha256: "aaaa"\n' \
    > "$TEST_DIR/resp.out"

  local tok out
  tok="$(review_validate_reference_access "$TEST_DIR/resp.out" "$TEST_DIR/digests.txt" subagent "$TEST_DIR/payload.md" || true)"
  out="$(review_attestation_outcome "$tok")"
  [ "$out" = "attestation-failed payload-digest-mismatch" ] || {
    echo "expected exactly 'attestation-failed payload-digest-mismatch'; got '$out' (from token '$tok')" >&2
    return 1
  }
}

@test "review_attestation_outcome strips the validator prefix for every 0052 reason" {
  source "$LIB"
  # The whole 0052 vocabulary, so a reason added later cannot reach an outcomes
  # file still wearing its internal prefix.
  local r out
  for r in absent malformed read-failure duplicate-path unknown-path missing-path digest-mismatch; do
    out="$(review_attestation_outcome "invalid:$r")"
    [ "$out" = "attestation-failed $r" ] || {
      echo "invalid:$r mapped to '$out', expected 'attestation-failed $r'" >&2
      return 1
    }
  done
}

@test "review_attestation_outcome passes a dispatch failure through unchanged" {
  source "$LIB"
  # A refused tool is NOT an attestation fault and must not be relabelled as
  # one on the way to the outcomes file.
  local out
  out="$(review_attestation_outcome 'failed subagent-permission-denied Bash')"
  [ "$out" = "failed subagent-permission-denied Bash" ] || {
    echo "a dispatch failure must pass through unchanged; got '$out'" >&2
    return 1
  }
  out="$(review_attestation_outcome ok)"
  [ "$out" = "ok" ]
}

@test "review_attestation_outcome refuses a token it does not recognise" {
  source "$LIB"
  # So a validator that starts emitting a new shape is a loud error rather than
  # an outcomes file full of tokens nothing downstream can classify.
  run review_attestation_outcome 'something-else'
  [ "$status" -ne 0 ] || {
    echo "an unrecognised token must not be mapped silently; got: $output" >&2
    return 1
  }
}

@test "a cli permission denial is NOT reported as a subagent denial" {
  source "$LIB"
  mkpayload
  mkexpected
  printf 'permission_denied: Bash\n' > "$TEST_DIR/resp.out"

  # The remedy differs by mode, so the token must too. A subagent is refused by
  # the ORCHESTRATOR's permission model (fix: the command's allowed-tools); a
  # cli reviewer is refused by its own invocation (fix: that agent's cmd in
  # agents.toml — this repo carries `--allowedTools … Bash(shasum:*)` on
  # `claude -p` for exactly that reason). The arm was not mode-gated, so a cli
  # refusal sent the operator to edit the wrong file.
  local tok
  tok="$(review_validate_reference_access "$TEST_DIR/resp.out" "$TEST_DIR/digests.txt" cli "$TEST_DIR/payload.md" || true)"
  [ "$tok" = "failed permission-denied Bash" ] || {
    echo "a cli denial must be 'failed permission-denied Bash'; got '$tok'" >&2
    return 1
  }
  # And the subagent arm still names the subagent.
  tok="$(review_validate_reference_access "$TEST_DIR/resp.out" "$TEST_DIR/digests.txt" subagent "$TEST_DIR/payload.md" || true)"
  [ "$tok" = "failed subagent-permission-denied Bash" ] || {
    echo "a subagent denial must be 'failed subagent-permission-denied Bash'; got '$tok'" >&2
    return 1
  }
}

@test "a denial with no mode argument is not attributed to a subagent" {
  source "$LIB"
  mkpayload
  mkexpected
  printf 'permission_denied: Read\n' > "$TEST_DIR/resp.out"
  # Spec 0052's call shape passes no mode at all. It must not inherit the
  # subagent token by default — the default is the mode that existed first.
  local tok
  tok="$(review_validate_reference_access "$TEST_DIR/resp.out" "$TEST_DIR/digests.txt" || true)"
  [ "$tok" = "failed permission-denied Read" ] || {
    echo "a modeless denial must not be a subagent denial; got '$tok'" >&2
    return 1
  }
}

@test "a wrong payload_sha256 is attestation-failed payload-digest-mismatch" {
  source "$LIB"
  mkpayload
  mkexpected
  printf 'verdict: approve\npayload_sha256: "deadbeef"\nreference_access:\n  - path: ".speccraft/architecture.md"\n    sha256: "aaaa"\n' \
    > "$TEST_DIR/resp.out"

  run review_validate_reference_access "$TEST_DIR/resp.out" "$TEST_DIR/digests.txt" subagent "$TEST_DIR/payload.md"
  [ "$status" -ne 0 ]
  printf '%s\n' "$output" | grep -qF 'payload-digest-mismatch' || {
    echo "expected payload-digest-mismatch; got: $output" >&2
    return 1
  }
}

@test "a correct payload digest plus correct reference digests is valid" {
  source "$LIB"
  mkpayload
  mkexpected
  printf 'verdict: approve\npayload_sha256: "%s"\nreference_access:\n  - path: ".speccraft/architecture.md"\n    sha256: "aaaa"\n' \
    "$PAYLOAD_SHA" > "$TEST_DIR/resp.out"

  run review_validate_reference_access "$TEST_DIR/resp.out" "$TEST_DIR/digests.txt" subagent "$TEST_DIR/payload.md"
  [ "$status" -eq 0 ] || {
    echo "a fully correct subagent attestation must validate; got: $output" >&2
    return 1
  }
  printf '%s\n' "$output" | grep -qxF 'ok'
}

@test "permission_denied maps to failed subagent-permission-denied" {
  source "$LIB"
  mkpayload
  mkexpected
  printf 'permission_denied: Bash\n' > "$TEST_DIR/resp.out"

  run review_validate_reference_access "$TEST_DIR/resp.out" "$TEST_DIR/digests.txt" subagent "$TEST_DIR/payload.md"
  [ "$status" -ne 0 ]
  printf '%s\n' "$output" | grep -qF 'subagent-permission-denied' || {
    echo "expected subagent-permission-denied; got: $output" >&2
    return 1
  }
}

@test "permission_denied is not reported as a generic attestation failure" {
  source "$LIB"
  mkpayload
  mkexpected
  printf 'permission_denied: Bash\n' > "$TEST_DIR/resp.out"

  run review_validate_reference_access "$TEST_DIR/resp.out" "$TEST_DIR/digests.txt" subagent "$TEST_DIR/payload.md"
  # A refused tool is a DISPATCH failure. Reporting it as an attestation
  # problem sends an operator to look at the reviewer's digests when the fix
  # is a tool grant in allowed-tools.
  printf '%s\n' "$output" | grep -qE 'missing-payload-digest|payload-digest-mismatch|missing-digest' && {
    echo "a permission denial must not be reported as an attestation fault; got: $output" >&2
    return 1
  }
  # It must also name the tool that was refused.
  printf '%s\n' "$output" | grep -qF 'Bash' || {
    echo "the outcome must name the refused tool; got: $output" >&2
    return 1
  }
  return 0
}

@test "a cli response is unaffected by the payload-digest rule" {
  source "$LIB"
  mkpayload
  mkexpected
  # No payload_sha256 at all, and no mode argument: spec 0052's cli contract,
  # which must keep validating exactly as before. The payload digest is a
  # SUBAGENT requirement — a cli reviewer receives the bytes on a transport
  # speccraft controls, so there is nothing for it to confuse them with.
  printf 'verdict: approve\nreference_access:\n  - path: ".speccraft/architecture.md"\n    sha256: "aaaa"\n' \
    > "$TEST_DIR/resp.out"

  run review_validate_reference_access "$TEST_DIR/resp.out" "$TEST_DIR/digests.txt"
  [ "$status" -eq 0 ] || {
    echo "the 0052 cli contract must be unchanged; got: $output" >&2
    return 1
  }
}
