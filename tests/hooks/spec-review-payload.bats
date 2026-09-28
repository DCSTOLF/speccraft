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
  # Derived paths belong HERE, not at file scope: a top-level `RESP="$FIX/…"`
  # would expand before setup() runs and silently resolve to "/responses".
  RESP="$FIX/responses"
  EXPECTED_DIGESTS="$RESP/expected-digests.txt"
  export PATH="$PLUGIN_DIR/bin:$PATH"
  TEST_DIR="$(mktemp -d)"
}

teardown() {
  # A single-use-source writer blocked in open() outlives the test otherwise
  # (see the AC8 proof below); the FIFO it waits on is about to be removed.
  [ -z "${FIFO_WRITER_PID:-}" ] || kill "$FIFO_WRITER_PID" 2>/dev/null || true
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

# ---- AC9: one digest primitive, resolved once, pinned on BOTH polarities --
#
# `sha256sum` is GNU coreutils only and absent from a default macOS userland;
# `shasum -a 256` is present on both. This repo lost eight consecutive CI runs
# to exactly this BSD/GNU class (spec 0050), so the primitive is pinned in both
# directions rather than assumed — and the awk-interval trap guarded beside it
# is the same class of silent cross-environment divergence.

# make_digest_tool <dir> <name> <hex> — a stand-in checksum tool emitting the
# standard "<hex>  <name>" two-column form, so the caller's field extraction is
# exercised rather than bypassed. /bin/sh with builtins only: these run on a
# PATH that contains nothing but the stub dir.
make_digest_tool() {
  local dir="$1" name="$2" hex="$3"
  mkdir -p "$dir"
  cat > "$dir/$name" <<EOS
#!/bin/sh
printf '%s  -\n' "$hex"
EOS
  chmod +x "$dir/$name"
}

BSD_HEX="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
GNU_HEX="9999999999999999999999999999999999999999999999999999999999999999"

@test "review_digest resolves shasum -a 256 when the GNU tool is absent from PATH" {
  source "$LIB"
  make_digest_tool "$TEST_DIR/bsd" shasum "$BSD_HEX"
  # PATH is the stub dir ALONE: the real /usr/bin tools cannot be reached, so a
  # resolution that fell through to them would be visible here.
  PATH="$TEST_DIR/bsd" run review_digest "$FIX/digest/d01-known-vector.txt"
  [ "$status" -eq 0 ]
  [ "$output" = "$BSD_HEX" ]
}

@test "review_digest resolves the GNU tool when shasum is absent from PATH" {
  source "$LIB"
  make_digest_tool "$TEST_DIR/gnu" sha256sum "$GNU_HEX"
  PATH="$TEST_DIR/gnu" run review_digest "$FIX/digest/d01-known-vector.txt"
  [ "$status" -eq 0 ]
  [ "$output" = "$GNU_HEX" ]
}

@test "review_digest errors with a named message when neither primitive exists" {
  source "$LIB"
  mkdir -p "$TEST_DIR/empty"
  PATH="$TEST_DIR/empty" run review_digest "$FIX/digest/d01-known-vector.txt"
  assert_named_failure "shasum -a 256"
}

@test "review_digest matches a known vector and emits bare lowercase hex" {
  source "$LIB"
  # Against the REAL primitive on the ordinary PATH, so the stubs above cannot
  # be the only thing the contract is pinned to.
  run review_digest "$FIX/digest/d01-known-vector.txt"
  [ "$status" -eq 0 ]
  [ "$output" = "596bcab1b9feaa19b8c5c49b11d4a6c41509fb5f1586eed5bafc1b0dc61a15ef" ]
}

@test "review_digest reads stdin when given no file" {
  source "$LIB"
  run bash -c "source '$LIB'; review_digest < '$FIX/digest/d01-known-vector.txt'"
  [ "$output" = "596bcab1b9feaa19b8c5c49b11d4a6c41509fb5f1586eed5bafc1b0dc61a15ef" ]
}

# ---- AC8: ONE read per reference file, proved behaviorally ----------------
#
# A source scan is not sufficient evidence — the naive two-pass shape
# (`wc -c "$f"` then `grep '^## ' "$f"`) reads the path TWICE and looks
# perfectly reasonable. Against a single-use source it produces a record whose
# size and heading index disagree, which is what the two tests below contrast.

REF_CONTENT='# Title

## Alpha

body text

### Beta
'

# A single-use source: content on the first read, empty on the next few, so a
# second pass is observable rather than merely suspected. The extra empty opens
# exist so a two-pass consumer FAILS instead of blocking forever in open().
start_single_use_source() {
  local fifo="$1"
  mkfifo "$fifo"
  ( printf '%s' "$REF_CONTENT" > "$fifo"; for _ in 1 2 3; do : > "$fifo"; done ) &
  FIFO_WRITER_PID=$!
}

@test "the single-use-source proof requires mkfifo — gated at the suite, never skipped at runtime" {
  # A runtime `skip` would let the one-scan proof erode silently on any host
  # where the technique is unavailable. Assert the premise instead.
  run command -v mkfifo
  [ "$status" -eq 0 ]
}

@test "the reference record for a single-use source carries a non-empty heading index AND a matching digest" {
  source "$LIB"
  mkdir -p "$TEST_DIR/.speccraft"
  fifo="$TEST_DIR/.speccraft/conventions.md"
  printf '%s' "$REF_CONTENT" > "$TEST_DIR/plain.md"   # a freely re-readable twin
  expected_digest="$(review_digest "$TEST_DIR/plain.md")"
  expected_size="$(wc -c < "$TEST_DIR/plain.md" | tr -d ' ')"

  start_single_use_source "$fifo"
  run _review_scan_reference "$fifo"
  [ "$status" -eq 0 ]
  # Line 1 is "<byte-size> <sha256>", the rest is the heading index in file order.
  [ "$(printf '%s\n' "$output" | head -1)" = "$expected_size $expected_digest" ]
  [ "$(printf '%s\n' "$output" | tail -n +2)" = "## Alpha
### Beta" ]
}

@test "the naive two-pass shape disagrees with itself on the same single-use source" {
  # The BITE proof. This is the implementation AC8 forbids, run against the same
  # fixture: the size comes from the first read and the index from the second,
  # which is empty. Without this arm, the test above would pass just as happily
  # on a two-pass implementation given an ordinary file.
  mkdir -p "$TEST_DIR/.speccraft"
  fifo="$TEST_DIR/.speccraft/conventions.md"
  start_single_use_source "$fifo"
  two_pass_size="$(wc -c < "$fifo" | tr -d ' ')"
  two_pass_index="$(grep -E '^## |^### ' "$fifo" || true)"
  [ "$two_pass_size" -gt 0 ]
  [ -z "$two_pass_index" ]
}

# ---- AC2/AC6/AC7/AC13/AC15/AC16: the composer envelope -------------------
#
# One compound envelope per clause rather than one test per sentence: the
# composer is a single seam, and atomizing it inflates the task count without
# adding coverage (spec 0048's technique, and this spec's planning notes).

# A synthetic repo whose root find-root will resolve, so tier classification
# runs against real repo-relative paths instead of a stubbed answer.
make_corpus() {
  mkdir -p "$TEST_DIR/.speccraft" "$TEST_DIR/round" "$TEST_DIR/specs/0001-x"
  printf '# Guardrails\n\nGUARDRAILS-BODY\n'  > "$TEST_DIR/.speccraft/guardrails.md"
  printf '# Index\n\nINDEX-BODY\n'            > "$TEST_DIR/.speccraft/index.md"
  # The reference bodies carry a marker the heading grammar CANNOT emit, so
  # "the body did not leak" is decidable rather than eyeballed.
  printf '# Arch\n\n## Arch One\n\nSPECCRAFT-REF-BODY-MUST-NOT-APPEAR\n\n### Arch Two\n' \
    > "$TEST_DIR/.speccraft/architecture.md"
  printf '# Conv\n\n## Conv One\n\nSPECCRAFT-REF-BODY-MUST-NOT-APPEAR\n' \
    > "$TEST_DIR/.speccraft/conventions.md"
  printf '# Spec\n\nFROZEN-SPEC-BODY\n'       > "$TEST_DIR/round/spec-frozen.md"
  # The live spec.md differs from the frozen image: AC16 is decidable only if
  # the two sources carry different markers.
  printf '# Spec\n\nLIVE-SPEC-MUST-NOT-APPEAR\n' > "$TEST_DIR/specs/0001-x/spec.md"
  printf 'TEMPLATE-HEAD\n\nDiff:\n{{DIFF}}\n\nSections:\n{{CHANGED_SECTIONS}}\n' \
    > "$TEST_DIR/template.md"
  cd "$TEST_DIR"
}

compose_default() {
  review_compose_payload "$TEST_DIR/template.md" round/spec-frozen.md \
    --inline .speccraft/guardrails.md .speccraft/index.md \
    --reference .speccraft/architecture.md .speccraft/conventions.md \
    --digest-out "$TEST_DIR/digests.txt"
}

# first_index <text> <fixed-string> — 1-based line number of the first match, or
# 0. The order assertions compare FOUND INDICES, never absolute line numbers, so
# a legitimate change to the surrounding prose cannot break them.
first_index() {
  printf '%s\n' "$1" | grep -nF -- "$2" | head -1 | cut -d: -f1
}

@test "review_compose_payload rejects a reference-tier file passed in the inline position" {
  source "$LIB"; make_corpus
  # The payload bound must not depend on every caller remembering the policy.
  run review_compose_payload "$TEST_DIR/template.md" round/spec-frozen.md \
    --inline .speccraft/guardrails.md .speccraft/conventions.md \
    --reference .speccraft/architecture.md \
    --digest-out "$TEST_DIR/digests.txt"
  assert_named_failure ".speccraft/conventions.md"
}

@test "the composed payload orders template, then each inline file under ## File:, then the reference section" {
  source "$LIB"; make_corpus
  run compose_default
  [ "$status" -eq 0 ]
  local t g i r
  t="$(first_index "$output" 'TEMPLATE-HEAD')"
  g="$(first_index "$output" '## File: .speccraft/guardrails.md')"
  i="$(first_index "$output" '## File: .speccraft/index.md')"
  r="$(first_index "$output" '## Reference files')"
  [ "$t" -gt 0 ] && [ "$g" -gt "$t" ] && [ "$i" -gt "$g" ] && [ "$r" -gt "$i" ]
  # Inline files are pasted in FULL — the tier split bounds the reference half only.
  printf '%s\n' "$output" | grep -qF 'GUARDRAILS-BODY'
  printf '%s\n' "$output" | grep -qF 'INDEX-BODY'
  # …and each reference record carries path, byte size and heading index.
  printf '%s\n' "$output" | grep -qF '.speccraft/architecture.md'
  printf '%s\n' "$output" | grep -qE 'bytes: [0-9]+'
  printf '%s\n' "$output" | grep -qF '## Arch One'
  printf '%s\n' "$output" | grep -qF '### Arch Two'
}

# The two AC6 negatives, as NAMED predicates so each can be run twice: against
# the real payload (must pass) and against a committed forbidden fixture (must
# reject). A bare `! grep -q` against the payload alone is inert — it passes on
# an empty string just as happily (AC29).
payload_has_no_reference_body() {
  local hits
  hits="$(printf '%s\n' "$1" | grep -nF 'SPECCRAFT-REF-BODY-MUST-NOT-APPEAR' || true)"
  [ -z "$hits" ] || { echo "reference BODY leaked into the payload: $hits"; return 1; }
  return 0
}

payload_has_no_expected_digest() {
  local text="$1" digest hits
  shift
  for digest in "$@"; do
    hits="$(printf '%s\n' "$text" | grep -nF "$digest" || true)"
    [ -z "$hits" ] || { echo "composition-time digest leaked into the payload: $hits"; return 1; }
  done
  return 0
}

@test "the composed payload contains no reference BODY and no composition-time digest" {
  source "$LIB"; make_corpus
  run compose_default
  [ "$status" -eq 0 ]
  local payload="$output" d1 d2
  d1="$(review_digest .speccraft/architecture.md)"
  d2="$(review_digest .speccraft/conventions.md)"
  run payload_has_no_reference_body "$payload"
  [ "$status" -eq 0 ]
  # If the expected value were in the prompt, a reviewer could echo it back
  # without ever opening the file — the read-sentinel failure round 3 killed.
  run payload_has_no_expected_digest "$payload" "$d1" "$d2"
  [ "$status" -eq 0 ]
}

@test "the no-reference-body checker REJECTS the committed forbidden fixture" {
  run payload_has_no_reference_body "$(cat "$FIX/forbidden/fb01-reference-body.md")"
  [ "$status" -eq 1 ]
}

@test "the no-expected-digest checker REJECTS the committed forbidden fixture" {
  run payload_has_no_expected_digest "$(cat "$FIX/forbidden/fb02-expected-digest.md")" \
    "0000000000000000000000000000000000000000000000000000000000000000"
  [ "$status" -eq 1 ]
}

@test "a reference file named but missing on disk is a named error" {
  source "$LIB"; make_corpus
  rm "$TEST_DIR/.speccraft/conventions.md"
  # A missing conventions.md must not quietly shrink the payload and leave the
  # reviewer unaware that a whole tier is absent.
  run review_compose_payload "$TEST_DIR/template.md" round/spec-frozen.md \
    --inline .speccraft/guardrails.md \
    --reference .speccraft/architecture.md .speccraft/conventions.md \
    --digest-out "$TEST_DIR/digests.txt"
  assert_named_failure ".speccraft/conventions.md"
}

@test "an empty reference set emits the section with an explicit none marker" {
  source "$LIB"; make_corpus
  run review_compose_payload "$TEST_DIR/template.md" round/spec-frozen.md \
    --inline .speccraft/guardrails.md \
    --digest-out "$TEST_DIR/digests.txt"
  [ "$status" -eq 0 ]
  # Omitting the section would make "no reference files were sent" and "the
  # section was dropped by a bug" indistinguishable to the reviewer.
  printf '%s\n' "$output" | grep -qF '## Reference files'
  printf '%s\n' "$output" | grep -qF '(none)'
  [ -f "$TEST_DIR/digests.txt" ]
  [ ! -s "$TEST_DIR/digests.txt" ]
}

@test "--digest-out receives one <sha256>  <path> line per reference and the payload receives none" {
  source "$LIB"; make_corpus
  run compose_default
  [ "$status" -eq 0 ]
  # The digests need a channel that is NOT the payload (AC6), and this is it.
  [ "$(wc -l < "$TEST_DIR/digests.txt" | tr -d ' ')" = "2" ]
  grep -qE '^[0-9a-f]{64}  \.speccraft/architecture\.md$' "$TEST_DIR/digests.txt"
  grep -qE '^[0-9a-f]{64}  \.speccraft/conventions\.md$' "$TEST_DIR/digests.txt"
  # The digest-out sidecar is the ONE other file the composer writes.
  run payload_has_no_expected_digest "$output" \
    "$(review_digest .speccraft/architecture.md)" "$(review_digest .speccraft/conventions.md)"
  [ "$status" -eq 0 ]
}

@test "a scoped round substitutes {{DIFF}} and {{CHANGED_SECTIONS}} and leaves no placeholder surviving" {
  source "$LIB"; make_corpus
  run review_compose_payload "$TEST_DIR/template.md" round/spec-frozen.md \
    --inline .speccraft/guardrails.md \
    --reference .speccraft/architecture.md \
    --digest-out "$TEST_DIR/digests.txt" \
    --diff "DIFF-MARKER" --changed "SECTIONS-MARKER"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF 'DIFF-MARKER'
  printf '%s\n' "$output" | grep -qF 'SECTIONS-MARKER'
  run bash -c "printf '%s\n' \"\$1\" | grep -nF '{{'" _ "$output"
  [ "$status" -ne 0 ]
}

@test "the composer reads spec content only from the <spec-src> it is given" {
  source "$LIB"; make_corpus
  # AC16 under AC24's deferral: there is no fresh review-snapshot.md at compose
  # time, so the round's frozen image is the source and spec.md is never read.
  run compose_default
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF 'FROZEN-SPEC-BODY'
  run bash -c "printf '%s\n' \"\$1\" | grep -nF 'LIVE-SPEC-MUST-NOT-APPEAR'" _ "$output"
  [ "$status" -ne 0 ]
}

# a_utf8_locale — a UTF-8 locale this host actually has. Hard-coding one would
# silently fall back to C on a host that lacks it, making the arm vacuous.
a_utf8_locale() {
  locale -a 2>/dev/null | grep -iE 'utf-?8' | grep -viE '^(c|posix)\.' | head -1
}

@test "heading records are byte-identical under LC_ALL=C and under a UTF-8 locale" {
  source "$LIB"; make_corpus
  printf '# T\n\n## Ünïcödé — héading\n\nSPECCRAFT-REF-BODY-MUST-NOT-APPEAR\n' \
    > "$TEST_DIR/.speccraft/architecture.md"
  local utf8; utf8="$(a_utf8_locale)"
  [ -n "$utf8" ]
  # Two hosts with different locales must not compose different records from
  # the same bytes (AC13).
  LC_ALL=C           run compose_default; local c_out="$output"
  LC_ALL="$utf8"     run compose_default; local u_out="$output"
  [ "$c_out" = "$u_out" ]
  printf '%s\n' "$c_out" | grep -qF '## Ünïcödé — héading'
}

# ---- AC19/AC20/AC21: the budget, the refusal, the overrides ---------------
#
# The failure this replaces is a 600 s timeout — the least informative outcome
# available: it names neither the cause (payload size) nor the remedy, and at
# the quorum layer it is indistinguishable from an agent that had nothing to
# say. Everything below exists so oversize is discovered BEFORE dispatch and
# reported with the specific remedy for the specific limit.

ARGV_LIMIT=65536
PAYLOAD_LIMIT=262144

@test "review_budget_check exits 0 for ok and for every refusal" {
  source "$LIB"
  # A refusal is DATA, not a shell failure: `if ! review_budget_check` would
  # otherwise conflate "over budget" with "the helper broke".
  run review_budget_check 100 stdin
  [ "$status" -eq 0 ] && [ "$output" = "ok" ]
  run review_budget_check $((ARGV_LIMIT + 1)) argv
  [ "$status" -eq 0 ] && [ "$output" = "refuse:argv-limit" ]
  run review_budget_check $((PAYLOAD_LIMIT + 1)) stdin
  [ "$status" -eq 0 ] && [ "$output" = "refuse:payload-limit" ]
}

@test "the input-mode matrix is exhaustive: argv, acp, stdin, file, empty, absent" {
  source "$LIB"
  local over_argv=$((ARGV_LIMIT + 1))
  # argv and acp are BOTH argv transport: aux-delegator invokes ACP as
  # `acpx <agent> <prompt>`, so exempting it would exempt the mode most likely
  # to overflow.
  run review_budget_check "$over_argv" argv; [ "$output" = "refuse:argv-limit" ]
  run review_budget_check "$over_argv" acp;  [ "$output" = "refuse:argv-limit" ]
  # stdin and file pass no prompt as an argument, so only the payload limit binds.
  run review_budget_check "$over_argv" stdin; [ "$output" = "ok" ]
  run review_budget_check "$over_argv" file;  [ "$output" = "ok" ]
  # A registry entry with no `input` key normalizes to stdin.
  run review_budget_check "$over_argv" "";    [ "$output" = "ok" ]
  run review_budget_check "$over_argv";       [ "$output" = "ok" ]
}

@test "an unknown input mode is a named error, not a silent normalization to stdin" {
  source "$LIB"
  # Only EMPTY normalizes. Treating an unrecognised mode as stdin would exempt
  # the next argv transport somebody adds to the registry.
  run review_budget_check 100 telepathy
  assert_named_failure "telepathy"
}

@test "each limit is pinned at limit-1, limit and limit+1 with the value AT the limit accepted" {
  source "$LIB"
  run review_budget_check $((ARGV_LIMIT - 1)) argv; [ "$output" = "ok" ]
  run review_budget_check "$ARGV_LIMIT" argv;       [ "$output" = "ok" ]
  run review_budget_check $((ARGV_LIMIT + 1)) argv; [ "$output" = "refuse:argv-limit" ]
  run review_budget_check $((PAYLOAD_LIMIT - 1)) stdin; [ "$output" = "ok" ]
  run review_budget_check "$PAYLOAD_LIMIT" stdin;       [ "$output" = "ok" ]
  run review_budget_check $((PAYLOAD_LIMIT + 1)) stdin; [ "$output" = "refuse:payload-limit" ]
}

@test "refuse:payload-limit wins deterministically when both limits are exceeded" {
  source "$LIB"
  run review_budget_check $((PAYLOAD_LIMIT + 1)) argv
  [ "$output" = "refuse:payload-limit" ]
}

@test "the refusal reason enum is exactly refuse:argv-limit and refuse:payload-limit" {
  source "$LIB"
  local mode bytes out
  # Enumerated, so a third reason value added later fails here rather than
  # silently reaching a caller that switches on the two known ones.
  for mode in argv acp stdin file ""; do
    for bytes in 1 "$ARGV_LIMIT" $((ARGV_LIMIT + 1)) "$PAYLOAD_LIMIT" $((PAYLOAD_LIMIT + 1)); do
      out="$(review_budget_check "$bytes" "$mode")"
      case "$out" in
        ok|refuse:argv-limit|refuse:payload-limit) ;;
        *) echo "unknown budget verdict '$out' for mode='$mode' bytes=$bytes"; return 1 ;;
      esac
    done
  done
}

RANKED="41000  .speccraft/guardrails.md
12000  spec.md"

@test "an argv-limit message carries agent, mode, bytes, effective limit, a named file, the migration line and agents.toml" {
  source "$LIB"
  run review_refusal_message codex argv 70000 refuse:argv-limit "$RANKED"
  [ "$status" -eq 0 ]
  # Each element asserted by EXACT MATCH rather than by message length.
  printf '%s\n' "$output" | grep -qF 'codex'
  printf '%s\n' "$output" | grep -qF 'argv'
  printf '%s\n' "$output" | grep -qF '70000'
  printf '%s\n' "$output" | grep -qF "$ARGV_LIMIT"
  printf '%s\n' "$output" | grep -qF '.speccraft/guardrails.md'
  # stdin is the remedy for THIS limit, and the migration is concrete because
  # existing repos own their agents.toml and are never rewritten.
  printf '%s\n' "$output" | grep -qF 'input = "stdin"'
  printf '%s\n' "$output" | grep -qF '.speccraft/agents.toml'
}

@test "a payload-limit message names the actual remedy and does NOT carry the migration line" {
  source "$LIB"
  run review_refusal_message codex stdin 300000 refuse:payload-limit "$RANKED"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "$PAYLOAD_LIMIT"
  printf '%s\n' "$output" | grep -qiE 'compact|shorter spec'
  # stdin fixes an argv-limit refusal and does NOTHING for a payload-limit one;
  # offering it here would send the developer after the wrong fix.
  run bash -c "printf '%s\n' \"\$1\" | grep -nF 'input = \"stdin\"'" _ "$output"
  [ "$status" -ne 0 ]
}

@test "a both-limits message names both and states that a stdin-mode agent would still be refused" {
  source "$LIB"
  # One enum value is returned, but both limits are named — worded so the argv
  # limit cannot be read as an available remedy.
  run review_refusal_message codex argv 300000 refuse:payload-limit "$RANKED"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "$PAYLOAD_LIMIT"
  printf '%s\n' "$output" | grep -qF "$ARGV_LIMIT"
  printf '%s\n' "$output" | grep -qF 'a stdin-mode agent is still refused above the payload limit'
}

@test "the message quotes the RUNTIME effective limit, not the compiled default" {
  source "$LIB"
  # A diagnostic that disagrees with the behavior when an override is in play is
  # worse than no diagnostic: it sends the reader to the wrong number.
  REVIEW_MAX_ARGV_BYTES=4096 run review_refusal_message codex argv 5000 refuse:argv-limit "$RANKED"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF '4096'
  run bash -c "printf '%s\n' \"\$1\" | grep -nF '$ARGV_LIMIT'" _ "$output"
  [ "$status" -ne 0 ]
}

@test "a valid override is honoured by the budget check itself" {
  source "$LIB"
  REVIEW_MAX_ARGV_BYTES=4096 run review_budget_check 5000 argv
  [ "$output" = "refuse:argv-limit" ]
  REVIEW_MAX_PAYLOAD_BYTES=524288 run review_budget_check 300000 stdin
  [ "$output" = "ok" ]
}

@test "each rejected override shape warns on stderr naming the variable and proceeds with the compiled default" {
  source "$LIB"
  local bad
  # Empty, zero, negative, non-numeric, and below the named floor. Each must be
  # LEGIBLE rather than silent: the valid override is the sanctioned one-shot
  # escape hatch for an oversized round, so a typo in it must not look like a
  # policy decision.
  for bad in "" 0 -1 abc 12x 1023; do
    REVIEW_MAX_ARGV_BYTES="$bad" run review_effective_limit argv
    [ "$status" -eq 0 ]
    printf '%s\n' "$output" | grep -qF "REVIEW_MAX_ARGV_BYTES" || {
      echo "override '$bad' did not name the offending variable: $output"; return 1; }
    printf '%s\n' "$output" | grep -qF "$ARGV_LIMIT" || {
      echo "override '$bad' did not fall back to the compiled default: $output"; return 1; }
  done
  # …and it does not abort the review. The warning rides on stderr, which bats
  # merges into $output, so the verdict is the LAST line rather than the whole
  # of it — a real caller captures stdout and sees only `ok`.
  REVIEW_MAX_ARGV_BYTES=abc run review_budget_check 100 argv
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | tail -1)" = "ok" ]
  printf '%s\n' "$output" | grep -qF "REVIEW_MAX_ARGV_BYTES"
}

@test "REVIEW_MIN_LIMIT_BYTES is a named constant, not an inline magic number" {
  source "$LIB"
  [ "$REVIEW_MIN_LIMIT_BYTES" = "1024" ]
}

@test "review_rank_files ranks the named files by size, largest first" {
  source "$LIB"; make_corpus
  printf 'x%.0s' $(seq 1 500) > "$TEST_DIR/.speccraft/guardrails.md"
  run review_rank_files .speccraft/guardrails.md .speccraft/index.md
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | head -1 | sed 's/.*  //')" = ".speccraft/guardrails.md" ]
}

@test "the budget check runs on the composed payload of BOTH --diff branches" {
  source "$LIB"; make_corpus
  # A small delta with a large heading index must still refuse under argv mode,
  # so the scoped branch cannot be the one that escapes the bound. The inline
  # guardrails are padded past REVIEW_MIN_LIMIT_BYTES because the override floor
  # is 1024 and the fixture corpus is otherwise smaller than any legal limit.
  printf 'x%.0s' $(seq 1 3000) >> "$TEST_DIR/.speccraft/guardrails.md"
  local full scoped
  full="$(compose_default | wc -c | tr -d ' ')"
  scoped="$(review_compose_payload "$TEST_DIR/template.md" round/spec-frozen.md \
    --inline .speccraft/guardrails.md \
    --reference .speccraft/architecture.md \
    --digest-out "$TEST_DIR/digests.txt" \
    --diff "tiny delta" --changed "[]" | wc -c | tr -d ' ')"
  [ "$full" -gt 0 ] && [ "$scoped" -gt 0 ]
  REVIEW_MAX_ARGV_BYTES=1024 run review_budget_check "$full" argv
  [ "$output" = "refuse:argv-limit" ]
  REVIEW_MAX_ARGV_BYTES=1024 run review_budget_check "$scoped" argv
  [ "$output" = "refuse:argv-limit" ]
}

# ---- AC10/AC11/AC12/AC13/AC13b/AC14: materialize once, dispatch exactly ---
#
# ONE compound envelope, because these criteria share a single seam: the bytes
# are composed, written once, measured, and handed to a CLI. Splitting them into
# one test per clause would assert the same seam five times over.

# mode_of <path> — the permission string, via ls rather than stat: `stat -c` is
# GNU-only and `stat -f` is BSD-only, and this suite runs on both runners.
mode_of() {
  ls -ld "$1" | cut -c1-10
}

@test "the round temp dir is 0700 and the payload artifact is 0600" {
  source "$LIB"
  review_round_tmpdir
  [ -d "$REVIEW_ROUND_TMPDIR" ]
  # A full review prompt is the most sensitive artifact this command produces;
  # it must not be world-readable even for the seconds it exists.
  [ "$(mode_of "$REVIEW_ROUND_TMPDIR")" = "drwx------" ]
  review_materialize_payload "$REVIEW_ROUND_TMPDIR/payload.txt" printf 'hello\n'
  [ "$(mode_of "$REVIEW_ROUND_TMPDIR/payload.txt")" = "-rw-------" ]
}

@test "measured bytes equal wc -c of the artifact actually dispatched, for a payload ending in several newlines" {
  source "$LIB"
  review_round_tmpdir
  local art="$REVIEW_ROUND_TMPDIR/payload.txt" measured actual
  # Trailing newlines are the whole point: `bytes="$(compose)"` strips them, so
  # measured and dispatched bytes would differ silently. Redirection cannot.
  measured="$(review_materialize_payload "$art" printf 'body\n\n\n\n')"
  actual="$(wc -c < "$art" | tr -d ' ')"
  [ "$measured" = "$actual" ]
  [ "$measured" = "8" ]   # 'body' + four newlines, none of them lost
}

@test "review_round_tmpdir does not destroy the caller's EXIT trap" {
  source "$LIB"
  # Not a hypothetical: a helper that clobbers EXIT makes a FAILING bats test
  # report nothing at all, so every assertion in the tests above would be inert
  # — and a driver with its own cleanup would silently lose it.
  run bash -c "source '$LIB'; trap 'printf CALLER-EXIT-RAN > \"$TEST_DIR/prior\"' EXIT; review_round_tmpdir; exit 0"
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_DIR/prior")" = "CALLER-EXIT-RAN" ]
}

@test "review_materialize_payload refuses to overwrite an existing artifact" {
  source "$LIB"
  review_round_tmpdir
  local art="$REVIEW_ROUND_TMPDIR/payload.txt"
  review_materialize_payload "$art" printf 'first\n'
  run review_materialize_payload "$art" printf 'second\n'
  assert_named_failure "$art"
  # The first bytes survive: a second materialization is refused, not merged.
  [ "$(cat "$art")" = "first" ]
}

@test "exactly one payload artifact is created per round at the instrumented seams" {
  source "$LIB"; make_corpus
  review_round_tmpdir
  export REVIEW_MATERIALIZE_LOG="$TEST_DIR/materialize.log"
  : > "$REVIEW_MATERIALIZE_LOG"
  review_materialize_payload "$REVIEW_ROUND_TMPDIR/payload.txt" \
    review_compose_payload "$TEST_DIR/template.md" round/spec-frozen.md \
      --inline .speccraft/guardrails.md \
      --reference .speccraft/architecture.md \
      --digest-out "$TEST_DIR/digests.txt"
  # Bounded to NAMED seams: an unbounded "no copy anywhere on the filesystem"
  # check would itself be the vacuous negative this spec argues against.
  run review_seam_single_creation "$REVIEW_MATERIALIZE_LOG"
  [ "$status" -eq 0 ]
  # …and dispatch adds no copy of its own, for any mode.
  review_dispatch_payload "true" file "$REVIEW_ROUND_TMPDIR/payload.txt"
  run review_seam_single_creation "$REVIEW_MATERIALIZE_LOG"
  [ "$status" -eq 0 ]
}

@test "the seam checker REJECTS the committed two-creation log fixture" {
  source "$LIB"
  # AC29: the negative is pinned against a committed artifact, so "exactly one"
  # cannot pass by never being exercised against two.
  run review_seam_single_creation "$FIX/forbidden/fb03-double-materialization.log"
  [ "$status" -ne 0 ]
  printf '%s\n' "$output" | grep -qF 'payload.debug.txt'
}

@test "the round temp dir is removed on clean exit" {
  source "$LIB"
  # The trap belongs to the shell that called review_round_tmpdir, so the whole
  # lifecycle has to be exercised in a child shell.
  run bash -c "source '$LIB'; review_round_tmpdir; printf '%s' \"\$REVIEW_ROUND_TMPDIR\" > '$TEST_DIR/dir'; exit 0"
  [ "$status" -eq 0 ]
  [ ! -e "$(cat "$TEST_DIR/dir")" ]
}

@test "the round temp dir is removed on SIGINT and on SIGTERM" {
  source "$LIB"
  local sig
  # A crash must not leave a full review prompt on disk indefinitely. `trap`
  # cannot catch SIGKILL, and that boundary is stated in the lib rather than
  # claimed away — so it is deliberately not asserted here.
  for sig in INT TERM; do
    bash -c "source '$LIB'; review_round_tmpdir; printf '%s' \"\$REVIEW_ROUND_TMPDIR\" > '$TEST_DIR/dir.$sig'; kill -$sig \$\$; sleep 5" || true
    [ -s "$TEST_DIR/dir.$sig" ]
    [ ! -e "$(cat "$TEST_DIR/dir.$sig")" ] || {
      echo "temp dir survived SIG$sig: $(cat "$TEST_DIR/dir.$sig")"; return 1; }
  done
}

@test "a NUL-bearing payload is refused with a diagnostic naming NUL" {
  source "$LIB"
  # POSIX argv cannot carry an embedded NUL, so measured-equals-dispatched is
  # unimplementable for argv mode on such a payload. Refuse, and say which of
  # the two representability rules failed.
  run review_payload_representable "$FIX/binary/b01-nul.bin"
  assert_named_failure "NUL"
}

@test "an invalid-UTF-8 payload is refused with a diagnostic naming UTF-8" {
  source "$LIB"
  run review_payload_representable "$FIX/binary/b02-invalid-utf8.bin"
  assert_named_failure "UTF-8"
  # The two fixtures are independent: the NUL one is VALID UTF-8 and the invalid
  # one is NUL-free, so neither diagnostic can be reached by accident.
  run review_payload_representable "$FIX/digest/d01-known-vector.txt"
  [ "$status" -eq 0 ]
}

# A stub CLI standing in for the boundary: it digests exactly what it received,
# from argv or from stdin, so "the bytes that reached the CLI" is a measurement
# rather than an assumption.
install_boundary_stub() {
  mkdir -p "$TEST_DIR/cli"
  cat > "$TEST_DIR/cli/codex" <<'STUB'
#!/usr/bin/env bash
# One stub for all four transports, so a single digest comparison covers them.
case "${1:-}" in
  --file) cat "$2" > "$BOUNDARY_RAW" ;;
  "")     cat > "$BOUNDARY_RAW" ;;
  *)      printf '%s' "$1" > "$BOUNDARY_RAW" ;;
esac
STUB
  chmod +x "$TEST_DIR/cli/codex"
  export BOUNDARY_RAW="$TEST_DIR/boundary.raw"
  export PATH="$TEST_DIR/cli:$PATH"
}

@test "argv and acp dispatch deliver a digest equal to the artifact digest for zero, one and several trailing newlines" {
  source "$LIB"
  install_boundary_stub
  review_round_tmpdir
  local body mode art n=0
  # AC13b: reading an artifact into a shell variable for argv dispatch strips
  # trailing newlines — the same defect AC10 closes for composition, arriving
  # one step later. Every trailing-newline shape is exercised.
  for body in 'no trailing newline' 'one trailing newline
' 'several trailing newlines


'; do
    for mode in argv acp stdin file; do
      n=$((n + 1))
      art="$REVIEW_ROUND_TMPDIR/p$n.txt"
      printf '%s' "$body" > "$art"
      : > "$BOUNDARY_RAW"
      review_dispatch_payload "codex" "$mode" "$art"
      [ "$(review_digest "$BOUNDARY_RAW")" = "$(review_digest "$art")" ] || {
        echo "mode=$mode lost bytes: artifact=$(wc -c < "$art") boundary=$(wc -c < "$BOUNDARY_RAW")"
        return 1
      }
    done
  done
}

@test "file mode passes the artifact itself rather than writing a second copy" {
  source "$LIB"
  review_round_tmpdir
  mkdir -p "$TEST_DIR/cli"
  # `input = "file"` is where a second copy would appear most naturally, so the
  # argument the CLI receives is asserted to BE the round's artifact.
  cat > "$TEST_DIR/cli/codex" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$SEEN_ARGS"
STUB
  chmod +x "$TEST_DIR/cli/codex"
  export SEEN_ARGS="$TEST_DIR/seen.args"
  export PATH="$TEST_DIR/cli:$PATH"
  local art="$REVIEW_ROUND_TMPDIR/payload.txt"
  printf 'body\n' > "$art"
  review_dispatch_payload "codex" file "$art"
  grep -qxF -- "$art" "$SEEN_ARGS"
}

@test "aux-delegator's review path dispatches a precomposed artifact and forbids recomposition" {
  local f="$PLUGIN_DIR/agents/aux-delegator.md"
  # Left as it was, a review round would compose TWICE: the delegator would
  # re-prefix the template, re-inline context, and for input = "file" write a
  # second copy — so the bytes measured by the budget would not be the bytes
  # dispatched, violated by the component furthest from the check.
  grep -qF 'review_dispatch_payload' "$f"
  grep -qF 'precomposed' "$f"
  grep -qiF 'must not' "$f"
}

@test "aux-delegator's non-review mode instructions are byte-identical to the committed golden" {
  # Content-equality of every line naming a non-review mode. The review path may
  # be rewritten freely; these lines may not drift as a side effect.
  run bash -c "grep -iE 'implement|analyze' '$PLUGIN_DIR/agents/aux-delegator.md'"
  [ "$status" -eq 0 ]
  [ "$output" = "$(cat "$FIX/golden/aux-delegator-nonreview.golden")" ]
}

# The validator's VERDICT is its stdout; the review_error detail rides on stderr,
# which bats merges into $output — so the verdict is the LAST line. Asserting
# equality against the whole of $output would fail on the diagnostic that makes
# a rejection useful.
assert_reason() {
  [ "$(printf '%s\n' "$output" | tail -1)" = "$1" ] || {
    echo "want verdict '$1', got: $output" >&2
    return 1
  }
}

# ---- AC25/AC26/AC28: attestation, capability, shipped template ------------
#
# A matching digest establishes that a process with filesystem access at the
# dispatched cwd obtained the referenced bytes. It does NOT establish that the
# model reasoned over them — a reviewer could checksum a path without ever
# bringing the content into context. The guarantee is deliberately the weaker
# one: it converts "this agent cannot read files at all, and nobody noticed"
# from an invisible failure into a mechanical one, which is the failure actually
# reported from the field.

@test "review_validate_reference_access accepts a well-formed response" {
  source "$LIB"
  run review_validate_reference_access "$RESP/ra01-valid.out" "$EXPECTED_DIGESTS"
  [ "$status" -eq 0 ]
  assert_reason "ok"
}

@test "review_validate_reference_access tolerates unquoted YAML scalars" {
  source "$LIB"
  # The shipped CLIs are not consistent about quoting. A parser that only
  # accepted one spelling would fail every verdict from whichever CLI chose the
  # other, which looks exactly like a reviewer that cannot read files.
  run review_validate_reference_access "$RESP/ra09-unquoted.out" "$EXPECTED_DIGESTS"
  [ "$status" -eq 0 ]
  assert_reason "ok"
}

@test "a missing expected path is rejected" {
  source "$LIB"
  run review_validate_reference_access "$RESP/ra02-missing-path.out" "$EXPECTED_DIGESTS"
  [ "$status" -ne 0 ]
  assert_reason "invalid:missing-path"
}

@test "an unknown path is rejected" {
  source "$LIB"
  run review_validate_reference_access "$RESP/ra03-unknown-path.out" "$EXPECTED_DIGESTS"
  [ "$status" -ne 0 ]
  assert_reason "invalid:unknown-path"
}

@test "a wrong digest is rejected" {
  source "$LIB"
  run review_validate_reference_access "$RESP/ra04-wrong-digest.out" "$EXPECTED_DIGESTS"
  [ "$status" -ne 0 ]
  assert_reason "invalid:digest-mismatch"
}

@test "duplicate entries for one path are rejected" {
  source "$LIB"
  # Otherwise one read could be presented twice to cover a path never opened.
  run review_validate_reference_access "$RESP/ra05-duplicate-path.out" "$EXPECTED_DIGESTS"
  [ "$status" -ne 0 ]
  assert_reason "invalid:duplicate-path"
}

@test "an absent reference_access block is rejected" {
  source "$LIB"
  run review_validate_reference_access "$RESP/ra06-absent.out" "$EXPECTED_DIGESTS"
  [ "$status" -ne 0 ]
  assert_reason "invalid:absent"
}

@test "an entry with no sha256 is rejected as malformed" {
  source "$LIB"
  run review_validate_reference_access "$RESP/ra08-no-digest.out" "$EXPECTED_DIGESTS"
  [ "$status" -ne 0 ]
  assert_reason "invalid:malformed"
}

@test "a non-empty reference_access_failures is rejected even when every digest matches" {
  source "$LIB"
  # The digests are all correct in this fixture: the verdict is refused because
  # the reviewer itself reported it could not read a reference.
  run review_validate_reference_access "$RESP/ra07-failures-nonempty.out" "$EXPECTED_DIGESTS"
  [ "$status" -ne 0 ]
  assert_reason "invalid:read-failure"
}

@test "every CAPTURED historical reviewer response yields a named reason, never a parser crash" {
  source "$LIB"
  local f out
  # The corpus is 12 real round-1..6 outputs from this spec's own review. They
  # predate the schema, so they must be REJECTED — but with `invalid:absent`,
  # the reason that says "this response has no attestation", not with a parse
  # error. A validator too strict for how the CLIs actually wrap YAML would fail
  # every verdict, and it would look like a fleet of unreadable references.
  for f in "$RESP"/historical/*.out; do
    run review_validate_reference_access "$f" "$EXPECTED_DIGESTS"
    [ "$status" -ne 0 ] || { echo "$f unexpectedly validated"; return 1; }
    case "$output" in
      invalid:absent) ;;
      *) echo "$f gave '$output', want invalid:absent (a parser failure would show up here)"; return 1 ;;
    esac
  done
}

@test "the validator's reason enum is exhaustively pinned" {
  source "$LIB"
  local f out
  # A new reason value must be added here deliberately, not discovered by a
  # caller switching on the known ones.
  for f in "$RESP"/ra0*.out; do
    out="$(review_validate_reference_access "$f" "$EXPECTED_DIGESTS" || true)"
    case "$out" in
      ok|invalid:absent|invalid:malformed|invalid:missing-path|invalid:unknown-path|invalid:duplicate-path|invalid:digest-mismatch|invalid:read-failure) ;;
      *) echo "unknown validator verdict '$out' for $f"; return 1 ;;
    esac
  done
}

@test "a failed attestation counts toward neither predicate and is reported in its own category" {
  source "$LIB"
  make_spec_dir
  # The linkage AC25 requires: the same rule as a timeout.
  run review_responses_complete "$(outcomes 'codex attestation-failed digest-mismatch' 'claude-p approve')"
  [ "$status" -eq 1 ]
  run review_approval_quorum_met 2 "$(outcomes 'codex attestation-failed digest-mismatch' 'claude-p approve')"
  [ "$status" -eq 1 ]
  run review_finalize_round "$SPEC_DIR" 1 "$(outcomes 'codex attestation-failed digest-mismatch' 'claude-p approve')"
  printf '%s\n' "$output" | grep -qF 'attestation-failure: codex digest-mismatch'
  printf '%s\n' "$output" | grep -qxF 'status: draft'
}

# ---- AC26: the registry capability flag, opt-out --------------------------

@test "review_agent_reference_read is true when the flag is absent, true when true, false only for an explicit false" {
  source "$LIB"
  local t="$TEST_DIR/agents.toml"
  cat > "$t" <<'TOML'
[[agents]]
name = "no-flag"
input = "stdin"

[[agents]]
name = "yes-flag"
input = "stdin"
reference_read = true

[[agents]]
name = "no-read"
input = "stdin"
reference_read = false
TOML
  # OPT-OUT, deliberately. Making absence mean "incapable" would have been an
  # operationally breaking upgrade: every already-initialized repo lacks the
  # key, so every configured reviewer would go ineligible on the first git pull.
  run review_agent_reference_read "$t" no-flag;  [ "$output" = "true" ]
  run review_agent_reference_read "$t" yes-flag; [ "$output" = "true" ]
  run review_agent_reference_read "$t" no-read;  [ "$output" = "false" ]
}

@test "review_agent_field reads a per-agent value and does not bleed across blocks" {
  source "$LIB"
  local t="$TEST_DIR/agents.toml"
  cat > "$t" <<'TOML'
[[agents]]
name = "first"
input = "stdin"

[[agents]]
name = "second"
input = "argv"
TOML
  # A whole-file grep would answer "stdin" for both, which is how an agent added
  # later with argv slips past AC28.
  run review_agent_field "$t" first input;  [ "$output" = "stdin" ]
  run review_agent_field "$t" second input; [ "$output" = "argv" ]
  run review_agent_field "$t" first nosuch; [ -z "$output" ]
}

@test "a reference_read = false agent is refused with the named message" {
  source "$LIB"
  run review_reference_read_message codex-sandboxed
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF 'codex-sandboxed'
  printf '%s\n' "$output" | grep -qF 'reference_read = false'
}

@test "agents/aux-delegator.md frontmatter lists Read" {
  # Confirm-only: handing a reviewer a path is useless if the dispatched agent
  # cannot open files, and it fails WORSE than a timeout — a plausible verdict
  # on a file never read.
  run sed -n '1,/^---$/p;/^tools:/p' "$PLUGIN_DIR/agents/aux-delegator.md"
  printf '%s\n' "$output" | grep -qE '^tools:.*\bRead\b'
}

# ---- AC27 (prompt half) / AC28: the shipped templates ---------------------

@test "templates/prompts/review.md carries the reference_access schema and the read-it-yourself instruction" {
  local t="$PLUGIN_DIR/templates/prompts/review.md"
  grep -qF 'reference_access:' "$t"
  grep -qF 'reference_access_failures:' "$t"
  grep -qF 'sha256' "$t"
  grep -qiF 'your own tools' "$t"
  # An unreadable reference must invalidate the verdict, stated to the reviewer
  # rather than merely enforced behind its back.
  grep -qiF 'does not count' "$t"
}

@test "templates/speccraft/agents.toml sets stdin per agent, retains no argv, and flags every enabled entry" {
  source "$LIB"
  local t="$PLUGIN_DIR/templates/speccraft/agents.toml" name enabled
  run review_agent_field "$t" claude-p input; [ "$output" = "stdin" ]
  run review_agent_field "$t" opencode input; [ "$output" = "stdin" ]
  # Parsed PER AGENT, so an agent added later with argv fails here rather than
  # passing on a whole-file grep.
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    [ "$(review_agent_field "$t" "$name" input)" != "argv" ] || {
      echo "agent '$name' still ships input = argv"; return 1; }
    enabled="$(review_agent_field "$t" "$name" enabled)"
    [ "$enabled" = "false" ] || [ "$(review_agent_field "$t" "$name" reference_read)" = "true" ] || {
      echo "enabled agent '$name' carries no explicit reference_read = true"; return 1; }
  done < <(review_agent_names "$t")
}

# ---- AC17/AC18: the ratio, on two corpora ---------------------------------
#
# ONE assertion over two corpora, per the spec's planning notes. AC18 proves the
# MECHANISM works, everywhere and without skipping; AC17 proves TODAY'S REAL TREE
# fits. Both are pinned BIDIRECTIONALLY: under the argv limit AND at least 2x
# smaller than a full paste of the same inputs — so a regression that erodes the
# compression ratio while still landing just under the limit fails, rather than
# passing on the absolute bound alone.

# Materialize the static corpus as a repo find-root will resolve, since tier
# classification is root-relative by design.
make_static_corpus() {
  mkdir -p "$TEST_DIR/.speccraft" "$TEST_DIR/round"
  cp "$FIX/corpus/guardrails.md"   "$TEST_DIR/.speccraft/guardrails.md"
  cp "$FIX/corpus/index.md"        "$TEST_DIR/.speccraft/index.md"
  cp "$FIX/corpus/architecture.md" "$TEST_DIR/.speccraft/architecture.md"
  cp "$FIX/corpus/conventions.md"  "$TEST_DIR/.speccraft/conventions.md"
  cp "$FIX/corpus/spec.md"         "$TEST_DIR/round/spec-frozen.md"
  cd "$TEST_DIR"
}

# largest_archived_spec <archive-dir> — the biggest spec.md, with a
# LEXICOGRAPHIC-ID tiebreaker so two same-sized specs cannot make the selection
# non-deterministic. Test-side on purpose: it selects a corpus, it ships nothing.
largest_archived_spec() {
  local dir="${1:-}"
  [ -d "$dir" ] || return 1
  find "$dir" -name spec.md -type f 2>/dev/null \
    | while IFS= read -r f; do printf '%s %s\n' "$(LC_ALL=C wc -c < "$f" | tr -d ' ')" "$f"; done \
    | sort -k1,1rn -k2,2 \
    | head -1 | sed 's/^[0-9]*  *//'
}

@test "the static corpus composes under the argv limit AND at least 2x smaller than a full paste" {
  source "$LIB"; make_static_corpus
  local tiered full
  tiered="$(review_compose_payload "$FIX/corpus/template.md" round/spec-frozen.md \
    --inline .speccraft/guardrails.md .speccraft/index.md \
    --reference .speccraft/architecture.md .speccraft/conventions.md \
    --digest-out "$TEST_DIR/digests.txt" | LC_ALL=C wc -c | tr -d ' ')"
  full="$(review_full_paste_bytes "$FIX/corpus/template.md" round/spec-frozen.md \
    .speccraft/guardrails.md .speccraft/index.md \
    .speccraft/architecture.md .speccraft/conventions.md)"
  [ "$tiered" -le "$REVIEW_MAX_ARGV_BYTES_DEFAULT" ] || {
    echo "tiered composition is $tiered bytes, over the argv limit"; return 1; }
  [ "$full" -ge $((tiered * 2)) ] || {
    echo "compression ratio eroded: tiered=$tiered full=$full (want full >= 2x tiered)"; return 1; }
}

@test "the live .speccraft plus the largest archived spec composes under the argv limit while a full paste exceeds it by more than 2x" {
  source "$LIB"
  local archive="$PLUGIN_DIR/specs/.archive" spec tiered full
  # A fresh clone or a shallow CI checkout has no archive. SKIP with a stated
  # reason rather than failing or — worse — passing vacuously.
  [ -d "$archive" ] || skip "specs/.archive is absent (fresh clone or shallow checkout)"
  spec="$(largest_archived_spec "$archive")"
  [ -n "$spec" ] || skip "specs/.archive contains no spec.md"
  cd "$PLUGIN_DIR"
  # Selected DYNAMICALLY: no hard-coded path and no hard-coded byte count, so an
  # unrelated spec:close cannot red this and neither can a new archive entry.
  tiered="$(review_compose_payload "$PLUGIN_DIR/templates/prompts/review.md" "$spec" \
    --inline .speccraft/guardrails.md .speccraft/index.md \
    --reference .speccraft/architecture.md .speccraft/conventions.md \
    --digest-out "$TEST_DIR/digests.txt" | LC_ALL=C wc -c | tr -d ' ')"
  full="$(review_full_paste_bytes "$PLUGIN_DIR/templates/prompts/review.md" "$spec" \
    .speccraft/guardrails.md .speccraft/index.md \
    .speccraft/architecture.md .speccraft/conventions.md)"
  [ "$tiered" -le "$REVIEW_MAX_ARGV_BYTES_DEFAULT" ] || {
    echo "live tiered composition is $tiered bytes, over the argv limit (spec: $spec)"; return 1; }
  # The reported bug, reproduced as an assertion: a full paste from THIS repo is
  # already several times the claude-p argv limit.
  [ "$full" -gt $((REVIEW_MAX_ARGV_BYTES_DEFAULT * 2)) ] || {
    echo "full paste is only $full bytes — this corpus no longer demonstrates the bug"; return 1; }
  [ "$full" -ge $((tiered * 2)) ] || {
    echo "compression ratio eroded on the live corpus: tiered=$tiered full=$full"; return 1; }
}

@test "the largest archived spec is selected by size with a lexicographic-id tiebreaker" {
  local d="$TEST_DIR/arch"
  mkdir -p "$d/0009-small" "$d/0031-tie" "$d/0007-tie"
  printf 'x%.0s' $(seq 1 10)  > "$d/0009-small/spec.md"
  printf 'y%.0s' $(seq 1 100) > "$d/0031-tie/spec.md"
  printf 'z%.0s' $(seq 1 100) > "$d/0007-tie/spec.md"
  # Two same-sized specs must not make the choice depend on directory order.
  run largest_archived_spec "$d"
  [ "$status" -eq 0 ]
  [ "$output" = "$d/0007-tie/spec.md" ]
}

@test "the live-corpus arm skips with a stated reason when the archive is absent or empty" {
  local empty="$TEST_DIR/no-archive"
  mkdir -p "$empty"
  # The skip PREDICATE is asserted directly, because a test that skips cannot
  # itself prove it skipped for the right reason.
  run largest_archived_spec "$empty"
  [ -z "$output" ]
  run largest_archived_spec "$TEST_DIR/does-not-exist"
  [ "$status" -ne 0 ]
}
