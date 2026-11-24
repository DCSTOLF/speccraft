#!/usr/bin/env bats
# Spec 0054 AC23b — `codex-plugin` and `subagent` are REVIEW-ONLY modes, and
# the two delegation consumers must refuse them.
#
# `/speccraft:spec:delegate` and the `aux-delegator` subagent hand a task to an
# external CLI and integrate the result. Neither can do that through either new
# mode: `codex-plugin` reaches a companion that runs its own agent loop and
# reports touched files, and `subagent` can only be started by the orchestrating
# session. A consumer that tried would not fail cleanly — `aux-delegator`
# composes a prompt and shells out, so a `subagent` entry with no `cmd` would
# produce an empty command line and a confident-looking empty result.
#
# So the refusal is a PRECONDITION, before any dispatch, and both consumers use
# ONE message — not two copies that drift.
#
# `cli` and `acp` delegation must be completely unchanged: spec 0052's and the
# earlier delegate tests pass unedited, and two rows here assert the two
# supported modes still pass the gate.

setup() {
  PLUGIN_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  LIB="$PLUGIN_DIR/commands/spec/review.lib.sh"
  DELEGATE="$PLUGIN_DIR/commands/spec/delegate.md"
  AUX="$PLUGIN_DIR/agents/aux-delegator.md"
  export PATH="$PLUGIN_DIR/bin:$PATH"
  TEST_DIR="$(mktemp -d)"
  TOML="$TEST_DIR/agents.toml"
}

teardown() {
  rm -rf "$TEST_DIR"
}

entry() {
  local name="$1" mode="$2" cmd="${3:-}"
  {
    printf '[[agents]]\n'
    printf 'name = "%s"\n' "$name"
    printf 'mode = "%s"\n' "$mode"
    printf 'enabled = true\n'
    printf 'reference_read = true\n'
    [ -z "$cmd" ] || printf 'cmd = %s\n' "$cmd"
    printf '\n'
  } >> "$TOML"
}

# ---------------------------------------------------------------------------
# The one message
# ---------------------------------------------------------------------------

@test "the refusal names the mode and the token unsupported-mode" {
  source "$LIB"
  run review_refuse_review_only_mode codex-plugin
  [ "$status" -ne 0 ]
  printf '%s\n' "$output" | grep -qF 'unsupported-mode'
  printf '%s\n' "$output" | grep -qF 'codex-plugin'
  run review_refuse_review_only_mode subagent
  [ "$status" -ne 0 ]
  printf '%s\n' "$output" | grep -qF 'subagent'
}

@test "the refusal names all four review commands" {
  source "$LIB"
  # Naming them is the actionable part: the operator configured this entry for
  # a reason, and the message has to say where it DOES work rather than only
  # where it does not.
  run review_refuse_review_only_mode subagent
  local cmd
  for cmd in /speccraft:spec:review /speccraft:arch:review /speccraft:pm:review \
             /speccraft:spec:review-code; do
    printf '%s\n' "$output" | grep -qF "$cmd" || {
      echo "the refusal does not name $cmd: $output" >&2
      return 1
    }
  done
}

@test "the refusal names cli and acp as what delegation supports" {
  source "$LIB"
  run review_refuse_review_only_mode codex-plugin
  printf '%s\n' "$output" | grep -qF 'cli'
  printf '%s\n' "$output" | grep -qF 'acp'
}

@test "the refusal promises no future support" {
  source "$LIB"
  # A guardrail, not a roadmap. "not yet", "for now" and "in a future release"
  # all invite a reader to treat the restriction as a scheduling accident, and
  # the restriction is structural: a subagent cannot be started from a shell.
  run review_refuse_review_only_mode subagent
  printf '%s\n' "$output" | grep -qiE 'not yet|for now|future|planned|coming|will be supported|eventually' && {
    echo "the refusal reads as a roadmap: $output" >&2
    return 1
  }
  return 0
}

@test "the roadmap guard bites on a message that promises support" {
  # Premise for the row above: prove the pattern matches the phrasing it
  # forbids, or the negative is vacuous.
  local bad
  for bad in 'not yet supported' 'for now, use review' 'planned for a future release' \
             'will be supported soon'; do
    printf '%s\n' "$bad" | grep -qiE 'not yet|for now|future|planned|coming|will be supported|eventually' || {
      echo "the roadmap guard missed: $bad" >&2
      return 1
    }
  done
  # …and does not fire on the legitimate message's vocabulary.
  printf '%s\n' 'unsupported-mode: subagent is a review-only mode; delegation supports cli and acp' \
    | grep -qiE 'not yet|for now|future|planned|coming|will be supported|eventually' && {
    echo "the roadmap guard false-positived on the real message" >&2
    return 1
  }
  return 0
}

@test "a delegatable mode passed to the refusal is a programming error" {
  source "$LIB"
  # Calling it with `cli` means the caller's gate is inverted. Exit 2 naming
  # the mode, distinct from the exit-1 refusal, so the two cannot be confused.
  run review_refuse_review_only_mode cli
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | grep -qF 'cli'
}

# ---------------------------------------------------------------------------
# The precondition gate
# ---------------------------------------------------------------------------

@test "review_require_delegatable_mode refuses a codex-plugin entry" {
  source "$LIB"
  : > "$TOML"
  entry cxp codex-plugin
  run review_require_delegatable_mode "$TOML" cxp
  [ "$status" -ne 0 ]
  printf '%s\n' "$output" | grep -qF 'unsupported-mode'
  printf '%s\n' "$output" | grep -qF 'codex-plugin'
}

@test "review_require_delegatable_mode refuses a subagent entry" {
  source "$LIB"
  : > "$TOML"
  entry sub subagent
  run review_require_delegatable_mode "$TOML" sub
  [ "$status" -ne 0 ]
  printf '%s\n' "$output" | grep -qF 'unsupported-mode'
}

@test "a cli entry passes the gate unchanged" {
  source "$LIB"
  : > "$TOML"
  entry codex cli '["codex", "exec"]'
  run review_require_delegatable_mode "$TOML" codex
  [ "$status" -eq 0 ]
  # Silent on success: the gate is a precondition, not a step that reports.
  [ -z "$output" ] || { echo "the gate printed on success: $output" >&2; return 1; }
}

@test "an acp entry passes the gate unchanged" {
  source "$LIB"
  : > "$TOML"
  {
    printf '[[agents]]\n'
    printf 'name = "cxacp"\n'
    printf 'mode = "acp"\n'
    printf 'enabled = true\n'
    printf 'reference_read = true\n'
    printf 'acp_agent = "codex"\n\n'
  } >> "$TOML"
  run review_require_delegatable_mode "$TOML" cxacp
  [ "$status" -eq 0 ]
}

@test "an entry with no mode defaults to cli and passes" {
  source "$LIB"
  # The registry's default. A gate that treated an absent mode as unknown would
  # break every pre-0054 agents.toml on the first delegation.
  : > "$TOML"
  {
    printf '[[agents]]\n'
    printf 'name = "legacy"\n'
    printf 'enabled = true\n'
    printf 'reference_read = true\n'
    printf 'cmd = ["codex", "exec"]\n\n'
  } >> "$TOML"
  run review_require_delegatable_mode "$TOML" legacy
  [ "$status" -eq 0 ]
}

@test "an unknown agent is a named error, not a silent pass" {
  source "$LIB"
  : > "$TOML"
  entry codex cli '["codex", "exec"]'
  run review_require_delegatable_mode "$TOML" nosuch
  [ "$status" -ne 0 ]
  printf '%s\n' "$output" | grep -qF 'nosuch'
}

@test "the gate launches nothing" {
  source "$LIB"
  # It is the PRECONDITION: it runs before any dispatch, so it must not itself
  # reach a CLI. A stub of each delegatable binary records any execution.
  mkdir -p "$TEST_DIR/trap"
  local cmd
  for cmd in codex claude opencode acpx; do
    printf '#!/usr/bin/env bash\nprintf %%s "$0" >> "%s/launched"\n' "$TEST_DIR" \
      > "$TEST_DIR/trap/$cmd"
    chmod +x "$TEST_DIR/trap/$cmd"
  done
  PATH="$TEST_DIR/trap:$PATH"
  : > "$TOML"
  entry cxp codex-plugin
  run review_require_delegatable_mode "$TOML" cxp
  [ "$status" -ne 0 ]
  [ ! -e "$TEST_DIR/launched" ] || {
    echo "the gate launched: $(cat "$TEST_DIR/launched")" >&2
    return 1
  }
  # And the same on the PASSING path, where a dispatch would be plausible.
  : > "$TOML"
  entry codex cli '["codex", "exec"]'
  run review_require_delegatable_mode "$TOML" codex
  [ "$status" -eq 0 ]
  [ ! -e "$TEST_DIR/launched" ] || {
    echo "the gate launched on the passing path: $(cat "$TEST_DIR/launched")" >&2
    return 1
  }
}

@test "the launch trap really records an execution" {
  # Premise for the row above.
  mkdir -p "$TEST_DIR/trap"
  printf '#!/usr/bin/env bash\nprintf %%s "$0" >> "%s/launched"\n' "$TEST_DIR" \
    > "$TEST_DIR/trap/codex"
  chmod +x "$TEST_DIR/trap/codex"
  PATH="$TEST_DIR/trap:$PATH" codex
  [ -e "$TEST_DIR/launched" ] || {
    echo "the trap stub did not record its own execution" >&2
    return 1
  }
}

# ---------------------------------------------------------------------------
# Both consumers, and the one text
# ---------------------------------------------------------------------------

@test "spec:delegate gates on the mode before dispatching" {
  grep -qF 'review_require_delegatable_mode' "$DELEGATE" || {
    echo "spec:delegate has no mode gate:" >&2
    grep -nE '^[0-9]+\.' "$DELEGATE" >&2
    return 1
  }
}

@test "aux-delegator gates on the mode before dispatching" {
  grep -qF 'review_require_delegatable_mode' "$AUX" || {
    echo "aux-delegator has no mode gate:" >&2
    grep -nE '^[0-9]+\.' "$AUX" >&2
    return 1
  }
}

@test "the gate is the FIRST step in each consumer, before prompt composition" {
  # A refusal after the prompt is composed still costs the compose, and in
  # aux-delegator's case the compose is where a cmd-less entry produces an
  # empty command line.
  local f gate first_dispatch
  for f in "$DELEGATE" "$AUX"; do
    gate="$(grep -nF 'review_require_delegatable_mode' "$f" | head -1 | cut -d: -f1)"
    first_dispatch="$(grep -nE 'review_dispatch_payload|acpx |Compose the prompt|Build the shell command|Invoke the .aux-delegator. subagent' "$f" \
      | head -1 | cut -d: -f1)"
    [ -n "$gate" ] || { echo "$f has no gate" >&2; return 1; }
    [ -n "$first_dispatch" ] || {
      echo "$f: could not locate a dispatch step; row would be vacuous" >&2
      return 1
    }
    [ "$gate" -lt "$first_dispatch" ] || {
      echo "$f gates at line $gate, after the dispatch step at $first_dispatch" >&2
      return 1
    }
  done
}

@test "both consumers document the restriction in prose, not only in a call" {
  local f
  for f in "$DELEGATE" "$AUX"; do
    grep -qiE 'review-only' "$f" || {
      echo "$f never explains that the two modes are review-only" >&2
      return 1
    }
  done
}

@test "aux-delegator distinguishes the registry's mode from its own task mode" {
  # aux-delegator takes a `mode` parameter of review|implement|analyze while
  # the registry's `mode` is cli|acp|codex-plugin|subagent. Two different
  # things under one word is exactly the conflation that produced a live defect
  # in spec:review earlier in this spec (transport passed as dispatch mode).
  # BOTH senses must be named, not just one. A single mention of "dispatch
  # mode" is satisfied even by a file that still calls its own parameter
  # `mode`, which is the ambiguity being removed.
  grep -qiE 'dispatch mode' "$AUX" || {
    echo "aux-delegator never names the registry's sense as the dispatch mode:" >&2
    grep -nF 'mode' "$AUX" | head >&2
    return 1
  }
  grep -qF 'task_mode' "$AUX" || {
    echo "aux-delegator's own parameter is still the bare 'mode':" >&2
    grep -nE '^- `' "$AUX" >&2
    return 1
  }
  # And the bare `mode` must no longer be the name of its own input.
  grep -qE '^- `mode`:' "$AUX" && {
    echo "aux-delegator still declares an input literally named 'mode'" >&2
    return 1
  }
  return 0
}

@test "neither consumer carries its own copy of the refusal text" {
  # ONE text, in the lib. Two copies drift, and the second copy is the one
  # nobody updates.
  #
  # The premise comes first: without it this row passes just as happily when
  # the message exists NOWHERE, which is the state before the helper is
  # written.
  grep -qF 'unsupported-mode:' "$LIB" || {
    echo "the lib holds no refusal message, so this row would be vacuous" >&2
    return 1
  }
  local f
  for f in "$DELEGATE" "$AUX"; do
    grep -qF 'unsupported-mode:' "$f" && {
      echo "$f inlines the refusal message instead of calling the helper:" >&2
      grep -nF 'unsupported-mode:' "$f" >&2
      return 1
    }
  done
  return 0
}
