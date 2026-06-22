#!/usr/bin/env bash
# commands/arch/new.lib.sh — testable shell helpers backing /speccraft:arch:new
# (spec 0022, AC2). Sourced by commands/arch/new.md at runtime and by
# tests/hooks/arch-new-preflight.bats at test time.
#
# All functions are pure (no top-level side effects). Errors go to stderr;
# stdout is reserved for structured output (the allocated id). Mirrors the
# commands/spec/revise.lib.sh colocation pattern.

set -euo pipefail

# arch_next_id <design-tree-dir>
# Echoes the next zero-padded four-digit id for the design/ tree: the highest
# existing NNNN prefix + 1, or 0001 when the tree is absent or empty. Ids are
# never reused — gaps from abandoned/deleted designs are not reclaimed.
arch_next_id() {
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

# arch_scaffold_design <file> <id> <title>
# Writes a draft design.md with canonical frontmatter and the Architect
# section skeleton (Feasibility / Components / Data model / NFRs & trade-offs).
# Creates the parent directory.
arch_scaffold_design() {
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

# Design $id — $title

## Feasibility

<is this buildable? key unknowns, spikes needed>

## Components

<the pieces and how they fit>

## Data model

<entities, shapes, storage>

## NFRs & trade-offs

<performance, security, operability; alternatives weighed>
EOF
}
