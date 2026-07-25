#!/usr/bin/env bats
# Tests for commands/init.lib.sh::seed_conventions (spec 0034 AC5).
#
# /speccraft:init seeds the copied .speccraft/conventions.md's Testing section +
# test-command marker from the DETECTED stack, instead of shipping hardcoded Go
# conventions into a host repo. It PRESERVES an existing conventions.md
# byte-for-byte (the editable source of truth) — idempotent. An unknown stack
# yields a TODO placeholder + empty marker, never a Go default.
#
# Pure shell helper, no side effects at source time — mirrors the
# commands/spec/*.lib.sh colocation convention (spec 0015). seed_conventions
# shells out to `speccraft-state detect-stack`, resolved from the bin/ on PATH.

setup() {
  PLUGIN_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  LIB="$PLUGIN_DIR/commands/init.lib.sh"
  TEMPLATE="$PLUGIN_DIR/templates/speccraft/conventions.md"
  TEST_REPO="$(mktemp -d)"
  mkdir -p "$TEST_REPO/.speccraft"
  export PATH="$PLUGIN_DIR/bin:$PATH"
  # shellcheck disable=SC1090
  source "$LIB"
}

teardown() {
  rm -rf "$TEST_REPO"
}

@test "fresh Python repo: marker filled with pytest; naming section present" {
  touch "$TEST_REPO/pyproject.toml"
  seed_conventions "$TEST_REPO" "$TEMPLATE"
  run cat "$TEST_REPO/.speccraft/conventions.md"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'speccraft:test-command = "pytest"'
  echo "$output" | grep -q '## Naming'
  # And the effective command reads back through the CLI.
  run bash -c "cd '$TEST_REPO' && speccraft-state test-command"
  [ "$status" -eq 0 ]
  [ "$output" = "pytest" ]
}

@test "fresh repo: no Go idioms leak from the shipped template" {
  touch "$TEST_REPO/pyproject.toml"
  seed_conventions "$TEST_REPO" "$TEMPLATE"
  run cat "$TEST_REPO/.speccraft/conventions.md"
  ! echo "$output" | grep -q 'fmt.Errorf'
  ! echo "$output" | grep -q 'slog'
  ! echo "$output" | grep -q 'scope="\*\*/\*_test.go"'
}

@test "existing conventions.md is preserved byte-identical (idempotent)" {
  printf '# My own conventions\n\nDo not touch.\n' > "$TEST_REPO/.speccraft/conventions.md"
  cp "$TEST_REPO/.speccraft/conventions.md" "$TEST_REPO/before"
  touch "$TEST_REPO/go.mod"
  seed_conventions "$TEST_REPO" "$TEMPLATE"
  run cmp -s "$TEST_REPO/before" "$TEST_REPO/.speccraft/conventions.md"
  [ "$status" -eq 0 ]
}

@test "unknown stack: empty marker + TODO placeholder, not a Go default" {
  # No manifest at the repo root → detect-stack reports unknown.
  seed_conventions "$TEST_REPO" "$TEMPLATE"
  run cat "$TEST_REPO/.speccraft/conventions.md"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'speccraft:test-command = ""'
  echo "$output" | grep -qi 'TODO'
  ! echo "$output" | grep -q 'go test'
}
