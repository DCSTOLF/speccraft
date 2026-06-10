#!/usr/bin/env bash
# tests/e2e/lib.sh — shared assertion helpers for the e2e harness and
# any sibling fixture under tests/e2e/. Sourced, not executed.
#
# Introduced by spec 0014 to give run.sh and the new
# contains_adr_assertion_test.sh fixture the *exact same* predicate
# implementations — the fixture's "exact predicate" invariant breaks if
# helpers drift between the two sites.
#
# Note: `set -euo pipefail` here mutates the sourcing shell. Both
# tests/e2e/run.sh and contains_adr_assertion_test.sh already set this
# at top, so re-application is a no-op for them. A future caller that
# intentionally has these off would need to re-toggle after sourcing.
set -euo pipefail

# fail prints an assertion failure to stderr and exits 2.
#
# When called from tests/e2e/run.sh in lifecycle context, $LAST_LOG and
# $LOG_DIR identify the most recent claude -p invocation log; we dump
# it to stderr to aid debugging. When called from a sibling fixture
# (e.g. contains_adr_assertion_test.sh) neither variable is set, so the
# guard below skips the log dump. `${VAR:-}` default-empty expansion
# keeps this safe under `set -u`.
fail() {
  echo "FAIL: $*" >&2
  if [ -n "${LAST_LOG:-}" ] && [ -n "${LOG_DIR:-}" ] && [ -f "$LOG_DIR/$LAST_LOG" ]; then
    echo "--- last claude log ($LAST_LOG) ---" >&2
    cat "$LOG_DIR/$LAST_LOG" >&2
    echo "--- end log ---" >&2
  fi
  exit 2
}

pass()   { echo "PASS: $*"; }
exists() { [ -e "$1" ] || fail "expected to exist: $1"; pass "exists $1"; }

# contains: fixed-string match (grep -qF). Unchanged from run.sh's
# pre-spec-0014 definition.
contains() {
  grep -qF "$2" "$1" || fail "expected '$2' in $1"
  pass "contains $1: $2"
}

# contains_regex: extended-regex match (grep -qE). Introduced by spec
# 0014 to express the anchored ADR date-header pattern at run.sh's
# [7/9] /speccraft:spec:close assertion. Sibling to contains; pick
# fixed-string vs regex explicitly at the call site rather than
# overloading contains with a flag.
contains_regex() {
  grep -qE "$2" "$1" || fail "expected regex '$2' in $1"
  pass "contains_regex $1: $2"
}

status_is() {
  local f="$1" want="$2"
  grep -q "^status: $want" "$f" || fail "expected status:$want in $f"
  pass "status=$want in $f"
}
