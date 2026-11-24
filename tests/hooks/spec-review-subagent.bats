#!/usr/bin/env bats
# Spec 0054 AC18b — preflight a custom `subagent_type` BEFORE launching it.
#
# A registry entry may name any agent as its reviewer. The round reads that
# reviewer's verdict from `<round-dir>/<agent>.out`, so an agent without the
# `Write` tool cannot produce one: it would be launched, think, and return
# nothing, and the round would record an empty or missing artifact several
# minutes later. Checking the agent's own frontmatter first turns that into an
# immediate, named refusal.
#
# `Edit` is a different case. It is not required for the round to work, but a
# reviewer that can Edit can rewrite the very document it is judging — so it
# warns and still dispatches, because the operator chose that agent on purpose.
#
# Everything here runs against FIXTURE agent definitions in a temp dir, never
# against the repo's own agents/: a test that asserted "the shipped reviewer
# passes preflight" would red for an unrelated edit to that file, and would
# tell us nothing about the refusal arms.

setup() {
  PLUGIN_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  LIB="$PLUGIN_DIR/commands/spec/review.lib.sh"
  RUNBOOK="$PLUGIN_DIR/skills/review-round/SKILL.md"
  export PATH="$PLUGIN_DIR/bin:$PATH"
  TEST_DIR="$(mktemp -d)"
  AGENTS_DIR="$TEST_DIR/agents"
  mkdir -p "$AGENTS_DIR"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# make_agent <name> <tools-line-or-empty> — a minimal agent definition. An
# empty second argument omits the `tools:` key entirely, which is how a host
# declares an UNCONFINED agent.
make_agent() {
  local name="$1" tools="${2:-}"
  {
    printf -- '---\n'
    printf 'name: %s\n' "$name"
    printf 'description: "fixture agent"\n'
    [ -z "$tools" ] || printf 'tools: %s\n' "$tools"
    printf 'model: inherit\n'
    printf -- '---\n\n'
    printf 'Fixture body.\n'
  } > "$AGENTS_DIR/$name.md"
}

assert_named_failure() {
  local pattern="$1"
  printf '%s\n' "$output" | grep -qF -- "$pattern" || {
    echo "expected output to name '$pattern'; got: $output" >&2
    return 1
  }
}

# ---------------------------------------------------------------------------
# AC18b — the three arms
# ---------------------------------------------------------------------------

@test "a subagent_type whose agent declares Write passes preflight" {
  source "$LIB"
  make_agent good '[Read, Grep, Glob, Write]'
  run review_subagent_preflight "$AGENTS_DIR" good
  [ "$status" -eq 0 ]
  [ "$output" = "ok" ]
}

@test "a custom subagent_type lacking Write is failed subagent-launch missing-write-tool" {
  source "$LIB"
  make_agent nowerite '[Read, Grep, Glob]'
  run review_subagent_preflight "$AGENTS_DIR" nowerite
  # A refusal is DATA, like review_budget_check's: exit 0, token on stdout, so
  # the round records it and the other reviewers still run.
  [ "$status" -eq 0 ]
  [ "$output" = "failed subagent-launch missing-write-tool" ]
}

@test "the recorded refusal is a whole outcome line, not a bare reason" {
  source "$LIB"
  # The outcomes file is read as `<agent> <outcome> <rest>`. A bare
  # `missing-write-tool` in the outcome column would hit _review_outcome_kind's
  # unknown-token arm and abort the round with exit 2 instead of recording it.
  make_agent nowerite '[Read]'
  run review_subagent_preflight "$AGENTS_DIR" nowerite
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qE '^failed ' || {
    echo "preflight's refusal does not start with the 'failed' outcome: $output" >&2
    return 1
  }
}

@test "a failed preflight is a non-verdict the round can finalize around" {
  source "$LIB"
  make_agent nowerite '[Read]'
  run review_subagent_preflight "$AGENTS_DIR" nowerite
  # Feed the real token through the real classifier: a refusal token the round
  # cannot classify is worse than no preflight at all.
  tok="$(printf '%s\n' "$output" | awk '{print $1}')"
  run _review_outcome_kind "$tok"
  [ "$status" -eq 0 ]
  [ "$output" = "non-verdict" ]
}

@test "an unknown subagent_type is failed subagent-launch with a named reason" {
  source "$LIB"
  run review_subagent_preflight "$AGENTS_DIR" nosuchagent
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qE '^failed subagent-launch ' || {
    echo "expected a named subagent-launch failure; got: $output" >&2
    return 1
  }
  assert_named_failure "unknown-subagent-type"
}

@test "the unknown-type refusal names the type that was not found" {
  source "$LIB"
  # Without the name, an operator with four registry entries cannot tell which
  # one points at a missing agent.
  run review_subagent_preflight "$AGENTS_DIR" typo-reviewer
  assert_named_failure "typo-reviewer"
}

@test "a custom subagent_type declaring Edit warns and still dispatches" {
  source "$LIB"
  make_agent editor '[Read, Edit, Write]'
  run review_subagent_preflight "$AGENTS_DIR" editor
  [ "$status" -eq 0 ]
  # It DISPATCHES: stdout is still the ok token, so the runbook proceeds.
  printf '%s\n' "$output" | grep -qxF "ok" || {
    echo "the Edit arm must still dispatch; stdout was: $output" >&2
    return 1
  }
}

@test "the Edit warning goes to stderr, never into the outcome" {
  source "$LIB"
  make_agent editor '[Read, Edit, Write]'
  # stdout ALONE must be the bare token: the runbook captures it with $(…) and
  # a warning mixed in would be appended to the outcomes file verbatim.
  out="$(review_subagent_preflight "$AGENTS_DIR" editor 2>/dev/null)"
  [ "$out" = "ok" ] || {
    echo "stdout carried more than the token: '$out'" >&2
    return 1
  }
  err="$(review_subagent_preflight "$AGENTS_DIR" editor 2>&1 >/dev/null)"
  printf '%s\n' "$err" | grep -qF "Edit" || {
    echo "no Edit warning on stderr; got: '$err'" >&2
    return 1
  }
  printf '%s\n' "$err" | grep -qF "editor" || {
    echo "the warning does not name the agent: '$err'" >&2
    return 1
  }
}

@test "a Write-less agent that also declares Edit refuses rather than warns" {
  source "$LIB"
  # Order matters: the refusal is fatal to the round, the warning is not. A
  # warn-first implementation would emit `ok` and the reviewer would be
  # launched anyway.
  make_agent editnowrite '[Read, Edit]'
  run review_subagent_preflight "$AGENTS_DIR" editnowrite
  [ "$status" -eq 0 ]
  [ "$output" = "failed subagent-launch missing-write-tool" ]
}

@test "an agent with no tools key at all dispatches with a warning" {
  source "$LIB"
  # Omitting `tools:` grants the agent EVERY tool, so Write is present and the
  # round works — but so are Edit and bare Bash. That is the operator's choice
  # to make, and ours to say out loud.
  make_agent unconfined ''
  run review_subagent_preflight "$AGENTS_DIR" unconfined
  [ "$status" -eq 0 ]
  out="$(review_subagent_preflight "$AGENTS_DIR" unconfined 2>/dev/null)"
  [ "$out" = "ok" ]
  err="$(review_subagent_preflight "$AGENTS_DIR" unconfined 2>&1 >/dev/null)"
  [ -n "$err" ] || {
    echo "an unconfined agent dispatched silently" >&2
    return 1
  }
}

@test "the plugin-qualified subagent_type resolves to the bare file name" {
  source "$LIB"
  # The registry default IS `speccraft:reviewer`, and the file is
  # agents/reviewer.md. A preflight that does not strip the prefix would refuse
  # the one agent this spec ships.
  # A minimal grant list on purpose. The shipped reviewer's EXACT list is
  # pinned in review-subagent-agent.bats; repeating it here would couple this
  # file to that one and add a second mention-only GNU-tool exemption for a
  # string this test does not need.
  make_agent reviewer '[Read, Grep, Glob, Write]'
  run review_subagent_preflight "$AGENTS_DIR" speccraft:reviewer
  [ "$status" -eq 0 ]
  [ "$output" = "ok" ]
}

@test "the shipped reviewer passes preflight under its dispatch default" {
  source "$LIB"
  # The one end-to-end row: the REAL agents dir, under the REAL default, so the
  # fixtures above cannot all agree on a contract the shipped pair fails.
  local default
  default="$(grep -oE 'a\.SubagentType = "[^"]+"' "$PLUGIN_DIR/tools/internal/delegate/toml.go" \
    | head -1 | sed 's/.*"\(.*\)"/\1/')"
  [ -n "$default" ] || { echo "could not read the Go default" >&2; return 1; }
  run review_subagent_preflight "$PLUGIN_DIR/agents" "$default"
  [ "$status" -eq 0 ]
  [ "$output" = "ok" ]
}

@test "a subagent_type containing a path separator is refused, not resolved" {
  source "$LIB"
  # `../../etc/passwd` must not be read as an agent definition, and a type that
  # escapes the agents dir is a registry error either way.
  mkdir -p "$TEST_DIR/elsewhere"
  make_agent decoy '[Read, Write]'
  mv "$AGENTS_DIR/decoy.md" "$TEST_DIR/elsewhere/decoy.md"
  run review_subagent_preflight "$AGENTS_DIR" "../elsewhere/decoy"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qE '^failed subagent-launch ' || {
    echo "a traversing subagent_type was not refused; got: $output" >&2
    return 1
  }
}

@test "an empty subagent_type is a named error, not a resolved path" {
  source "$LIB"
  run review_subagent_preflight "$AGENTS_DIR" ""
  [ "$status" -ne 0 ]
  # Anchored on the REASON, not the function name: bash's own "command not
  # found" message contains the function name too, so a name-only assertion
  # passes before the function exists.
  assert_named_failure "subagent type required"
}

@test "a missing agents dir is a named error, not a silent unknown-type" {
  source "$LIB"
  # These two must be distinguishable: a typo'd registry entry is the
  # operator's to fix, a missing plugin dir is ours.
  run review_subagent_preflight "$TEST_DIR/nodir" reviewer
  [ "$status" -ne 0 ]
  assert_named_failure "agents dir"
  assert_named_failure "$TEST_DIR/nodir"
}

@test "the named-error rows cannot be satisfied by a command-not-found message" {
  # Premise for the two rows above. bash prints
  # "…: review_subagent_preflight: command not found" with a non-zero status,
  # which satisfies both `[ status -ne 0 ]` and any assertion that merely looks
  # for the function's name.
  run bash -c 'review_subagent_preflight /nowhere x'
  [ "$status" -ne 0 ]
  printf '%s\n' "$output" | grep -qF 'review_subagent_preflight' || {
    echo "premise does not hold: no function name in the shell's error" >&2
    return 1
  }
  printf '%s\n' "$output" | grep -qF 'subagent type required' && {
    echo "a command-not-found message satisfied the reason assertion" >&2
    return 1
  }
  printf '%s\n' "$output" | grep -qF 'agents dir' && {
    echo "a command-not-found message satisfied the agents-dir assertion" >&2
    return 1
  }
  return 0
}

@test "preflight reads the frontmatter only, not a fenced example in the body" {
  source "$LIB"
  # An agent whose BODY documents a tools list containing Write, while its
  # frontmatter omits it, must still be refused.
  cat > "$AGENTS_DIR/decoyed.md" <<'AGENT'
---
name: decoyed
tools: [Read, Grep]
model: inherit
---

For reference, a well-formed reviewer declares:

```yaml
tools: [Read, Grep, Glob, Write]
```
AGENT
  run review_subagent_preflight "$AGENTS_DIR" decoyed
  [ "$status" -eq 0 ]
  [ "$output" = "failed subagent-launch missing-write-tool" ]
}

@test "a body fence cannot supply a tools list the frontmatter omits" {
  source "$LIB"
  # The row above cannot detect a whole-file read: its frontmatter `tools:`
  # comes FIRST, so the reader exits on the real value either way. This is the
  # case that distinguishes them — no `tools:` in the frontmatter at all, and a
  # fenced one in the body. The correct answer is the UNCONFINED arm (ok plus a
  # warning); a whole-file read would instead refuse on the body's Write-less
  # example and never launch an agent that was entitled to run.
  cat > "$AGENTS_DIR/bodyonly.md" <<'AGENT'
---
name: bodyonly
model: inherit
---

A reviewer's grants are declared like this:

```yaml
tools: [Read, Grep]
```
AGENT
  out="$(review_subagent_preflight "$AGENTS_DIR" bodyonly 2>/dev/null)"
  [ "$out" = "ok" ] || {
    echo "a body fence was read as the agent's grants: '$out'" >&2
    return 1
  }
  err="$(review_subagent_preflight "$AGENTS_DIR" bodyonly 2>&1 >/dev/null)"
  printf '%s\n' "$err" | grep -qF "no tools" || {
    echo "the unconfined warning is absent, so the body fence was consulted: '$err'" >&2
    return 1
  }
}

@test "preflight does not mistake WriteFile or a Write mention in prose for the tool" {
  source "$LIB"
  # Membership, not substring: `[Read, WriteFile]` does not grant Write.
  make_agent writefile '[Read, WriteFile]'
  run review_subagent_preflight "$AGENTS_DIR" writefile
  [ "$output" = "failed subagent-launch missing-write-tool" ]
}

@test "preflight launches nothing itself" {
  source "$LIB"
  # It is a pure frontmatter read. If it ever shells out, a stub of that name
  # on PATH would be executed and leave a marker.
  mkdir -p "$TEST_DIR/trap"
  for cmd in claude codex opencode acpx; do
    printf '#!/usr/bin/env bash\nprintf %%s "$0" >> "%s/launched"\n' "$TEST_DIR" \
      > "$TEST_DIR/trap/$cmd"
    chmod +x "$TEST_DIR/trap/$cmd"
  done
  PATH="$TEST_DIR/trap:$PATH"
  make_agent good '[Read, Write]'
  run review_subagent_preflight "$AGENTS_DIR" good
  [ "$status" -eq 0 ]
  [ ! -e "$TEST_DIR/launched" ] || {
    echo "preflight launched: $(cat "$TEST_DIR/launched")" >&2
    return 1
  }
}

@test "the launch-trap stub really does record an execution" {
  # Premise for the row above: without this, that row passes even if the stubs
  # are never executable or PATH never takes effect.
  mkdir -p "$TEST_DIR/trap"
  printf '#!/usr/bin/env bash\nprintf %%s "$0" >> "%s/launched"\n' "$TEST_DIR" \
    > "$TEST_DIR/trap/claude"
  chmod +x "$TEST_DIR/trap/claude"
  PATH="$TEST_DIR/trap:$PATH" claude
  [ -e "$TEST_DIR/launched" ] || {
    echo "the trap stub did not record its own execution" >&2
    return 1
  }
}

# ---------------------------------------------------------------------------
# AC18b — the refusal happens BEFORE the Agent launch
# ---------------------------------------------------------------------------

@test "the runbook preflights before it instructs the Agent launch" {
  # The ordering is the whole point: a preflight after the launch is a report,
  # not a gate. The runbook is executed top-to-bottom by a model, so line
  # order IS the control flow.
  local pre launch
  pre="$(grep -nF 'review_subagent_preflight' "$RUNBOOK" | head -1 | cut -d: -f1)"
  launch="$(grep -nE 'Use the \*\*Agent\*\* tool|subagent_type.{0,4}:' "$RUNBOOK" | head -1 | cut -d: -f1)"
  [ -n "$pre" ] || {
    echo "the runbook never calls review_subagent_preflight:" >&2
    grep -nF 'subagent' "$RUNBOOK" >&2
    return 1
  }
  [ -n "$launch" ] || {
    echo "could not locate the Agent launch instruction; row would be vacuous" >&2
    return 1
  }
  [ "$pre" -lt "$launch" ] || {
    echo "preflight is at line $pre, after the launch instruction at $launch" >&2
    return 1
  }
}

@test "the runbook says a failed preflight means no Agent is launched" {
  grep -qiE 'before (any|the) (Agent )?launch|do not launch|never launch' "$RUNBOOK" || {
    echo "the runbook does not state that a failed preflight skips the launch:" >&2
    grep -niF 'preflight' "$RUNBOOK" >&2
    return 1
  }
}

@test "the runbook records the preflight refusal as the agent's outcome" {
  # Otherwise a refused reviewer has NO recorded outcome, which
  # review_responses_complete cannot distinguish from one never dispatched.
  grep -qE 'subagent-launch|PREFLIGHT.*OUTCOMES|preflight[^.]*\$OUTCOMES' "$RUNBOOK" || {
    echo "the runbook does not record the preflight refusal:" >&2
    grep -niF 'preflight' "$RUNBOOK" >&2
    return 1
  }
}

# ---------------------------------------------------------------------------
# AC18b — a preflight failure is not a durable write
# ---------------------------------------------------------------------------

@test "every preflight failure leaves a prior durable review.md byte-unchanged" {
  source "$LIB"
  local dir
  dir="$TEST_DIR/specs/0001-x"
  mkdir -p "$dir"
  printf '# Spec\n\nSPEC\n' > "$dir/spec.md"
  printf '# Spec\n\nSNAP\n' > "$dir/review-snapshot.md"
  printf '# Review\n\nPRIOR-REVIEW\n' > "$dir/review.md"
  cp "$dir/review.md" "$TEST_DIR/review.before"

  make_agent nowerite '[Read]'
  local arm
  for arm in nowerite nosuchagent "../elsewhere/decoy"; do
    run review_subagent_preflight "$AGENTS_DIR" "$arm"
    [ "$status" -eq 0 ]
    # Record it the way the round would, then finalize: a round whose only
    # reviewer was refused is INERT, so review.md must not move.
    printf 'subagent-reviewer %s\n' "$output" > "$TEST_DIR/outcomes"
    run review_finalize_round "$dir" 1 "$TEST_DIR/outcomes"
    [ "$status" -eq 0 ]
    printf '%s\n' "$output" | grep -qxF "responses_complete: false"
    cmp -s "$TEST_DIR/review.before" "$dir/review.md" || {
      echo "review.md moved after a '$arm' preflight refusal" >&2
      return 1
    }
  done
}

# ---------------------------------------------------------------------------
# ACs 20a / 20b / 17a — the subagent timeout, cancellation and collection
# protocol.
#
# A subagent is not a process: the shell cannot see it, signal it, or wait on
# it. Only the orchestrating session can, through the Agent and TaskStop tools,
# across many separate tool calls between which NO shell state survives. So the
# agent id and the deadline have to live in the round dir, and the arithmetic
# that decides "is this reviewer late?" has to be a helper rather than a sum a
# model does in prose.
#
# The deadline is recorded as an ABSOLUTE epoch second. A relative timeout
# re-read on a later tool call would restart the clock every time it was
# consulted, so a reviewer could never be late.
# ---------------------------------------------------------------------------

make_round_dir() {
  ROUND_DIR="$TEST_DIR/round"
  mkdir -p "$ROUND_DIR"
}

@test "review_subagent_record stores the agent id and an absolute deadline" {
  source "$LIB"
  make_round_dir
  run review_subagent_record "$ROUND_DIR" codex-sub agent_abc123 600
  [ "$status" -eq 0 ]
  local rec="$ROUND_DIR/codex-sub.subagent"
  [ -f "$rec" ] || { echo "no record written; dir holds: $(ls -A "$ROUND_DIR")" >&2; return 1; }
  grep -qF 'agent_abc123' "$rec"
  # An ABSOLUTE epoch, not the 600: a relative timeout re-read on a later tool
  # call restarts the clock, so nothing is ever late.
  local dl now
  dl="$(awk -F= '/^deadline=/ {print $2}' "$rec")"
  now="$(date +%s)"
  [ -n "$dl" ] || { echo "no deadline recorded: $(cat "$rec")" >&2; return 1; }
  [ "$dl" -gt "$now" ] || { echo "deadline $dl is not in the future (now $now)" >&2; return 1; }
  [ "$dl" -le "$((now + 601))" ] || { echo "deadline $dl is not now+600 (now $now)" >&2; return 1; }
}

@test "the recorded deadline is per agent, not per round" {
  source "$LIB"
  make_round_dir
  review_subagent_record "$ROUND_DIR" a agent_a 600
  review_subagent_record "$ROUND_DIR" b agent_b 900
  # Two reviewers launched moments apart must not share one deadline, or
  # stopping the slow one stops the round's accounting for the fast one.
  grep -qF 'agent_a' "$ROUND_DIR/a.subagent"
  grep -qF 'agent_b' "$ROUND_DIR/b.subagent"
  run review_subagent_agent_id "$ROUND_DIR" b
  [ "$output" = "agent_b" ]
}

@test "review_subagent_deadline_expired is false before and true after" {
  source "$LIB"
  make_round_dir
  review_subagent_record "$ROUND_DIR" slow agent_s 600
  run review_subagent_deadline_expired "$ROUND_DIR" slow
  [ "$status" -eq 1 ]
  # A NEGATIVE timeout records a deadline already in the past — the clean way
  # to test lateness without sleeping or injecting a clock.
  review_subagent_record "$ROUND_DIR" late agent_l -5
  run review_subagent_deadline_expired "$ROUND_DIR" late
  [ "$status" -eq 0 ]
}

@test "deadline_expired on an unrecorded agent is a named error, not false" {
  source "$LIB"
  make_round_dir
  # "No record" must not read as "not expired": that would let a reviewer the
  # round never recorded run forever, and the cleanup gate would wait on it.
  run review_subagent_deadline_expired "$ROUND_DIR" neverlaunched
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | grep -qF "neverlaunched"
}

@test "review_subagent_collect accepts an on-time, non-empty artifact" {
  source "$LIB"
  make_round_dir
  review_subagent_record "$ROUND_DIR" good agent_g 600
  printf 'verdict: approve\n' > "$ROUND_DIR/good.out"
  run review_subagent_collect "$ROUND_DIR" good
  [ "$status" -eq 0 ]
  [ "$output" = "ok" ]
}

@test "a missing artifact after the agent returns is failed subagent-no-output" {
  source "$LIB"
  make_round_dir
  review_subagent_record "$ROUND_DIR" silent agent_s 600
  run review_subagent_collect "$ROUND_DIR" silent
  [ "$status" -eq 0 ]
  [ "$output" = "failed subagent-no-output" ]
}

@test "an empty artifact is failed subagent-no-output, never an empty verdict" {
  source "$LIB"
  make_round_dir
  review_subagent_record "$ROUND_DIR" empty agent_e 600
  : > "$ROUND_DIR/empty.out"
  run review_subagent_collect "$ROUND_DIR" empty
  [ "$status" -eq 0 ]
  [ "$output" = "failed subagent-no-output" ]
  # A whitespace-only artifact is the same thing: a reviewer that wrote a
  # newline has not returned a verdict.
  printf '\n  \n' > "$ROUND_DIR/empty.out"
  run review_subagent_collect "$ROUND_DIR" empty
  [ "$output" = "failed subagent-no-output" ]
}

@test "a reviewer completing after its deadline is recorded timeout late-completion" {
  source "$LIB"
  make_round_dir
  review_subagent_record "$ROUND_DIR" tardy agent_t -5
  printf 'verdict: approve\n' > "$ROUND_DIR/tardy.out"
  run review_subagent_collect "$ROUND_DIR" tardy
  [ "$status" -eq 0 ]
  [ "$output" = "timeout late-completion" ]
}

@test "the late outcome classifies as a non-verdict" {
  source "$LIB"
  # This is what keeps a late approve out of quorum: the round reads the
  # outcome column, and `timeout` is in REVIEW_NON_VERDICTS.
  run _review_outcome_kind timeout
  [ "$output" = "non-verdict" ]
}

@test "a late approve is not counted toward quorum" {
  source "$LIB"
  make_round_dir
  review_subagent_record "$ROUND_DIR" tardy agent_t -5
  printf 'verdict: approve\n' > "$ROUND_DIR/tardy.out"
  out="$(review_subagent_collect "$ROUND_DIR" tardy)"
  printf 'tardy %s\n' "$out" > "$TEST_DIR/outcomes"
  run review_approval_quorum_met 1 "$TEST_DIR/outcomes"
  [ "$status" -eq 1 ]
  run review_responses_complete "$TEST_DIR/outcomes"
  [ "$status" -eq 1 ]
}

@test "an already-finalized review.md is byte-unchanged after a late completion" {
  source "$LIB"
  make_round_dir
  local dir="$TEST_DIR/specs/0001-x"
  mkdir -p "$dir"
  printf '# Spec\n\nSPEC\n' > "$dir/spec.md"
  printf '# Spec\n\nSNAP\n' > "$dir/review-snapshot.md"
  printf '# Review\n\nFINALIZED-REVIEW\n' > "$dir/review.md"
  # The round completed on its other reviewer and finalized.
  printf 'ontime approve\n' > "$TEST_DIR/outcomes"
  run review_finalize_round "$dir" 1 "$TEST_DIR/outcomes"
  [ "$status" -eq 0 ]
  cp "$dir/review.md" "$TEST_DIR/review.after-finalize"

  # NOW the late reviewer lands. Collecting it must not move review.md, and
  # re-finalizing with the late record must not either — the round is over.
  review_subagent_record "$ROUND_DIR" tardy agent_t -5
  printf 'verdict: approve\n' > "$ROUND_DIR/tardy.out"
  out="$(review_subagent_collect "$ROUND_DIR" tardy)"
  printf 'tardy %s\n' "$out" >> "$TEST_DIR/outcomes"
  run review_finalize_round "$dir" 1 "$TEST_DIR/outcomes"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qxF "responses_complete: false"
  cmp -s "$TEST_DIR/review.after-finalize" "$dir/review.md" || {
    echo "review.md moved after a late completion" >&2
    return 1
  }
}

@test "review_subagent_collect reads the artifact from disk, not an argument" {
  source "$LIB"
  make_round_dir
  review_subagent_record "$ROUND_DIR" ondisk agent_o 600
  # AC17a. Pass a plausible verdict as a THIRD argument and leave the artifact
  # absent: a collector that accepted pasted content would answer ok.
  run review_subagent_collect "$ROUND_DIR" ondisk 'verdict: approve'
  [ "$output" = "failed subagent-no-output" ] || {
    echo "collect honoured pasted content over the artifact: $output" >&2
    return 1
  }
}

@test "review_subagent_stop_failed names the agent id, not the agent name" {
  source "$LIB"
  make_round_dir
  review_subagent_record "$ROUND_DIR" stuck agent_xyz789 600
  run review_subagent_stop_failed "$ROUND_DIR" stuck
  [ "$status" -eq 0 ]
  [ "$output" = "failed subagent-stop-failed agent_xyz789" ] || {
    echo "unexpected stop-failed record: $output" >&2
    return 1
  }
}

@test "a stop-failed quarantines the round dir rather than cleaning it up" {
  source "$LIB"
  make_round_dir
  review_subagent_record "$ROUND_DIR" stuck agent_xyz789 600
  run review_subagent_stop_failed "$ROUND_DIR" stuck
  [ "$status" -eq 0 ]
  [ -f "$ROUND_DIR/quarantine" ] || {
    echo "no quarantine file; dir holds: $(ls -A "$ROUND_DIR")" >&2
    return 1
  }
  # A reviewer that may still be running needs its payload and output path kept.
  grep -qF 'subagent-stop-failed' "$ROUND_DIR/quarantine"
  grep -qF 'agent_xyz789' "$ROUND_DIR/quarantine"
}

@test "a subagent quarantine records no companion root to probe" {
  source "$LIB"
  make_round_dir
  review_subagent_record "$ROUND_DIR" stuck agent_q 600
  review_subagent_stop_failed "$ROUND_DIR" stuck
  # No shell-reachable API can ask whether a subagent is alive, so recording a
  # root would invite a probe that cannot mean anything.
  #
  # `^root[ =]`, not `^root=`: the quarantine record is space-separated
  # (`root <path>`), so an `=` pattern could never match and the negative would
  # be vacuous whatever the code did.
  grep -qE '^root[ =]' "$ROUND_DIR/quarantine" && {
    echo "a subagent quarantine recorded a probe root:" >&2
    cat "$ROUND_DIR/quarantine" >&2
    return 1
  }
  # Premise: the record really is written in that shape, so the pattern above
  # is aimed at the format in use.
  grep -qE '^mode subagent$' "$ROUND_DIR/quarantine" || {
    echo "the quarantine record is not in the space-separated shape assumed:" >&2
    cat "$ROUND_DIR/quarantine" >&2
    return 1
  }
  return 0
}

@test "stop_failed on an unrecorded agent is a named error, not an empty id" {
  source "$LIB"
  make_round_dir
  # `failed subagent-stop-failed` with no id is unactionable: the operator
  # cannot tell the host which agent to look for.
  run review_subagent_stop_failed "$ROUND_DIR" neverlaunched
  [ "$status" -ne 0 ]
  printf '%s\n' "$output" | grep -qF "neverlaunched"
}

@test "the cleanup gate refuses a quarantined round dir" {
  source "$LIB"
  make_round_dir
  review_subagent_record "$ROUND_DIR" stuck agent_s 600
  review_subagent_stop_failed "$ROUND_DIR" stuck
  run review_round_cleanup "$ROUND_DIR"
  [ "$status" -ne 0 ]
  [ -d "$ROUND_DIR" ] || { echo "the round dir was removed despite quarantine" >&2; return 1; }
}

# ---------------------------------------------------------------------------
# AC20a — the protocol as the runbook states it
# ---------------------------------------------------------------------------

@test "the runbook's timeout protocol launches in the background and waits for notifications" {
  # The spec's protocol is explicit that the orchestrator does NOT poll: it
  # launches in the background, which yields an agent id, and waits for a
  # completion notification. The landed text said "stop polling for a
  # response", which describes a loop that was never meant to exist.
  grep -qiE 'in the background' "$RUNBOOK" || {
    echo "the runbook does not say the Agent launch is backgrounded:" >&2
    grep -niE 'agent id|background' "$RUNBOOK" >&2
    return 1
  }
  grep -qiE 'notification' "$RUNBOOK" || {
    echo "the runbook does not say the round waits for completion notifications" >&2
    return 1
  }
  grep -qiE '(rather than|instead of|never|not by) poll' "$RUNBOOK" || {
    echo "the runbook does not contrast waiting with polling:" >&2
    grep -niE 'poll' "$RUNBOOK" >&2
    return 1
  }
}

@test "the runbook's protocol calls each of the four subagent helpers" {
  local fn
  for fn in review_subagent_record review_subagent_deadline_expired \
            review_subagent_collect review_subagent_stop_failed; do
    grep -qF "$fn" "$RUNBOOK" || {
      echo "the runbook's protocol never calls $fn:" >&2
      sed -n '/^## 4\./,/^## 5\./p' "$RUNBOOK" >&2
      return 1
    }
  done
}

@test "the runbook states that partial output is never a verdict" {
  grep -qiE 'partial output is never a verdict|subagent-no-output' "$RUNBOOK" || {
    echo "the runbook does not cover the no-output case" >&2
    return 1
  }
}

@test "the runbook states that cleanup waits for every reviewer to be proven terminal" {
  grep -qiE 'proven terminal|proven to be terminal|every reviewer is proven' "$RUNBOOK" || {
    echo "the runbook does not state the cleanup gate in those terms:" >&2
    grep -niE 'cleanup|terminal' "$RUNBOOK" >&2
    return 1
  }
}

@test "the runbook's timeout protocol still has exactly seven numbered steps" {
  # Pinned by spec 0054 AC20 and asserted in spec-review-round-runbook.bats
  # too. Repeated here because this file is what rewrites the section: a
  # rewrite that drops a step would otherwise only red in the other file.
  local n
  n="$(sed -n '/^## 4\./,/^## 5\./p' "$RUNBOOK" | grep -cE '^[1-9]\. ')"
  [ "$n" -eq 7 ] || {
    echo "expected 7 numbered steps in the protocol, found $n" >&2
    sed -n '/^## 4\./,/^## 5\./p' "$RUNBOOK" >&2
    return 1
  }
}

@test "a late reviewer with no artifact is recorded late, not as no-output" {
  source "$LIB"
  make_round_dir
  # The ordering case. Both facts are true — it was late AND it wrote nothing —
  # so the order of the two checks decides the label, and that has to be a
  # CHOICE rather than an accident of how the function was written.
  #
  # Lateness wins: once the deadline has passed the round has already
  # finalized, so "this arrived too late to count" is the governing fact, and
  # what the artifact holds no longer matters. Both labels are non-verdicts, so
  # quorum is unaffected either way; this pins which one an operator reads.
  review_subagent_record "$ROUND_DIR" tardy agent_t -5
  run review_subagent_collect "$ROUND_DIR" tardy
  [ "$status" -eq 0 ]
  [ "$output" = "timeout late-completion" ] || {
    echo "expected lateness to govern; got: $output" >&2
    return 1
  }
}

@test "an agent name carrying a path separator is refused, not written through" {
  source "$LIB"
  make_round_dir
  # The record path is built from the agent name, so a name with a separator
  # would write the launch record outside the round dir — where the lease and
  # the cleanup gate do not reach it.
  run review_subagent_record "$ROUND_DIR" "../escape" agent_x 600
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | grep -qF "../escape"
  [ ! -e "$TEST_DIR/escape.subagent" ] || {
    echo "a record was written outside the round dir" >&2
    return 1
  }
  # Every reader of the record must refuse it too, not just the writer.
  run review_subagent_collect "$ROUND_DIR" "../escape"
  [ "$status" -eq 2 ]
  run review_subagent_deadline_expired "$ROUND_DIR" "sub/dir"
  [ "$status" -eq 2 ]
  run review_subagent_stop_failed "$ROUND_DIR" "sub/dir"
  [ "$status" -ne 0 ]
}
