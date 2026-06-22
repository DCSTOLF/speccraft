#!/usr/bin/env bats
# Tests for commands/arch/new.lib.sh — testable shell helpers backing
# /speccraft:arch:new (spec 0022, AC2).
#
# Covers id allocation (empty-tree base case + highest-NNNN+1, never reused)
# and design.md scaffolding (frontmatter shape + section headers). Helpers are
# pure; sourcing a nonexistent lib is the RED state until T8 lands.

setup() {
  PLUGIN_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  ARCH_LIB="$PLUGIN_DIR/commands/arch/new.lib.sh"
  TEST_REPO="$(mktemp -d)"
  mkdir -p "$TEST_REPO"
  export ARCH_LIB TEST_REPO
}

teardown() {
  rm -rf "$TEST_REPO"
}

@test "arch_next_id: empty tree (no design/ dir) yields 0001" {
  source "$ARCH_LIB"
  run arch_next_id "$TEST_REPO/design"
  [ "$status" -eq 0 ]
  [ "$output" = "0001" ]
}

@test "arch_next_id: highest NNNN + 1, gaps not reclaimed" {
  source "$ARCH_LIB"
  mkdir -p "$TEST_REPO/design/0001-alpha" "$TEST_REPO/design/0005-charlie"
  run arch_next_id "$TEST_REPO/design"
  [ "$status" -eq 0 ]
  [ "$output" = "0006" ]
}

@test "arch_scaffold_design: writes design.md with draft frontmatter + sections" {
  source "$ARCH_LIB"
  local f="$TEST_REPO/design/0001-auth-model/design.md"
  mkdir -p "$(dirname "$f")"
  run arch_scaffold_design "$f" "0001" "Auth model"
  [ "$status" -eq 0 ]
  [ -f "$f" ]
  grep -qE '^status: draft$' "$f"
  grep -qE '^id: "0001"$' "$f"
  grep -qF 'title: "Auth model"' "$f"
  grep -qE '^## Feasibility$' "$f"
  grep -qE '^## Components$' "$f"
}
