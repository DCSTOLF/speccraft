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
  review_subagent_completed "$ROUND_DIR" good > /dev/null
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
  review_subagent_completed "$ROUND_DIR" tardy > /dev/null
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
  review_subagent_completed "$ROUND_DIR" tardy > /dev/null
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
  review_subagent_completed "$ROUND_DIR" tardy > /dev/null
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
  review_subagent_completed "$ROUND_DIR" ondisk > /dev/null
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

@test "the runbook's protocol calls each of the five subagent helpers" {
  local fn
  for fn in review_subagent_record review_subagent_completed \
            review_subagent_deadline_expired \
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

@test "a reviewer with no artifact is no-output, whatever the clock says" {
  source "$LIB"
  make_round_dir
  # THIS ROW WAS REVERSED by Phase G.5, deliberately and not reluctantly.
  #
  # It used to assert that lateness governs when BOTH facts are true — the
  # deadline had passed and nothing was written. That ordering only made sense
  # while lateness was decided by comparing NOW against the deadline. Round 8
  # showed that test to be wrong: the protocol has the orchestrator wait for
  # the SLOWEST reviewer before collecting, so "now is past the deadline" was
  # true for every reviewer in any round containing one timeout, and a fast
  # reviewer's timely verdict was being thrown away.
  #
  # Lateness is now decided by the ARTIFACT's mtime — did the output LAND after
  # its deadline, which is what AC20b actually says. With no artifact there is
  # no time to compare, so the only fact available is the diagnosable one: the
  # agent returned without writing a verdict.
  review_subagent_record "$ROUND_DIR" tardy agent_t -5
  run review_subagent_collect "$ROUND_DIR" tardy
  [ "$status" -eq 0 ]
  [ "$output" = "failed subagent-no-output" ] || {
    echo "expected subagent-no-output with no artifact to time; got: $output" >&2
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

# ---------------------------------------------------------------------------
# AC17d — attributing an out-of-bounds write when subagents run concurrently.
#
# A subagent shares the orchestrating session's filesystem access. The round
# takes a tree snapshot before and after dispatch, so a write outside the round
# dir is DETECTABLE — but with two subagents running concurrently it is not
# ATTRIBUTABLE: nothing in the snapshot says which of them wrote.
#
# So the rule is conditioned on how many were active, and the honest answer
# when two were is to fail BOTH with an `<unattributed>` marker. That is
# deliberately harsh: it means one reviewer's misbehaviour voids the other's
# verdict. The alternative — guessing, or letting both stand — would either
# blame an innocent reviewer by name or admit a verdict from a round whose
# integrity is unknown.
#
# "Active" is read from the launch records in the round dir, never inferred
# from wall-clock timing (conventions.md §Ledger write-lock: contention tests
# use the seam, never timing). Every subagent with a launch record was live at
# some point between the two snapshots by construction, since `tree.before` is
# taken right after the round dir is created and `tree.after` only once every
# reviewer is terminal.
# ---------------------------------------------------------------------------

# snapshots <changed|same> — the pre/post pair the attributor compares.
snapshots() {
  printf 'a  111\nb  222\n' > "$ROUND_DIR/tree.before"
  if [ "$1" = changed ]; then
    printf 'a  111\nb  222\nc  333\n' > "$ROUND_DIR/tree.after"
  else
    cp "$ROUND_DIR/tree.before" "$ROUND_DIR/tree.after"
  fi
}

@test "two concurrent subagents with one writing out of bounds both record unattributed" {
  source "$LIB"
  make_round_dir
  review_subagent_record "$ROUND_DIR" alpha agent_a 600
  review_subagent_record "$ROUND_DIR" beta  agent_b 600
  snapshots changed
  run review_attribute_tree_writes "$ROUND_DIR"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qxF 'alpha failed subagent-wrote-files <unattributed>' || {
    echo "alpha not failed: $output" >&2
    return 1
  }
  printf '%s\n' "$output" | grep -qxF 'beta failed subagent-wrote-files <unattributed>' || {
    echo "beta not failed: $output" >&2
    return 1
  }
  [ "$(printf '%s\n' "$output" | grep -c 'subagent-wrote-files')" = "2" ]
}

@test "that round's responses_complete is false and quorum cannot be met" {
  source "$LIB"
  make_round_dir
  review_subagent_record "$ROUND_DIR" alpha agent_a 600
  review_subagent_record "$ROUND_DIR" beta  agent_b 600
  snapshots changed
  # beta reviewed honestly and approved. Its verdict must NOT carry the round.
  review_attribute_tree_writes "$ROUND_DIR" > "$TEST_DIR/outcomes"
  run review_responses_complete "$TEST_DIR/outcomes"
  [ "$status" -eq 1 ]
  run review_approval_quorum_met 1 "$TEST_DIR/outcomes"
  [ "$status" -eq 1 ]
}

@test "with exactly one subagent active the outcome names that agent" {
  source "$LIB"
  make_round_dir
  review_subagent_record "$ROUND_DIR" solo agent_s 600
  snapshots changed
  run review_attribute_tree_writes "$ROUND_DIR"
  [ "$status" -eq 0 ]
  [ "$output" = "solo failed subagent-wrote-files" ] || {
    echo "unexpected single-agent attribution: $output" >&2
    return 1
  }
}

@test "the single-agent outcome carries no unattributed marker" {
  source "$LIB"
  make_round_dir
  review_subagent_record "$ROUND_DIR" solo agent_s 600
  snapshots changed
  run review_attribute_tree_writes "$ROUND_DIR"
  printf '%s\n' "$output" | grep -qF '<unattributed>' && {
    echo "a sole subagent was marked unattributed: $output" >&2
    return 1
  }
  return 0
}

@test "the unattributed guard bites on the two-agent output" {
  source "$LIB"
  # Premise for the row above: prove the marker IS what the two-agent case
  # emits, so its absence in the one-agent case is a real distinction.
  make_round_dir
  review_subagent_record "$ROUND_DIR" alpha agent_a 600
  review_subagent_record "$ROUND_DIR" beta  agent_b 600
  snapshots changed
  run review_attribute_tree_writes "$ROUND_DIR"
  printf '%s\n' "$output" | grep -qF '<unattributed>' || {
    echo "the two-agent case emits no marker, so the negative is vacuous" >&2
    return 1
  }
}

@test "two concurrent subagents with no out-of-bounds write record neither failure" {
  source "$LIB"
  make_round_dir
  review_subagent_record "$ROUND_DIR" alpha agent_a 600
  review_subagent_record "$ROUND_DIR" beta  agent_b 600
  snapshots same
  run review_attribute_tree_writes "$ROUND_DIR"
  [ "$status" -eq 0 ]
  # The rule is NOT "fail everything when more than one runs". Without this
  # row, an implementation that failed both on sight of two records would pass
  # every other row in this section.
  [ -z "$output" ] || {
    echo "a clean two-subagent round recorded a failure: $output" >&2
    return 1
  }
}

@test "a codex-plugin reviewer running alongside a writing subagent is not failed" {
  source "$LIB"
  make_round_dir
  review_subagent_record "$ROUND_DIR" alpha agent_a 600
  # The codex-plugin reviewer leaves its own artifacts but NO launch record:
  # its touchedFiles is per job, self-attested and attributable, so a tree
  # difference is never charged to it.
  printf 'verdict: approve\n' > "$ROUND_DIR/codexp.out"
  printf 'job-1\n'            > "$ROUND_DIR/codexp.job"
  snapshots changed
  run review_attribute_tree_writes "$ROUND_DIR"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF 'codexp' && {
    echo "a codex-plugin reviewer was swept into the attribution: $output" >&2
    return 1
  }
  # …and the sole subagent is still named, rather than the round giving up.
  [ "$output" = "alpha failed subagent-wrote-files" ]
}

@test "activity spans the snapshot interval, not an instant" {
  source "$LIB"
  make_round_dir
  # Both subagents have already RETURNED — their artifacts are on disk and
  # neither is running now. They were nonetheless both live between the two
  # snapshots, so the write is still unattributable. An implementation that
  # asked "which agents are running at this moment" would attribute it to
  # nobody and let a tainted round complete.
  review_subagent_record "$ROUND_DIR" alpha agent_a 600
  review_subagent_record "$ROUND_DIR" beta  agent_b 600
  printf 'verdict: approve\n' > "$ROUND_DIR/alpha.out"
  printf 'verdict: approve\n' > "$ROUND_DIR/beta.out"
  snapshots changed
  run review_attribute_tree_writes "$ROUND_DIR"
  [ "$(printf '%s\n' "$output" | grep -c '<unattributed>')" = "2" ]
}

@test "a tree change with no subagent active blames no reviewer, but says so" {
  source "$LIB"
  make_round_dir
  snapshots changed
  run review_attribute_tree_writes "$ROUND_DIR"
  [ "$status" -eq 0 ]
  # Nothing on stdout: no reviewer can be blamed, and inventing one would be
  # worse than the change going unattributed.
  out="$(review_attribute_tree_writes "$ROUND_DIR" 2>/dev/null)"
  [ -z "$out" ] || { echo "blamed a reviewer that never ran: $out" >&2; return 1; }
  # But NOT silently: an unexplained tree change during a round is worth a word.
  err="$(review_attribute_tree_writes "$ROUND_DIR" 2>&1 >/dev/null)"
  [ -n "$err" ] || { echo "an unattributable tree change passed silently" >&2; return 1; }
}

@test "a missing snapshot is a named error, not an implied clean tree" {
  source "$LIB"
  make_round_dir
  review_subagent_record "$ROUND_DIR" alpha agent_a 600
  run review_attribute_tree_writes "$ROUND_DIR"
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | grep -qF 'tree.before'
  # One present and one absent is the same error: comparing a snapshot against
  # nothing must never read as "no change".
  printf 'a  111\n' > "$ROUND_DIR/tree.before"
  run review_attribute_tree_writes "$ROUND_DIR"
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | grep -qF 'tree.after'
}

@test "the attributed outcome classifies as a non-verdict the round can finalize" {
  source "$LIB"
  make_round_dir
  review_subagent_record "$ROUND_DIR" solo agent_s 600
  snapshots changed
  out="$(review_attribute_tree_writes "$ROUND_DIR")"
  run _review_outcome_kind "$(printf '%s\n' "$out" | awk '{print $2}')"
  [ "$status" -eq 0 ]
  [ "$output" = "non-verdict" ]
}

@test "the runbook's attribution rule is conditioned on how many subagents ran" {
  # The landed text said both reviewers record it whenever "more than one
  # subagent" is active, with no one-agent arm and no clean-round arm.
  # `review_attribute_tree_` covers both names: the runbook now calls the
  # REWRITING form (`_outcomes`), and this row is about the RULE being
  # conditioned on the subagent count, not about which of the two it calls.
  # The sibling row below pins that it uses the rewriting one.
  grep -qF 'review_attribute_tree_' "$RUNBOOK" || {
    echo "the runbook does not call the attributor:" >&2
    sed -n '/^## 7\./,$p' "$RUNBOOK" >&2
    return 1
  }
  grep -qF '<unattributed>' "$RUNBOOK" || {
    echo "the runbook never names the unattributed marker" >&2
    return 1
  }
  # Scoped to §7, and anchored on the arm's OUTCOME rather than on a count
  # phrase. A whole-file `exactly one` is satisfied by §0's "exactly one
  # composer" — unrelated prose — so deleting the one-subagent arm from the
  # table left this row green.
  local sec
  sec="$(sed -n '/^## 7\./,$p' "$RUNBOOK")"
  [ -n "$sec" ] || { echo "could not isolate §7; row would be vacuous" >&2; return 1; }
  printf '%s\n' "$sec" | grep -qE '(one|single)[^|]*\| *`?<agent> failed subagent-wrote-files`? *— *named' || {
    echo "§7 states no one-subagent arm, so the rule reads as fail-everything:" >&2
    printf '%s\n' "$sec" | grep -nE 'subagent-wrote-files|unattributed' >&2
    return 1
  }
  printf '%s\n' "$sec" | grep -qiE 'more than one|two running|concurrent' || {
    echo "§7 states no many-subagent arm" >&2
    return 1
  }
  printf '%s\n' "$sec" | grep -qiE 'neither failure|records \*\*neither\*\*|not .fail everything' || {
    echo "§7 does not say a clean two-subagent round records neither failure" >&2
    return 1
  }
}

@test "the attribution-arm guard is not satisfied by prose outside section 7" {
  # Premise for the row above. §0 legitimately says "exactly one composer";
  # that sentence must satisfy none of the three arm assertions.
  printf 'contract: exactly one composer, so there is exactly one answer.\n' \
    > "$TEST_DIR/sec0"
  grep -qE '(one|single)[^|]*\| *`?<agent> failed subagent-wrote-files`? *— *named' \
    "$TEST_DIR/sec0" && {
    echo "the one-arm pattern matched unrelated composer prose" >&2
    return 1
  }
  # And it must match the real table row, pipes and backticks included.
  printf '| exactly one | `<agent> failed subagent-wrote-files` — named |\n' \
    > "$TEST_DIR/sec7"
  grep -qE '(one|single)[^|]*\| *`?<agent> failed subagent-wrote-files`? *— *named' \
    "$TEST_DIR/sec7" || {
    echo "the one-arm pattern misses the real table row" >&2
    return 1
  }
  return 0
}

# ---------------------------------------------------------------------------
# Phase G.5 — remediation from cross-model code-review round 8.
#
# Four defects, all reproduced before being fixed, and all invisible to the
# unit rows above because each lives in the SEAM between two helpers that are
# individually correct.
# ---------------------------------------------------------------------------

@test "the outcomes file never records the ok token" {
  source "$LIB"
  make_round_dir
  # `ok` is the PROCEED signal, the same shape review_budget_check and
  # review_subagent_preflight use. It is not an outcome: the outcomes file is
  # read as `<agent> <outcome> <rest>`, and `ok` hits
  # _review_outcome_kind's unknown-token arm, which aborts the whole round with
  # exit 2. The runbook recorded it unconditionally, so EVERY successful
  # subagent round died at the first predicate.
  review_subagent_record "$ROUND_DIR" rev agent_1 600
  printf 'verdict: approve\n' > "$ROUND_DIR/rev.out"
  review_subagent_completed "$ROUND_DIR" rev > /dev/null
  local col
  col="$(review_subagent_collect "$ROUND_DIR" rev)"
  [ "$col" = "ok" ]
  run _review_outcome_kind "$col"
  [ "$status" -eq 2 ] || {
    echo "ok has become a recordable outcome; this row needs rethinking" >&2
    return 1
  }
  # So the runbook must BRANCH on it rather than append it.
  grep -qE 'if \[ "\$COL" != ok \]|\[ "\$COL" = ok \]' "$RUNBOOK" || {
    echo "the runbook does not branch on collect's ok token:" >&2
    grep -nF 'review_subagent_collect' -A3 "$RUNBOOK" >&2
    return 1
  }
}

@test "no runbook step appends collect's output without testing it first" {
  # The exact shape that shipped: `printf ... "$(review_subagent_collect …)" >> "$OUTCOMES"`.
  grep -qE 'review_subagent_collect[^)]*\)" *>> *"\$OUTCOMES"' "$RUNBOOK" && {
    echo "the runbook still appends collect's output unconditionally:" >&2
    grep -nE 'review_subagent_collect' "$RUNBOOK" >&2
    return 1
  }
  # Premise: the pattern matches the line it forbids.
  printf '  printf "%%s %%s\\n" "$agent" "$(review_subagent_collect "$ROUND_DIR" "$agent")" >> "$OUTCOMES"\n' \
    > "$TEST_DIR/old-step6"
  grep -qE 'review_subagent_collect[^)]*\)" *>> *"\$OUTCOMES"' "$TEST_DIR/old-step6" || {
    echo "the guard pattern does not match the historical line" >&2
    cat "$TEST_DIR/old-step6" >&2
    return 1
  }
  return 0
}

@test "a verdict stamped before its deadline is on time even when collected later" {
  source "$LIB"
  make_round_dir
  # The defect round 8 found: lateness was decided by comparing NOW against the
  # deadline, at the moment of collection. The protocol has the orchestrator
  # wait for the SLOWEST reviewer's deadline before collecting (§4 steps 3-4),
  # so a fast reviewer's perfectly timely verdict was recorded
  # `timeout late-completion` and dropped from quorum. One timeout could
  # discard every other verdict in the round.
  #
  # AC20b is about output that LANDS after its deadline, so what decides is the
  # completion stamp the orchestrator writes when the notification arrives.
  review_subagent_record "$ROUND_DIR" ontime agent_o 600
  printf 'verdict: approve\n' > "$ROUND_DIR/ontime.out"
  review_subagent_completed "$ROUND_DIR" ontime > /dev/null
  # Now move the deadline to just AFTER the completion stamp and well before
  # now — the fast-reviewer-plus-one-timeout shape, where collection happens
  # long after the deadline has passed.
  local done_at
  done_at="$(awk -F= '/^completed=/ {print $2; exit}' "$ROUND_DIR/ontime.subagent")"
  [ -n "$done_at" ] || { echo "no completion stamp was written" >&2; return 1; }
  printf 'agent=ontime\nagent_id=agent_o\nlaunched=%s\ndeadline=%s\ncompleted=%s\n' \
    "$((done_at - 10))" "$((done_at + 1))" "$done_at" > "$ROUND_DIR/ontime.subagent"
  run review_subagent_collect "$ROUND_DIR" ontime
  [ "$status" -eq 0 ]
  [ "$output" = "ok" ] || {
    echo "a verdict stamped before its deadline was recorded '$output'" >&2
    return 1
  }
}

@test "a verdict stamped after its deadline is still late-completion" {
  source "$LIB"
  make_round_dir
  # The converse, so the fix above cannot have simply disabled the check.
  review_subagent_record "$ROUND_DIR" tardy2 agent_t2 600
  printf 'verdict: approve\n' > "$ROUND_DIR/tardy2.out"
  review_subagent_completed "$ROUND_DIR" tardy2 > /dev/null
  local done_at
  done_at="$(awk -F= '/^completed=/ {print $2; exit}' "$ROUND_DIR/tardy2.subagent")"
  printf 'agent=tardy2\nagent_id=agent_t2\nlaunched=%s\ndeadline=%s\ncompleted=%s\n' \
    "$((done_at - 100))" "$((done_at - 1))" "$done_at" > "$ROUND_DIR/tardy2.subagent"
  run review_subagent_collect "$ROUND_DIR" tardy2
  [ "$output" = "timeout late-completion" ] || {
    echo "a verdict stamped after its deadline was recorded '$output'" >&2
    return 1
  }
}

@test "review_subagent_completed stamps an epoch second into the launch record" {
  source "$LIB"
  make_round_dir
  review_subagent_record "$ROUND_DIR" rev agent_r 600
  run review_subagent_completed "$ROUND_DIR" rev
  [ "$status" -eq 0 ]
  case "$output" in ''|*[!0-9]*) echo "not an epoch second: '$output'" >&2; return 1 ;; esac
  grep -qE '^completed=[0-9]+$' "$ROUND_DIR/rev.subagent" || {
    echo "no completed= line in the record:" >&2
    cat "$ROUND_DIR/rev.subagent" >&2
    return 1
  }
  local now; now="$(date +%s)"
  [ "$output" -le "$now" ] && [ "$output" -ge "$((now - 120))" ]
}

@test "stamping an unrecorded agent is a named error" {
  source "$LIB"
  make_round_dir
  # A stamp with no launch record has no deadline to be judged against, so it
  # would be data nothing can use.
  run review_subagent_completed "$ROUND_DIR" neverlaunched
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | grep -qF "neverlaunched"
}

@test "an artifact with no completion stamp is a named error, never a guess" {
  source "$LIB"
  make_round_dir
  # This is the one case where guessing is tempting and wrong twice over.
  # Falling back to `now` reintroduces the exact defect round 8 found;
  # assuming on-time lets a genuinely late verdict into quorum. So the
  # protocol must have stamped it, and if it did not, say so.
  review_subagent_record "$ROUND_DIR" unstamped agent_u 600
  printf 'verdict: approve\n' > "$ROUND_DIR/unstamped.out"
  run review_subagent_collect "$ROUND_DIR" unstamped
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | grep -qF 'review_subagent_completed' || {
    echo "the error does not name the missing step: $output" >&2
    return 1
  }
}

@test "a missing artifact is no-output even when the deadline has passed" {
  source "$LIB"
  make_round_dir
  # The ordering changed with the fix: no-output is now decided FIRST, because
  # with the artifact's mtime as the lateness test there is nothing to read a
  # time from when the artifact is absent. The agent returned without writing,
  # which is the diagnosable fact.
  review_subagent_record "$ROUND_DIR" silent2 agent_s2 -5
  run review_subagent_collect "$ROUND_DIR" silent2
  [ "$status" -eq 0 ]
  [ "$output" = "failed subagent-no-output" ] || {
    echo "expected subagent-no-output, got '$output'" >&2
    return 1
  }
}

# ---------------------------------------------------------------------------
# AC17d — a disqualified approval must not count
# ---------------------------------------------------------------------------

@test "review_attribute_tree_outcomes replaces the implicated reviewers' records" {
  source "$LIB"
  make_round_dir
  review_subagent_record "$ROUND_DIR" alpha agent_a 600
  review_subagent_record "$ROUND_DIR" beta  agent_b 600
  snapshots changed
  printf 'alpha approve\nbeta approve\n' > "$TEST_DIR/outcomes"
  run review_attribute_tree_outcomes "$ROUND_DIR" "$TEST_DIR/outcomes"
  # Exit 1 means "records were rewritten", matching
  # review_hash_collision_outcomes; exit 0 means the tree was clean. A caller
  # that treated 1 as failure would abort a round on a correct disqualification.
  [ "$status" -eq 1 ]
  # REPLACED, not appended: one authoritative record per reviewer.
  [ "$(grep -c . "$TEST_DIR/outcomes")" -eq 2 ] || {
    echo "the outcomes file grew instead of being rewritten:" >&2
    cat "$TEST_DIR/outcomes" >&2
    return 1
  }
  grep -qxF 'alpha failed subagent-wrote-files <unattributed>' "$TEST_DIR/outcomes"
  grep -qxF 'beta failed subagent-wrote-files <unattributed>' "$TEST_DIR/outcomes"
  grep -qF 'approve' "$TEST_DIR/outcomes" && {
    echo "a disqualified approval survived the rewrite:" >&2
    cat "$TEST_DIR/outcomes" >&2
    return 1
  }
  return 0
}

@test "a disqualified approval cannot meet quorum" {
  source "$LIB"
  make_round_dir
  review_subagent_record "$ROUND_DIR" alpha agent_a 600
  review_subagent_record "$ROUND_DIR" beta  agent_b 600
  snapshots changed
  printf 'alpha approve\nbeta approve\n' > "$TEST_DIR/outcomes"
  review_attribute_tree_outcomes "$ROUND_DIR" "$TEST_DIR/outcomes" || true
  # The whole point of AC17d. Before the fix the attribution was APPENDED, so
  # the approvals stayed in the file and the round reported
  # responses_complete: false with approval_quorum_met: TRUE — an innocent
  # reviewer's approval carrying a round whose integrity is unknown.
  run review_approval_quorum_met 1 "$TEST_DIR/outcomes"
  [ "$status" -eq 1 ] || { echo "the disqualified approval still met quorum" >&2; return 1; }
  run review_responses_complete "$TEST_DIR/outcomes"
  [ "$status" -eq 1 ]
}

@test "the rewrite leaves an uninvolved reviewer's verdict intact" {
  source "$LIB"
  make_round_dir
  review_subagent_record "$ROUND_DIR" alpha agent_a 600
  snapshots changed
  # A cli reviewer has no launch record, so it is not implicated — and its
  # verdict must survive. A rewrite that blanked the whole file would pass the
  # rows above.
  printf 'alpha approve\ncodex changes-requested\n' > "$TEST_DIR/outcomes"
  review_attribute_tree_outcomes "$ROUND_DIR" "$TEST_DIR/outcomes" || true
  grep -qxF 'codex changes-requested' "$TEST_DIR/outcomes" || {
    echo "an uninvolved reviewer's verdict was rewritten:" >&2
    cat "$TEST_DIR/outcomes" >&2
    return 1
  }
  grep -qxF 'alpha failed subagent-wrote-files' "$TEST_DIR/outcomes"
}

@test "a clean tree leaves the outcomes file byte-unchanged" {
  source "$LIB"
  make_round_dir
  review_subagent_record "$ROUND_DIR" alpha agent_a 600
  snapshots same
  printf 'alpha approve\n' > "$TEST_DIR/outcomes"
  cp "$TEST_DIR/outcomes" "$TEST_DIR/before"
  run review_attribute_tree_outcomes "$ROUND_DIR" "$TEST_DIR/outcomes"
  [ "$status" -eq 0 ]
  cmp -s "$TEST_DIR/before" "$TEST_DIR/outcomes" || {
    echo "a clean round rewrote the outcomes file" >&2
    return 1
  }
}

@test "the runbook rewrites outcomes rather than appending the attribution" {
  grep -qF 'review_attribute_tree_outcomes' "$RUNBOOK" || {
    echo "the runbook does not use the rewriting form:" >&2
    grep -nF 'review_attribute_tree' "$RUNBOOK" >&2
    return 1
  }
  # And the appending form must be gone, or both run and the file grows.
  grep -qE 'review_attribute_tree_writes[^)]*>> *"\$OUTCOMES"' "$RUNBOOK" && {
    echo "the runbook still appends the attribution:" >&2
    grep -nF 'review_attribute_tree' "$RUNBOOK" >&2
    return 1
  }
  return 0
}

# ---------------------------------------------------------------------------
# AC18b — the preflight holes
# ---------------------------------------------------------------------------

@test "a YAML block-list tools key is read, not treated as absent" {
  source "$LIB"
  # The hole: _review_frontmatter_field returns the text after `tools:` on the
  # SAME line. A block list leaves that empty, which took the "declares no
  # tools, inherits everything" branch — so a Write-less agent passed preflight
  # and the round later recorded subagent-no-output after a full model run.
  cat > "$AGENTS_DIR/blocked.md" <<'AGENT'
---
name: blocked
tools:
  - Read
  - Grep
model: inherit
---
body
AGENT
  run review_subagent_preflight "$AGENTS_DIR" blocked
  [ "$status" -eq 0 ]
  [ "$output" = "failed subagent-launch missing-write-tool" ] || {
    echo "a block-list agent with no Write was not refused: '$output'" >&2
    return 1
  }
}

@test "a block list containing Write passes, and one containing Edit warns" {
  source "$LIB"
  cat > "$AGENTS_DIR/blockok.md" <<'AGENT'
---
name: blockok
tools:
  - Read
  - Write
model: inherit
---
body
AGENT
  run review_subagent_preflight "$AGENTS_DIR" blockok
  [ "$output" = "ok" ]
  cat > "$AGENTS_DIR/blockedit.md" <<'AGENT'
---
name: blockedit
tools:
  - Read
  - Edit
  - Write
model: inherit
---
body
AGENT
  out="$(review_subagent_preflight "$AGENTS_DIR" blockedit 2>/dev/null)"
  [ "$out" = "ok" ]
  err="$(review_subagent_preflight "$AGENTS_DIR" blockedit 2>&1 >/dev/null)"
  printf '%s\n' "$err" | grep -qF "Edit" || {
    echo "the Edit warning is missing for a block list: '$err'" >&2
    return 1
  }
}

@test "a genuinely absent tools key still takes the unconfined arm" {
  source "$LIB"
  # The block-list fix must not swallow the real no-tools case.
  make_agent nokey ''
  out="$(review_subagent_preflight "$AGENTS_DIR" nokey 2>/dev/null)"
  [ "$out" = "ok" ]
  err="$(review_subagent_preflight "$AGENTS_DIR" nokey 2>&1 >/dev/null)"
  printf '%s\n' "$err" | grep -qF "no tools" || {
    echo "an agent with no tools key lost its warning: '$err'" >&2
    return 1
  }
}

@test "a foreign plugin qualifier is refused, not resolved against speccraft's agents" {
  source "$LIB"
  make_agent reviewer '[Read, Grep, Glob, Write]'
  # The hole: `${type##*:}` strips EVERY qualifier, so `otherplugin:reviewer`
  # was approved by inspecting speccraft's own agents/reviewer.md while the
  # Agent tool would launch a different plugin's agent entirely — one that may
  # lack Write (the very failure this check exists to prevent) or declare Edit
  # (whose warning is then never shown).
  run review_subagent_preflight "$AGENTS_DIR" otherplugin:reviewer
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qE '^failed subagent-launch ' || {
    echo "a foreign plugin qualifier was accepted: '$output'" >&2
    return 1
  }
  printf '%s\n' "$output" | grep -qF 'otherplugin' || {
    echo "the refusal does not name the qualifier: '$output'" >&2
    return 1
  }
}

@test "a multi-colon qualifier is refused too" {
  source "$LIB"
  make_agent reviewer '[Read, Grep, Glob, Write]'
  run review_subagent_preflight "$AGENTS_DIR" a:b:reviewer
  printf '%s\n' "$output" | grep -qE '^failed subagent-launch ' || {
    echo "a:b:reviewer was accepted: '$output'" >&2
    return 1
  }
}

@test "speccraft's own qualifier is still stripped" {
  source "$LIB"
  make_agent reviewer '[Read, Grep, Glob, Write]'
  # The regression floor for the fix: the dispatch default IS
  # `speccraft:reviewer`, so refusing every qualifier would refuse the one
  # reviewer this spec ships.
  run review_subagent_preflight "$AGENTS_DIR" speccraft:reviewer
  [ "$output" = "ok" ]
  run review_subagent_preflight "$AGENTS_DIR" reviewer
  [ "$output" = "ok" ]
}

@test "an agent name with a newline or a glob character is refused" {
  source "$LIB"
  make_round_dir
  # Registry names are user-controlled, and the launch record is a
  # `key=value` file read with awk -F=. A newline in the name breaks that
  # format; a glob character can match a path the caller did not mean.
  run review_subagent_record "$ROUND_DIR" 'two
lines' agent_x 600
  [ "$status" -eq 2 ]
  run review_subagent_record "$ROUND_DIR" 'star*' agent_x 600
  [ "$status" -eq 2 ]
  run review_subagent_record "$ROUND_DIR" 'brack[et]' agent_x 600
  [ "$status" -eq 2 ]
  # …while the names real registries use are still accepted.
  run review_subagent_record "$ROUND_DIR" 'claude-p' agent_x 600
  [ "$status" -eq 0 ]
  run review_subagent_record "$ROUND_DIR" 'codex_acp.v2' agent_x 600
  [ "$status" -eq 0 ]
}

@test "the runbook stamps completion before it collects" {
  # Ordering again, and for the same reason as the outcomes-file init: the
  # stamp has to be written when the notification arrives, which is strictly
  # before the collection step that reads it. A runbook that stamped at
  # collection time would reproduce exactly the defect the stamp replaced.
  local stamp collect
  stamp="$(grep -nF 'review_subagent_completed' "$RUNBOOK" | head -1 | cut -d: -f1)"
  collect="$(grep -nF 'review_subagent_collect' "$RUNBOOK" | head -1 | cut -d: -f1)"
  [ -n "$stamp" ] || { echo "the runbook never stamps completion" >&2; return 1; }
  [ -n "$collect" ] || { echo "the runbook never collects; row would be vacuous" >&2; return 1; }
  [ "$stamp" -lt "$collect" ] || {
    echo "the runbook stamps at line $stamp, after collecting at $collect" >&2
    return 1
  }
}

@test "the runbook says collection time is not completion time" {
  # The reasoning has to be in the text, or the next editor moves the stamp to
  # the collection step because it reads more tidily there.
  grep -qiE 'collection time is NOT|not when (it|the reviewer) finished' "$RUNBOOK" || {
    echo "the runbook does not warn that collection time is not completion time:" >&2
    grep -niF 'review_subagent_completed' -A3 "$RUNBOOK" >&2
    return 1
  }
}

@test "an UNINDENTED YAML block list is read, not treated as absent" {
  source "$LIB"
  # Round 9. The block-list branch first required indentation, but an
  # unindented sequence under a key is legal YAML — and an agent using one had
  # its grants read as ABSENT, took the "inherits every tool" arm, and passed
  # preflight with no Write at all.
  cat > "$AGENTS_DIR/unindented.md" <<'AGENT'
---
name: unindented
tools:
- Read
- Grep
model: inherit
---
body
AGENT
  run review_subagent_preflight "$AGENTS_DIR" unindented
  [ "$status" -eq 0 ]
  [ "$output" = "failed subagent-launch missing-write-tool" ] || {
    echo "an unindented block list with no Write was not refused: '$output'" >&2
    return 1
  }
  # …and one that DOES grant Write still passes, so the fix is not a blanket
  # refusal of unindented lists.
  cat > "$AGENTS_DIR/unindented-ok.md" <<'AGENT'
---
name: unindented-ok
tools:
- Read
- Write
model: inherit
---
body
AGENT
  run review_subagent_preflight "$AGENTS_DIR" unindented-ok
  [ "$output" = "ok" ]
}

@test "a nested indented key cannot shadow the real top-level one" {
  source "$LIB"
  # Round 9: the key match stripped whitespace, so an indented `tools:` inside
  # a `meta:` block matched first and won. That is a preflight BYPASS — an
  # agent could declare a generous nested list and a Write-less real one.
  cat > "$AGENTS_DIR/nested.md" <<'AGENT'
---
name: nested
meta:
  tools: [Read, Write, Edit]
tools: [Read, Grep]
model: inherit
---
body
AGENT
  [ "$(_review_frontmatter_field "$AGENTS_DIR/nested.md" tools)" = "[Read, Grep]" ] || {
    echo "the nested key won: '$(_review_frontmatter_field "$AGENTS_DIR/nested.md" tools)'" >&2
    return 1
  }
  run review_subagent_preflight "$AGENTS_DIR" nested
  [ "$output" = "failed subagent-launch missing-write-tool" ] || {
    echo "the nested grant list was used for the preflight: '$output'" >&2
    return 1
  }
}

@test "a block-list value is emitted exactly once" {
  source "$LIB"
  # In POSIX awk, `exit` inside a main rule still runs END — so the branch that
  # printed on list end and the END rule both fired, and the helper returned
  # its value twice. Harmless for a membership test, wrong for anything that
  # reads "the value".
  cat > "$AGENTS_DIR/twice.md" <<'AGENT'
---
name: twice
authors:
  - claude
  - dstolf
status: draft
---
body
AGENT
  local out
  out="$(_review_frontmatter_field "$AGENTS_DIR/twice.md" authors)"
  [ "$(printf '%s\n' "$out" | grep -c .)" -eq 1 ] || {
    echo "the value was emitted more than once:" >&2
    printf '%s\n' "$out" >&2
    return 1
  }
  [ "$out" = "claude dstolf" ]
}
