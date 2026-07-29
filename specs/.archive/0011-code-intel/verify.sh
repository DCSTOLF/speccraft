#!/usr/bin/env bash
# specs/0011-code-intel/verify.sh
#
# Mechanical verification of acceptance criteria for spec 0011 —
# "Defer code-intel routing to user globals".
#
# Run from the repo root:
#   bash specs/0011-code-intel/verify.sh
#
# Exit 0 means all three ACs hold. Non-zero means at least one fails;
# stderr names which check.
set -euo pipefail

# Resolve repo root from this script's location, then cd there so all
# greps below see consistent relative paths regardless of the caller's CWD.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
cd "$REPO_ROOT"

fails=0
note_fail() {
  echo "FAIL: $*" >&2
  fails=$((fails + 1))
}
note_pass() {
  echo "pass: $*"
}

# ---------------------------------------------------------------------------
# AC1 — skills/speccraft-context/SKILL.md
# ---------------------------------------------------------------------------
SKILL="skills/speccraft-context/SKILL.md"

# AC1.a: no codegraph / cgc references anywhere in the skill file.
if grep -inE 'codegraph|cgc' "$SKILL" >/dev/null 2>&1; then
  note_fail "AC1.a: $SKILL still contains codegraph/cgc references"
  grep -inE 'codegraph|cgc' "$SKILL" >&2 || true
else
  note_pass "AC1.a: $SKILL has no codegraph/cgc references"
fi

# AC1.b: positive presence of deferral wording.
if grep -in 'defer' "$SKILL" >/dev/null 2>&1; then
  note_pass "AC1.b: $SKILL contains 'defer' wording"
else
  note_fail "AC1.b: $SKILL lacks any 'defer' wording"
fi

# AC1.c: the structural-queries section was replaced, not deleted —
# look for the acknowledgment phrase the spec calls out by name.
if grep -inE 'structural queries are a real need|structural queries are a legitimate need' "$SKILL" >/dev/null 2>&1; then
  note_pass "AC1.c: $SKILL retains structural-queries acknowledgment"
else
  note_fail "AC1.c: $SKILL is missing the 'structural queries are a real/legitimate need' acknowledgment"
fi

# ---------------------------------------------------------------------------
# AC2 — commands/init.md (repo-wide)
# ---------------------------------------------------------------------------
INIT="commands/init.md"

# AC2.a: exactly one repo-wide match, in commands/init.md.
matches="$(grep -rni 'codegraph' commands/ agents/ hooks/ skills/ tools/ templates/ 2>/dev/null || true)"
match_count="$(printf '%s' "$matches" | grep -c . || true)"
if [ "$match_count" -eq 1 ]; then
  if printf '%s\n' "$matches" | grep -q '^commands/init\.md:'; then
    note_pass "AC2.a: exactly one repo-wide codegraph match, in $INIT"
  else
    note_fail "AC2.a: the single surviving match is not in $INIT"
    printf '%s\n' "$matches" >&2
  fi
else
  note_fail "AC2.a: expected exactly 1 repo-wide codegraph match, got $match_count"
  printf '%s\n' "$matches" >&2
fi

# AC2.b: the surviving line frames CodeGraphContext as an example.
if grep -niE 'such as|for example|e\.g\.,' "$INIT" | grep -i 'codegraphcontext' >/dev/null 2>&1; then
  note_pass "AC2.b: $INIT frames CodeGraphContext as an example"
else
  note_fail "AC2.b: $INIT does not frame CodeGraphContext as an example (looking for 'such as' / 'for example' / 'e.g.,' on the same line)"
fi

# AC2.c: the conditional install-suggestion behaviour is preserved —
# the trigger phrase ('call-graph' or 'symbol-search') still appears.
if grep -niE 'call-graph|symbol-search' "$INIT" >/dev/null 2>&1; then
  note_pass "AC2.c: $INIT still gates the suggestion on call-graph / symbol-search needs"
else
  note_fail "AC2.c: $INIT lost the conditional trigger phrase (call-graph / symbol-search)"
fi

# ---------------------------------------------------------------------------
# AC3 — templates/speccraft/architecture.md
# ---------------------------------------------------------------------------
ARCH="templates/speccraft/architecture.md"

# AC3.a: no codegraph references anywhere under templates/.
if grep -rni 'codegraph' templates/ >/dev/null 2>&1; then
  note_fail "AC3.a: templates/ still contains codegraph references"
  grep -rni 'codegraph' templates/ >&2 || true
else
  note_pass "AC3.a: templates/ has no codegraph references"
fi

# AC3.b: the layering rule still stands as advisory.
if grep -in 'Advisory in v1' "$ARCH" >/dev/null 2>&1; then
  note_pass "AC3.b: $ARCH retains 'Advisory in v1' qualifier"
else
  note_fail "AC3.b: $ARCH lost the 'Advisory in v1' qualifier"
fi

# ---------------------------------------------------------------------------
echo
if [ "$fails" -eq 0 ]; then
  echo "all acceptance checks passed (spec 0011)"
  exit 0
else
  echo "$fails acceptance check(s) failed" >&2
  exit 1
fi
