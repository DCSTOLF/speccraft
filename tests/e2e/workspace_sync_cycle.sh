#!/usr/bin/env bash
# tests/e2e/workspace_sync_cycle.sh — hermetic end-to-end for the /speccraft:sync
# WORKSPACE branch (spec 0043). Drives the REAL commands/sync.lib.sh helpers + the
# REAL speccraft-state ledger oracles (ledger-get / ledger-set / reconcile /
# get-status) across a fresh workspace whose member spec was closed OUT OF BAND
# while the ledger pointer was left behind — exactly the drift the workspace sync
# pass exists to reconcile.
#
# What this proves that the bats unit tests cannot (full detect→apply chain against
# the real Go ledger writer):
#   AC2/AC9  ledger-get dumps the stale stored row.
#   AC3/AC4  sync_ledger_drift emits status-ahead + stale-in-flight for the drift.
#   AC8/AC10 sync_apply_member_plan applies the plan through the REAL ledger-set.
#   AC9      the mutation is asserted DIRECTLY via ledger-get (last_completed_phase
#            = validated, in_flight cleared) — NOT only via reconcile — and reconcile
#            then reports done: true.
#
# Hermetic: only Go + bash. No network, no LLM, no aux agents.
# Exit: 0 all assertions passed · 1 setup failed · 2 assertion failed

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK="$(mktemp -d -t workspace-sync-cycle.XXXXXX)"
export PATH="$WORK:$PATH"          # so `speccraft-state` resolves to our fresh build

cleanup() {
  if [ "${KEEP_E2E:-0}" = "1" ]; then echo "==> Kept: $WORK"; else rm -rf "$WORK"; fi
}
trap cleanup EXIT

fail() { echo "FAIL: $*" >&2; exit 2; }
note() { echo "  $*"; }
field() { awk -F '\t' -v n="$2" 'NR==1{print $n}' <<<"$1"; }

# ---- 1. Build speccraft-state + source the real sync lib ----
echo "==> Building speccraft-state + sourcing sync.lib.sh..."
( cd "$REPO_ROOT/tools" && go build -o "$WORK/speccraft-state" ./cmd/speccraft-state ) || fail "build failed"
# shellcheck source=/dev/null
source "$REPO_ROOT/commands/sync.lib.sh"

# ---- 2. A fresh workspace with one member whose spec was closed out of band ----
WS="$WORK/workspace"
mkdir -p "$WS/.speccraft"
printf 'kind = "workspace"\n' > "$WS/.speccraft/speccraft.toml"
printf 'members:\n  - path: ./api\n' > "$WS/workspace.yml"
# The member repo + a spec that is already CLOSED on disk.
mkdir -p "$WS/api/.speccraft" "$WS/api/specs/0007-auth"
printf 'kind = "repo"\n' > "$WS/api/.speccraft/speccraft.toml"
printf -- '---\nstatus: closed\n---\n' > "$WS/api/specs/0007-auth/spec.md"

# The ledger, however, was left behind: pointer at `planned`, `in_flight=implement`,
# and a stale `blocked` marker — as if the conductor crashed mid-implement and the
# developer finished + closed the member by hand.
( cd "$WS" && speccraft-state ledger-set D0001 ./api spec 0007-auth )
( cd "$WS" && speccraft-state ledger-set D0001 ./api last_completed_phase planned )
( cd "$WS" && speccraft-state ledger-set D0001 ./api in_flight implement )
( cd "$WS" && speccraft-state ledger-set D0001 ./api blocked waiting-on-review )

# ---- 3. AC2: ledger-get dumps the stale stored row ----
echo "==> ledger-get dumps the stored (stale) pointer..."
ROW="$( ( cd "$WS" && speccraft-state ledger-get D0001 ) | awk -F '\t' '$2=="./api"{print; exit}' )"
[ "$(field "$ROW" 4)" = "planned" ]  || fail "AC2: stored last_completed_phase should be planned"
[ "$(field "$ROW" 5)" = "implement" ] || fail "AC2: stored in_flight should be implement"
note "AC2: ledger-get shows the stale row (planned / implement / waiting-on-review)"

# ---- 4. AC3/AC4: sync_ledger_drift detects status-ahead + stale-in-flight ----
echo "==> sync_ledger_drift against live member status..."
STATUS="$( ( cd "$WS/api" && speccraft-state get-status 0007-auth ) )"
[ "$STATUS" = "closed" ] || fail "setup: member status should resolve to closed"
FINDINGS="$(sync_ledger_drift D0001 ./api 0007-auth planned implement waiting-on-review "$STATUS" 1)"
grep -q '^status-ahead'    <<<"$FINDINGS" || fail "AC3: expected a status-ahead finding"
grep -q '^stale-in-flight' <<<"$FINDINGS" || fail "AC4: expected a stale-in-flight finding"
grep -q '^stale-blocked'   <<<"$FINDINGS" || fail "AC5: expected a stale-blocked finding"
# The status-ahead fix tuple advances to validated.
AHEAD_LINE="$(grep '^status-ahead' <<<"$FINDINGS")"
[ "$(field "$AHEAD_LINE" 5)" = "validated" ] || fail "AC3: status-ahead should advance to validated"
note "AC3/AC4/AC5: detected status-ahead(→validated) + stale-in-flight + stale-blocked"

# ---- 5. AC8/AC10: apply the per-member plan through the REAL ledger-set ----
echo "==> sync_apply_member_plan (conflict-safe, ordered)..."
APPLY_OUT="$(sync_apply_member_plan "$WS" D0001 ./api "$ROW" \
  last_completed_phase=validated in_flight= blocked=)"
grep -q '^conflict' <<<"$APPLY_OUT" && fail "AC10: unexpected conflict on an unmutated row"
note "AC8/AC10: plan applied without conflict"

# ---- 6. AC9: assert the mutation DIRECTLY via ledger-get (not only reconcile) ----
NEWROW="$( ( cd "$WS" && speccraft-state ledger-get D0001 ) | awk -F '\t' '$2=="./api"{print; exit}' )"
[ "$(field "$NEWROW" 4)" = "validated" ] || fail "AC9: pointer should be validated after apply"
[ -z "$(field "$NEWROW" 5)" ]            || fail "AC9: in_flight should be cleared after apply"
[ -z "$(field "$NEWROW" 6)" ]            || fail "AC9: blocked should be cleared after apply"
note "AC9: ledger-get confirms last_completed_phase=validated, in_flight + blocked cleared"

# ---- 7. AC9: reconcile now reports the design done ----
REC="$( ( cd "$WS" && speccraft-state reconcile D0001 ) )"
grep -q '^done: true' <<<"$REC" || fail "AC9: reconcile should report done: true"
note "AC9: reconcile → done: true"

echo "==> workspace_sync_cycle.sh: ALL PASSED"
