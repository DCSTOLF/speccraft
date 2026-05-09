#!/usr/bin/env bash
# Stop hook: gentle close-out reminder.
# Full implementation in Phase 8.
set -euo pipefail
export PATH="${CLAUDE_PLUGIN_ROOT}/bin:$PATH"

ROOT="$(speccraft-state find-root 2>/dev/null || true)"
[ -z "$ROOT" ] && exit 0

ACTIVE="$(speccraft-state get active_spec 2>/dev/null || echo "")"
if [ -n "$ACTIVE" ] && [ "$ACTIVE" != "null" ]; then
  TASKS_DONE="$(speccraft-state tasks-done-pct 2>/dev/null || echo "")"
  if [ "$TASKS_DONE" = "100" ]; then
    echo "## speccraft"
    echo "All tasks for $ACTIVE are complete. Consider \`/spec:close\`."
  fi
fi
