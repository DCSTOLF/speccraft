#!/usr/bin/env bash
# specs/0022-pm-architect-upstream-workflows/verify.sh
#
# Mechanical verification of the doc-layer acceptance criteria for spec 0022 —
# PM and Architect upstream workflows. Covers the agent + command frontmatter
# contracts, critic-narrowness, and the critic-before-cross-reviewer ordering
# in the *:review command bodies. The Go/bats/e2e layers cover the behavioral
# ACs; this oracle covers what is purely a documentation/frontmatter contract.
#
# Run from anywhere:
#   bash specs/0022-pm-architect-upstream-workflows/verify.sh
#
# Exit 0 = all checks hold. Non-zero = at least one fails; stderr names which.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
cd "$REPO_ROOT"

fails=0
note_fail() { echo "FAIL: $*" >&2; fails=$((fails + 1)); }
note_pass() { echo "pass: $*"; }

# has_key <file> <key>  — frontmatter key present (e.g. "name:", "model:").
has_key() {
  local file="$1" key="$2"
  [ -f "$file" ] && grep -qE "^${key}:" "$file"
}

check_agent_frontmatter() {
  local file="$1"
  if [ ! -f "$file" ]; then
    note_fail "agent missing: $file"
    return
  fi
  local k
  for k in name description tools model; do
    if has_key "$file" "$k"; then
      note_pass "$file has '$k:'"
    else
      note_fail "$file missing '$k:' frontmatter key"
    fi
  done
}

check_command_frontmatter() {
  local file="$1"
  if [ ! -f "$file" ]; then
    note_fail "command missing: $file"
    return
  fi
  local k
  for k in description argument-hint allowed-tools; do
    if has_key "$file" "$k"; then
      note_pass "$file has '$k:'"
    else
      note_fail "$file missing '$k:' frontmatter key"
    fi
  done
}

# ---------------------------------------------------------------------------
# Author + critic agents (OQ3) — presence + frontmatter contract.
# ---------------------------------------------------------------------------
for a in pm-author arch-author pm-critic arch-critic; do
  check_agent_frontmatter "agents/$a.md"
done

# ---------------------------------------------------------------------------
# Reuse-unchanged pin — cross-reviewer + memory-keeper must still be present
# (this spec reuses them; it does not replace them).
# ---------------------------------------------------------------------------
for a in cross-reviewer memory-keeper; do
  if [ -f "agents/$a.md" ]; then
    note_pass "reused agent present: agents/$a.md"
  else
    note_fail "reused agent missing: agents/$a.md"
  fi
done

# ---------------------------------------------------------------------------
# Command bodies — presence + frontmatter contract.
# ---------------------------------------------------------------------------
for c in new review prioritize close; do
  check_command_frontmatter "commands/pm/$c.md"
done
for c in new review decide close; do
  check_command_frontmatter "commands/arch/$c.md"
done

# ---------------------------------------------------------------------------
# Critic narrowness — critics carry a checklist and are NOT a review quorum.
# Positive: mentions a "checklist". Negative: does not mention "quorum".
# ---------------------------------------------------------------------------
for critic in pm-critic arch-critic; do
  f="agents/$critic.md"
  if grep -qiE 'checklist' "$f" 2>/dev/null; then
    note_pass "$f carries a checklist (stage-specific self-check)"
  else
    note_fail "$f lacks 'checklist' wording (critic should be a self-check)"
  fi
  if grep -qiE 'quorum' "$f" 2>/dev/null; then
    note_fail "$f mentions 'quorum' — critics must not be a second review quorum"
  else
    note_pass "$f does not claim a review quorum"
  fi
done

# ---------------------------------------------------------------------------
# Invoked-before-review — *:review runs the critic self-check before the
# cross-model cross-reviewer. Assert both are referenced and the critic line
# precedes the cross-reviewer line.
# ---------------------------------------------------------------------------
check_critic_before_review() {
  local cmd="$1" critic="$2"
  if [ ! -f "$cmd" ]; then
    note_fail "review command missing: $cmd"
    return
  fi
  local cl xl
  cl="$(grep -nF "$critic" "$cmd" | head -1 | cut -d: -f1)"
  xl="$(grep -nF "cross-reviewer" "$cmd" | head -1 | cut -d: -f1)"
  if [ -z "$cl" ]; then
    note_fail "$cmd does not reference $critic"
    return
  fi
  if [ -z "$xl" ]; then
    note_fail "$cmd does not reference cross-reviewer"
    return
  fi
  if [ "$cl" -lt "$xl" ]; then
    note_pass "$cmd invokes $critic (line $cl) before cross-reviewer (line $xl)"
  else
    note_fail "$cmd invokes $critic (line $cl) AFTER cross-reviewer (line $xl)"
  fi
}
check_critic_before_review "commands/pm/review.md" "pm-critic"
check_critic_before_review "commands/arch/review.md" "arch-critic"

if [ "$fails" -gt 0 ]; then
  echo "verify.sh: $fails check(s) failed" >&2
  exit 1
fi
echo "verify.sh: all checks passed"
