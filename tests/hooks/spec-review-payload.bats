#!/usr/bin/env bats
# Spec 0052 — bound the /speccraft:spec:review reviewer payload.
#
# Covers the tier table (AC1), the heading extractor and its fence grammar
# (AC3/AC4), and the awk-interval portability arm (AC5). Later tasks extend
# this file with the composer, budget, dispatch and attestation criteria.
#
# Shape follows tests/hooks/spec-review-diff.bats (same lib under test):
# PLUGIN_DIR is resolved from BATS_TEST_FILENAME, and ./bin goes FIRST on PATH
# so the repo's own speccraft-state answers find-root — a stale cached plugin
# would otherwise resolve a different root and the tier tests would lie.
#
# Every expected value here is pinned against a CURATED FIXTURE, never against a
# heading count of a live .speccraft/ file: an unrelated spec:close must not be
# able to red this suite (AC3, and conventions.md §"structural over content").

setup() {
  PLUGIN_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  LIB="$PLUGIN_DIR/commands/spec/review.lib.sh"
  FIX="$PLUGIN_DIR/tests/hooks/fixtures/spec-review-payload"
  export PATH="$PLUGIN_DIR/bin:$PATH"
  TEST_DIR="$(mktemp -d)"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# Assert a helper failed for ITS OWN reason, not on a bare "command not found"
# that a typo would also satisfy. Used for every first-touch of a new helper.
assert_named_failure() {
  local pattern="$1"
  [ "$status" -ne 0 ] || {
    echo "expected non-zero exit, got 0; output: $output" >&2
    return 1
  }
  printf '%s\n' "$output" | grep -qF -- "$pattern" || {
    echo "expected output to name '$pattern'; got: $output" >&2
    return 1
  }
}

# ---- AC1: tier classification -------------------------------------------

@test "review_context_tier classifies guardrails.md and index.md as inline" {
  source "$LIB"
  run review_context_tier ".speccraft/guardrails.md"
  [ "$status" -eq 0 ]
  [ "$output" = "inline" ]
  run review_context_tier ".speccraft/index.md"
  [ "$status" -eq 0 ]
  [ "$output" = "inline" ]
}

@test "review_context_tier classifies architecture.md and conventions.md as reference" {
  source "$LIB"
  run review_context_tier ".speccraft/architecture.md"
  [ "$status" -eq 0 ]
  [ "$output" = "reference" ]
  run review_context_tier ".speccraft/conventions.md"
  [ "$status" -eq 0 ]
  [ "$output" = "reference" ]
}

@test "review_context_tier errors on history.md — this spec does not add it to the payload" {
  source "$LIB"
  run review_context_tier ".speccraft/history.md"
  assert_named_failure "history.md"
}

@test "review_context_tier matches the repo-relative path, not the basename" {
  source "$LIB"
  # A vendored .speccraft/ and a spec document that merely SHARES the basename
  # must both be errors. Matching on the trailing basename would classify both
  # as reference and silently admit a foreign file to the payload.
  run review_context_tier "vendor/other/.speccraft/conventions.md"
  assert_named_failure "vendor/other/.speccraft/conventions.md"
  run review_context_tier "specs/0052-x/conventions.md"
  assert_named_failure "specs/0052-x/conventions.md"
}

@test "review_context_tier is path-shape invariant across absolute, ./-prefixed and bare" {
  source "$LIB"
  local expected="reference"
  run review_context_tier "$PLUGIN_DIR/.speccraft/conventions.md"
  [ "$output" = "$expected" ]
  run review_context_tier "./.speccraft/conventions.md"
  [ "$output" = "$expected" ]
  run review_context_tier ".speccraft/conventions.md"
  [ "$output" = "$expected" ]
}

# ---- AC3: heading extraction shape, pinned to curated fixtures -----------

@test "review_heading_index emits nothing and exits 0 for a file with no headings" {
  source "$LIB"
  run review_heading_index "$FIX/headings/h01-none.md"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "review_heading_index emits ## headings and excludes the h1" {
  source "$LIB"
  run review_heading_index "$FIX/headings/h02-h2-only.md"
  [ "$status" -eq 0 ]
  [ "$output" = "## Alpha
## Beta" ]
}

@test "review_heading_index emits ### headings" {
  source "$LIB"
  run review_heading_index "$FIX/headings/h03-h3-only.md"
  [ "$output" = "### One
### Two" ]
}

@test "review_heading_index excludes #### and deeper" {
  source "$LIB"
  run review_heading_index "$FIX/headings/h04-h4-excluded.md"
  [ "$output" = "## Keep
### Keep too" ]
}

@test "review_heading_index preserves a code span in a heading" {
  source "$LIB"
  run review_heading_index "$FIX/headings/h05-code-span.md"
  [ "$output" = '## A `code span` here' ]
}

@test "review_heading_index preserves non-ASCII in a heading" {
  source "$LIB"
  run review_heading_index "$FIX/headings/h06-non-ascii.md"
  [ "$output" = "## Ünïcödé — héading" ]
}

@test "review_heading_index strips the trailing CR on a CRLF file" {
  source "$LIB"
  run review_heading_index "$FIX/headings/h07-crlf.md"
  # A surviving \r would make the record differ byte-wise between a CRLF and an
  # LF checkout of the same memory file.
  printf '%s' "$output" | grep -q $'\r' && {
    echo "output still carries a CR: $(printf '%s' "$output" | cat -A)" >&2
    return 1
  }
  [ "$output" = "## CR One
### CR Two" ]
}

# ---- AC4: fence grammar --------------------------------------------------

@test "review_heading_index ignores headings inside a backtick fence" {
  source "$LIB"
  run review_heading_index "$FIX/fences/f01-backtick.md"
  [ "$output" = "## Real One
## Real Two" ]
}

@test "review_heading_index ignores headings inside a tilde fence" {
  source "$LIB"
  run review_heading_index "$FIX/fences/f02-tilde.md"
  [ "$output" = "## Real One
## Real Two" ]
}

@test "review_heading_index does not close a 4-char fence on a 3-char line" {
  source "$LIB"
  run review_heading_index "$FIX/fences/f03-four-char-fence.md"
  # "### Still inside" sits after a 3-backtick line but INSIDE a 4-backtick
  # fence. A length-blind close would emit it.
  [ "$output" = "## Real One
## Real Two" ]
}

@test "review_heading_index ignores headings inside a fence with an info string" {
  source "$LIB"
  run review_heading_index "$FIX/fences/f04-info-string.md"
  [ "$output" = "## Real One
## Real Two" ]
}

@test "review_heading_index ignores headings inside an indented fence" {
  source "$LIB"
  run review_heading_index "$FIX/fences/f05-indented-fence.md"
  [ "$output" = "## Real One
## Real Two" ]
}

@test "review_heading_index suppresses headings to EOF on an unclosed fence" {
  source "$LIB"
  run review_heading_index "$FIX/fences/f06-unclosed-fence.md"
  [ "$output" = "## Real One" ]
}

# ---- AC5: the behavioural arm of the interval guard ----------------------

@test "the environment's awk silently matches nothing for a {n,m} interval" {
  # This is the PREMISE of AC5, asserted rather than assumed. mawk does not
  # implement interval expressions and reports no error; if this machine's awk
  # ever gains them, the behavioural arm below stops being load-bearing and
  # this test tells us so.
  run bash -c "printf '## a\n### b\n' | awk '/^#{2,3} /{print}'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "review_heading_index emits a NON-EMPTY index under the environment's own awk" {
  source "$LIB"
  # The arm that bites: an extractor written with /^#{2,3} / passes a source
  # scan and emits ZERO headings here. Only running it proves otherwise.
  run review_heading_index "$FIX/headings/h02-h2-only.md"
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

# ---- AC22/AC23/AC24: round predicates, inert round, deferred promote ------
#
# The round's outcome set is a file of `<agent> <outcome> [detail…]` records,
# one per REQUIRED reviewer. `responses_complete` and `approval_quorum_met` are
# separate predicates over that file because they gate different things: the
# first gates synthesis and the durable writes (and holds for ANY verdict,
# including changes-requested — spec 0035 AC2), the second alone gates
# `status: reviewed`. Conflating them would forbid exactly what a legitimate
# changes-requested round does.

# A speccraft-state stub that RECORDS every invocation. The inert-round
# assertions are made HERE, at the seam, not inferred from unchanged bytes: a
# round that wrote the same bytes back would also leave the file "unchanged".
install_state_stub() {
  mkdir -p "$TEST_DIR/stub"
  cat > "$TEST_DIR/stub/speccraft-state" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$SEAM_LOG"
case "$1" in
  find-root)       printf '%s\n' "$STUB_ROOT" ;;
  review-snapshot) printf '%s\n' "1111111111111111111111111111111111111111111111111111111111111111" ;;
esac
exit 0
STUB
  chmod +x "$TEST_DIR/stub/speccraft-state"
  export SEAM_LOG="$TEST_DIR/seam.log"
  export STUB_ROOT="$TEST_DIR"
  : > "$SEAM_LOG"
  export PATH="$TEST_DIR/stub:$PATH"
}

# A real spec dir, so the durable-write arms run against the REAL binary and a
# call that slipped through the gate would actually move bytes on disk.
make_spec_dir() {
  SPEC_DIR="$TEST_DIR/specs/0001-x"
  mkdir -p "$SPEC_DIR"
  printf '# Spec\n\nCURRENT-SPEC-MARKER\n' > "$SPEC_DIR/spec.md"
  printf '# Spec\n\nBASELINE-SNAPSHOT-MARKER\n' > "$SPEC_DIR/review-snapshot.md"
  printf '# Review\n\nPRIOR-REVIEW-MARKER\n' > "$SPEC_DIR/review.md"
}

outcomes() {
  local f="$TEST_DIR/outcomes.txt"
  printf '%s\n' "$@" > "$f"
  printf '%s\n' "$f"
}

@test "review_responses_complete is false when any required reviewer refused" {
  source "$LIB"
  run review_responses_complete "$(outcomes 'codex approve' 'claude-p refused refuse:argv-limit')"
  [ "$status" -eq 1 ]
}

@test "review_responses_complete is true for two changes-requested verdicts" {
  source "$LIB"
  # A timeout is not a verdict (spec 0035); a changes-requested IS one.
  run review_responses_complete "$(outcomes 'codex changes-requested' 'claude-p changes-requested')"
  [ "$status" -eq 0 ]
}

@test "review_responses_complete treats timeout, failure and a failed attestation as non-verdicts" {
  source "$LIB"
  run review_responses_complete "$(outcomes 'codex timeout')";            [ "$status" -eq 1 ]
  run review_responses_complete "$(outcomes 'codex failed')";             [ "$status" -eq 1 ]
  run review_responses_complete "$(outcomes 'codex attestation-failed')"; [ "$status" -eq 1 ]
}

@test "review_responses_complete is false for an empty outcome set" {
  source "$LIB"
  # Zero reviewers is not "everyone answered" — it is a round that never ran.
  run review_responses_complete "$(outcomes)"
  [ "$status" -eq 1 ]
}

@test "review_responses_complete names an unknown outcome token instead of silently not counting it" {
  source "$LIB"
  # Exit 2, distinct from the exit-1 "incomplete" answer: a typo'd outcome must
  # not be indistinguishable from a legitimate refusal.
  run review_responses_complete "$(outcomes 'codex approvd')"
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | grep -qF "approvd"
}

@test "review_approval_quorum_met counts only approve and approve-with-comments" {
  source "$LIB"
  run review_approval_quorum_met 2 "$(outcomes 'codex approve' 'claude-p approve-with-comments')"
  [ "$status" -eq 0 ]
  run review_approval_quorum_met 2 "$(outcomes 'codex approve' 'claude-p changes-requested')"
  [ "$status" -eq 1 ]
  run review_approval_quorum_met 1 "$(outcomes 'codex reject' 'claude-p changes-requested')"
  [ "$status" -eq 1 ]
}

@test "a complete changes-requested round writes review.md, stamps the fingerprint, and leaves status draft" {
  source "$LIB"
  make_spec_dir
  run review_finalize_round "$SPEC_DIR" 1 "$(outcomes 'codex changes-requested' 'claude-p changes-requested')"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qxF "responses_complete: true"
  printf '%s\n' "$output" | grep -qxF "approval_quorum_met: false"
  printf '%s\n' "$output" | grep -qxF "status: draft"
  # Spec 0035 AC2 preserved: the durable write happens for ANY verdict.
  grep -qE '^reviewed_sha256: [0-9a-f]{64}$' "$SPEC_DIR/review.md"
  # …and the snapshot is promoted HERE, at the end of the round, not at its start.
  grep -qF 'CURRENT-SPEC-MARKER' "$SPEC_DIR/review-snapshot.md"
}

@test "a complete round meeting quorum reports status reviewed" {
  source "$LIB"
  make_spec_dir
  run review_finalize_round "$SPEC_DIR" 1 "$(outcomes 'codex approve' 'claude-p changes-requested')"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qxF "responses_complete: true"
  printf '%s\n' "$output" | grep -qxF "approval_quorum_met: true"
  printf '%s\n' "$output" | grep -qxF "status: reviewed"
}

@test "an all-refused round invokes neither review-snapshot write nor review-commit at the seam" {
  source "$LIB"
  install_state_stub
  make_spec_dir
  run review_finalize_round "$SPEC_DIR" 1 "$(outcomes 'codex refused refuse:argv-limit' 'claude-p refused refuse:payload-limit')"
  [ "$status" -eq 0 ]
  run grep -c 'review-snapshot' "$SEAM_LOG"
  [ "$output" = "0" ]
  run grep -c 'review-commit' "$SEAM_LOG"
  [ "$output" = "0" ]
}

@test "an all-refused round leaves review.md and review-snapshot.md byte-identical" {
  source "$LIB"
  make_spec_dir   # REAL speccraft-state on PATH: a call that slipped the gate moves bytes
  before_review="$(cat "$SPEC_DIR/review.md")"
  before_snap="$(cat "$SPEC_DIR/review-snapshot.md")"
  run review_finalize_round "$SPEC_DIR" 1 "$(outcomes 'codex refused refuse:argv-limit' 'claude-p timeout')"
  [ "$status" -eq 0 ]
  [ "$(cat "$SPEC_DIR/review.md")" = "$before_review" ]
  [ "$(cat "$SPEC_DIR/review-snapshot.md")" = "$before_snap" ]
  # The baseline the NEXT --diff anchors on is untouched, so the following round
  # is classified against the same reviewed version rather than a silent re-baseline.
  grep -qF 'BASELINE-SNAPSHOT-MARKER' "$SPEC_DIR/review-snapshot.md"
}

@test "an all-refused round reports synthesis skipped, so cross-reviewer is never invoked" {
  source "$LIB"
  make_spec_dir
  run review_finalize_round "$SPEC_DIR" 1 "$(outcomes 'codex refused refuse:argv-limit')"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qxF "synthesis: skipped"
  printf '%s\n' "$output" | grep -qxF "responses_complete: false"
}

@test "a mixed round is inert and names both the refusal and the verdict obtained" {
  source "$LIB"
  make_spec_dir
  run review_finalize_round "$SPEC_DIR" 1 "$(outcomes 'codex refused refuse:argv-limit' 'claude-p approve')"
  [ "$status" -eq 0 ]
  # The two predicates are separately observable and DISAGREE here: an approval
  # was obtained, yet the round is inert because a required reviewer never answered.
  printf '%s\n' "$output" | grep -qxF "responses_complete: false"
  printf '%s\n' "$output" | grep -qxF "approval_quorum_met: true"
  printf '%s\n' "$output" | grep -qxF "status: draft"
  # The report names every refusal AND every verdict obtained — a round that
  # reported only the failure would hide a real verdict from the developer.
  printf '%s\n' "$output" | grep -qF "no-verdict: codex refused refuse:argv-limit"
  printf '%s\n' "$output" | grep -qF "verdict: claude-p approve"
  [ "$(cat "$SPEC_DIR/review.md")" = "$(printf '# Review\n\nPRIOR-REVIEW-MARKER\n')" ]
}

@test "a failed attestation is reported in its own category" {
  source "$LIB"
  make_spec_dir
  run review_finalize_round "$SPEC_DIR" 1 "$(outcomes 'codex attestation-failed digest-mismatch')"
  [ "$status" -eq 0 ]
  # AC25: a chronically failing reviewer must be diagnosable, not merely excluded.
  printf '%s\n' "$output" | grep -qF "attestation-failure: codex digest-mismatch"
}

# runbook_promote_free — a NAMED predicate, run twice: against the real runbook
# (must pass) and against the committed forbidden fixture (must reject). Exit 2
# for "no review-diff call at all" so that deleting the call cannot be mistaken
# for compliance — the failure mode a bare `! grep -q --promote` would accept.
runbook_promote_free() {
  local f="$1" hits
  grep -qF 'speccraft-state review-diff' "$f" || {
    echo "no 'speccraft-state review-diff' call found in $f"
    return 2
  }
  hits="$(grep -nE 'review-diff.*--promote' "$f" || true)"
  [ -z "$hits" ] || { echo "forbidden --promote at round start: $hits"; return 1; }
  return 0
}

@test "the round's opening review-diff call carries no --promote" {
  run runbook_promote_free "$PLUGIN_DIR/commands/spec/review.md"
  [ "$status" -eq 0 ]
}

@test "the promote-free checker REJECTS the committed forbidden runbook fixture" {
  run runbook_promote_free "$FIX/forbidden/fb05-runbook-promote.md"
  [ "$status" -eq 1 ]
}

@test "the promote-free checker distinguishes a deleted call from a compliant one" {
  printf '# Runbook with no review-diff call at all\n' > "$TEST_DIR/no-call.md"
  run runbook_promote_free "$TEST_DIR/no-call.md"
  [ "$status" -eq 2 ]
}
