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

# live_workspace_cwd — the cwd every stage of a live round must share.
#
# The companion keys its job store by GIT WORKSPACE ROOT, so this is not a
# cosmetic choice of working directory: it decides which store the job is
# written into, and therefore whether the status/result/cancel calls can see it
# at all. `find-root` is the same resolution the shipped dispatcher uses
# (`review_dispatch_agent` defaults its cwd to it), so the smoke launches where
# production launches. The plugin dir is the fallback for a host whose
# `speccraft-state` is not on PATH; it is this file's own repo, hence also a
# workspace root.
live_workspace_cwd() {
  local root
  root="$(speccraft-state find-root 2>/dev/null || true)"
  [ -n "$root" ] || root="$PLUGIN_DIR"
  printf '%s\n' "$root"
}

# live_launch <root> <toml> <payload> — launch a background job and echo its id.
#
# Drives the stages DIRECTLY rather than through `_review_codex_dispatch`,
# because that wrapper creates its launch file with `mktemp` and removes it, so
# a caller cannot get the job id afterwards — and the job id is exactly what
# ACs 26 and 26a require to be recorded. Uses the adapter's own launch idiom
# (`xargs -0 env`, never a bare `xargs -0`, which defaults to `echo` and
# launches nothing).
#
# The cwd is the WORKSPACE ROOT, never `$TEST_DIR`. The first live run of this
# file passed the per-test temp dir, which the companion resolved to itself —
# so the job went into a store keyed by a directory that is deleted in
# `teardown`, and every later stage queried the repo's store and found nothing.
live_launch() {
  local root="$1" toml="$2" art="$3"
  local argv_file="$TEST_DIR/argv" launch_file="$TEST_DIR/launch" cwd
  cwd="$(live_workspace_cwd)"
  review_codex_task_argv "$toml" codex-plugin "$root" "$art" "$cwd" > "$argv_file"
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

  # OBSERVATION ONE — the job is still live. Without this the row proves
  # nothing: `review_codex_job_cancel` returns 0 on ANY terminal status, so a
  # job that completed on its own a moment ago would be recorded as a confirmed
  # cancellation. That is not a flake to be retried past — it is the row
  # silently changing what it attests, so it is a hard failure with the
  # re-run instruction attached.
  local st_pre
  st_pre="$(review_codex_job_status "$root" "$job")"
  if _review_codex_job_terminal "$st_pre"; then
    echo "the job was already '$st_pre' BEFORE the cancel — nothing was cancelled" >&2
    echo "AC26a needs a job still queued or running at cancel time; re-run." >&2
    echo "If this repeats, make the prompt in this body longer-running." >&2
    return 1
  fi
  echo "LIVE AC26a: pre-cancel status=$st_pre" >&3

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

  # OBSERVATION TWO — `cancelled` specifically, not merely terminal. A job that
  # raced to `completed` between the check above and the cancel must not be
  # recorded as a cancellation either.
  local st_post
  st_post="$(review_codex_job_status "$root" "$job")"
  [ "$st_post" = "cancelled" ] || {
    echo "post-cancel status is '$st_post', not 'cancelled'" >&2
    echo "The cancel helper accepts any terminal status, so this is the only" >&2
    echo "check that distinguishes a cancellation from a coincidence." >&2
    return 1
  }
  echo "LIVE AC26a: post-cancel status=$st_post (was $st_pre)" >&3
  echo "LIVE AC26a reminder: confirm in /codex:status that the turn is no" >&3
  echo "  longer active, and record the job id in changelog.md." >&3
}

# ---------------------------------------------------------------------------
# Spec 0055 ACs 1 / 2 — the two defects the first live run of this file found.
#
# Defect 1: `live_launch` passed `$TEST_DIR` as `--cwd`. The Codex companion
# keys its job store by GIT WORKSPACE ROOT — every path inside a repo resolves
# to that repo's root, and a non-repo directory resolves to ITSELF. So the
# launch wrote its job into a per-tempdir store while the three post-launch
# helpers, which pass no `--cwd` at all, queried the repo's store and saw
# nothing. `No job found` is indistinguishable from "not terminal yet" to a
# polling adapter, so the round looked like a 300 s timeout in `codex-plugin`
# mode rather than a test that launched into the wrong store.
#
# Defect 2: the AC26a body asserted only that `review_codex_job_cancel`
# returned 0 — but that helper returns 0 on ANY terminal status
# (`completed | failed | cancelled`). A job that finished on its own a moment
# before the cancel would have been recorded as a confirmed cancellation, which
# is the one thing this file exists to prove and the one thing no stub can.
#
# The first two rows are UNGATED on purpose: they are the only part of AC1 that
# a host with no Codex plugin and no credits can run, and the only thing
# keeping the fix pinned between live runs.
# ---------------------------------------------------------------------------

# live_stub_node — put a recording `node` on PATH and echo its directory.
#
# Stands in for the companion so the launch idiom (`xargs -0 env`) really
# executes. It records the argv the PROCESS received, which is a stronger thing
# to assert on than the argv file the helper wrote: a launch that mangled word
# boundaries would still have a correct-looking argv file.
live_stub_node() {
  local dir="$TEST_DIR/stub"
  mkdir -p "$dir"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'printf "%%s\\n" "$@" > "%s"\n' "$TEST_DIR/node-argv"
    printf 'printf "{\\"jobId\\":\\"job-stub-live-smoke\\"}\\n"\n'
  } > "$dir/node"
  chmod 0755 "$dir/node"
  printf '%s\n' "$dir"
}

# live_mutant_tree <file> <sed-expr> — a minimal plugin tree under $TEST_DIR
# whose tests/hooks/ holds a MUTATED copy of <file>; echoes that copy's path,
# and returns 1 when the mutation changed nothing.
#
# Symlinks commands/ and bin/ rather than copying: `setup` resolves PLUGIN_DIR
# from the test file's own path, so a mutant run from the temp dir directly
# would resolve a plugin root with no lib to source and fail for a reason
# having nothing to do with what is being tested.
live_mutant_tree() {
  local src="$1" expr="$2" tree="$TEST_DIR/mutant-plugin" out
  mkdir -p "$tree/tests/hooks"
  ln -sfn "$PLUGIN_DIR/commands" "$tree/commands"
  ln -sfn "$PLUGIN_DIR/bin" "$tree/bin"
  out="$tree/tests/hooks/$(basename "$src")"
  sed "$expr" "$src" > "$out"
  cmp -s "$src" "$out" && return 1
  printf '%s\n' "$out"
}

@test "live_launch derives its cwd from the workspace root, not a temp dir" {
  source "$LIB"

  local toml want got job art
  toml="$(live_registry)"
  art="$TEST_DIR/codex-plugin.payload"
  printf 'irrelevant to a stubbed launch\n' > "$art"
  PATH="$(live_stub_node):$PATH"

  want="$(live_workspace_cwd)"
  job="$(live_launch "$TEST_DIR/fake-plugin-root" "$toml" "$art")"
  [ "$job" = "job-stub-live-smoke" ] || {
    echo "the stubbed launch did not return its job id; got '$job'" >&2
    return 1
  }

  got="$(awk '$0 == "--cwd" { getline; print; exit }' "$TEST_DIR/node-argv")"
  [ -n "$got" ] || {
    echo "no --cwd in the launched argv:" >&2
    cat "$TEST_DIR/node-argv" >&2
    return 1
  }
  [ "$got" = "$want" ] || {
    echo "launch cwd is '$got'; the workspace root is '$want'" >&2
    return 1
  }
  # The property that actually matters, asserted directly rather than inferred
  # from the string: the cwd must BE a git workspace root, because that is what
  # the companion hashes to pick a job store.
  [ -d "$got/.git" ] || {
    echo "launch cwd '$got' is not a git workspace root" >&2
    return 1
  }
  [ "$got" != "$TEST_DIR" ] || {
    echo "launch cwd is the per-test temp dir — defect 1 is back" >&2
    return 1
  }
}

@test "the launch-cwd row rejects a /tmp cwd, so it is not vacuous" {
  # Mutate, don't assert: revert `live_launch`'s cwd to the per-test temp dir —
  # defect 1 verbatim — and run the row above against it in a child bats. It
  # must report `not ok`. An assertion that has never been seen to fail is
  # indistinguishable from a typo in its own pattern.
  local mutant out
  mutant="$(live_mutant_tree "$BATS_TEST_FILENAME" \
    's|^  cwd="$(live_workspace_cwd)"$|  cwd="$TEST_DIR"|')" || {
    echo "the mutation changed nothing — this row would be vacuous" >&2
    return 1
  }
  # `-f` matches the launch-cwd row only; this row's own name does not match,
  # so there is no recursion.
  out="$(bats_child -f 'live_launch derives its cwd' "$mutant" || true)"
  printf '%s\n' "$out" | grep -qE '^not ok' || {
    echo "the pre-fix temp-dir cwd PASSED the launch-cwd row:" >&2
    printf '%s\n' "$out" >&2
    return 1
  }
}

@test "the AC26a body requires a non-terminal status before the cancel and cancelled after" {
  # The AC26a body is gated and cannot run here, so this row reads it instead.
  # AC2: a confirmed cancellation needs TWO observations in a fixed order — a
  # non-terminal status BEFORE the cancel, and `cancelled` SPECIFICALLY after
  # it. Asserting the order is the point; both checks present but reversed
  # would prove nothing.
  local body ln_status ln_pre ln_cancel ln_post
  body="$(awk '/^@test "AC26a live cancellation/,/^}$/' "$BATS_TEST_FILENAME")"
  [ -n "$body" ] || { echo "could not locate the AC26a body" >&2; return 1; }

  # Patterns deliberately stop before the first argument: a pattern carrying a
  # space after an adapter function name would itself be read as a call by the
  # arity guard below.
  ln_status="$(printf '%s\n' "$body" | grep -nF 'st_pre="$(review_codex_job_status' | head -1 | cut -d: -f1)"
  ln_pre="$(printf '%s\n' "$body" | grep -nF 'if _review_codex_job_terminal' | head -1 | cut -d: -f1)"
  ln_cancel="$(printf '%s\n' "$body" | grep -nF 'run review_codex_job_cancel' | head -1 | cut -d: -f1)"
  ln_post="$(printf '%s\n' "$body" | grep -nF '[ "$st_post" = "cancelled" ]' | head -1 | cut -d: -f1)"

  [ -n "$ln_status" ] || { echo "AC26a never reads a pre-cancel status" >&2; return 1; }
  [ -n "$ln_pre" ] || { echo "AC26a never refuses a pre-cancel TERMINAL status" >&2; return 1; }
  [ -n "$ln_cancel" ] || { echo "AC26a never calls the cancel helper" >&2; return 1; }
  [ -n "$ln_post" ] || {
    echo "AC26a does not assert the post-cancel status is cancelled specifically" >&2
    echo "(review_codex_job_cancel() returns 0 on completed and failed too)" >&2
    return 1
  }

  [ "$ln_status" -lt "$ln_pre" ] && [ "$ln_pre" -lt "$ln_cancel" ] \
    && [ "$ln_cancel" -lt "$ln_post" ] || {
    echo "AC26a's cancellation checks are out of order:" >&2
    echo "  status=$ln_status terminal-refusal=$ln_pre cancel=$ln_cancel post=$ln_post" >&2
    return 1
  }
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
    # counting quoted words and bare tokens, stopping at the first shell
    # control operator.
    #
    # `;` and `&` are in that set, not just `|` and `>`: spec 0055 added
    # `if _review_codex_job_terminal "$st_pre"; then`, a one-argument call the
    # earlier pattern read as two by counting `then`. A guard that red-flags a
    # correct call is worse than no guard — the next engineer learns to reword
    # around it rather than trust it.
    got="$(printf '%s\n' "$line" \
      | sed "s/.*$fn//; s/[|>;&].*//" \
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
