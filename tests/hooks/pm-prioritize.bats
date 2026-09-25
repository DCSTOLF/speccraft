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

# --- spec 0049 (AC1, AC2 shell layer, AC3) — mirrors arch-decide.bats ---
# The two @tests above are spec 0022's and are pinned UNMODIFIED by AC1.

@test "pm_set_status: lib has no in-place rewrite and invokes set-status --kind brief" {
  # `run` + explicit status check, NOT `! grep -q` — see the sibling test in
  # arch-decide.bats: `set -e` ignores a `!`-negated failure, so the bare
  # negated form is an inert assertion.
  run grep -nE '\bsed\b|perl -i' "$PM_LIB"
  [ "$status" -ne 0 ] || { echo "hand-rolled in-place edit still present:"; echo "$output"; false; }
  grep -q 'set-status --kind brief' "$PM_LIB"
}

@test "pm_set_status: successful transition leaves no stray sibling" {
  source "$PM_LIB"
  f="$(seed_brief draft)"
  dir="$(dirname "$f")"
  run pm_set_status "$f" prioritized
  [ "$status" -eq 0 ]
  listing="$(ls -A "$dir")"
  [ "$listing" = "brief.md" ]
}

@test "pm_set_status: missing file -> non-zero + non-empty stderr (shell layer)" {
  source "$PM_LIB"
  run pm_set_status "$TEST_REPO/nope/brief.md" prioritized
  [ "$status" -ne 0 ]
  [ -n "$output" ]
}

@test "pm_set_status: invalid status for the brief kind -> non-zero + stderr (binary layer)" {
  source "$PM_LIB"
  f="$(seed_brief draft)"
  before="$(cat "$f")"
  run pm_set_status "$f" decided   # a design-only value
  [ "$status" -ne 0 ]
  [ -n "$output" ]
  [ "$before" = "$(cat "$f")" ]
}

@test "pm_set_status: PATH shim write failure -> non-zero + stderr + byte-identical + no temp" {
  # AC2's deterministic, uid-independent seam at the shell layer — see the
  # equivalent test in arch-decide.bats for why permissions were rejected.
  source "$PM_LIB"
  f="$(seed_brief draft)"
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

  PATH="$shim:$PATH" SPECCRAFT_STATE_BIN="$shim/speccraft-state" run pm_set_status "$f" prioritized
  [ "$status" -ne 0 ]
  [ -n "$output" ]
  [ "$before" = "$(cat "$f")" ]
  listing="$(ls -A "$dir")"
  [ "$listing" = "brief.md" ]
}
