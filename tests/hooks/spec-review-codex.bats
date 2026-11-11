#!/usr/bin/env bats
# Spec 0054 Phase C — the codex-plugin adapter.
#
# Shape follows tests/hooks/spec-review-dispatch.bats (same lib under test):
# PLUGIN_DIR from BATS_TEST_FILENAME, ./bin FIRST on PATH, every derived path
# assigned in setup().
#
# This file starts with review_with_deadline (AC10), which bounds every single
# companion invocation. The JOB deadline is a different thing — AC6a's cancel
# path — because killing the local caller does not stop a Codex turn.

setup() {
  PLUGIN_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  LIB="$PLUGIN_DIR/commands/spec/review.lib.sh"
  STUB_NODE="$PLUGIN_DIR/tests/hooks/stubs/stub-node.sh"
  CODEX_FIX="$PLUGIN_DIR/tests/hooks/fixtures/review-dispatch/codex"
  export PATH="$PLUGIN_DIR/bin:$PATH"
  TEST_DIR="$(mktemp -d)"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# Assert a helper failed for ITS OWN reason, not on a bare "command not found"
# that a typo would also satisfy.
assert_named_failure() {
  local pattern="$1"
  [ "$status" -ne 0 ] || {
    echo "expected non-zero exit, got 0; output: $output" >&2
    return 1
  }
  printf '%s\n' "$output" | grep -qF -- "$pattern" || {
    echo "expected output to name '$pattern'; got: $output" >&2
    return 1
  }
}

# count_procs — how many processes currently run EXACTLY this command line.
# Matched whole-line against `ps -eo args=` rather than with `pkill -f`, which
# would also match this very test's own argv and so could never be trusted.
count_procs() {
  ps -eo args= | awk -v want="$1" '$0 == want' | wc -l | awk '{print $1}'
}

# ---------------------------------------------------------------------------
# AC10 — review_with_deadline
# ---------------------------------------------------------------------------

@test "review_with_deadline returns 124 when the deadline expires" {
  source "$LIB"
  run review_with_deadline 1 sleep 30
  [ "$status" -eq 124 ]
}

@test "review_with_deadline returns 124 within 5 s on a 30 s sleeper" {
  source "$LIB"
  local t0 t1
  t0=$(date +%s)
  run review_with_deadline 1 sleep 30
  t1=$(date +%s)
  [ "$status" -eq 124 ]
  # Wall-clock bound on the HARNESS only. It must not outlive the deadline by
  # anything like the command's own 30 s, which is what a missing kill looks
  # like from outside.
  [ "$((t1 - t0))" -lt 5 ]
}

@test "review_with_deadline leaves no process from the killed tree alive" {
  source "$LIB"
  # A marker argv unique to this test, so the count cannot collide with any
  # other sleeper on a busy CI box.
  # The `exec` wrapper is not decoration, and a bare `sleep 2531` will not do.
  # bats captures output through a pipe and holds fd 3 for its TAP stream; a
  # surviving orphan inherits both and bats then blocks forever, so a
  # regression in the kill path HANGS the suite instead of failing it. A bare
  # sleep cannot redirect its own descriptors, hence the shell that closes them
  # and then `exec`s — which keeps this a single direct child of the subshell,
  # exactly what this row means to test. Verified: with the kill recursion
  # removed, this row now reports a clean failure instead of wedging.
  local marker="sleep 2531"
  [ "$(count_procs "$marker")" -eq 0 ]
  run review_with_deadline 1 sh -c 'exec 3>&- >/dev/null 2>&1; exec sleep 2531' 3>&-
  [ "$status" -eq 124 ]
  sleep 1
  [ "$(count_procs "$marker")" -eq 0 ]
}

@test "review_with_deadline kills the whole descendant tree, not just the job it launched" {
  source "$LIB"
  # The command is a shell that spawns GRANDCHILDREN. Killing only the direct
  # child leaves these behind, which is the defect this row exists for.
  #
  # `3>&-` plus the inner `exec` is what makes a regression FAIL rather than
  # HANG. bats holds fd 3 for its TAP stream and blocks until every inheritor
  # closes it, so an orphan that outlives the subshell wedges the whole suite.
  # Closing stdout/stderr alone is NOT enough — that was the first attempt, and
  # it still hung, because fd 3 was the handle being held.
  local marker="sleep 2532"
  [ "$(count_procs "$marker")" -eq 0 ]
  run review_with_deadline 1 sh -c 'exec 3>&- >/dev/null 2>&1; sleep 2532 & sleep 2532 & sleep 2532' 3>&-
  [ "$status" -eq 124 ]
  sleep 1
  [ "$(count_procs "$marker")" -eq 0 ]
}

@test "review_with_deadline returns the command's own status when it finishes first" {
  source "$LIB"
  run review_with_deadline 5 true
  [ "$status" -eq 0 ]
}

@test "review_with_deadline preserves a non-zero command status" {
  source "$LIB"
  # 7, not 1: a function that collapsed every failure to 1 would pass a
  # 1-valued assertion while losing the companion's real exit code, and this
  # spec classifies on that exact code.
  run review_with_deadline 5 sh -c 'exit 7'
  [ "$status" -eq 7 ]
}

@test "review_with_deadline preserves a non-zero status with errexit ACTIVE" {
  # bats's `run` turns errexit OFF, so the plain status rows above cannot see
  # this defect at all: they passed with the subshell's `set +e` deleted. But
  # the .md command bodies source this lib and inherit its `set -euo pipefail`,
  # and under errexit the subshell aborts the instant the command exits
  # non-zero — before the status can be recorded — so every failing reviewer
  # would be reported as a timeout. This row runs the function the way
  # production does.
  # No `|| ...` guard here, deliberately. Appending one suspends errexit for
  # the whole left-hand side — nested functions and subshells included — so a
  # `|| printf` version of this row ALSO passed with the guard deleted. With no
  # guard, errexit is genuinely live and the function's return becomes the
  # shell's exit status, which is precisely what the command body sees.
  #
  # Correct lib: the status file is written, so 7 propagates.
  # Guard deleted: the subshell dies before writing it, the poll waits out the
  # full deadline, and 7 silently becomes 124 — a failure reported as a timeout.
  run bash -c "source '$LIB'; review_with_deadline 5 sh -c 'exit 7'"
  [ "$status" -eq 7 ]

  command -v zsh >/dev/null 2>&1 || { echo "zsh required — never silent-skip (see ci.yml)"; false; }
  run zsh -c "source '$LIB'; review_with_deadline 5 sh -c 'exit 7'"
  [ "$status" -eq 7 ]
}

@test "review_with_deadline names an error for a non-positive deadline" {
  source "$LIB"
  # The pattern must be the helper's OWN diagnostic, not just its name: the
  # shell's "command not found: review_with_deadline" contains the name too, so
  # a bare-name needle passes while the function does not exist at all. That is
  # exactly how this row false-passed when first written.
  run review_with_deadline 0 true
  assert_named_failure 'deadline must be a positive integer'
  [ "$status" -ne 124 ]

  run review_with_deadline -3 true
  assert_named_failure 'deadline must be a positive integer'

  run review_with_deadline abc true
  assert_named_failure 'deadline must be a positive integer'
}

@test "review_with_deadline emits nothing on stdout for a silent command" {
  source "$LIB"
  # The caller parses the companion's stdout, so a job-control notice or a
  # stray diagnostic leaking into it would be read as reviewer output.
  run review_with_deadline 1 sleep 30
  [ "$status" -eq 124 ]
  [ -z "$output" ]
}

@test "review_with_deadline passes the command's own stdout through unaltered" {
  source "$LIB"
  run review_with_deadline 5 printf 'hello\n'
  [ "$status" -eq 0 ]
  [ "$output" = "hello" ]
}

@test "review_with_deadline uses no timeout(1)" {
  # macOS has no timeout(1), so reaching for it would work in CI and fail on
  # the platform this convention exists to protect.
  run grep -nE '(^|[^[:alnum:]_-])timeout[[:space:]]+[0-9]' "$LIB"
  [ "$status" -ne 0 ]
}

@test "review_with_deadline uses no wait -n, which zsh does not support" {
  # The regression floor for a real defect: the plan prescribed that form, and
  # zsh answers it with "job not found: -n" (rc 127). The libs are sourced into
  # the caller's shell, which on macOS is zsh, so this is not hypothetical.
  #
  # Comment lines are excluded, the same scope boundary tests-portability-sweep
  # draws: the lib must be free to DOCUMENT the form it refuses to use, and the
  # first version of this guard flagged its own explanatory comment. The
  # mutation test below proves the filter did not make the guard inert.
  run sh -c "grep -vE '^[[:space:]]*#' '$LIB' | grep -nE 'wait[[:space:]]+-n'"
  [ "$status" -ne 0 ]
}

@test "the wait -n guard bites on an executable line" {
  # Proves the comment filter above did not render the guard inert.
  local probe="$TEST_DIR/probe.lib.sh"
  {
    echo '# a comment mentioning wait -n must NOT trip the guard'
    echo 'f() { wait -n; }'
  } > "$probe"

  run sh -c "grep -vE '^[[:space:]]*#' '$probe' | grep -nE 'wait[[:space:]]+-n'"
  [ "$status" -eq 0 ]

  # ...and with the executable line removed, the surviving comment does not.
  echo '# a comment mentioning wait -n' > "$probe"
  run sh -c "grep -vE '^[[:space:]]*#' '$probe' | grep -nE 'wait[[:space:]]+-n'"
  [ "$status" -ne 0 ]
}

@test "review_with_deadline uses no job-control option, which zsh refuses in a script" {
  # `set -m` is the other obvious route to a killable process group. zsh rejects
  # it outright in a non-interactive script ("can't change option: -m"), and a
  # lib must not change the CALLER's shell options anyway.
  run grep -nE '^[[:space:]]*set[[:space:]]+[-+]m([[:space:]]|$)' "$LIB"
  [ "$status" -ne 0 ]
}

@test "review_with_deadline works when EXECUTED under real zsh, not merely sourced" {
  # lib-zsh-safety.bats proves every lib SOURCES under zsh. That cannot catch a
  # function whose BODY is bash-only — `wait -n` sources fine and fails at call
  # time. This leg actually runs the function under zsh.
  command -v zsh >/dev/null 2>&1 || { echo "zsh required — never silent-skip (see ci.yml)"; false; }

  # `set +e` after sourcing is required, not a convenience: the lib turns on
  # `set -e` at source time, so a 124 return would abort the zsh shell before
  # the echo could report it — which is how this row first failed, with the
  # function working correctly.
  run zsh -c "source '$LIB'; set +e; review_with_deadline 1 sleep 2533; echo \"rc=\$?\""
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qxF 'rc=124' || {
    echo "expected rc=124 under zsh; got: $output" >&2
    return 1
  }

  run zsh -c "source '$LIB'; set +e; review_with_deadline 5 sh -c 'exit 7'; echo \"rc=\$?\""
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qxF 'rc=7' || {
    echo "expected the command's own status under zsh; got: $output" >&2
    return 1
  }

  # And the tree really is reaped under zsh too, not merely reported as 124.
  sleep 1
  [ "$(count_procs "sleep 2533")" -eq 0 ]
}
