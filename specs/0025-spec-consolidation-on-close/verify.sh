#!/usr/bin/env bash
# specs/0025-spec-consolidation-on-close/verify.sh
#
# Mechanical verification of the doc-layer contracts for spec 0025 — spec
# consolidation into current domain specs on close. The bash helper
# (commands/spec/consolidate.lib.sh) is pinned by tests/hooks/spec-consolidate.bats
# and the model-behavior ACs by tests/e2e/spec_consolidate.sh; this oracle covers
# what is purely a documentation / wiring / invariant contract:
#   - close.md sources the lib and wires inline, confirm-gated consolidation (AC9)
#   - sync.md sources the lib and adds the backfill propose loop (AC11)
#   - memory-keeper documents a "consolidate" mode (reviewable responsibility
#     expansion, the reuse-not-new-agent decision)
#   - the paired context-skill invariant: speccraft-context loads
#     specs/domains/<area>.md (lazy) AND never lists either .archive tree
#   - template purity: templates/speccraft/** carries no domain-file-shape grammar
#     or .archive layout leak
#
# Run from anywhere:
#   bash specs/0025-spec-consolidation-on-close/verify.sh
# Exit 0 = all checks hold. Non-zero = at least one fails; stderr names which.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
cd "$REPO_ROOT"

fails=0
note_fail() { echo "FAIL: $*" >&2; fails=$((fails + 1)); }
note_pass() { echo "pass: $*"; }

present() { local f="$1" re="$2" d="$3"; if [ -f "$f" ] && grep -qE "$re" "$f"; then note_pass "$d"; else note_fail "$d"; fi; }
absent()  { local f="$1" re="$2" d="$3"; if [ -f "$f" ] && grep -qE "$re" "$f"; then note_fail "$d"; else note_pass "$d"; fi; }

# ---- 1. close.md: sources the lib + wires inline confirm-gated consolidation (AC9) ----
CLOSE="commands/spec/close.md"
present "$CLOSE" 'commands/spec/consolidate\.lib\.sh' "$CLOSE sources consolidate.lib.sh"
present "$CLOSE" 'consolidate_parse_delta|consolidate_apply_delta|consolidate_routing_seed' \
        "$CLOSE calls a consolidate helper (inline consolidation step)"
present "$CLOSE" '[Cc]onfirm'                          "$CLOSE consolidation step is confirm-gated"
present "$CLOSE" 'never gates close|still closes|close still completes' \
        "$CLOSE states consolidation never gates close"

# ---- 2. sync.md: sources the lib + adds the backfill propose loop (AC11) ----
SYNC="commands/sync.md"
present "$SYNC" 'commands/spec/consolidate\.lib\.sh'  "$SYNC sources consolidate.lib.sh"
present "$SYNC" 'consolidate_backfill_candidates'      "$SYNC enumerates backfill candidates"
present "$SYNC" 'consolidate_backfill_order'           "$SYNC presents the history.md replay order"
present "$SYNC" 'consolidation-skip'                   "$SYNC writes a consolidation-skip marker on decline"

# ---- 3. memory-keeper documents a "consolidate" mode (reviewable expansion) ----
MK="agents/memory-keeper.md"
present "$MK" '^#+[[:space:]]*Mode:[[:space:]]*consolidate' "$MK documents a '# Mode: consolidate' section"
present "$MK" '[Pp]ropose'  "$MK consolidate mode mentions propose"
present "$MK" '[Mm]erge'    "$MK consolidate mode mentions merge"
present "$MK" '[Rr]out'     "$MK consolidate mode mentions routing"
present "$MK" '[Cc]onflict' "$MK consolidate mode mentions conflict"

# ---- 4. paired context-skill invariant (load specs/domains/<area>.md, NOT .archive) ----
SKILL="skills/speccraft-context/SKILL.md"
present "$SKILL" 'specs/domains/'         "$SKILL loads specs/domains/<area>.md (current behavior)"
absent  "$SKILL" 'specs/\.archive'        "$SKILL does NOT load specs/.archive (no silent re-bloat)"
absent  "$SKILL" 'specs/domains/\.archive' "$SKILL does NOT load specs/domains/.archive"

# ---- 5. template purity: no domain-file-shape grammar / .archive leak ----
# Presence pairing: the template tree exists and carries its memory templates, so the
# absence checks below are meaningful (not vacuously true on an empty tree).
if [ -f templates/speccraft/conventions.md ]; then
  note_pass "templates/speccraft/ carries its memory templates (purity scope is non-empty)"
else
  note_fail "templates/speccraft/conventions.md missing — purity scope is empty"
fi
if grep -rqE 'consolidation-conflicts|specs/domains/\.archive|specs/\.archive' templates/speccraft/ 2>/dev/null; then
  note_fail "templates/speccraft/** leaks consolidation/.archive layout (template purity)"
else
  note_pass "templates/speccraft/** is free of consolidation/.archive layout (template purity)"
fi

if [ "$fails" -ne 0 ]; then
  echo "verify.sh: $fails check(s) failed" >&2
  exit 1
fi
echo "verify.sh: all checks passed"
