#!/usr/bin/env bash
# specs/0030-cross-env-command-hardening/verify.sh
#
# Grep oracle for spec 0030's doc/config-only surfaces — the sections that have
# no natural Go/bats failing test. Each check below IS the RED for its surface on
# `main` and goes green as the corresponding migration lands:
#
#   AC6  — no bare $CLAUDE_PLUGIN_ROOT deref for bin/|commands/|templates/ in any
#          command doc; each migrated doc resolves via `speccraft-state plugin-root`.
#   AC7  — the sourceable-command-helper convention is updated in lockstep.
#   AC9  — no zsh-reserved identifier is assigned in any commands/**/*.lib.sh
#          (backstopped by the real-zsh source leg in tests/hooks/lib-zsh-safety.bats).
#   AC11 — the two JSON manifests carry version 1.7.0.
#   AC12 — .devcontainer exports SPECCRAFT_PLUGIN_ROOT.
#
# Run from anywhere:
#   bash specs/0030-cross-env-command-hardening/verify.sh
# Exit 0 = all checks hold. Non-zero = at least one fails; stderr names which.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
cd "$REPO_ROOT"

fails=0
pass() { echo "pass: $1"; }
fail() { echo "FAIL: $1" >&2; fails=$((fails+1)); }

# present_in <file> <ere> <desc>: file must exist and match.
present_in() {
  if [ -f "$1" ] && grep -qE "$2" "$1"; then pass "$3"; else fail "$3"; fi
}
# absent_in <file> <ere> <desc>: file must exist and NOT match.
absent_in() {
  if [ -f "$1" ] && grep -qE "$2" "$1"; then fail "$3"; else pass "$3"; fi
}

# ---- AC6 — no bare $CLAUDE_PLUGIN_ROOT deref in command docs (hooks/ exempt) ----
# Matches $CLAUDE_PLUGIN_ROOT or ${CLAUDE_PLUGIN_ROOT} immediately followed by a
# /bin, /commands, or /templates path segment.
FORBIDDEN='\$\{?CLAUDE_PLUGIN_ROOT\}?/(bin|commands|templates)'
if grep -rnE "$FORBIDDEN" commands --include='*.md' >/dev/null 2>&1; then
  echo "FAIL: AC6 — bare \$CLAUDE_PLUGIN_ROOT/{bin,commands,templates} deref still present in command docs:" >&2
  grep -rnE "$FORBIDDEN" commands --include='*.md' >&2 || true
  fails=$((fails+1))
else
  pass "AC6 — no bare \$CLAUDE_PLUGIN_ROOT/{bin,commands,templates} deref in command docs"
fi

# ---- AC6 (positive) — the resolve idiom is present where docs need the root ----
if grep -rqF 'PLUGIN_ROOT="$(speccraft-state plugin-root)"' commands --include='*.md'; then
  pass "AC6 — command docs resolve PLUGIN_ROOT via speccraft-state plugin-root"
else
  fail "AC6 — no command doc uses PLUGIN_ROOT=\"\$(speccraft-state plugin-root)\""
fi

# ---- AC7 — convention lockstep ----
CONV=".speccraft/conventions.md"
present_in "$CONV" 'speccraft-state plugin-root' \
  "$CONV: Runtime sourcing prescribes speccraft-state plugin-root"
absent_in "$CONV" 'source[[:space:]]+"\$CLAUDE_PLUGIN_ROOT/commands/' \
  "$CONV: old \$CLAUDE_PLUGIN_ROOT sourcing form removed as the canonical example"

# ---- AC9 — no zsh-reserved identifier assigned in any commands/**/*.lib.sh ----
RESERVED='status|pipestatus|path|cdpath|fignore|mailpath|manpath|fpath|watch|psvar|signals|argv|histchars|ARGC|HISTCHARS'
# (a) bare/prefixed assignment target: NAME=
ASSIGN="(^|[[:space:]])($RESERVED)="
# (b) declaration/loop of a reserved NAME as a standalone word
DECL="(^|[[:space:]])(local|declare|typeset|read|for)[[:space:]]+([^#=]*[[:space:]])?($RESERVED)([[:space:]]|=|\$)"
zsh_hit=0
while IFS= read -r lib; do
  if grep -nE "$ASSIGN" "$lib" >/dev/null 2>&1 || grep -nE "$DECL" "$lib" >/dev/null 2>&1; then
    echo "FAIL: AC9 — zsh-reserved identifier assigned in $lib:" >&2
    grep -nE "$ASSIGN|$DECL" "$lib" >&2 || true
    zsh_hit=1
  fi
done < <(find commands -name '*.lib.sh' | sort)
if [ "$zsh_hit" -eq 0 ]; then
  pass "AC9 — no zsh-reserved identifier assigned in any commands/**/*.lib.sh"
else
  fails=$((fails+1))
fi

# ---- AC11 — version 1.7.0 across the JSON manifests ----
present_in ".claude-plugin/plugin.json"      '"version":[[:space:]]*"1\.7\.0"' \
  ".claude-plugin/plugin.json at 1.7.0"
present_in ".claude-plugin/marketplace.json" '"version":[[:space:]]*"1\.7\.0"' \
  ".claude-plugin/marketplace.json at 1.7.0"

# ---- AC12 — devcontainer exports SPECCRAFT_PLUGIN_ROOT ----
present_in ".devcontainer/devcontainer.json" 'SPECCRAFT_PLUGIN_ROOT' \
  ".devcontainer/devcontainer.json exports SPECCRAFT_PLUGIN_ROOT"

if [ "$fails" -ne 0 ]; then
  echo "verify.sh: $fails check(s) failed" >&2
  exit 1
fi
echo "verify.sh: all checks passed"
