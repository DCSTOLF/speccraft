#!/usr/bin/env bash
# tests/e2e/install_binaries_provenance_test.sh — sibling fixture pinning
# scripts/install-binaries.sh download/fallback/provenance behavior and
# scripts/doctor.sh's reporting of it (spec 0021, AC2/AC3).
#
# The installer is run inside a throwaway plugin dir (a copy of the
# script + a fixture plugin.json), so the real repo's bin/ and
# .binary-version are never touched. SPECCRAFT_RELEASE_BASE points the
# download at a local file:// fixture (or a deliberately-broken base), so
# no network or real GitHub release is needed.
#
#   - Scenario A (download happy path, AC2): a valid file:// release +
#     a PATH with `go` removed → exit 0, binaries extracted,
#     .binary-provenance == "download", and no source build was needed.
#   - Scenario B (failed download is loud + falls back, AC3): an
#     unreachable base with a (stub) `go` available → the failed URL is
#     named on stderr before the fallback, exit 0, .binary-provenance ==
#     "source".
#   - Scenario C (doctor reports the distinct state, AC3): with
#     .binary-provenance == "source", doctor.sh surfaces a distinct
#     "built from source (download unavailable)" diagnostic.
#
# Exit codes: 0 success, 2 on any assertion failure (via lib.sh fail()).
set -euo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$LIB_DIR/lib.sh"

note() { echo "  $*"; }

echo "==> install_binaries_provenance_test (spec 0021)"

REPO_ROOT="$(cd "$LIB_DIR/../.." && pwd)"
VERSION="9.9.9"
PLATFORMS="linux-amd64 linux-arm64 macos-amd64 macos-arm64"

TMP="$(mktemp -d -t install-prov-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

# make_nogo_path — echo a copy of $PATH with every directory that
# contains a `go` executable removed, so `command -v go` fails for a
# child process. Used to prove the download happy path needs no Go.
make_nogo_path() {
  local out="" d
  local saved_ifs="$IFS"
  IFS=':'
  for d in $PATH; do
    [ -n "$d" ] || continue
    [ -x "$d/go" ] && continue
    out="${out:+$out:}$d"
  done
  IFS="$saved_ifs"
  echo "$out"
}

# build_release_fixture <root> — create <root>/v<VERSION>/ with the four
# platform tarballs (each holding the three helper binaries) plus a
# checksums.txt computed over them. Echoes the base <root>.
build_release_fixture() {
  local root="$1" rel stage plat
  rel="$root/v$VERSION"; mkdir -p "$rel"
  stage="$root/stage"; mkdir -p "$stage"
  printf '#!/bin/sh\necho state\n' > "$stage/speccraft-state"
  printf '#!/bin/sh\necho guard\n' > "$stage/speccraft-guard"
  printf '#!/bin/sh\necho drift\n' > "$stage/speccraft-drift"
  for plat in $PLATFORMS; do
    tar -czf "$rel/speccraft-$VERSION-$plat.tar.gz" -C "$stage" \
      speccraft-state speccraft-guard speccraft-drift
  done
  ( cd "$rel" && sha256sum speccraft-"$VERSION"-*.tar.gz > checksums.txt )
  echo "$root"
}

# setup_plugin <dir> — a throwaway plugin tree: copies of the scripts
# under test, a fixture plugin.json at VERSION, empty bin/ + tools/.
setup_plugin() {
  local pdir="$1"
  mkdir -p "$pdir/scripts" "$pdir/bin" "$pdir/.claude-plugin" "$pdir/tools"
  cp "$REPO_ROOT/scripts/install-binaries.sh" "$pdir/scripts/"
  cp "$REPO_ROOT/scripts/doctor.sh" "$pdir/scripts/"
  printf '{\n  "version": "%s"\n}\n' "$VERSION" > "$pdir/.claude-plugin/plugin.json"
}

# ---------------------------------------------------------------------------
# Scenario A — download happy path, no Go on PATH.
# ---------------------------------------------------------------------------
note "scenario A: download happy path needs no Go (.binary-provenance=download)"
PDIR_A="$TMP/plugin-a"; setup_plugin "$PDIR_A"
BASE_A="$(build_release_fixture "$TMP/rel-a")"
NOGO="$(make_nogo_path)"
# Sanity: the scrubbed PATH must still expose the installer's own tools,
# else a failure below would be misattributed. Fail loudly if not.
for t in curl jq tar sha256sum uname mktemp; do
  PATH="$NOGO" command -v "$t" >/dev/null 2>&1 \
    || fail "scenario A precondition: '$t' missing from scrubbed PATH"
done
PATH="$NOGO" command -v go >/dev/null 2>&1 \
  && fail "scenario A precondition: 'go' should be absent from scrubbed PATH"

set +e
OUT_A="$(PATH="$NOGO" SPECCRAFT_RELEASE_BASE="file://$BASE_A" \
  bash "$PDIR_A/scripts/install-binaries.sh" 2>&1)"
RC_A=$?
set -e
if [ "$RC_A" -ne 0 ]; then
  fail "scenario A: expected exit 0 from download path, got $RC_A:
$OUT_A"
fi
exists "$PDIR_A/bin/speccraft-state"
if [ ! -f "$PDIR_A/.binary-provenance" ] \
   || [ "$(cat "$PDIR_A/.binary-provenance")" != "download" ]; then
  fail "scenario A: expected .binary-provenance=download, got: $(cat "$PDIR_A/.binary-provenance" 2>/dev/null || echo '<absent>')
$OUT_A"
fi
note "scenario A: ok"

# ---------------------------------------------------------------------------
# Scenario B — failed download is loud, then falls back to source build.
# ---------------------------------------------------------------------------
note "scenario B: failed download names URL and falls back (.binary-provenance=source)"
PDIR_B="$TMP/plugin-b"; setup_plugin "$PDIR_B"
# Stub `go` so the source-build fallback runs fast and hermetically.
mkdir -p "$TMP/fakebin"
cat > "$TMP/fakebin/go" <<'GOSTUB'
#!/usr/bin/env bash
# Minimal `go build -o OUT PKG` stand-in: just create OUT.
out=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    *)  shift ;;
  esac
done
if [ -n "$out" ]; then printf '#!/bin/sh\necho stub\n' > "$out"; chmod +x "$out"; fi
exit 0
GOSTUB
chmod +x "$TMP/fakebin/go"
BADBASE="file://$TMP/no-such-release-dir"

set +e
OUT_B="$(PATH="$TMP/fakebin:$PATH" SPECCRAFT_RELEASE_BASE="$BADBASE" \
  bash "$PDIR_B/scripts/install-binaries.sh" 2>&1)"
RC_B=$?
set -e
if [ "$RC_B" -ne 0 ]; then
  fail "scenario B: expected exit 0 via source fallback, got $RC_B:
$OUT_B"
fi
if ! printf '%s\n' "$OUT_B" | grep -q "speccraft-$VERSION-"; then
  fail "scenario B: failed download must name the asset URL on stderr, got:
$OUT_B"
fi
if ! printf '%s\n' "$OUT_B" | grep -qiE 'download|unavailable|fail|from source'; then
  fail "scenario B: fallback must be announced (not silent), got:
$OUT_B"
fi
if [ ! -f "$PDIR_B/.binary-provenance" ] \
   || [ "$(cat "$PDIR_B/.binary-provenance")" != "source" ]; then
  fail "scenario B: expected .binary-provenance=source, got: $(cat "$PDIR_B/.binary-provenance" 2>/dev/null || echo '<absent>')
$OUT_B"
fi
note "scenario B: ok"

# ---------------------------------------------------------------------------
# Scenario C — doctor reports the distinct source-fallback state.
# ---------------------------------------------------------------------------
note "scenario C: doctor surfaces the distinct 'built from source' state"
PDIR_C="$TMP/plugin-c"; setup_plugin "$PDIR_C"
for b in speccraft-state speccraft-guard speccraft-drift; do
  printf '#!/bin/sh\n' > "$PDIR_C/bin/$b"; chmod +x "$PDIR_C/bin/$b"
done
echo "$VERSION" > "$PDIR_C/.binary-version"
echo "source"   > "$PDIR_C/.binary-provenance"

set +e
OUT_C="$(bash "$PDIR_C/scripts/doctor.sh" 2>&1)"
set -e
if ! printf '%s\n' "$OUT_C" | grep -qi 'built from source'; then
  fail "scenario C: doctor must report a 'built from source' state, got:
$OUT_C"
fi
if ! printf '%s\n' "$OUT_C" | grep -qi 'download unavailable'; then
  fail "scenario C: the source state must note the download was unavailable, got:
$OUT_C"
fi
note "scenario C: ok"

echo "PASS: install_binaries_provenance_test.sh"
