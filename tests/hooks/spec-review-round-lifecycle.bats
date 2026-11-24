#!/usr/bin/env bats
# Spec 0054 ACs 14d / 15 / 27 — the round directory's lifecycle.
#
# The round dir holds every reviewer's payload and the path each writes its
# verdict to. So cleanup has exactly two jobs that pull against each other:
# it must run on EVERY exit path, including the ones nobody plans for, and it
# must NEVER run while a reviewer might still write there. Deleting a live
# reviewer's output path does not fail loudly — the reviewer writes into a
# removed directory and the round records `subagent-no-output`, which reads as
# the reviewer's fault.
#
# "Proven terminal" is the predicate that reconciles them: completed, timed
# out, or confirmed stopped. Proven from the round's OWN records, never from
# the clock — a reviewer that has not been heard from is not terminal just
# because its deadline passed.
#
# Quarantine is the single exception: a reviewer that may still be running
# keeps the dir, and only an operator (or, for codex-plugin, a probe) releases
# it.

setup() {
  PLUGIN_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  LIB="$PLUGIN_DIR/commands/spec/review.lib.sh"
  # Sourced in setup as well as in each test, because the round dir is created
  # here. Each @test re-sources it for its own shell.
  . "$LIB"
  RUNBOOK="$PLUGIN_DIR/skills/review-round/SKILL.md"
  export PATH="$PLUGIN_DIR/bin:$PATH"
  TEST_DIR="$(mktemp -d)"
  # A real repo and a REAL round dir. review_round_cleanup refuses any path
  # outside the `.review-rounds` parent — correctly, since it ends in `rm -rf`
  # — so a bare mktemp dir would make every cleanup row pass on the wrong
  # refusal, which is how the first draft of this file read green.
  REPO="$TEST_DIR/repo"
  mkdir -p "$REPO/.speccraft"
  cd "$REPO"
  ROUND_DIR="$(review_round_dir_create spec 0001 600)"
}

teardown() {
  cd /
  rm -rf "$TEST_DIR"
}

# ---------------------------------------------------------------------------
# review_round_all_terminal
# ---------------------------------------------------------------------------

@test "a round with no recorded reviewers is terminal" {
  source "$LIB"
  # Every pre-subagent round: nothing was launched through the record, so
  # there is nothing that could still be writing. A predicate that answered
  # "pending" here would make cleanup unreachable for cli-only rounds.
  run review_round_all_terminal "$ROUND_DIR"
  [ "$status" -eq 0 ]
}

@test "a launched reviewer that has not been heard from is NOT terminal" {
  source "$LIB"
  review_subagent_record "$ROUND_DIR" rev agent_r 600
  run review_round_all_terminal "$ROUND_DIR"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF 'rev' || {
    echo "the pending reviewer is not named: $output" >&2
    return 1
  }
}

@test "an expired deadline alone does not make a reviewer terminal" {
  source "$LIB"
  # The trap this predicate exists to avoid. A reviewer whose deadline passed
  # may still be running — that is exactly why TaskStop and the stop-failed
  # outcome exist. Treating the clock as proof would delete the dir under it.
  review_subagent_record "$ROUND_DIR" slow agent_s -5
  run review_subagent_deadline_expired "$ROUND_DIR" slow
  [ "$status" -eq 0 ]
  run review_round_all_terminal "$ROUND_DIR"
  [ "$status" -eq 1 ] || {
    echo "an expired deadline was taken as proof of termination" >&2
    return 1
  }
}

@test "a completion stamp makes a reviewer terminal" {
  source "$LIB"
  review_subagent_record "$ROUND_DIR" rev agent_r 600
  review_subagent_completed "$ROUND_DIR" rev > /dev/null
  run review_round_all_terminal "$ROUND_DIR"
  [ "$status" -eq 0 ]
}

@test "review_subagent_terminal stamps the non-completion terminal states" {
  source "$LIB"
  # A reviewer that timed out and was CONFIRMED stopped never completes, so it
  # needs its own proof. Without it, a round containing one timeout could never
  # be cleaned up.
  review_subagent_record "$ROUND_DIR" stopped agent_x 600
  run review_subagent_terminal "$ROUND_DIR" stopped timeout
  [ "$status" -eq 0 ]
  grep -qE '^terminal=[0-9]+ timeout$' "$ROUND_DIR/stopped.subagent" || {
    echo "no terminal= stamp in the record:" >&2
    cat "$ROUND_DIR/stopped.subagent" >&2
    return 1
  }
  run review_round_all_terminal "$ROUND_DIR"
  [ "$status" -eq 0 ]
}

@test "a terminal stamp requires a reason" {
  source "$LIB"
  review_subagent_record "$ROUND_DIR" stopped agent_x 600
  # "Terminal" with no reason is unauditable: an operator reading the record
  # cannot tell a confirmed stop from a completion from a give-up.
  run review_subagent_terminal "$ROUND_DIR" stopped
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | grep -qF 'reason'
}

@test "one pending reviewer among several keeps the whole round pending" {
  source "$LIB"
  review_subagent_record "$ROUND_DIR" a agent_a 600
  review_subagent_record "$ROUND_DIR" b agent_b 600
  review_subagent_record "$ROUND_DIR" c agent_c 600
  review_subagent_completed "$ROUND_DIR" a > /dev/null
  review_subagent_terminal  "$ROUND_DIR" b timeout
  run review_round_all_terminal "$ROUND_DIR"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF 'c' || {
    echo "the one pending reviewer is not named: $output" >&2
    return 1
  }
  # …and naming only the pending one, not the terminal ones.
  printf '%s\n' "$output" | grep -qE '\ba\b' && {
    echo "a terminal reviewer was reported pending: $output" >&2
    return 1
  }
  return 0
}

@test "a missing round dir is a named error, not terminal" {
  source "$LIB"
  run review_round_all_terminal "$TEST_DIR/nodir"
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | grep -qF 'nodir'
}

# ---------------------------------------------------------------------------
# The cleanup gate
# ---------------------------------------------------------------------------

@test "cleanup refuses a round with a pending reviewer" {
  source "$LIB"
  review_subagent_record "$ROUND_DIR" rev agent_r 600
  run review_round_cleanup "$ROUND_DIR"
  [ "$status" -ne 0 ]
  [ -d "$ROUND_DIR" ] || {
    echo "the dir was removed while a reviewer was still pending" >&2
    return 1
  }
  # NOT `grep -qF 'rev'`: the function's OWN name,
  # `review_round_cleanup`, contains that substring, so the row passed on the
  # error message of a cleanup that refused for an entirely different reason.
  # Named reviewer, delimited, plus the word that says why.
  printf '%s\n' "$output" | grep -qiF 'pending' || {
    echo "the refusal does not say a reviewer is pending: $output" >&2
    return 1
  }
  printf '%s\n' "$output" | grep -qE '(^|[^a-z])rev([^a-z]|$)' || {
    echo "the refusal does not name the pending reviewer: $output" >&2
    return 1
  }
}

@test "cleanup proceeds once every reviewer is proven terminal" {
  source "$LIB"
  review_subagent_record "$ROUND_DIR" a agent_a 600
  review_subagent_record "$ROUND_DIR" b agent_b 600
  review_subagent_completed "$ROUND_DIR" a > /dev/null
  review_subagent_terminal  "$ROUND_DIR" b timeout
  run review_round_cleanup "$ROUND_DIR"
  [ "$status" -eq 0 ]
  [ ! -d "$ROUND_DIR" ] || {
    echo "the dir survived a fully terminal round" >&2
    return 1
  }
}

@test "the pending-reviewer gate bites: the same round cleans up after stamping" {
  source "$LIB"
  # Prove the refusal above is about the PENDING state and not about something
  # else in the dir — same dir, same reviewer, one stamp apart.
  review_subagent_record "$ROUND_DIR" rev agent_r 600
  run review_round_cleanup "$ROUND_DIR"
  [ "$status" -ne 0 ]
  review_subagent_completed "$ROUND_DIR" rev > /dev/null
  run review_round_cleanup "$ROUND_DIR"
  [ "$status" -eq 0 ]
  [ ! -d "$ROUND_DIR" ]
}

@test "a cli-only round still cleans up" {
  source "$LIB"
  # The regression floor: rounds with no subagent reviewers are the common
  # case, and the new gate must not strand them.
  printf 'payload\n' > "$ROUND_DIR/codex.payload"
  printf 'verdict: approve\n' > "$ROUND_DIR/codex.out"
  run review_round_cleanup "$ROUND_DIR"
  [ "$status" -eq 0 ]
  [ ! -d "$ROUND_DIR" ]
}

@test "a quarantined round is the one exit path that retains the dir" {
  source "$LIB"
  review_subagent_record "$ROUND_DIR" stuck agent_q 600
  review_subagent_stop_failed "$ROUND_DIR" stuck > /dev/null
  # Even fully stamped as terminal, the quarantine keeps it.
  review_subagent_terminal "$ROUND_DIR" stuck stop-failed
  run review_round_cleanup "$ROUND_DIR"
  [ "$status" -ne 0 ]
  [ -d "$ROUND_DIR" ]
  printf '%s\n' "$output" | grep -qiF 'quarantin'
}

# ---------------------------------------------------------------------------
# Quarantine with more than one unresolved reviewer (round 8)
# ---------------------------------------------------------------------------

@test "two stop-failures both appear in the quarantine record" {
  source "$LIB"
  # The defect: the record was written with `mv -f`, so the second
  # stop-failure OVERWROTE the first and the operator lost that agent's
  # handle entirely. Worse, resolving the surviving record would release the
  # dir while the first reviewer might still be writing to it.
  review_subagent_record "$ROUND_DIR" one task_1 600
  review_subagent_record "$ROUND_DIR" two task_2 600
  review_subagent_stop_failed "$ROUND_DIR" one > /dev/null
  review_subagent_stop_failed "$ROUND_DIR" two > /dev/null
  grep -qF 'task_1' "$ROUND_DIR/quarantine" || {
    echo "the first agent's handle was lost:" >&2
    cat "$ROUND_DIR/quarantine" >&2
    return 1
  }
  grep -qF 'task_2' "$ROUND_DIR/quarantine" || {
    echo "the second agent's handle is missing:" >&2
    cat "$ROUND_DIR/quarantine" >&2
    return 1
  }
}

@test "the same reviewer quarantined twice is recorded once" {
  source "$LIB"
  # Idempotent: a retried stop must not grow the record, or the count below
  # stops meaning anything.
  review_subagent_record "$ROUND_DIR" one task_1 600
  review_subagent_stop_failed "$ROUND_DIR" one > /dev/null
  review_subagent_stop_failed "$ROUND_DIR" one > /dev/null
  [ "$(grep -c '^id task_1$' "$ROUND_DIR/quarantine")" -eq 1 ] || {
    echo "a retried stop duplicated the record:" >&2
    cat "$ROUND_DIR/quarantine" >&2
    return 1
  }
}

@test "review_round_quarantine_count reports how many reviewers are unresolved" {
  source "$LIB"
  review_subagent_record "$ROUND_DIR" one task_1 600
  review_subagent_record "$ROUND_DIR" two task_2 600
  run review_round_quarantine_count "$ROUND_DIR"
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
  review_subagent_stop_failed "$ROUND_DIR" one > /dev/null
  run review_round_quarantine_count "$ROUND_DIR"
  [ "$output" = "1" ]
  review_subagent_stop_failed "$ROUND_DIR" two > /dev/null
  run review_round_quarantine_count "$ROUND_DIR"
  [ "$output" = "2" ]
}

@test "cleanup names how many reviewers are quarantined" {
  source "$LIB"
  review_subagent_record "$ROUND_DIR" one task_1 600
  review_subagent_record "$ROUND_DIR" two task_2 600
  review_subagent_stop_failed "$ROUND_DIR" one > /dev/null
  review_subagent_stop_failed "$ROUND_DIR" two > /dev/null
  run review_round_cleanup "$ROUND_DIR"
  [ "$status" -ne 0 ]
  # An operator told "quarantined (subagent-stop-failed task_2)" would resolve
  # that one and expect the dir to go away. It must say there are two.
  printf '%s\n' "$output" | grep -qE '2 ' || {
    echo "the refusal does not say how many are unresolved: $output" >&2
    return 1
  }
}

@test "the first quarantine record still drives the existing readers" {
  source "$LIB"
  # The regression floor for the append change: _review_quarantine_field and
  # review_round_quarantine_resolve read the FIRST record, and the sweep's
  # report format is pinned by spec 0054's own earlier tests.
  review_subagent_record "$ROUND_DIR" one task_1 600
  review_subagent_record "$ROUND_DIR" two task_2 600
  review_subagent_stop_failed "$ROUND_DIR" one > /dev/null
  review_subagent_stop_failed "$ROUND_DIR" two > /dev/null
  [ "$(_review_quarantine_field "$ROUND_DIR" id)" = "task_1" ]
  [ "$(_review_quarantine_field "$ROUND_DIR" outcome)" = "subagent-stop-failed" ]
  [ "$(_review_quarantine_field "$ROUND_DIR" mode)" = "subagent" ]
}

# ---------------------------------------------------------------------------
# The runbook
# ---------------------------------------------------------------------------

@test "the runbook's cleanup step gates on the terminal predicate" {
  grep -qF 'review_round_all_terminal' "$RUNBOOK" || {
    echo "the runbook does not gate cleanup on the terminal predicate:" >&2
    grep -nF 'review_round_cleanup' -B3 "$RUNBOOK" >&2
    return 1
  }
}

@test "the runbook stamps a timed-out reviewer terminal" {
  # Otherwise a round containing one timeout can never be cleaned up, and the
  # sweep has to reclaim every such dir by lease expiry.
  grep -qF 'review_subagent_terminal' "$RUNBOOK" || {
    echo "the runbook never stamps a non-completing reviewer terminal:" >&2
    grep -nF 'TaskStop' "$RUNBOOK" >&2
    return 1
  }
}

@test "the runbook says an expired deadline is not proof of termination" {
  # Scoped to the CLEANUP section and anchored on the deadline, not on
  # "may still be running" anywhere in the file — §4's stop-failed paragraph
  # already says that about a different thing, which made this row vacuous.
  local sec
  sec="$(sed -n '/^## 7\./,$p' "$RUNBOOK")"
  [ -n "$sec" ] || { echo "could not isolate §7; row would be vacuous" >&2; return 1; }
  printf '%s\n' "$sec" | grep -qiE 'deadline[^.]*(not|never) (proof|proven|terminal)|an expired deadline is not' || {
    echo "§7 does not warn that an expired deadline is not proof:" >&2
    printf '%s\n' "$sec" | grep -niE 'terminal|deadline' >&2
    return 1
  }
}
