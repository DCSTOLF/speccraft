#!/usr/bin/env bash
# Spec 0008 AC #2 — assert tests/e2e/run.sh --language-only runs the
# three language fixture scripts without invoking claude -p and without
# requiring ANTHROPIC_API_KEY.
#
# Strategy: invoke run.sh with --language-only under a stripped PATH and
# an unset ANTHROPIC_API_KEY. The fixture scripts (rust_*_cycle.sh,
# python_cycle.sh) build their own binaries and use cargo shims; they do
# not need claude. If --language-only is implemented correctly, the
# script never calls claude -p, so claude can be absent from PATH.
#
# Exit:
#   0 — all assertions pass
#   2 — assertion failed

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
RUNSH="$REPO_ROOT/tests/e2e/run.sh"

# Source cargo env if available (rustup install side-effect). A normal
# devcontainer shell does this via .profile; this assertion script may be
# invoked from a context that didn't.
# shellcheck disable=SC1091
[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"

fail() { echo "FAIL: $*" >&2; exit 2; }
note() { echo "  $*"; }

if [ ! -f "$RUNSH" ]; then
  fail "$RUNSH does not exist"
fi

# ---- Check 1: source-level — flag is mentioned ----
if ! grep -qF -- '--language-only' "$RUNSH"; then
  fail "$RUNSH does not mention --language-only flag"
fi
note "source-level: --language-only flag is present"

# ---- Check 2: functional — claude is shimmed; any invocation is recorded ----
# Prepend a temp dir with a `claude` shim that records calls to a log
# file. If --language-only honors its contract, the log stays empty.
# This is safer than stripping PATH (which would also remove bash, go,
# cargo, etc.). Mirrors the cargo-shim technique used in rust_*_cycle.sh.
SHIM_DIR="$(mktemp -d -t claude-shim.XXXXXX)"
trap 'rm -rf "$SHIM_DIR"' EXIT

cat > "$SHIM_DIR/claude" <<'SHIM'
#!/usr/bin/env bash
echo "$@" >> "${CLAUDE_SHIM_LOG:-/dev/null}"
exit 0
SHIM
chmod +x "$SHIM_DIR/claude"

CLAUDE_LOG="$SHIM_DIR/calls.log"
: > "$CLAUDE_LOG"

set +e
out=$(env -u ANTHROPIC_API_KEY \
      CLAUDE_SHIM_LOG="$CLAUDE_LOG" \
      PATH="$SHIM_DIR:$PATH" \
      bash "$RUNSH" --language-only 2>&1)
code=$?
set -e

# The shim's call log MUST be empty — --language-only must never invoke claude.
if [ -s "$CLAUDE_LOG" ]; then
  echo "claude shim recorded calls (should be zero):" >&2
  cat "$CLAUDE_LOG" >&2
  fail "--language-only invoked claude $(wc -l < "$CLAUDE_LOG") time(s); should be 0"
fi
note "claude shim recorded zero invocations"

if [ "$code" -ne 0 ]; then
  echo "$out"
  fail "run.sh --language-only exited $code (want 0); claude unavailable on PATH and ANTHROPIC_API_KEY unset"
fi
note "exit 0 with claude absent and ANTHROPIC_API_KEY unset"

# Each fixture must have produced its OK line.
if ! echo "$out" | grep -qF 'rust_inline_cycle e2e passed'; then
  fail "rust_inline_cycle.sh did not pass in --language-only mode"
fi
note "rust_inline_cycle invoked"

if ! echo "$out" | grep -qF 'rust_integration_cycle e2e passed'; then
  fail "rust_integration_cycle.sh did not pass in --language-only mode"
fi
note "rust_integration_cycle invoked"

if ! echo "$out" | grep -qF 'python_cycle e2e passed'; then
  fail "python_cycle.sh did not pass in --language-only mode"
fi
note "python_cycle invoked"

# The throwaway Go module from step [1/N] must NOT be created in
# language-only mode (it's part of the lifecycle path, per spec §What.2
# Note on Go).
if echo "$out" | grep -qF 'Creating throwaway Go module'; then
  fail "--language-only set up the throwaway Go module; lifecycle path should be skipped"
fi
note "throwaway Go module setup skipped (lifecycle path bypassed)"

# claude -p must not appear in any output line (its only valid call site
# is the lifecycle path; if it shows up, the skip is incomplete).
if echo "$out" | grep -qE 'claude\s+-p\b'; then
  fail "--language-only invoked claude -p somewhere; should be entirely skipped"
fi
note "claude -p never invoked"

echo "OK: tests/e2e/run.sh --language-only passes all AC #2 assertions"
