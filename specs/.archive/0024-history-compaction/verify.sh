#!/usr/bin/env bash
# specs/0024-history-compaction/verify.sh
#
# Mechanical verification of the doc-layer contracts for spec 0024 — bounded,
# reviewable history.md compaction. The bash helper (compact.lib.sh) is pinned by
# tests/hooks/history-compact.bats and the model-behavior ACs by
# tests/e2e/history_compact.sh; this oracle covers what is purely a
# documentation / frontmatter / invariant contract:
#   - the /speccraft:history:compact command frontmatter
#   - memory-keeper's documented "compact" mode (the reuse-not-new-store decision
#     made an explicit, reviewable responsibility expansion)
#   - the paired context-skill invariant: the speccraft-context skill still loads
#     history.md by name AND does NOT load history-archive (so archiving cannot
#     silently re-bloat context)
#   - the spec:close nudge wiring references the command
#
# Run from anywhere:
#   bash specs/0024-history-compaction/verify.sh
# Exit 0 = all checks hold. Non-zero = at least one fails; stderr names which.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
cd "$REPO_ROOT"

fails=0
note_fail() { echo "FAIL: $*" >&2; fails=$((fails + 1)); }
note_pass() { echo "pass: $*"; }

has_key()  { local f="$1" k="$2"; [ -f "$f" ] && grep -qE "^${k}:" "$f"; }
present()  { local f="$1" re="$2" d="$3"; if [ -f "$f" ] && grep -qE "$re" "$f"; then note_pass "$d"; else note_fail "$d"; fi; }
absent()   { local f="$1" re="$2" d="$3"; if [ -f "$f" ] && grep -qE "$re" "$f"; then note_fail "$d"; else note_pass "$d"; fi; }

# ---- 1. command frontmatter ----
CMD="commands/history/compact.md"
if [ -f "$CMD" ]; then
  for k in description argument-hint allowed-tools; do
    if has_key "$CMD" "$k"; then note_pass "$CMD has '$k:'"; else note_fail "$CMD missing '$k:'"; fi
  done
else
  note_fail "command missing: $CMD"
fi

# ---- 2. memory-keeper documents a "compact" mode (reviewable expansion) ----
MK="agents/memory-keeper.md"
present "$MK" '^#+[[:space:]]*Mode:[[:space:]]*compact' "$MK documents a '# Mode: compact' section"
present "$MK" '[Pp]ropose'                              "$MK compact mode mentions propose"
present "$MK" '[Ss]ummari[sz]e'                         "$MK compact mode mentions summarize"
present "$MK" '[Mm]erge'                                "$MK compact mode mentions merge"

# ---- 3. paired context-skill invariant (load history.md, NOT history-archive) ----
SKILL="skills/speccraft-context/SKILL.md"
present "$SKILL" 'history\.md'        "$SKILL still loads history.md by name"
absent  "$SKILL" 'history-archive'    "$SKILL does NOT load history-archive (no silent re-bloat)"

# ---- 4. spec:close nudge wiring references the command ----
present "commands/spec/close.md" '/speccraft:history:compact' "commands/spec/close.md references /speccraft:history:compact (nudge wiring)"

if [ "$fails" -ne 0 ]; then
  echo "verify.sh: $fails check(s) failed" >&2
  exit 1
fi
echo "verify.sh: all checks passed"
