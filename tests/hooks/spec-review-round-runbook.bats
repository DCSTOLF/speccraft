#!/usr/bin/env bats
# Spec 0054 ACs 19 / 20 — the shared round runbook and the four command files.
#
# Four commands run cross-model review today: spec:review, arch:review,
# pm:review and spec:review-code. Each has its own body, so a mode handled
# wrongly would be handled wrongly four times. This spec gives them ONE shared
# runbook and makes each command reference it.
#
# These are assertions over MARKDOWN. The runbook is executed by the
# orchestrating session rather than by a shell, so its text is the
# implementation and its wording is what gets tested.

setup() {
  PLUGIN_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  RUNBOOK="$PLUGIN_DIR/skills/review-round/SKILL.md"
  SPEC_CMD="$PLUGIN_DIR/commands/spec/review.md"
  ARCH_CMD="$PLUGIN_DIR/commands/arch/review.md"
  PM_CMD="$PLUGIN_DIR/commands/pm/review.md"
  CODE_CMD="$PLUGIN_DIR/commands/spec/review-code.md"
  ALL_CMDS="$SPEC_CMD $ARCH_CMD $PM_CMD $CODE_CMD"
  export PATH="$PLUGIN_DIR/bin:$PATH"
  TEST_DIR="$(mktemp -d)"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# allowed_tools <command-file> — the allowed-tools frontmatter line.
allowed_tools() {
  awk '/^allowed-tools:/ { print; exit }' "$1"
}

# ---------------------------------------------------------------------------
# AC20 — the shared runbook exists and covers all four modes
# ---------------------------------------------------------------------------

@test "the shared runbook file exists at skills/review-round/SKILL.md" {
  [ -f "$RUNBOOK" ]
  # A skill needs frontmatter to be loadable at all.
  head -1 "$RUNBOOK" | grep -qxF -- '---'
  grep -qE '^name: review-round$' "$RUNBOOK"
}

@test "the runbook names all four modes" {
  local m
  for m in cli acp codex-plugin subagent; do
    grep -qF -- "$m" "$RUNBOOK" || {
      echo "the runbook never mentions mode '$m'" >&2
      return 1
    }
  done
}

@test "the runbook states that subagent reviewers are dispatched by the orchestrating session" {
  # The distinction that keeps a subagent out of aux-delegator: only the
  # orchestrating session can start one, and review_dispatch_agent refuses the
  # mode outright for exactly that reason.
  grep -qiF 'orchestrating session' "$RUNBOOK"
  grep -qiF 'aux-delegator' "$RUNBOOK"
}

# ---------------------------------------------------------------------------
# AC19 — the model carried on an Agent dispatch
# ---------------------------------------------------------------------------

@test "the runbook's Agent dispatch carries model: opus for a registry model of opus" {
  grep -qE 'model: *opus' "$RUNBOOK" || {
    echo "the runbook never shows a model: opus dispatch" >&2
    return 1
  }
}

@test "the runbook carries no model when the registry says inherit or omits it" {
  # The absence has to be SPELLED OUT, or an implementer reading the opus
  # example above will pass a model every time.
  grep -qiE 'no .?model|omit.*model|without .*model' "$RUNBOOK" || {
    echo "the runbook does not say the model is omitted for inherit" >&2
    return 1
  }
  grep -qF 'inherit' "$RUNBOOK"
}

@test "the runbook states that the no-model case relies on reviewer.md's model: inherit" {
  # Why omitting the model is safe: the agent definition carries it instead.
  grep -qF 'reviewer.md' "$RUNBOOK" || {
    echo "the runbook does not point at reviewer.md for the inherited model" >&2
    return 1
  }
}

@test "the runbook records requested: inherit for a custom subagent_type with no model" {
  grep -qF 'requested: inherit' "$RUNBOOK" || {
    echo "the runbook does not record the requested: inherit outcome field" >&2
    return 1
  }
  grep -qF 'per <agent> definition' "$RUNBOOK" || {
    echo "the runbook does not carry the 'per <agent> definition' qualifier" >&2
    return 1
  }
}

# ---------------------------------------------------------------------------
# AC17a — the response is read from the artifact, never transcribed
# ---------------------------------------------------------------------------

@test "the runbook contains no instruction to transcribe the Agent result into .out" {
  # A missing runbook also contains no such instruction, so assert the premise
  # or this row passes before the file exists.
  [ -f "$RUNBOOK" ] || {
    echo "the runbook does not exist; this row would pass vacuously" >&2
    return 1
  }

  # The reviewer writes its own <agent>.out. An instruction to copy the Agent
  # tool's return value into that file would put the orchestrator's
  # paraphrase where the reviewer's bytes belong — and the attestation digest
  # is computed over those bytes.
  run bash -c 'grep -vE "^[[:space:]]*(#|>)" "$1" | grep -niE "transcribe|copy .*(result|response|output).*into|paste .*into .*\.out"' _ "$RUNBOOK"
  [ "$status" -ne 0 ] || {
    echo "the runbook instructs transcription:" >&2
    printf '%s\n' "$output" >&2
    return 1
  }
}

@test "the transcription guard bites on an executable line" {
  local probe="$TEST_DIR/probe.md"
  printf '%s\n' '> a quoted line about transcribe is not an instruction' > "$probe"
  run bash -c 'grep -vE "^[[:space:]]*(#|>)" "$1" | grep -niE "transcribe|copy .*(result|response|output).*into|paste .*into .*\.out"' _ "$probe"
  [ "$status" -ne 0 ]

  printf '%s\n' 'Then transcribe the Agent result into <agent>.out.' >> "$probe"
  run bash -c 'grep -vE "^[[:space:]]*(#|>)" "$1" | grep -niE "transcribe|copy .*(result|response|output).*into|paste .*into .*\.out"' _ "$probe"
  [ "$status" -eq 0 ]
}

@test "the runbook says the response is READ from the artifact the reviewer wrote" {
  # The positive counterpart, so the negative above cannot be satisfied by
  # saying nothing at all about where the response comes from.
  grep -qiE 'read .*(the )?(artifact|<agent>\.out|\.out file)' "$RUNBOOK" || {
    echo "the runbook does not say the response is read from the artifact" >&2
    return 1
  }
}

# ---------------------------------------------------------------------------
# The subagent timeout and cancellation protocol
# ---------------------------------------------------------------------------

@test "the runbook spells out the subagent timeout and cancellation protocol" {
  grep -qF 'TaskStop' "$RUNBOOK" || {
    echo "the runbook never names TaskStop" >&2
    return 1
  }
  grep -qF 'subagent-stop-failed' "$RUNBOOK" || {
    echo "the runbook does not name the subagent-stop-failed outcome" >&2
    return 1
  }
  # Quarantine is what a failed stop produces; without it the round dir would
  # be deleted under a reviewer that is still running.
  grep -qiF 'quarantine' "$RUNBOOK"
}

@test "the runbook's timeout protocol has seven numbered steps" {
  # Counted, so the protocol cannot be silently shortened to "stop it and move
  # on" — the steps are what keep an unstoppable reviewer from being recorded
  # as a plain timeout.
  local n
  n="$(awk '/[Tt]imeout .*protocol/,/^#{2,3} /' "$RUNBOOK" | grep -cE '^[[:space:]]*[1-9]\.')"
  [ "$n" -ge 7 ] || {
    echo "expected at least 7 numbered steps in the timeout protocol, found $n" >&2
    return 1
  }
}

@test "the runbook prints the round dir path for later tool calls" {
  # The runbook spans many tool calls and the shell does not persist between
  # them, so the round dir path has to be carried in the transcript.
  grep -qiE 'round dir|round directory' "$RUNBOOK"
  grep -qF 'review_round_dir_create' "$RUNBOOK" || {
    echo "the runbook does not call review_round_dir_create" >&2
    return 1
  }
}

# ---------------------------------------------------------------------------
# AC20 — all four command files
# ---------------------------------------------------------------------------

@test "each of the four review command files references the shared runbook" {
  local f
  for f in $ALL_CMDS; do
    grep -qF 'review-round' "$f" || {
      echo "$f does not reference the shared runbook" >&2
      return 1
    }
  done
}

@test "each of the four lists Agent in allowed-tools" {
  local f
  for f in $ALL_CMDS; do
    allowed_tools "$f" | grep -qF '"Agent"' || {
      echo "$f allowed-tools lacks Agent: $(allowed_tools "$f")" >&2
      return 1
    }
  done
}

@test "each of the four lists TaskStop in allowed-tools" {
  # Asserted in ALL FOUR: the timeout protocol cannot stop a reviewer without
  # it, so a command that dispatches subagents and cannot stop them would
  # record subagent-stop-failed on every timeout.
  local f
  for f in $ALL_CMDS; do
    allowed_tools "$f" | grep -qF '"TaskStop"' || {
      echo "$f allowed-tools lacks TaskStop: $(allowed_tools "$f")" >&2
      return 1
    }
  done
}

@test "each of the four lists Bash(shasum:*) and Bash(sha256sum:*)" {
  # Attestation digests are computed by the reviewer through Bash. Both
  # spellings, because the primitive is probed: shasum on BSD/macOS, the GNU
  # tool where shasum is absent.
  local f
  for f in $ALL_CMDS; do
    allowed_tools "$f" | grep -qF 'Bash(shasum:*)' || {
      echo "$f allowed-tools lacks Bash(shasum:*): $(allowed_tools "$f")" >&2
      return 1
    }
    allowed_tools "$f" | grep -qF 'Bash(sha256sum:*)' || {
      echo "$f allowed-tools lacks Bash(sha256sum:*): $(allowed_tools "$f")" >&2
      return 1
    }
  done
}

@test "review-code additionally lists Write" {
  # It records outcomes into the round dir; the other three already have Write
  # or do not need it.
  allowed_tools "$CODE_CMD" | grep -qF '"Write"' || {
    echo "review-code allowed-tools lacks Write: $(allowed_tools "$CODE_CMD")" >&2
    return 1
  }
}

@test "each of the four names all four modes" {
  local f m
  for f in $ALL_CMDS; do
    for m in cli acp codex-plugin subagent; do
      grep -qF -- "$m" "$f" || {
        echo "$f never mentions mode '$m'" >&2
        return 1
      }
    done
  done
}

@test "arch:review names design.md and design/<id>/review.md" {
  grep -qF 'design.md' "$ARCH_CMD"
  grep -qE 'design/[^ ]*/review\.md' "$ARCH_CMD" || {
    echo "arch:review does not name design/<id>/review.md" >&2
    return 1
  }
}

@test "pm:review names brief.md and product/<id>/review.md" {
  grep -qF 'brief.md' "$PM_CMD"
  grep -qE 'product/[^ ]*/review\.md' "$PM_CMD" || {
    echo "pm:review does not name product/<id>/review.md" >&2
    return 1
  }
}

@test "no review command still calls the backend unchanged" {
  # arch/review.md and pm/review.md both say exactly this today: that they use
  # the same backend as /speccraft:spec:review, "unchanged". After this spec
  # the backend is NOT unchanged — it grew two modes — so the prose would be
  # actively wrong.
  # Matched on the CLAIM, not the bare word: commands/spec/review.md says
  # review.md is left "byte-unchanged" on a failed round, which is both true
  # and unrelated. A bare `unchanged` needle flags that and would push an
  # author to reword a correct sentence.
  local f
  for f in $ALL_CMDS; do
    if grep -qE 'backend[^.]*unchanged|uses, unchanged' "$f"; then
      echo "$f still claims the backend is unchanged:" >&2
      grep -nE 'backend[^.]*unchanged|uses, unchanged' "$f" >&2
      return 1
    fi
  done
  return 0
}

@test "the unchanged-prose guard bites" {
  # Proves the row above is not passing because the needle is unmatchable.
  local probe="$TEST_DIR/probe2.md"
  # The exact prose arch/review.md and pm/review.md carried before this spec.
  printf '%s\n' 'the same multi-model backend /speccraft:spec:review uses, unchanged' > "$probe"
  run grep -qE 'backend[^.]*unchanged|uses, unchanged' "$probe"
  [ "$status" -eq 0 ]

  # And it does NOT flag the unrelated byte-unchanged sentence, or the guard
  # would be pressuring an author to reword something correct.
  printf '%s\n' 'review.md is left byte-unchanged, so a failed round is re-reviewed' > "$probe"
  run grep -qE 'backend[^.]*unchanged|uses, unchanged' "$probe"
  [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# AC17 — two byte-identical artifacts are a dispatch failure, not two verdicts
#
# This is the false-quorum bug that started the whole programme. If two
# reviewers' `.out` files are byte-identical, the round did not consult two
# models: something dispatched one reviewer twice, or wrote one response to
# both paths. Counting them as agreement reports "quorum of 2" for a round that
# asked one model once — the single most misleading output this system can
# produce, because it looks exactly like consensus.
#
# Spec 0052 left this as runbook PROSE ("hash-compare the outputs before
# counting them"), which nothing enforces. These rows pin a real helper.
# ---------------------------------------------------------------------------

LIBSH() { printf '%s\n' "$PLUGIN_DIR/commands/spec/review.lib.sh"; }

@test "two byte-identical agent.out artifacts in one round are reported as a dispatch failure" {
  source "$(LIBSH)"
  local d="$TEST_DIR/round"; mkdir -p "$d"
  printf 'verdict: approve\n' > "$d/codex.out"
  printf 'verdict: approve\n' > "$d/claude-p.out"

  run review_hash_compare_outputs "$d"
  [ "$status" -ne 0 ] || {
    echo "identical outputs must NOT be accepted as two verdicts" >&2
    return 1
  }
  # Both agents named, so an operator can tell WHICH pair collided rather than
  # being told only that something did.
  printf '%s\n' "$output" | grep -qF 'codex' || {
    echo "the failure must name the first agent; got: $output" >&2
    return 1
  }
  printf '%s\n' "$output" | grep -qF 'claude-p' || {
    echo "the failure must name the second agent; got: $output" >&2
    return 1
  }
}

@test "two byte-identical subagent artifacts are reported the same way" {
  source "$(LIBSH)"
  # AC17 says "including two subagents". A subagent's artifact is written by
  # the orchestrating session rather than by a CLI, so the duplicate-write path
  # is MORE likely there, not less — and the helper must not care about mode.
  local d="$TEST_DIR/round"; mkdir -p "$d"
  printf 'verdict: changes-requested\nconcerns: []\n' > "$d/sub-a.out"
  printf 'verdict: changes-requested\nconcerns: []\n' > "$d/sub-b.out"

  run review_hash_compare_outputs "$d"
  [ "$status" -ne 0 ]
  printf '%s\n' "$output" | grep -qF 'sub-a' && printf '%s\n' "$output" | grep -qF 'sub-b' || {
    echo "both subagents must be named; got: $output" >&2
    return 1
  }
}

@test "distinct outputs in one round are accepted" {
  source "$(LIBSH)"
  # The premise check. Without it, a helper that rejected every round would
  # satisfy both rows above.
  local d="$TEST_DIR/round"; mkdir -p "$d"
  printf 'verdict: approve\n' > "$d/codex.out"
  printf 'verdict: changes-requested\n' > "$d/claude-p.out"

  run review_hash_compare_outputs "$d"
  [ "$status" -eq 0 ] || {
    echo "two genuinely different verdicts must be accepted; got: $output" >&2
    return 1
  }
}

@test "outputs differing only in trailing newlines are NOT a collision" {
  source "$(LIBSH)"
  # The comparison must be over the FILES, and this is the row that proves it.
  # A capture-based implementation (`a=$(cat f1); b=$(cat f2)`) strips every
  # trailing newline, so it would call these two equal and fail an honest round
  # as a dispatch fault — refusing two genuinely different verdicts. AC17 says
  # BYTE-identical, and these are not byte-identical.
  local d="$TEST_DIR/round"; mkdir -p "$d"
  printf 'verdict: approve\n'     > "$d/codex.out"
  printf 'verdict: approve\n\n\n' > "$d/claude-p.out"

  run review_hash_compare_outputs "$d"
  [ "$status" -eq 0 ] || {
    echo "files differing in trailing newlines are distinct and must be accepted; got: $output" >&2
    return 1
  }
}

@test "byte-identical outputs collide even when both end in several newlines" {
  source "$(LIBSH)"
  # The other half: the file-based comparison must still catch a real duplicate
  # whose bytes happen to include trailing blank lines, so the row above cannot
  # have been satisfied by ignoring trailing whitespace altogether.
  local d="$TEST_DIR/round"; mkdir -p "$d"
  printf 'verdict: approve\n\n\n' > "$d/codex.out"
  printf 'verdict: approve\n\n\n' > "$d/claude-p.out"

  run review_hash_compare_outputs "$d"
  [ "$status" -ne 0 ] || {
    echo "identical bytes must collide regardless of trailing newlines; got: $output" >&2
    return 1
  }
}

@test "a single reviewer's round is not a collision with itself" {
  source "$(LIBSH)"
  local d="$TEST_DIR/round"; mkdir -p "$d"
  printf 'verdict: approve\n' > "$d/codex.out"
  run review_hash_compare_outputs "$d"
  [ "$status" -eq 0 ] || {
    echo "one reviewer must not collide with itself; got: $output" >&2
    return 1
  }
}

@test "a round with no artifacts at all is not reported as a collision" {
  source "$(LIBSH)"
  local d="$TEST_DIR/round"; mkdir -p "$d"
  run review_hash_compare_outputs "$d"
  [ "$status" -eq 0 ] || {
    echo "an empty round is inert, not a dispatch bug; got: $output" >&2
    return 1
  }
}

@test "three artifacts with one duplicated pair are reported" {
  source "$(LIBSH)"
  # So the comparison is pairwise rather than "all equal".
  local d="$TEST_DIR/round"; mkdir -p "$d"
  printf 'A\n' > "$d/one.out"
  printf 'B\n' > "$d/two.out"
  printf 'A\n' > "$d/three.out"
  run review_hash_compare_outputs "$d"
  [ "$status" -ne 0 ] || {
    echo "a duplicated pair among three must be caught; got: $output" >&2
    return 1
  }
  printf '%s\n' "$output" | grep -qF 'one' && printf '%s\n' "$output" | grep -qF 'three' || {
    echo "the colliding PAIR must be named, not the odd one out; got: $output" >&2
    return 1
  }
}

@test "the runbook says to hash-compare before counting verdicts" {
  # The helper is useless if the runbook never calls it: this is the step that
  # 0052 left as prose and nothing enforced.
  grep -qE 'review_hash_(compare_outputs|collision_outcomes)' "$RUNBOOK" || {
    echo "the runbook does not call the hash-compare step at all" >&2
    return 1
  }
  # And it must say the step comes BEFORE counting, which is the whole point:
  # a collision discovered after the quorum is computed changes nothing.
  grep -qiE 'before counting|not count' "$RUNBOOK" || {
    echo "the runbook does not say the comparison precedes counting" >&2
    return 1
  }
}

@test "neither verdict is counted when the hashes match" {
  source "$(LIBSH)"
  # The consequence that matters. A collision must not merely be REPORTED
  # somewhere — it must keep both records out of the quorum count, or a round
  # still reports consensus while naming the bug beside it.
  local d="$TEST_DIR/round"; mkdir -p "$d"
  printf '%s\n' 'codex approve' 'claude-p approve' > "$d/outcomes.txt"
  printf 'verdict: approve\n' > "$d/codex.out"
  printf 'verdict: approve\n' > "$d/claude-p.out"

  # Premise: at quorum 1 these two records WOULD meet quorum on their own.
  review_approval_quorum_met 1 "$d/outcomes.txt" || {
    echo "premise failed: two approvals must meet quorum 1 before the rewrite" >&2
    return 1
  }

  # After the collision is folded in, both become non-verdicts.
  review_hash_collision_outcomes "$d" "$d/outcomes.txt" || true
  run review_approval_quorum_met 1 "$d/outcomes.txt"
  [ "$status" -ne 0 ] || {
    echo "a collision must leave quorum unmet; outcomes now:" >&2
    cat "$d/outcomes.txt" >&2
    return 1
  }
  grep -qF 'failed duplicate-output' "$d/outcomes.txt" || {
    echo "each colliding reviewer must be recorded by name; got:" >&2
    cat "$d/outcomes.txt" >&2
    return 1
  }
}

# ---------------------------------------------------------------------------
# The runbook's literal calls are checked against the real functions.
#
# Cross-model review round 2 found that §2 passed a PATH to
# review_budget_check, which takes a byte count and refuses anything else —
# so the shared runbook's very first gate errored for every reviewer. No test
# existed because the runbook is markdown, and nothing had ever compared its
# fenced calls against the functions they name. These rows close that.
# ---------------------------------------------------------------------------

@test "the runbook never passes a path where review_budget_check wants bytes" {
  # The exact defect: `review_budget_check "$ROUND_DIR/payload.md" …`.
  grep -nE 'review_budget_check[[:space:]]+"?\$[A-Za-z_{]*(ROUND_DIR|ART|PAYLOAD)' "$RUNBOOK" && {
    echo "review_budget_check is being passed a path; it takes a BYTE COUNT:" >&2
    grep -nE 'review_budget_check' "$RUNBOOK" >&2
    return 1
  }
  # And it must be called with something byte-shaped at all.
  grep -qE 'review_budget_check[[:space:]]+"\$BYTES"' "$RUNBOOK" || {
    echo "the runbook does not pass a measured byte count to review_budget_check:" >&2
    grep -nE 'review_budget_check' "$RUNBOOK" >&2
    return 1
  }
}

@test "review_budget_check really does refuse a path, so the row above is not theoretical" {
  source "$(LIBSH)"
  printf 'payload\n' > "$TEST_DIR/payload.md"
  run review_budget_check "$TEST_DIR/payload.md" stdin
  [ "$status" -ne 0 ] || {
    echo "premise failed: review_budget_check accepted a path" >&2
    return 1
  }
  printf '%s\n' "$output" | grep -qF 'base-10 integer' || {
    echo "expected the integer diagnostic; got: $output" >&2
    return 1
  }
}

@test "the runbook composes one payload PER AGENT, never one shared file" {
  # A single shared payload.md defeats two separate contracts at once: the
  # per-agent digest the subagent attests (AC16) and the duplicate-output check
  # (AC17), which is meaningless when every reviewer was handed the same file.
  grep -nE '\$ROUND_DIR/payload\.md' "$RUNBOOK" && {
    echo "the runbook still dispatches one shared payload.md:" >&2
    grep -nE 'payload\.md' "$RUNBOOK" >&2
    return 1
  }
  grep -qF '$ROUND_DIR/$agent.payload' "$RUNBOOK" || {
    echo "the runbook does not name a per-agent payload artifact" >&2
    return 1
  }
  return 0
}

@test "the runbook's compose, dispatch and attest steps name the SAME artifact" {
  # They disagreed: §2 wrote payload.md, §3 dispatched payload.md, §6 validated
  # <agent>.payload — a path the runbook never created. A subagent could return
  # the right digest for the bytes it was given and still fail validation.
  local n_payload n_digest
  n_payload="$(grep -cE '(\$agent|<agent>)\.payload' "$RUNBOOK")"
  n_digest="$(grep -cE '(\$agent|<agent>)\.digests' "$RUNBOOK")"
  [ "$n_payload" -ge 3 ] || {
    echo "expected the per-agent payload named in compose, dispatch and attest; found $n_payload" >&2
    grep -nE 'payload' "$RUNBOOK" >&2
    return 1
  }
  [ "$n_digest" -ge 2 ] || {
    echo "expected a per-agent digest sidecar in compose and attest; found $n_digest" >&2
    grep -nE 'digests' "$RUNBOOK" >&2
    return 1
  }
}

@test "the runbook tells the caller to pass --label" {
  # Two of the five branches do not review a spec. Without --label an arch or
  # pm reviewer is told it holds a "Spec under review" and goes looking for
  # acceptance criteria a design or brief does not have.
  grep -qF -- '--label' "$RUNBOOK" || {
    echo "the runbook never mentions --label" >&2
    return 1
  }
}

# ---------------------------------------------------------------------------
# The same class, in commands/spec/review.md.
# ---------------------------------------------------------------------------

@test "spec:review never passes the transport where the dispatch mode belongs" {
  # `MODE="$(review_agent_field … input)"` then
  # `review_validate_reference_access … "$MODE"` conflates two different
  # things. The validator's third argument selects the subagent-only
  # payload_sha256 rule and the permission-denial token, so a subagent round
  # silently ran the pre-0054 contract.
  grep -nE 'MODE="\$\(review_agent_field[^)]*input' "$SPEC_CMD" && {
    echo "MODE is being read from the registry's input field:" >&2
    grep -nE 'MODE=' "$SPEC_CMD" >&2
    return 1
  }
  grep -qE 'MODE="\$\(review_agent_mode' "$SPEC_CMD" || {
    echo "spec:review does not read MODE from review_agent_mode:" >&2
    grep -nE 'MODE=' "$SPEC_CMD" >&2
    return 1
  }
  # And the transport is read separately, since the budget still needs it.
  grep -qE 'review_agent_transport' "$SPEC_CMD" || {
    echo "spec:review no longer reads the transport for the budget check" >&2
    return 1
  }
  return 0
}

@test "spec:review dispatches through the shared mode router" {
  # A direct review_dispatch_payload call hands a codex-plugin or subagent
  # entry an empty command and drops it with no named outcome — exactly the
  # "a bash path never silently drops one" rule (AC13).
  grep -qF 'review_dispatch_agent' "$SPEC_CMD" || {
    echo "spec:review does not call review_dispatch_agent" >&2
    return 1
  }
  grep -nE '^\s*review_dispatch_payload ' "$SPEC_CMD" && {
    echo "spec:review still dispatches directly, bypassing the mode router:" >&2
    grep -nE 'review_dispatch_payload' "$SPEC_CMD" >&2
    return 1
  }
  return 0
}

@test "spec:review uses the persistent round dir, not a trap-cleaned temp dir" {
  # A subagent is dispatched by the orchestrating session in a LATER tool call.
  # A temp dir cleaned by an EXIT trap is gone by then, so the reviewer finds
  # no payload — which makes spec:review structurally unable to run a subagent.
  grep -nE 'review_round_tmpdir|REVIEW_ROUND_TMPDIR' "$SPEC_CMD" && {
    echo "spec:review still uses the shell-scoped temp dir:" >&2
    grep -nE 'tmpdir|TMPDIR' "$SPEC_CMD" >&2
    return 1
  }
  grep -qF 'review_round_dir_create' "$SPEC_CMD" || {
    echo "spec:review does not create a persistent round dir" >&2
    return 1
  }
  return 0
}

@test "the scoped --diff round passes the prior review to the composer" {
  # Step 2b promises to attach the prior review as evidence; the composer call
  # dropped it, so a scoped reviewer got no previous findings and could not
  # tell whether a change resolved anything. A full-round recipe omits it
  # silently — there is no error, just a worse review.
  grep -qE 'prior-review\.md|\$\{PRIOR' "$SPEC_CMD" || {
    echo "the scoped branch does not pass the prior review inline:" >&2
    grep -nE 'review_compose_payload' -A4 "$SPEC_CMD" >&2
    return 1
  }
  # It must travel as --inline: a --reference hand-off sends only a path and a
  # heading index, and the prior review is not a reference-tier file.
  grep -qE -- '--inline[^|]*PRIOR' "$SPEC_CMD" || {
    echo "the prior review must ride as --inline evidence" >&2
    grep -nE -- '--inline' "$SPEC_CMD" >&2
    return 1
  }
}

@test "the runbook and the Go loader agree on the default subagent_type" {
  # Two readers of one registry must resolve an omitted subagent_type to the
  # SAME agent. The runbook said `reviewer`; the loader and the spec say
  # `speccraft:reviewer`. A bare `reviewer` is a different, probably
  # nonexistent agent, so the shell path would dispatch to nothing.
  local go_default
  go_default="$(grep -oE 'a\.SubagentType = "[^"]+"' "$PLUGIN_DIR/tools/internal/delegate/toml.go" \
    | head -1 | sed 's/.*"\(.*\)"/\1/')"
  [ -n "$go_default" ] || {
    echo "could not find the Go default; this row would pass vacuously" >&2
    return 1
  }
  grep -qF "$go_default" "$RUNBOOK" || {
    echo "the runbook does not name the Go loader's default ('$go_default'):" >&2
    grep -nF 'subagent_type' "$RUNBOOK" >&2
    return 1
  }
  # And it must not state the BARE name as the default.
  grep -qE 'defaulting to .?reviewer.?[^:]' "$RUNBOOK" && {
    echo "the runbook still gives a bare 'reviewer' as the default" >&2
    return 1
  }
  return 0
}

# ---------------------------------------------------------------------------
# AC21 — arch:review and pm:review write review.md only on a COMPLETE round
#
# The spec lane has had this gate since 0035: an inert round must leave the
# prior review.md byte-unchanged, because the NEXT --diff round classifies
# against it and a wiped review.md silently collapses the provenance chain.
# The design and brief lanes never got the gate — their step 4 is an
# unconditional Write — and `review_finalize_round` is spec-only: it promotes
# a review-snapshot.md and stamps a reviewed_sha256 that neither lane has.
#
# So two halves are tested here: the SHELL seam (finalize learns <kind>) and
# the MARKDOWN (the two commands actually gate on it).
# ---------------------------------------------------------------------------

# A doc dir shaped like a design/ or product/ entry: a prior review.md whose
# bytes we watch, and NO snapshot — if finalize promotes one anyway we see it
# appear rather than merely change.
make_doc_dir() {
  DOC_DIR="$TEST_DIR/design/0001-x"
  mkdir -p "$DOC_DIR"
  printf '# Design\n\nCURRENT-DESIGN-MARKER\n' > "$DOC_DIR/design.md"
  printf '# Review\n\nPRIOR-DESIGN-REVIEW-MARKER\n' > "$DOC_DIR/review.md"
}

# A real spec dir, for the regression floor: the 3-arg call must still do
# everything 0052 made it do.
make_spec_dir_local() {
  SPEC_DIR="$TEST_DIR/specs/0001-x"
  mkdir -p "$SPEC_DIR"
  printf '# Spec\n\nCURRENT-SPEC-MARKER\n' > "$SPEC_DIR/spec.md"
  printf '# Spec\n\nBASELINE-SNAPSHOT-MARKER\n' > "$SPEC_DIR/review-snapshot.md"
  printf '# Review\n\nPRIOR-REVIEW-MARKER\n' > "$SPEC_DIR/review.md"
}

# Logs every speccraft-state invocation, so "no snapshot, no fingerprint" is
# proven at the SEAM and not merely by the absence of a file a real binary
# might have declined to write for an unrelated reason.
install_state_seam() {
  mkdir -p "$TEST_DIR/stub"
  cat > "$TEST_DIR/stub/speccraft-state" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$SEAM_LOG"
case "$1" in
  find-root)       printf '%s\n' "$STUB_ROOT" ;;
  review-snapshot) printf '%s\n' "2222222222222222222222222222222222222222222222222222222222222222" ;;
esac
exit 0
STUB
  chmod +x "$TEST_DIR/stub/speccraft-state"
  export SEAM_LOG="$TEST_DIR/seam.log"
  export STUB_ROOT="$TEST_DIR"
  : > "$SEAM_LOG"
  export PATH="$TEST_DIR/stub:$PATH"
}

round_outcomes() {
  local f="$TEST_DIR/outcomes.txt"
  printf '%s\n' "$@" > "$f"
  printf '%s\n' "$f"
}

@test "a complete design round promotes no snapshot and stamps no fingerprint" {
  source "$PLUGIN_DIR/commands/spec/review.lib.sh"
  install_state_seam
  make_doc_dir
  run review_finalize_round "$DOC_DIR" 1 "$(round_outcomes 'codex approve' 'claude-p approve')" design
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qxF "responses_complete: true"
  printf '%s\n' "$output" | grep -qxF "approval_quorum_met: true"
  # The two spec-only durable writes never happen for a design.
  run grep -c 'review-snapshot' "$SEAM_LOG"
  [ "$output" = "0" ]
  run grep -c 'review-commit' "$SEAM_LOG"
  [ "$output" = "0" ]
  [ ! -e "$DOC_DIR/review-snapshot.md" ]
}

@test "a complete brief round promotes no snapshot and stamps no fingerprint" {
  source "$PLUGIN_DIR/commands/spec/review.lib.sh"
  install_state_seam
  DOC_DIR="$TEST_DIR/product/0001-x"
  mkdir -p "$DOC_DIR"
  printf '# Review\n\nPRIOR-BRIEF-REVIEW-MARKER\n' > "$DOC_DIR/review.md"
  run review_finalize_round "$DOC_DIR" 1 "$(round_outcomes 'codex approve')" brief
  [ "$status" -eq 0 ]
  run grep -c 'review-snapshot' "$SEAM_LOG"
  [ "$output" = "0" ]
  run grep -c 'review-commit' "$SEAM_LOG"
  [ "$output" = "0" ]
}

@test "a design round leaves an existing review.md byte-unchanged either way" {
  source "$PLUGIN_DIR/commands/spec/review.lib.sh"
  make_doc_dir   # REAL speccraft-state on PATH: a stray call would move bytes
  cp "$DOC_DIR/review.md" "$TEST_DIR/review.before"
  # Complete round…
  run review_finalize_round "$DOC_DIR" 1 "$(round_outcomes 'codex approve')" design
  [ "$status" -eq 0 ]
  cmp -s "$TEST_DIR/review.before" "$DOC_DIR/review.md"
  # …and inert round. Neither is finalize's to write: the synthesized verdict
  # is the command's Write, and finalize must not stamp anything into it.
  run review_finalize_round "$DOC_DIR" 1 "$(round_outcomes 'codex timeout')" design
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qxF "responses_complete: false"
  cmp -s "$TEST_DIR/review.before" "$DOC_DIR/review.md"
}

@test "a design round creates no review.md where none existed" {
  source "$PLUGIN_DIR/commands/spec/review.lib.sh"
  DOC_DIR="$TEST_DIR/design/0002-y"
  mkdir -p "$DOC_DIR"
  run review_finalize_round "$DOC_DIR" 1 "$(round_outcomes 'codex timeout')" design
  [ "$status" -eq 0 ]
  [ ! -e "$DOC_DIR/review.md" ]
  run review_finalize_round "$DOC_DIR" 1 "$(round_outcomes 'codex approve')" design
  [ "$status" -eq 0 ]
  [ ! -e "$DOC_DIR/review.md" ]
}

@test "the code kind writes nothing durable at all" {
  source "$PLUGIN_DIR/commands/spec/review.lib.sh"
  install_state_seam
  DOC_DIR="$TEST_DIR/code-round"
  mkdir -p "$DOC_DIR"
  run review_finalize_round "$DOC_DIR" 1 "$(round_outcomes 'codex approve')" code
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qxF "responses_complete: true"
  # A code round has no document and no lane, so no lifecycle state either.
  # Reporting `draft` would invite a caller to "promote" something.
  printf '%s\n' "$output" | grep -qxF "status: n/a"
  [ ! -e "$DOC_DIR/review.md" ]
  [ ! -e "$DOC_DIR/review-snapshot.md" ]
  run grep -c 'review-snapshot' "$SEAM_LOG"
  [ "$output" = "0" ]
  run grep -c 'review-commit' "$SEAM_LOG"
  [ "$output" = "0" ]
}

@test "the design and brief kinds never report status reviewed" {
  source "$PLUGIN_DIR/commands/spec/review.lib.sh"
  install_state_seam
  make_doc_dir
  # A design is promoted by /speccraft:arch:decide and a brief by
  # /speccraft:pm:prioritize — never by a review round. Reporting `reviewed`
  # here would name a state neither lane's machine has.
  run review_finalize_round "$DOC_DIR" 1 "$(round_outcomes 'codex approve')" design
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qxF "approval_quorum_met: true"
  # NOT `grep -qvF`: that succeeds whenever ANY line differs, which is every
  # multi-line report. The assertion has to be a positive match inverted by
  # hand, or it never bites.
  printf '%s\n' "$output" | grep -qxF "status: reviewed" && {
    echo "a design round reported the spec lane's reviewed state" >&2
    return 1
  }
  run review_finalize_round "$DOC_DIR" 1 "$(round_outcomes 'codex approve')" brief
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qxF "status: reviewed" && {
    echo "a brief round reported the spec lane's reviewed state" >&2
    return 1
  }
  return 0
}

@test "the three-argument call still behaves exactly as spec 0052 left it" {
  source "$PLUGIN_DIR/commands/spec/review.lib.sh"
  make_spec_dir_local
  # The regression floor: <kind> is OPTIONAL and defaults to spec, so every
  # existing caller keeps the snapshot promote and the fingerprint stamp.
  run review_finalize_round "$SPEC_DIR" 1 "$(round_outcomes 'codex changes-requested' 'claude-p changes-requested')"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qxF "status: draft"
  grep -qE '^reviewed_sha256: [0-9a-f]{64}$' "$SPEC_DIR/review.md"
  grep -qF 'CURRENT-SPEC-MARKER' "$SPEC_DIR/review-snapshot.md"
}

@test "an explicit spec kind is identical to omitting it" {
  source "$PLUGIN_DIR/commands/spec/review.lib.sh"
  make_spec_dir_local
  run review_finalize_round "$SPEC_DIR" 1 "$(round_outcomes 'codex approve')" spec
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qxF "status: reviewed"
  grep -qE '^reviewed_sha256: [0-9a-f]{64}$' "$SPEC_DIR/review.md"
  grep -qF 'CURRENT-SPEC-MARKER' "$SPEC_DIR/review-snapshot.md"
}

@test "an unknown kind is a named error, not a silent fall-through to spec" {
  source "$PLUGIN_DIR/commands/spec/review.lib.sh"
  make_spec_dir_local
  before="$(cat "$SPEC_DIR/review-snapshot.md")"
  run review_finalize_round "$SPEC_DIR" 1 "$(round_outcomes 'codex approve')" desgin
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | grep -qF "desgin"
  # A typo'd kind must not get the spec lane's durable writes by accident.
  [ "$(cat "$SPEC_DIR/review-snapshot.md")" = "$before" ]
}

@test "arch:review gates the review.md write on response completeness" {
  # Step 4 was an unconditional '**Write** design/$ACTIVE/review.md'. An inert
  # round would overwrite a real prior review with a synthesis of refusals.
  grep -qF 'review_responses_complete' "$ARCH_CMD" || {
    echo "arch:review has no completeness gate before its Write:" >&2
    grep -nF 'review.md' "$ARCH_CMD" >&2
    return 1
  }
  grep -qE 'review_finalize_round[^\n]*design' "$ARCH_CMD" || {
    echo "arch:review does not finalize with KIND=design:" >&2
    grep -nF 'review_finalize_round' "$ARCH_CMD" >&2
    return 1
  }
  grep -qF 'byte-unchanged' "$ARCH_CMD" || {
    echo "arch:review never states that an inert round leaves review.md alone" >&2
    return 1
  }
}

@test "pm:review gates the review.md write on response completeness" {
  grep -qF 'review_responses_complete' "$PM_CMD" || {
    echo "pm:review has no completeness gate before its Write:" >&2
    grep -nF 'review.md' "$PM_CMD" >&2
    return 1
  }
  grep -qE 'review_finalize_round[^\n]*brief' "$PM_CMD" || {
    echo "pm:review does not finalize with KIND=brief:" >&2
    grep -nF 'review_finalize_round' "$PM_CMD" >&2
    return 1
  }
  grep -qF 'byte-unchanged' "$PM_CMD" || {
    echo "pm:review never states that an inert round leaves review.md alone" >&2
    return 1
  }
}

# The exact pre-gate sentence as it actually shipped, backticks included. An
# earlier draft of this pattern omitted them and matched nothing — the guard
# passed while the line it guards against was still in the tree.
UNGATED_WRITE_RE='^4\. \*\*Write\*\* `?(design|product)/\$ACTIVE/review\.md`? with the synthesized verdict\.$'

@test "neither arch:review nor pm:review still carries the ungated Write" {
  local cmd
  for cmd in "$ARCH_CMD" "$PM_CMD"; do
    grep -qE "$UNGATED_WRITE_RE" "$cmd" && {
      echo "$cmd still writes review.md unconditionally:" >&2
      grep -nE "$UNGATED_WRITE_RE" "$cmd" >&2
      return 1
    }
  done
  return 0
}

@test "the ungated-Write guard bites on the sentence it is meant to catch" {
  # Prove the row above is not vacuous: reproduce the historical line VERBATIM
  # and require the pattern to match it. A typo in that regex, or a missing
  # backtick, would otherwise make the guard pass forever.
  cat > "$TEST_DIR/old-step4.txt" <<'OLD'
4. **Write** `design/$ACTIVE/review.md` with the synthesized verdict.
4. **Write** `product/$ACTIVE/review.md` with the synthesized verdict.
OLD
  [ "$(grep -cE "$UNGATED_WRITE_RE" "$TEST_DIR/old-step4.txt")" = "2" ] || {
    echo "the guard pattern does not match the historical lines" >&2
    cat "$TEST_DIR/old-step4.txt" >&2
    return 1
  }
}

# Every variable the runbook's shell blocks READ must be assigned by one of
# those blocks, or be a declared caller/environment parameter. The runbook is
# executed by a model, so an undefined variable is not a shell error — it
# expands to empty and the step quietly does the wrong thing. That is how §7
# came to pass a `$ROUND_DIR/outcomes` path while every other step appended to
# an `$OUTCOMES` nothing had ever set.
RUNBOOK_EXTERNAL_VARS="AGENTS AUTHORS DOC_DIR QUORUM REVIEW_TIMEOUT_S CLAUDE_PLUGIN_ROOT"

# runbook_shell_blocks — the contents of every ```bash fence, concatenated.
runbook_shell_blocks() {
  awk '/^```bash$/ { inb = 1; next } /^```$/ { inb = 0 } inb' "$RUNBOOK"
}

@test "every variable the runbook's shell blocks read is assigned or declared" {
  local blocks var missing=""
  blocks="$(runbook_shell_blocks)"
  [ -n "$blocks" ] || {
    echo "no bash fences found — this row would pass vacuously" >&2
    return 1
  }
  for var in $(printf '%s\n' "$blocks" \
      | grep -oE '\$\{?[A-Z][A-Z0-9_]*' | sed 's/^[$]{*//' | sort -u); do
    # Declared as the caller's or the environment's?
    case " $RUNBOOK_EXTERNAL_VARS " in *" $var "*) continue ;; esac
    # Assigned by some shell block in this runbook?
    printf '%s\n' "$blocks" | grep -qE "^[[:space:]]*(local )?$var=" && continue
    missing="$missing $var"
  done
  [ -z "$missing" ] || {
    echo "runbook reads but never sets:$missing" >&2
    echo "add the assignment, or declare it in RUNBOOK_EXTERNAL_VARS and the" >&2
    echo "parameter table if it really is the caller's to supply" >&2
    return 1
  }
}

@test "the undefined-variable guard bites on a variable nothing sets" {
  # Prove the row above is not vacuous by running its logic over a fence that
  # reads a variable no block assigns.
  local blocks var missing=""
  blocks='FOO="$BAR"
echo "$NOWHERE_SET"'
  for var in $(printf '%s\n' "$blocks" \
      | grep -oE '\$\{?[A-Z][A-Z0-9_]*' | sed 's/^[$]{*//' | sort -u); do
    case " $RUNBOOK_EXTERNAL_VARS " in *" $var "*) continue ;; esac
    printf '%s\n' "$blocks" | grep -qE "^[[:space:]]*(local )?$var=" && continue
    missing="$missing $var"
  done
  # BAR and NOWHERE_SET are unset; FOO is assigned, so it must NOT be reported.
  case "$missing" in
    *BAR*)            : ;;
    *) echo "guard missed an unset variable; got '$missing'" >&2; return 1 ;;
  esac
  case "$missing" in
    *NOWHERE_SET*)    : ;;
    *) echo "guard missed NOWHERE_SET; got '$missing'" >&2; return 1 ;;
  esac
  case "$missing" in
    *FOO*) echo "guard wrongly reported an ASSIGNED variable" >&2; return 1 ;;
  esac
  return 0
}

@test "the runbook declares each caller-supplied variable in its parameter table" {
  # RUNBOOK_EXTERNAL_VARS is an escape hatch; it must not become a place to
  # hide a variable from the reader of the runbook.
  local var
  for var in AGENTS AUTHORS DOC_DIR QUORUM; do
    grep -qF "\`$var\`" "$RUNBOOK" || {
      echo "$var is exempted by the guard but never documented as the caller's" >&2
      return 1
    }
  done
}

@test "the runbook creates the outcomes file before the first dispatch" {
  # An absent outcomes file and a round nobody answered are indistinguishable
  # to review_responses_complete, so it must exist and be empty up front.
  local init_line dispatch_line
  init_line="$(grep -nE '^: > "\$OUTCOMES"$' "$RUNBOOK" | head -1 | cut -d: -f1)"
  dispatch_line="$(grep -nF '>> "$OUTCOMES"' "$RUNBOOK" | head -1 | cut -d: -f1)"
  [ -n "$init_line" ] || {
    echo "the runbook never truncates \$OUTCOMES to create it" >&2
    return 1
  }
  [ -n "$dispatch_line" ] || {
    echo "no append to \$OUTCOMES found; this row would pass vacuously" >&2
    return 1
  }
  [ "$init_line" -lt "$dispatch_line" ] || {
    echo "the outcomes file is created at line $init_line, after the first" >&2
    echo "append at line $dispatch_line" >&2
    return 1
  }
}

@test "the runbook names the kind-aware finalize call" {
  # §7 said only 'Then finalize for this KIND' with no call — the one step the
  # round cannot infer. Four commands reading that text would each invent one.
  grep -qE 'review_finalize_round[^\n]*KIND' "$RUNBOOK" || {
    echo "the runbook does not show a kind-aware finalize call:" >&2
    grep -nF 'finalize' "$RUNBOOK" >&2
    return 1
  }
  # And it must state that the verdict document is written only on a complete
  # round, since that is the gate arch/pm were missing.
  grep -qF 'byte-unchanged' "$RUNBOOK" || {
    echo "the runbook does not state the inert-round guarantee" >&2
    return 1
  }
}
