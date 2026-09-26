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

# Spec 0050 AC10 — canonicalisation, now done in pure shell.
#
# The hook used `realpath -m`, which macOS does not support: the call failed under
# `set -e`, so the hook exited BEFORE delegating to speccraft-guard. Both this guard
# AND the entire TDD invariant were inert on macOS, reporting `realpath: illegal
# option -- m`. These tests pin the canonicalisation the replacement must do, through
# the hook's own contract rather than by reaching into a private function.
#
# The dot-segment cases are the load-bearing ones: a plain string comparison on
# file_path would let every one of them through, which is why the path is
# canonicalised at all.
@test "rejects an uncanonical path with dot segments that resolves to state.json" {
  cd "$TEST_REPO"
  run bash -c "echo '$(hook_input Edit "$TEST_REPO/.speccraft/../.speccraft/./state.json")' | '$HOOK'"
  [ "$status" -ne 0 ]
  [[ "$output" == *"speccraft-state"* ]]
}

@test "rejects a relative dot-segment path that resolves to state.json" {
  cd "$TEST_REPO/.speccraft"
  run bash -c "echo '$(hook_input Edit "../.speccraft/state.json")' | '$HOOK'"
  [ "$status" -ne 0 ]
  [[ "$output" == *"speccraft-state"* ]]
}

# The converse: canonicalisation must not over-match. A file merely NAMED
# state.json elsewhere in the tree is not the single-writer file.
@test "allows Edit on a same-named state.json outside .speccraft/" {
  mkdir -p "$TEST_REPO/elsewhere"
  echo '{}' > "$TEST_REPO/elsewhere/state.json"
  cd "$TEST_REPO"
  run bash -c "echo '$(hook_input Edit "$TEST_REPO/elsewhere/state.json")' | '$HOOK'"
  [[ "$output" != *"speccraft-state is the only sanctioned"* ]]
}

# A path whose PARENT DIRECTORY does not exist must not abort the hook. This is the
# case `realpath -m` was originally chosen for (-m tolerates missing components), so
# the replacement has to cover it or the hook breaks on every create-in-new-dir edit.
@test "a target under a nonexistent directory neither aborts nor is mistaken for state.json" {
  cd "$TEST_REPO"
  run bash -c "echo '$(hook_input Write "$TEST_REPO/brand/new/dir/file.go")' | '$HOOK'"
  [[ "$output" != *"speccraft-state is the only sanctioned"* ]]
  [[ "$output" != *"realpath"* ]]
  [[ "$output" != *"illegal option"* ]]
}
