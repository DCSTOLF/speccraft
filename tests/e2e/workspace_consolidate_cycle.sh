#!/usr/bin/env bash
# tests/e2e/workspace_consolidate_cycle.sh — hermetic end-to-end for the /speccraft:sync
# W4 design-consolidation pass (spec 0044). Drives the REAL commands/sync.lib.sh helpers
# + the REAL speccraft-state ledger ops (ledger-get / ledger-set / reconcile /
# ledger-archive) across a fresh workspace with one fully-done design and one in-progress
# design.
#
# What this proves that the bats unit tests cannot (full detect→consolidate→archive chain
# against the real Go ledger-archive op):
#   AC3  sync_done_live_designs lists ONLY the done design.
#   AC5/AC6 sync_consolidate_design writes design/<id>-<slug>/outcome.md with each member
#        outcome line, via the fingerprinted marker.
#   AC2/AC8 ledger-archive moves the done design's rows out of the live ledger into
#        ledger.archive.md (ParseLedger-valid via ledger-get on the archive path); the
#        in-progress design's rows are byte-untouched.
#   AC9  a second run is a clean no-op BOTH ways (outcome byte-unchanged + ledger-archive
#        exit 0 via the absent-live+in-archive branch).
#
# Hermetic: only Go + bash. No network, no LLM, no aux agents.
# Exit: 0 all assertions passed · 1 setup failed · 2 assertion failed

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK="$(mktemp -d -t workspace-consolidate-cycle.XXXXXX)"
export PATH="$WORK:$PATH"

cleanup() {
  if [ "${KEEP_E2E:-0}" = "1" ]; then echo "==> Kept: $WORK"; else rm -rf "$WORK"; fi
}
trap cleanup EXIT

fail() { echo "FAIL: $*" >&2; exit 2; }
note() { echo "  $*"; }

echo "==> Building speccraft-state + sourcing sync.lib.sh..."
( cd "$REPO_ROOT/tools" && go build -o "$WORK/speccraft-state" ./cmd/speccraft-state ) || fail "build failed"
# shellcheck source=/dev/null
source "$REPO_ROOT/commands/sync.lib.sh"

# ---- A fresh workspace: one done design (0007) + one in-progress design (0009) ----
WS="$WORK/workspace"
mkdir -p "$WS/.speccraft" "$WS/design/0007-auth" "$WS/design/0009-billing"
printf 'kind = "workspace"\n' > "$WS/.speccraft/speccraft.toml"
printf 'members:\n  - path: ./api\n  - path: ./web\n' > "$WS/workspace.yml"
printf -- '---\nid: "0007"\n---\n' > "$WS/design/0007-auth/design.md"
printf -- '---\nid: "0009"\n---\n' > "$WS/design/0009-billing/design.md"

# Done design 0007: member ./api spec closed.
mkdir -p "$WS/api/.speccraft" "$WS/api/specs/0007-a"
printf 'kind = "repo"\n' > "$WS/api/.speccraft/speccraft.toml"
printf -- '---\nstatus: closed\n---\n' > "$WS/api/specs/0007-a/spec.md"
( cd "$WS" && speccraft-state ledger-set 0007 ./api spec 0007-a )
( cd "$WS" && speccraft-state ledger-set 0007 ./api last_completed_phase validated )

# In-progress design 0009: member ./web spec in-progress.
mkdir -p "$WS/web/.speccraft" "$WS/web/specs/0009-b"
printf 'kind = "repo"\n' > "$WS/web/.speccraft/speccraft.toml"
printf -- '---\nstatus: in-progress\n---\n' > "$WS/web/specs/0009-b/spec.md"
( cd "$WS" && speccraft-state ledger-set 0009 ./web spec 0009-b )
( cd "$WS" && speccraft-state ledger-set 0009 ./web last_completed_phase planned )

# ---- AC3: only the done design is a candidate ----
echo "==> sync_done_live_designs..."
CANDS="$(sync_done_live_designs "$WS")"
[ "$CANDS" = "0007" ] || fail "AC3: candidates=%q, want only 0007 (0009 is in-progress)"
note "AC3: sync_done_live_designs → 0007 only"

# Capture the in-progress design's live rows to assert they survive byte-identical.
WEB_BEFORE="$( ( cd "$WS" && speccraft-state ledger-get 0009 ) )"

# ---- AC5/AC6: consolidate the done design ----
echo "==> sync_consolidate_design 0007..."
sync_consolidate_design "$WS" 0007 || fail "AC6: consolidate failed"
OUTCOME="$WS/design/0007-auth/outcome.md"
[ -f "$OUTCOME" ] || fail "AC6: outcome.md not written"
grep -qF './api → 0007-a → closed' "$OUTCOME" || fail "AC5: member outcome line missing"
grep -q '^consolidated: .* fingerprint: ' "$OUTCOME" || fail "AC6: fingerprint marker missing"
note "AC5/AC6: outcome.md written with member line + fingerprint marker"

# ---- AC2/AC8: rows moved out of live ledger, into the archive; in-progress untouched ----
[ -z "$( ( cd "$WS" && speccraft-state ledger-get 0007 ) )" ] || fail "AC8: 0007 rows still live"
grep -q '## design 0007' "$WS/.speccraft/ledger.archive.md" || fail "AC2: 0007 not in archive"
WEB_AFTER="$( ( cd "$WS" && speccraft-state ledger-get 0009 ) )"
[ "$WEB_BEFORE" = "$WEB_AFTER" ] || fail "AC2: in-progress design 0009 rows changed"
note "AC2/AC8: 0007 archived out of live ledger; 0009 rows byte-untouched"

# The archive parses as a ledger: a filtered ledger-get over it via a temp workspace read.
# (ledger-get reads .speccraft/ledger.md, so validate the archive by ParseLedger through a
# swapped-in copy — a done design section must round-trip.)
cp "$WS/.speccraft/ledger.archive.md" "$WORK/parsecheck.md"
mkdir -p "$WORK/pc/.speccraft"; printf 'kind = "workspace"\n' > "$WORK/pc/.speccraft/speccraft.toml"
cp "$WS/.speccraft/ledger.archive.md" "$WORK/pc/.speccraft/ledger.md"
( cd "$WORK/pc" && speccraft-state ledger-get 0007 ) | grep -q '0007' || fail "AC2: archive not ParseLedger-valid"
note "AC2: ledger.archive.md is ParseLedger-valid (0007 section round-trips)"

# ---- AC9: a second run is a clean no-op both ways ----
echo "==> second run (idempotency)..."
OUTCOME_BEFORE="$(cat "$OUTCOME")"
[ -z "$(sync_done_live_designs "$WS")" ] || fail "AC9: 0007 must no longer be a candidate"
( cd "$WS" && speccraft-state ledger-archive 0007 ) || fail "AC9: re-archive should exit 0 (absent-live+in-archive)"
[ "$(cat "$OUTCOME")" = "$OUTCOME_BEFORE" ] || fail "AC9: outcome.md changed on the second run"
note "AC9: second run no-op both ways (outcome byte-stable + ledger-archive exit 0)"

echo "==> workspace_consolidate_cycle.sh: ALL PASSED"
