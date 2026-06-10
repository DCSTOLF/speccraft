#!/usr/bin/env bash
# PreToolUse hook for write tools: runtime single-writer guardrail for
# .speccraft/state.json, then delegate to speccraft-guard for the
# spec-first + TDD invariant.
#
# Write-tool coverage (spec 0012 AC4 / §What item 3): gates on the full
# set of Claude Code write tools — Edit, Write, MultiEdit, NotebookEdit.
# Adding a future write-tool name is a one-line change in GATED_TOOLS.
# Update hooks/hooks.json matcher in lockstep so new tool names actually
# reach this script.
#
# Runtime dependencies: jq, realpath -m (devcontainer image ships both
# at /usr/bin/{jq,realpath}). If portability to a minimal image becomes
# a concern, fold this guard into a small Go helper.
set -euo pipefail
export PATH="${CLAUDE_PLUGIN_ROOT}/bin:$PATH"

ROOT="$(speccraft-state find-root 2>/dev/null || true)"
[ -z "$ROOT" ] && exit 0

# Capture the envelope once so we can both inspect it for the state.json
# guard below and replay it to speccraft-guard.
INPUT="$(cat)"

# Runtime single-writer guardrail (spec 0012 AC4).
#
# The only sanctioned writer of .speccraft/state.json is the speccraft-state
# binary. A Go-test grep enforces this at the source level
# (tools/internal/speccraft/state_single_writer_test.go); this hook covers
# the runtime axis a `claude -p` session can otherwise bypass.
#
# Path comparison uses `realpath -m` for canonicalisation (-m allows
# components that don't exist, so we can canonicalise paths the model is
# about to *create*). We deliberately do NOT call realpath -e or
# filepath.EvalSymlinks — no current path uses a symlinked .speccraft/
# and the extra stat round-trip would run on every write tool call.
GATED_TOOLS="Edit Write MultiEdit NotebookEdit"
TOOL_NAME="$(printf '%s' "$INPUT" | jq -r '.tool_name // empty')"
FILE_PATH="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty')"
if [ -n "$TOOL_NAME" ] && [ -n "$FILE_PATH" ]; then
  for t in $GATED_TOOLS; do
    if [ "$TOOL_NAME" = "$t" ]; then
      ABS="$(realpath -m -- "$FILE_PATH")"
      STATE="$(realpath -m -- "$ROOT/.speccraft/state.json")"
      if [ "$ABS" = "$STATE" ]; then
        cat >&2 <<'EOF'
.speccraft/state.json is single-writer: speccraft-state is the only
sanctioned writer. Do not Edit/Write/MultiEdit/NotebookEdit this file
directly — even to "fix" a value the binary just produced.

Use:
  speccraft-state set active_spec <id>       # set the active spec
  speccraft-state set active_spec null       # clear it (spec 0012)
  speccraft-state set override_pending true  # one-time TDD bypass

See spec 0012 (specs/0012-clear-active-spec-correctly-on-close/).
EOF
        exit 2
      fi
      break
    fi
  done
fi

# Delegate to the Go binary; it does the real work and exits with 2 on block.
exec speccraft-guard pre-tool-use <<<"$INPUT"
