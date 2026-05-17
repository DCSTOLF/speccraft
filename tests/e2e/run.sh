#!/usr/bin/env bash
# End-to-end test for speccraft.
# Runs entirely inside the devcontainer. Creates a throwaway Go module,
# installs the plugin, drives the full lifecycle non-interactively via
# `claude -p`, and asserts on filesystem state.
#
# Hermetic: uses mock aux agents installed by .devcontainer/setup.sh.
# No network calls beyond Claude Code's own inference traffic.
#
# Run from repo root inside the devcontainer:
#   bash tests/e2e/run.sh
#
# Exit codes:
#   0  all assertions passed
#   1  setup failed
#   2  assertion failed
#   3  claude -p failed
set -euo pipefail

# ---- config ----
TEST_ROOT="${TEST_ROOT:-/tmp/speccraft-e2e-$$}"
PLUGIN_DIR="${PLUGIN_DIR:-$(pwd)}"
LOG_DIR="$TEST_ROOT/.logs"
CLAUDE_BIN="${CLAUDE_BIN:-claude}"

cleanup() {
  if [ "${KEEP_TEST_DIR:-0}" = "1" ]; then
    echo "==> Test dir kept: $TEST_ROOT"
  else
    rm -rf "$TEST_ROOT"
  fi
}
trap cleanup EXIT

mkdir -p "$LOG_DIR"
cd "$TEST_ROOT"

echo "==> Test root: $TEST_ROOT"
echo "==> Plugin:    $PLUGIN_DIR"
echo "==> Logs:      $LOG_DIR"

# ---- assertion helpers ----
LAST_LOG=""
fail() {
  echo "FAIL: $*" >&2
  if [ -n "$LAST_LOG" ] && [ -f "$LOG_DIR/$LAST_LOG" ]; then
    echo "--- last claude log ($LAST_LOG) ---" >&2
    cat "$LOG_DIR/$LAST_LOG" >&2
    echo "--- end log ---" >&2
  fi
  exit 2
}
pass()   { echo "PASS: $*"; }
exists() { [ -e "$1" ] || fail "expected to exist: $1"; pass "exists $1"; }
contains() {
  grep -qF "$2" "$1" || fail "expected '$2' in $1"
  pass "contains $1: $2"
}
status_is() {
  local f="$1" want="$2"
  grep -q "^status: $want" "$f" || fail "expected status:$want in $f"
  pass "status=$want in $f"
}

run_claude() {
  local prompt="$1" log="$2"
  LAST_LOG="$log"
  echo "    > $prompt"
  "$CLAUDE_BIN" -p \
    --permission-mode bypassPermissions \
    --output-format text \
    "$prompt" > "$LOG_DIR/$log" 2>&1 \
  || { echo "claude -p failed; log:"; cat "$LOG_DIR/$log" >&2; exit 3; }
}

# ---- 1. Set up a throwaway Go module ----
echo "==> [1/8] Creating throwaway Go module"
git init -q
go mod init example.com/sample >/dev/null
cat > main.go <<'GO'
package main

import "fmt"

func main() { fmt.Println(greeting()) }
func greeting() string { return "hello" }
GO
cat > main_test.go <<'GO'
package main

import "testing"

func TestGreeting(t *testing.T) {
    if greeting() != "hello" { t.Fatal("wrong greeting") }
}
GO
git config user.email "ci@speccraft.test"
git config user.name "speccraft CI"
git add . && git commit -qm "initial"

# ---- 2. Install plugin from local path ----
echo "==> [2/8] Installing speccraft plugin from $PLUGIN_DIR"
run_claude "/plugin marketplace add $PLUGIN_DIR" 01-plugin-add.log
run_claude "/plugin install speccraft@speccraft" 02-plugin-install.log

# ---- 3. /speccraft:init ----
echo "==> [3/8] /speccraft:init"
run_claude "/speccraft:init. Use these answers when prompted: project='sample', stack='Go 1.22', layering='just main', top guardrails='no fmt.Println outside main; always handle errors; tests required for new code'." 03-init.log
exists ".speccraft/index.md"
exists ".speccraft/guardrails.md"
exists ".speccraft/architecture.md"
exists ".speccraft/conventions.md"
exists ".speccraft/history.md"
exists ".speccraft/agents.toml"
exists ".speccraft/state.json"
exists "specs/.gitkeep"
contains ".gitignore" ".speccraft/state.json"

# ---- 4. /spec:new ----
echo "==> [4/8] /spec:new"
run_claude "/spec:new \"Add farewell function\". Answers: why='symmetry with greeting'; what='add farewell() that returns goodbye, called from main'; AC='1) farewell() returns \\\"goodbye\\\" 2) main prints both greeting and farewell 3) test covers farewell'; oos='internationalization'; questions=none." 04-new.log
SPEC_DIR="$(ls -d specs/0001-* 2>/dev/null | head -1)"
[ -n "$SPEC_DIR" ] || fail "spec dir 0001-* not created"
exists "$SPEC_DIR/spec.md"
status_is "$SPEC_DIR/spec.md" "draft"

# ---- 5. /spec:review (with mock agents) ----
echo "==> [5/8] /spec:review (mock agents)"
run_claude "/spec:review --agents codex,opencode" 05-review.log
exists "$SPEC_DIR/review.md"

# ---- 6. /spec:plan ----
echo "==> [6/8] /spec:plan"
run_claude "/spec:plan --skip-review" 06-plan.log
exists "$SPEC_DIR/plan.md"
exists "$SPEC_DIR/tasks.md"
status_is "$SPEC_DIR/spec.md" "planned"

# ---- 7. TDD invariant: write test first, then prod ----
echo "==> [7/8] TDD invariant"

# This should be ALLOWED (test edit first).
run_claude "Edit main_test.go to add a TestFarewell that asserts farewell() returns \"goodbye\". Just write the test, don't implement farewell yet." 07a-tdd-test.log
contains "main_test.go" "TestFarewell"

# This should be ALLOWED (production edit, but test was edited first this session).
run_claude "Now implement farewell() in main.go to return \"goodbye\", and update main() to also print farewell()." 07b-tdd-impl.log
contains "main.go" "farewell"
go test ./... >> "$LOG_DIR/07c-go-test.log" 2>&1 || fail "go test failed after implementation"
pass "go test passes"

# ---- 8. /spec:close ----
echo "==> [8/8] /spec:close"
run_claude "/spec:close. Approve all proposed memory updates." 08-close.log
exists "$SPEC_DIR/changelog.md"
status_is "$SPEC_DIR/spec.md" "closed"
contains ".speccraft/history.md" "farewell"

# state.json should have cleared active_spec
ACTIVE="$(jq -r '.active_spec // "null"' .speccraft/state.json)"
[ "$ACTIVE" = "null" ] || fail "active_spec not cleared after close: $ACTIVE"
pass "active_spec cleared"

echo
echo "==> ALL E2E ASSERTIONS PASSED"
