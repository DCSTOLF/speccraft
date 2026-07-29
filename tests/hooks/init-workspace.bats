#!/usr/bin/env bats
# Tests for commands/init.lib.sh workspace-init helpers (spec 0042).
#
# `/speccraft:init --workspace` scaffolds a workspace root: a speccraft.toml with
# kind = "workspace" and a parser-valid workspace.yml member manifest that the
# existing Go readers (ReadConfig, ParseWorkspaceMembers) already accept. All
# deterministic mechanics are PURE SHELL helpers here (ungated .sh); the
# model-driven approval prompt + orchestration live in commands/init.md and are
# covered by the credit-gated e2e, not bats.
#
# The black-box parser oracle is the REAL reader via `speccraft-state
# list-members` (ParseWorkspaceMembers) and `config-kind`/`find-workspace-root`
# (ReadConfigStrict / FindWorkspaceRoot) — never a hand-rolled shell parser.

setup() {
  PLUGIN_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  LIB="$PLUGIN_DIR/commands/init.lib.sh"
  TEST_REPO="$(mktemp -d)"
  export PATH="$PLUGIN_DIR/bin:$PATH"
  # shellcheck disable=SC1090
  source "$LIB"
}

teardown() {
  rm -rf "$TEST_REPO"
}

# --- ws_arg_parse (AC6 order-independence) --------------------------------

@test "ws_arg_parse: --workspace alone selects workspace mode" {
  run ws_arg_parse --workspace
  [ "$status" -eq 0 ]
  echo "$output" | grep -qx 'workspace'
  ! echo "$output" | grep -qx 'force'
}

@test "ws_arg_parse: --force --workspace is order-independent" {
  run ws_arg_parse --force --workspace
  [ "$status" -eq 0 ]
  a="$(ws_arg_parse --force --workspace | sort)"
  b="$(ws_arg_parse --workspace --force | sort)"
  [ "$a" = "$b" ]
}

@test "ws_arg_parse: a repeated flag is idempotent" {
  run ws_arg_parse --workspace --workspace
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | grep -c workspace)" -eq 1 ]
}

@test "ws_arg_parse: an unknown flag is rejected with a usage error" {
  run ws_arg_parse --nope
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi 'usage'
}

@test "ws_arg_parse: a stray positional is rejected" {
  run ws_arg_parse foo
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi 'usage'
}

# --- ws_toml_body (AC1 / AC7) ---------------------------------------------

@test "ws_toml_body: fresh emit declares exactly one top-level kind = workspace" {
  run bash -c "source '$LIB'; ws_toml_body </dev/null"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | grep -c '^kind = \"workspace\"$')" -eq 1 ]
}

@test "ws_toml_body: existing single kind=workspace is returned unchanged, other keys preserved" {
  in=$'kind = "workspace"\n[tdd]\ntest_roots = ["tests"]\n'
  out="$(printf '%s' "$in" | { source "$LIB"; ws_toml_body; })"
  [ "$out" = "$(printf '%s' "$in")" ]
  echo "$out" | grep -q '\[tdd\]'
  echo "$out" | grep -q 'test_roots = \["tests"\]'
}

@test "ws_toml_body: duplicate kind lines normalize to one kind=workspace" {
  in=$'kind = "workspace"\nkind = "workspace"\n[tdd]\n'
  out="$(printf '%s' "$in" | { source "$LIB"; ws_toml_body; })"
  [ "$(echo "$out" | grep -c '^kind = \"workspace\"$')" -eq 1 ]
  echo "$out" | grep -q '\[tdd\]'
}

@test "ws_toml_body: an existing kind=repo refuses migration (non-zero, no rewrite)" {
  run bash -c "source '$LIB'; printf 'kind = \"repo\"\n' | ws_toml_body"
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi 'migration'
  ! echo "$output" | grep -q 'kind = "workspace"'
}

@test "ws_toml_body: emitted toml reads back as workspace via config-kind and find-workspace-root" {
  mkdir -p "$TEST_REPO/.speccraft"
  ws_toml_body </dev/null > "$TEST_REPO/.speccraft/speccraft.toml"
  run speccraft-state config-kind "$TEST_REPO"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | tr -d '[:space:]')" = "workspace" ]
  run bash -c "cd '$TEST_REPO' && speccraft-state find-workspace-root"
  [ "$status" -eq 0 ]
  want="$(cd "$TEST_REPO" && pwd -P)"
  [ "$(cd "$(echo "$output")" && pwd -P)" = "$want" ]
}

# --- ws_manifest_body (AC2) -----------------------------------------------

@test "ws_manifest_body: empty members yields an empty members: set" {
  out="$(ws_manifest_body)"
  echo "$out" | grep -qx 'members:'
  # no UNcommented member line
  [ "$(echo "$out" | grep -c '^  - path:')" -eq 0 ]
}

@test "ws_manifest_body: multiple members are emitted lexicographically sorted" {
  out="$(ws_manifest_body web api core)"
  got="$(echo "$out" | sed -n 's/^  - path: //p')"
  [ "$got" = $'api\ncore\nweb' ]
}

@test "ws_manifest_body: a member with whitespace/# is emitted double-quoted" {
  out="$(ws_manifest_body 'my repo')"
  echo "$out" | grep -qx '  - path: "my repo"'
}

@test "ws_manifest_body: a member containing a double-quote is skipped with a reason" {
  run bash -c "source '$LIB'; ws_manifest_body 'ba\"d'"
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q '^  - path:.*ba'   # never emitted as a member line
  echo "$output" | grep -qi 'double-quote'       # reason on stderr, merged by run
}

@test "ws_manifest_body: the emitted manifest parses via speccraft-state list-members" {
  mkdir -p "$TEST_REPO/.speccraft"
  printf 'kind = "workspace"\n' > "$TEST_REPO/.speccraft/speccraft.toml"
  mkdir -p "$TEST_REPO/api" "$TEST_REPO/my repo"
  ws_manifest_body api 'my repo' > "$TEST_REPO/workspace.yml" 2>/dev/null
  run bash -c "cd '$TEST_REPO' && speccraft-state list-members"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qP 'present\tapi'
  echo "$output" | grep -qP 'present\tmy repo'
}

@test "ws_manifest_body: empty manifest parses to zero members" {
  mkdir -p "$TEST_REPO/.speccraft"
  printf 'kind = "workspace"\n' > "$TEST_REPO/.speccraft/speccraft.toml"
  ws_manifest_body > "$TEST_REPO/workspace.yml"
  run bash -c "cd '$TEST_REPO' && speccraft-state list-members"
  [ "$status" -eq 0 ]
  [ -z "$(echo "$output" | tr -d '[:space:]')" ]
}

# --- ws_detect_members (AC3a) ---------------------------------------------

# mkchild <name> <toml-body|-> — create an immediate child speccraft repo.
mkchild() {
  local name="$1" body="$2"
  mkdir -p "$TEST_REPO/$name/.speccraft"
  [ "$body" = "-" ] || printf '%s\n' "$body" > "$TEST_REPO/$name/.speccraft/speccraft.toml"
}

@test "ws_detect_members: emits repo-kind children with .speccraft, lexicographically sorted" {
  mkchild core 'kind = "repo"'
  mkchild api '-'   # absent kind → coerces to repo
  out="$(ws_detect_members "$TEST_REPO" 2>/dev/null)"
  [ "$out" = $'api\ncore' ]
}

@test "ws_detect_members: excludes a kind=workspace child with a reason" {
  mkchild inner 'kind = "workspace"'
  run bash -c "source '$LIB'; ws_detect_members '$TEST_REPO'"
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -qx 'inner'
  echo "$output" | grep -qi 'inner'   # reason mentions it
}

@test "ws_detect_members: excludes a hidden dot-directory and a symlinked child" {
  mkchild real 'kind = "repo"'
  mkdir -p "$TEST_REPO/.hidden/.speccraft"
  ln -s "$TEST_REPO/real" "$TEST_REPO/link"
  out="$(ws_detect_members "$TEST_REPO" 2>/dev/null)"
  [ "$out" = 'real' ]
}

@test "ws_detect_members: a strict-invalid child config is skipped with a reason, not coerced" {
  mkchild bad 'kind = "bogus"'
  run bash -c "source '$LIB'; ws_detect_members '$TEST_REPO'"
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -qx 'bad'
}

# --- ws_write_root (AC4 / AC6 preserve / AC9 ordering) --------------------

@test "ws_write_root: writes workspace.yml BEFORE flipping the toml (toml-write fault leaves manifest present, kind un-flipped)" {
  mkdir -p "$TEST_REPO/.speccraft/speccraft.toml"   # a DIRECTORY → toml write must fail
  run bash -c "source '$LIB'; ws_write_root '$TEST_REPO' api"
  [ "$status" -ne 0 ]
  [ -f "$TEST_REPO/workspace.yml" ]                 # step 1 completed
  [ -d "$TEST_REPO/.speccraft/speccraft.toml" ]     # never flipped to a file
}

@test "ws_write_root: an existing workspace.yml is preserved byte-for-byte" {
  mkdir -p "$TEST_REPO/.speccraft"
  printf '# curated\nmembers:\n  - path: hand\n' > "$TEST_REPO/workspace.yml"
  cp "$TEST_REPO/workspace.yml" "$TEST_REPO/before"
  ws_write_root "$TEST_REPO" api core
  run cmp -s "$TEST_REPO/before" "$TEST_REPO/workspace.yml"
  [ "$status" -eq 0 ]
}

@test "ws_write_root: does not eagerly create .speccraft/ledger.md" {
  mkdir -p "$TEST_REPO/.speccraft"
  ws_write_root "$TEST_REPO"
  [ ! -e "$TEST_REPO/.speccraft/ledger.md" ]
}

@test "ws_write_root: an existing ledger.md is preserved unchanged" {
  mkdir -p "$TEST_REPO/.speccraft"
  printf 'existing ledger\n' > "$TEST_REPO/.speccraft/ledger.md"
  ws_write_root "$TEST_REPO"
  run cat "$TEST_REPO/.speccraft/ledger.md"
  [ "$output" = "existing ledger" ]
}

# --- commands/init.md wiring (source-scan meta-tests; spec-0032 discipline) ---

@test "init.md argument-hint advertises [--workspace] [--force]" {
  run grep -E '^argument-hint: "\[--workspace\] \[--force\]"' "$PLUGIN_DIR/commands/init.md"
  [ "$status" -eq 0 ]
}

@test "init.md wires the --workspace branch (ws_write_root + workspace index template)" {
  grep -q -- '--workspace' "$PLUGIN_DIR/commands/init.md"
  grep -q 'ws_write_root' "$PLUGIN_DIR/commands/init.md"
  grep -q 'index.workspace.md' "$PLUGIN_DIR/commands/init.md"
  grep -q 'ws_detect_members' "$PLUGIN_DIR/commands/init.md"
}
