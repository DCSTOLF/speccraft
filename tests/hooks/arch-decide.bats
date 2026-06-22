#!/usr/bin/env bats
# Tests for commands/arch/decide.lib.sh — arch_set_status status transition
# backing /speccraft:arch:decide (spec 0022). Pure helper; RED until T15.

setup() {
  PLUGIN_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  ARCH_LIB="$PLUGIN_DIR/commands/arch/decide.lib.sh"
  TEST_REPO="$(mktemp -d)"
  export ARCH_LIB TEST_REPO
}

teardown() {
  rm -rf "$TEST_REPO"
}

seed_design() {
  local status="$1"
  local f="$TEST_REPO/design/0001-x/design.md"
  mkdir -p "$(dirname "$f")"
  cat > "$f" <<EOF
---
id: "0001"
title: "X"
status: $status
created: 2026-06-22
---

# Design 0001 — X
EOF
  echo "$f"
}

@test "arch_set_status: draft -> decided" {
  source "$ARCH_LIB"
  f="$(seed_design draft)"
  run arch_set_status "$f" decided
  [ "$status" -eq 0 ]
  grep -qE '^status: decided$' "$f"
}

@test "arch_set_status: rejects non-draft source" {
  source "$ARCH_LIB"
  f="$(seed_design closed)"
  run arch_set_status "$f" decided
  [ "$status" -ne 0 ]
  grep -qE '^status: closed$' "$f"   # unchanged
}
