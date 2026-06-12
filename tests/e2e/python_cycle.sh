#!/usr/bin/env bash
# Spec 0018 e2e: drives speccraft-guard against a Python project layout through
# the PreToolUse hook flow, exercising the RED→GREEN red-check (not the pre-0018
# touch-check). The Python runner is a configured stub (`[tdd.python] command`)
# emitting controlled pytest-style output, so the fixture is hermetic — no real
# pytest/python runtime required (mirrors the Rust fixture's cargo shim).
#
# Verifies: a green/absent just-added test BLOCKS, a failing just-added test
# ALLOWS, a collection error BLOCKS distinctly, and test-file edits are always
# allowed (and capture just-added ids).
#
# Exit: 0 pass · 1 setup failed · 2 assertion failed

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK="$(mktemp -d -t python-cycle.XXXXXX)"

cleanup() {
  if [ "${KEEP_E2E:-0}" = "1" ]; then echo "==> Kept: $WORK"; else rm -rf "$WORK"; fi
}
trap cleanup EXIT

fail() { echo "FAIL: $*" >&2; exit 2; }
note() { echo "  $*"; }

# ---- Build binaries ----
echo "==> Building speccraft-guard..."
GUARD_BIN="$WORK/speccraft-guard"
( cd "$REPO_ROOT/tools" && go build -o "$GUARD_BIN" ./cmd/speccraft-guard )

# ---- Stub pytest runner (controlled via env) ----
STUB="$WORK/fake_pytest"
cat > "$STUB" <<'SH'
#!/usr/bin/env bash
case "${FAKE_OUTCOME:-pass}" in
  fail)  echo "t.py::${FAKE_TEST:-test_new} FAILED [100%]"; exit 1;;
  build) echo "ERROR collecting t.py" >&2; exit 2;;
  *)     echo "t.py::${FAKE_TEST:-test_new} PASSED [100%]"; exit 0;;
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
cat > "$PROJ/.speccraft/speccraft.toml" <<TOML
[tdd.python]
command = "$STUB"
TOML
printf 'def existing():\n    return 1\n' > "$PROJ/src/foo.py"
printf 'def test_old():\n    assert True\n' > "$PROJ/src/test_foo.py"

reset_state() {
  cat > "$PROJ/.speccraft/state.json" <<JSON
{"version":1,"active_spec":"0018-technical-review","session":{"id":"e2e","edited_test_files":[],"edited_prod_files":[]}}
JSON
}

# guard_edit PATH [NEW_STRING_JSON] — drive a PreToolUse Edit through the guard.
# Returns the guard's exit code in $code and combined output in $out.
guard_edit() {
  local path="$1" newstr="${2:-}"
  local json
  json=$(printf '{"tool_name":"Edit","tool_input":{"file_path":"%s","old_string":"","new_string":"%s"},"cwd":"%s"}' "$path" "$newstr" "$PROJ")
  set +e
  out=$(printf '%s' "$json" | "$GUARD_BIN" pre-tool-use 2>&1)
  code=$?
  set -e
}

# capture_test_new — edit the sibling test file adding test_new (RED), so the
# guard captures it into the session's just-added set.
capture_test_new() {
  guard_edit "$PROJ/src/test_foo.py" 'def test_old():\n    assert True\n\ndef test_new():\n    assert False\n'
  [ "$code" -eq 0 ] || fail "test-file edit must be allowed; got $code: $out"
}

# ---- Scenario A: RED missing — no just-added test → BLOCK ----
echo "==> A: no just-added test blocks the production edit"
reset_state
guard_edit "$PROJ/src/foo.py"
[ "$code" -ne 0 ] || fail "A: expected block when nothing was just-added"
echo "$out" | grep -qF "add a failing test" || fail "A: missing 'add a failing test': $out"
note "blocked, prompts to add a failing test"

# ---- Scenario B: GREEN — failing just-added test → ALLOW ----
echo "==> B: failing just-added test allows the production edit"
reset_state
capture_test_new
FAKE_OUTCOME=fail FAKE_TEST=test_new guard_edit "$PROJ/src/foo.py"
[ "$code" -eq 0 ] || fail "B: expected allow when just-added test fails; got $code: $out"
note "allowed on observed RED"

# ---- Scenario C: passing just-added test → BLOCK ----
echo "==> C: passing just-added test blocks (no observed failure)"
reset_state
capture_test_new
FAKE_OUTCOME=pass FAKE_TEST=test_new guard_edit "$PROJ/src/foo.py"
[ "$code" -ne 0 ] || fail "C: expected block when just-added test passes"
echo "$out" | grep -qF "no failing test observed" || fail "C: missing 'no failing test observed': $out"
note "blocked: green is not RED"

# ---- Scenario D: collection error → BLOCK distinctly ----
echo "==> D: collection/build error blocks distinctly from missing RED"
reset_state
capture_test_new
FAKE_OUTCOME=build FAKE_TEST=test_new guard_edit "$PROJ/src/foo.py"
[ "$code" -ne 0 ] || fail "D: expected block on collection error"
echo "$out" | grep -qF "build/collection failed" || fail "D: missing 'build/collection failed': $out"
note "blocked: build/collection failure is not a valid RED"

# ---- Scenario E: test-file edit always allowed ----
echo "==> E: test-file edit always allowed"
reset_state
guard_edit "$PROJ/src/test_foo.py"
[ "$code" -eq 0 ] || fail "E: test-file edit must always be allowed; got $code: $out"
note "test-file edit accepted"

echo "OK: python_cycle e2e passed (spec 0018 red-check)"
