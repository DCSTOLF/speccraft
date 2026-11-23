#!/usr/bin/env bats
# Spec 0054 ACs 17b / 17c — the content-aware tree snapshot.
#
# After a round, speccraft must tell whether a reviewer wrote outside its round
# dir. A subagent runs with the orchestrator's own tools, so nothing stops it
# editing the repo; `failed subagent-wrote-files` is how that is caught.
#
# The obvious implementations all have holes, and each one is a required row
# below rather than prose:
#
#   `git status --porcelain` text comparison — a tracked file that was ALREADY
#     dirty keeps the byte-identical ` M <path>` entry when its contents change
#     again, and an untracked DIRECTORY collapses to one `?? <dir>/` entry no
#     matter how many files appear beneath it.
#   a path-only untracked inventory — editing the bytes of an existing
#     untracked file adds and removes no paths at all.
#   `--exclude-standard` — writing `bin/probe` or `tools/bin/probe` is ignored
#     by git and therefore invisible, and committing a built binary is a hard
#     guardrail subject in this repo, which makes it the most consequential
#     row here rather than an edge case.
#   `--directory` — collapses an untracked tree back to one entry.
#
# So the snapshot HASHES content, per file.

setup() {
  PLUGIN_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  LIB="$PLUGIN_DIR/commands/spec/review.lib.sh"
  export PATH="$PLUGIN_DIR/bin:$PATH"
  TEST_DIR="$(mktemp -d)"
  REPO="$TEST_DIR/repo"
  mkdir -p "$REPO/.speccraft"
  cd "$REPO"
  git init -q
  git config user.email t@example.com
  git config user.name T
  printf 'tracked one\n' > tracked.txt
  mkdir -p sub
  printf 'tracked two\n' > sub/nested.txt
  git add -A
  git commit -qm init
}

teardown() {
  cd /
  rm -rf "$TEST_DIR"
}

# snap <out> — capture a snapshot into a file. Through a FILE, never `$(...)`:
# the snapshot is a multi-line digest listing whose trailing newline matters
# for a byte comparison.
snap() {
  review_tree_snapshot > "$1"
}

# assert_changed <before> <after> <why>
assert_changed() {
  if cmp -s "$1" "$2"; then
    echo "snapshot did NOT change: $3" >&2
    echo "--- snapshot ---" >&2
    head -40 "$1" >&2
    return 1
  fi
  return 0
}

assert_unchanged() {
  cmp -s "$1" "$2" || {
    echo "snapshot changed but should not have: $3" >&2
    diff "$1" "$2" >&2 || true
    return 1
  }
  return 0
}

# ---------------------------------------------------------------------------
# What the snapshot covers
# ---------------------------------------------------------------------------

@test "review_tree_snapshot hashes every tracked file outside the round dir" {
  source "$LIB"
  snap "$TEST_DIR/s1"
  grep -qF 'tracked.txt' "$TEST_DIR/s1"
  grep -qF 'sub/nested.txt' "$TEST_DIR/s1"
}

@test "review_tree_snapshot hashes every untracked regular file" {
  source "$LIB"
  printf 'untracked\n' > loose.txt
  snap "$TEST_DIR/s1"
  grep -qF 'loose.txt' "$TEST_DIR/s1"
}

@test "two files under one untracked directory both appear in the snapshot" {
  source "$LIB"
  # THE row that fails if --directory is ever used: it would collapse these to
  # a single `newdir/` entry and a later file appearing there would be
  # invisible.
  mkdir -p newdir
  printf 'a\n' > newdir/a.txt
  printf 'b\n' > newdir/b.txt

  snap "$TEST_DIR/s1"
  grep -qF 'newdir/a.txt' "$TEST_DIR/s1" || {
    echo "newdir/a.txt missing — the enumeration collapsed the directory" >&2
    return 1
  }
  grep -qF 'newdir/b.txt' "$TEST_DIR/s1" || {
    echo "newdir/b.txt missing — the enumeration collapsed the directory" >&2
    return 1
  }
}

@test "it records path and type for untracked non-regular entries without hashing them" {
  source "$LIB"
  ln -s /nonexistent-target danglink

  # A dangling symlink cannot be read as content, but it must still be
  # RECORDED by path and type, or creating one would be an invisible change.
  run review_tree_snapshot
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qE '^symlink +danglink$' || {
    echo "the dangling symlink was not recorded with its type:" >&2
    printf '%s\n' "$output" >&2
    return 1
  }
  # And it was not hashed — a dangling symlink has no content to hash.
  printf '%s\n' "$output" | grep -qE '^[0-9a-f]{64}  danglink$' && {
    echo "a dangling symlink must not carry a content digest" >&2
    return 1
  }
  return 0
}

@test "git does not enumerate fifos, so the snapshot cannot see them either" {
  source "$LIB"
  mkfifo afifo 2>/dev/null || skip "mkfifo unavailable"

  # A STATED LIMITATION, pinned so it is not mistaken for coverage. git lists
  # untracked regular files and symlinks; a fifo appears in neither
  # `ls-files --others` nor `status --porcelain`, so no git-based enumeration
  # can report one. The premise is asserted first, so this row documents git's
  # behaviour rather than merely accepting the snapshot's.
  [ "$(git ls-files --others | grep -c '^afifo$')" -eq 0 ] || {
    echo "premise broken: git DOES enumerate fifos now; the snapshot should too" >&2
    return 1
  }
  [ "$(git status --porcelain | grep -c 'afifo')" -eq 0 ]

  run review_tree_snapshot
  [ "$status" -eq 0 ]

  # Consequence: a reviewer creating a fifo outside its round dir is NOT
  # detected. Accepted deliberately — catching it would mean walking the whole
  # worktree with find instead of asking git, and for this check a false
  # positive (AC17c: "sensitive without being noisy") is far more damaging
  # than missing an exotic case no reviewer has reason to produce.
  printf '%s\n' "$output" | grep -qF 'afifo' && {
    echo "unexpected: the snapshot saw a fifo — update this row's reasoning" >&2
    return 1
  }
  return 0
}

# ---------------------------------------------------------------------------
# The four required rows — each defeats a weaker implementation
# ---------------------------------------------------------------------------

@test "modifying an already-dirty tracked file changes the snapshot" {
  source "$LIB"
  # Already dirty BEFORE the round, so its porcelain entry is byte-identical
  # before and after: ` M tracked.txt` both times.
  printf 'dirty already\n' >> tracked.txt
  snap "$TEST_DIR/before"
  local porc_before porc_after
  porc_before="$(git status --porcelain -- tracked.txt)"

  printf 'dirty again\n' >> tracked.txt
  snap "$TEST_DIR/after"
  porc_after="$(git status --porcelain -- tracked.txt)"

  # The premise: porcelain really is unchanged, so this row is testing what it
  # claims to test.
  [ "$porc_before" = "$porc_after" ] || {
    echo "premise broken: porcelain differed ($porc_before vs $porc_after)" >&2
    return 1
  }
  assert_changed "$TEST_DIR/before" "$TEST_DIR/after" "an already-dirty tracked file was modified again"
}

@test "adding a file beneath an already-untracked directory changes the snapshot" {
  source "$LIB"
  mkdir -p untracked_dir
  printf 'first\n' > untracked_dir/first.txt
  snap "$TEST_DIR/before"

  printf 'second\n' > untracked_dir/second.txt
  snap "$TEST_DIR/after"
  assert_changed "$TEST_DIR/before" "$TEST_DIR/after" "a file appeared under an already-untracked directory"
}

@test "editing the bytes of an existing untracked file changes the snapshot" {
  source "$LIB"
  # Adds and removes NO paths at all — the row that fails if untracked files
  # are inventoried by path instead of hashed.
  printf 'v1\n' > loose.txt
  snap "$TEST_DIR/before"

  printf 'v2\n' > loose.txt
  snap "$TEST_DIR/after"
  assert_changed "$TEST_DIR/before" "$TEST_DIR/after" "an untracked file's bytes changed with no path added or removed"
}

@test "writing bin/probe changes the snapshot" {
  source "$LIB"
  # The hard-guardrail row: `bin/` is gitignored here, so --exclude-standard
  # would make a built binary landing in it invisible. "Never commit built
  # binaries from bin/" is a stated guardrail, which makes this the most
  # consequential row in the file.
  printf '%s\n' 'bin/' > .gitignore
  printf '%s\n' 'tools/bin/' >> .gitignore
  git add .gitignore && git commit -qm ignore
  mkdir -p bin
  snap "$TEST_DIR/before"

  printf 'ELF\n' > bin/probe
  snap "$TEST_DIR/after"
  assert_changed "$TEST_DIR/before" "$TEST_DIR/after" "bin/probe was written"
}

@test "writing tools/bin/probe changes the snapshot" {
  source "$LIB"
  printf '%s\n' 'bin/' > .gitignore
  printf '%s\n' 'tools/bin/' >> .gitignore
  git add .gitignore && git commit -qm ignore
  mkdir -p tools/bin
  snap "$TEST_DIR/before"

  printf 'ELF\n' > tools/bin/probe
  snap "$TEST_DIR/after"
  assert_changed "$TEST_DIR/before" "$TEST_DIR/after" "tools/bin/probe was written"
}

# ---------------------------------------------------------------------------
# Negative rows over the implementation
# ---------------------------------------------------------------------------

@test "the enumeration passes no --exclude-standard" {
  run sh -c "cat '$LIB' | grep -vE '^[[:space:]]*#' | grep -nF -- '--exclude-standard'"
  [ "$status" -ne 0 ]
}

@test "the enumeration passes no --directory" {
  run sh -c "cat '$LIB' | grep -vE '^[[:space:]]*#' | grep -nE 'ls-files[^|;]*--directory'"
  [ "$status" -ne 0 ]
}

@test "the two enumeration guards bite on an executable line" {
  local probe="$TEST_DIR/probe.sh"
  printf '%s\n' '# a comment naming --exclude-standard and ls-files --directory' > "$probe"
  run sh -c "cat '$probe' | grep -vE '^[[:space:]]*#' | grep -nF -- '--exclude-standard'"
  [ "$status" -ne 0 ]

  printf '%s\n' 'f() { git ls-files --others --exclude-standard -z; }' >> "$probe"
  run sh -c "cat '$probe' | grep -vE '^[[:space:]]*#' | grep -nF -- '--exclude-standard'"
  [ "$status" -eq 0 ]

  printf '%s\n' 'g() { git ls-files --others --directory -z; }' >> "$probe"
  run sh -c "cat '$probe' | grep -vE '^[[:space:]]*#' | grep -nE 'ls-files[^|;]*--directory'"
  [ "$status" -eq 0 ]
}

@test "the implementation never compares git status --porcelain text" {
  # Porcelain text cannot see either of the first two required rows above.
  run sh -c "cat '$LIB' | grep -vE '^[[:space:]]*#' | grep -nF -- 'status --porcelain'"
  [ "$status" -ne 0 ]
}

@test "the porcelain guard bites on an executable line" {
  local probe="$TEST_DIR/probe2.sh"
  printf '%s\n' '# a comment naming status --porcelain' > "$probe"
  run sh -c "cat '$probe' | grep -vE '^[[:space:]]*#' | grep -nF -- 'status --porcelain'"
  [ "$status" -ne 0 ]
  printf '%s\n' 'f() { git status --porcelain; }' >> "$probe"
  run sh -c "cat '$probe' | grep -vE '^[[:space:]]*#' | grep -nF -- 'status --porcelain'"
  [ "$status" -eq 0 ]
}

@test "the snapshot hashes content rather than listing paths alone" {
  source "$LIB"
  # The positive counterpart to the path-only negative: every regular file's
  # line must carry a digest, not just its path.
  printf 'content\n' > loose.txt
  snap "$TEST_DIR/s1"
  grep -E '^[0-9a-f]{64}  ' "$TEST_DIR/s1" >/dev/null || {
    echo "no sha256 digests in the snapshot:" >&2
    head -10 "$TEST_DIR/s1" >&2
    return 1
  }
  # And the untracked file specifically is hashed, not merely named.
  grep -E "^[0-9a-f]{64}  loose\.txt$" "$TEST_DIR/s1" >/dev/null || {
    echo "the untracked file carries no digest:" >&2
    grep -F loose.txt "$TEST_DIR/s1" >&2
    return 1
  }
}

@test "the snapshot uses no literal GNU checksum tool" {
  # Both portability-guard.bats and tests-portability-sweep.bats flag that
  # token; the digest must go through _review_digest_cmd, whose resolved PATH
  # is what gets executed.
  source "$LIB"
  grep -q '_review_digest_cmd' "$LIB"
}

# ---------------------------------------------------------------------------
# AC17b — the volatile set is a CLOSED list of four
# ---------------------------------------------------------------------------

@test "a mid-round write to .claude/settings.local.json leaves the check passing" {
  source "$LIB"
  mkdir -p .claude
  printf '{}\n' > .claude/settings.local.json
  snap "$TEST_DIR/before"
  printf '{"a":1}\n' > .claude/settings.local.json
  snap "$TEST_DIR/after"
  assert_unchanged "$TEST_DIR/before" "$TEST_DIR/after" ".claude/settings.local.json is volatile"
}

@test "a mid-round write to .speccraft/state.json leaves the check passing" {
  source "$LIB"
  printf '{}\n' > .speccraft/state.json
  snap "$TEST_DIR/before"
  printf '{"session":"x"}\n' > .speccraft/state.json
  snap "$TEST_DIR/after"
  assert_unchanged "$TEST_DIR/before" "$TEST_DIR/after" ".speccraft/state.json is volatile"
}

@test "a mid-round write to tests/e2e/.logs/ leaves the check passing" {
  source "$LIB"
  mkdir -p tests/e2e/.logs
  printf 'log\n' > tests/e2e/.logs/run.log
  snap "$TEST_DIR/before"
  printf 'more log\n' >> tests/e2e/.logs/run.log
  snap "$TEST_DIR/after"
  assert_unchanged "$TEST_DIR/before" "$TEST_DIR/after" "tests/e2e/.logs/ is volatile"
}

@test "a mid-round write to .speccraft/.review-rounds/.gitignore leaves the check passing" {
  source "$LIB"
  mkdir -p .speccraft/.review-rounds
  snap "$TEST_DIR/before"
  printf '*\n' > .speccraft/.review-rounds/.gitignore
  snap "$TEST_DIR/after"
  assert_unchanged "$TEST_DIR/before" "$TEST_DIR/after" "the round parent's own .gitignore is volatile"
}

@test "a write to any other ignored path fails the check" {
  source "$LIB"
  printf '%s\n' 'ignored_other/' > .gitignore
  git add .gitignore && git commit -qm ignore
  mkdir -p ignored_other
  snap "$TEST_DIR/before"
  printf 'x\n' > ignored_other/file.txt
  snap "$TEST_DIR/after"
  assert_changed "$TEST_DIR/before" "$TEST_DIR/after" "an ignored path OUTSIDE the four-entry list was written"
}

@test "the exclusion list contains exactly four entries" {
  source "$LIB"
  # A closed set, so widening it silently is not possible. Any fifth exclusion
  # is a deliberate, reviewable edit to this number.
  local n
  n="$(printf '%s\n' $REVIEW_TREE_VOLATILE | grep -c .)"
  [ "$n" -eq 4 ] || {
    echo "expected exactly 4 volatile entries, got $n: $REVIEW_TREE_VOLATILE" >&2
    return 1
  }
  for p in .claude/settings.local.json .speccraft/state.json tests/e2e/.logs .speccraft/.review-rounds; do
    printf '%s\n' $REVIEW_TREE_VOLATILE | grep -qxF "$p" || {
      echo "missing volatile entry '$p' in: $REVIEW_TREE_VOLATILE" >&2
      return 1
    }
  done
}

# ---------------------------------------------------------------------------
# AC17c — round setup is never mistaken for a reviewer write
# ---------------------------------------------------------------------------

@test "the whole .review-rounds tree is excluded from the snapshot" {
  source "$LIB"
  local dir
  dir="$(review_round_dir_create spec 0054 600)"
  snap "$TEST_DIR/before"
  printf 'payload\n' > "$dir/payload.md"
  printf 'digest\n' > "$dir/digests.txt"
  snap "$TEST_DIR/after"

  # The reviewer's OWN artifacts live here. If they registered as writes, every
  # round would report subagent-wrote-files.
  assert_unchanged "$TEST_DIR/before" "$TEST_DIR/after" "writes inside the round dir"
}

@test "AC17c property 1 sequence: the pre-round snapshot is taken after the round dir is created" {
  source "$LIB"
  # SEQUENCE, isolated. The installed-base first-round case: creating the round
  # writes BOTH the parent and its .gitignore, neither of which existed before.
  # Taking the pre-round snapshot AFTER create puts those setup writes in the
  # baseline, where they cannot read as a reviewer write.
  #
  # Nothing is written INTO the round dir here, deliberately. Doing so would
  # drag the exclusion property into this row, and AC17c asks for the two to
  # hold independently so that neither is silently load-bearing. This row
  # therefore still passes with the exclusion removed.
  [ ! -d .speccraft/.review-rounds ]

  review_round_dir_create spec 0054 600 >/dev/null
  [ -f .speccraft/.review-rounds/.gitignore ] || {
    echo "premise: round setup must have written the .gitignore before the snapshot" >&2
    return 1
  }

  snap "$TEST_DIR/before"
  snap "$TEST_DIR/after"
  assert_unchanged "$TEST_DIR/before" "$TEST_DIR/after" "round setup preceded the pre-round snapshot"
}

@test "AC17c property 2 exclusion: .review-rounds is excluded independent of sequence" {
  source "$LIB"
  # EXCLUSION, isolated. The snapshot is taken BEFORE the round dir exists at
  # all, and a payload is written into it afterwards — so every one of those
  # writes lands after the baseline and sequence cannot help. This row passes
  # only because .review-rounds is excluded, which is what makes it the
  # independent counterpart to property 1.
  [ ! -d .speccraft/.review-rounds ]
  snap "$TEST_DIR/before"

  local dir
  dir="$(review_round_dir_create spec 0054 600)"
  printf 'payload\n' > "$dir/payload.md"
  snap "$TEST_DIR/after"
  assert_unchanged "$TEST_DIR/before" "$TEST_DIR/after" "exclusion alone must cover round setup"
}

@test "the check passes with a pre-existing dirty tree and a pre-existing untracked file" {
  source "$LIB"
  # Sensitivity without noise: a repo that was already dirty and already had an
  # untracked file, with NOTHING changed during the round, must not report a
  # write. A check that compared against a clean tree would fire on every
  # developer's working copy.
  printf 'dirty\n' >> tracked.txt
  printf 'untracked\n' > loose.txt

  snap "$TEST_DIR/before"
  snap "$TEST_DIR/after"
  assert_unchanged "$TEST_DIR/before" "$TEST_DIR/after" "nothing changed during the round"
}
