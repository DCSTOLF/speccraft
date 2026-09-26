#!/usr/bin/env bats
# Spec 0050 AC8 — the SessionStart hook must not install RELEASE binaries over
# freshly built ones.
#
# WHAT HAPPENED. `tests/hooks/session-start.bats` runs the real
# `hooks/session-start.sh` with CLAUDE_PLUGIN_ROOT pointed at this repository.
# That hook calls `scripts/install-binaries.sh`, which — finding no
# `.binary-version` stamp, since it is gitignored and absent on a fresh checkout —
# downloaded the v1.16.0 release tarball and untarred it over `bin/`, replacing
# the binaries CI had built from HEAD minutes earlier.
#
# `session-start.bats` sorts before `tasks-verify.bats`, so by the time the latter
# ran, `bin/speccraft-state` was the last RELEASED build. `tasks-verify` shipped in
# spec 0047 and is still unreleased, so four tests failed with
# `unknown subcommand: tasks-verify` — a genuine capability gap reported as a
# parser bug.
#
# The clobber is not new. It has happened on every CI run for as long as the test
# has existed, and was harmless only while no test needed a subcommand newer than
# the last release. The first unreleased subcommand turned a long-standing latent
# fault into eight consecutive red runs on main.
#
# TWO INDEPENDENT PINS, because either alone leaves a hole:
#   1. The bats suite must not be able to fetch a release at all (protects a
#      developer's working tree, where CI's stamp does not exist).
#   2. Both bats CI jobs must stamp `.binary-version` after building, so the
#      installer takes its fast path and never reaches the network.

setup() {
  PLUGIN_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  CI="$PLUGIN_DIR/.github/workflows/ci.yml"
  SS="$PLUGIN_DIR/tests/hooks/session-start.bats"
  export PLUGIN_DIR CI SS
}

@test "session-start.bats cannot fetch a release build over the repo's bin/" {
  # It must pin the download base away from GitHub Releases. Without this, running
  # the suite on a developer machine with no version stamp silently replaces a
  # locally built bin/ with the last release.
  run grep -n 'SPECCRAFT_RELEASE_BASE' "$SS"
  [ "$status" -eq 0 ] || {
    echo "session-start.bats runs the real installer against the real plugin root;"
    echo "without SPECCRAFT_RELEASE_BASE pinned it can download a release into bin/."
    false
  }
  # And the pinned base must not be the live releases host.
  run grep -n 'SPECCRAFT_RELEASE_BASE=.*github\.com' "$SS"
  [ "$status" -ne 0 ] || { echo "the pinned base must not point at GitHub Releases:"; echo "$output"; false; }
}

# Asserted per JOB, not repo-wide: a single stamp line anywhere in ci.yml would
# satisfy a naive grep while one of the two bats jobs still downloaded a release.
# `hooks` and `hooks-macos` each build their own binaries and each need the stamp.
@test "ci.yml: both bats jobs stamp .binary-version after building" {
  local job
  for job in hooks hooks-macos; do
    # Slice the job's block: from its own key to the next top-level job key.
    run bash -c "awk '/^  ${job}:/{f=1;next} f && /^  [a-z][a-z0-9-]*:/{exit} f' '$CI' | grep -c 'binary-version'"
    [ "$output" -ge 1 ] || {
      echo "job '$job' builds binaries but writes no .binary-version stamp, so"
      echo "install-binaries.sh will download the last release over them."
      false
    }
  done
}

# Ordering matters as much as presence: a stamp written AFTER bats has already run
# protects nothing.
@test "ci.yml: the stamp is written before the bats step in each job" {
  local job
  for job in hooks hooks-macos; do
    local block stamp batsline
    block="$(awk -v j="  $job:" '$0==j{f=1;next} f && /^  [a-z][a-z0-9-]*:/{exit} f' "$CI")"
    stamp="$(printf '%s\n' "$block" | grep -n 'binary-version' | head -1 | cut -d: -f1)"
    batsline="$(printf '%s\n' "$block" | grep -n 'bats tests/hooks' | head -1 | cut -d: -f1)"
    [ -n "$stamp" ] || { echo "no stamp in job $job"; false; }
    [ -n "$batsline" ] || { echo "no bats invocation in job $job"; false; }
    [ "$stamp" -lt "$batsline" ] || {
      echo "job $job stamps at line $stamp but runs bats at $batsline — too late to prevent the clobber"
      false
    }
  done
}

# The stamp must carry the version install-binaries.sh actually compares against
# (`.claude-plugin/plugin.json`'s `version`), not a hardcoded literal that would
# silently stop matching at the next release.
@test "ci.yml: the stamp is derived from plugin.json, not hardcoded" {
  run grep -nE 'binary-version' "$CI"
  [ "$status" -eq 0 ]
  run grep -nE 'binary-version' "$CI"
  echo "$output" | grep -q 'plugin.json' || {
    echo "the stamp must be read from .claude-plugin/plugin.json so it tracks the"
    echo "version install-binaries.sh compares against:"
    echo "$output"
    false
  }
}
