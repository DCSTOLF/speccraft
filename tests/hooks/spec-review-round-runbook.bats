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
