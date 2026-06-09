#!/usr/bin/env bash
# End-to-end test for speccraft.
# Runs entirely inside the devcontainer. Creates a throwaway Go module,
# loads the speccraft plugin via --plugin-dir, drives the full lifecycle
# non-interactively via `claude -p`, and asserts on filesystem state.
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

# Resolve absolute path to this script's directory BEFORE any cd. The
# language-fixture invocations later need to invoke sibling scripts and
# can't rely on $BASH_SOURCE staying meaningful after `cd "$TEST_ROOT"`.
E2E_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---- flag parse (spec 0008 AC #2) ----
# `--language-only` skips the entire claude -p driven lifecycle and runs
# only the per-language fixture scripts (Rust + Python). Used by the
# e2e-language-only CI job which has no API credits and no
# ANTHROPIC_API_KEY. Single contract — one entrypoint, one flag.
LANGUAGE_ONLY=0
for arg in "$@"; do
  case "$arg" in
    --language-only) LANGUAGE_ONLY=1 ;;
    --help|-h)
      echo "usage: $0 [--language-only]"
      echo "  --language-only   skip the claude -p lifecycle; run only language fixtures (spec 0008)"
      exit 0
      ;;
    *)
      echo "unknown argument: $arg" >&2
      exit 1
      ;;
  esac
done

# >>> cargo-preamble (spec 0005 AC #9 — fail fast on missing Rust toolchain)
# The e2e harness exercises Rust fixtures (inline + integration cycles per
# AC #6); without cargo on PATH the assertions would misreport. Surface a
# clear message instead of letting downstream `cargo test` invocations
# fail with shell-not-found errors.
if ! command -v cargo >/dev/null 2>&1; then
  echo "cargo not found on PATH" >&2
  echo "  The speccraft e2e harness requires a Rust toolchain (rustup + cargo)." >&2
  echo "  Install via .devcontainer/setup.sh or 'curl --proto =https --tlsv1.2 -sSf https://sh.rustup.rs | sh'." >&2
  exit 1
fi
# <<< cargo-preamble

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

# ---- language-fixture runner (shared by lifecycle and --language-only) ----
# Spec 0008 AC #2 + AC #6: invokes the three language fixture scripts in
# hermetic subshells. Each fixture is self-contained (builds its own
# binaries into mktemp -d) and exits non-zero on assertion failure.
run_language_fixtures() {
  # Use the absolute E2E_DIR captured at script-start (before any cd).
  # Resolving $BASH_SOURCE here would fail because the script has
  # already cd'd into $TEST_ROOT.
  ( bash "$E2E_DIR/rust_inline_cycle.sh" )      || fail "rust_inline_cycle.sh failed"
  pass "rust_inline_cycle.sh"
  ( bash "$E2E_DIR/rust_integration_cycle.sh" ) || fail "rust_integration_cycle.sh failed"
  pass "rust_integration_cycle.sh"
  ( bash "$E2E_DIR/python_cycle.sh" )           || fail "python_cycle.sh failed"
  pass "python_cycle.sh"
  ( bash "$E2E_DIR/javascript_cycle.sh" )       || fail "javascript_cycle.sh failed"
  pass "javascript_cycle.sh"
}

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

classify_claude_failure() {
  # Spec 0008 AC #5: read combined claude -p output on stdin and emit
  # an "ENVIRONMENT_FAILURE: <category>" tag iff the output matches one
  # of the enumerated environmental failure modes. Empty string emitted
  # for unmatched failures (left to surface as ordinary assertion
  # failures). Categories are checked in priority order:
  #   credit_exhausted > auth > transient_api
  # so the most-specific signal wins when a log happens to contain
  # multiple matches.
  local content
  content="$(cat)"

  # credit_exhausted: literal Anthropic API error string.
  if printf '%s' "$content" | grep -qF -- 'Credit balance is too low'; then
    echo "ENVIRONMENT_FAILURE: credit_exhausted"
    return 0
  fi

  # auth: HTTP 401/403, missing/empty ANTHROPIC_API_KEY, or known
  # auth-error substrings (case-insensitive).
  if [ -z "${ANTHROPIC_API_KEY:-}" ] \
     || printf '%s' "$content" | grep -qE 'HTTP/[0-9.]+[[:space:]]+(401|403)\b' \
     || printf '%s' "$content" | grep -qE '\b(401|403)[[:space:]]+(Unauthorized|Forbidden)\b' \
     || printf '%s' "$content" | grep -qE 'status:[[:space:]]*(401|403)\b' \
     || printf '%s' "$content" | grep -qiF 'invalid x-api-key' \
     || printf '%s' "$content" | grep -qiF 'authentication failed' \
     || printf '%s' "$content" | grep -qiF 'unauthorized'; then
    echo "ENVIRONMENT_FAILURE: auth"
    return 0
  fi

  # transient_api: HTTP 5xx, HTTP 429, or transient-error substrings.
  if printf '%s' "$content" | grep -qE 'HTTP/[0-9.]+[[:space:]]+(5[0-9]{2}|429)\b' \
     || printf '%s' "$content" | grep -qE 'status:[[:space:]]*(5[0-9]{2}|429)\b' \
     || printf '%s' "$content" | grep -qiF 'network' \
     || printf '%s' "$content" | grep -qiF 'timeout' \
     || printf '%s' "$content" | grep -qiF 'connection refused'; then
    echo "ENVIRONMENT_FAILURE: transient_api"
    return 0
  fi

  # Unmatched — stays an unadorned assertion failure.
  return 0
}

run_claude() {
  local prompt="$1" log="$2"
  LAST_LOG="$log"
  echo "    > $prompt"
  "$CLAUDE_BIN" -p \
    --permission-mode bypassPermissions \
    --output-format text \
    --plugin-dir "$PLUGIN_DIR" \
    "$prompt" > "$LOG_DIR/$log" 2>&1 \
  || {
    echo "claude -p failed; log:"
    cat "$LOG_DIR/$log" >&2
    # Spec 0008 AC #5: tag enumerated environmental failures so CI logs
    # can distinguish env problems from real assertion failures.
    local tag
    tag="$(classify_claude_failure < "$LOG_DIR/$log")"
    if [ -n "$tag" ]; then
      echo "$tag" >&2
    fi
    exit 3
  }
}

# ---- --language-only short-circuit (spec 0008 AC #2) ----
# Skip the entire claude -p lifecycle. Run only the language fixtures
# and exit. The fixtures are self-contained; they don't need claude,
# ANTHROPIC_API_KEY, or the throwaway Go module.
if [ "$LANGUAGE_ONLY" = "1" ]; then
  echo "==> --language-only mode: skipping lifecycle, running language fixtures"
  run_language_fixtures
  echo
  echo "==> LANGUAGE-ONLY E2E PASSED"
  exit 0
fi

# ---- 1. Set up a throwaway Go module ----
echo "==> [1/9] Creating throwaway Go module"
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

# ---- 2. /speccraft:init ----
echo "==> [2/9] /speccraft:init"
run_claude "/speccraft:init. Use these answers when prompted: project='sample', stack='Go 1.22', layering='just main', top guardrails='no fmt.Println outside main; always handle errors; tests required for new code'." 02-init.log
exists ".speccraft/index.md"
exists ".speccraft/guardrails.md"
exists ".speccraft/architecture.md"
exists ".speccraft/conventions.md"
exists ".speccraft/history.md"
exists ".speccraft/agents.toml"
exists ".speccraft/state.json"
exists "specs/.gitkeep"
contains ".gitignore" ".speccraft/state.json"

# ---- 3. /speccraft:spec:new ----
echo "==> [3/9] /speccraft:spec:new"
run_claude "/speccraft:spec:new \"Add farewell function\". Answers: why='symmetry with greeting'; what='add farewell() that returns goodbye, called from main'; AC='1) farewell() returns \"goodbye\" 2) main prints both greeting and farewell 3) test covers farewell'; oos='internationalization'; questions=none." 03-new.log
SPEC_DIR="$(find specs -maxdepth 1 -name '0001-*' -type d 2>/dev/null | head -1)"
[ -n "$SPEC_DIR" ] || fail "spec dir 0001-* not created"
exists "$SPEC_DIR/spec.md"
status_is "$SPEC_DIR/spec.md" "draft"

# ---- 4. /speccraft:spec:review (with mock agents) ----
echo "==> [4/9] /speccraft:spec:review (mock agents)"
run_claude "/speccraft:spec:review --agents codex,opencode" 04-review.log
exists "$SPEC_DIR/review.md"

# ---- 5. /speccraft:spec:plan ----
echo "==> [5/9] /speccraft:spec:plan"
run_claude "/speccraft:spec:plan --skip-review" 05-plan.log
exists "$SPEC_DIR/plan.md"
exists "$SPEC_DIR/tasks.md"
status_is "$SPEC_DIR/spec.md" "planned"

# ---- 6. TDD invariant: write test first, then prod ----
echo "==> [6/9] TDD invariant"

# This should be ALLOWED (test edit first).
run_claude "Edit main_test.go to add a TestFarewell that asserts farewell() returns \"goodbye\". Just write the test, don't implement farewell yet." 06a-tdd-test.log
contains "main_test.go" "TestFarewell"

# This should be ALLOWED (production edit, but test was edited first this session).
run_claude "Now implement farewell() in main.go to return \"goodbye\", and update main() to also print farewell()." 06b-tdd-impl.log
contains "main.go" "farewell"
go test ./... >> "$LOG_DIR/06c-go-test.log" 2>&1 || fail "go test failed after implementation"
pass "go test passes"

# ---- 7. /speccraft:spec:close ----
echo "==> [7/9] /speccraft:spec:close"
run_claude "/speccraft:spec:close. Approve all proposed memory updates." 07-close.log
exists "$SPEC_DIR/changelog.md"
status_is "$SPEC_DIR/spec.md" "closed"
contains ".speccraft/history.md" "farewell"

# state.json should have cleared active_spec
ACTIVE="$(jq -r '.active_spec // "null"' .speccraft/state.json)"
[ "$ACTIVE" = "null" ] || fail "active_spec not cleared after close: $ACTIVE"
pass "active_spec cleared"

# ---- 8/10. Language dispatch (specs 0005 Rust + 0007 Python + 0010 JS/TS) ----
# Shared with the --language-only short-circuit above. Each fixture is
# CWD-independent and self-contained (builds binaries into mktemp -d,
# installs shims, runs hermetic assertions).
echo "==> [8/10] Rust dispatch (spec 0005)"
echo "==> [9/10] Python dispatch (spec 0007)"
echo "==> [10/10] JS/TS dispatch (spec 0010)"
run_language_fixtures

echo
echo "==> ALL E2E ASSERTIONS PASSED"
