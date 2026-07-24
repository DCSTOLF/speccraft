#!/usr/bin/env bats
# tests/hooks/lib-zsh-safety.bats — spec 0030 AC8 + AC10.
#
# Command libs are `source`d into the caller's shell by the .md command bodies.
# On macOS that shell is zsh, which reserves parameters like `status` — a bare
# `status` local aborts the source with "read-only variable: status" under
# `set -u`. A bash harness cannot reproduce this (bash has no such reserved
# names), so these legs run REAL zsh, mirroring spec 0029's
# Test_consolidate_lib_sources_under_real_zsh. zsh is required, never
# silent-skipped (ci.yml installs it).

setup() {
  PLUGIN_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  REVISE_LIB="$PLUGIN_DIR/commands/spec/revise.lib.sh"
  FIX="$(mktemp -d)"
  printf -- '---\nid: "0001"\nstatus: draft\n---\n\n# x\n' > "$FIX/draft.md"
  printf -- '---\nid: "0001"\nstatus: closed\n---\n\n# x\n' > "$FIX/closed.md"
}

teardown() {
  [ -n "${FIX:-}" ] && rm -rf "$FIX"
}

# AC8 — every command lib must `source` cleanly under real zsh with set -u.
@test "AC8: every commands/**/*.lib.sh sources under real zsh (set -u), no stderr" {
  command -v zsh >/dev/null 2>&1 || { echo "zsh required — never silent-skip (see ci.yml)"; false; }
  local lib fail=0
  while IFS= read -r lib; do
    run zsh -uc "source '$lib'"
    if [ "$status" -ne 0 ] || [ -n "$output" ]; then
      echo "FAIL sourcing under zsh: $lib (exit=$status)"
      echo "$output"
      fail=1
    fi
  done < <(find "$PLUGIN_DIR/commands" -name '*.lib.sh' | sort)
  [ "$fail" -eq 0 ]
}

# Backstop — the same libs must still source cleanly under bash -u (no regression).
@test "AC8: every commands/**/*.lib.sh still sources under bash (set -u)" {
  local lib fail=0
  while IFS= read -r lib; do
    run bash -uc "source '$lib'"
    if [ "$status" -ne 0 ]; then
      echo "FAIL sourcing under bash: $lib (exit=$status)"
      echo "$output"
      fail=1
    fi
  done < <(find "$PLUGIN_DIR/commands" -name '*.lib.sh' | sort)
  [ "$fail" -eq 0 ]
}

# AC10 — preflight_status_gate runs correctly when revise.lib.sh is sourced into
# zsh: a draft spec returns 0, with no reserved-variable diagnostic.
@test "AC10: preflight_status_gate under zsh — draft returns 0, no reserved-var diagnostic" {
  run zsh -uc "source '$REVISE_LIB'; preflight_status_gate '$FIX/draft.md'"
  [ "$status" -eq 0 ]
  [[ "$output" != *"read-only variable"* ]]
}

# AC10 — a non-revisable status (closed) returns non-zero because of the status
# gate itself, NOT because of a zsh reserved-name abort.
@test "AC10: preflight_status_gate under zsh — closed returns non-zero via the gate, no reserved-var diagnostic" {
  run zsh -uc "source '$REVISE_LIB'; preflight_status_gate '$FIX/closed.md'"
  [ "$status" -ne 0 ]
  [[ "$output" != *"read-only variable"* ]]
}
