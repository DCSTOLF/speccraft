#!/usr/bin/env bats
# Tests for commands/pm/new.lib.sh — testable shell helpers backing
# /speccraft:pm:new (spec 0022, AC2).
#
# Covers id allocation (empty-tree base case + highest-NNNN+1, never reused)
# and brief.md scaffolding (frontmatter shape + section headers). Helpers are
# pure; sourcing a nonexistent lib is the RED state until T8 lands.

setup() {
  PLUGIN_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  PM_LIB="$PLUGIN_DIR/commands/pm/new.lib.sh"
  TEST_REPO="$(mktemp -d)"
  mkdir -p "$TEST_REPO"
  export PM_LIB TEST_REPO
}

teardown() {
  rm -rf "$TEST_REPO"
}

@test "pm_next_id: empty tree (no product/ dir) yields 0001" {
  source "$PM_LIB"
  run pm_next_id "$TEST_REPO/product"
  [ "$status" -eq 0 ]
  [ "$output" = "0001" ]
}

@test "pm_next_id: empty existing product/ dir yields 0001" {
  source "$PM_LIB"
  mkdir -p "$TEST_REPO/product"
  run pm_next_id "$TEST_REPO/product"
  [ "$status" -eq 0 ]
  [ "$output" = "0001" ]
}

@test "pm_next_id: highest NNNN + 1, gaps not reclaimed" {
  source "$PM_LIB"
  mkdir -p "$TEST_REPO/product/0001-alpha" "$TEST_REPO/product/0003-bravo"
  run pm_next_id "$TEST_REPO/product"
  [ "$status" -eq 0 ]
  [ "$output" = "0004" ]
}

@test "pm_scaffold_brief: writes brief.md with draft frontmatter + sections" {
  source "$PM_LIB"
  local f="$TEST_REPO/product/0001-onboarding/brief.md"
  mkdir -p "$(dirname "$f")"
  run pm_scaffold_brief "$f" "0001" "Onboarding revamp"
  [ "$status" -eq 0 ]
  [ -f "$f" ]
  grep -qE '^status: draft$' "$f"
  grep -qE '^id: "0001"$' "$f"
  grep -qF 'title: "Onboarding revamp"' "$f"
  grep -qE '^## Why$' "$f"
  grep -qE '^## What$' "$f"
}
