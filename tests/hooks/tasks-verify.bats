#!/usr/bin/env bats
# Spec 0047 AC3 — `speccraft-state tasks-verify` exits 0 on EVERY tasks.md that
# already exists in this repo, live and archived.
#
# This fixture is deliberately non-vacuous. The corpus was audited while writing
# the spec and already contains every shape that can break the parser:
#
#   - specs/.archive/0001-speccraft-v1/tasks.md   — dotted AND multi-dot task ids
#                                                   at COLUMN 0 (T0.1, T0.5.1)
#   - specs/.archive/0016-…/tasks.md              — T1.1–T1.10 sub-checkboxes
#                                                   (multi-digit suffixes), a
#                                                   deeper `- [x] #1 …` prose
#                                                   level, **bold** task text,
#                                                   and both id: and spec: keys
#   - several archived files                      — unticked tasks, incl. an
#                                                   unticked parent with unticked
#                                                   children (0016 T5)
#
# The column-0 dotted-id case was a genuine RED found by running the binary over
# the real corpus: an earlier grammar rejected `T0.1` as a misplaced
# sub-checkbox. Only indentation makes a sub-checkbox.

setup() {
  PLUGIN_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  if [ ! -x "$PLUGIN_DIR/bin/speccraft-state" ]; then
    ( cd "$PLUGIN_DIR/tools" && go build -o ../bin/speccraft-state ./cmd/speccraft-state )
  fi
  export PATH="$PLUGIN_DIR/bin:$PATH"
  export PLUGIN_DIR
}

@test "tasks-verify: every existing tasks.md in specs/ and specs/.archive/ is clean" {
  cd "$PLUGIN_DIR"
  local failed=0 checked=0
  for f in specs/*/tasks.md specs/.archive/*/tasks.md; do
    [ -e "$f" ] || continue
    checked=$((checked + 1))
    if ! out="$(speccraft-state tasks-verify "$f" 2>&1)"; then
      echo "NOT CLEAN: $f"
      echo "$out"
      failed=$((failed + 1))
    fi
  done
  [ "$checked" -gt 0 ]
  [ "$failed" -eq 0 ]
}

@test "tasks-verify: the multi-digit-suffix + deep-prose archive file parses (0016)" {
  cd "$PLUGIN_DIR"
  f=specs/.archive/0016-scrub-readme-v1-spec-cgc-routing/tasks.md
  [ -f "$f" ]
  run speccraft-state tasks-verify "$f"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "tasks-verify: the column-0 dotted-id archive file parses (0001)" {
  cd "$PLUGIN_DIR"
  f=specs/.archive/0001-speccraft-v1/tasks.md
  [ -f "$f" ]
  run speccraft-state tasks-verify "$f"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "tasks-verify: this spec's own contract-bearing tasks.md is clean" {
  cd "$PLUGIN_DIR"
  f=specs/0047-done-means-contract/tasks.md
  if [ -f "$f" ]; then
    run speccraft-state tasks-verify "$f"
    [ "$status" -eq 0 ]
  fi
}

@test "tasks-verify: usage without a path exits 2 and states the prose boundary" {
  run speccraft-state tasks-verify
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "never verified"
  echo "$output" | grep -q "side effects"
}
