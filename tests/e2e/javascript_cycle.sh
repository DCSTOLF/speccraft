#!/usr/bin/env bash
# Spec 0010 e2e: drives speccraft-guard against a JS/TS project layout
# through the PreToolUse hook flow. Verifies the JS/TS sibling-test resolver
# (session-state only, not filesystem) and the __tests__/ directory convention.
#
# No JS runtime required — the fixture drives speccraft-guard via shell JSON
# on stdin, identical to python_cycle.sh and the Rust cycle scripts.
#
# Exit:
#   0  all assertions passed
#   1  setup failed
#   2  assertion failed

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK="$(mktemp -d -t js-cycle.XXXXXX)"

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

# ---- Build binaries ----
echo "==> Building speccraft-guard + speccraft-state..."
GUARD_BIN="$WORK/speccraft-guard"
STATE_BIN="$WORK/speccraft-state"
( cd "$REPO_ROOT/tools" && go build -o "$GUARD_BIN" ./cmd/speccraft-guard )
( cd "$REPO_ROOT/tools" && go build -o "$STATE_BIN" ./cmd/speccraft-state )

# ---- Scaffold project ----
PROJ="$WORK/proj"
mkdir -p "$PROJ/src" "$PROJ/src/__tests__" "$PROJ/.speccraft" \
         "$PROJ/specs/0010-javascript-typescript-support"

cat > "$PROJ/specs/0010-javascript-typescript-support/spec.md" <<'MD'
---
status: in-progress
---
# Spec
MD

reset_state() {
  cat > "$PROJ/.speccraft/state.json" <<JSON
{"version":1,"active_spec":"0010-javascript-typescript-support","session":{"id":"e2e","edited_test_files":[],"edited_prod_files":[]}}
JSON
}

hook_input() {
  local path="$1"
  cat <<JSON
{"tool_name":"Edit","tool_input":{"file_path":"$path","old_string":"","new_string":""},"cwd":"$PROJ"}
JSON
}

# ---- Scenario A: RED — production write rejected with no sibling test in session ----
echo "==> Scenario A: RED — no sibling test registered"
reset_state
touch "$PROJ/src/foo.ts"

set +e
out=$(hook_input "$PROJ/src/foo.ts" | "$GUARD_BIN" pre-tool-use 2>&1)
code=$?
set -e
[ "$code" -ne 0 ] || fail "Scenario A: expected non-zero exit, got 0; stderr: $out"
echo "$out" | grep -qF "no sibling test registered for" \
  || fail "Scenario A: stderr missing 'no sibling test registered for': $out"
note "rejection cites 'no sibling test registered for'"

# TypeScript-specific path
touch "$PROJ/src/handler.ts"
set +e
out=$(hook_input "$PROJ/src/handler.ts" | "$GUARD_BIN" pre-tool-use 2>&1)
code=$?
set -e
[ "$code" -ne 0 ] || fail "Scenario A (TS): expected non-zero exit, got 0"
note "TypeScript path also rejected"

# Session-only semantics: on-disk test does NOT satisfy the invariant
touch "$PROJ/src/foo.test.ts"  # exists on disk but not in session
set +e
out=$(hook_input "$PROJ/src/foo.ts" | "$GUARD_BIN" pre-tool-use 2>&1)
code=$?
set -e
[ "$code" -ne 0 ] \
  || fail "Scenario A (on-disk): on-disk test must not satisfy session-only check; got exit 0"
note "on-disk test does not satisfy session-only invariant"

# ---- Scenario B: GREEN — suffix sibling registered in session ----
echo "==> Scenario B: GREEN — foo.test.ts registered in session"
reset_state
touch "$PROJ/src/foo.ts"
touch "$PROJ/src/foo.test.ts"
( cd "$PROJ" && "$STATE_BIN" track-edit "$PROJ/src/foo.test.ts" )

set +e
out=$(hook_input "$PROJ/src/foo.ts" | "$GUARD_BIN" pre-tool-use 2>&1)
code=$?
set -e
[ "$code" -eq 0 ] \
  || fail "Scenario B: expected exit 0 after track-edit, got $code; stderr: $out"
note "production write allowed after suffix test registered"

# ---- Scenario C: GREEN — __tests__/ sibling registered in session ----
echo "==> Scenario C: GREEN — __tests__/handler.test.ts registered"
reset_state
touch "$PROJ/src/handler.ts"
mkdir -p "$PROJ/src/__tests__"
touch "$PROJ/src/__tests__/handler.test.ts"
( cd "$PROJ" && "$STATE_BIN" track-edit "$PROJ/src/__tests__/handler.test.ts" )

set +e
out=$(hook_input "$PROJ/src/handler.ts" | "$GUARD_BIN" pre-tool-use 2>&1)
code=$?
set -e
[ "$code" -eq 0 ] \
  || fail "Scenario C: expected exit 0 after __tests__ track-edit, got $code; stderr: $out"
note "__tests__/ sibling resolves correctly"

# ---- Scenario D: test file write always allowed ----
echo "==> Scenario D: test-file write always allowed"
reset_state

set +e
out=$(hook_input "$PROJ/src/foo.test.ts" | "$GUARD_BIN" pre-tool-use 2>&1)
code=$?
set -e
[ "$code" -eq 0 ] \
  || fail "Scenario D: test-file edit must always be allowed; got exit $code; stderr: $out"
note "test-file edit accepted with empty session state"

echo "OK: javascript_cycle e2e passed"
