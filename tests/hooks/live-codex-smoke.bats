#!/usr/bin/env bats
# Spec 0054 ACs 26 / 26a — the LIVE smoke, gated behind an explicit knob.
#
# NON-CI BY DESIGN. These two tests talk to a real Codex companion, consume
# real credits, and need a host where the plugin is installed and
# authenticated. Every other Codex-touching AC in this spec uses a stub `node`
# and a fake HOME; this is the only one that cannot.
#
# They run ONLY when SPECCRAFT_LIVE_CODEX_SMOKE=1. Without it they **skip with
# a message naming themselves and the knob** — they never pass silently. That
# matters because AC27's gate is "the whole bats suite green", and an engineer
# running the suite locally without `/codex:setup` must not be able to read
# that as having covered the live smoke. The third test here is NOT gated: it
# runs in CI and is what makes the skip auditable.
#
# What bats CAN and CANNOT prove, stated plainly:
#   CAN — the codex-plugin adapter really drives a live companion through
#         `task --background` → `status` → `result`, and a real cancel is
#         confirmed.
#   CANNOT — the `subagent` half of AC26. A subagent is launched by the
#         orchestrating session's Agent tool; no shell can start one. That half
#         is satisfied by running /speccraft:spec:review by hand and recording
#         it, which is why the AC says "manual, recorded in the changelog".
#
# So a green run of this file is NOT the whole of AC26. The changelog entry is.

SMOKE_KNOB="SPECCRAFT_LIVE_CODEX_SMOKE"

setup() {
  PLUGIN_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  LIB="$PLUGIN_DIR/commands/spec/review.lib.sh"
  export PATH="$PLUGIN_DIR/bin:$PATH"
  TEST_DIR="$(mktemp -d)"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# live_gate <ac> — skip unless the knob is exactly 1.
#
# Called BEFORE the lib is sourced, per this repo's skip-ordering rule
# (`spec-review-payload.bats` enforces it): a `skip` after a `source` has
# already run the sourced file's top level, so the skip no longer means "this
# test did nothing".
live_gate() {
  [ "${SPECCRAFT_LIVE_CODEX_SMOKE:-}" = "1" ] || skip \
    "$1 skipped: $SMOKE_KNOB is not 1 — the live smoke consumes real Codex credits and needs the plugin installed and authenticated"
}

# live_registry — a one-entry codex-plugin registry in $TEST_DIR.
live_registry() {
  local toml="$TEST_DIR/agents.toml"
  {
    printf '[[agents]]\n'
    printf 'name = "codex-plugin"\n'
    printf 'mode = "codex-plugin"\n'
    printf 'enabled = true\n'
    printf 'reference_read = true\n'
  } > "$toml"
  printf '%s\n' "$toml"
}

# live_launch <root> <toml> <payload> — launch a background job and echo its id.
#
# Drives the stages DIRECTLY rather than through `_review_codex_dispatch`,
# because that wrapper creates its launch file with `mktemp` and removes it, so
# a caller cannot get the job id afterwards — and the job id is exactly what
# ACs 26 and 26a require to be recorded. Uses the adapter's own launch idiom
# (`xargs -0 env`, never a bare `xargs -0`, which defaults to `echo` and
# launches nothing).
live_launch() {
  local root="$1" toml="$2" art="$3"
  local argv_file="$TEST_DIR/argv" launch_file="$TEST_DIR/launch"
  review_codex_task_argv "$toml" codex-plugin "$root" "$art" "$TEST_DIR" > "$argv_file"
  xargs -0 env < "$argv_file" > "$launch_file" 2>/dev/null
  review_codex_job_id "$launch_file"
}

@test "AC26 live codex-plugin plus subagent round (SPECCRAFT_LIVE_CODEX_SMOKE)" {
  live_gate "AC26"
  source "$LIB"

  local toml root version
  toml="$(live_registry)"

  # Resolve and preflight first: without the plugin this is a named refusal,
  # not a hang.
  root="$(review_codex_plugin_root "$toml" codex-plugin)" || {
    echo "the Codex plugin root could not be resolved — run /codex:setup" >&2
    return 1
  }
  run review_codex_preflight "$root"
  [ "$status" -eq 0 ] || {
    echo "the companion is not usable on this host:" >&2
    printf '%s\n' "$output" >&2
    return 1
  }
  version="$(_review_codex_version_for_root "$root")"
  [ -n "$version" ] || { echo "could not read the companion version" >&2; return 1; }

  # A deliberately tiny payload: this costs real credits, so ask for the least
  # that still proves the whole path.
  local art="$TEST_DIR/codex-plugin.payload"
  printf 'Reply with exactly one line: LIVE-SMOKE-OK\n' > "$art"

  # Stage 1 — `task --background`.
  local job
  job="$(live_launch "$root" "$toml" "$art")"
  [ -n "$job" ] || { echo "no job id came back from the launch" >&2; return 1; }

  # Stage 2 — `status`, polled to a terminal state.
  run _review_codex_poll "$root" "$job" 300
  [ "$status" -eq 0 ] || {
    echo "the job did not reach a terminal status inside 300s" >&2
    printf '%s\n' "$output" >&2
    return 1
  }
  local st
  st="$(review_codex_job_status "$root" "$job")"

  # Stage 3 — `result`.
  local out="$TEST_DIR/result.out"
  run review_codex_job_result "$root" "$job" "$out"
  [ "$status" -eq 0 ] || {
    echo "the result could not be collected:" >&2
    printf '%s\n' "$output" >&2
    return 1
  }
  grep -qF 'LIVE-SMOKE-OK' "$out" || {
    echo "the companion's result did not carry the requested marker:" >&2
    cat "$out" >&2
    return 1
  }

  # RECORD THESE IN changelog.md — the AC asks for the companion version, the
  # resolved job ids, and that the round went through background + status +
  # result. Printed rather than merely asserted, so a manual run can be
  # transcribed.
  echo "LIVE AC26: companion=$version root=$root job=$job status=$st" >&3
  echo "LIVE AC26: stages exercised = task --background, status, result" >&3
  echo "LIVE AC26 reminder: the SUBAGENT half is not provable from bats." >&3
  echo "  Run /speccraft:spec:review by hand with a subagent reviewer enabled" >&3
  echo "  and record both attested verdicts in changelog.md." >&3
}

@test "AC26a live cancellation smoke (SPECCRAFT_LIVE_CODEX_SMOKE)" {
  live_gate "AC26a"
  source "$LIB"

  local toml root
  toml="$(live_registry)"
  root="$(review_codex_plugin_root "$toml" codex-plugin)" || {
    echo "the Codex plugin root could not be resolved — run /codex:setup" >&2
    return 1
  }
  run review_codex_preflight "$root"
  [ "$status" -eq 0 ] || { echo "the companion is not usable on this host" >&2; return 1; }

  # A job that will still be running when we cancel it. This is the ONLY check
  # that the detached broker actually stops; no stub can prove it, which is
  # exactly why this test exists and cannot run in CI.
  local art="$TEST_DIR/codex-plugin.payload"
  printf 'Count slowly from 1 to 500, one number per line, with a comment on each.\n' > "$art"

  local job
  job="$(live_launch "$root" "$toml" "$art")"
  [ -n "$job" ] || { echo "no job id came back from the launch" >&2; return 1; }
  echo "LIVE AC26a: cancelling job=$job" >&3

  # The cancel must CONFIRM. An unconfirmed cancel is
  # `failed codex-cancel-unconfirmed <job-id>` and quarantines the round,
  # because the reviewer may still be running.
  run review_codex_job_cancel "$root" "$job"
  [ "$status" -eq 0 ] || {
    echo "the live cancel did not confirm:" >&2
    printf '%s\n' "$output" >&2
    echo "Check /codex:status before retrying; the turn may still be active." >&2
    return 1
  }

  local st
  st="$(review_codex_job_status "$root" "$job")"
  echo "LIVE AC26a: post-cancel status=$st" >&3
  echo "LIVE AC26a reminder: confirm in /codex:status that the turn is no" >&3
  echo "  longer active, and record the job id in changelog.md." >&3
}

# ---------------------------------------------------------------------------
# The arity guard. These two bodies CANNOT run here — no plugin, no credits —
# so nothing would catch a call whose signature drifted. This row reads the
# adapter's own `# <fn> <args…>` doc headers and checks every adapter call in
# this file against them.
#
# It earned its place immediately: the first draft of both bodies called
# `review_codex_preflight <toml> <agent>` (it takes a ROOT),
# `review_codex_job_id <toml> <agent>` (a LAUNCH FILE), and
# `review_codex_job_status`/`_cancel` with three arguments (they take two).
# All four would have failed on the one host that matters, months from now.
# ---------------------------------------------------------------------------

@test "every codex adapter call in this file matches the adapter's documented arity" {
  local adapter="$PLUGIN_DIR/commands/spec/review-codex.lib.sh"
  local fn doc want got line fails=""
  # One call per line, in the two live bodies' helpers and bodies.
  while IFS= read -r line; do
    fn="$(printf '%s\n' "$line" | grep -oE '\b_?review_codex_[a-z_]+\b' | head -1)"
    [ -n "$fn" ] || continue
    doc="$(grep -E "^# $fn " "$adapter" | head -1)"
    [ -n "$doc" ] || continue    # no doc header to check against
    # The documented arity: `# fn <a> <b> — …` → count the <…> before the dash.
    want="$(printf '%s\n' "$doc" | sed 's/ —.*//' | grep -oE '<[^>]+>' | grep -c . || true)"
    # The actual arity: arguments after the function name on this call line,
    # counting quoted words and bare tokens, stopping at a redirect or pipe.
    got="$(printf '%s\n' "$line" \
      | sed "s/.*$fn//; s/[|>].*//" \
      | grep -oE '"[^"]*"|[^ ]+' | grep -c . || true)"
    [ "$want" = "$got" ] || fails="$fails
  $fn: documented $want args, called with $got — $line"
  done <<EOF
$(grep -nE '\b_?review_codex_[a-z_]+ ' "$BATS_TEST_FILENAME" | grep -vE '^\s*[0-9]+:\s*#')
EOF
  [ -z "$fails" ] || {
    echo "adapter calls whose arity does not match the documented signature:$fails" >&2
    return 1
  }
}

# The parent-run variables a nested bats must NOT inherit. A child inherits
# BATS_TEST_NAMES and then reports `unknown test name` for its OWN tests, and
# its TAP output collides with the parent's stream ("Executed 6 instead of
# expected 8").
#
# An EXPLICIT LIST, not every `BATS_*` variable. Clearing them all also removed
# BATS_ROOT / BATS_LIBEXEC, which some bats installations need to locate their
# own internals — this devcontainer's resolves them from argv0 and did not
# care, CI's install does, and there the child died with
# `//bats-core/validator.bash: No such file or directory`. Found by the first
# CI run this branch ever had; a nested-process helper must clear the
# RUN-scoped state and keep the INSTALL-scoped state.
BATS_CHILD_CLEAR="BATS_TEST_NAMES BATS_TEST_FILTER BATS_TEST_NAME
BATS_TEST_NUMBER BATS_TEST_DESCRIPTION BATS_TEST_FILENAME BATS_TEST_TMPDIR
BATS_SUITE_TEST_NUMBER BATS_RUN_TMPDIR BATS_TEST_SOURCE BATS_OUT"

# bats_child <bats-args...> — run a nested bats with the parent's RUN-scoped
# BATS state cleared and its installation state intact.
bats_child() {
  local v clear=""
  for v in $BATS_CHILD_CLEAR; do
    clear="$clear -u $v"
  done
  # shellcheck disable=SC2086
  env $clear SPECCRAFT_LIVE_CODEX_SMOKE= bats "$@" 2>&1
}

@test "each gated test skips with a message naming itself and the knob" {
  # Run THIS file's two gated tests in a child bats with the knob unset, and
  # read the skip reasons. `-f AC26` matches both gated names and not this
  # one, so there is no recursion.
  local out
  out="$(bats_child -f 'AC26' "$BATS_TEST_FILENAME" || true)"
  [ -n "$out" ] || { echo "the child bats run produced nothing" >&2; return 1; }

  # Two skips, no passes: a gated test that PASSED without the knob would mean
  # it ran a live round in CI.
  [ "$(printf '%s\n' "$out" | grep -c '# skip')" -eq 2 ] || {
    echo "expected exactly 2 skipped gated tests; got:" >&2
    printf '%s\n' "$out" >&2
    return 1
  }
  local ac
  for ac in AC26 AC26a; do
    printf '%s\n' "$out" | grep -qF "$ac skipped" || {
      echo "the skip message does not name $ac:" >&2
      printf '%s\n' "$out" >&2
      return 1
    }
  done
  # Scoped to the SKIP REASON, not the whole child output: the gated tests'
  # TITLES also contain the knob name, so a whole-output grep passed even with
  # the knob removed from the reason. The reason is the part after `# skip`.
  local reasons
  reasons="$(printf '%s\n' "$out" | sed -n 's/.*# skip //p')"
  [ -n "$reasons" ] || { echo "no skip reasons found; row would be vacuous" >&2; return 1; }
  [ "$(printf '%s\n' "$reasons" | grep -cF "$SMOKE_KNOB")" -eq 2 ] || {
    echo "both skip reasons must name the knob; got:" >&2
    printf '%s\n' "$reasons" >&2
    return 1
  }
}

@test "the skip audit would notice a gated test that passed without the knob" {
  # Premise for the row above. A test body that skipped on a DIFFERENT
  # condition, or not at all, must change the count the audit reads.
  local probe="$TEST_DIR/probe.bats"
  # Built with printf, NOT a heredoc. bats finds tests by scanning for `@test`
  # at the start of a line and does not know a heredoc from code — a
  # column-0 `@test` inside one is counted as a real test of THIS file, which
  # made bats announce `1..8` for six tests and then warn "Executed 6 instead
  # of expected 8". Same class as every other line-based-scanner surprise in
  # this spec: keep fixture text out of the shapes the scanner looks for.
  {
    printf '%s\n' '@test "AC26 pretend gated" { :; }'
    printf '%s\n' '@test "AC26a pretend gated" { skip "for some other reason"; }'
  } > "$probe"
  local out
  out="$(bats_child -f 'AC26' "$probe" || true)"
  [ "$(printf '%s\n' "$out" | grep -c '# skip')" -eq 2 ] && {
    echo "the audit counts 2 skips for a file with one pass and one skip" >&2
    printf '%s\n' "$out" >&2
    return 1
  }
  return 0
}

@test "CI does not set the live-smoke knob" {
  # AC27: "CI runs without SPECCRAFT_LIVE_CODEX_SMOKE, so AC26/26a are skipped
  # and a green suite never attests them." If CI ever set it, a green run would
  # start meaning something different — and would burn credits per push.
  local hits
  hits="$(grep -rn "$SMOKE_KNOB" "$PLUGIN_DIR/.github" 2>/dev/null \
    | grep -vE '#|skip' || true)"
  [ -z "$hits" ] || {
    echo "CI references the live-smoke knob:" >&2
    printf '%s\n' "$hits" >&2
    return 1
  }
}

@test "the gated tests name the knob in their own titles" {
  # So `bats` output and the CI log show WHY they were skipped even to a reader
  # who only sees the test list. AC26 requires the skips to appear in the CI
  # log by name.
  local n
  n="$(grep -cE "^@test \"AC26a? live.*$SMOKE_KNOB" "$BATS_TEST_FILENAME")"
  [ "$n" -eq 2 ] || {
    echo "expected 2 gated test titles naming the knob, found $n" >&2
    grep -nE '^@test' "$BATS_TEST_FILENAME" >&2
    return 1
  }
}

@test "the nested-bats helper keeps bats' own installation variables" {
  # The defect CI caught: clearing every BATS_* variable also removed
  # BATS_ROOT / BATS_LIBEXEC, so on an installation that resolves its
  # internals from those (CI's does; this container's does not) the child died
  # with `//bats-core/validator.bash: No such file or directory`. The row that
  # used the helper then failed for a reason having nothing to do with what it
  # was testing.
  local v
  for v in BATS_ROOT BATS_LIBEXEC BATS_LIB_PATH BATS_TMPDIR; do
    printf '%s\n' "$BATS_CHILD_CLEAR" | grep -qxF "$v" && {
      echo "$v is install-scoped and must NOT be cleared for the child" >&2
      return 1
    }
  done
  # …and the run-scoped one that caused the original problem IS cleared.
  printf '%s\n' "$BATS_CHILD_CLEAR" | tr ' ' '\n' | grep -qxF 'BATS_TEST_NAMES' || {
    echo "BATS_TEST_NAMES is not cleared, so a child would filter on the parent's list" >&2
    return 1
  }
  # The helper must actually work: a trivial nested run succeeds.
  local probe="$TEST_DIR/trivial.bats"
  printf '%s\n' '@test "trivial" { :; }' > "$probe"
  local out
  out="$(bats_child "$probe" || true)"
  printf '%s\n' "$out" | grep -qE '^ok 1 trivial' || {
    echo "the nested helper could not run a trivial file:" >&2
    printf '%s\n' "$out" >&2
    return 1
  }
}
