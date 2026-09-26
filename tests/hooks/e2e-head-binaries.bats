#!/usr/bin/env bats
# Spec 0050 AC14/AC15 — the E2E suite must exercise HEAD, not the last release.
#
# `tests/e2e/run.sh` loads the plugin with `--plugin-dir "$PLUGIN_DIR"`, which gets
# HEAD's commands, hooks, agents and skills. The BINARIES those shell out to came from
# somewhere else entirely: the SessionStart hook runs `scripts/install-binaries.sh`,
# which — finding no `.binary-version` stamp, since it is gitignored and therefore
# absent on a fresh checkout — DOWNLOADED the last release into `$PLUGIN_DIR/bin/`.
#
# So the suite validated HEAD's markdown against RELEASE Go, and every command that
# referenced a subcommand added since that release silently degraded to a fallback.
# `/speccraft:spec:close` step 2 calls `tasks-verify` (spec 0047, unreleased): the agent
# reported it missing, ran each `done:` predicate by hand, hit a stale locator and
# stopped for a decision. The suite failed at `exists changelog.md` — three steps
# downstream of the actual cause, which is why this is pinned here and not left to the
# next reader of an e2e log.
#
# Pinned in bats rather than inside run.sh because run.sh needs credits and a
# devcontainer to execute; these are structural assertions about it that cost nothing.

setup() {
  PLUGIN_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  RUN="$PLUGIN_DIR/tests/e2e/run.sh"
  export PLUGIN_DIR RUN
}

@test "run.sh builds the plugin's binaries from source" {
  run grep -nE 'go build -o "\$PLUGIN_DIR/bin/' "$RUN"
  [ "$status" -eq 0 ] || {
    echo "run.sh must build \$PLUGIN_DIR/bin/* from source; otherwise the SessionStart"
    echo "hook downloads the last release over them and the suite tests a release."
    false
  }
}

@test "run.sh stamps .binary-version so install-binaries.sh cannot download a release" {
  run grep -n 'binary-version' "$RUN"
  [ "$status" -eq 0 ] || { echo "no version stamp in run.sh — the installer will download"; false; }
  # Derived from plugin.json, not hardcoded: the installer compares against that exact
  # value, so a literal would stop matching at the next version bump and the download
  # would quietly come back.
  echo "$output" | grep -q 'plugin.json' || {
    echo "the stamp must be read from .claude-plugin/plugin.json:"; echo "$output"; false
  }
}

@test "run.sh builds and stamps BEFORE the first claude invocation" {
  local build stamp firstclaude
  build="$(grep -n 'go build -o "\$PLUGIN_DIR/bin/' "$RUN" | head -1 | cut -d: -f1)"
  stamp="$(grep -n 'binary-version' "$RUN" | head -1 | cut -d: -f1)"
  # The first LIFECYCLE claude call. `run_claude()`'s own definition mentions
  # $CLAUDE_BIN too, so anchor on the call site, not the definition.
  firstclaude="$(grep -n 'run_claude "' "$RUN" | head -1 | cut -d: -f1)"
  [ -n "$build" ] && [ -n "$stamp" ] && [ -n "$firstclaude" ]
  [ "$build" -lt "$firstclaude" ] || { echo "build at $build is after the first claude call at $firstclaude"; false; }
  [ "$stamp" -lt "$firstclaude" ] || { echo "stamp at $stamp is after the first claude call at $firstclaude"; false; }
}

# The build is worthless if it silently produces a binary without the subcommands
# HEAD's commands call. run.sh must assert, not assume.
@test "run.sh verifies the built binary actually answers tasks-verify" {
  run grep -n 'tasks-verify' "$RUN"
  [ "$status" -eq 0 ] || {
    echo "run.sh must prove the built binary supports tasks-verify (spec 0047), or a"
    echo "silent fallback to release behaviour stays possible."
    false
  }
}

# AC15 — the close prompt must resolve the task-completion gate deterministically.
@test "the [10/13] close prompt tells the agent how to handle gate violations" {
  run grep -n 'task-completion gate reports violations' "$RUN"
  [ "$status" -eq 0 ] || {
    echo "close.md step 2 STOPS on violations and asks for a decision. With no guidance"
    echo "the run's outcome depends on whether the done: predicates authored at [8/13]"
    echo "still match the code written at [9/13] — which twice they did not."
    false
  }
}

# The gate must keep its teeth: bypassing it would mean the e2e stops exercising the
# one mechanism spec 0047 added.
@test "the close prompt does NOT hand the agent the bypass token" {
  # Comment lines excluded: the comment above the prompt legitimately NAMES the token
  # while explaining why it is withheld. Only a live line may not carry it.
  run bash -c "grep -n 'SKIP-TASKS-VERIFY' '$RUN' | grep -vE '^[0-9]+:[[:space:]]*#'"
  [ "$status" -ne 0 ] || {
    echo "supplying the bypass token would make every e2e close skip the gate:"
    echo "$output"
    false
  }
}

# And it must not invite the other cheat: making a predicate pass by weakening it.
@test "the close prompt forbids weakening a predicate" {
  grep -q 'do NOT weaken a predicate' "$RUN"
}
