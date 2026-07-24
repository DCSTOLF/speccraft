#!/usr/bin/env bash
# specs/0031-guard-write-tool-red-candidate-blindspot/verify.sh
#
# Manifest oracle for spec 0031's version bump (AC6). The three Go `const
# version` surfaces are pinned by their sibling version_test.go files; this
# script pins the two JSON manifests that have no Go test.
#
# Run from anywhere:
#   bash specs/0031-guard-write-tool-red-candidate-blindspot/verify.sh
# Exit 0 = all checks hold. Non-zero = at least one fails; stderr names which.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
cd "$REPO_ROOT"

fails=0
present_in() {
  if [ -f "$1" ] && grep -qE "$2" "$1"; then echo "pass: $3"; else echo "FAIL: $3" >&2; fails=$((fails+1)); fi
}
absent_in() {
  if [ -f "$1" ] && grep -qE "$2" "$1"; then echo "FAIL: $3" >&2; fails=$((fails+1)); else echo "pass: $3"; fi
}

present_in ".claude-plugin/plugin.json"      '"version":[[:space:]]*"1\.7\.1"' ".claude-plugin/plugin.json at 1.7.1"
absent_in  ".claude-plugin/plugin.json"      '"version":[[:space:]]*"1\.7\.0"' ".claude-plugin/plugin.json no stale 1.7.0"
present_in ".claude-plugin/marketplace.json" '"version":[[:space:]]*"1\.7\.1"' ".claude-plugin/marketplace.json at 1.7.1"
absent_in  ".claude-plugin/marketplace.json" '"version":[[:space:]]*"1\.7\.0"' ".claude-plugin/marketplace.json no stale 1.7.0"

if [ "$fails" -ne 0 ]; then
  echo "verify.sh: $fails check(s) failed" >&2
  exit 1
fi
echo "verify.sh: all checks passed"
