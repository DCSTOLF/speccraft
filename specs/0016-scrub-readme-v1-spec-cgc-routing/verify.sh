#!/usr/bin/env bash
# verify.sh — grep-assertion oracle for spec 0016
#
# Per .speccraft/conventions.md §"Grep-assertion oracle for doc-only specs"
# (spec 0011). Each AC1 + AC2 string is one labelled grep -F invocation. Every
# grep is FILE-SCOPED by name to README.md or speccraft-v1-spec.md — repo-wide
# grep -r is forbidden because the absence-target strings literally appear
# inside this spec's own spec.md (AC3).
#
# Exit code:
#   0  — all 12 checks passed (full GREEN)
#   1  — at least one check failed; check labelled output above

set -euo pipefail

# Resolve repo root from BASH_SOURCE so greps see consistent paths regardless
# of caller CWD (per convention §"Grep-assertion oracle").
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
cd "$REPO_ROOT"

fails=0

# --- absence check helper -----------------------------------------------------
# Args: <label> <file> <fixed-string>
# Pass: file does NOT contain string. Fail: file DOES contain string.
absent() {
  local label="$1" file="$2" needle="$3"
  if grep -qF -- "$needle" "$file"; then
    echo "FAIL [$label]: '$needle' still present in $file"
    fails=$((fails + 1))
  else
    echo "ok   [$label]"
  fi
}

# --- presence check helper ----------------------------------------------------
# Args: <label> <file> <fixed-string>
# Pass: file DOES contain string. Fail: file does NOT contain string.
present() {
  local label="$1" file="$2" needle="$3"
  if grep -qF -- "$needle" "$file"; then
    echo "ok   [$label]"
  else
    echo "FAIL [$label]: '$needle' missing from $file (anchor erased?)"
    fails=$((fails + 1))
  fi
}

echo "=== spec 0016 verify.sh — grep-assertion oracle ==="
echo

echo "--- README.md absence checks (AC1) ---"
# Single-quoted literal preserves backticks; grep -F treats them as data.
absent 'absence #1: README "prefer it over grep/find"' \
  README.md \
  'prefer it over `grep`/`find` for structural questions'
absent 'absence #2: README "skill will note its presence"' \
  README.md \
  'the speccraft skill will note its presence'
absent 'absence #3: README "the recommended way to answer"' \
  README.md \
  "It's the recommended way to answer"
absent 'absence #4: README "use its tools to check architectural"' \
  README.md \
  'use its tools to check architectural invariants'
absent 'absence #5: README "prefer CGC for structural queries" (defensive pin)' \
  README.md \
  'prefer CodeGraphContext for structural queries'

echo
echo "--- README.md presence anchor (AC1) ---"
present 'presence: README "Recommended companions" section header' \
  README.md \
  'Recommended companions'

echo
echo "--- speccraft-v1-spec.md absence checks (AC2) ---"
absent 'absence #7: v1-spec "prefer its tools for structural queries"' \
  speccraft-v1-spec.md \
  'prefer its tools for structural queries'
absent 'absence #8: v1-spec "suggest installing CGC as an MCP server"' \
  speccraft-v1-spec.md \
  'suggest installing CodeGraphContext as an MCP server alongside speccraft'
absent 'absence #9: v1-spec "should install it as an MCP server"' \
  speccraft-v1-spec.md \
  'should install it as an MCP server alongside speccraft'
absent 'absence #10: v1-spec "users who need these capabilities should install"' \
  speccraft-v1-spec.md \
  'users who need these capabilities should install'
absent 'absence #11: v1-spec "the recommended integration with CGC"' \
  speccraft-v1-spec.md \
  'the recommended integration with CodeGraphContext'

echo
echo "--- speccraft-v1-spec.md presence anchor (AC2) ---"
present 'presence: v1-spec "Recommended companion" §13 bolded label' \
  speccraft-v1-spec.md \
  'Recommended companion'

echo
if [ "$fails" -eq 0 ]; then
  echo "PASS: all 12 checks ok"
  exit 0
else
  echo "FAIL: $fails check(s) failed"
  exit 1
fi
