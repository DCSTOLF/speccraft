#!/usr/bin/env bash
# UserPromptSubmit hook: nudge if user requests code change with no active spec.
# Full implementation in Phase 4.
set -euo pipefail
export PATH="${CLAUDE_PLUGIN_ROOT}/bin:$PATH"

ROOT="$(speccraft-state find-root 2>/dev/null || true)"
[ -z "$ROOT" ] && exit 0

# Read prompt from stdin (Claude Code provides JSON).
INPUT="$(cat)"
PROMPT="$(echo "$INPUT" | jq -r '.prompt // ""')"

# Heuristic: does the prompt request code change?
if echo "$PROMPT" | grep -iqE '\b(implement|add|fix|refactor|change|update|modify|write|create)\b.*\.(go|md|json|toml)\b|^(fix|add|implement|build|create) '; then
  ACTIVE="$(speccraft-state get active_spec 2>/dev/null || echo "")"
  if [ -z "$ACTIVE" ] || [ "$ACTIVE" = "null" ]; then
    cat <<EOF
## speccraft note
You're requesting a code change but no spec is active. The spec-first invariant
will block edits to production files. Consider:

- \`/spec:new "<title>"\` to start a spec, or
- \`/spec:implement\` if a spec is planned but not in-progress, or
- prefix with \`scratch:\` if this is throwaway work in tests or docs.
EOF
  fi
fi
