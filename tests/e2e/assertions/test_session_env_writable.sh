#!/usr/bin/env bash
# Spec 0008 AC #1 — probe + assert ~/.claude/session-env writability.
#
# Probes ownership and mode of /home/vscode/.claude (and the nested
# session-env directory if present) and asserts the container user can
# create session-env/probe. Designed to run inside the devcontainer —
# CI invokes via `devcontainer exec ... bash tests/e2e/assertions/test_session_env_writable.sh`;
# locally, just run it directly.
#
# Output is intentionally verbose: spec 0008 §Open questions item 2 says
# the implementer "should probe at start time and document the actual
# root cause in the changelog." This script's stdout IS that
# documentation — pipe to a log file for the changelog entry.
#
# Exit:
#   0 — directory writable, owner matches runner uid
#   2 — assertion failed (EACCES, ownership mismatch, or stat error)

set -euo pipefail

CLAUDE_DIR="${HOME}/.claude"
SESSION_ENV="${CLAUDE_DIR}/session-env"
RUNNER_UID="$(id -u)"
RUNNER_GID="$(id -g)"
RUNNER_USER="$(id -un)"

fail() { echo "FAIL: $*" >&2; exit 2; }
note() { echo "  $*"; }

# ---- Probe block (always emitted, even on success — feeds the changelog) ----
echo "==> AC #1 probe — ~/.claude ownership/mode"
note "runner: uid=${RUNNER_UID} gid=${RUNNER_GID} user=${RUNNER_USER}"

if [ ! -e "$CLAUDE_DIR" ]; then
  note "${CLAUDE_DIR}: ABSENT (will be created on first use)"
else
  note "${CLAUDE_DIR}: $(stat -c '%u %g %a %U:%G' "$CLAUDE_DIR")"
fi

if [ -e "$SESSION_ENV" ]; then
  note "${SESSION_ENV}: $(stat -c '%u %g %a %U:%G' "$SESSION_ENV")"
else
  note "${SESSION_ENV}: ABSENT (this is where the harness tries to mkdir)"
fi

# ---- Assertion block ----
echo "==> AC #1 assertion — can the container user write here?"

# Attempt the exact operation the aux-delegator harness performs.
if ! mkdir -p "$SESSION_ENV" 2>/dev/null; then
  note "mkdir -p ${SESSION_ENV} FAILED — this is the EACCES root cause"
  exit 2
fi

PROBE_FILE="$SESSION_ENV/.spec0008-probe"
if ! touch "$PROBE_FILE" 2>/dev/null; then
  fail "touch ${PROBE_FILE} failed even after mkdir succeeded"
fi

PROBE_OWNER="$(stat -c '%U:%G' "$PROBE_FILE")"
EXPECTED_OWNER="${RUNNER_USER}:${RUNNER_USER}"
if [ "$PROBE_OWNER" != "$EXPECTED_OWNER" ]; then
  fail "probe file owner = ${PROBE_OWNER}, want ${EXPECTED_OWNER}"
fi

note "probe file owner: ${PROBE_OWNER} ✓"
rm -f "$PROBE_FILE"

echo "OK: ~/.claude/session-env is writable by the container user"
