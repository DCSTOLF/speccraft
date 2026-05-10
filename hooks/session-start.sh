#!/usr/bin/env bash
# SessionStart hook: ensure binaries present, find .speccraft/, inject index.md.
set -euo pipefail

# Make plugin-shipped binaries discoverable.
export PATH="${CLAUDE_PLUGIN_ROOT}/bin:$PATH"

# Ensure binaries are present (download from GitHub Releases on first use,
# no-op when version stamp matches).
"${CLAUDE_PLUGIN_ROOT}/scripts/install-binaries.sh" >&2

# Find .speccraft/ by walking up from cwd.
# Use the binary when available; fall back to pure-bash walk.
find_speccraft_root() {
  local dir="${PWD}"
  while [ "$dir" != "/" ]; do
    if [ -d "$dir/.speccraft" ]; then
      echo "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  return 1
}

if command -v speccraft-state >/dev/null 2>&1; then
  ROOT="$(speccraft-state find-root 2>/dev/null || true)"
else
  ROOT="$(find_speccraft_root 2>/dev/null || true)"
fi
if [ -z "$ROOT" ]; then
  # Not a speccraft repo. Quietly succeed.
  exit 0
fi

# Reset session fields in state.json (Phase 2 binary does this; stub here).
if command -v speccraft-state >/dev/null 2>&1; then
  speccraft-state reset-session 2>/dev/null || true
fi

# Inject index.md as additional system context.
# Claude Code's hook protocol: print to stdout, it's appended to context.
echo "## speccraft memory (always-injected)"
echo
cat "$ROOT/.speccraft/index.md"
echo
echo "_For deeper detail, the speccraft-context skill knows when to load"
echo "guardrails.md, architecture.md, conventions.md, or history.md._"
