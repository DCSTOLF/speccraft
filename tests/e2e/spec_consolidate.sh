#!/usr/bin/env bash
# tests/e2e/spec_consolidate.sh — credit-gated e2e fixture for spec consolidation
# (spec 0025, model-behavior tier AC7–AC12).
#
# SOURCED by tests/e2e/run.sh from inside the claude -p lifecycle (run_claude,
# LOG_DIR, and the lib.sh predicates must already be in scope). Defines ONE entry
# function the lifecycle calls; no side effects at source time. Like the spec-0022
# /0024 fixtures, the consolidation flow can only be exercised by really driving
# the command body through claude — the deterministic mechanics are pinned at zero
# credit cost by tests/hooks/spec-consolidate.bats and specs/0025-…/verify.sh.
#
# STRUCTURAL predicates only — never grep model prose (plan R3 / structural-over-
# content). Reuses the `cmp -s` byte-unchanged idiom from arch_close_memory.sh.
# Drives the retroactive /speccraft:sync backfill (the same routing→delta→merge→
# archive flow close runs inline) on seeded closed specs. Asserts:
#   - DECLINE: the domain file AND the specs/ layout are byte-identical; the spec
#     dir is NOT moved (AC9).
#   - CONFIRM: the routed domain file gained the provenance-suffixed requirement
#     and the archive-B file is non-empty (AC7); the closed dir moved under
#     specs/.archive/ and is gone from specs/ (AC12 / dir-move).
#   - CONFLICT: a MODIFY whose locator matches nothing leaves consolidation-
#     conflicts.md in the spec dir, the domain line byte-unchanged, dir NOT moved
#     (AC8).
#
# AC10 (routing seed presented / multi-domain split) and AC11 (the backfill
# candidate/order predicate) are pinned deterministically by spec-consolidate.bats
# and verify.sh — not re-driven here, to avoid redundant credit-gated runs.

set -euo pipefail

PROV_SUFFIX_RE='\(specs?[[:space:]]+[0-9]{4}'

# Seed a domain file plus a closed spec carrying a well-formed delta block.
_spec_consolidate_seed() {
  local dom="specs/domains/state.md"
  mkdir -p "specs/domains"
  cat > "$dom" <<'EOF'
# State domain

- close clears active_spec to "" (spec 0012)
- state uses a sentinel string for cleared active_spec (spec 0012)
EOF

  mkdir -p "specs/0089-demo-consolidation"
  cat > "specs/0089-demo-consolidation/spec.md" <<'EOF'
---
id: "0089"
title: "Demo Consolidation Source"
status: closed
created: 2026-06-01
domains: [state]
delta:
  - ADD: pre-tool-use hook gates the Write tool (spec 0089)
  - MODIFY: state uses omitempty sibling keys (spec 0089)
    locator: state uses a sentinel string for cleared active_spec
---

# body
EOF

  # A second closed spec whose MODIFY locator matches nothing → conflict path.
  mkdir -p "specs/0088-conflict-source"
  cat > "specs/0088-conflict-source/spec.md" <<'EOF'
---
id: "0088"
title: "Conflict Source"
status: closed
created: 2026-06-02
domains: [state]
delta:
  - MODIFY: a replacement requirement (spec 0088)
    locator: a requirement line that does not exist in the domain file
---

# body
EOF
}

spec_consolidate() {
  command -v run_claude >/dev/null 2>&1 \
    || fail "spec_consolidate must be sourced by run.sh (run_claude undefined)"

  local DOM="specs/domains/state.md"
  local ARCH="specs/domains/.archive/state.md"
  _spec_consolidate_seed

  # Snapshots for the decline (byte-unchanged) assertions.
  local SNAP_DOM; SNAP_DOM="$(mktemp)"; cp "$DOM" "$SNAP_DOM"

  # ---- DECLINE: nothing is written or moved ----
  echo "==> [cons 1/3] /speccraft:sync consolidation backfill (decline → no write/move)"
  run_claude "/speccraft:sync. When the consolidation backfill proposes folding spec 0089 into specs/domains/state.md, DECLINE it — do not apply, do not move anything." cons-01-decline.log
  cmp -s "$SNAP_DOM" "$DOM" || fail "consolidation (decline) modified the domain file"
  [ ! -d "specs/.archive/0089-demo-consolidation" ] || fail "consolidation (decline) moved the spec dir"
  [ -d "specs/0089-demo-consolidation" ] || fail "consolidation (decline) lost the spec dir from specs/"
  pass "consolidation (decline) left the domain file + specs/ layout byte-unchanged"

  # ---- CONFIRM: 0089 folds into the domain, dir moves, archive-B written ----
  echo "==> [cons 2/3] /speccraft:sync consolidation backfill (confirm spec 0089)"
  run_claude "/speccraft:sync. Approve the consolidation backfill for spec 0089: fold its delta (the ADD and the MODIFY) into specs/domains/state.md, archive the superseded text, and move the closed dir to specs/.archive/." cons-02-confirm.log

  # AC7: routed domain file carries the merged, provenance-suffixed requirement(s).
  contains "$DOM" "(spec 0089)"
  contains_regex "$DOM" "$PROV_SUFFIX_RE"
  # AC7/B5: the MODIFY's superseded text was archived (archive-B exists + non-empty).
  exists "$ARCH"
  [ -s "$ARCH" ] || fail "archive-B file is empty after a MODIFY consolidation"
  # AC12 / dir-move: the closed dir moved under specs/.archive/ and is gone from specs/.
  exists "specs/.archive/0089-demo-consolidation/spec.md"
  [ ! -d "specs/0089-demo-consolidation" ] || fail "consolidated spec dir still a live silo under specs/"
  pass "consolidation (confirm) merged into the domain, archived superseded text, moved the dir"

  # ---- CONFLICT: a non-matching MODIFY locator records a conflict, never moves ----
  local SNAP_DOM2; SNAP_DOM2="$(mktemp)"; cp "$DOM" "$SNAP_DOM2"
  echo "==> [cons 3/3] /speccraft:sync consolidation backfill (spec 0088 → conflict)"
  run_claude "/speccraft:sync. Process the consolidation backfill for spec 0088. Its MODIFY locator matches no line in specs/domains/state.md, so record the conflict and leave the domain file unchanged; the spec must not move." cons-03-conflict.log

  exists "specs/0088-conflict-source/consolidation-conflicts.md"
  cmp -s "$SNAP_DOM2" "$DOM" || fail "a conflict consolidation mutated the domain file"
  [ ! -d "specs/.archive/0088-conflict-source" ] || fail "a spec with an open conflict was moved to .archive"
  [ -d "specs/0088-conflict-source" ] || fail "the conflicted spec dir was lost from specs/"
  pass "consolidation (conflict) recorded the sink, left the domain byte-unchanged, did not move the dir"

  rm -f "$SNAP_DOM" "$SNAP_DOM2"
}
