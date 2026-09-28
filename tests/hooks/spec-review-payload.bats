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
