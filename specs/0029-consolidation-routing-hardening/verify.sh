#!/usr/bin/env bash
# specs/0029-consolidation-routing-hardening/verify.sh
#
# Doc-contract oracle for spec 0029 Fix C (the conflation hardening). The
# deterministic tier (zsh-safe sourcing, the exact-form BASH_SOURCE guard,
# consolidate_existing_domains, the seed byte-pin) is covered by
# tests/hooks/spec-consolidate.bats; AC6 by tests/e2e/spec_consolidate.sh. This
# oracle pins what is purely documentation: that close.md + memory-keeper make the
# two close-time mechanisms (Mode: close → .speccraft/ ; Mode: consolidate →
# specs/domains/) UN-CONFUSABLE.
#
# Run from anywhere:
#   bash specs/0029-consolidation-routing-hardening/verify.sh
# Exit 0 = all checks hold. Non-zero = at least one fails; stderr names which.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
cd "$REPO_ROOT"

fails=0
present() {
  local f="$1" re="$2" d="$3"
  if [ -f "$f" ] && grep -qiE "$re" "$f"; then echo "pass: $d"; else echo "FAIL: $d" >&2; fails=$((fails+1)); fi
}

CLOSE="commands/spec/close.md"
MK="agents/memory-keeper.md"

# ---- AC4 — never-.speccraft routing, restated at the point of use ----
present "$CLOSE" 'routes only to .*specs/domains'                       "$CLOSE: consolidation routes ONLY to specs/domains/"
present "$CLOSE" 'never .*(writes? )?.*\.speccraft/'                    "$CLOSE: consolidation NEVER writes .speccraft/"
present "$MK"    'routes only to .*specs/domains'                       "$MK Mode: consolidate routes ONLY to specs/domains/"
present "$MK"    'never .*(writes? )?.*\.speccraft/'                    "$MK Mode: consolidate NEVER writes .speccraft/"

# ---- AC4 — no-substitute disambiguation (Mode: close ≠ Mode: consolidate) ----
present "$CLOSE" 'not a substitute for .*consolidat'                    "$CLOSE: Mode: close updates are NOT a substitute for consolidation"
present "$MK"    'does not perform consolidation'                       "$MK Mode: close: 'does not perform consolidation' disambiguator"
present "$MK"    'see .*mode: consolidate'                              "$MK Mode: close: points to Mode: consolidate"

# ---- AC5 — no-delta/no-domains is a FALLBACK, not a skip ----
present "$CLOSE" 'fallback.*not a skip|never a skip'                    "$CLOSE: missing delta:/domains: is a fallback, never a skip"
present "$MK"    'fallback.*not a skip|never a skip'                    "$MK Mode: consolidate: missing delta:/domains: is a fallback, never a skip"

# ---- CF-4 — residual-risk note (mitigation, not enforcement) ----
present "$MK"    'mitigation, not enforcement'                          "$MK: residual-risk note (Fix C is mitigation, not enforcement)"

if [ "$fails" -ne 0 ]; then
  echo "verify.sh: $fails check(s) failed" >&2
  exit 1
fi
echo "verify.sh: all checks passed"
