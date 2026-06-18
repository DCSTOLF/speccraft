#!/usr/bin/env bash
# scripts/verify-release.sh — release-completeness oracle (spec 0021).
#
# Usage: verify-release.sh <version>      # version WITHOUT leading "v"
#
# Asserts that the published release for v<version> is complete and
# installable: the four platform tarballs and checksums.txt all resolve
# under ${SPECCRAFT_RELEASE_BASE}/v<version>/, and — in the STRONG form —
# each tarball's recomputed SHA-256 matches its checksums.txt entry.
# Exits 0 only when all four resolve AND all four hashes match; otherwise
# prints a loud, named failure and exits non-zero.
#
# SPECCRAFT_RELEASE_BASE defaults to the GitHub Releases download base;
# tests override it with a file:// base to run hermetically (no network).
# This script is reused as release.yml's final self-verify step.
set -euo pipefail

VERSION="${1:?usage: verify-release.sh <version>  (e.g. 1.1.0)}"
BASE="${SPECCRAFT_RELEASE_BASE:-https://github.com/dcstolf/speccraft/releases/download}"
PLATFORMS=(linux-amd64 linux-arm64 macos-amd64 macos-arm64)
REL="$BASE/v$VERSION"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

die() { echo "verify-release: $*" >&2; exit 1; }

# fetch <url> <dest> — copy for a file:// base, curl otherwise. Returns
# non-zero (without aborting under set -e at the call site via `|| die`)
# when the asset is missing or unreachable.
fetch() {
  local url="$1" dest="$2"
  case "$url" in
    file://*) cp "${url#file://}" "$dest" 2>/dev/null ;;
    *)        curl -fsSL "$url" -o "$dest" ;;
  esac
}

SUMS_URL="$REL/checksums.txt"
fetch "$SUMS_URL" "$TMP/checksums.txt" \
  || die "missing or unreachable: $SUMS_URL"

for plat in "${PLATFORMS[@]}"; do
  tarball="speccraft-$VERSION-$plat.tar.gz"
  url="$REL/$tarball"
  fetch "$url" "$TMP/$tarball" \
    || die "missing or unreachable asset: $url"

  expected="$(awk -v f="$tarball" '$2 == f { print $1 }' "$TMP/checksums.txt")"
  [ -n "$expected" ] \
    || die "no checksum entry for $tarball in checksums.txt"

  actual="$(sha256sum "$TMP/$tarball" | awk '{ print $1 }')"
  if [ "$actual" != "$expected" ]; then
    die "checksum mismatch (SHA-256) for $tarball: expected $expected, got $actual"
  fi
done

echo "verify-release: v$VERSION OK — 4 platform tarballs + checksums.txt verified"
