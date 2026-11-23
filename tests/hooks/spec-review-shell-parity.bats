#!/usr/bin/env bats
# Spec 0054 AC27 — the review libs must BEHAVE the same in bash and in zsh.
#
# This file exists because of a whole class of defects that shipped past both a
# full bats suite and two cross-model review rounds.
#
# `tests/hooks/lib-zsh-safety.bats` already proves every lib SOURCES cleanly
# under zsh. That is necessary and not sufficient: sourcing only runs the
# top-level assignments and function definitions. The function BODIES were
# never executed under zsh by anything, and the bodies are where the two
# shells disagree.
#
# The disagreement that bit, in one line:
#
#     zsh does not word-split an unquoted parameter expansion.
#
# So `for m in $REVIEW_VALID_MODES` iterates ONCE under zsh with the whole
# string "cli acp codex-plugin subagent" as a single element, and the mode
# check rejects every mode it is supposed to accept — while printing a
# diagnostic that lists the mode as valid. And `$digest "$p"`, where `$digest`
# holds "shasum -a 256", tries to execute a command whose name contains two
# spaces.
#
# These are not edge cases. The `.md` command bodies `source` these libs into
# whatever shell the agent's Bash tool runs, which on macOS is zsh. Every
# affected function is on the main path of a review round.
#
# zsh is REQUIRED here, never silent-skipped — the same rule spec 0029 and
# spec 0030 set for their zsh legs, and ci.yml installs it. A silent skip would
# turn this whole file into the coverage it is meant to replace.

setup() {
  PLUGIN_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  LIB="$PLUGIN_DIR/commands/spec/review.lib.sh"
  export PATH="$PLUGIN_DIR/bin:$PATH"
  TEST_DIR="$(mktemp -d)"
  REPO="$TEST_DIR/repo"
  mkdir -p "$REPO/.speccraft"
  cd "$REPO"
  git init -q .
  git config user.email t@example.com
  git config user.name  Test
  printf 'guardrails\n'  > .speccraft/guardrails.md
  printf 'index\n'       > .speccraft/index.md
  printf '# arch\n'      > .speccraft/architecture.md
  printf '# conventions\n' > .speccraft/conventions.md
  git add -A
  git commit -q -m init
}

teardown() {
  cd /
  rm -rf "$TEST_DIR"
}

require_zsh() {
  command -v zsh >/dev/null 2>&1 || {
    echo "zsh is REQUIRED for this file and must never be silent-skipped (ci.yml installs it)." >&2
    return 1
  }
}

# in_shell <shell> <script> — run <script> with the lib sourced, in <shell>,
# from the fixture repo. Written to a file rather than passed with -c so the
# quoting of the script under test is not itself part of the experiment.
in_shell() {
  local sh="$1" script="$2" f="$TEST_DIR/probe.$$.sh"
  {
    printf '. %s\n' "$LIB"
    printf '%s\n' "$script"
  } > "$f"
  ( cd "$REPO" && "$sh" "$f" 2>&1 )
}

# parity <description> <script> — the core assertion: both shells produce the
# same stdout for the same script. Prints both sides on failure, because
# "they differ" without the two values is not diagnosable.
parity() {
  local what="$1" script="$2" a b
  require_zsh || return 1
  a="$(in_shell bash "$script")"
  b="$(in_shell zsh  "$script")"
  [ "$a" = "$b" ] || {
    echo "SHELL PARITY FAILURE: $what" >&2
    echo "  bash: [$a]" >&2
    echo "  zsh:  [$b]" >&2
    return 1
  }
}

# ---------------------------------------------------------------------------
# The parity harness must itself be able to fail. A harness that cannot
# distinguish the shells would pass this whole file vacuously, which is exactly
# the failure mode the file was written to end.
# ---------------------------------------------------------------------------

@test "the parity harness detects a genuine bash/zsh difference" {
  require_zsh
  # ZSH_VERSION is set in zsh and unset in bash, so this script MUST differ.
  run parity 'a deliberately shell-dependent probe' 'echo "${ZSH_VERSION:-no-zsh}"'
  [ "$status" -ne 0 ] || {
    echo "the harness reported parity on a script that cannot be equal" >&2
    return 1
  }
}

@test "the parity harness agrees on a shell-independent probe" {
  parity 'a shell-independent probe' 'echo stable'
}

# ---------------------------------------------------------------------------
# The word-splitting class, function by function.
# ---------------------------------------------------------------------------

@test "review_digest agrees across shells" {
  # `$digest "$p"` with $digest = "shasum -a 256". Under zsh this executes a
  # command literally named 'shasum -a 256'. Every reference digest, every
  # payload digest and the whole tree snapshot run through here.
  parity 'review_digest' 'review_digest .speccraft/index.md || echo "FAILED rc=$?"'
}

@test "review_context_tier agrees across shells for every table entry" {
  # `for entry in $REVIEW_INLINE_SET` / `$REVIEW_REFERENCE_SET`. Under zsh no
  # path is in any tier, so the composer refuses every file it is given.
  parity 'review_context_tier over the whole table' '
for p in .speccraft/guardrails.md .speccraft/index.md .speccraft/architecture.md .speccraft/conventions.md; do
  printf "%s=%s\n" "$p" "$(review_context_tier "$p" 2>&1 | head -1)"
done'
}

@test "review_agent_mode accepts every valid mode in both shells" {
  # `for m in $REVIEW_VALID_MODES`. The diagnostic lists the mode as valid
  # while rejecting it, which is the worst kind of error message.
  cat > .speccraft/agents.toml <<'EOF'
[[agents]]
name = "a_cli"
mode = "cli"
cmd = ["cat"]
input = "stdin"

[[agents]]
name = "a_acp"
mode = "acp"
acp_agent = "codex"

[[agents]]
name = "a_plugin"
mode = "codex-plugin"
model = "gpt-5-codex"

[[agents]]
name = "a_sub"
mode = "subagent"
model = "opus"
EOF
  parity 'review_agent_mode over all four modes' '
for a in a_cli a_acp a_plugin a_sub; do
  printf "%s=%s\n" "$a" "$(review_agent_mode .speccraft/agents.toml "$a" 2>&1 | head -1)"
done'
}

@test "_review_outcome_kind agrees across shells for every outcome token" {
  # `for entry in $REVIEW_VERDICTS` / `$REVIEW_NON_VERDICTS`. This decides
  # whether a round is complete and whether quorum was met, so a zsh
  # misclassification silently changes a round's verdict.
  parity '_review_outcome_kind over verdicts and non-verdicts' '
for o in approve approve-with-comments changes-requested reject refused timeout failed attestation-failed nonsense; do
  printf "%s=%s\n" "$o" "$(_review_outcome_kind "$o" 2>&1 | head -1)"
done'
}

@test "_review_tree_is_volatile agrees across shells" {
  # `for v in $REVIEW_TREE_VOLATILE`. Under zsh nothing is volatile, so every
  # round reports the orchestrator's own bookkeeping writes as a reviewer
  # writing out of bounds.
  parity '_review_tree_is_volatile over the closed set' '
for p in .speccraft/state.json .claude/settings.local.json .speccraft/.review-rounds/x tests/e2e/.logs/a README.md; do
  if _review_tree_is_volatile "$p"; then printf "%s=volatile\n" "$p"; else printf "%s=counted\n" "$p"; fi
done'
}

@test "review_tree_snapshot agrees across shells" {
  parity 'review_tree_snapshot' 'review_tree_snapshot . 2>&1 | head -5'
}

@test "the composer agrees across shells" {
  # The end-to-end consequence: if tiering disagrees, no payload composes at
  # all under zsh, and the round dies before any reviewer is reached.
  printf '# spec\n' > "$TEST_DIR/spec.md"
  parity 'review_compose_payload byte count' '
out="$(review_compose_payload '"$PLUGIN_DIR"'/templates/prompts/review.md '"$TEST_DIR"'/spec.md \
  --inline .speccraft/guardrails.md .speccraft/index.md \
  --reference .speccraft/architecture.md .speccraft/conventions.md \
  --digest-out '"$TEST_DIR"'/d.txt 2>&1)" || echo "COMPOSE FAILED"
printf "%s\n" "${#out}"'
}

# ---------------------------------------------------------------------------
# Round-directory identity. Not a word-splitting bug, but the same root cause:
# a bash assumption that zsh does not share.
# ---------------------------------------------------------------------------

@test "two rounds created from one shell get distinct directories, in both shells" {
  require_zsh
  # zsh gives a command-substitution subshell the SAME $RANDOM as its parent
  # unless the parent touches RANDOM in between, and every real caller takes
  # the path by `$(review_round_dir_create ...)`. Two rounds then share one
  # directory, and the first round's cleanup deletes the second's payload.
  local sh out a b
  for sh in bash zsh; do
    out="$(in_shell "$sh" '
a="$(review_round_dir_create spec 0054 600)"
b="$(review_round_dir_create spec 0054 600)"
[ "$a" = "$b" ] && echo COLLISION || echo distinct')"
    printf '%s: %s\n' "$sh" "$out" >&2
    [ "$out" = "distinct" ] || {
      echo "two rounds share one directory under $sh: $out" >&2
      return 1
    }
  done
}

# ---------------------------------------------------------------------------
# Dispatch must reach the command for a real, array-form registry.
# ---------------------------------------------------------------------------

@test "review_dispatch_agent reaches an array-form cli command in both shells" {
  require_zsh
  # Every real registry writes `cmd = ["codex", "exec", ...]`; this repo's own
  # does. review_dispatch_agent read it with review_agent_field, which returns
  # the RAW TOML text, so the shell tried to execute the word `["codex",`.
  cat > .speccraft/agents.toml <<'EOF'
[[agents]]
name = "arr"
mode = "cli"
cmd = ["cat"]
input = "stdin"
EOF
  printf 'PAYLOAD-MARKER\n' > art.txt
  local sh out
  for sh in bash zsh; do
    out="$(in_shell "$sh" 'review_dispatch_agent .speccraft/agents.toml arr art.txt || echo "DISPATCH FAILED rc=$?"')"
    printf '%s: %s\n' "$sh" "$out" >&2
    printf '%s\n' "$out" | grep -qF 'PAYLOAD-MARKER' || {
      echo "array-form cmd did not reach the command under $sh: $out" >&2
      return 1
    }
  done
}

@test "review_dispatch_agent passes a multi-word array cmd as separate arguments" {
  require_zsh
  # A multi-element array must arrive as separate argv entries. A fix that
  # merely re-joined the array into one command string would pass the
  # single-word row above and still break every real registry, all of which are
  # multi-word: `["codex", "exec", "--sandbox", "workspace-write"]`.
  cat > .speccraft/agents.toml <<'EOF'
[[agents]]
name = "multi"
mode = "cli"
cmd = ["tr", "a-z", "A-Z"]
input = "stdin"
EOF
  printf 'row\n' > art.txt
  local sh out
  for sh in bash zsh; do
    out="$(in_shell "$sh" 'review_dispatch_agent .speccraft/agents.toml multi art.txt || echo "DISPATCH FAILED rc=$?"')"
    printf '%s: %s\n' "$sh" "$out" >&2
    printf '%s\n' "$out" | grep -qF 'ROW' || {
      echo "a multi-word array cmd was not passed as separate arguments under $sh: $out" >&2
      return 1
    }
  done
}

@test "an argv element containing a space is a named refusal, not silently split" {
  require_zsh
  # The stated limitation of the frozen `review_dispatch_payload <cmd> <mode>
  # <artifact>` signature: a space-joined string cannot carry an argv element
  # that itself contains a space. Refusing by name is the only honest option —
  # splitting it would dispatch a command line nobody wrote and then attribute
  # the resulting failure to the reviewer.
  cat > .speccraft/agents.toml <<'EOF'
[[agents]]
name = "spacey"
mode = "cli"
cmd = ["awk", "{ print }"]
input = "stdin"
EOF
  printf 'row\n' > art.txt
  local sh out
  for sh in bash zsh; do
    # `|| echo`, not `; echo`: review.lib.sh turns on errexit in the shell that
    # sources it, so a bare `;` would abort the probe before it could report.
    out="$(in_shell "$sh" 'review_dispatch_agent .speccraft/agents.toml spacey art.txt || echo "rc=$?"')"
    printf '%s: %s\n' "$sh" "$out" >&2
    printf '%s\n' "$out" | grep -qF 'containing a space' || {
      echo "an embedded-space argv element must be refused BY NAME under $sh: $out" >&2
      return 1
    }
    printf '%s\n' "$out" | grep -qF 'rc=2' || {
      echo "the refusal must be non-zero under $sh: $out" >&2
      return 1
    }
  done
}

@test "review_agent_argv emits one argv word per line, losslessly" {
  cat > .speccraft/agents.toml <<'EOF'
[[agents]]
name = "spacey"
mode = "cli"
cmd = ["awk", "{ print }"]
input = "stdin"
EOF
  source "$LIB"
  run review_agent_argv .speccraft/agents.toml spacey
  [ "$status" -eq 0 ]
  # Two elements, and the second keeps its interior space — which is exactly
  # the information review_agent_cmd's space-joined form destroys, and the
  # reason the refusal above can be made at all.
  [ "$(printf '%s\n' "$output" | grep -c .)" -eq 2 ] || {
    echo "expected 2 argv words; got: $output" >&2
    return 1
  }
  printf '%s\n' "$output" | grep -qxF '{ print }' || {
    echo "the embedded space was not preserved; got: $output" >&2
    return 1
  }
}

# ---------------------------------------------------------------------------
# A sourced lib must not mutate the caller's shell state.
# ---------------------------------------------------------------------------

@test "review_with_deadline leaves the caller's fd 9 open" {
  # conventions.md: 'A sourced helper must not clobber the caller's EXIT trap',
  # generalized. review_with_deadline dups stdin to fd 9 and then closes fd 9
  # in the CALLER, because the lib is sourced. A caller holding the standard
  # `exec 9>lock; flock 9` advisory lock loses it silently, and two rounds then
  # enter a section that was meant to be exclusive.
  local sh out
  for sh in bash zsh; do
    command -v "$sh" >/dev/null 2>&1 || { echo "$sh required" >&2; return 1; }
    out="$(in_shell "$sh" '
exec 9>'"$TEST_DIR"'/lock
review_with_deadline 5 true >/dev/null 2>&1
if printf "x" >&9 2>/dev/null; then echo "fd9-open"; else echo "fd9-CLOSED"; fi')"
    printf '%s: %s\n' "$sh" "$out" >&2
    [ "$out" = "fd9-open" ] || {
      echo "review_with_deadline closed the caller's fd 9 under $sh" >&2
      return 1
    }
  done
}

# ---------------------------------------------------------------------------
# The static guard. The rows above pin the sites that bit; this one keeps the
# CLASS from coming back in code written after this spec closes.
# ---------------------------------------------------------------------------

@test "no review lib iterates an unquoted scalar with for" {
  # `for x in $LIST` is the shape. It reads as portable and is not: bash splits
  # the expansion, zsh does not. Membership belongs in a padded `case`, which
  # behaves identically in both shells.
  local hits
  hits="$(grep -nE '^[[:space:]]*for[[:space:]]+[A-Za-z_][A-Za-z_0-9]*[[:space:]]+in[[:space:]]+\$[A-Za-z_][A-Za-z_0-9]*[[:space:]]*;?[[:space:]]*(do)?[[:space:]]*$' \
    "$PLUGIN_DIR"/commands/spec/review*.lib.sh 2>/dev/null || true)"
  [ -z "$hits" ] || {
    echo "unquoted scalar iteration (splits in bash, not in zsh):" >&2
    printf '%s\n' "$hits" >&2
    echo "Use a padded case membership test, or emit one item per line." >&2
    return 1
  }
  # Premise check: the pattern must actually match the shape it forbids, or
  # this assertion is the vacuous negative the spec argues against.
  printf 'for m in $LIST; do\n  :\ndone\n' > "$TEST_DIR/canary.lib.sh"
  grep -qE '^[[:space:]]*for[[:space:]]+[A-Za-z_][A-Za-z_0-9]*[[:space:]]+in[[:space:]]+\$[A-Za-z_][A-Za-z_0-9]*[[:space:]]*;?[[:space:]]*(do)?[[:space:]]*$' \
    "$TEST_DIR/canary.lib.sh" || {
    echo "the guard pattern cannot match the shape it forbids" >&2
    return 1
  }
}

@test "no review lib executes an unquoted scalar as a command" {
  # `$cmd < "$art"` and `$digest "$p"`. Same root cause, worse symptom: the
  # whole string becomes one command NAME.
  local hits
  hits="$(grep -nE '^[[:space:]]*(\||&&|\|\||;)?[[:space:]]*\$[A-Za-z_][A-Za-z_0-9]*[[:space:]]+["<-]' \
    "$PLUGIN_DIR"/commands/spec/review*.lib.sh 2>/dev/null \
    | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' || true)"
  [ -z "$hits" ] || {
    echo "unquoted scalar executed as a command (one word under zsh):" >&2
    printf '%s\n' "$hits" >&2
    echo "Resolve to a wrapper function, or expand a real array." >&2
    return 1
  }
  printf '  $cmd < "$art"\n' > "$TEST_DIR/canary2.lib.sh"
  grep -qE '^[[:space:]]*(\||&&|\|\||;)?[[:space:]]*\$[A-Za-z_][A-Za-z_0-9]*[[:space:]]+["<-]' \
    "$TEST_DIR/canary2.lib.sh" || {
    echo "the guard pattern cannot match the shape it forbids" >&2
    return 1
  }
}
