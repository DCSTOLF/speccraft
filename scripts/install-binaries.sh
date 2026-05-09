#!/usr/bin/env bash
# Download (or build) speccraft helper binaries into <plugin>/bin/.
# Idempotent: skips when .binary-version matches plugin version.
# Full implementation wired in Phase 4. This is the Phase 0 stub.
set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BIN_DIR="$PLUGIN_DIR/bin"
VERSION_FILE="$PLUGIN_DIR/.binary-version"
RELEASE_BASE="https://github.com/dcstolf/speccraft/releases/download"

EXPECTED="$(jq -r '.version' "$PLUGIN_DIR/.claude-plugin/plugin.json")"
INSTALLED="$([ -f "$VERSION_FILE" ] && cat "$VERSION_FILE" || echo "none")"

# Fast path: already correct.
if [ "$INSTALLED" = "$EXPECTED" ] && [ -x "$BIN_DIR/speccraft-state" ]; then
  exit 0
fi

# Detect platform.
OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
case "$OS" in
  darwin) OS="macos" ;;
  linux)  OS="linux" ;;
  *) echo "speccraft: unsupported OS $OS (Windows: use WSL)" >&2; exit 1 ;;
esac

ARCH="$(uname -m)"
case "$ARCH" in
  arm64|aarch64) ARCH="arm64" ;;
  x86_64|amd64)  ARCH="amd64" ;;
  *) echo "speccraft: unsupported arch $ARCH" >&2; exit 1 ;;
esac

PLATFORM="${OS}-${ARCH}"
TARBALL="speccraft-${EXPECTED}-${PLATFORM}.tar.gz"
URL="${RELEASE_BASE}/v${EXPECTED}/${TARBALL}"
SUMS_URL="${RELEASE_BASE}/v${EXPECTED}/checksums.txt"

mkdir -p "$BIN_DIR"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "speccraft: installing helper binaries (v${EXPECTED}, ${PLATFORM})..." >&2

if curl -fsSL "$URL" -o "$TMP/${TARBALL}" 2>/dev/null \
   && curl -fsSL "$SUMS_URL" -o "$TMP/checksums.txt" 2>/dev/null; then
  ( cd "$TMP" && grep "${TARBALL}" checksums.txt | sha256sum -c - >&2 )
  tar -xzf "$TMP/${TARBALL}" -C "$BIN_DIR"
  chmod +x "$BIN_DIR"/*
  echo "$EXPECTED" > "$VERSION_FILE"
  echo "speccraft: installed." >&2
  exit 0
fi

# Source fallback.
if command -v go >/dev/null 2>&1; then
  echo "speccraft: download unavailable; building from source..." >&2
  ( cd "$PLUGIN_DIR/tools" \
    && for cmd in speccraft-state speccraft-guard speccraft-drift; do
         CGO_ENABLED=0 go build -o "$BIN_DIR/$cmd" "./cmd/$cmd"
       done )
  echo "$EXPECTED" > "$VERSION_FILE"
  echo "speccraft: built from source." >&2
  exit 0
fi

cat >&2 <<EOF
speccraft: failed to install helper binaries.

Tried:
  1. Download from ${URL}
  2. Build from source (requires 'go' on PATH; not found)

Check network connectivity, or install Go >= 1.22 to build from source.
Run \`bash $PLUGIN_DIR/scripts/doctor.sh\` for a full diagnostic.
EOF
exit 1
