#!/usr/bin/env bash
# tests/e2e/pm_to_spec_bridge.sh — credit-gated e2e fixture for the
# spec:new --from / informed-by bridge (spec 0022, AC5).
#
# SOURCED by tests/e2e/run.sh from inside the claude -p lifecycle: run_claude,
# LOG_DIR, jq, and the lib.sh predicates must already be in scope. Unlike the
# self-contained language cycles, the bridge can only be exercised by really
# driving the pm:new / spec:new command bodies through claude, so this fixture
# defines a function the lifecycle calls rather than running in a subshell.
# No side effects at source time.
#
# STRUCTURAL predicates only — never grep model prose (plan R3). Asserts:
#   - pm:new scaffolds a brief and sets active_product WITHOUT touching
#     active_spec (lane independence at the set, AC6-support).
#   - spec:new --from product/<id> emits a NON-EMPTY informed-by key, pulls a
#     non-placeholder Why/What, sets active_spec, and leaves active_product
#     intact (AC5).
#   - plain spec:new emits NO informed-by key — byte-shape parity (AC5).

set -euo pipefail

# section_nonempty <file> <header> — structural: "## <header>" is followed by at
# least one non-blank line that is not a bare `<placeholder>` token. Exit 0 if
# the section carries real content, 1 otherwise. (Never inspects WHAT the words
# are — only that the placeholder was replaced.)
section_nonempty() {
  local file="$1" header="$2"
  awk -v h="## $header" '
    $0 == h { grab=1; next }
    grab && /^## / { exit }
    grab && NF && $0 !~ /^<.*>$/ { found=1; exit }
    END { exit (found ? 0 : 1) }
  ' "$file"
}

# newest_spec_dir <newline-separated-before-list> — echoes the single spec dir
# that appeared since the snapshot. Empty if none/ambiguous.
newest_spec_dir() {
  local before="$1" after
  after="$(ls -d specs/[0-9]* 2>/dev/null | sort || true)"
  comm -13 <(printf '%s\n' "$before") <(printf '%s\n' "$after") | head -1
}

pm_to_spec_bridge() {
  command -v run_claude >/dev/null 2>&1 \
    || fail "pm_to_spec_bridge must be sourced by run.sh (run_claude undefined)"

  echo "==> [bridge 1/3] /speccraft:pm:new"
  run_claude "/speccraft:pm:new \"Checkout revamp\". Answers: why='cart abandonment is high; analytics show 60% drop at payment'; what='streamline checkout to one page; success metric: -20% abandonment'; oos='payment provider migration'." bridge-01-pm-new.log
  local PROD_DIR PROD_ID
  PROD_DIR="$(find product -maxdepth 1 -name '0001-*' -type d 2>/dev/null | head -1)"
  [ -n "$PROD_DIR" ] || fail "pm:new did not create product/0001-*"
  exists "$PROD_DIR/brief.md"
  PROD_ID="$(basename "$PROD_DIR")"

  # active_product set; active_spec untouched at the PM-lane set (lane independence).
  local AP AS
  AP="$(jq -r '.active_product // "null"' .speccraft/state.json)"
  [ "$AP" = "$PROD_ID" ] || fail "active_product not set to $PROD_ID (got '$AP')"
  AS="$(jq -r '.active_spec // "null"' .speccraft/state.json)"
  [ "$AS" = "null" ] || fail "pm:new disturbed active_spec (got '$AS')"
  pass "pm:new set active_product=$PROD_ID; active_spec untouched"

  # --- spec:new --from <brief>: pulls Why/What, writes informed-by ---
  local BEFORE FROM_SPEC
  BEFORE="$(ls -d specs/[0-9]* 2>/dev/null | sort || true)"
  echo "==> [bridge 2/3] /speccraft:spec:new --from product/$PROD_ID"
  run_claude "/speccraft:spec:new \"Implement one-page checkout\" --from product/$PROD_ID" bridge-02-spec-from.log
  FROM_SPEC="$(newest_spec_dir "$BEFORE")"
  [ -n "$FROM_SPEC" ] || fail "spec:new --from did not create a new spec dir"
  exists "$FROM_SPEC/spec.md"
  contains_regex "$FROM_SPEC/spec.md" "^informed-by: \[product/$PROD_ID\]$"
  section_nonempty "$FROM_SPEC/spec.md" Why  || fail "Why section is empty/placeholder in $FROM_SPEC/spec.md"
  section_nonempty "$FROM_SPEC/spec.md" What || fail "What section is empty/placeholder in $FROM_SPEC/spec.md"
  pass "spec:new --from wrote informed-by + non-empty Why/What"

  # active_spec now points at the bridged spec; active_product is untouched.
  AS="$(jq -r '.active_spec // "null"' .speccraft/state.json)"
  [ "$AS" = "$(basename "$FROM_SPEC")" ] || fail "active_spec not set to bridged spec (got '$AS')"
  AP="$(jq -r '.active_product // "null"' .speccraft/state.json)"
  [ "$AP" = "$PROD_ID" ] || fail "spec:new --from disturbed active_product (got '$AP', want '$PROD_ID')"
  pass "spec:new --from set active_spec; active_product intact (lane independence)"

  # --- plain spec:new: NO informed-by key (byte-shape parity, AC5) ---
  BEFORE="$(ls -d specs/[0-9]* 2>/dev/null | sort || true)"
  echo "==> [bridge 3/3] /speccraft:spec:new (plain — no --from)"
  run_claude "/speccraft:spec:new \"Add request id logging\". Answers: why='trace requests across services'; what='attach a request id to every log line'; AC='1) every log line carries a request id 2) id propagates across calls 3) test covers propagation'; oos='distributed tracing backend'; questions=none." bridge-03-spec-plain.log
  local PLAIN_SPEC
  PLAIN_SPEC="$(newest_spec_dir "$BEFORE")"
  [ -n "$PLAIN_SPEC" ] || fail "plain spec:new did not create a new spec dir"
  exists "$PLAIN_SPEC/spec.md"
  # Inverted assertion (per contains_adr_assertion_test.sh): contains_regex must
  # FAIL on a plain spec. A succeeding subshell means the key leaked in.
  if ( contains_regex "$PLAIN_SPEC/spec.md" "^informed-by:" ) >/dev/null 2>&1; then
    fail "plain spec:new unexpectedly wrote an informed-by key in $PLAIN_SPEC/spec.md"
  fi
  pass "plain spec:new has no informed-by key (byte-shape parity)"
}
