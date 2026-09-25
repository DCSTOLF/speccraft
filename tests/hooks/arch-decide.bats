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

# --- spec 0049 (AC1, AC2 shell layer, AC3) ---
#
# The two @tests above are spec 0022's and are pinned UNMODIFIED by AC1: the
# reroute through the sanctioned writer must be behaviour-preserving on the
# success and gate paths. Everything below is new.
#
# Coverage is deliberately SPLIT BY LAYER (review round 2, item 6). The helper
# resolves two of the five non-zero paths itself, before `speccraft-state` is
# ever invoked, so a PATH shim cannot exercise them and a single undifferentiated
# "it errors" test would leave them uncovered.

@test "arch_set_status: lib has no in-place rewrite and invokes set-status --kind design" {
  # The original defect, as a source-level assertion: a GNU-only in-place
  # stream edit that silently no-ops on BSD. The fix is to not hand-roll the
  # write at all.
  #
  # NOTE the form: `! grep -q ...` on its own line would be INERT here, because
  # `set -e` is specified to ignore a command whose failure is negated by `!`.
  # Written that way the assertion never fails the test and the @test passes on
  # its last line alone. Use `run` + an explicit status check.
  run grep -nE '\bsed\b|perl -i' "$ARCH_LIB"
  [ "$status" -ne 0 ] || { echo "hand-rolled in-place edit still present:"; echo "$output"; false; }
  grep -q 'set-status --kind design' "$ARCH_LIB"
}

@test "arch_set_status: successful transition leaves no stray sibling" {
  # AC3 — the field report's `design.md-E` turd. BSD sed consumed `-E` as the
  # backup suffix and wrote a byte-identical sibling.
  source "$ARCH_LIB"
  f="$(seed_design draft)"
  dir="$(dirname "$f")"
  run arch_set_status "$f" decided
  [ "$status" -eq 0 ]
  listing="$(ls -A "$dir")"
  [ "$listing" = "design.md" ]
}

@test "arch_set_status: missing file -> non-zero + non-empty stderr (shell layer)" {
  source "$ARCH_LIB"
  run arch_set_status "$TEST_REPO/nope/design.md" decided
  [ "$status" -ne 0 ]
  [ -n "$output" ]
}

@test "arch_set_status: non-draft source -> non-zero + stderr + file unchanged (shell layer)" {
  source "$ARCH_LIB"
  f="$(seed_design decided)"
  before="$(cat "$f")"
  run arch_set_status "$f" decided
  [ "$status" -ne 0 ]
  [ -n "$output" ]
  [ "$before" = "$(cat "$f")" ]
}

@test "arch_set_status: invalid status for the design kind -> non-zero + stderr (binary layer)" {
  source "$ARCH_LIB"
  f="$(seed_design draft)"
  before="$(cat "$f")"
  run arch_set_status "$f" prioritized   # a brief-only value
  [ "$status" -ne 0 ]
  [ -n "$output" ]
  [ "$before" = "$(cat "$f")" ]
}

@test "arch_set_status: PATH shim write failure -> non-zero + stderr + byte-identical + no temp" {
  # AC2's deterministic, uid-independent seam at the shell layer. A read-only
  # file would not fail (rename(2) into a writable parent succeeds) and a
  # read-only directory silently no-ops under root; shimming the binary is
  # exact. The helper shells out, so this is the only reachable seam from bats.
  source "$ARCH_LIB"
  f="$(seed_design draft)"
  dir="$(dirname "$f")"
  before="$(cat "$f")"

  shim="$TEST_REPO/shim"
  mkdir -p "$shim"
  cat > "$shim/speccraft-state" <<'EOS'
#!/usr/bin/env bash
echo "speccraft-state: injected write failure" >&2
exit 1
EOS
  chmod +x "$shim/speccraft-state"

  PATH="$shim:$PATH" SPECCRAFT_STATE_BIN="$shim/speccraft-state" run arch_set_status "$f" decided
  [ "$status" -ne 0 ]
  [ -n "$output" ]
  [ "$before" = "$(cat "$f")" ]
  listing="$(ls -A "$dir")"
  [ "$listing" = "design.md" ]
}
