#!/usr/bin/env bash
# Spec 0018 e2e: drives speccraft-guard against a JS/TS project layout through
# the PreToolUse hook flow, exercising the RED→GREEN red-check (not the pre-0018
# session-membership touch-check). The JS/TS runner is the configured
# `[tdd.typescript] command`, a stub emitting controlled TAP, so the fixture is
# hermetic — no Node/vitest required.
#
# Verifies: a green/absent just-added test BLOCKS, a failing just-added test
# ALLOWS, an UNCONFIGURED runner fails closed (Decision D2), and test-file edits
# are always allowed (and capture just-added ids).
#
# Exit: 0 pass · 1 setup failed · 2 assertion failed

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK="$(mktemp -d -t js-cycle.XXXXXX)"

cleanup() {
  if [ "${KEEP_E2E:-0}" = "1" ]; then echo "==> Kept: $WORK"; else rm -rf "$WORK"; fi
}
trap cleanup EXIT

fail() { echo "FAIL: $*" >&2; exit 2; }
note() { echo "  $*"; }

# ---- Build binary ----
echo "==> Building speccraft-guard..."
GUARD_BIN="$WORK/speccraft-guard"
( cd "$REPO_ROOT/tools" && go build -o "$GUARD_BIN" ./cmd/speccraft-guard )

# ---- Stub TAP runner (controlled via env) ----
STUB="$WORK/fake_vitest"
cat > "$STUB" <<'SH'
#!/usr/bin/env bash
case "${FAKE_OUTCOME:-pass}" in
  fail)  echo "not ok 1 - ${FAKE_TEST:-brandnew}"; exit 1;;
  build) echo "SyntaxError: Unexpected token" >&2; exit 1;;
  *)     echo "ok 1 - ${FAKE_TEST:-brandnew}"; exit 0;;
esac
SH
chmod +x "$STUB"

# ---- Scaffold project ----
PROJ="$WORK/proj"
mkdir -p "$PROJ/src" "$PROJ/.speccraft" "$PROJ/specs/0018-technical-review"
cat > "$PROJ/specs/0018-technical-review/spec.md" <<'MD'
---
status: in-progress
---
# Spec
MD
printf 'export const x = 1;\n' > "$PROJ/src/foo.ts"
printf "test('old', () => {})\n" > "$PROJ/src/foo.test.ts"

# Configure the TS runner to the stub (JS shares the same adapter).
configure_runner() {
  cat > "$PROJ/.speccraft/speccraft.toml" <<TOML
[tdd.typescript]
command = "$STUB"
TOML
}
unconfigure_runner() { rm -f "$PROJ/.speccraft/speccraft.toml"; }

reset_state() {
  cat > "$PROJ/.speccraft/state.json" <<JSON
{"version":1,"active_spec":"0018-technical-review","session":{"id":"e2e","edited_test_files":[],"edited_prod_files":[]}}
JSON
}

guard_edit() {
  local path="$1" newstr="${2:-}"
  local json
  json=$(printf '{"tool_name":"Edit","tool_input":{"file_path":"%s","old_string":"","new_string":"%s"},"cwd":"%s"}' "$path" "$newstr" "$PROJ")
  set +e
  out=$(printf '%s' "$json" | "$GUARD_BIN" pre-tool-use 2>&1)
  code=$?
  set -e
}

capture_brandnew() {
  guard_edit "$PROJ/src/foo.test.ts" "test('old', () => {})\ntest('brandnew', () => {})\n"
  [ "$code" -eq 0 ] || fail "test-file edit must be allowed; got $code: $out"
}

# ---- Scenario A: RED missing — no just-added test → BLOCK ----
echo "==> A: no just-added test blocks the production edit"
configure_runner
reset_state
guard_edit "$PROJ/src/foo.ts"
[ "$code" -ne 0 ] || fail "A: expected block when nothing was just-added"
echo "$out" | grep -qF "add a failing test" || fail "A: missing 'add a failing test': $out"
note "blocked, prompts to add a failing test"

# ---- Scenario B: GREEN — failing just-added test → ALLOW ----
echo "==> B: failing just-added test allows the production edit"
configure_runner
reset_state
capture_brandnew
FAKE_OUTCOME=fail FAKE_TEST=brandnew guard_edit "$PROJ/src/foo.ts"
[ "$code" -eq 0 ] || fail "B: expected allow when just-added test fails; got $code: $out"
note "allowed on observed RED"

# ---- Scenario C: passing just-added test → BLOCK ----
echo "==> C: passing just-added test blocks (no observed failure)"
configure_runner
reset_state
capture_brandnew
FAKE_OUTCOME=pass FAKE_TEST=brandnew guard_edit "$PROJ/src/foo.ts"
[ "$code" -ne 0 ] || fail "C: expected block when just-added test passes"
echo "$out" | grep -qF "no failing test observed" || fail "C: missing 'no failing test observed': $out"
note "blocked: green is not RED"

# ---- Scenario D: unconfigured runner → FAIL CLOSED (Decision D2) ----
echo "==> D: unconfigured JS/TS runner fails closed"
unconfigure_runner
reset_state
capture_brandnew
guard_edit "$PROJ/src/foo.ts"
[ "$code" -ne 0 ] || fail "D: expected fail-closed block with no configured runner"
echo "$out" | grep -qF "no test runner available" || fail "D: missing 'no test runner available': $out"
note "blocked: unconfigured runner fails closed (never falls back to touch-check)"

# ---- Scenario E: test-file edit always allowed ----
echo "==> E: test-file edit always allowed"
configure_runner
reset_state
guard_edit "$PROJ/src/foo.test.ts"
[ "$code" -eq 0 ] || fail "E: test-file edit must always be allowed; got $code: $out"
note "test-file edit accepted"

echo "OK: javascript_cycle e2e passed (spec 0018 red-check)"
