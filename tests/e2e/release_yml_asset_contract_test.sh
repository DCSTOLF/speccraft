#!/usr/bin/env bash
# tests/e2e/release_yml_asset_contract_test.sh — static meta-test pinning
# the producer/consumer asset contract and the deadlock-free placement of
# the release-completeness guard (spec 0021, AC1/AC4).
#
# It greps the live workflow + installer so the producer (release.yml)
# and consumer (install-binaries.sh) cannot silently disagree, and so the
# verify guard cannot drift into a deadlock-prone position.
#
#   - Scenario A: release.yml publishes the checksum asset as
#     `checksums.txt` (and no longer `checksums-merged.txt`), matching
#     what install-binaries.sh fetches. (The original mismatch would
#     re-trigger the source fallback even with a valid release.)
#   - Scenario B: release.yml invokes scripts/verify-release.sh — the
#     primary completeness guard is wired in.
#   - Scenario C (deadlock-freedom): the verify guard lives in the
#     tag-triggered release.yml (so it can only run for an existing tag,
#     never a bare plugin.json bump), it is NOT added to the main-push
#     ci.yml, and install-binaries.sh agrees on `checksums.txt`.
#
# Exit codes: 0 success, 2 on any assertion failure (via lib.sh fail()).
set -euo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$LIB_DIR/lib.sh"

note() { echo "  $*"; }

echo "==> release_yml_asset_contract_test (spec 0021)"

REPO_ROOT="$(cd "$LIB_DIR/../.." && pwd)"
RELEASE_YML="$REPO_ROOT/.github/workflows/release.yml"
CI_YML="$REPO_ROOT/.github/workflows/ci.yml"
INSTALL_SH="$REPO_ROOT/scripts/install-binaries.sh"

exists "$RELEASE_YML"
exists "$CI_YML"
exists "$INSTALL_SH"

# absent <file> <fixed-string> <message> — fail if the string IS present.
absent() {
  if grep -qF -- "$2" "$1"; then
    fail "$3 (unexpectedly found '$2' in $1)"
  fi
  pass "absent $1: $2"
}

# ---------------------------------------------------------------------------
# Scenario A — producer publishes checksums.txt, not checksums-merged.txt.
# ---------------------------------------------------------------------------
note "scenario A: release.yml publishes checksums.txt (not checksums-merged.txt)"
contains "$RELEASE_YML" "checksums.txt"
absent   "$RELEASE_YML" "checksums-merged.txt" \
  "release.yml must publish checksums.txt, not the merged name"
note "scenario A: ok"

# ---------------------------------------------------------------------------
# Scenario B — release.yml wires in the verify-release.sh guard.
# ---------------------------------------------------------------------------
note "scenario B: release.yml invokes verify-release.sh"
contains "$RELEASE_YML" "verify-release.sh"
note "scenario B: ok"

# ---------------------------------------------------------------------------
# Scenario C — deadlock-freedom + consumer agreement.
# ---------------------------------------------------------------------------
note "scenario C: guard is tag-triggered, absent from ci.yml, consumer agrees"
# C1: the guard lives in the tag-triggered workflow (release.yml has a
# `tags:` trigger), so it can only run for an existing tag.
contains_regex "$RELEASE_YML" "^[[:space:]]*tags:"
# C2: the completeness guard is NOT added to the main-push ci.yml, where
# it would fire on a bumped-but-not-yet-released plugin.json (the deadlock).
absent "$CI_YML" "verify-release.sh" \
  "the completeness guard must not run in main-push ci.yml (deadlock risk)"
# C3: the consumer side of the contract — install-binaries.sh fetches
# checksums.txt and not the merged name.
contains "$INSTALL_SH" "checksums.txt"
absent   "$INSTALL_SH" "checksums-merged.txt" \
  "install-binaries.sh must fetch checksums.txt"
note "scenario C: ok"

echo "PASS: release_yml_asset_contract_test.sh"
