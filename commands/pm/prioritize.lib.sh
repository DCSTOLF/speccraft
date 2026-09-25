#!/usr/bin/env bash
# commands/pm/prioritize.lib.sh — testable helper backing /speccraft:pm:prioritize
# (spec 0022). Sourced by commands/pm/prioritize.md at runtime and by
# tests/hooks/pm-prioritize.bats at test time. Pure function, no side effects
# at source time.

set -euo pipefail

# Cross-shell self-location: the canonical `${BASH_SOURCE[0]:-$0}` guarded form
# required by spec 0029 (an exact-form grep guard rejects any other spelling).
_PM_PRIORITIZE_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

# _pm_state_bin
# Resolve the `speccraft-state` binary (spec 0049, plan Appendix C). Order:
#   1. $SPECCRAFT_STATE_BIN — explicit operator/test override
#   2. PATH — a real installation resolves the plugin's own matching bin/
#   3. plugin-local bin/, derived from this lib's own location
# Prints the resolved path; returns non-zero with a diagnostic if none is usable.
_pm_state_bin() {
  if [ -n "${SPECCRAFT_STATE_BIN:-}" ] && [ -x "${SPECCRAFT_STATE_BIN}" ]; then
    printf '%s\n' "$SPECCRAFT_STATE_BIN"; return 0
  fi
  local found
  if found="$(command -v speccraft-state 2>/dev/null)" && [ -n "$found" ]; then
    printf '%s\n' "$found"; return 0
  fi
  local local_bin="$_PM_PRIORITIZE_LIB_DIR/../../bin/speccraft-state"
  if [ -x "$local_bin" ]; then
    printf '%s\n' "$local_bin"; return 0
  fi
  echo "pm_set_status: cannot find speccraft-state (tried \$SPECCRAFT_STATE_BIN, PATH, $local_bin)" >&2
  return 1
}

# pm_set_status <brief.md> <new-status>
# Gates the source status (only a `draft` brief may be transitioned), then
# delegates the write to the sanctioned frontmatter writer:
#   speccraft-state set-status --kind brief <brief.md> <status>
#
# The write is NOT hand-rolled. This helper carried a byte-identical copy of
# `/speccraft:arch:decide`'s GNU-only in-place stream edit, so
# /speccraft:pm:prioritize had the same silent no-op on macOS: the BSD editor
# consumes the ERE flag as a backup suffix and rejects the `0,/re/` address,
# nothing is written, and that edit's exit status of 0 becomes the function's.
# Delegating
# inherits byte-safe writes, per-kind enum validation, closed-artifact
# immutability, and a real non-zero exit (spec 0049 AC1/AC2).
#
# Every failure path returns non-zero AND writes a diagnostic to stderr.
pm_set_status() {
  local file="$1" new="$2"
  if [ ! -f "$file" ]; then
    echo "pm_set_status: $file not found" >&2
    return 1
  fi
  local cur
  cur="$(awk -F': ' '/^status:/{print $2; exit}' "$file")"
  if [ "$cur" != "draft" ]; then
    echo "pm_set_status: source status is '$cur'; only 'draft' may be transitioned" >&2
    return 1
  fi
  local bin
  bin="$(_pm_state_bin)" || return 1
  if ! "$bin" set-status --kind brief "$file" "$new"; then
    echo "pm_set_status: set-status --kind brief failed for $file (via $bin)" >&2
    return 1
  fi
}
