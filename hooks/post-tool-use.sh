#!/usr/bin/env bash
# PostToolUse: track session edits + regex drift scan.
# Full drift scan wired in Phase 7.
set -euo pipefail
export PATH="${CLAUDE_PLUGIN_ROOT}/bin:$PATH"

ROOT="$(speccraft-state find-root 2>/dev/null || true)"
[ -z "$ROOT" ] && exit 0

INPUT="$(cat)"
FILE="$(echo "$INPUT" | jq -r '.tool_input.file_path // ""')"

# Track session edits for the TDD invariant.
speccraft-state track-edit "$FILE" 2>/dev/null || true

# Drift scan: only on enforce:-tagged rules. Fast (regex only in v1).
DRIFT="$(speccraft-drift scan-file "$FILE" 2>/dev/null || true)"
if [ -n "$DRIFT" ]; then
  echo "## speccraft drift"
  echo "$DRIFT"
fi
