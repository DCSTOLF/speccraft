#!/usr/bin/env bash
# tests/e2e/arch_close_memory.sh — credit-gated e2e fixture for arch:close
# routing durable decisions through the existing memory-keeper (spec 0022, AC4)
# and clearing ONLY the Architect lane (AC6).
#
# SOURCED by tests/e2e/run.sh from inside the claude -p lifecycle (run_claude,
# LOG_DIR, jq, cmp, and the lib.sh predicates must already be in scope). Defines
# a function the lifecycle calls; no side effects at source time.
#
# STRUCTURAL predicates only — never grep model prose (plan R3). Reuses the
# dated-ADR header SHAPE regex proven by contains_adr_assertion_test.sh. Asserts:
#   CONFIRM path:
#     - history.md gains a dated ADR header (memory-keeper invoked + applied).
#     - architecture.md changes (the proposed diff was applied on confirm).
#     - active_design is cleared; active_spec / active_product are UNTOUCHED (AC6).
#   DECLINE path:
#     - architecture.md AND history.md remain byte-identical (no write on decline).

set -euo pipefail

# ADR header shape — identical to run.sh:[10/13] and contains_adr_assertion_test.sh.
ADR_HEADER_RE="^## 20[0-9]{2}-[0-9]{2}-[0-9]{2}"

arch_close_memory() {
  command -v run_claude >/dev/null 2>&1 \
    || fail "arch_close_memory must be sourced by run.sh (run_claude undefined)"

  # Lanes that must survive an arch:close untouched (lane independence, AC6).
  local SPEC_BEFORE PROD_BEFORE
  SPEC_BEFORE="$(jq -r '.active_spec // "null"' .speccraft/state.json)"
  PROD_BEFORE="$(jq -r '.active_product // "null"' .speccraft/state.json)"

  # ---- CONFIRM path ----
  echo "==> [arch-mem 1/2] /speccraft:arch:new + arch:close (confirm)"
  run_claude "/speccraft:arch:new \"Auth model\". Answers: feasibility='OAuth2 with short-lived JWTs is buildable on the current stack'; components='token issuer, verifier middleware, refresh store'; nfrs='tokens expire in 15m; rotate signing keys quarterly; trade-off: stateless verify vs revocation latency'." arch-mem-01-new.log
  local DESIGN_DIR DESIGN_ID
  DESIGN_DIR="$(find design -maxdepth 1 -name '0001-*' -type d 2>/dev/null | head -1)"
  [ -n "$DESIGN_DIR" ] || fail "arch:new did not create design/0001-*"
  exists "$DESIGN_DIR/design.md"
  DESIGN_ID="$(basename "$DESIGN_DIR")"
  [ "$(jq -r '.active_design // "null"' .speccraft/state.json)" = "$DESIGN_ID" ] \
    || fail "arch:new did not set active_design=$DESIGN_ID"

  # Snapshot the two memory files BEFORE close so "applied on confirm" is provable.
  local SNAP_ARCH SNAP_HIST
  SNAP_ARCH="$(mktemp)"; SNAP_HIST="$(mktemp)"
  cp .speccraft/architecture.md "$SNAP_ARCH"
  cp .speccraft/history.md "$SNAP_HIST"

  run_claude "/speccraft:arch:close. Approve all proposed memory updates." arch-mem-02-close-confirm.log

  # memory-keeper invoked + applied: a dated ADR header now exists in history.md.
  contains_regex ".speccraft/history.md" "$ADR_HEADER_RE"
  # The proposed architecture.md diff was applied on confirm (file changed).
  if cmp -s "$SNAP_ARCH" .speccraft/architecture.md; then
    fail "arch:close (confirm) did not change architecture.md"
  fi
  pass "arch:close (confirm) appended ADR + updated architecture.md"

  # active_design cleared; the other two lanes are byte-identical (AC6).
  [ "$(jq -r '.active_design // "null"' .speccraft/state.json)" = "null" ] \
    || fail "arch:close did not clear active_design"
  [ "$(jq -r '.active_spec // "null"' .speccraft/state.json)" = "$SPEC_BEFORE" ] \
    || fail "arch:close disturbed active_spec (lane independence)"
  [ "$(jq -r '.active_product // "null"' .speccraft/state.json)" = "$PROD_BEFORE" ] \
    || fail "arch:close disturbed active_product (lane independence)"
  pass "arch:close cleared ONLY active_design (spec/product lanes intact)"

  # ---- DECLINE path ----
  echo "==> [arch-mem 2/2] /speccraft:arch:new + arch:close (decline → no write)"
  run_claude "/speccraft:arch:new \"Caching layer\". Answers: feasibility='read-through cache in front of the product DB'; components='cache client, invalidation hook'; nfrs='p99 < 50ms; trade-off: staleness window vs hit rate'." arch-mem-03-new2.log
  local DESIGN2
  DESIGN2="$(find design -maxdepth 1 -name '0002-*' -type d 2>/dev/null | head -1)"
  [ -n "$DESIGN2" ] || fail "second arch:new did not create design/0002-*"

  # Snapshot AFTER the confirm path so the decline assertion is independent.
  cp .speccraft/architecture.md "$SNAP_ARCH"
  cp .speccraft/history.md "$SNAP_HIST"

  run_claude "/speccraft:arch:close. Do NOT apply the proposed memory updates — decline them." arch-mem-04-close-decline.log

  cmp -s "$SNAP_ARCH" .speccraft/architecture.md \
    || fail "arch:close (decline) wrote to architecture.md"
  cmp -s "$SNAP_HIST" .speccraft/history.md \
    || fail "arch:close (decline) wrote to history.md"
  pass "arch:close (decline) left architecture.md + history.md byte-identical"

  rm -f "$SNAP_ARCH" "$SNAP_HIST"
}
