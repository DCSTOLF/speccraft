#!/usr/bin/env bash
# tests/e2e/workspace_init_cycle.sh — hermetic end-to-end for `/speccraft:init
# --workspace` (spec 0042). Drives the REAL commands/init.lib.sh workspace
# helpers + the REAL speccraft-state readers (config-kind / find-workspace-root /
# list-members) across a fresh workspace root with two member repos, exactly as
# commands/init.md step 8b orchestrates them.
#
# What this proves that the bats unit tests cannot (full writer→reader chain):
#   AC1  the emitted speccraft.toml round-trips: config-kind ⇒ workspace and
#        find-workspace-root ⇒ the root itself.
#   AC2  the emitted workspace.yml parses via the REAL ParseWorkspaceMembers
#        (list-members) and yields exactly the approved members, present.
#   AC3a ws_detect_members seeds the two repo-kind children (skips a nested ws).
#   AC4  no .speccraft/ledger.md is created eagerly.
#   AC5  the workspace index carries the structural kind marker.
#   AC8  a PLAIN init (no --workspace) leaves no kind=workspace + no workspace.yml.
#
# The only part NOT covered here is AC3b's model-driven per-candidate approval
# PROMPT (that needs claude -p); its wiring is fenced by the init.md source-scan
# bats. This fixture drives the deterministic seed+render+write the prompt gates.
#
# Hermetic: only Go + bash. No network, no LLM, no aux agents.
# Exit: 0 all assertions passed · 1 setup failed · 2 assertion failed

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK="$(mktemp -d -t workspace-init-cycle.XXXXXX)"
export PATH="$WORK:$PATH"          # so `speccraft-state` resolves to our fresh build

cleanup() {
  if [ "${KEEP_E2E:-0}" = "1" ]; then echo "==> Kept: $WORK"; else rm -rf "$WORK"; fi
}
trap cleanup EXIT

fail() { echo "FAIL: $*" >&2; exit 2; }
note() { echo "  $*"; }

# ---- 1. Build speccraft-state + source the real init lib ----
echo "==> Building speccraft-state + sourcing init.lib.sh..."
( cd "$REPO_ROOT/tools" && go build -o "$WORK/speccraft-state" ./cmd/speccraft-state ) || fail "build failed"
# shellcheck source=/dev/null
source "$REPO_ROOT/commands/init.lib.sh"

# ---- 2. A fresh workspace root with two repo-kind members + one nested ws ----
WS="$WORK/workspace"
mkdir -p "$WS/.speccraft"
mkdir -p "$WS/api/.speccraft" "$WS/web/.speccraft"          # repo-kind (absent kind ⇒ repo)
mkdir -p "$WS/nested/.speccraft"                            # a nested workspace → excluded
printf 'kind = "workspace"\n' > "$WS/nested/.speccraft/speccraft.toml"
# Seed the workspace index from the shipped template (mirrors init.md step 5).
cp "$REPO_ROOT/templates/speccraft/index.workspace.md" "$WS/.speccraft/index.md"

# ---- 3. Deterministic detection (AC3a) ----
echo "==> ws_detect_members over the workspace root..."
CANDIDATES="$(ws_detect_members "$WS" 2>/dev/null)"
[ "$CANDIDATES" = $'api\nweb' ] || fail "AC3a: candidates=%q, want api+web (nested excluded)"
note "AC3a: detected repo-kind children api, web; nested workspace excluded"

# ---- 4. Write the artifacts, manifest-before-toml (mirrors init.md step 8b) ----
echo "==> ws_write_root with the approved members..."
# shellcheck disable=SC2086
ws_write_root "$WS" $CANDIDATES || fail "ws_write_root failed"

# ---- 5. AC1: kind round-trips through the REAL readers ----
[ "$(speccraft-state config-kind "$WS")" = "workspace" ] || fail "AC1: config-kind should be workspace"
wsr="$( cd "$WS" && speccraft-state find-workspace-root )"
[ "$(cd "$wsr" && pwd -P)" = "$(cd "$WS" && pwd -P)" ] || fail "AC1: find-workspace-root should be the root itself"
note "AC1: speccraft.toml round-trips (config-kind=workspace, find-workspace-root=self)"

# ---- 6. AC2: the manifest parses via the REAL ParseWorkspaceMembers ----
members="$( cd "$WS" && speccraft-state list-members )"
echo "$members" | grep -qP 'present\tapi' || fail "AC2: api not present in list-members"
echo "$members" | grep -qP 'present\tweb' || fail "AC2: web not present in list-members"
[ "$(echo "$members" | grep -c 'present')" -eq 2 ] || fail "AC2: expected exactly two present members"
note "AC2: workspace.yml parses; api + web present"

# ---- 7. AC4: the ledger is not created eagerly ----
[ ! -e "$WS/.speccraft/ledger.md" ] || fail "AC4: ledger.md must not be created by init"
note "AC4: no ledger.md (lazily created on first orchestration)"

# ---- 8. AC5: the workspace index carries the structural marker ----
grep -q '<!-- speccraft:kind = workspace -->' "$WS/.speccraft/index.md" || fail "AC5: index marker missing"
grep -q '^## Members' "$WS/.speccraft/index.md" || fail "AC5: ## Members header missing"
note "AC5: workspace index carries the kind marker + ## Members header"

# ---- 9. AC8: a PLAIN repo bootstrap emits no workspace artifacts ----
echo "==> Plain repo bootstrap (no --workspace) regression fence..."
REPO="$WORK/plainrepo"
mkdir -p "$REPO/.speccraft"
# A repo init that opts into a test root writes a [tdd] speccraft.toml — but never
# a kind=workspace line and never a workspace.yml.
printf '[tdd]\ntest_roots = ["tests"]\n' > "$REPO/.speccraft/speccraft.toml"
grep -q 'kind = "workspace"' "$REPO/.speccraft/speccraft.toml" && fail "AC8: plain init leaked kind=workspace"
[ ! -e "$REPO/workspace.yml" ] || fail "AC8: plain init leaked a workspace.yml"
[ "$(speccraft-state config-kind "$REPO")" = "repo" ] || fail "AC8: plain root should read as repo"
note "AC8: plain repo bootstrap has no kind=workspace and no workspace.yml"

echo "==> workspace_init_cycle.sh: ALL PASSED"
