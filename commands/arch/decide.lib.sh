#!/usr/bin/env bash
# commands/arch/decide.lib.sh — testable helper backing /speccraft:arch:decide
# (spec 0022). Sourced by commands/arch/decide.md at runtime and by
# tests/hooks/arch-decide.bats at test time. Pure function, no side effects at
# source time.

set -euo pipefail

# Cross-shell self-location: the canonical `${BASH_SOURCE[0]:-$0}` guarded form
# required by spec 0029 (an exact-form grep guard rejects any other spelling).
_ARCH_DECIDE_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

# _arch_state_bin
# Resolve the `speccraft-state` binary (spec 0049, plan Appendix C). Order:
#   1. $SPECCRAFT_STATE_BIN — explicit operator/test override
#   2. PATH — a real installation resolves the plugin's own matching bin/
#   3. plugin-local bin/, derived from this lib's own location — what makes the
#      helper work in CI where no ambient speccraft-state exists
# Prints the resolved path; returns non-zero with a diagnostic if none is usable.
_arch_state_bin() {
  if [ -n "${SPECCRAFT_STATE_BIN:-}" ] && [ -x "${SPECCRAFT_STATE_BIN}" ]; then
    printf '%s\n' "$SPECCRAFT_STATE_BIN"; return 0
  fi
  local found
  if found="$(command -v speccraft-state 2>/dev/null)" && [ -n "$found" ]; then
    printf '%s\n' "$found"; return 0
  fi
  local local_bin="$_ARCH_DECIDE_LIB_DIR/../../bin/speccraft-state"
  if [ -x "$local_bin" ]; then
    printf '%s\n' "$local_bin"; return 0
  fi
  echo "arch_set_status: cannot find speccraft-state (tried \$SPECCRAFT_STATE_BIN, PATH, $local_bin)" >&2
  return 1
}

# arch_set_status <design.md> <new-status>
# Gates the source status (only a `draft` design may be transitioned), then
# delegates the write to the sanctioned frontmatter writer:
#   speccraft-state set-status --kind design <design.md> <status>
#
# The write is NOT hand-rolled. It used to be a GNU-only in-place stream edit
# (see spec 0049's Why section for the exact invocation), which was non-portable
# twice over: the BSD editor reads the in-place flag's next argument as a backup
# suffix — so the ERE flag became the suffix and a stray `design.md-E` sibling
# appeared — and it does not support the `0,/re/` address form. Nothing matched,
# nothing was written, and because that edit was the function's last command its
# exit status of 0 became the function's: the caller was told a transition had
# happened that had not. Delegating inherits byte-safe writes, per-kind enum validation,
# closed-artifact immutability, and a real non-zero exit (spec 0049 AC1/AC2).
#
# Every failure path returns non-zero AND writes a diagnostic to stderr; a
# silent non-zero is a defect under AC2, because the caller's inability to tell
# what happened was the original bug.
arch_set_status() {
  local file="$1" new="$2"
  if [ ! -f "$file" ]; then
    echo "arch_set_status: $file not found" >&2
    return 1
  fi
  local cur
  cur="$(awk -F': ' '/^status:/{print $2; exit}' "$file")"
  if [ "$cur" != "draft" ]; then
    echo "arch_set_status: source status is '$cur'; only 'draft' may be transitioned" >&2
    return 1
  fi
  local bin
  bin="$(_arch_state_bin)" || return 1
  if ! "$bin" set-status --kind design "$file" "$new"; then
    echo "arch_set_status: set-status --kind design failed for $file (via $bin)" >&2
    return 1
  fi
}
