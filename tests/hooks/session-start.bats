#!/usr/bin/env bats
# Tests for hooks/session-start.sh

setup() {
  PLUGIN_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  HOOK="$PLUGIN_DIR/hooks/session-start.sh"
  TEST_REPO="$(mktemp -d)"
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR"
  export PATH="$PLUGIN_DIR/bin:$PATH"
  # Spec 0050 defect B. The hook runs the REAL scripts/install-binaries.sh against
  # the REAL plugin root, so with no `.binary-version` stamp present — it is
  # gitignored, hence absent on every fresh checkout — the installer downloaded the
  # last RELEASE tarball and untarred it over this repo's bin/. In CI that replaced
  # the binaries built from HEAD minutes earlier, and because this file sorts before
  # tasks-verify.bats, four later tests failed with `unknown subcommand:
  # tasks-verify` — a subcommand that exists at HEAD and not in the release.
  #
  # Pinning the base at an unreachable file:// URL keeps the real installer under
  # test while making the download branch fail deterministically: it falls back to
  # building from THIS tree, which can only ever produce current binaries. The
  # suite must never be able to make the repo's bin/ older than its source.
  export SPECCRAFT_RELEASE_BASE="file:///nonexistent/speccraft-release-base"
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
