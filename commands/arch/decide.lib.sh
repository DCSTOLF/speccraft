#!/usr/bin/env bash
# commands/arch/decide.lib.sh — testable helper backing /speccraft:arch:decide
# (spec 0022). Sourced by commands/arch/decide.md at runtime and by
# tests/hooks/arch-decide.bats at test time. Pure function, no side effects at
# source time.

set -euo pipefail

# arch_set_status <design.md> <new-status>
# Gates the source status (only a `draft` design may be transitioned) and
# rewrites the first `status:` frontmatter line in place. Errors to stderr,
# returns non-zero, and leaves the file unchanged when the gate fails.
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
  sed -i -E "0,/^status:/s/^status: .*/status: $new/" "$file"
}
