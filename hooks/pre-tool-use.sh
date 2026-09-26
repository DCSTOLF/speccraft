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
# Runtime dependencies: jq. Path canonicalisation is done in pure shell —
# see canon_path below. It used to use `realpath -m`, which macOS does not
# support (spec 0050 AC10): the invocation failed under `set -e`, so the hook
# exited BEFORE delegating to speccraft-guard, leaving both the state.json
# guard and the whole TDD invariant inert on macOS while printing a confusing
# `realpath: illegal option -- m`.
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
# canon_path <path> — absolute, symlink-resolved path of a file that need NOT
# exist. Only its DIRECTORY has to, which is what makes this a safe replacement
# for the `realpath -m` this used to call:
#
#   - `cd "$(dirname …)" && pwd -P` resolves `.`, `..` and symlinks exactly as
#     realpath would, for any path whose parent directory exists.
#   - When the parent does NOT exist, the target cannot be
#     <root>/.speccraft/state.json — whose directory always exists, since ROOT
#     was found by locating it. So the lexical fallback below can never turn a
#     real match into a miss, which is the only property this comparison needs.
#
# Portable everywhere: it invokes neither realpath nor the GNU-only recursive
# flag of readlink, both of which differ or are absent on BSD userland.
# Splits with parameter expansion rather than dirname/basename: this runs on
# EVERY write tool call, so two subshells per call is a real cost, and BSD's
# dirname/basename take their operand positionally — relying on them to accept
# `--` is the kind of assumption that produced the defect being fixed here.
canon_path() {
  local p="${1%/}" d b dabs
  case "$p" in
    */*) d="${p%/*}"; b="${p##*/}"; [ -n "$d" ] || d="/" ;;
    *)   d="."; b="$p" ;;
  esac
  if dabs="$(cd "$d" 2>/dev/null && pwd -P)"; then
    printf '%s/%s\n' "${dabs%/}" "$b"
  elif [ "${p#/}" != "$p" ]; then
    printf '%s\n' "$p"
  else
    printf '%s/%s\n' "${PWD%/}" "$p"
  fi
}

GATED_TOOLS="Edit Write MultiEdit NotebookEdit"
TOOL_NAME="$(printf '%s' "$INPUT" | jq -r '.tool_name // empty')"
FILE_PATH="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty')"
if [ -n "$TOOL_NAME" ] && [ -n "$FILE_PATH" ]; then
  for t in $GATED_TOOLS; do
    if [ "$TOOL_NAME" = "$t" ]; then
      ABS="$(canon_path "$FILE_PATH")"
      STATE="$(canon_path "$ROOT/.speccraft/state.json")"
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
