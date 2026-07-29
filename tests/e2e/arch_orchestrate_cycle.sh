#!/usr/bin/env bash
# tests/e2e/arch_orchestrate_cycle.sh — hermetic end-to-end for the architect
# conductor (spec 0039). Drives the REAL commands/arch/orchestrate.lib.sh + the
# REAL speccraft-state (ledger-set / reconcile / find-root / set-status) across a
# REAL kind=workspace with two member repos. The only thing mocked is the
# LLM-driven /speccraft:spec:* phase EFFECT (a shell mock that writes/advances the
# member's spec.md).
#
# What this proves that the bats unit tests cannot:
#   1. Design spike #1 — a phase dispatched with cwd scoped to the member resolves
#      the MEMBER's own FindRoot (specs land in <ws>/<member>/specs/, never <ws>/specs/).
#   2. The full happy path: two members driven new→…→validated, ledger advancing,
#      `reconcile` rolling up to done:true when every member spec is `closed`.
#   3. Failure isolation: one member's validate fails → it is `blocked` (in_flight
#      cleared) while its sibling still closes; a clean re-attempt clears `blocked`.
#
# Hermetic: only Go + bash needed. No network, no LLM, no aux agents.
#
# Exit: 0 all assertions passed · 1 setup failed · 2 assertion failed

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK="$(mktemp -d -t arch-orchestrate-cycle.XXXXXX)"
export PATH="$WORK:$PATH"          # so `speccraft-state` resolves to our fresh build
WS="$WORK/workspace"
DESIGN="0001-demo"

cleanup() {
  if [ "${KEEP_E2E:-0}" = "1" ]; then echo "==> Kept: $WORK"; else rm -rf "$WORK"; fi
}
trap cleanup EXIT

fail() { echo "FAIL: $*" >&2; exit 2; }
note() { echo "  $*"; }

# ---- 1. Build the state binary + source the real conductor lib ----
echo "==> Building speccraft-state + sourcing orchestrate.lib.sh..."
( cd "$REPO_ROOT/tools" && go build -o "$WORK/speccraft-state" ./cmd/speccraft-state ) || fail "build failed"
# shellcheck source=/dev/null
source "$REPO_ROOT/commands/arch/orchestrate.lib.sh"

# ---- 2. A kind=workspace with two independent member repos ----
mkdir -p "$WS/.speccraft" "$WS/api/.speccraft" "$WS/web/.speccraft"
printf 'kind = "workspace"\n' > "$WS/.speccraft/speccraft.toml"
# member repos default to kind=repo (empty .speccraft) — each has its own spec stream.

# ---- 3. The mocked phase effect, run CWD-SCOPED inside a member ----
# It resolves the member root via `speccraft-state find-root` (from cwd) — this is
# the spike-#1 crux: if cwd-scoping works, find-root returns the MEMBER, and the
# spec lands in the member repo.
mock_phase() {
  local action="$1" ref="$2" fail_validate="${3:-0}" root spec
  root="$(speccraft-state find-root)"          # cwd-scoped → the member repo
  spec="$root/specs/$ref/spec.md"
  case "$action" in
    new)
      mkdir -p "$(dirname "$spec")"
      printf -- '---\nid: "%s"\nstatus: draft\n---\n# %s\n' "$ref" "$ref" > "$spec" ;;
    review)    speccraft-state set-status "$spec" reviewed ;;
    plan)      speccraft-state set-status "$spec" planned ;;
    implement) speccraft-state set-status "$spec" in-progress ;;
    validate)
      if [ "$fail_validate" = "1" ]; then return 1; fi   # tests-gate fails
      speccraft-state set-status "$spec" closed ;;
    *) return 1 ;;
  esac
}

# ---- 4. Drive one member through the lifecycle using the real lib ----
drive_member() {
  local member="$1" ref="$2" fail_validate="${3:-0}"
  local dir="$WS/${member#./}" pointer="" action code
  ( cd "$WS" && speccraft-state ledger-set "$DESIGN" "$member" spec "" )   # seed row only
  while : ; do
    action="$(orch_next_phase "$pointer")"
    if [ "$action" = "done" ]; then break; fi
    ( cd "$WS" && speccraft-state ledger-set "$DESIGN" "$member" in_flight "$action" )
    if ( cd "$dir" && mock_phase "$action" "$ref" "$fail_validate" ); then code=0; else code=1; fi
    if [ "$action" = "new" ] && [ "$code" = "0" ]; then
      ( cd "$WS" && speccraft-state ledger-set "$DESIGN" "$member" spec "$ref" )
    fi
    orch_apply_result "$WS" "$DESIGN" "$member" "$action" "$code"
    if [ "$code" != "0" ]; then return 1; fi    # blocked — stop driving this member
    pointer="$(orch_completed_token "$action")"
  done
}

# ---- 5. Scenario: api closes cleanly; web's validate fails then retries ----
echo "==> Driving ./api (happy path)..."
drive_member ./api 0001-api 0 || fail "api should have completed"

# spike #1: the api spec landed in the MEMBER repo, not the workspace root.
[ -f "$WS/api/specs/0001-api/spec.md" ] || fail "spike#1: api spec.md not in the member repo"
[ ! -f "$WS/specs/0001-api/spec.md" ]   || fail "spike#1: api spec leaked to the workspace root"
note "spike#1 discharged: cwd-scoped dispatch landed the spec in <ws>/api/specs/"
grep -q '^status: closed$' "$WS/api/specs/0001-api/spec.md" || fail "api spec should be closed"
note "api driven new→…→validated→closed"

echo "==> Driving ./web with a failing validate (failure isolation)..."
drive_member ./web 0001-web 1 && fail "web should have blocked on validate" || note "web blocked as expected"

# reconcile: api done, web blocked, design NOT done (sibling isolation held).
recon="$( cd "$WS" && speccraft-state reconcile "$DESIGN" )"
echo "$recon" | grep -q '^done: false$'                    || fail "reconcile should be done:false while web is blocked"
echo "$recon" | grep -qE '^closed'$'\t''\./api'            || fail "reconcile should show ./api closed"
echo "$recon" | grep -qE '^blocked'$'\t''\./web'           || fail "reconcile should show ./web blocked"
grep -q '^status: closed$' "$WS/api/specs/0001-api/spec.md" || fail "api must stay closed despite web failing"
# in_flight cleared on the failed attempt (a non-executing member never shows in_flight).
grep -q 'in_flight: validate' "$WS/.speccraft/ledger.md" && fail "web in_flight must be cleared after the failed attempt"
note "failure isolation held: ./api closed, ./web blocked, design not done, in_flight cleared"

echo "==> Clean re-attempt of ./web validate (blocked-clear + full rollup)..."
( cd "$WS" && speccraft-state ledger-set "$DESIGN" ./web in_flight validate )
( cd "$WS/web" && mock_phase validate 0001-web 0 ) || fail "web validate retry should pass"
orch_apply_result "$WS" "$DESIGN" ./web validate 0

recon="$( cd "$WS" && speccraft-state reconcile "$DESIGN" )"
echo "$recon" | grep -q '^done: true$'          || fail "reconcile should be done:true after web closes"
echo "$recon" | grep -qE '^closed'$'\t''\./web'  || fail "web should be closed after retry"
grep -q 'blocked: validate failed' "$WS/.speccraft/ledger.md" && fail "web blocked must be cleared on clean retry"
note "web retry cleared blocked + closed; design rolled up to done:true"

echo "==> arch_orchestrate_cycle.sh: ALL PASSED"
