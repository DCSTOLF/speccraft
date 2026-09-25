#!/usr/bin/env bats
# Spec 0049 T17/T18 (AC11) — scripts/verify-linux-pins.sh.
#
# AC11 is a claim about the test suite's COVERAGE TOPOLOGY: reverting any one of
# this spec's three production fixes must fail at least one test ON LINUX, so no
# fix is pinned only by the macOS runner. That is not something a single
# assertion checks, so it is operationalised as a script that reverts each fix
# in turn and asserts a failure.
#
# The script is non-CI-gating and author-run before close. Its DANGEROUS
# property is the reason for most of the tests below: a helper whose job is to
# revert production fixes is one bug away from destroying uncommitted work.
# Review round 2 (codex) required isolation; review item 4 (claude-p) preferred
# a detached worktree over a temp clone — same isolation, faster, and no risk of
# inheriting an unclean index.

setup() {
  PLUGIN_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SCRIPT="$PLUGIN_DIR/scripts/verify-linux-pins.sh"
  export PLUGIN_DIR SCRIPT
}

@test "verify-linux-pins --list names exactly the three production pins" {
  run bash "$SCRIPT" --list
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  echo "$output" | grep -q 'commands/arch/decide.lib.sh'
  echo "$output" | grep -q 'commands/pm/prioritize.lib.sh'
  echo "$output" | grep -q 'commands/spec/consolidate.lib.sh'
  # Exactly three, so a fix added later cannot be silently unpinned.
  [ "$(echo "$output" | grep -c 'lib.sh')" -eq 3 ]
}

# Review item 3 (codex): fingerprint the caller's tree BEFORE creating the
# worktree, so a mutation caused during SETUP is also caught. Fingerprinting
# after setup would blind the final self-check to the script's own damage.
@test "verify-linux-pins fingerprints the caller tree BEFORE creating the worktree" {
  # Order is load-bearing, so assert it in the source rather than inferring it.
  fp="$(grep -n 'caller_fingerprint=' "$SCRIPT" | head -1 | cut -d: -f1)"
  wt="$(grep -n 'worktree add --detach' "$SCRIPT" | head -1 | cut -d: -f1)"
  [ -n "$fp" ] && [ -n "$wt" ] && [ "$fp" -lt "$wt" ]
}

@test "verify-linux-pins uses git worktree add --detach, never a temp clone" {
  grep -q 'git worktree add --detach' "$SCRIPT"
  run grep -n 'git clone' "$SCRIPT"
  [ "$status" -ne 0 ] || { echo "a temp clone can inherit an unclean index; use a detached worktree:"; echo "$output"; false; }
}

@test "verify-linux-pins removes the worktree on every exit path including failure" {
  grep -qE "^[[:space:]]*trap " "$SCRIPT"
  grep -q 'worktree remove' "$SCRIPT"
}

# BEHAVIOURAL, not source introspection: if the per-pin baseline were not
# restored, reverts would LAYER and the second check would run with two fixes
# missing instead of one — which is how one revert contaminates the next.
#
# The injected test command records, on each invocation, how many of the three
# markers are still present. With a clean baseline every invocation must see
# exactly 2 of 3. A layered run would show 2, then 1, then 0.
@test "verify-linux-pins restarts each mutation from the same clean baseline" {
  grep -q 'SPECCRAFT_VLP_TEST_CMD' "$SCRIPT"

  repo="$(mktemp -d)"
  git -C "$repo" init -q
  git -C "$repo" config user.email t@example.com
  git -C "$repo" config user.name t
  mkdir -p "$repo/commands/arch" "$repo/commands/pm" "$repo/commands/spec"
  printf 'set-status --kind design\n' > "$repo/commands/arch/decide.lib.sh"
  printf 'set-status --kind brief\n'  > "$repo/commands/pm/prioritize.lib.sh"
  printf 'for(i=NR;i>0;i--)\n'        > "$repo/commands/spec/consolidate.lib.sh"
  git -C "$repo" add -A
  git -C "$repo" commit -qm init

  # OUTSIDE the repo: anything created inside it would trip the script's own
  # "caller checkout was modified" self-check (exit 3) — which is the check
  # working correctly, so the harness must not fight it.
  aux="$(mktemp -d)"
  log="$aux/marker-counts.log"
  counter="$aux/count-markers.sh"
  cat > "$counter" <<'EOS'
#!/usr/bin/env bash
n=0
grep -qF 'set-status --kind design' commands/arch/decide.lib.sh && n=$((n+1))
grep -qF 'set-status --kind brief'  commands/pm/prioritize.lib.sh && n=$((n+1))
grep -qF 'for(i=NR;i>0;i--)'        commands/spec/consolidate.lib.sh && n=$((n+1))
echo "$n" >> "$MARKER_LOG"
exit 1   # always "fail" so every pin counts as PINNED and the loop completes
EOS
  chmod +x "$counter"

  MARKER_LOG="$log" SPECCRAFT_VLP_TEST_CMD="$counter" \
    run bash -c "cd '$repo' && bash '$SCRIPT'"
  [ "$status" -eq 0 ] || { echo "expected all pins confirmed"; echo "$output"; false; }

  # Three invocations, each seeing exactly two markers.
  [ "$(wc -l < "$log")" -eq 3 ] || { echo "expected 3 invocations, got:"; cat "$log"; false; }
  ! grep -qv '^2$' "$log" || { echo "a revert leaked into the next check (counts should all be 2):"; cat "$log"; false; }
  rm -rf "$repo" "$aux"
}

# The property that matters most: even a run where a pin check FAILS must leave
# the caller's checkout byte-identical. Exercised for real against a scratch
# repo, with an injected test command that always reports success — which makes
# every pin look UNPINNED and drives the script down its failure path.
@test "verify-linux-pins leaves the caller checkout byte-identical after a FAILING run" {
  repo="$(mktemp -d)"
  git -C "$repo" init -q
  git -C "$repo" config user.email t@example.com
  git -C "$repo" config user.name t
  mkdir -p "$repo/commands/arch" "$repo/commands/pm" "$repo/commands/spec" "$repo/scripts"
  printf 'set-status --kind design\n' > "$repo/commands/arch/decide.lib.sh"
  printf 'set-status --kind brief\n'  > "$repo/commands/pm/prioritize.lib.sh"
  printf 'for(i=NR;i>0;i--)\n'        > "$repo/commands/spec/consolidate.lib.sh"
  cp "$SCRIPT" "$repo/scripts/verify-linux-pins.sh"
  git -C "$repo" add -A
  git -C "$repo" commit -qm init

  # An uncommitted change the script must not touch.
  printf 'MY UNCOMMITTED WORK\n' > "$repo/scratch.txt"
  before_scratch="$(cat "$repo/scratch.txt")"
  before_tree="$(cd "$repo" && find . -path ./.git -prune -o -type f -print | sort | xargs -I{} sh -c 'printf "%s " {}; cksum < {}' | sort)"

  # SPECCRAFT_VLP_TEST_CMD=true ⇒ tests "pass" even with a fix reverted, so
  # every pin is reported UNPINNED and the script exits non-zero.
  SPECCRAFT_VLP_TEST_CMD=true run bash -c "cd '$repo' && bash scripts/verify-linux-pins.sh"
  [ "$status" -ne 0 ] || { echo "with an always-passing test command every pin is unpinned; must exit non-zero"; echo "$output"; false; }

  after_scratch="$(cat "$repo/scratch.txt")"
  after_tree="$(cd "$repo" && find . -path ./.git -prune -o -type f -print | sort | xargs -I{} sh -c 'printf "%s " {}; cksum < {}' | sort)"
  [ "$before_scratch" = "$after_scratch" ] || { echo "uncommitted work was modified"; false; }
  [ "$before_tree" = "$after_tree" ] || { echo "caller checkout changed:"; diff <(echo "$before_tree") <(echo "$after_tree") || true; false; }
  # And no worktree left behind.
  run bash -c "cd '$repo' && git worktree list | wc -l"
  [ "$(echo "$output" | tr -d ' ')" = "1" ]
  rm -rf "$repo"
}
