#!/usr/bin/env bash
# Spec 0049 AC11 — verify that each of this spec's three production fixes is
# pinned by at least one test ON LINUX.
#
# WHY. AC11 is a claim about the test suite's COVERAGE TOPOLOGY, not about any
# single behaviour: no fix may be pinned *only* by the macOS runner, or a
# decision to gate that job (open question 2's documented fallback) would
# silently un-pin real bugs. There is no single assertion for that, so this
# script reverts each fix in turn and requires the suite to notice.
#
# NOT CI-GATING. Author-run before `/speccraft:spec:close`; its final line goes
# in the spec's changelog.md as the evidence for AC11.
#
# SAFETY, which is most of the code below. A helper whose job is to revert
# production fixes is one bug away from destroying uncommitted work, and a
# revert left in place would contaminate every later check in the same run. So:
#   * the caller's tree is fingerprinted FIRST, before any setup, so damage
#     done during setup is also caught (review item 3);
#   * all mutation happens in a DETACHED WORKTREE, never the caller's checkout,
#     and never a temp clone — a clone can inherit an unclean index (item 4);
#   * a trap removes the worktree on every exit path, including failure;
#   * each pin restarts from the same clean baseline rather than layering;
#   * a final self-check re-fingerprints the caller's tree and fails loudly if
#     a single byte moved.

set -uo pipefail

# --- the three pins -----------------------------------------------------------
# Each entry: <file>|<sed-free mutation marker>|<what reverting it breaks>
# The mutation is expressed as a token to delete, which is enough to undo each
# fix: remove the sanctioned-writer call or the portable reversal and the
# corresponding tests must fail.
PINS=(
  "commands/arch/decide.lib.sh|set-status --kind design|arch_set_status delegates to the sanctioned writer"
  "commands/pm/prioritize.lib.sh|set-status --kind brief|pm_set_status delegates to the sanctioned writer"
  "commands/spec/consolidate.lib.sh|for(i=NR;i>0;i--)|consolidate_backfill_order uses the POSIX reversal, not tac"
)

if [ "${1:-}" = "--list" ]; then
  for p in "${PINS[@]}"; do
    printf '%s — %s\n' "${p%%|*}" "${p##*|}"
  done
  exit 0
fi

repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "verify-linux-pins: not inside a git repository" >&2
  exit 2
}
cd "$repo_root" || exit 2

# --- fingerprint the caller's tree FIRST (review item 3) ----------------------
# Before ANY setup, so a mutation caused while creating the worktree is caught
# too. Fingerprinting after setup would blind this check to our own damage.
fingerprint_tree() {
  find . -path ./.git -prune -o -path ./.worktrees -prune -o -type f -print 2>/dev/null \
    | sort \
    | while IFS= read -r f; do printf '%s ' "$f"; cksum < "$f"; done
}
caller_fingerprint="$(fingerprint_tree)"

wt=""
pristine=""
cleanup() {
  # Runs on success, failure, and interrupt.
  if [ -n "$wt" ] && [ -d "$wt" ]; then
    git worktree remove --force "$wt" >/dev/null 2>&1 || rm -rf "$wt"
  fi
  [ -n "$pristine" ] && rm -rf "$pristine"
  git worktree prune >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

wt="$(mktemp -d)/pins"
if ! git worktree add --detach "$wt" HEAD >/dev/null 2>&1; then
  echo "verify-linux-pins: could not create a detached worktree" >&2
  exit 2
fi

# The worktree is created from HEAD for its git metadata and isolation, but HEAD
# is NOT the state under test: while a spec is in progress its fixes and its new
# test files are uncommitted, and most are untracked, so a HEAD worktree would
# contain the OLD code and the OLD suite and report every pin unpinned. (It did,
# on the first real run.) So overlay a snapshot of the CURRENT working tree.
#
# `git stash create` is not sufficient either — it excludes untracked files, and
# in this spec the new guard/sweep tests that do the pinning are untracked.
pristine="$(mktemp -d)"
if ! tar -cf - --exclude=./.git --exclude=./.worktrees . 2>/dev/null \
     | ( cd "$pristine" && tar -xf - ) 2>/dev/null; then
  echo "verify-linux-pins: could not snapshot the working tree" >&2
  exit 2
fi
overlay_pristine() {
  # Restore the worktree's content to the pristine snapshot. Overwrites in
  # place; .git is excluded so the worktree link file survives.
  ( cd "$pristine" && tar -cf - . ) 2>/dev/null | ( cd "$wt" && tar -xf - ) 2>/dev/null
}
overlay_pristine

# The suite to run inside the worktree. Injectable so the bats tests can drive
# the failure path deterministically without running the real suite.
test_cmd="${SPECCRAFT_VLP_TEST_CMD:-bats tests/hooks/}"

unpinned=0
confirmed=0
for p in "${PINS[@]}"; do
  file="${p%%|*}"
  rest="${p#*|}"
  marker="${rest%%|*}"
  desc="${rest##*|}"

  # Clean baseline for THIS pin — never layered on the previous revert. Restored
  # from the pristine working-tree snapshot, NOT `git checkout`, because the
  # state under test is the working tree rather than HEAD.
  overlay_pristine

  if [ ! -f "$wt/$file" ]; then
    echo "UNPINNED $file — file absent in the worktree"
    unpinned=$((unpinned + 1))
    continue
  fi

  # Revert the fix by deleting its marker line (no in-place stream edit: filter
  # to a temp and move, which is portable and leaves no backup sibling).
  #
  # `|| true` is REQUIRED, not defensive noise: grep exits 1 when it selects no
  # lines, which happens whenever removing the marker empties the file. Gating
  # the mv on grep's status (`grep … && mv`) therefore made the revert silently
  # no-op, and the script then reported the fix "pinned" on the strength of a
  # test run against unmodified code — a false green in the very tool that
  # exists to detect false greens.
  tmp="$(mktemp)"
  grep -vF "$marker" "$wt/$file" > "$tmp" || true
  mv "$tmp" "$wt/$file"

  # Prove the revert actually landed before drawing any conclusion from the
  # test run. Without this, any future failure to mutate reads as "pinned".
  if grep -qF "$marker" "$wt/$file"; then
    echo "ERROR $file — the revert did not take effect; refusing to judge this pin" >&2
    unpinned=$((unpinned + 1))
    continue
  fi

  if ( cd "$wt" && eval "$test_cmd" >/dev/null 2>&1 ); then
    echo "UNPINNED $file — reverting the fix did NOT fail any test ($desc)"
    unpinned=$((unpinned + 1))
  else
    echo "pinned   $file — $desc"
    confirmed=$((confirmed + 1))
  fi
done

# Restore the worktree to pristine before the self-check, then let the trap
# remove it entirely.
overlay_pristine

# --- final self-check: the caller's tree must be byte-identical ---------------
after_fingerprint="$(fingerprint_tree)"
if [ "$caller_fingerprint" != "$after_fingerprint" ]; then
  echo "FAIL: this script modified the caller's checkout — that must never happen." >&2
  diff <(printf '%s\n' "$caller_fingerprint") <(printf '%s\n' "$after_fingerprint") >&2 || true
  exit 3
fi

total=${#PINS[@]}
if [ "$unpinned" -ne 0 ]; then
  echo "verify-linux-pins.sh: ${confirmed}/${total} pins confirmed, ${unpinned} UNPINNED" >&2
  exit 1
fi
echo "verify-linux-pins.sh: ${confirmed}/${total} pins confirmed"
