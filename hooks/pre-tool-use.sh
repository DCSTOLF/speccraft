#!/usr/bin/env bash
# PreToolUse hook for Edit|Write: enforce spec-first + TDD invariant.
# Full implementation in Phase 4 (speccraft-guard binary).
set -euo pipefail
export PATH="${CLAUDE_PLUGIN_ROOT}/bin:$PATH"

ROOT="$(speccraft-state find-root 2>/dev/null || true)"
[ -z "$ROOT" ] && exit 0

# Delegate to the Go binary; it does the real work and exits with 2 on block.
exec speccraft-guard pre-tool-use
