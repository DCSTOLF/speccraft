#!/usr/bin/env bats
# Tests for commands/spec/new.lib.sh — the --from / informed-by bridge backing
# /speccraft:spec:new (spec 0022, AC5/AC8). Pure helpers, no side effects at
# source time. RED until T18 lands the lib.
#
# Contract pinned here:
#   - --from product/<id> | design/<id> pulls the referent's Why/What into the
#     new spec and writes a NON-EMPTY `informed-by:` frontmatter key.
#   - plain spec:new writes NO `informed-by:` key (byte-shape parity, AC5).
#   - a `closed` referent is an accepted --from source (AC8).
#   - a dangling --from referent is NON-FATAL: exit 0, note on stderr, spec
#     still generated with the advisory link recorded (AC8).

setup() {
  PLUGIN_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SPEC_LIB="$PLUGIN_DIR/commands/spec/new.lib.sh"
  TEST_REPO="$(mktemp -d)"
  export SPEC_LIB TEST_REPO
}

teardown() {
  rm -rf "$TEST_REPO"
}

seed_brief() {
  local id="$1" status="$2"
  local f="$TEST_REPO/product/$id/brief.md"
  mkdir -p "$(dirname "$f")"
  cat > "$f" <<EOF
---
id: "${id%%-*}"
title: "Seeded"
status: $status
created: 2026-06-22
---

# Product brief — Seeded

## Why

Users hit problem P with evidence E.

## What

Ship capability C with success metric M.

## Out of scope

- nothing
EOF
}

@test "spec_from_emits_informed_by: --from product/<id> sets non-empty key" {
  source "$SPEC_LIB"
  seed_brief "0001-x" draft
  spec_file="$TEST_REPO/specs/0001-y/spec.md"
  run spec_new_scaffold "$spec_file" "0001" "Y" "2026-06-22" "$TEST_REPO" "product/0001-x"
  [ "$status" -eq 0 ]
  [ -f "$spec_file" ]
  grep -qE '^informed-by: \[product/0001-x\]$' "$spec_file"
  # Why/What pulled from the brief (structural: the brief body words landed).
  grep -qF 'problem P' "$spec_file"
  grep -qF 'capability C' "$spec_file"
}

@test "spec_plain_new_has_no_informed_by_key" {
  source "$SPEC_LIB"
  spec_file="$TEST_REPO/specs/0001-y/spec.md"
  run spec_new_scaffold "$spec_file" "0001" "Y" "2026-06-22" "$TEST_REPO"
  [ "$status" -eq 0 ]
  [ -f "$spec_file" ]
  ! grep -qE '^informed-by:' "$spec_file"
}

@test "spec_from_accepts_closed_brief" {
  source "$SPEC_LIB"
  seed_brief "0002-c" closed
  spec_file="$TEST_REPO/specs/0001-y/spec.md"
  run spec_new_scaffold "$spec_file" "0001" "Y" "2026-06-22" "$TEST_REPO" "product/0002-c"
  [ "$status" -eq 0 ]
  grep -qE '^informed-by: \[product/0002-c\]$' "$spec_file"
  grep -qF 'capability C' "$spec_file"
}

@test "spec_from_dangling_referent_is_nonfatal" {
  source "$SPEC_LIB"
  spec_file="$TEST_REPO/specs/0001-y/spec.md"
  run spec_new_scaffold "$spec_file" "0001" "Y" "2026-06-22" "$TEST_REPO" "product/9999-missing"
  [ "$status" -eq 0 ]
  [ -f "$spec_file" ]
  # Advisory dangling link still recorded (the link may dangle — AC8).
  grep -qE '^informed-by: \[product/9999-missing\]$' "$spec_file"
  # Non-fatal note surfaced (run merges stderr into $output).
  [[ "$output" == *"not found"* ]]
}
