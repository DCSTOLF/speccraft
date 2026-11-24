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
  # A REAL git repo: review_tree_snapshot enumerates through `git ls-files` and
  # refuses to report an empty snapshot outside a work tree (spec 0054 AC17b).
  # Without `git init` the lease row below failed on THAT, not on a re-stamp —
  # which is the guard doing its job, and a reminder to read the message rather
  # than the exit code.
  git init -q .
  git config user.email t@example.com
  git config user.name  Test
  printf 'x\n' > .speccraft/index.md
  git add -A
  git commit -q -m init
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

# ---------------------------------------------------------------------------
# AC15 — the lease is written ONCE and never renewed.
#
# "Never renewed" is a claim about every code path, so the load-bearing
# assertion is byte-equality of the lease file across a whole round. That
# catches a re-stamp under ANY name — `_touch`, `_bump`, an inlined
# `date`-plus-arithmetic, a well-meaning `review_round_lease_write` call from a
# later phase — where a grep for `lease_renew` only catches the obvious one.
#
# The margin that makes it safe is `+300 s` on top of `review_timeout_s`. Every
# path a round can take is bounded INSIDE that, or is covered by quarantine
# instead of by the lease; the survival rows below walk each one.
# ---------------------------------------------------------------------------

lease_bytes() {
  cksum < "$1/lease"
}

@test "the lease expiry is review_timeout_s plus the 300s margin" {
  source "$LIB"
  local dir expiry now
  now="$(date +%s)"
  dir="$(review_round_dir_create spec 0002 600)"
  expiry="$(awk '$1 == "expires_at" { print $2; exit }' "$dir/lease")"
  [ -n "$expiry" ] || { echo "no expiry in the lease" >&2; return 1; }
  # now + 600 + 300, allowing a couple of seconds of clock drift between the
  # two `date` calls.
  [ "$expiry" -ge "$((now + 900))" ] && [ "$expiry" -le "$((now + 903))" ] || {
    echo "expiry $expiry is not now+900 (now was $now)" >&2
    return 1
  }
}

@test "the lease file is byte-identical before and after a full round sequence" {
  source "$LIB"
  local before after
  before="$(lease_bytes "$ROUND_DIR")"

  # A whole round, through the helpers a real round calls, in order.
  review_tree_snapshot > "$ROUND_DIR/tree.before"
  printf 'payload\n' > "$ROUND_DIR/sub.payload"
  review_subagent_record "$ROUND_DIR" sub agent_s 600
  printf 'verdict: approve\n' > "$ROUND_DIR/sub.out"
  review_subagent_completed "$ROUND_DIR" sub > /dev/null
  printf 'sub %s\n' "$(review_subagent_collect "$ROUND_DIR" sub)" > /dev/null
  printf 'sub approve\n' > "$ROUND_DIR/outcomes"
  review_hash_compare_outputs "$ROUND_DIR" > /dev/null 2>&1 || true
  review_tree_snapshot > "$ROUND_DIR/tree.after"
  review_attribute_tree_outcomes "$ROUND_DIR" "$ROUND_DIR/outcomes" || true
  review_round_all_terminal "$ROUND_DIR"

  after="$(lease_bytes "$ROUND_DIR")"
  [ "$before" = "$after" ] || {
    echo "the lease was re-stamped during the round" >&2
    echo "  before: $before" >&2
    echo "  after:  $after" >&2
    return 1
  }
}

@test "the byte-equality row would notice a re-stamp" {
  source "$LIB"
  # Premise. Without it the row above passes on any round that happens not to
  # touch the lease for unrelated reasons, and a future re-stamp under a new
  # name would land silently.
  local before after
  before="$(lease_bytes "$ROUND_DIR")"
  review_round_lease_write "$ROUND_DIR" "$(( $(date +%s) + 9999 ))"
  after="$(lease_bytes "$ROUND_DIR")"
  [ "$before" != "$after" ] || {
    echo "rewriting the lease did not change its bytes, so the row is vacuous" >&2
    return 1
  }
}

# sweep_now — run the sweep from the fixture repo, swallowing its report.
sweep_now() {
  review_round_sweep > /dev/null 2>&1 || true
}

@test "a codex-plugin round polling to its review_timeout_s deadline survives a sweep" {
  source "$LIB"
  # The poll stops at review_timeout_s; the lease runs 300s past it. So a
  # round that used its ENTIRE budget still has five minutes of lease left.
  local dir expiry
  dir="$(review_round_dir_create spec 0003 600)"
  expiry="$(awk '$1 == "expires_at" { print $2; exit }' "$dir/lease")"
  # Simulate the poll having consumed the whole timeout by moving the lease's
  # clock reference, not by sleeping: rewrite the expiry to what it would be
  # 600s from now, i.e. the margin alone.
  review_round_lease_write "$dir" "$(( $(date +%s) + 300 ))"
  printf 'job-1\n' > "$dir/codexp.job"
  sweep_now
  [ -d "$dir" ] || {
    echo "a round inside its lease margin was swept" >&2
    return 1
  }
}

@test "a cancel plus one confirming status survives a sweep" {
  source "$LIB"
  local dir
  dir="$(review_round_dir_create spec 0004 600)"
  # One cancel and one status, each under review_with_deadline — tens of
  # seconds. Represented here by the lease still being far from expiry.
  review_with_deadline 5 true > /dev/null 2>&1 || true
  sweep_now
  [ -d "$dir" ]
}

@test "a subagent round to its deadline and TaskStop survives a sweep" {
  source "$LIB"
  local dir
  dir="$(review_round_dir_create spec 0005 600)"
  review_subagent_record "$dir" sub agent_s 600
  # The deadline passes and the reviewer is stopped — still inside the margin.
  review_round_lease_write "$dir" "$(( $(date +%s) + 300 ))"
  review_subagent_terminal "$dir" sub timeout
  sweep_now
  [ -d "$dir" ] || {
    echo "a stopped-reviewer round inside its margin was swept" >&2
    return 1
  }
}

@test "a cli-only round under review_with_deadline survives a sweep" {
  source "$LIB"
  local dir
  dir="$(review_round_dir_create spec 0006 600)"
  printf 'payload\n' > "$dir/codex.payload"
  review_with_deadline 5 true > /dev/null 2>&1 || true
  sweep_now
  [ -d "$dir" ]
}

@test "the survival rows are not vacuous: an EXPIRED lease really is swept" {
  source "$LIB"
  # Premise for all four. If the sweep never deleted anything, every row above
  # would pass with no mechanism at all.
  local dir
  dir="$(review_round_dir_create spec 0007 600)"
  review_round_lease_write "$dir" "$(( $(date +%s) - 10 ))"
  sweep_now
  [ ! -d "$dir" ] || {
    echo "the sweep did not reclaim a dir whose lease had expired" >&2
    return 1
  }
}

@test "a quarantined dir outlives its own expired lease, and is REPORTED" {
  source "$LIB"
  # Quarantine beats the lease, which is what lets an unbounded phase be safe
  # without renewal.
  local dir out
  dir="$(review_round_dir_create spec 0008 600)"
  review_subagent_record "$dir" stuck agent_q 600
  review_subagent_stop_failed "$dir" stuck > /dev/null
  review_round_lease_write "$dir" "$(( $(date +%s) - 10 ))"
  out="$(review_round_sweep 2>&1 || true)"
  [ -d "$dir" ] || {
    echo "a quarantined dir was reclaimed once its lease expired" >&2
    return 1
  }
  # The REPORT is the load-bearing half, and survival alone cannot test it.
  # Retention is DOUBLY protected: disabling the sweep's own quarantine check
  # fails no survival row, because review_round_cleanup independently refuses a
  # quarantined dir. Verified by mutation — `if false` on that check left every
  # `[ -d "$dir" ]` row green. The report line is what actually bites.
  printf '%s\n' "$out" | grep -qF 'quarantined' || {
    echo "the sweep did not report the retained dir:" >&2
    printf '%s\n' "$out" >&2
    return 1
  }
  printf '%s\n' "$out" | grep -qF 'agent_q' || {
    echo "the report does not name the unresolved agent:" >&2
    printf '%s\n' "$out" >&2
    return 1
  }
  printf '%s\n' "$out" | grep -qF 'lease-expired' || {
    echo "the report does not say the lease had expired:" >&2
    printf '%s\n' "$out" >&2
    return 1
  }
}

@test "no review lib defines a lease-renewal helper" {
  # A CONVENTION NUDGE, not the guard. The guard is the byte-equality row
  # above, which catches a re-stamp whatever it is called; this row only keeps
  # the obvious spelling from reappearing and reads as documentation of the
  # decision.
  local hits
  hits="$(grep -nE '^[[:space:]]*(review_round_lease_(renew|touch|bump|extend))\(\)' \
    "$PLUGIN_DIR"/commands/spec/review*.lib.sh 2>/dev/null || true)"
  [ -z "$hits" ] || {
    echo "a lease-renewal helper appeared:" >&2
    printf '%s\n' "$hits" >&2
    echo "Every round path is bounded inside the expiry, or quarantines." >&2
    return 1
  }
  # Premise: the pattern matches the shape it forbids.
  printf 'review_round_lease_renew() {\n  :\n}\n' > "$TEST_DIR/canary.lib.sh"
  grep -qE '^[[:space:]]*(review_round_lease_(renew|touch|bump|extend))\(\)' \
    "$TEST_DIR/canary.lib.sh" || {
    echo "the nudge pattern cannot match the shape it forbids" >&2
    return 1
  }
}

# ---------------------------------------------------------------------------
# AC25 / the token vocabulary — one table, pinned by a source scan.
#
# Twelve `failed <reason>` outcomes accreted across phases C, E and G, each
# introduced where it was needed. Nothing listed them, so nothing could tell a
# new reason from a TYPO of an existing one — and a typo'd reason is recorded,
# classified as a non-verdict, and reported to the operator as if it meant
# something.
#
# The table is the sole definition, and the scan below is what keeps it so.
# Same shape as the one-shared-parser-entrypoint pattern in conventions.md.
# ---------------------------------------------------------------------------

@test "REVIEW_FAILURE_REASONS lists every failure reason the libs emit" {
  source "$LIB"
  [ -n "${REVIEW_FAILURE_REASONS:-}" ] || {
    echo "no REVIEW_FAILURE_REASONS table" >&2
    return 1
  }
  # Every `failed <reason>` in a printf that writes an outcome. The reason is
  # the FIRST token after `failed`; sub-reasons (subagent-launch's
  # missing-write-tool, say) ride in the rest of the line.
  local emitted r missing=""
  emitted="$(grep -rhoE "printf '[^']*failed [a-z][a-z0-9-]+" \
    "$PLUGIN_DIR"/commands/spec/review*.lib.sh 2>/dev/null \
    | grep -oE 'failed [a-z][a-z0-9-]+' | awk '{print $2}' | sort -u)"
  [ -n "$emitted" ] || {
    echo "the scan found no emitted reasons; this row would be vacuous" >&2
    return 1
  }
  while IFS= read -r r; do
    [ -n "$r" ] || continue
    _review_list_has "$r" "$REVIEW_FAILURE_REASONS" || missing="$missing $r"
  done <<EOF
$emitted
EOF
  [ -z "$missing" ] || {
    echo "emitted but not registered in REVIEW_FAILURE_REASONS:$missing" >&2
    echo "Add it to the table, or it cannot be told from a typo." >&2
    return 1
  }
}

@test "the scan really sees the reasons the libs emit" {
  source "$LIB"
  # Premise. If the extraction pattern missed everything, the row above would
  # pass with an empty table.
  local emitted
  emitted="$(grep -rhoE "printf '[^']*failed [a-z][a-z0-9-]+" \
    "$PLUGIN_DIR"/commands/spec/review*.lib.sh 2>/dev/null \
    | grep -oE 'failed [a-z][a-z0-9-]+' | awk '{print $2}' | sort -u)"
  # A few known ones, each introduced by a different phase, so the scan cannot
  # be passing by covering only one file.
  local r
  for r in subagent-no-output subagent-stop-failed duplicate-output; do
    printf '%s\n' "$emitted" | grep -qxF "$r" || {
      echo "the scan missed '$r', which the libs demonstrably emit" >&2
      printf '%s\n' "$emitted" >&2
      return 1
    }
  done
  [ "$(printf '%s\n' "$emitted" | grep -c .)" -ge 8 ] || {
    echo "the scan found suspiciously few reasons:" >&2
    printf '%s\n' "$emitted" >&2
    return 1
  }
}

@test "review_failure_reason_known accepts a registered reason and refuses a typo" {
  source "$LIB"
  run review_failure_reason_known subagent-no-output
  [ "$status" -eq 0 ]
  run review_failure_reason_known subagent-stop-failed
  [ "$status" -eq 0 ]
  # The whole point: a near-miss must be distinguishable from a real reason.
  run review_failure_reason_known subagent-no-ouput
  [ "$status" -ne 0 ]
  printf '%s\n' "$output" | grep -qF 'subagent-no-ouput'
  run review_failure_reason_known ''
  [ "$status" -ne 0 ]
}

@test "the table is defined exactly once across the review libs" {
  # One definition, or the two copies drift and the scan above passes against
  # whichever happens to be sourced last.
  local n
  n="$(grep -c '^REVIEW_FAILURE_REASONS=' "$PLUGIN_DIR"/commands/spec/review*.lib.sh \
    | awk -F: '{ sum += $2 } END { print sum }')"
  [ "$n" -eq 1 ] || {
    echo "expected exactly 1 definition of REVIEW_FAILURE_REASONS, found $n" >&2
    grep -n '^REVIEW_FAILURE_REASONS=' "$PLUGIN_DIR"/commands/spec/review*.lib.sh >&2
    return 1
  }
}

@test "every registered reason is actually emitted somewhere" {
  source "$LIB"
  # The converse scan: a reason in the table that nothing emits is either dead
  # vocabulary or a sign that the emitting path was lost in a refactor. Either
  # way an operator could never see it, so it should not be documented as
  # possible.
  local r unused=""
  for r in $(printf '%s\n' "$REVIEW_FAILURE_REASONS" | tr ' ' '\n'); do
    [ -n "$r" ] || continue
    grep -rqF "failed $r" "$PLUGIN_DIR"/commands/spec/review*.lib.sh || unused="$unused $r"
  done
  [ -z "$unused" ] || {
    echo "registered but never emitted:$unused" >&2
    return 1
  }
}

# ---------------------------------------------------------------------------
# Phase H.5 — remediation from cross-model code-review round 9.
#
# The T65 cleanup gate was put inside `review_round_cleanup`, which the SWEEP
# also calls — and that broke lease-based reclamation for every round that
# launched a subagent, silently, because the sweep's `|| true` swallowed the
# refusal. Both round-9 reviewers found it independently.
#
# The distinction the fix rests on: the gate is for the round's OWN cleanup,
# while a stamp is still coming. The sweep reclaims rounds that were
# ABANDONED — the orchestrator died, so no stamp will ever arrive — and for
# those the EXPIRED LEASE is the proof instead. The lease margin
# (`review_timeout_s + 300 s`) already bounds every reviewer's deadline, so a
# subagent in a lease-expired round is necessarily past its own.
# ---------------------------------------------------------------------------

@test "the sweep reclaims an abandoned round that launched a subagent" {
  source "$LIB"
  local dir
  dir="$(review_round_dir_create spec 0009 600)"
  # The orchestrator crashed after launching: a record exists, no stamp ever
  # arrives, and the lease runs out.
  review_subagent_record "$dir" sub agent_s 600
  review_round_lease_write "$dir" "$(( $(date +%s) - 10 ))"
  sweep_now
  [ ! -d "$dir" ] || {
    echo "a lease-expired abandoned round was not reclaimed — AC14b's" >&2
    echo "'lease expired ⇒ removed' no longer holds for subagent rounds" >&2
    return 1
  }
}

@test "the round's own cleanup still refuses a pending reviewer" {
  source "$LIB"
  # The regression floor for the fix above: making the sweep able to reclaim
  # must NOT make the in-round path able to delete under a live reviewer.
  review_subagent_record "$ROUND_DIR" live agent_l 600
  run review_round_cleanup "$ROUND_DIR"
  [ "$status" -ne 0 ]
  [ -d "$ROUND_DIR" ]
  printf '%s\n' "$output" | grep -qiF 'pending'
}

@test "review_round_reclaim still refuses a quarantined dir" {
  source "$LIB"
  # Quarantine is the ONE state where a reviewer may genuinely still be running
  # past the lease, which is why it outranks the lease. The reclaim path drops
  # the terminal gate; it must not drop this.
  local dir
  dir="$(review_round_dir_create spec 0010 600)"
  review_subagent_record "$dir" stuck agent_q 600
  review_subagent_stop_failed "$dir" stuck > /dev/null
  review_round_lease_write "$dir" "$(( $(date +%s) - 10 ))"
  run review_round_reclaim "$dir"
  [ "$status" -ne 0 ]
  [ -d "$dir" ] || { echo "reclaim deleted a quarantined dir" >&2; return 1; }
  printf '%s\n' "$output" | grep -qiF 'quarantin'
}

@test "removing the quarantine file lets the sweep reclaim the round" {
  source "$LIB"
  # AC15a's documented operator action: "once the quarantine file is removed
  # (operator action) … the same sweep reclaims it". The T65 gate broke it —
  # review_subagent_stop_failed never stamped the agent terminal, so after the
  # operator removed the file the sweep called cleanup, cleanup refused
  # 'still pending', and the refusal was swallowed. The dir was then never
  # reclaimed AND never reported, because the quarantine file that produced the
  # report line was gone.
  local dir
  dir="$(review_round_dir_create spec 0011 600)"
  review_subagent_record "$dir" stuck agent_q 600
  review_subagent_stop_failed "$dir" stuck > /dev/null
  review_round_lease_write "$dir" "$(( $(date +%s) - 10 ))"
  rm -f "$dir/quarantine"
  sweep_now
  [ ! -d "$dir" ] || {
    echo "the operator's documented resolution did not reclaim the round" >&2
    return 1
  }
}

@test "the sweep REPORTS a lease-expired NON-quarantined round it cannot reclaim" {
  source "$LIB"
  # The else branch — not quarantined, lease expired, and the delete itself
  # fails. A `|| true` there left such rounds neither deleted nor mentioned,
  # on every sweep, forever: the operator had no way to learn the directory
  # existed. The quarantine branch has its own report line (next row), so a
  # row using a quarantined dir would exercise the wrong arm — which is how
  # the first version of this row passed against the `|| true`.
  [ "$(id -u)" -ne 0 ] || skip "a read-only parent does not deny unlink as root"
  local dir parent out
  dir="$(review_round_dir_create spec 0013 600)"
  review_round_lease_write "$dir" "$(( $(date +%s) - 10 ))"
  parent="$(review_round_parent)"
  chmod 0500 "$parent"
  out="$(review_round_sweep 2>&1 || true)"
  chmod 0700 "$parent"
  [ -d "$dir" ] || skip "the platform allowed the unlink; the report cannot be observed here"
  printf '%s\n' "$out" | grep -qF "$dir" || {
    echo "an unreclaimable lease-expired dir was not reported:" >&2
    printf '%s\n' "$out" >&2
    return 1
  }
  printf '%s\n' "$out" | grep -qF 'not reclaimable' || {
    echo "the report does not say why it was retained:" >&2
    printf '%s\n' "$out" >&2
    return 1
  }
}

@test "the sweep REPORTS a quarantined lease-expired round it cannot reclaim" {
  source "$LIB"
  # Never swallowed. A `|| true` here left such rounds neither deleted nor
  # mentioned, on every sweep, forever — the operator had no way to learn the
  # directory existed.
  local dir out
  dir="$(review_round_dir_create spec 0012 600)"
  review_subagent_record "$dir" stuck agent_q 600
  review_subagent_stop_failed "$dir" stuck > /dev/null
  review_round_lease_write "$dir" "$(( $(date +%s) - 10 ))"
  out="$(review_round_sweep 2>&1 || true)"
  [ -d "$dir" ]
  printf '%s\n' "$out" | grep -qF "$dir" || {
    echo "the retained dir was not named in the sweep's report:" >&2
    printf '%s\n' "$out" >&2
    return 1
  }
}

@test "review_round_quarantine_count prints one number for an id-less record" {
  source "$LIB"
  # `grep -c` prints 0 AND exits 1 with no match, so a
  # `grep -c … || printf '0\n'` fallback emitted "0" twice — and any caller
  # doing arithmetic on that got a syntax error rather than a count.
  printf 'outcome something\n' > "$ROUND_DIR/quarantine"
  run review_round_quarantine_count "$ROUND_DIR"
  [ "$status" -eq 0 ]
  [ "$output" = "0" ] || {
    echo "expected a single '0', got: '$output'" >&2
    return 1
  }
  [ "$(printf '%s\n' "$output" | grep -c .)" -eq 1 ]
}

@test "a malformed completion stamp is a named error, not an on-time verdict" {
  source "$LIB"
  # `[ "$x" -gt "$y" ]` on a non-integer errors with status 2, which `if`
  # reads as FALSE — so a malformed record quietly admitted the verdict as on
  # time. The sibling deadline predicate validated its value; collect did not.
  review_subagent_record "$ROUND_DIR" m agent_m 600
  printf 'verdict: approve\n' > "$ROUND_DIR/m.out"
  printf 'agent=m\nagent_id=agent_m\nlaunched=1\ndeadline=notanumber\ncompleted=5\n' \
    > "$ROUND_DIR/m.subagent"
  run review_subagent_collect "$ROUND_DIR" m
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | grep -qiF 'malformed'
  # …and the converse, so the validation cannot have simply rejected everything.
  printf 'agent=m\nagent_id=agent_m\nlaunched=1\ndeadline=99999999999\ncompleted=5\n' \
    > "$ROUND_DIR/m.subagent"
  run review_subagent_collect "$ROUND_DIR" m
  [ "$output" = "ok" ]
}

@test "the runbook handles the attribution's exit 2 rather than swallowing it" {
  # `|| true` discarded exit 2 (a missing snapshot) as well as the normal
  # exit 1, so a round whose integrity check could not RUN finalized as though
  # it had passed — an approval reaching synthesis unverified.
  grep -qE 'review_attribute_tree_outcomes[^|]*\|\| *true' "$RUNBOOK" && {
    echo "the runbook still swallows the attribution's exit status:" >&2
    grep -nF 'review_attribute_tree_outcomes' "$RUNBOOK" >&2
    return 1
  }
  grep -qE 'rc=\$\?' "$RUNBOOK" || {
    echo "the runbook does not capture the attribution's exit code" >&2
    return 1
  }
  grep -qE '"\$rc" -eq 2' "$RUNBOOK" || {
    echo "the runbook does not treat exit 2 as fatal:" >&2
    grep -nF 'review_attribute_tree_outcomes' -A4 "$RUNBOOK" >&2
    return 1
  }
}

@test "the runbook no longer describes the abandoned mtime mechanism" {
  # The code judges lateness by the completion stamp; §4 step 5 still said
  # "the artifact's own modification time". The runbook is what the
  # orchestrator follows, so a stale mechanism there is not a stale comment —
  # it is a stale instruction.
  grep -qiF 'modification time' "$RUNBOOK" && {
    echo "the runbook still teaches the mtime mechanism:" >&2
    grep -niF 'modification time' "$RUNBOOK" >&2
    return 1
  }
  grep -qF 'completion stamp from step 3' "$RUNBOOK" || {
    echo "the runbook does not point step 5 at the completion stamp" >&2
    return 1
  }
}
