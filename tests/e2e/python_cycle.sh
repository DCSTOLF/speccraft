#!/usr/bin/env bash
# Spec 0007 e2e: drives speccraft-guard against a Python project layout
# through the full PreToolUse hook flow. Exercises the sibling-test
# heuristic (spec 0002) and the separate-tree resolver (spec 0003) and
# verifies the always-allowed paths for test files (covers AC #5).
#
# Strategy: build speccraft-guard + speccraft-state, scaffold a temp
# Python project with src/ and tests/, then drive the guard via Claude
# Code hook JSON on stdin. Assert exit codes and stderr substrings.
# No external runner involved — Python's TDD invariant is pure
# file-classification + session-state lookup.
#
# fail() uses exit 2 to match the Rust scripts' convention; this is what
# AC #7 in the spec requires. To verify locally: induce a controlled
# failure (change an expected substring), run the script, observe $? == 2.
#
# Exit:
#   0  all assertions passed
#   1  setup failed
#   2  assertion failed

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK="$(mktemp -d -t python-cycle.XXXXXX)"

cleanup() {
  if [ "${KEEP_E2E:-0}" = "1" ]; then
    echo "==> Kept: $WORK"
  else
    rm -rf "$WORK"
  fi
}
trap cleanup EXIT

fail() { echo "FAIL: $*" >&2; exit 2; }
note() { echo "  $*"; }

# ---- T2: build both binaries ----
echo "==> Building speccraft-guard + speccraft-state..."
GUARD_BIN="$WORK/speccraft-guard"
STATE_BIN="$WORK/speccraft-state"
( cd "$REPO_ROOT/tools" && go build -o "$GUARD_BIN" ./cmd/speccraft-guard )
( cd "$REPO_ROOT/tools" && go build -o "$STATE_BIN" ./cmd/speccraft-state )

# ---- T3: shared Python project fixture ----
PROJ="$WORK/proj"
mkdir -p "$PROJ/src" "$PROJ/tests" "$PROJ/.speccraft" \
         "$PROJ/specs/0007-python-e2e-fixture"

# Sibling pair (AC #2)
cat > "$PROJ/src/foo.py" <<'PY'
def foo():
    return "foo"
PY
cat > "$PROJ/src/test_foo.py" <<'PY'
from foo import foo
def test_foo():
    assert foo() == "foo"
PY

# Separate-tree pair (AC #3). NOTE: place bar.py in a subdirectory that
# contains no test_*.py / *_test.py files. Tier 1 of SiblingTestFiles
# is a dir-glob, not a name-stem match: it returns ALL `test_*.py` /
# `*_test.py` in the same directory. If we colocated bar.py with the
# AC #2 fixture (src/test_foo.py), tier 1 would pick up test_foo.py and
# tier 2 (separate-tree walk) would never fire — masking the AC #3
# behavior we're trying to verify.
mkdir -p "$PROJ/src/pkg"
cat > "$PROJ/src/pkg/bar.py" <<'PY'
def bar():
    return "bar"
PY
cat > "$PROJ/tests/test_bar.py" <<'PY'
import sys; sys.path.append("src/pkg")
from bar import bar
def test_bar():
    assert bar() == "bar"
PY

# No-test-anywhere subdir (AC #4) — same reasoning: keep orphan.py away
# from any test_*.py glob.
mkdir -p "$PROJ/src/loners"

# No-test-anywhere file (AC #4) — lives in src/loners/, no test_*.py
# nearby, no matching tests/test_orphan.py either.
cat > "$PROJ/src/loners/orphan.py" <<'PY'
def orphan():
    return "orphan"
PY

# Active spec + in-progress status so the guard's status check passes.
cat > "$PROJ/specs/0007-python-e2e-fixture/spec.md" <<'MD'
---
status: in-progress
---
# Spec
MD

# Fresh state.json builder — used to reset between scenarios so each AC
# is independent of the others (spec doesn't say so explicitly; this is
# the planner's correctness fix flagged in the spec's open questions).
reset_state() {
  cat > "$PROJ/.speccraft/state.json" <<JSON
{"version":1,"active_spec":"0007-python-e2e-fixture","session":{"id":"e2e","edited_test_files":[],"edited_prod_files":[]}}
JSON
}

# hook_input emits the Claude Code PreToolUse hook JSON envelope for the
# given absolute file path. The guard reads tool_input.file_path and cwd.
hook_input() {
  local path="$1"
  cat <<JSON
{"tool_name":"Edit","tool_input":{"file_path":"$path","old_string":"","new_string":""},"cwd":"$PROJ"}
JSON
}

# ---- T4: AC #2 tier-1 sibling — rejection then acceptance ----
echo "==> AC #2 tier-1 sibling reject/accept (src/test_foo.py beside src/foo.py)"
reset_state

set +e
out=$(hook_input "$PROJ/src/foo.py" | "$GUARD_BIN" pre-tool-use 2>&1)
code=$?
set -e
[ "$code" -ne 0 ] || fail "AC #2 reject: expected non-zero, got 0; stderr was: $out"
echo "$out" | grep -qF "test_foo.py" \
  || fail "AC #2 reject: stderr does not name test_foo.py: $out"
note "rejection cites test_foo.py"

# Acceptance after track-edit. The guard compares filepath.Abs(sibling)
# against state.Session.EditedTestFiles, so invoke track-edit from inside
# $PROJ (per the planner's risk-mitigation note).
( cd "$PROJ" && "$STATE_BIN" track-edit "$PROJ/src/test_foo.py" )

set +e
out=$(hook_input "$PROJ/src/foo.py" | "$GUARD_BIN" pre-tool-use 2>&1)
code=$?
set -e
[ "$code" -eq 0 ] \
  || fail "AC #2 accept: expected exit 0 after track-edit, got $code; stderr: $out"
note "acceptance after track-edit"

# ---- T5: AC #3 tier-2 separate `tests/` tree — rejection then acceptance ----
echo "==> AC #3 tier-2 separate-tree reject/accept (tests/test_bar.py for src/bar.py)"
cat > "$PROJ/.speccraft/speccraft.toml" <<'TOML'
[tdd]
test_roots = ["tests"]
TOML
reset_state

set +e
out=$(hook_input "$PROJ/src/pkg/bar.py" | "$GUARD_BIN" pre-tool-use 2>&1)
code=$?
set -e
[ "$code" -ne 0 ] \
  || fail "AC #3 reject: expected non-zero, got 0; stderr: $out"
echo "$out" | grep -qF "test_bar.py" \
  || fail "AC #3 reject: stderr does not name test_bar.py: $out"
note "rejection cites tests/test_bar.py"

( cd "$PROJ" && "$STATE_BIN" track-edit "$PROJ/tests/test_bar.py" )

set +e
out=$(hook_input "$PROJ/src/pkg/bar.py" | "$GUARD_BIN" pre-tool-use 2>&1)
code=$?
set -e
[ "$code" -eq 0 ] \
  || fail "AC #3 accept: expected exit 0 after track-edit, got $code; stderr: $out"
note "acceptance after track-edit"

# ---- T6: AC #4 no-test-anywhere — rejection cites (none found) ----
echo "==> AC #4 no-test-anywhere — rejection with '(none found)'"
reset_state

set +e
out=$(hook_input "$PROJ/src/loners/orphan.py" | "$GUARD_BIN" pre-tool-use 2>&1)
code=$?
set -e
[ "$code" -ne 0 ] \
  || fail "AC #4: expected non-zero, got 0; stderr: $out"
# See goPythonProdGuard in tools/cmd/speccraft-guard/main.go — emits the
# literal '(none found)' when SiblingTestFiles returns an empty list.
echo "$out" | grep -qF "(none found)" \
  || fail "AC #4: stderr does not contain literal '(none found)': $out"
note "rejection cites (none found)"

# ---- T7: AC #5 test-file always-allowed regardless of session state ----
echo "==> AC #5 test-file always-allowed (src/test_foo.py)"
reset_state

set +e
out=$(hook_input "$PROJ/src/test_foo.py" | "$GUARD_BIN" pre-tool-use 2>&1)
code=$?
set -e
[ "$code" -eq 0 ] \
  || fail "AC #5: hook on a test file must always accept (no prior track-edit); got exit $code; stderr: $out"
note "test-file edit accepted with empty session state"

echo "OK: python_cycle e2e passed"
