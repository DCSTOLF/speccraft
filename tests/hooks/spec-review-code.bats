#!/usr/bin/env bats
# Spec 0054 ACs 22 / 22a — review-code freezes ONE diff, and says what it left out.
#
# Today `spec:review-code` tells each agent to collect "the diff" itself. Two
# reviewers dispatched a second apart can therefore review DIFFERENT bytes: the
# working tree is live while a round runs. A verdict about bytes nobody can
# reproduce is not reviewable, and the payload digest a `subagent` attests
# (AC16) would be meaningless if the thing hashed were recomputed per agent.
#
# So the diff is computed exactly once, into the round dir, and every payload
# composes from that one artifact.
#
# AC22a is the other half, and it is not cosmetic. `git diff HEAD` excludes
# untracked files. A reviewer handed a diff with no mention of that assumes it
# saw everything that changed and approves a branch whose brand-new file it
# never read. This spec criticizes `/codex:adversarial-review` for sweeping
# untracked files in, so the opposite choice has to be STATED where the
# reviewer and the operator each see it — in the payload prose and on stdout.

setup() {
  PLUGIN_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  LIB="$PLUGIN_DIR/commands/spec/review.lib.sh"
  CMD="$PLUGIN_DIR/commands/spec/review-code.md"
  TPL="$PLUGIN_DIR/templates/prompts/review-code.md"
  export PATH="$PLUGIN_DIR/bin:$PATH"
  TEST_DIR="$(mktemp -d)"
  REPO="$TEST_DIR/repo"
  mkdir -p "$REPO/.speccraft"
  cd "$REPO"
}

teardown() {
  cd /
  rm -rf "$TEST_DIR"
}

assert_named_failure() {
  local pattern="$1"
  [ "$status" -ne 0 ] || {
    echo "expected non-zero exit, got 0; output: $output" >&2
    return 1
  }
  printf '%s\n' "$output" | grep -qF -- "$pattern" || {
    echo "expected output to name '$pattern'; got: $output" >&2
    return 1
  }
}

# mkrepo — a repo with one commit, one STAGED edit that the working tree
# reverses, and one untracked file.
#
# The staged-then-reversed edit is the shape that separates the three plausible
# implementations. `git diff` alone reports nothing (worktree == index after the
# revert is staged? no — worktree == HEAD), `git diff --cached` reports the
# staged edit, and `git diff HEAD` reports the net change against the commit.
# The spec names `git diff HEAD`, so only that answer is correct.
mkrepo() {
  git init -q .
  git config user.email t@example.com
  git config user.name  Test
  printf 'original\n' > tracked.txt
  printf 'second\n'   > other.txt
  git add tracked.txt other.txt
  git commit -q -m init
  # staged edit, then the working tree puts the original bytes back
  printf 'staged-change\n' > tracked.txt
  git add tracked.txt
  printf 'original\n' > tracked.txt
  # a real net change against HEAD, so the frozen diff is never empty
  printf 'second\nappended\n' > other.txt
  printf 'brand new and untracked\n' > untracked.txt
}

round_dir() {
  local d="$REPO/.speccraft/.review-rounds/round"
  mkdir -p "$d"
  printf '%s\n' "$d"
}

# ---------------------------------------------------------------------------
# AC22 — one diff, computed once
# ---------------------------------------------------------------------------

@test "review_freeze_diff writes exactly one artifact into the round dir" {
  source "$LIB"
  mkrepo
  local d; d="$(round_dir)"

  run review_freeze_diff "$d"
  [ "$status" -eq 0 ] || { echo "freeze failed: $output" >&2; return 1; }

  # It echoes the artifact path, and that path is inside the round dir.
  local art="$output"
  [ -f "$art" ] || { echo "no artifact at '$art'" >&2; return 1; }
  case "$art" in
    "$d"/*) : ;;
    *) echo "artifact '$art' is not inside the round dir '$d'" >&2; return 1 ;;
  esac

  # Exactly one diff artifact, not one per agent.
  local n
  n="$(find "$d" -maxdepth 1 -type f -name '*.diff' | wc -l | tr -d ' ')"
  [ "$n" -eq 1 ] || {
    echo "expected exactly 1 .diff artifact in the round dir, found $n:" >&2
    find "$d" -maxdepth 1 -type f -name '*.diff' >&2
    return 1
  }
}

@test "review_freeze_diff refuses a second materialization" {
  source "$LIB"
  mkrepo
  local d; d="$(round_dir)"

  run review_freeze_diff "$d"
  [ "$status" -eq 0 ]

  # The 0052 single-creation seam. A second freeze in the same round means two
  # reviewers can be handed two different diffs, which is the whole defect.
  run review_freeze_diff "$d"
  assert_named_failure 'already'
}

@test "the frozen diff is git diff HEAD, so a staged edit reversed in the tree is absent" {
  source "$LIB"
  mkrepo
  local d; d="$(round_dir)"
  local art; art="$(review_freeze_diff "$d")"

  # The reversed edit nets to nothing against HEAD. An implementation that used
  # `git diff --cached` would show it, and the two reviewers would disagree
  # about a change that does not exist.
  grep -qF 'staged-change' "$art" && {
    echo "a staged edit reversed in the working tree must not appear:" >&2
    cat "$art" >&2
    return 1
  }
  # ...while the genuine net change does appear.
  grep -qF 'appended' "$art" || {
    echo "the real net change against HEAD is missing:" >&2
    cat "$art" >&2
    return 1
  }
  return 0
}

@test "the frozen diff is byte-identical to git diff HEAD" {
  source "$LIB"
  mkrepo
  local d; d="$(round_dir)"
  local art; art="$(review_freeze_diff "$d")"

  git diff HEAD > "$TEST_DIR/expected.diff"
  cmp -s "$art" "$TEST_DIR/expected.diff" || {
    echo "frozen diff differs from 'git diff HEAD':" >&2
    diff "$TEST_DIR/expected.diff" "$art" >&2 || true
    return 1
  }
}

@test "with --base the frozen diff is git diff <ref>...HEAD" {
  source "$LIB"
  mkrepo
  # a second commit so <ref>...HEAD has something to say that `git diff HEAD`
  # does not: committed changes are invisible to the default form.
  printf 'committed-only\n' > committed.txt
  git add committed.txt
  git commit -q -m second
  local base; base="$(git rev-parse HEAD~1)"

  local d; d="$(round_dir)"
  local art; art="$(review_freeze_diff "$d" "$base")"

  git diff "$base"...HEAD > "$TEST_DIR/expected.diff"
  cmp -s "$art" "$TEST_DIR/expected.diff" || {
    echo "frozen --base diff differs from 'git diff <ref>...HEAD':" >&2
    diff "$TEST_DIR/expected.diff" "$art" >&2 || true
    return 1
  }
  grep -qF 'committed-only' "$art" || {
    echo "the committed change must be in a <ref>...HEAD diff:" >&2
    cat "$art" >&2
    return 1
  }
}

@test "an untracked file is absent from the frozen diff" {
  source "$LIB"
  mkrepo
  local d; d="$(round_dir)"
  local art; art="$(review_freeze_diff "$d")"

  grep -qF 'brand new and untracked' "$art" && {
    echo "untracked content must not be in the frozen diff:" >&2
    cat "$art" >&2
    return 1
  }
  grep -qF 'untracked.txt' "$art" && {
    echo "an untracked path must not be in the frozen diff:" >&2
    cat "$art" >&2
    return 1
  }
  return 0
}

@test "review_freeze_diff refuses a round dir that does not exist" {
  source "$LIB"
  mkrepo
  # A typo'd round dir must be a named error, not a diff written to a path
  # nobody composes from — which would dispatch an EMPTY diff to every agent.
  run review_freeze_diff "$REPO/.speccraft/.review-rounds/nope"
  assert_named_failure 'round'
}

@test "review_freeze_diff names an unknown base ref rather than freezing nothing" {
  source "$LIB"
  mkrepo
  local d; d="$(round_dir)"
  run review_freeze_diff "$d" no-such-ref
  assert_named_failure 'no-such-ref'
}

@test "review_freeze_diff on a clean tree still writes the artifact" {
  source "$LIB"
  git init -q .
  git config user.email t@example.com
  git config user.name  Test
  printf 'x\n' > a.txt
  git add a.txt
  git commit -q -m init

  local d; d="$(round_dir)"
  run review_freeze_diff "$d"
  [ "$status" -eq 0 ] || { echo "a clean tree must not be an error: $output" >&2; return 1; }
  # An empty-but-present artifact is what lets the composer and the budget
  # treat "nothing changed" as a round with a verdict rather than a crash.
  [ -f "$output" ] || { echo "no artifact for a clean tree" >&2; return 1; }
}

# ---------------------------------------------------------------------------
# AC22a — the exclusion is stated, in the payload and on stdout
# ---------------------------------------------------------------------------

@test "the code-review template names the untracked-file exclusion in prose" {
  # Not a comment and not a flag: prose the reviewer reads. A reviewer that is
  # not told assumes the diff is everything and approves a branch carrying a
  # file it never saw.
  grep -qiF 'untracked' "$TPL" || {
    echo "templates/prompts/review-code.md does not mention untracked files" >&2
    return 1
  }
  grep -qiE 'untracked files (are|were)? ?(deliberately )?(not|NOT)' "$TPL" || {
    echo "the mention must state the EXCLUSION, not merely use the word:" >&2
    grep -niF untracked "$TPL" >&2
    return 1
  }
}

@test "the composed payload carries the untracked-file exclusion" {
  source "$LIB"
  mkrepo
  # AC22a on the composed bytes, not on the template alone: a template line
  # dropped by the composer's substitution loop would leave the reviewer
  # uninformed while the template test above still passed.
  mkdir -p "$REPO/.speccraft"
  printf 'guardrails\n' > .speccraft/guardrails.md
  printf 'index\n'      > .speccraft/index.md
  printf '# arch\n'     > .speccraft/architecture.md
  printf '# conv\n'     > .speccraft/conventions.md
  printf '# spec\n'     > "$TEST_DIR/spec.md"

  local d; d="$(round_dir)"
  review_freeze_diff "$d" > /dev/null
  local art="$d/payload"
  review_materialize_payload "$art" \
    review_compose_payload "$TPL" "$TEST_DIR/spec.md" \
      --inline .speccraft/guardrails.md .speccraft/index.md \
      --reference .speccraft/architecture.md .speccraft/conventions.md \
      --digest-out "$d/digests" > /dev/null

  grep -qiF 'untracked' "$art" || {
    echo "the composed payload never names the untracked exclusion" >&2
    return 1
  }
}

@test "the review-code command repeats the untracked exclusion on stdout" {
  # The operator reading the round's output must see it too. The payload tells
  # the reviewer; stdout tells the human who has to decide whether the round
  # covered what they care about.
  grep -qiF 'untracked' "$CMD" || {
    echo "commands/spec/review-code.md does not mention untracked files" >&2
    return 1
  }
  grep -qiE 'stdout|report|surface|print' "$CMD" || {
    echo "the command body does not say the exclusion is reported" >&2
    return 1
  }
}

@test "the code-review template keeps a challenge framing" {
  # Spec: 'The code-review template keeps a challenge framing.' A template that
  # drifts to 'summarize the changes' yields agreeable nothing from every model.
  grep -qiE 'challenge|assume the diff is wrong|hunt for' "$TPL" || {
    echo "review-code.md lost its challenge framing:" >&2
    head -20 "$TPL" >&2
    return 1
  }
}

# ---------------------------------------------------------------------------
# AC22 — no active spec
# ---------------------------------------------------------------------------

@test "the review-code command states the round runs with no active spec" {
  # 'With no active spec, review-code still runs and the payload says so; a
  # spec is not required.' review-code reviews a DIFF; refusing without a spec
  # would make it unusable on exactly the ad-hoc change it exists for.
  grep -qiE 'no active spec|without an active spec|if any' "$CMD" || {
    echo "review-code.md does not cover the no-active-spec case" >&2
    return 1
  }
  grep -qiE 'still run|does not require|not required|proceed' "$CMD" || {
    echo "review-code.md does not say the round still runs:" >&2
    grep -niE 'active spec' "$CMD" >&2
    return 1
  }
}

@test "the no-spec substitute names itself rather than being an empty section" {
  source "$LIB"
  mkrepo
  printf 'guardrails\n' > .speccraft/guardrails.md
  printf 'index\n'      > .speccraft/index.md
  printf '# arch\n'     > .speccraft/architecture.md
  printf '# conv\n'     > .speccraft/conventions.md

  # The command hands the composer a stand-in when no spec is active. An EMPTY
  # file would compose a 'Spec under review' heading with nothing under it,
  # which reads as a truncated payload rather than as a deliberate absence.
  local d; d="$(round_dir)"
  review_no_active_spec_notice > "$TEST_DIR/nospec.md"
  [ -s "$TEST_DIR/nospec.md" ] || {
    echo "the no-spec stand-in must not be empty" >&2
    return 1
  }
  grep -qiE 'no active spec|no spec is active' "$TEST_DIR/nospec.md" || {
    echo "the stand-in must say no spec is active; got:" >&2
    cat "$TEST_DIR/nospec.md" >&2
    return 1
  }
}

# ---------------------------------------------------------------------------
# Out of scope — the negative that keeps it out
# ---------------------------------------------------------------------------

@test "no --include-untracked option exists anywhere in the shipped surface" {
  # Explicitly out of scope. Pinned because it is the obvious next feature
  # request, and adding it would silently break AC22's reproducibility claim:
  # an untracked sweep is not reconstructable from a recorded HEAD.
  local hits
  hits="$(grep -rlF -- '--include-untracked' \
    "$PLUGIN_DIR/commands" "$PLUGIN_DIR/skills" "$PLUGIN_DIR/templates" \
    "$PLUGIN_DIR/agents" "$PLUGIN_DIR/hooks" 2>/dev/null || true)"
  [ -z "$hits" ] || {
    echo "--include-untracked is out of scope but appears in:" >&2
    printf '%s\n' "$hits" >&2
    return 1
  }
  # Premise check: the grep above must be capable of finding the string, or the
  # assertion is vacuous for the usual reason.
  printf -- 'x --include-untracked y\n' > "$TEST_DIR/canary.md"
  grep -rlF -- '--include-untracked' "$TEST_DIR" >/dev/null || {
    echo "the grep cannot find the string it is asserting absent" >&2
    return 1
  }
}

@test "review_freeze_diff rejects an unknown option" {
  source "$LIB"
  mkrepo
  local d; d="$(round_dir)"
  # So a future --include-untracked cannot arrive as a silently ignored word.
  run review_freeze_diff "$d" --include-untracked
  assert_named_failure 'include-untracked'
}
