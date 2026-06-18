#!/usr/bin/env bash
# tests/e2e/verify_release_test.sh — sibling fixture pinning
# scripts/verify-release.sh (spec 0021, AC1/AC4).
#
# verify-release.sh <version> is the release-completeness oracle: it
# asserts the four platform tarballs + checksums.txt resolve under
# ${SPECCRAFT_RELEASE_BASE}/v<version>/, and verifies integrity in the
# STRONG form (CF-4) — it downloads each tarball and recomputes its
# SHA-256 against the matching checksums.txt entry. It is reused as the
# final self-verify step of release.yml.
#
# This fixture exercises it hermetically via a file:// fixture base, so
# no network or real GitHub release is needed. Structure mirrors
# revise_noop_assertion_test.sh's Scenario A/B/C layout.
#
#   - Scenario A (positive): all four tarballs + a correct checksums.txt
#     present → exit 0.
#   - Scenario B (missing asset): one tarball absent → non-zero exit, and
#     the failure names the missing tarball's URL/path on stderr.
#   - Scenario C (checksum mismatch, STRONG form): a tarball is corrupted
#     after checksums.txt was computed → non-zero exit, checksum-mismatch
#     message. This is what makes the check strong rather than a mere
#     presence test.
#
# Exit codes: 0 success, 2 on any assertion failure (via lib.sh fail()).
set -euo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$LIB_DIR/lib.sh"

note() { echo "  $*"; }

echo "==> verify_release_test (spec 0021)"

REPO_ROOT="$(cd "$LIB_DIR/../.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/verify-release.sh"
VERSION="9.9.9"
PLATFORMS="linux-amd64 linux-arm64 macos-amd64 macos-arm64"

TMP="$(mktemp -d -t verify-release-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

# build_fixture <dir> — create v<VERSION>/ with the four tarballs and a
# checksums.txt computed over them. Echoes the release dir path.
build_fixture() {
  local root="$1" rel
  rel="$root/v$VERSION"
  mkdir -p "$rel"
  local plat
  for plat in $PLATFORMS; do
    # A "tarball" with deterministic-but-distinct bytes per platform.
    printf 'speccraft %s %s payload\n' "$VERSION" "$plat" \
      > "$rel/speccraft-$VERSION-$plat.tar.gz"
  done
  ( cd "$rel" && sha256sum speccraft-"$VERSION"-*.tar.gz > checksums.txt )
  echo "$rel"
}

# run_verify <fixture-root> — invoke verify-release.sh against a file://
# base, capturing combined output and exit code into RV_OUT / RV_RC.
run_verify() {
  local root="$1"
  set +e
  RV_OUT="$(SPECCRAFT_RELEASE_BASE="file://$root" bash "$SCRIPT" "$VERSION" 2>&1)"
  RV_RC=$?
  set -e
}

# ---------------------------------------------------------------------------
# Scenario A — complete, correct release → exit 0.
# ---------------------------------------------------------------------------
note "scenario A: complete release verifies (exit 0)"
A_ROOT="$TMP/a"
build_fixture "$A_ROOT" >/dev/null
run_verify "$A_ROOT"
if [ "$RV_RC" -ne 0 ]; then
  fail "scenario A: expected exit 0 for a complete release, got $RV_RC:
$RV_OUT"
fi
note "scenario A: ok"

# ---------------------------------------------------------------------------
# Scenario B — a missing tarball → non-zero, names the missing asset.
# ---------------------------------------------------------------------------
note "scenario B: missing tarball fails loudly and names the asset"
B_ROOT="$TMP/b"
B_REL="$(build_fixture "$B_ROOT")"
rm -f "$B_REL/speccraft-$VERSION-macos-arm64.tar.gz"
run_verify "$B_ROOT"
if [ "$RV_RC" -eq 0 ]; then
  fail "scenario B: expected non-zero exit for a missing tarball, got 0:
$RV_OUT"
fi
if ! printf '%s\n' "$RV_OUT" | grep -q "speccraft-$VERSION-macos-arm64.tar.gz"; then
  fail "scenario B: failure must name the missing asset, got:
$RV_OUT"
fi
note "scenario B: ok"

# ---------------------------------------------------------------------------
# Scenario C — corrupted tarball (STRONG-form checksum mismatch) → non-zero.
# ---------------------------------------------------------------------------
note "scenario C: checksum mismatch fails (strong form)"
C_ROOT="$TMP/c"
C_REL="$(build_fixture "$C_ROOT")"
# Corrupt one tarball's bytes AFTER checksums.txt was computed.
printf 'corrupted bytes\n' >> "$C_REL/speccraft-$VERSION-linux-amd64.tar.gz"
run_verify "$C_ROOT"
if [ "$RV_RC" -eq 0 ]; then
  fail "scenario C: expected non-zero exit for a checksum mismatch, got 0:
$RV_OUT"
fi
if ! printf '%s\n' "$RV_OUT" | grep -qiE 'checksum|sha-?256|mismatch'; then
  fail "scenario C: failure must mention a checksum mismatch, got:
$RV_OUT"
fi
note "scenario C: ok"

echo "PASS: verify_release_test.sh"
