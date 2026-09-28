#!/usr/bin/env bash
# commands/spec/review.lib.sh — testable shell helpers backing the diff-focused
# re-review path of /speccraft:spec:review (spec 0035). Sourced both by
# commands/spec/review.md at runtime and by tests/hooks/spec-review-diff.bats.
#
# All functions are pure (no top-level side effects). The Go binaries own change
# DETECTION (speccraft-state review-diff / review-snapshot); this lib owns the
# command-layer UX: parsing the prior review fingerprint, classifying the run via
# the provenance gate, and building the scoped reviewer payload.
#
# Cross-shell self-location and zsh-reserved-name avoidance follow the spec-0029
# conventions; no bare `status` locals.

set -euo pipefail

# ---------------------------------------------------------------------------
# Spec 0052 — payload tiering and heading extraction.
#
# Tier membership is a FIXED TABLE, not a heuristic over the spec's content and
# not a size threshold: a file is inline or reference by identity, so the
# payload's shape cannot drift with the day's file sizes. Anything not in a
# table is an ERROR, never a silent default — `.speccraft/history.md` included,
# which this spec deliberately does not add to what a reviewer sees.
# ---------------------------------------------------------------------------

# Pasted verbatim: small, and guardrails in particular must be unmissable.
REVIEW_INLINE_SET=".speccraft/guardrails.md .speccraft/index.md"
# Sent as path + byte size + heading index; the reviewer reads what it needs.
REVIEW_REFERENCE_SET=".speccraft/architecture.md .speccraft/conventions.md"

review_error() { echo "$*" >&2; }

# _review_repo_relative <path> — echo <path> relative to the repository root.
# Absolute paths under the root are stripped to their repo-relative form; a
# leading `./` is removed; anything else is returned unchanged (and will fail
# the tier lookup, which is the point).
_review_repo_relative() {
  local p="$1" root
  root="$(speccraft-state find-root 2>/dev/null || pwd)"
  case "$p" in
    "$root"/*) p="${p#"$root"/}" ;;
    ./*)       p="${p#./}" ;;
  esac
  printf '%s\n' "$p"
}

# review_context_tier <path> — echo "inline" | "reference", or fail with a
# named error.
#
# The comparison is against the FULL repo-relative path, never the trailing
# basename. Matching on the basename would classify `vendor/other/.speccraft/
# conventions.md`, or a spec document that happens to be called
# `conventions.md`, as reference-tier — silently admitting a foreign file to
# the payload, or worse, omitting a real one's body on the assumption the
# reviewer can find it.
review_context_tier() {
  local path="${1:-}" rel entry
  [ -n "$path" ] || { review_error "review_context_tier: path required"; return 1; }
  rel="$(_review_repo_relative "$path")"
  for entry in $REVIEW_INLINE_SET; do
    [ "$rel" = "$entry" ] && { printf 'inline\n'; return 0; }
  done
  for entry in $REVIEW_REFERENCE_SET; do
    [ "$rel" = "$entry" ] && { printf 'reference\n'; return 0; }
  done
  review_error "review_context_tier: '$path' is not a known context file (tier table: $REVIEW_INLINE_SET $REVIEW_REFERENCE_SET)"
  return 1
}

# review_heading_index <file> — emit every `^## ` and `^### ` heading, in file
# order, and nothing else.
#
# PORTABILITY, load-bearing: the heading match uses anchored literal forms
# (`/^## /`, `/^### /`) and NEVER a regex INTERVAL EXPRESSION (a brace-delimited
# repetition count) on the hash run. This devcontainer runs mawk, which does not
# implement interval expressions and matches NOTHING for that form — silently,
# with exit 0. The identical spelling works under GNU `grep -E`, so the
# divergence is invisible without running it (cf.
# commands/history/compact.lib.sh:26, which spells the four-digit year as a
# bracket run rather than a repetition count for the same reason).
#
# The forbidden spelling is deliberately not written out here: this file sits
# under a scanned root, and tests/hooks/portability-guard.bats clause (f) flags
# the form in comments too, by design. The literal lives in that guard's
# fixtures and in tests/hooks/spec-review-payload.bats, both outside the scan.
#
# Fence grammar: a fence opens on a line whose first non-space run is three or
# more backticks or three or more tildes, and closes only on a line of the SAME
# character at the SAME OR GREATER length. An unclosed fence suppresses headings
# to end of file. Runs under LC_ALL=C so two hosts with different locales cannot
# produce different records from the same bytes.
review_heading_index() {
  local file="${1:-}"
  [ -n "$file" ] || { review_error "review_heading_index: file required"; return 1; }
  # `-e`, not `-f`: a reference source may be a FIFO or other non-regular file,
  # and the one-scan proof in tests/hooks/spec-review-payload.bats depends on it.
  [ -e "$file" ] || { review_error "review_heading_index: $file not found"; return 1; }
  _review_heading_stream < "$file"
}

# _review_heading_stream — the single heading/fence parser, reading stdin.
# review_heading_index wraps it for a path; _review_scan_reference feeds it the
# ONE buffer it read (AC8), so there is exactly one grammar in the lib rather
# than a file version and a buffer version drifting apart
# (.speccraft/conventions.md §"One shared parser entrypoint").
_review_heading_stream() {
  LC_ALL=C awk '
    # Length of the leading run of character c in s (interval-free).
    function runlen(s, c,   n) {
      n = 0
      while (substr(s, n + 1, 1) == c) n++
      return n
    }
    {
      line = $0
      sub(/\r$/, "", line)          # CRLF checkouts must not alter the record
      probe = line
      sub(/^[ ]*/, "", probe)       # a fence may be indented
      fc = substr(probe, 1, 1)
      n  = 0
      if (fc == "`" || fc == "~") n = runlen(probe, fc)

      if (infence) {
        # Close only on the same character at >= the opening length.
        if (n >= 3 && fc == fence_char && n >= fence_len) infence = 0
        next
      }
      if (n >= 3) { infence = 1; fence_char = fc; fence_len = n; next }
      if (line ~ /^## / || line ~ /^### /) print line
    }
  '
}

# ---------------------------------------------------------------------------
# Spec 0052 — the digest primitive, and the one-scan reference record.
# ---------------------------------------------------------------------------

# _review_digest_cmd — echo the SHA-256 command word, resolved ONCE per shell.
#
# PORTABILITY, load-bearing and the same class as the awk-interval trap guarded
# above: the GNU coreutils checksum tool is absent from a default macOS
# userland, while `shasum -a 256` ships on both BSD and GNU systems. This repo
# lost eight consecutive CI runs to that class (spec 0050), so `shasum` is
# PREFERRED and the GNU tool is reached only through a `command -v` probe whose
# resolved PATH is what gets executed — never a bare literal invocation, which
# tests/hooks/portability-guard.bats clause (e) correctly forbids under a
# shipped root.
_REVIEW_DIGEST_CMD="${_REVIEW_DIGEST_CMD:-}"
_review_digest_cmd() {
  [ -z "$_REVIEW_DIGEST_CMD" ] || { printf '%s\n' "$_REVIEW_DIGEST_CMD"; return 0; }
  if command -v shasum >/dev/null 2>&1; then
    _REVIEW_DIGEST_CMD="shasum -a 256"
  else
    local gnu
    gnu="$(command -v sha256sum 2>/dev/null || true)"
    [ -n "$gnu" ] || {
      review_error "review_digest: no SHA-256 primitive on PATH (looked for 'shasum -a 256', then the GNU coreutils checksum tool)"
      return 1
    }
    _REVIEW_DIGEST_CMD="$gnu"
  fi
  printf '%s\n' "$_REVIEW_DIGEST_CMD"
}

# review_digest [<file>] — echo the bare lowercase hex SHA-256 of <file>, or of
# stdin when no file is given. Both primitives emit "<hex>  <name>", so the
# first field is taken.
review_digest() {
  local cmd out
  cmd="$(_review_digest_cmd)" || return 1
  if [ $# -gt 0 ]; then
    out="$($cmd < "$1")" || return 1
  else
    out="$($cmd)" || return 1
  fi
  printf '%s\n' "${out%% *}"
}

# _review_scan_reference <path> — read <path> ONCE and emit its record:
#   line 1   : "<byte-size> <sha256>"
#   lines 2+ : the heading index, in file order
#
# ONE read is a contract, not an optimisation (AC8). The obvious two-pass shape
# — `wc -c "$f"` then `grep '^## ' "$f"` — looks reasonable and is wrong: on a
# single-use source the size comes from one read and the index from another, so
# the record describes two different things. Everything below is derived from
# the single buffer.
#
# The buffer cannot carry a NUL byte, and that FAILS SAFE rather than silently:
# a NUL-bearing reference yields a digest the reviewer's own read will not
# match, the attestation fails, and the verdict is not counted — the same
# outcome as a reference that could not be read at all.
_review_scan_reference() {
  local file="${1:-}" buf size digest
  [ -n "$file" ] || { review_error "_review_scan_reference: path required"; return 1; }
  [ -e "$file" ] || { review_error "_review_scan_reference: $file not found"; return 1; }
  # The trailing-X sentinel preserves trailing newlines, which command
  # substitution would otherwise strip — the same byte-fidelity concern AC10
  # settles for the payload artifact, arriving one layer down.
  buf="$(LC_ALL=C cat -- "$file"; printf X)"
  buf="${buf%X}"
  size="$(printf '%s' "$buf" | LC_ALL=C wc -c | tr -d ' ')"
  digest="$(printf '%s' "$buf" | review_digest)" || return 1
  printf '%s %s\n' "$size" "$digest"
  printf '%s' "$buf" | _review_heading_stream
}

# ---------------------------------------------------------------------------
# Spec 0052 — round predicates and the round's single durable-write point.
#
# A round's result is a set of records, one per REQUIRED reviewer, of the shape
#   <agent> <outcome> [detail…]
# and TWO predicates are taken over it. They are deliberately separate because
# they gate different things, and conflating them breaks a real path:
#
#   responses_complete  — every required reviewer returned a VERDICT. Gates
#     synthesis, the review.md write and the reviewed_sha256 commit — and holds
#     for ANY verdict, `changes-requested` included (spec 0035 AC2).
#   approval_quorum_met — AGREEING verdicts >= the quorum. Gates `status:
#     reviewed`, and nothing else.
#
# `review_quorum` counts agreement, so gating the durable write on it would
# forbid exactly what a legitimate changes-requested round does: persist its
# review. A refusal, a timeout, a failure and a failed digest attestation are
# all non-verdicts — an over-budget agent is held to the same standard as the
# timeout it replaces, or a round reaches quorum having consulted fewer models
# than the developer believes.
# ---------------------------------------------------------------------------

REVIEW_VERDICTS="approve approve-with-comments changes-requested reject"
REVIEW_AGREEING_VERDICTS="approve approve-with-comments"
# A timeout is not a verdict (spec 0035 review.md step 6), and neither is a
# pre-dispatch budget refusal or a reference read that could not be attested.
REVIEW_NON_VERDICTS="refused timeout failed attestation-failed"

# _review_outcome_kind <outcome> — echo "verdict" | "non-verdict"; return 2 and
# name the token otherwise. An unrecognised outcome must NOT fall through to
# "non-verdict": a typo would then read as a refusal, quietly making a round
# inert with no indication why.
_review_outcome_kind() {
  local outcome="${1:-}" entry
  for entry in $REVIEW_VERDICTS; do
    [ "$outcome" = "$entry" ] && { printf 'verdict\n'; return 0; }
  done
  for entry in $REVIEW_NON_VERDICTS; do
    [ "$outcome" = "$entry" ] && { printf 'non-verdict\n'; return 0; }
  done
  review_error "review: unknown outcome '$outcome' (verdicts: $REVIEW_VERDICTS; non-verdicts: $REVIEW_NON_VERDICTS)"
  return 2
}

# review_responses_complete <outcomes-file>
#   0 — every required reviewer returned a verdict
#   1 — at least one did not, or the set is empty (a round that never ran is
#       not a round in which everyone answered)
#   2 — malformed record, named on stderr
review_responses_complete() {
  local file="${1:-}" agent outcome rest kind seen=0 rc
  [ -n "$file" ] && [ -f "$file" ] || {
    review_error "review_responses_complete: an outcomes file is required (got '${file:-}')"
    return 2
  }
  while IFS=' ' read -r agent outcome rest || [ -n "$agent" ]; do
    [ -n "$agent" ] || continue
    [ -n "$outcome" ] || { review_error "review_responses_complete: record for '$agent' has no outcome"; return 2; }
    rc=0; kind="$(_review_outcome_kind "$outcome")" || rc=$?
    [ "$rc" -eq 0 ] || return 2
    seen=$((seen + 1))
    [ "$kind" = "verdict" ] || return 1
  done < "$file"
  [ "$seen" -gt 0 ] || return 1
  return 0
}

# review_approval_quorum_met <quorum> <outcomes-file>
#   0 — agreeing verdicts (approve / approve-with-comments) >= quorum
#   1 — below quorum
#   2 — malformed quorum or record
review_approval_quorum_met() {
  local quorum="${1:-}" file="${2:-}" agent outcome rest entry count=0 rc kind
  case "$quorum" in
    ''|*[!0-9]*) review_error "review_approval_quorum_met: quorum must be a base-10 integer (got '${quorum:-}')"; return 2 ;;
  esac
  [ -n "$file" ] && [ -f "$file" ] || {
    review_error "review_approval_quorum_met: an outcomes file is required (got '${file:-}')"
    return 2
  }
  while IFS=' ' read -r agent outcome rest || [ -n "$agent" ]; do
    [ -n "$agent" ] || continue
    [ -n "$outcome" ] || { review_error "review_approval_quorum_met: record for '$agent' has no outcome"; return 2; }
    rc=0; kind="$(_review_outcome_kind "$outcome")" || rc=$?
    [ "$rc" -eq 0 ] || return 2
    for entry in $REVIEW_AGREEING_VERDICTS; do
      [ "$outcome" = "$entry" ] && count=$((count + 1))
    done
  done < "$file"
  [ "$count" -ge "$quorum" ]
}

# review_finalize_round <spec-dir> <quorum> <outcomes-file>
# — the ONLY place a review round performs a durable write. Emits the round
# report on stdout and returns 0 whether or not the round was productive: a
# refusal is data, not a shell failure.
#
# When `responses_complete` is false the round is INERT — no snapshot promote,
# no fingerprint commit, review.md untouched — and the report says so while
# still naming every verdict that WAS obtained. That is what stops a
# refusal-only round wiping the prior review.md and collapsing spec 0035's
# provenance gate on the next --diff.
#
# The snapshot promote lives HERE rather than at the start of the round (spec
# 0052 AC24). `review-diff --promote` used to re-baseline review-snapshot.md
# before any verdict existed, so an all-refused round silently moved the anchor
# the NEXT round classifies against, and the following round misclassified.
review_finalize_round() {
  local spec_dir="${1:-}" quorum="${2:-}" file="${3:-}"
  local complete=false quorum_met=false synthesis=skipped state=draft
  local rc fp agent outcome rest kind
  [ -n "$spec_dir" ] || { review_error "review_finalize_round: spec dir required"; return 2; }

  rc=0; review_responses_complete "$file" || rc=$?
  [ "$rc" -ne 2 ] || return 2
  [ "$rc" -eq 0 ] && complete=true

  rc=0; review_approval_quorum_met "$quorum" "$file" || rc=$?
  [ "$rc" -ne 2 ] || return 2
  [ "$rc" -eq 0 ] && quorum_met=true

  if [ "$complete" = true ]; then
    synthesis=done
    fp="$(speccraft-state review-snapshot write "$spec_dir")" || {
      review_error "review_finalize_round: review-snapshot write failed; review.md left unchanged"
      return 1
    }
    speccraft-state review-commit "$spec_dir/review.md" "$fp" || {
      review_error "review_finalize_round: review-commit failed; review.md left unchanged"
      return 1
    }
    [ "$quorum_met" = true ] && state=reviewed
  fi

  printf 'responses_complete: %s\n' "$complete"
  printf 'approval_quorum_met: %s\n' "$quorum_met"
  printf 'synthesis: %s\n' "$synthesis"
  printf 'status: %s\n' "$state"

  # Every refusal AND every verdict obtained. A report naming only the failures
  # hides a real verdict from the developer; one naming only the verdicts hides
  # that the round consulted fewer models than it appears to have.
  while IFS=' ' read -r agent outcome rest || [ -n "$agent" ]; do
    [ -n "$agent" ] || continue
    rc=0; kind="$(_review_outcome_kind "$outcome")" || rc=$?
    [ "$rc" -eq 0 ] || return 2
    if [ "$kind" = "verdict" ]; then
      printf 'verdict: %s %s\n' "$agent" "$outcome"
    elif [ "$outcome" = "attestation-failed" ]; then
      # Its own category: a reviewer whose reference reads never attest must be
      # diagnosable, not merely excluded round after round (AC25).
      printf 'attestation-failure: %s%s\n' "$agent" "${rest:+ $rest}"
    else
      printf 'no-verdict: %s %s%s\n' "$agent" "$outcome" "${rest:+ $rest}"
    fi
  done < "$file"
  return 0
}

# ---------------------------------------------------------------------------
# Spec 0052 — the round's temp directory, the ONE payload artifact, and dispatch.
#
# "Bytes exactly as handed to the CLI" cannot be guaranteed through shell command
# substitution, which strips trailing newlines. So the payload is written to a
# single file, the budget is measured over THAT file, and THAT file is what gets
# piped to stdin, passed with --file, or read for an argv-mode invocation.
# Measured bytes and dispatched bytes are the same bytes by construction rather
# than by convention.
#
# This is the ONLY materialization permitted. No debug or convenience copy may be
# written anywhere else: a cached full prompt would reintroduce the unbounded
# artifact through a side channel while the budget check still reported success.
# ---------------------------------------------------------------------------

REVIEW_ROUND_TMPDIR="${REVIEW_ROUND_TMPDIR:-}"

_review_round_cleanup() {
  [ -z "${REVIEW_ROUND_TMPDIR:-}" ] || rm -rf "$REVIEW_ROUND_TMPDIR"
}

# The caller's EXIT handler, saved so installing ours does not DESTROY it.
# Silently clobbering EXIT is not a theoretical concern: it makes a failing bats
# test report nothing at all, so an assertion added to such a test would be
# inert — and a driver that had its own cleanup would simply lose it.
_REVIEW_PRIOR_EXIT="${_REVIEW_PRIOR_EXIT:-}"

_review_fire_prior_exit() {
  local spec="${_REVIEW_PRIOR_EXIT:-}" body raw
  [ -n "$spec" ] || return 0
  _REVIEW_PRIOR_EXIT=""          # fire once, never recurse
  body="${spec#trap -- }"
  body="${body% EXIT}"
  # `trap -p` emits a re-evalable single-quoted word, which is why this is a
  # quoting-safe unwrap rather than a hopeful one.
  eval "raw=$body" 2>/dev/null || return 0
  eval "$raw" || true
}

# review_round_tmpdir — create the round's 0700 temp directory, set
# REVIEW_ROUND_TMPDIR, and install the cleanup trap IMMEDIATELY after creation.
#
# It sets a variable rather than echoing the path ON PURPOSE. A caller writing
# `d="$(review_round_tmpdir)"` would install the trap inside the command
# substitution's subshell, which exits at once — deleting the directory before
# the round could use it. There is no spelling of this helper that is safe to
# call in a subshell, so it does not offer one.
#
# The trap covers EXIT HUP INT TERM, so a crash cannot leave a full review
# prompt on disk indefinitely. It CANNOT cover SIGKILL — that is a stated
# boundary, not an oversight: `kill -9` leaves the directory behind.
review_round_tmpdir() {
  REVIEW_ROUND_TMPDIR="$(mktemp -d)"
  chmod 700 "$REVIEW_ROUND_TMPDIR"
  _REVIEW_PRIOR_EXIT="$(trap -p EXIT)"
  trap '_review_round_cleanup; _review_fire_prior_exit' EXIT
  trap '_review_round_cleanup; _review_fire_prior_exit; exit 130' HUP INT TERM
}

# review_materialize_payload <artifact> <composer-command…>
# — run the composer with stdout REDIRECTED into a single mode-0600 artifact,
# and echo the artifact's byte count.
#
# Redirected, never captured: `bytes="$(compose)"` would strip the trailing
# newlines and the measured count would then describe bytes nobody dispatches.
# An artifact that already exists is REFUSED rather than overwritten, which is
# the single-materialization invariant enforced where it can actually be checked.
review_materialize_payload() {
  local art="${1:-}"
  [ -n "$art" ] || { review_error "review_materialize_payload: artifact path required"; return 1; }
  shift
  [ "$#" -gt 0 ] || { review_error "review_materialize_payload: a composer command is required"; return 1; }
  [ ! -e "$art" ] || {
    review_error "review_materialize_payload: refusing to materialize twice — '$art' already exists"
    return 1
  }
  ( umask 077; : > "$art" ) || return 1
  chmod 600 "$art"
  # The instrumented seam AC11 counts. Bounded to NAMED call sites: an unbounded
  # "no copy anywhere on the filesystem" check would be the vacuous negative
  # this spec argues against.
  [ -z "${REVIEW_MATERIALIZE_LOG:-}" ] || printf 'materialize %s\n' "$art" >> "$REVIEW_MATERIALIZE_LOG"
  "$@" > "$art" || {
    review_error "review_materialize_payload: composer failed; '$art' is incomplete"
    return 1
  }
  LC_ALL=C wc -c < "$art" | tr -d ' '
}

# review_seam_single_creation <log> — exit 0 iff exactly one payload artifact was
# created this round, naming every creation otherwise.
review_seam_single_creation() {
  local log="${1:-}" n
  [ -n "$log" ] && [ -f "$log" ] || {
    review_error "review_seam_single_creation: instrumentation log not found: '${log:-}'"; return 1; }
  n="$(grep -c . "$log" || true)"
  [ "$n" = "1" ] || {
    review_error "review_seam_single_creation: expected exactly ONE payload materialization this round, found $n:"
    review_error "$(cat -- "$log")"
    return 1
  }
  return 0
}

# review_payload_representable <artifact> — the stated representability boundary.
#
# The payload domain is NUL-free, valid UTF-8. A NUL byte is refused because
# POSIX argv cannot carry one, which would make the measured-equals-dispatched
# claim unimplementable for argv mode; invalid UTF-8 is refused because two
# hosts could otherwise disagree about the same bytes. The diagnostic names
# WHICH of the two failed — "unrepresentable" alone would not tell the developer
# what to look for.
review_payload_representable() {
  local f="${1:-}" total stripped
  [ -n "$f" ] && [ -f "$f" ] || {
    review_error "review_payload_representable: artifact not found: '${f:-}'"; return 1; }
  total="$(LC_ALL=C wc -c < "$f" | tr -d ' ')"
  stripped="$(LC_ALL=C tr -d '\000' < "$f" | LC_ALL=C wc -c | tr -d ' ')"
  [ "$total" = "$stripped" ] || {
    review_error "review_payload_representable: '$f' contains a NUL byte; POSIX argv cannot carry one, so this payload cannot be dispatched byte-for-byte"
    return 1
  }
  if command -v iconv >/dev/null 2>&1; then
    iconv -f UTF-8 -t UTF-8 < "$f" >/dev/null 2>&1 || {
      review_error "review_payload_representable: '$f' is not valid UTF-8"
      return 1
    }
  else
    review_error "review_payload_representable: iconv is absent, so the UTF-8 arm was NOT checked for '$f' (the NUL arm was)"
  fi
  return 0
}

# review_dispatch_bytes <artifact> — set REVIEW_DISPATCH_PAYLOAD to the artifact's
# bytes EXACTLY, trailing newlines included.
#
# `var="$(cat f)"` strips them — the same defect review_materialize_payload
# closes for composition, arriving one step later, at the file-to-argv
# conversion. `read -d ''` reads to EOF without a NUL delimiter and returns
# non-zero there while still assigning, which is why the failure is tolerated.
review_dispatch_bytes() {
  local f="${1:-}"
  [ -n "$f" ] && [ -f "$f" ] || {
    review_error "review_dispatch_bytes: artifact not found: '${f:-}'"; return 1; }
  IFS= read -r -d '' REVIEW_DISPATCH_PAYLOAD < "$f" || true
  return 0
}

# review_dispatch_payload <agent-cmd> <input-mode> <artifact>
# — send the artifact's bytes to the CLI, unmodified, by the mode's transport.
#
# `file` mode passes the ROUND'S ARTIFACT itself. Writing a tempfile here would
# be the second copy AC11 forbids, and it is the most natural place for one to
# appear.
review_dispatch_payload() {
  local cmd="${1:-}" mode="${2:-}" art="${3:-}"
  [ -n "$cmd" ] || { review_error "review_dispatch_payload: agent command required"; return 1; }
  [ -n "$art" ] && [ -f "$art" ] || {
    review_error "review_dispatch_payload: payload artifact not found: '${art:-}'"; return 1; }
  case "$mode" in
    ''|stdin) $cmd < "$art" ;;
    file)     $cmd --file "$art" ;;
    argv|acp)
      review_dispatch_bytes "$art" || return 1
      $cmd "$REVIEW_DISPATCH_PAYLOAD"
      ;;
    *) review_error "review_dispatch_payload: unknown input mode '$mode' (known: argv, acp, stdin, file; empty normalizes to stdin)"; return 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# Spec 0052 — the pre-dispatch byte budget.
#
# The failure this replaces is a 600 s timeout, which is the least informative
# outcome available: ten minutes per agent, no verdict, and no indication
# whether the model was slow or the prompt never fit. Oversize is discovered
# HERE, before dispatch, with a remedy specific to the limit that bit.
# ---------------------------------------------------------------------------

# argv-mode agents only. Derived from the ~70 KB working limit reported from the
# field (tessera-cdc, 2026-09-25: a 622 KB prompt passed as ONE command-line
# argument to `claude -p`, timing out inside 600 s), rounded DOWN to a power of
# two. This is a conservative POLICY FLOOR, not a guarantee of process creation:
# real ARG_MAX varies (Linux 128 KB–2 MB, macOS 256 KB) and the environment
# block counts against it. Probing `getconf ARG_MAX` was considered and
# rejected — the usable limit is not ARG_MAX, and a probe would make the refusal
# boundary vary by machine, so a review that refuses in CI would pass locally.
REVIEW_MAX_ARGV_BYTES_DEFAULT=65536

# Every agent, every input mode. Derived from MEASUREMENT, not taste: the
# largest payload observed to complete successfully against both shipped CLIs is
# this spec's own round-3 review at 197,238 bytes, and 262144 is the next power
# of two above it. A payload beyond the largest one ever seen to work is refused
# rather than attempted.
#
# RAISE-ME PROTOCOL, because a spec only modestly longer than this one would
# refuse under it: do not raise this constant to make a round go through. Raise
# it only alongside a RECORDED observation of a larger payload completing
# against both shipped CLIs — and note that the `REVIEW_MAX_PAYLOAD_BYTES`
# environment override is the documented escape hatch for a one-off, which is
# why it is validated loudly rather than silently. Discovering the bound by
# tripping a refusal in CI is the outcome this comment exists to prevent.
REVIEW_MAX_PAYLOAD_BYTES_DEFAULT=262144

# The floor an override may not go below. Below this the value is definitionally
# a config bug rather than a policy choice — the compiled default is 64 KB.
REVIEW_MIN_LIMIT_BYTES=1024

# review_effective_limit <argv|payload> — echo the limit actually in force.
#
# The env override is the sanctioned one-shot escape hatch for an oversized
# round, so a malformed one must be LEGIBLE rather than silent: it warns on
# stderr naming the offending variable and proceeds with the compiled default.
# It never aborts the review — refusing to review because a limit was mistyped
# would trade one unhelpful failure for another.
review_effective_limit() {
  local which="${1:-}" var def raw present=0
  case "$which" in
    argv)
      var=REVIEW_MAX_ARGV_BYTES; def="$REVIEW_MAX_ARGV_BYTES_DEFAULT"
      [ -z "${REVIEW_MAX_ARGV_BYTES+x}" ] || { present=1; raw="$REVIEW_MAX_ARGV_BYTES"; }
      ;;
    payload)
      var=REVIEW_MAX_PAYLOAD_BYTES; def="$REVIEW_MAX_PAYLOAD_BYTES_DEFAULT"
      [ -z "${REVIEW_MAX_PAYLOAD_BYTES+x}" ] || { present=1; raw="$REVIEW_MAX_PAYLOAD_BYTES"; }
      ;;
    *) review_error "review_effective_limit: unknown limit '${which:-}' (want argv|payload)"; return 1 ;;
  esac
  [ "$present" -eq 1 ] || { printf '%s\n' "$def"; return 0; }
  local ok=1
  case "$raw" in
    ''|*[!0-9]*) ok=0 ;;
    *) [ "$raw" -ge "$REVIEW_MIN_LIMIT_BYTES" ] || ok=0 ;;
  esac
  [ "$ok" -eq 1 ] || {
    review_error "review: $var='$raw' is not a usable limit (want a base-10 integer >= $REVIEW_MIN_LIMIT_BYTES); using the compiled default $def"
    printf '%s\n' "$def"
    return 0
  }
  printf '%s\n' "$raw"
}

# review_budget_check <bytes> <input-mode> — echo "ok" or "refuse:<reason>" and
# exit 0 in BOTH cases: a refusal is data, not a shell failure.
#
# The mode matrix is taken from what aux-delegator actually does, not from
# assumption. `acp` is argv transport because aux-delegator invokes it as
# `acpx <agent> <prompt>` — normalizing it to stdin would have exempted the one
# mode most likely to overflow. Only an EMPTY/absent mode normalizes to stdin
# (a registry entry with no `input` key); an unrecognised mode is an error, so
# the next argv transport somebody adds cannot slip in exempt.
#
# `refuse:payload-limit` wins when both are exceeded, deterministically.
review_budget_check() {
  local bytes="${1:-}" mode="${2:-}" transport payload_limit argv_limit
  case "$bytes" in
    ''|*[!0-9]*) review_error "review_budget_check: bytes must be a base-10 integer (got '${bytes:-}')"; return 1 ;;
  esac
  case "$mode" in
    ''|stdin|file) transport=stream ;;
    argv|acp)      transport=argv ;;
    *) review_error "review_budget_check: unknown input mode '$mode' (known: argv, acp, stdin, file; empty normalizes to stdin)"; return 1 ;;
  esac
  payload_limit="$(review_effective_limit payload)"
  [ "$bytes" -le "$payload_limit" ] || { printf 'refuse:payload-limit\n'; return 0; }
  if [ "$transport" = argv ]; then
    argv_limit="$(review_effective_limit argv)"
    [ "$bytes" -le "$argv_limit" ] || { printf 'refuse:argv-limit\n'; return 0; }
  fi
  printf 'ok\n'
}

# review_rank_files <f…> — echo "<bytes>  <repo-relative path>" per file,
# largest first. The refusal names what is actually big, so the developer is not
# left to guess which file to compact.
review_rank_files() {
  local f
  for f in "$@"; do
    [ -e "$f" ] || continue
    printf '%s  %s\n' "$(LC_ALL=C wc -c < "$f" | tr -d ' ')" "$(_review_repo_relative "$f")"
  done | sort -rn
}

# review_refusal_message <agent> <mode> <bytes> <reason> <ranked-files>
# — the actionable refusal. Names the agent, its input mode, the measured bytes,
# the limit exceeded (from the RUNTIME effective value, so the diagnostic cannot
# disagree with the behavior when an override is in play), the oversized files,
# and a remedy SPECIFIC to the limit: stdin fixes an argv-limit refusal and does
# nothing at all for a payload-limit one.
review_refusal_message() {
  local agent="${1:-}" mode="${2:-}" bytes="${3:-}" reason="${4:-}" ranked="${5:-}"
  local mode_label="${mode:-stdin (no input key)}" argv_limit payload_limit line
  printf "review: REFUSING to dispatch '%s' — checked BEFORE the round runs, so this\n" "$agent"
  printf '  is a named refusal rather than a 600 s timeout with no explanation.\n'
  printf '  composed payload: %s bytes\n' "$bytes"
  printf '  input mode: %s\n' "$mode_label"
  case "$reason" in
    refuse:argv-limit)
      argv_limit="$(review_effective_limit argv)"
      printf '  over the ARGV limit of %s bytes (the whole prompt goes as ONE argument)\n' "$argv_limit"
      ;;
    refuse:payload-limit)
      payload_limit="$(review_effective_limit payload)"
      printf '  over the PAYLOAD limit of %s bytes (applies to every agent and every mode)\n' "$payload_limit"
      case "$mode" in
        argv|acp)
          argv_limit="$(review_effective_limit argv)"
          if [ "$bytes" -gt "$argv_limit" ]; then
            printf '  also over the ARGV limit of %s bytes — but that is not the binding\n' "$argv_limit"
            printf '  constraint here, and switching transport would not lift this refusal.\n'
          fi
          ;;
      esac
      ;;
    *) review_error "review_refusal_message: unknown reason '${reason:-}'"; return 1 ;;
  esac
  if [ -n "$ranked" ]; then
    printf '  largest inline files:\n'
    printf '%s\n' "$ranked" | while IFS= read -r line; do
      [ -n "$line" ] && printf '    %s\n' "$line"
    done
  fi
  case "$reason" in
    refuse:argv-limit)
      printf '  REMEDY: switch this agent to stdin in .speccraft/agents.toml:\n\n'
      printf '      input = "stdin"\n\n'
      printf '    stdin is not subject to the argv limit. Repos already initialized own\n'
      printf '    their .speccraft/agents.toml and are never rewritten, so the shipped\n'
      printf "    template's stdin default does not reach this repo on its own.\n"
      ;;
    refuse:payload-limit)
      printf '  REMEDY: compact the oversized memory files named above, or review a\n'
      printf '    shorter spec. Changing the input mode does NOT help — a stdin-mode agent is still refused above the payload limit.\n'
      printf '    For a legitimate one-off, REVIEW_MAX_PAYLOAD_BYTES is the sanctioned\n'
      printf '    escape hatch; raising the compiled default instead requires a recorded\n'
      printf '    observation of a larger payload completing against both shipped CLIs.\n'
      ;;
  esac
}

# ---------------------------------------------------------------------------
# Spec 0052 — the single composer.
# ---------------------------------------------------------------------------

# _review_each_path <newline-separated-list> — emit the non-empty entries.
_review_each_path() {
  printf '%s' "$1" | while IFS= read -r p; do
    [ -n "$p" ] && printf '%s\n' "$p"
  done
  return 0
}

# review_compose_payload <template> <spec-src>
#     --inline <f…> --reference <f…> --digest-out <path>
#     [--diff <diff>] [--changed <sections>]
# — emit the composed reviewer payload on STDOUT.
#
# This is the SOLE composer for both the full round and the spec-0035 scoped
# `--diff` round, which is why the template substitution and the evidence
# attachment live here: one place decides what bytes are sent, so the budget
# measures the bytes that are dispatched rather than a close-enough approximation.
#
# It writes NO payload file. The command driver redirects this stream once into
# the round's single mode-0600 artifact (AC10) — redirected, never captured into
# a variable, because command substitution strips trailing newlines and would
# make measured and dispatched bytes differ silently. The `--digest-out` sidecar
# is the one other thing it writes, and it never enters the payload (AC6): if
# the reviewer could see the expected digest it could echo it without opening
# the file, which is the read-sentinel theatre review round 3 killed.
#
# Path policy, per tier:
#   --reference  must classify as reference-tier and must EXIST. A named-but-
#                missing file is an error, never a quietly smaller payload.
#   --inline     must not classify as reference-tier (AC2) and must exist. A
#                path outside the tier table is permitted here — that is how the
#                prior review.md rides along as scoped-round evidence — and a
#                typo cannot hide in that allowance, because it will not exist.
review_compose_payload() {
  local template="${1:-}" spec_src="${2:-}"
  [ -n "$template" ] && [ -f "$template" ] || {
    review_error "review_compose_payload: template not found: '${template:-}'"; return 1; }
  [ -n "$spec_src" ] && [ -f "$spec_src" ] || {
    review_error "review_compose_payload: spec source not found: '${spec_src:-}'"; return 1; }
  shift 2

  local mode="" digest_out="" diff="" changed=""
  local inline_set="" reference_set="" nl=$'\n'
  while [ $# -gt 0 ]; do
    case "$1" in
      --inline)     mode=inline ;;
      --reference)  mode=reference ;;
      --digest-out) digest_out="${2:-}"; shift; mode="" ;;
      --diff)       diff="${2:-}"; shift; mode="" ;;
      --changed)    changed="${2:-}"; shift; mode="" ;;
      --*) review_error "review_compose_payload: unknown option '$1'"; return 1 ;;
      *)
        case "$mode" in
          inline)    inline_set="${inline_set}${1}${nl}" ;;
          reference) reference_set="${reference_set}${1}${nl}" ;;
          *) review_error "review_compose_payload: unexpected argument '$1' (expected --inline/--reference first)"; return 1 ;;
        esac
        ;;
    esac
    shift
  done
  [ -n "$digest_out" ] || {
    review_error "review_compose_payload: --digest-out <path> is required (the digests must travel OUTSIDE the payload)"
    return 1
  }

  # Validate EVERY path before reading any of them, so a failure late in the
  # reference set cannot leave a half-written digest sidecar behind.
  local p tier rc
  while IFS= read -r p; do
    rc=0; tier="$(review_context_tier "$p" 2>/dev/null)" || rc=$?
    if [ "$rc" -eq 0 ] && [ "$tier" = "reference" ]; then
      review_error "review_compose_payload: '$p' is a reference-tier file and must not be pasted inline"
      return 1
    fi
    [ -e "$p" ] || { review_error "review_compose_payload: inline file not found: '$p'"; return 1; }
  done < <(_review_each_path "$inline_set")
  while IFS= read -r p; do
    rc=0; tier="$(review_context_tier "$p" 2>/dev/null)" || rc=$?
    [ "$rc" -eq 0 ] && [ "$tier" = "reference" ] || {
      review_error "review_compose_payload: '$p' is not a reference-tier file"; return 1; }
    [ -e "$p" ] || { review_error "review_compose_payload: reference file not found: '$p'"; return 1; }
  done < <(_review_each_path "$reference_set")

  : > "$digest_out"

  # 1. the template, with the scoped-round markers substituted. Unset values
  #    substitute to EMPTY rather than surviving: a payload carrying a literal
  #    {{DIFF}} would be a reviewer-visible bug.
  local line
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      '{{DIFF}}')             printf '%s\n' "$diff" ;;
      '{{CHANGED_SECTIONS}}') printf '%s\n' "$changed" ;;
      *)                      printf '%s\n' "$line" ;;
    esac
  done < "$template"

  # 2. the spec under review, from the round's frozen image. The composer never
  #    names spec.md — it reads only the path it is given (AC16).
  printf '\n## Spec under review (frozen for this round)\n\n'
  cat -- "$spec_src"

  # 3. each inline file, in full, under its repo-relative path.
  while IFS= read -r p; do
    printf '\n## File: %s\n\n' "$(_review_repo_relative "$p")"
    cat -- "$p"
  done < <(_review_each_path "$inline_set")

  # 4. the reference records: path, byte size and heading index — never a body.
  printf '\n## Reference files (read these yourself)\n\n'
  if [ -z "$reference_set" ]; then
    # Emitted, never omitted: a reviewer must be able to tell "none were sent"
    # from "the section was dropped by a bug" (AC7).
    printf '(none) — no reference-tier files were sent this round.\n'
    return 0
  fi
  printf 'These files are NOT pasted. Open each path below with your own tools,\n'
  printf 'read what you need, and return its sha256 in `reference_access`. Report\n'
  printf 'any you could not read in `reference_access_failures` — a verdict given\n'
  printf 'without a matching digest for every path does not count.\n\n'
  local rec first heads size digest rel
  while IFS= read -r p; do
    rec="$(_review_scan_reference "$p")" || return 1
    first="${rec%%$nl*}"
    heads=""
    case "$rec" in *"$nl"*) heads="${rec#*$nl}" ;; esac
    size="${first%% *}"
    digest="${first#* }"
    rel="$(_review_repo_relative "$p")"
    printf '%s  %s\n' "$digest" "$rel" >> "$digest_out"
    printf -- '- path: %s\n' "$rel"
    printf '  bytes: %s\n' "$size"
    printf '  headings:\n'
    if [ -n "$heads" ]; then
      printf '%s\n' "$heads" | while IFS= read -r line; do printf '    %s\n' "$line"; done
    else
      printf '    (no ## or ### headings)\n'
    fi
    printf '\n'
  done < <(_review_each_path "$reference_set")
  return 0
}

# review_reviewed_sha256 <review.md> — echo the single usable reviewed_sha256
# value, or return non-zero. "Usable" (spec 0035 AC8) = exactly one line matching
# the anchored grammar ^reviewed_sha256: <64 lowercase hex>$. Zero, multiple, or
# malformed such lines → not usable.
review_reviewed_sha256() {
  local file="$1"
  [ -f "$file" ] || return 1
  local matches count
  matches="$(grep -E '^reviewed_sha256: [0-9a-f]{64}$' "$file" 2>/dev/null || true)"
  [ -n "$matches" ] || return 1
  count="$(printf '%s\n' "$matches" | grep -c .)"
  [ "$count" = "1" ] || return 1
  printf '%s\n' "${matches#reviewed_sha256: }"
}

# review_classify <snapshot> <changed> <base_fingerprint> <prior_reviewed_sha256>
# — echo the UX branch per the spec 0035 Provenance gate:
#   full-review   : first review (snapshot=false), OR the prior review.md is
#                   unusable / its fingerprint != base_fingerprint (baseline not
#                   the last-reviewed version — includes the failed-promote case).
#   short-circuit : baseline is the reviewed version AND nothing changed.
#   scoped        : baseline is the reviewed version AND the spec changed.
# The caller passes an empty prior_reviewed_sha256 when review.md is unusable.
review_classify() {
  local snapshot="$1" changed="$2" base="$3" prior="$4"
  if [ "$snapshot" != "true" ]; then
    printf 'full-review\n'
    return 0
  fi
  if [ -z "$prior" ] || [ "$prior" != "$base" ]; then
    printf 'full-review\n'
    return 0
  fi
  if [ "$changed" = "true" ]; then
    printf 'scoped\n'
  else
    printf 'short-circuit\n'
  fi
}

# review_build_payload <template> <frozen_spec> <prior_review_file> <diff>
#   <changed_sections>
# — echo the scoped re-review payload (spec 0035 AC7b): the populated re-review
# brief (template with the {{DIFF}} / {{CHANGED_SECTIONS}} markers substituted),
# followed by the CURRENT spec content read from the round's FROZEN spec image
# (NOT spec.md — preserving the AC11 single-read transaction) and the prior
# review.md body as regression-context evidence.
#
# The frozen image used to be review-snapshot.md, promoted at the start of the
# round; spec 0052 AC24 defers that promote to the end, so the caller passes the
# round's own frozen copy instead. This helper never names either file — it
# reads only the path it is given.
review_build_payload() {
  local template="$1" snapshot="$2" prior="$3" diff="$4" sections="$5"
  local line
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      '{{DIFF}}') printf '%s\n' "$diff" ;;
      '{{CHANGED_SECTIONS}}') printf '%s\n' "$sections" ;;
      *) printf '%s\n' "$line" ;;
    esac
  done < "$template"
  printf '\n===== CURRENT SPEC (frozen round image) =====\n'
  cat "$snapshot"
  printf '\n===== PRIOR REVIEW (settled vs. open) =====\n'
  cat "$prior"
}
