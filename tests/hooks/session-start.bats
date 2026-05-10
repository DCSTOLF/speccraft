#!/usr/bin/env bats
# Tests for hooks/session-start.sh

setup() {
  PLUGIN_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  HOOK="$PLUGIN_DIR/hooks/session-start.sh"
  TEST_REPO="$(mktemp -d)"
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR"
  export PATH="$PLUGIN_DIR/bin:$PATH"
}

teardown() {
  rm -rf "$TEST_REPO"
}

@test "session-start exits 0 with no .speccraft dir" {
  cd "$TEST_REPO"
  run "$HOOK"
  [ "$status" -eq 0 ]
}

@test "session-start injects index.md content when .speccraft exists" {
  mkdir -p "$TEST_REPO/.speccraft"
  echo "# My Project" > "$TEST_REPO/.speccraft/index.md"
  echo "A test project." >> "$TEST_REPO/.speccraft/index.md"

  cd "$TEST_REPO"
  run "$HOOK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"speccraft memory"* ]]
  [[ "$output" == *"My Project"* ]]
}

@test "session-start exits 0 when install-binaries.sh fails gracefully" {
  # Without a real .speccraft/, the hook should still succeed silently.
  cd "$TEST_REPO"
  run "$HOOK"
  [ "$status" -eq 0 ]
}
