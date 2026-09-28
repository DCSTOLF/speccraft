# FORBIDDEN FIXTURE — spec 0052. Not a suite; never run by bats.
#
# Bite proof for the skip-ordering guard in tests/hooks/spec-review-payload.bats.
# `source "$LIB"` enables `set -euo pipefail` in the test shell, and under
# `set -u` bats 1.2.1's skip path dies on an unbound BATS_TEARDOWN_STARTED — so a
# test that sources the lib and THEN skips ERRORS instead of skipping. AC17's
# stated skip shipped with exactly this ordering and would have hard-failed on a
# fresh clone, where it is the only thing standing between "no archive" and a red
# suite.

@test "a well-ordered test: the skip decision comes first" {
  [ -d "$SOMETHING" ] || skip "stated reason"
  source "$LIB"
  run true
}

@test "the forbidden ordering: source first, then skip" {
  source "$LIB"
  [ -d "$SOMETHING" ] || skip "this never prints — the test ERRORS instead"
  run true
}
