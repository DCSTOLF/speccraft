#!/usr/bin/env bats
# Tests for commands/sync.lib.sh — the deterministic workspace-reconciliation
# helpers backing the /speccraft:sync workspace branch (spec 0043). Pure functions;
# bats is the RED oracle (shell + markdown are not gated by the Go TDD guard). RED
# until commands/sync.lib.sh exists.

setup() {
  PLUGIN_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SYNC_LIB="$PLUGIN_DIR/commands/sync.lib.sh"
  SYNC_MD="$PLUGIN_DIR/commands/sync.md"
  TEST_WS="$(mktemp -d)"
  export PLUGIN_DIR SYNC_LIB SYNC_MD TEST_WS
  if [ ! -x "$PLUGIN_DIR/bin/speccraft-state" ]; then
    ( cd "$PLUGIN_DIR/tools" && go build -o ../bin/speccraft-state ./cmd/speccraft-state )
  fi
  export PATH="$PLUGIN_DIR/bin:$PATH"
}

teardown() { rm -rf "$TEST_WS"; }

# mk_ws — make TEST_WS a kind=workspace root with a members manifest.
mk_ws() {
  mkdir -p "$TEST_WS/.speccraft"
  printf 'kind = "workspace"\n' > "$TEST_WS/.speccraft/speccraft.toml"
  printf 'members:\n%s\n' "$1" > "$TEST_WS/workspace.yml"
}

# mk_member <path> <specRef> <status> — a kind=repo child with a spec at a status.
mk_member() {
  local path="$1" ref="$2" status="$3"
  mkdir -p "$TEST_WS/$path/.speccraft" "$TEST_WS/$path/specs/$ref"
  printf 'kind = "repo"\n' > "$TEST_WS/$path/.speccraft/speccraft.toml"
  printf -- '---\nstatus: %s\n---\n' "$status" > "$TEST_WS/$path/specs/$ref/spec.md"
}

# field <line> <n> — awk-extract the Nth tab field (empty-preserving).
field() { awk -F '\t' -v n="$2" 'NR==1{print $n}' <<<"$1"; }

# --- T3: self-location + defensive 0040 helper contracts ---

@test "sync.lib.sh sources cleanly and exposes reused 0040 helpers" {
  source "$SYNC_LIB"
  run orch_next_phase planned; [ "$status" -eq 0 ]; [ "$output" = "implement" ]
  run ws_detect_members "$TEST_WS"; [ "$status" -eq 0 ]   # sourced from init.lib.sh
}

@test "defensive: pinned 0040 token-machine values sync relies on" {
  source "$SYNC_LIB"
  run orch_next_phase validated; [ "$output" = "done" ]
  run orch_status_token closed;  [ "$output" = "validated" ]
}

# --- T5: status-ahead (AC3) ---

@test "sync_status_ahead: closed status vs planned pointer → validated" {
  source "$SYNC_LIB"
  run sync_status_ahead planned closed
  [ "$status" -eq 0 ]; [ "$output" = "validated" ]
}

@test "sync_status_ahead: status equal to pointer → no advance" {
  source "$SYNC_LIB"
  run sync_status_ahead planned planned   # planned status does not complete 'implement'
  [ "$status" -ne 0 ] || [ -z "$output" ]
}

@test "sync_status_ahead: status behind pointer → no advance" {
  source "$SYNC_LIB"
  run sync_status_ahead implemented reviewed
  [ "$status" -ne 0 ] || [ -z "$output" ]
}

@test "sync_status_ahead: validated pointer → nothing ahead" {
  source "$SYNC_LIB"
  run sync_status_ahead validated closed
  [ "$status" -ne 0 ] || [ -z "$output" ]
}

@test "sync_ledger_drift: status-ahead finding is a 6-field record with the fix tuple" {
  source "$SYNC_LIB"
  run sync_ledger_drift D ./api 0007-a planned "" "" closed 1
  [ "$status" -eq 0 ]
  line="$(grep '^status-ahead' <<<"$output")"
  [ -n "$line" ]
  [ "$(awk -F '\t' 'END{print NF}' <<<"$line")" -eq 6 ]
  [ "$(field "$line" 1)" = "status-ahead" ]
  [ "$(field "$line" 4)" = "last_completed_phase" ]
  [ "$(field "$line" 5)" = "validated" ]
}

@test "sync_ledger_drift: equal pointer emits no status-ahead" {
  source "$SYNC_LIB"
  run sync_ledger_drift D ./api 0007-a validated "" "" closed 1
  [ "$status" -eq 0 ]
  ! grep -q '^status-ahead' <<<"$output"
}

# --- T7: stale-in-flight (AC4) ---

@test "sync_stale_in_flight: completion reflected in status → stale" {
  source "$SYNC_LIB"
  run sync_stale_in_flight implement closed
  [ "$output" = "stale" ]
}

@test "sync_stale_in_flight: phase not yet reflected → live (untouched)" {
  source "$SYNC_LIB"
  run sync_stale_in_flight implement reviewed
  [ "$output" = "live" ]
}

@test "sync_stale_in_flight: malformed in_flight → malformed" {
  source "$SYNC_LIB"
  run sync_stale_in_flight "iteration=2" closed   # '=' token, no phase=
  [ "$output" = "malformed" ]
}

@test "sync_ledger_drift: stale in_flight → clear finding with empty value column" {
  source "$SYNC_LIB"
  run sync_ledger_drift D ./api 0007-a validated implement "" closed 1
  [ "$status" -eq 0 ]
  line="$(grep '^stale-in-flight' <<<"$output")"
  [ -n "$line" ]
  [ "$(awk -F '\t' 'END{print NF}' <<<"$line")" -eq 6 ]
  [ "$(field "$line" 4)" = "in_flight" ]
  [ -z "$(field "$line" 5)" ]   # empty value column preserved
}

@test "sync_ledger_drift: live in_flight emits nothing (live-run-safe)" {
  source "$SYNC_LIB"
  run sync_ledger_drift D ./api 0007-a planned implement "" reviewed 1
  [ "$status" -eq 0 ]
  ! grep -q '^stale-in-flight' <<<"$output"
}

@test "sync_ledger_drift: malformed in_flight → malformed-row advisory (row isolated)" {
  source "$SYNC_LIB"
  run sync_ledger_drift D ./api 0007-a planned "iteration=2" "" closed 1
  [ "$status" -eq 0 ]
  grep -q '^malformed-row' <<<"$output"
}

# --- T9: stale-blocked + dangling-spec (AC5/AC6) ---

@test "sync_ledger_drift: blocked + status-ahead → stale-blocked clear" {
  source "$SYNC_LIB"
  run sync_ledger_drift D ./api 0007-a planned "" waiting closed 1
  grep -q '^stale-blocked' <<<"$output"
  line="$(grep '^stale-blocked' <<<"$output")"
  [ "$(field "$line" 4)" = "blocked" ]
  [ -z "$(field "$line" 5)" ]
}

@test "sync_ledger_drift: blocked without progress → no stale-blocked" {
  source "$SYNC_LIB"
  run sync_ledger_drift D ./api 0007-a validated "" waiting closed 1
  ! grep -q '^stale-blocked' <<<"$output"
}

@test "sync_ledger_drift: unresolved spec ref → dangling-spec advisory" {
  source "$SYNC_LIB"
  run sync_ledger_drift D ./api 0007-a planned "" "" "" 0
  grep -q '^dangling-spec' <<<"$output"
}

@test "sync_ledger_drift: resolved spec ref → no dangling-spec" {
  source "$SYNC_LIB"
  run sync_ledger_drift D ./api 0007-a planned "" "" closed 1
  ! grep -q '^dangling-spec' <<<"$output"
}

# --- T11: membership audit (AC7) ---

@test "sync_membership_audit: missing manifest member → stale-member" {
  source "$SYNC_LIB"
  mk_ws "  - path: ./api"          # listed but not created on disk
  run sync_membership_audit "$TEST_WS"
  grep -q '^stale-member' <<<"$output"
}

@test "sync_membership_audit: kind=repo child absent from manifest → unlisted-member" {
  source "$SYNC_LIB"
  mk_ws "#  - path: none"
  mk_member web 0012-b in-progress   # on disk, not in manifest
  run sync_membership_audit "$TEST_WS"
  grep -q '^unlisted-member' <<<"$output"
}

@test "sync_membership_audit: clean workspace → zero findings" {
  source "$SYNC_LIB"
  mk_ws "  - path: ./api"
  mk_member api 0007-a closed
  run sync_membership_audit "$TEST_WS"
  [ -z "$(printf '%s' "$output" | tr -d '[:space:]')" ]
}

# --- T13: member plan + conflict guard (AC8/AC10) ---

@test "sync_apply_member_plan: all three fixes applied in fixed order, no self-conflict" {
  source "$SYNC_LIB"
  mk_ws "  - path: ./api"
  ( cd "$TEST_WS" && speccraft-state ledger-set D ./api spec 0007-a )
  ( cd "$TEST_WS" && speccraft-state ledger-set D ./api last_completed_phase planned )
  ( cd "$TEST_WS" && speccraft-state ledger-set D ./api in_flight implement )
  ( cd "$TEST_WS" && speccraft-state ledger-set D ./api blocked waiting )
  expected="$( ( cd "$TEST_WS" && speccraft-state ledger-get D ) | awk -F '\t' '$2=="./api"{print; exit}' )"
  run sync_apply_member_plan "$TEST_WS" D ./api "$expected" last_completed_phase=validated in_flight= blocked=
  [ "$status" -eq 0 ]
  ! grep -q '^conflict' <<<"$output"
  row="$( ( cd "$TEST_WS" && speccraft-state ledger-get D ) | awk -F '\t' '$2=="./api"{print; exit}' )"
  [ "$(field "$row" 4)" = "validated" ]
  [ -z "$(field "$row" 5)" ]
  [ -z "$(field "$row" 6)" ]
}

@test "sync_apply_member_plan: row changed since detection → conflict, ledger unchanged" {
  source "$SYNC_LIB"
  mk_ws "  - path: ./api"
  ( cd "$TEST_WS" && speccraft-state ledger-set D ./api spec 0007-a )
  ( cd "$TEST_WS" && speccraft-state ledger-set D ./api last_completed_phase planned )
  expected="$( ( cd "$TEST_WS" && speccraft-state ledger-get D ) | awk -F '\t' '$2=="./api"{print; exit}' )"
  # A conductor advances the row after detection.
  ( cd "$TEST_WS" && speccraft-state ledger-set D ./api last_completed_phase implemented )
  before="$( ( cd "$TEST_WS" && speccraft-state ledger-get D ) )"
  run sync_apply_member_plan "$TEST_WS" D ./api "$expected" last_completed_phase=validated
  [ "$status" -eq 0 ]
  grep -q '^conflict' <<<"$output"
  after="$( ( cd "$TEST_WS" && speccraft-state ledger-get D ) )"
  [ "$before" = "$after" ]   # ledger byte-unchanged
}

# --- T15: sync.md wiring source-scan (AC1/AC8) ---

# line_of <regex> — first 1-based line number matching in sync.md (0 if none).
line_of() { grep -n -E "$1" "$SYNC_MD" | head -1 | cut -d: -f1; }

@test "sync.md: both kind anchors present" {
  grep -qF '<!-- speccraft:sync:repo -->' "$SYNC_MD"
  grep -qF '<!-- speccraft:sync:workspace -->' "$SYNC_MD"
}

@test "sync.md: config-kind/KIND guard precedes both anchors (AC1)" {
  local guard repo ws
  guard="$(line_of 'config-kind|KIND=')"
  repo="$(line_of '<!-- speccraft:sync:repo -->')"
  ws="$(line_of '<!-- speccraft:sync:workspace -->')"
  [ -n "$guard" ] && [ "$guard" -gt 0 ]
  [ "$guard" -lt "$repo" ]
  [ "$guard" -lt "$ws" ]
}

@test "sync.md: workspace helpers appear only after the workspace anchor (AC1)" {
  local ws drift audit
  ws="$(line_of '<!-- speccraft:sync:workspace -->')"
  drift="$(line_of 'sync_ledger_drift')"
  audit="$(line_of 'sync_membership_audit')"
  [ "$drift" -gt "$ws" ]
  [ "$audit" -gt "$ws" ]
}

@test "sync.md: repo-flow steps appear only after the repo anchor (AC1)" {
  local repo scan
  repo="$(line_of '<!-- speccraft:sync:repo -->')"
  scan="$(line_of 'speccraft-drift scan-all')"
  [ "$scan" -gt "$repo" ]
}

@test "sync.md: apply is argv-to-ledger-set, never eval (AC8)" {
  ! grep -qE '(^|[^_[:alnum:]])eval([^_[:alnum:]]|$)' "$SYNC_MD"
  grep -qE 'sync_apply_member_plan|ledger-set' "$SYNC_MD"
}

@test "sync.md: advisory classes are documented reported-only (AC8)" {
  grep -qiE 'advisor(y|ies)' "$SYNC_MD"
  grep -qiE 'fixable|status-ahead|stale-in-flight' "$SYNC_MD"
}
