#!/usr/bin/env bats
# Tests for hooks/pre-tool-use.sh single-writer guardrail on
# .speccraft/state.json (spec 0012 AC4).
#
# The hook must reject any Edit/Write/MultiEdit/NotebookEdit tool call
# whose file_path resolves to <root>/.speccraft/state.json, naming
# `speccraft-state` as the sanctioned writer. It must NOT block writes
# to other files under .speccraft/ (memory files like conventions.md).

setup() {
  PLUGIN_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  HOOK="$PLUGIN_DIR/hooks/pre-tool-use.sh"
  TEST_REPO="$(mktemp -d)"
  mkdir -p "$TEST_REPO/.speccraft"
  # Seed a canonical empty state.json so speccraft-state find-root succeeds
  # from $TEST_REPO and no stale active_spec interferes with the test.
  cat > "$TEST_REPO/.speccraft/state.json" <<'JSON'
{"version":1,"session":{"id":"","edited_test_files":[],"edited_prod_files":[]}}
JSON
  # Sibling memory file used by the "allow" case.
  echo "# Conventions placeholder" > "$TEST_REPO/.speccraft/conventions.md"
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR"
  export PATH="$PLUGIN_DIR/bin:$PATH"
}

teardown() {
  rm -rf "$TEST_REPO"
}

# hook_input emits a synthetic Claude Code PreToolUse envelope.
hook_input() {
  local tool="$1"
  local path="$2"
  printf '{"tool_name":"%s","tool_input":{"file_path":"%s"},"cwd":"%s"}' \
    "$tool" "$path" "$TEST_REPO"
}

@test "rejects Edit on absolute path .speccraft/state.json" {
  cd "$TEST_REPO"
  run bash -c "echo '$(hook_input Edit "$TEST_REPO/.speccraft/state.json")' | '$HOOK'"
  [ "$status" -ne 0 ]
  [[ "$output" == *"speccraft-state"* ]]
}

@test "rejects Edit on relative path .speccraft/state.json" {
  cd "$TEST_REPO"
  run bash -c "echo '$(hook_input Edit ".speccraft/state.json")' | '$HOOK'"
  [ "$status" -ne 0 ]
  [[ "$output" == *"speccraft-state"* ]]
}

@test "rejects Write on .speccraft/state.json" {
  cd "$TEST_REPO"
  run bash -c "echo '$(hook_input Write "$TEST_REPO/.speccraft/state.json")' | '$HOOK'"
  [ "$status" -ne 0 ]
  [[ "$output" == *"speccraft-state"* ]]
}

@test "rejects MultiEdit on .speccraft/state.json" {
  cd "$TEST_REPO"
  run bash -c "echo '$(hook_input MultiEdit "$TEST_REPO/.speccraft/state.json")' | '$HOOK'"
  [ "$status" -ne 0 ]
  [[ "$output" == *"speccraft-state"* ]]
}

@test "rejects NotebookEdit on .speccraft/state.json" {
  cd "$TEST_REPO"
  run bash -c "echo '$(hook_input NotebookEdit "$TEST_REPO/.speccraft/state.json")' | '$HOOK'"
  [ "$status" -ne 0 ]
  [[ "$output" == *"speccraft-state"* ]]
}

@test "allows Edit on sibling memory file conventions.md" {
  cd "$TEST_REPO"
  run bash -c "echo '$(hook_input Edit "$TEST_REPO/.speccraft/conventions.md")' | '$HOOK'"
  [ "$status" -eq 0 ]
  # The state.json rejection message must NOT appear for a non-state.json
  # target — pins that the guard is not matching on the directory prefix.
  [[ "$output" != *"speccraft-state is the only sanctioned"* ]]
}
