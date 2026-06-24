#!/usr/bin/env bats
# Tests for commands/spec/consolidate.lib.sh — the deterministic tier of spec 0025
# (Spec consolidation into current domain specs on close, ACs 1-6 + CF-1..CF-3).
#
# Pure bash helpers, no side effects at source time — mirrors the
# commands/spec/revise.lib.sh + commands/history/compact.lib.sh colocation
# convention. The lib is SOURCED by commands/spec/close.md (inline-at-close) and
# commands/sync.md (backfill), and by this suite at test time.

setup() {
  PLUGIN_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  LIB="$PLUGIN_DIR/commands/spec/consolidate.lib.sh"
  TEST_REPO="$(mktemp -d)"

  # --- domain fixture (specs/domains/guard.md) ---
  DOM="$TEST_REPO/specs/domains/guard.md"
  mkdir -p "$(dirname "$DOM")"
  cat > "$DOM" <<'EOF'
# Guard domain

- close clears active_spec to "" (spec 0012)
- state uses a sentinel string for cleared active_spec (spec 0012)
- the guard fails closed on an unresolved runner (spec 0018)
EOF

  # --- closing-spec fixture with a well-formed delta block ---
  SPEC="$TEST_REPO/specs/0099-demo/spec.md"
  mkdir -p "$(dirname "$SPEC")"
  cat > "$SPEC" <<'EOF'
---
id: "0099"
title: "Demo Consolidation Spec"
status: closed
created: 2026-06-01
domains: [guard]
delta:
  - ADD: pre-tool-use hook gates the Write tool (spec 0099)
  - MODIFY: state uses omitempty sibling keys (spec 0099)
    locator: state uses a sentinel string for cleared active_spec
  - REMOVE:
    locator: the guard fails closed on an unresolved runner
---

# body
EOF
}

teardown() { rm -rf "$TEST_REPO"; }

# ---------------------------------------------------------------------------
# AC1 — consolidate_parse_delta
# ---------------------------------------------------------------------------

@test "consolidate_parse_delta: well-formed block parses ordered ADD/MODIFY/REMOVE" {
  source "$LIB"
  run consolidate_parse_delta "$SPEC"
  [ "$status" -eq 0 ]
  [ "${lines[0]%%$'\t'*}" = "ADD" ]
  [ "${lines[1]%%$'\t'*}" = "MODIFY" ]
  [ "${lines[2]%%$'\t'*}" = "REMOVE" ]
  [ "${#lines[@]}" -eq 3 ]
}

@test "consolidate_parse_delta: ADD entry carries no locator" {
  source "$LIB"
  run consolidate_parse_delta "$SPEC"
  [ "$status" -eq 0 ]
  # record is OP \t LOCATOR \t TEXT — ADD's locator field is empty
  local loc
  loc="$(printf '%s\n' "${lines[0]}" | cut -f2)"
  [ -z "$loc" ]
  local txt
  txt="$(printf '%s\n' "${lines[0]}" | cut -f3)"
  [ "$txt" = "pre-tool-use hook gates the Write tool (spec 0099)" ]
}

@test "consolidate_parse_delta: MODIFY carries its locator and new text" {
  source "$LIB"
  run consolidate_parse_delta "$SPEC"
  [ "$status" -eq 0 ]
  local loc txt
  loc="$(printf '%s\n' "${lines[1]}" | cut -f2)"
  txt="$(printf '%s\n' "${lines[1]}" | cut -f3)"
  [ "$loc" = "state uses a sentinel string for cleared active_spec" ]
  [ "$txt" = "state uses omitempty sibling keys (spec 0099)" ]
}

@test "consolidate_parse_delta: MODIFY without a locator is a malformed-block rejection (no output)" {
  source "$LIB"
  local bad="$TEST_REPO/specs/0098-bad/spec.md"; mkdir -p "$(dirname "$bad")"
  cat > "$bad" <<'EOF'
---
id: "0098"
delta:
  - MODIFY: new text (spec 0098)
---
EOF
  run consolidate_parse_delta "$bad"
  [ "$status" -ne 0 ]
  # no parsed record emitted on stdout (records are TAB-separated; the stderr
  # diagnostic that bats merges into $output carries no TAB)
  ! printf '%s' "$output" | grep -q $'\t'
}

@test "consolidate_parse_delta: REMOVE without a locator is a malformed-block rejection (no output)" {
  source "$LIB"
  local bad="$TEST_REPO/specs/0097-bad/spec.md"; mkdir -p "$(dirname "$bad")"
  cat > "$bad" <<'EOF'
---
id: "0097"
delta:
  - REMOVE:
---
EOF
  run consolidate_parse_delta "$bad"
  [ "$status" -ne 0 ]
  ! printf '%s' "$output" | grep -q $'\t'
}

@test "consolidate_parse_delta: a suffix-less ADD text still parses (empty provenance, not an error)" {
  source "$LIB"
  local s="$TEST_REPO/specs/0096-nosuffix/spec.md"; mkdir -p "$(dirname "$s")"
  cat > "$s" <<'EOF'
---
id: "0096"
delta:
  - ADD: a requirement with no provenance suffix
---
EOF
  run consolidate_parse_delta "$s"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
  [ "$(printf '%s\n' "${lines[0]}" | cut -f3)" = "a requirement with no provenance suffix" ]
}

# ---------------------------------------------------------------------------
# AC1 — consolidate_locator_match (the deterministic seed of the model heuristic)
# ---------------------------------------------------------------------------

@test "consolidate_locator_match: unique match ignores trailing (spec NNNN) suffix + whitespace" {
  source "$LIB"
  run consolidate_locator_match "$DOM" "  state uses a sentinel string for cleared active_spec  "
  [ "$status" -eq 0 ]
  [ "$output" = "- state uses a sentinel string for cleared active_spec (spec 0012)" ]
}

@test "consolidate_locator_match: zero matches → conflict signal (non-zero, no apply)" {
  source "$LIB"
  run consolidate_locator_match "$DOM" "a requirement that does not exist"
  [ "$status" -ne 0 ]
}

@test "consolidate_locator_match: >1 matches → conflict signal (non-zero)" {
  source "$LIB"
  printf -- '- duplicated requirement line (spec 0001)\n- duplicated requirement line (spec 0002)\n' >> "$DOM"
  run consolidate_locator_match "$DOM" "duplicated requirement line"
  [ "$status" -ne 0 ]
}

@test "consolidate_locator_match: the provenance suffix is never the match key" {
  source "$LIB"
  # locator carries a DIFFERENT suffix than the domain line — still matches on text
  run consolidate_locator_match "$DOM" "state uses a sentinel string for cleared active_spec (spec 9999)"
  [ "$status" -eq 0 ]
  [ "$output" = "- state uses a sentinel string for cleared active_spec (spec 0012)" ]
}

# ---------------------------------------------------------------------------
# AC2 — consolidate_routing_seed
# ---------------------------------------------------------------------------

@test "consolidate_routing_seed: explicit frontmatter domains: are authoritative" {
  source "$LIB"
  run consolidate_routing_seed "$SPEC"
  [ "$status" -eq 0 ]
  [ "$output" = "guard" ]
}

@test "consolidate_routing_seed: absent domains: → a deterministic seeded area key, stable across runs" {
  source "$LIB"
  local s="$TEST_REPO/specs/0095-release-pipeline/spec.md"; mkdir -p "$(dirname "$s")"
  cat > "$s" <<'EOF'
---
id: "0095"
title: "Release Pipeline Hardening"
status: closed
---
EOF
  run consolidate_routing_seed "$s"
  [ "$status" -eq 0 ]
  local first="$output"
  run consolidate_routing_seed "$s"
  [ "$output" = "$first" ]
  [ -n "$first" ]
}

# ---------------------------------------------------------------------------
# AC3 — consolidate_archiveB_append (self-describing header + full-entry dedup)
# ---------------------------------------------------------------------------

@test "consolidate_archiveB_append: writes self-describing header then verbatim suffix-bearing text; creates file" {
  source "$LIB"
  local arc="$TEST_REPO/specs/domains/.archive/guard.md"
  printf '## guard | spec 0099 | MODIFY\n- state uses a sentinel string for cleared active_spec (spec 0012)\n' \
    | consolidate_archiveB_append "$arc"
  [ -f "$arc" ]
  grep -qF '## guard | spec 0099 | MODIFY' "$arc"
  grep -qF -- '- state uses a sentinel string for cleared active_spec (spec 0012)' "$arc"
}

@test "consolidate_archiveB_append: full-entry byte-match dedup — identical re-run is a no-op" {
  source "$LIB"
  local arc="$TEST_REPO/specs/domains/.archive/guard.md"
  local entry='## guard | spec 0099 | MODIFY
- state uses a sentinel string for cleared active_spec (spec 0012)'
  printf '%s\n' "$entry" | consolidate_archiveB_append "$arc"
  printf '%s\n' "$entry" | consolidate_archiveB_append "$arc"
  [ "$(grep -cF '## guard | spec 0099 | MODIFY' "$arc")" -eq 1 ]
}

@test "consolidate_archiveB_append: two events with byte-identical payloads but different headers both persist" {
  source "$LIB"
  local arc="$TEST_REPO/specs/domains/.archive/guard.md"
  printf '## guard | spec 0099 | MODIFY\n- shared payload line (spec 0012)\n' | consolidate_archiveB_append "$arc"
  printf '## guard | spec 0100 | REMOVE\n- shared payload line (spec 0012)\n' | consolidate_archiveB_append "$arc"
  [ "$(grep -cF -- '- shared payload line (spec 0012)' "$arc")" -eq 2 ]
}

@test "consolidate_archiveB_append: nothing on stdin writes no file (blast radius)" {
  source "$LIB"
  local arc="$TEST_REPO/specs/domains/.archive/guard.md"
  printf '' | consolidate_archiveB_append "$arc"
  [ ! -f "$arc" ]
}

# ---------------------------------------------------------------------------
# AC6 / CF-1 — consolidate_apply_delta (idempotent writes, pinned write order)
# ---------------------------------------------------------------------------

@test "consolidate_apply_delta: ADD appends with suffix; dedups by normalized text + provenance" {
  source "$LIB"
  local arc="$TEST_REPO/specs/domains/.archive/guard.md"
  consolidate_apply_delta "$DOM" "$arc" guard 0099 ADD "" "pre-tool-use hook gates the Write tool (spec 0099)"
  [ "$(grep -cF -- 'pre-tool-use hook gates the Write tool (spec 0099)' "$DOM")" -eq 1 ]
  # idempotent re-run does not duplicate
  consolidate_apply_delta "$DOM" "$arc" guard 0099 ADD "" "pre-tool-use hook gates the Write tool (spec 0099)"
  [ "$(grep -cF -- 'pre-tool-use hook gates the Write tool (spec 0099)' "$DOM")" -eq 1 ]
}

@test "consolidate_apply_delta: MODIFY replaces unique line, appends modifying id, archives superseded text" {
  source "$LIB"
  local arc="$TEST_REPO/specs/domains/.archive/guard.md"
  consolidate_apply_delta "$DOM" "$arc" guard 0099 MODIFY \
    "state uses a sentinel string for cleared active_spec" \
    "state uses omitempty sibling keys (spec 0099)"
  # new text present
  grep -qF -- 'state uses omitempty sibling keys' "$DOM"
  # old line gone from the domain file
  ! grep -qF -- 'state uses a sentinel string for cleared active_spec (spec 0012)' "$DOM"
  # superseded text archived (suffix intact) under a self-describing header
  grep -qF -- '- state uses a sentinel string for cleared active_spec (spec 0012)' "$arc"
  grep -qE '^## guard \| spec 0099 \| MODIFY' "$arc"
}

@test "consolidate_apply_delta: REMOVE deletes unique line and archives its text" {
  source "$LIB"
  local arc="$TEST_REPO/specs/domains/.archive/guard.md"
  consolidate_apply_delta "$DOM" "$arc" guard 0099 REMOVE \
    "the guard fails closed on an unresolved runner" ""
  ! grep -qF -- 'the guard fails closed on an unresolved runner' "$DOM"
  grep -qF -- '- the guard fails closed on an unresolved runner (spec 0018)' "$arc"
}

@test "consolidate_apply_delta: MODIFY/REMOVE whose locator is already absent is a no-op" {
  source "$LIB"
  local arc="$TEST_REPO/specs/domains/.archive/guard.md"
  run consolidate_apply_delta "$DOM" "$arc" guard 0099 REMOVE "a line that is not present" ""
  [ "$status" -eq 0 ]
  [ ! -f "$arc" ] || [ "$(grep -c '^## ' "$arc")" -eq 0 ]
}

@test "CF-1 crash window (a): re-run after archive-B append but before domain mutation" {
  source "$LIB"
  local arc="$TEST_REPO/specs/domains/.archive/guard.md"
  # simulate the crash: archive-B step ran (entry present), domain NOT yet mutated
  printf '## guard | spec 0099 | MODIFY\n- state uses a sentinel string for cleared active_spec (spec 0012)\n' \
    | consolidate_archiveB_append "$arc"
  # re-run the full apply
  consolidate_apply_delta "$DOM" "$arc" guard 0099 MODIFY \
    "state uses a sentinel string for cleared active_spec" \
    "state uses omitempty sibling keys (spec 0099)"
  # exactly one archive-B entry (full-entry dedup), mutation applied once
  [ "$(grep -cE '^## guard \| spec 0099 \| MODIFY' "$arc")" -eq 1 ]
  grep -qF -- 'state uses omitempty sibling keys' "$DOM"
  ! grep -qF -- 'state uses a sentinel string for cleared active_spec (spec 0012)' "$DOM"
}

@test "CF-1 crash window (b): re-run after domain mutation but before dir-move" {
  source "$LIB"
  local arc="$TEST_REPO/specs/domains/.archive/guard.md"
  consolidate_apply_delta "$DOM" "$arc" guard 0099 MODIFY \
    "state uses a sentinel string for cleared active_spec" \
    "state uses omitempty sibling keys (spec 0099)"
  # re-run: locator now absent → no-op, archive-B dedups
  consolidate_apply_delta "$DOM" "$arc" guard 0099 MODIFY \
    "state uses a sentinel string for cleared active_spec" \
    "state uses omitempty sibling keys (spec 0099)"
  [ "$(grep -cE '^## guard \| spec 0099 \| MODIFY' "$arc")" -eq 1 ]
  [ "$(grep -cF -- 'state uses omitempty sibling keys' "$DOM")" -eq 1 ]
}

# ---------------------------------------------------------------------------
# AC4 — consolidate_blast_radius_ok
# ---------------------------------------------------------------------------

@test "consolidate_blast_radius_ok: accepts the allow-listed targets" {
  source "$LIB"
  run consolidate_blast_radius_ok "specs/domains/guard.md";                       [ "$status" -eq 0 ]
  run consolidate_blast_radius_ok "specs/domains/.archive/guard.md";              [ "$status" -eq 0 ]
  run consolidate_blast_radius_ok "specs/.archive/0099-demo/spec.md";             [ "$status" -eq 0 ]
  run consolidate_blast_radius_ok "specs/0099-demo/consolidation-conflicts.md";   [ "$status" -eq 0 ]
  run consolidate_blast_radius_ok "specs/0099-demo/consolidation-skip";           [ "$status" -eq 0 ]
}

@test "consolidate_blast_radius_ok: rejects memory files and other spec dirs" {
  source "$LIB"
  run consolidate_blast_radius_ok ".speccraft/history.md";        [ "$status" -ne 0 ]
  run consolidate_blast_radius_ok ".speccraft/conventions.md";    [ "$status" -ne 0 ]
  run consolidate_blast_radius_ok ".speccraft/architecture.md";   [ "$status" -ne 0 ]
  run consolidate_blast_radius_ok "specs/0099-demo/spec.md";      [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# AC5 / AC6 / AC8 / CF-2 — domain invariants, conflict file, dir-move
# ---------------------------------------------------------------------------

@test "consolidate_assert_domain_invariants: every requirement line carries a provenance suffix" {
  source "$LIB"
  run consolidate_assert_domain_invariants "$DOM"
  [ "$status" -eq 0 ]
  # a line missing a suffix fails the assertion
  printf -- '- a requirement with no provenance suffix\n' >> "$DOM"
  run consolidate_assert_domain_invariants "$DOM"
  [ "$status" -ne 0 ]
}

@test "consolidate_skill_excludes_archives: neither .archive tree may appear in the load list" {
  source "$LIB"
  local good="$TEST_REPO/SKILL.md"
  printf 'load: specs/domains/%s\n' '<area>.md' > "$good"
  run consolidate_skill_excludes_archives "$good"; [ "$status" -eq 0 ]
  local bad="$TEST_REPO/SKILL-bad.md"
  printf 'load: specs/.archive/\n' > "$bad"
  run consolidate_skill_excludes_archives "$bad"; [ "$status" -ne 0 ]
  printf 'load: specs/domains/.archive/\n' > "$bad"
  run consolidate_skill_excludes_archives "$bad"; [ "$status" -ne 0 ]
}

@test "consolidate_record_conflict / clear_conflict: write then remove the sink inside the spec dir" {
  source "$LIB"
  local sd="$TEST_REPO/specs/0099-demo"
  consolidate_record_conflict "$sd" "MODIFY locator matched 0 lines"
  [ -f "$sd/consolidation-conflicts.md" ]
  consolidate_clear_conflict "$sd"
  [ ! -f "$sd/consolidation-conflicts.md" ]
}

@test "consolidate_archive_dir_move: MOVE not delete; refuses while a conflict file exists; status stays closed" {
  source "$LIB"
  local sd="$TEST_REPO/specs/0099-demo"
  local archive_parent="$TEST_REPO/specs/.archive"
  # refuses while a conflict is open
  consolidate_record_conflict "$sd" "open"
  run consolidate_archive_dir_move "$sd" "$archive_parent"
  [ "$status" -ne 0 ]
  [ -d "$sd" ]
  # resolve → move succeeds, source gone, dest present, status unchanged
  consolidate_clear_conflict "$sd"
  run consolidate_archive_dir_move "$sd" "$archive_parent"
  [ "$status" -eq 0 ]
  [ ! -d "$sd" ]
  [ -d "$archive_parent/0099-demo" ]
  grep -qE '^status: closed' "$archive_parent/0099-demo/spec.md"
}

# ---------------------------------------------------------------------------
# AC11 / CF-3 — backfill predicate, history.md-order replay, marker state machine
# ---------------------------------------------------------------------------

@test "consolidate_backfill_candidates: closed AND under specs/ AND no skip marker; excludes archived/skip" {
  source "$LIB"
  # closed candidate (the 0099 fixture is status: closed)
  # an open (non-closed) spec — excluded
  local open="$TEST_REPO/specs/0090-open/spec.md"; mkdir -p "$(dirname "$open")"
  printf -- '---\nid: "0090"\nstatus: in-progress\n---\n' > "$open"
  # a closed-but-skipped spec — excluded
  local skip="$TEST_REPO/specs/0091-skip/spec.md"; mkdir -p "$(dirname "$skip")"
  printf -- '---\nid: "0091"\nstatus: closed\n---\n' > "$skip"
  touch "$TEST_REPO/specs/0091-skip/consolidation-skip"
  # an already-archived spec — excluded (lives under specs/.archive/)
  local arch="$TEST_REPO/specs/.archive/0092-done/spec.md"; mkdir -p "$(dirname "$arch")"
  printf -- '---\nid: "0092"\nstatus: closed\n---\n' > "$arch"
  run consolidate_backfill_candidates "$TEST_REPO"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qx "0099-demo"
  ! printf '%s\n' "$output" | grep -qx "0090-open"
  ! printf '%s\n' "$output" | grep -qx "0091-skip"
  ! printf '%s\n' "$output" | grep -qx "0092-done"
}

# ---------------------------------------------------------------------------
# AC2 (spec 0028) — the EXECUTABLE per-leg corpus-state table.
# Each case reconstructs the exact corpus the spec_consolidate.sh fixture builds
# for that leg (seeded-under-specs/ / skip-marked / archived sets, per the spec's
# corpus-state table) and asserts consolidate_backfill_candidates returns EXACTLY
# the intended singleton. A fixture-SEEDING regression (the 0089-bug class) is thus
# caught credit-free on every CI bats job — not only on a credit-gated lifecycle run.
# `setup()`'s ambient closed 0099-demo is neutralized with a skip marker so each
# corpus is exactly what the case seeds.
# ---------------------------------------------------------------------------

# _seed_closed <dir>  — a minimal closed spec under TEST_REPO/specs/<dir>.
_seed_closed() {
  local d="$TEST_REPO/specs/$1"
  mkdir -p "$d"
  printf -- '---\nid: "%s"\nstatus: closed\ncreated: 2026-06-01\n---\n' "${1%%-*}" > "$d/spec.md"
}

@test "Test_consolidate_backfill_candidates_decline_leg_singleton_is_0090" {
  source "$LIB"
  touch "$TEST_REPO/specs/0099-demo/consolidation-skip"      # neutralize ambient seed
  _seed_closed 0001-add-farewell-function; touch "$TEST_REPO/specs/0001-add-farewell-function/consolidation-skip"
  _seed_closed 0090-decline-source
  run consolidate_backfill_candidates "$TEST_REPO"
  [ "$status" -eq 0 ]
  [ "$output" = "0090-decline-source" ]                      # EXACTLY the singleton
}

@test "Test_consolidate_backfill_candidates_confirm_leg_singleton_is_0089" {
  source "$LIB"
  touch "$TEST_REPO/specs/0099-demo/consolidation-skip"
  _seed_closed 0001-add-farewell-function; touch "$TEST_REPO/specs/0001-add-farewell-function/consolidation-skip"
  _seed_closed 0090-decline-source;        touch "$TEST_REPO/specs/0090-decline-source/consolidation-skip"
  _seed_closed 0089-demo-consolidation
  run consolidate_backfill_candidates "$TEST_REPO"
  [ "$status" -eq 0 ]
  [ "$output" = "0089-demo-consolidation" ]
}

@test "Test_consolidate_backfill_candidates_conflict_leg_singleton_is_0088" {
  source "$LIB"
  touch "$TEST_REPO/specs/0099-demo/consolidation-skip"
  _seed_closed 0001-add-farewell-function; touch "$TEST_REPO/specs/0001-add-farewell-function/consolidation-skip"
  _seed_closed 0090-decline-source;        touch "$TEST_REPO/specs/0090-decline-source/consolidation-skip"
  _seed_closed 0088-conflict-source
  # 0089 archived (CONFIRM leg's move) — under specs/.archive/, excluded by the specs/*/ glob
  local arch="$TEST_REPO/specs/.archive/0089-demo-consolidation/spec.md"; mkdir -p "$(dirname "$arch")"
  printf -- '---\nid: "0089"\nstatus: closed\n---\n' > "$arch"
  run consolidate_backfill_candidates "$TEST_REPO"
  [ "$status" -eq 0 ]
  [ "$output" = "0088-conflict-source" ]                     # 0089's archival double-verified (absent)
}

@test "Test_consolidate_backfill_candidates_skip_excludes_confirm_target_0089" {
  # The original 0089 bug, reproduced at zero credits: a skip-marked confirm-target
  # is excluded from the candidate set.
  source "$LIB"
  touch "$TEST_REPO/specs/0099-demo/consolidation-skip"
  _seed_closed 0089-demo-consolidation
  touch "$TEST_REPO/specs/0089-demo-consolidation/consolidation-skip"
  run consolidate_backfill_candidates "$TEST_REPO"
  [ "$status" -eq 0 ]
  ! printf '%s\n' "$output" | grep -qx "0089-demo-consolidation"
}

@test "consolidate_backfill_order: oldest-first via 0024 history parser; history-less specs last by created then id" {
  source "$LIB"
  # history.md records 0099 then 0098 (newest-first); 0097 has NO history entry
  local H="$TEST_REPO/.speccraft/history.md"; mkdir -p "$(dirname "$H")"
  cat > "$H" <<'EOF'
# History

## 2026-06-10 — Later (spec 0099)

## 2026-06-05 — Earlier (spec 0098)
EOF
  for id in 0099-demo 0098-mid 0097-nohist; do
    mkdir -p "$TEST_REPO/specs/$id"
    printf -- '---\nid: "%s"\nstatus: closed\ncreated: 2026-06-01\n---\n' "${id%%-*}" > "$TEST_REPO/specs/$id/spec.md"
  done
  run consolidate_backfill_order "$TEST_REPO" "0099-demo 0098-mid 0097-nohist"
  [ "$status" -eq 0 ]
  # oldest-first: 0098 (older history entry) then 0099, then 0097 (history-less, last)
  [ "${lines[0]}" = "0098-mid" ]
  [ "${lines[1]}" = "0099-demo" ]
  [ "${lines[2]}" = "0097-nohist" ]
}

@test "consolidate_marker_state: moved/conflict/skip/pending state machine" {
  source "$LIB"
  local sd="$TEST_REPO/specs/0099-demo"
  run consolidate_marker_state "$sd"; [ "$output" = "pending" ]
  consolidate_record_conflict "$sd" "x"
  run consolidate_marker_state "$sd"; [ "$output" = "conflict-open" ]
  consolidate_clear_conflict "$sd"
  touch "$sd/consolidation-skip"
  run consolidate_marker_state "$sd"; [ "$output" = "declined" ]
  rm -f "$sd/consolidation-skip"
  run consolidate_marker_state "$TEST_REPO/specs/.archive/0099-demo"; [ "$output" = "consolidated" ]
}
