#!/usr/bin/env bats
# Tests for commands/pm/prioritize.lib.sh — pm_set_status status transition
# backing /speccraft:pm:prioritize (spec 0022). Pure helper; RED until T15.

setup() {
  PLUGIN_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  PM_LIB="$PLUGIN_DIR/commands/pm/prioritize.lib.sh"
  TEST_REPO="$(mktemp -d)"
  export PM_LIB TEST_REPO
}

teardown() {
  rm -rf "$TEST_REPO"
}

seed_brief() {
  local status="$1"
  local f="$TEST_REPO/product/0001-x/brief.md"
  mkdir -p "$(dirname "$f")"
  cat > "$f" <<EOF
---
id: "0001"
title: "X"
status: $status
created: 2026-06-22
---

# Product brief 0001 — X
EOF
  echo "$f"
}

@test "pm_set_status: draft -> prioritized" {
  source "$PM_LIB"
  f="$(seed_brief draft)"
  run pm_set_status "$f" prioritized
  [ "$status" -eq 0 ]
  grep -qE '^status: prioritized$' "$f"
}

@test "pm_set_status: rejects non-draft source" {
  source "$PM_LIB"
  f="$(seed_brief reviewed)"
  run pm_set_status "$f" prioritized
  [ "$status" -ne 0 ]
  grep -qE '^status: reviewed$' "$f"   # unchanged
}
