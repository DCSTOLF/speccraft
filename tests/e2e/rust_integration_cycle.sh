#!/usr/bin/env bash
# Spec 0005 AC #6 e2e: full red→green cycle for the INTEGRATION-test
# path. Mirrors rust_inline_cycle.sh but operates on tests/<stem>.rs.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK="$(mktemp -d -t rust-integration-cycle.XXXXXX)"
SHIM_DIR="$WORK/shim"
CRATE="$WORK/crate"
GUARD_BIN="$WORK/speccraft-guard"

cleanup() {
  if [ "${KEEP_E2E:-0}" = "1" ]; then
    echo "==> Kept: $WORK"
  else
    rm -rf "$WORK"
  fi
}
trap cleanup EXIT

fail() { echo "FAIL: $*" >&2; exit 2; }

echo "==> Building speccraft-guard..."
( cd "$REPO_ROOT/tools" && go build -o "$GUARD_BIN" ./cmd/speccraft-guard )

# Cargo shim
mkdir -p "$SHIM_DIR"
cat > "$SHIM_DIR/cargo" <<'SHIM'
#!/usr/bin/env bash
LOG="${CARGO_SHIM_LOG:-/dev/null}"
echo "$@" >> "$LOG"
exit 0
SHIM
chmod +x "$SHIM_DIR/cargo"
export CARGO_SHIM_LOG="$WORK/cargo-invocations.log"
: > "$CARGO_SHIM_LOG"
export PATH="$SHIM_DIR:$PATH"

# Crate fixture with integration test directory.
mkdir -p "$CRATE/src" "$CRATE/tests" "$CRATE/.speccraft" "$CRATE/specs/0005-rust-language-support"
cat > "$CRATE/Cargo.toml" <<TOML
[package]
name = "fixture"
version = "0.1.0"
edition = "2021"
TOML
cat > "$CRATE/src/lib.rs" <<RUST
pub fn alpha() -> i32 { 42 }
RUST
cat > "$CRATE/.speccraft/state.json" <<JSON
{"version":1,"active_spec":"0005-rust-language-support","session":{"id":"e2e","edited_test_files":[],"edited_prod_files":[]}}
JSON
cat > "$CRATE/specs/0005-rust-language-support/spec.md" <<MD
---
status: in-progress
---
# Spec
MD

# Step 1: initial-capture on a no-test fixture.
echo "==> Step 1: initial-capture invocation (integration path)"
INIT_INPUT=$(cat <<JSON
{
  "tool_name": "Edit",
  "tool_input": {
    "file_path": "$CRATE/src/lib.rs",
    "old_string": "pub fn alpha() -> i32 { 42 }",
    "new_string": "pub fn alpha() -> i32 { 42 }"
  },
  "cwd": "$CRATE"
}
JSON
)
if ! out=$(echo "$INIT_INPUT" | "$GUARD_BIN" pre-tool-use 2>&1); then
  echo "$out"
  fail "initial-capture rejected; should accept"
fi
echo "  stderr: $out" | head -1

# Step 2: create an integration test file via Write tool.
echo "==> Step 2: write tests/foo.rs (integration test)"
cat > "$CRATE/tests/foo.rs" <<RUST
fn it_works() {}
RUST
EDIT_INPUT=$(cat <<JSON
{
  "tool_name": "Write",
  "tool_input": {
    "file_path": "$CRATE/tests/foo.rs",
    "old_string": "",
    "new_string": "fn it_works() {}\n"
  },
  "cwd": "$CRATE"
}
JSON
)
set +e
out2=$(echo "$EDIT_INPUT" | "$GUARD_BIN" pre-tool-use 2>&1)
code2=$?
set -e
# Shim returns empty stdout → OutcomeAllPassed → reject "no failing test observed".
if [ "$code2" -eq 0 ]; then
  fail "expected rejection from shim-only path"
fi
if ! echo "$out2" | grep -q "no failing test observed"; then
  fail "expected 'no failing test observed' rejection, got: $out2"
fi

echo "OK: rust_integration_cycle e2e passed"
