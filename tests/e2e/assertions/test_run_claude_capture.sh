#!/usr/bin/env bash
# Spec 0008 AC #5 probe — pin run_claude's stdout+stderr capture shape.
#
# The ENVIRONMENT_FAILURE classifier (AC #5 GREEN) needs to grep the
# combined stdout+stderr of `claude -p` for known error substrings. If
# run_claude only captures stdout, half the matchers (HTTP codes printed
# to stderr) would silently miss. This probe pins the current shape so
# refactors that change it surface immediately.
#
# Exit: 0 pass, 2 fail.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
RUNSH="$REPO_ROOT/tests/e2e/run.sh"

fail() { echo "FAIL: $*" >&2; exit 2; }
note() { echo "  $*"; }

# Extract run_claude's body. awk over the function block.
BODY="$(awk '
  /^run_claude\(\) \{/ { inside=1; print; next }
  inside && /^\}/ { print; exit }
  inside { print }
' "$RUNSH")"

if [ -z "$BODY" ]; then
  fail "run_claude() not found in $RUNSH"
fi

# 1. claude -p output redirected to a log file
if ! echo "$BODY" | grep -qE '"\$CLAUDE_BIN"[[:space:]]+-p'; then
  fail "run_claude does not invoke \"\$CLAUDE_BIN\" -p (shape changed?)"
fi
note "run_claude invokes \"\$CLAUDE_BIN\" -p"

# 2. Combined stdout+stderr capture: `> "$LOG_DIR/$log" 2>&1`
if ! echo "$BODY" | grep -qE '>[[:space:]]*"\$LOG_DIR/\$log"[[:space:]]+2>&1'; then
  fail "run_claude does not capture combined stdout+stderr via > \"\$LOG_DIR/\$log\" 2>&1"
  fail "AC #5 classifier requires combined output; refusing to proceed"
fi
note "stdout+stderr combined into \$LOG_DIR/\$log via 2>&1"

# 3. Failure path: log cat'd to stderr + exit 3
if ! echo "$BODY" | grep -qE 'claude -p failed'; then
  fail "run_claude failure path does not announce 'claude -p failed'"
fi
if ! echo "$BODY" | grep -qE 'exit[[:space:]]+3'; then
  fail "run_claude failure path does not exit 3"
fi
note "failure path: announces 'claude -p failed' + exits 3"

# 4. Explicit model selection: `--model "${CLAUDE_MODEL:-claude-sonnet-4-6}"`
# (spec 0017 AC1). The `${VAR:-default}` form covers AC2 (override) and AC3
# (default) by Bash parameter-expansion semantics — no behavioral test needed.
if ! echo "$BODY" | grep -qE -- '--model[[:space:]]+"\$\{CLAUDE_MODEL:-claude-sonnet-4-6\}"'; then
  fail "run_claude does not pass --model \"\${CLAUDE_MODEL:-claude-sonnet-4-6}\" (spec 0017 AC1)"
fi
note "model selection: --model \"\${CLAUDE_MODEL:-claude-sonnet-4-6}\" (overridable, defaults to Sonnet)"

echo "OK: run_claude capture shape pinned (combined stdout+stderr, exit 3 on fail, explicit model)"
