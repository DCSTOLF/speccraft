#!/usr/bin/env bats
# Spec 0036 T23/T24 (AC4, AC5) — self-healing, deadlock-free archive + a thin
# bump_revision that routes through the sanctioned speccraft-state writers.
# Sources commands/spec/revise.lib.sh; uses the freshly built bin/ binaries.

setup() {
  PLUGIN_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  REVISE_LIB="$PLUGIN_DIR/commands/spec/revise.lib.sh"
  export PATH="$PLUGIN_DIR/bin:$PATH"
  TEST_REPO="$(mktemp -d)"
  SPEC_DIR="$TEST_REPO/specs/0099-fixture"
  mkdir -p "$SPEC_DIR"
}
teardown() { rm -rf "$TEST_REPO"; }

seed() {
  local st="$1" rev="$2"
  cat > "$SPEC_DIR/spec.md" <<INNER
---
id: "0099"
status: $st
revision: $rev
---

# Spec
INNER
}

@test "archive_rename self-heals past a pre-existing review-rN.md (no deadlock)" {
  seed reviewed 5
  printf 'live-review\n' > "$SPEC_DIR/review.md"
  printf 'old-r5\n' > "$SPEC_DIR/review-r5.md"
  source "$REVISE_LIB"
  run archive_rename "$SPEC_DIR" reviewed
  [ "$status" -eq 0 ]
  [ -f "$SPEC_DIR/review-r6.md" ]
  [ "$(cat "$SPEC_DIR/review-r6.md")" = "live-review" ]
  [ "$(cat "$SPEC_DIR/review-r5.md")" = "old-r5" ]
  [ ! -f "$SPEC_DIR/review.md" ]
  [ -f "$SPEC_DIR/spec.md" ]
}

@test "bump_revision heals counter to post-archive Effective + flips status draft (no .bak)" {
  seed reviewed 5
  printf 'live\n' > "$SPEC_DIR/review.md"
  source "$REVISE_LIB"
  archive_rename "$SPEC_DIR" reviewed
  run bump_revision "$SPEC_DIR/spec.md" reviewed
  [ "$status" -eq 0 ]
  grep -qE '^revision: 6$' "$SPEC_DIR/spec.md"
  grep -qE '^status: draft$' "$SPEC_DIR/spec.md"
  [ ! -f "$SPEC_DIR/spec.md.bak" ]
}

@test "revise archive path completes on a collision that previously deadlocked" {
  seed reviewed 5
  printf 'live\n' > "$SPEC_DIR/review.md"
  printf 'old\n' > "$SPEC_DIR/review-r5.md"
  source "$REVISE_LIB"
  run archive_rename "$SPEC_DIR" reviewed
  [ "$status" -eq 0 ]
  run bump_revision "$SPEC_DIR/spec.md" reviewed
  [ "$status" -eq 0 ]
  grep -qE '^revision: 7$' "$SPEC_DIR/spec.md"
}

@test "bump_revision uses no raw in-place sed on status/revision" {
  body="$(awk '/^bump_revision\(\)/,/^}/' "$REVISE_LIB")"
  ! grep -qE "sed -i.*(status|revision):" <<<"$body"
}

@test "preflight_archive_collisions is deleted from revise.lib.sh" {
  ! grep -qE '^preflight_archive_collisions\(\)' "$REVISE_LIB"
}
