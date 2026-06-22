#!/usr/bin/env bash
# commands/pm/new.lib.sh — testable shell helpers backing /speccraft:pm:new
# (spec 0022, AC2). Sourced by commands/pm/new.md at runtime and by
# tests/hooks/pm-new-preflight.bats at test time.
#
# All functions are pure (no top-level side effects). Errors go to stderr;
# stdout is reserved for structured output (the allocated id). Mirrors the
# commands/spec/revise.lib.sh colocation pattern.

set -euo pipefail

# pm_next_id <product-tree-dir>
# Echoes the next zero-padded four-digit id for the product/ tree: the highest
# existing NNNN prefix + 1, or 0001 when the tree is absent or empty. Ids are
# never reused — gaps from abandoned/deleted briefs are not reclaimed.
pm_next_id() {
  local tree="$1"
  local max=0 d n
  if [ -d "$tree" ]; then
    for d in "$tree"/[0-9][0-9][0-9][0-9]-*; do
      [ -d "$d" ] || continue
      n="$(basename "$d")"
      n="${n%%-*}"
      n=$((10#$n))
      if [ "$n" -gt "$max" ]; then
        max="$n"
      fi
    done
  fi
  printf '%04d\n' "$((max + 1))"
}

# pm_scaffold_brief <file> <id> <title>
# Writes a draft brief.md with canonical frontmatter and the PM section
# skeleton (Why / What / Out of scope). Creates the parent directory.
pm_scaffold_brief() {
  local file="$1" id="$2" title="$3"
  local created
  created="$(date +%F)"
  mkdir -p "$(dirname "$file")"
  cat > "$file" <<EOF
---
id: "$id"
title: "$title"
status: draft
created: $created
authors: [claude]
---

# Product brief $id — $title

## Why

<problem, who is affected, evidence>

## What

<proposed change, success metrics, scope>

## Out of scope

- <item>
EOF
}
