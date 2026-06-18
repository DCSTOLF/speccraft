#!/usr/bin/env bash
# Diagnostic script for speccraft.
# Run: bash $CLAUDE_PLUGIN_ROOT/scripts/doctor.sh
set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BIN_DIR="$PLUGIN_DIR/bin"
VERSION_FILE="$PLUGIN_DIR/.binary-version"
PROVENANCE_FILE="$PLUGIN_DIR/.binary-provenance"

ok()   { printf "  %-30s [OK]\n" "$1"; }
warn() { printf "  %-30s [WARN] %s\n" "$1" "$2"; }
fail() { printf "  %-30s [FAIL] %s\n" "$1" "$2"; FAILED=1; }

FAILED=0

echo "speccraft doctor"
echo "================"
echo

echo "## Required tools"
for tool in git jq curl; do
  if command -v $tool >/dev/null 2>&1; then
    ok "$tool"
  else
    fail "$tool" "not found — install via your package manager"
  fi
done

echo
echo "## Claude Code"
if command -v claude >/dev/null 2>&1; then
  CLAUDE_VER="$(claude --version 2>&1 | head -1 || echo unknown)"
  ok "claude ($CLAUDE_VER)"
else
  fail "claude" "Claude Code not found"
fi

echo
echo "## Helper binaries"
PLUGIN_VERSION="$(jq -r '.version' "$PLUGIN_DIR/.claude-plugin/plugin.json" 2>/dev/null || echo unknown)"
INSTALLED_VERSION="$([ -f "$VERSION_FILE" ] && cat "$VERSION_FILE" || echo none)"

echo "  Plugin version:            $PLUGIN_VERSION"
echo "  Installed binary version:  $INSTALLED_VERSION"

for bin in speccraft-state speccraft-guard speccraft-drift; do
  if [ -x "$BIN_DIR/$bin" ]; then
    BIN_VER="$("$BIN_DIR/$bin" --version 2>&1 | head -1 || echo unknown)"
    ok "$bin ($BIN_VER)"
  else
    fail "$bin" "not found in $BIN_DIR — run scripts/install-binaries.sh"
  fi
done

if [ "$PLUGIN_VERSION" != "$INSTALLED_VERSION" ]; then
  warn "version mismatch" "plugin=$PLUGIN_VERSION installed=$INSTALLED_VERSION; run install-binaries.sh"
fi

# Provenance: distinguish a clean download from a source-build fallback.
# A "source" marker means the release download was unavailable and the
# binaries were compiled locally — a distinct, actionable state (the
# release for this version may be missing or broken).
PROVENANCE="$([ -f "$PROVENANCE_FILE" ] && cat "$PROVENANCE_FILE" || echo unknown)"
echo "  Binary provenance:         $PROVENANCE"
if [ "$PROVENANCE" = "source" ]; then
  warn "binary provenance" "built from source (download unavailable) — the release for v$PLUGIN_VERSION may be missing or broken"
fi

echo
echo "## Network (GitHub Releases)"
RELEASE_URL="https://github.com/dcstolf/speccraft/releases"
if curl -fsSL --max-time 10 "$RELEASE_URL" >/dev/null 2>&1; then
  ok "GitHub Releases reachable"
else
  warn "GitHub Releases" "unreachable (offline or proxy) — source-build fallback will be used"
fi

echo
echo "## Go toolchain (source fallback)"
if command -v go >/dev/null 2>&1; then
  GO_VER="$(go version 2>&1 | awk '{print $3}')"
  ok "go ($GO_VER)"
else
  warn "go" "not found — source build unavailable; using release binaries only"
fi

echo
echo "## Aux agents"
for agent in codex opencode; do
  if command -v $agent >/dev/null 2>&1; then
    ok "$agent"
  else
    warn "$agent" "not on PATH — /spec:delegate and /spec:review will use mock or skip"
  fi
done

if command -v acpx >/dev/null 2>&1; then
  ok "acpx (ACP mode available)"
else
  warn "acpx" "not found — ACP mode disabled; CLI mode unaffected"
fi

echo
if [ "$FAILED" -eq 0 ]; then
  echo "All required checks passed."
else
  echo "Some checks failed. Fix the issues above and re-run."
  exit 1
fi
