#!/usr/bin/env bash
# commands/pm/prioritize.lib.sh — testable helper backing /speccraft:pm:prioritize
# (spec 0022). Sourced by commands/pm/prioritize.md at runtime and by
# tests/hooks/pm-prioritize.bats at test time. Pure function, no side effects
# at source time.

set -euo pipefail

# pm_set_status <brief.md> <new-status>
# Gates the source status (only a `draft` brief may be transitioned) and
# rewrites the first `status:` frontmatter line in place. Errors to stderr,
# returns non-zero, and leaves the file unchanged when the gate fails.
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
  sed -i -E "0,/^status:/s/^status: .*/status: $new/" "$file"
}
