#!/usr/bin/env bash
# tests/e2e/spec_consolidate.sh — credit-gated e2e fixture for spec consolidation
# (spec 0025 model-behavior tier; leg isolation hardened by spec 0028).
#
# SOURCED by tests/e2e/run.sh from inside the claude -p lifecycle (run_claude,
# LOG_DIR, E2E_DIR, and the lib.sh predicates must already be in scope). Defines ONE
# entry function the lifecycle calls; no side effects at source time.
#
# Spec 0028 — LEG ISOLATION. /speccraft:sync enumerates the WHOLE candidate corpus
# each run, and a sync-decline writes a permanent consolidation-skip marker. So the
# three legs are isolated by LAZY per-leg seeding to exactly ONE eligible candidate
# per sync (see the spec-0028 corpus-state table):
#   | leg     | seeded & under specs/ | skip-marked   | archived | candidate |
#   | DECLINE | 0001, 0090            | 0001          | —        | 0090      |
#   | CONFIRM | 0001, 0090, 0089      | 0001, 0090    | —        | 0089      |
#   | CONFLICT| 0001, 0090, 0088      | 0001, 0090    | 0089     | 0088      |
# 0001 (the lifecycle spec, closed in place by [10/13]) is skip-marked ONCE at entry;
# each leg's source is seeded immediately before its own sync; 0090's skip is written
# by the DECLINE sync itself, 0089 is archived by the CONFIRM move — NO marker is ever
# cleared. Each leg additionally asserts the LIVE candidate set is the intended
# singleton via a DIRECT invocation of consolidate_backfill_candidates (AC3,
# load-bearing) — the credit-free, fixture-mirroring guard lives in
# tests/hooks/spec-consolidate.bats (AC2). STRUCTURAL predicates only — never grep
# model prose.

set -euo pipefail

PROV_SUFFIX_RE='\(specs?[[:space:]]+[0-9]{4}'

# --- lazy per-leg seed helpers (each lands immediately before its own leg) -------

_seed_state_domain() {
  mkdir -p "specs/domains"
  cat > "specs/domains/state.md" <<'EOF'
# State domain

- close clears active_spec to "" (spec 0012)
- state uses a sentinel string for cleared active_spec (spec 0012)
EOF
}

_seed_0090_decline_source() {
  mkdir -p "specs/0090-decline-source"
  cat > "specs/0090-decline-source/spec.md" <<'EOF'
---
id: "0090"
title: "Decline Source"
status: closed
created: 2026-06-01
domains: [state]
delta:
  - ADD: a decline-source note that is never applied (spec 0090)
---

# body
EOF
}

_seed_0089_confirm_source() {
  mkdir -p "specs/0089-demo-consolidation"
  cat > "specs/0089-demo-consolidation/spec.md" <<'EOF'
---
id: "0089"
title: "Demo Consolidation Source"
status: closed
created: 2026-06-02
domains: [state]
delta:
  - ADD: pre-tool-use hook gates the Write tool (spec 0089)
  - MODIFY: state uses omitempty sibling keys (spec 0089)
    locator: state uses a sentinel string for cleared active_spec
---

# body
EOF
}

_seed_0088_conflict_source() {
  mkdir -p "specs/0088-conflict-source"
  cat > "specs/0088-conflict-source/spec.md" <<'EOF'
---
id: "0088"
title: "Conflict Source"
status: closed
created: 2026-06-03
domains: [state]
delta:
  - MODIFY: a replacement requirement (spec 0088)
    locator: a requirement line that does not exist in the domain file
---

# body
EOF
}

# _assert_candidate_singleton <expected-dir> <leg-label>
# AC3 (load-bearing): assert the LIVE backfill candidate set is exactly the leg's
# intended singleton, via a DIRECT invocation of consolidate_backfill_candidates —
# NOT by parsing model logs. This is the only check that verifies the corpus the
# fixture actually built matches the per-leg table; a seeding/order drift becomes a
# fast, named failure here instead of a confusing downstream state.md failure.
_assert_candidate_singleton() {
  local expected="$1" leg="$2" got
  got="$(consolidate_backfill_candidates "$PWD")"
  [ "$got" = "$expected" ] \
    || fail "$leg candidate set is not the singleton '$expected' (got: <$got>)"
}

spec_consolidate() {
  command -v run_claude >/dev/null 2>&1 \
    || fail "spec_consolidate must be sourced by run.sh (run_claude undefined)"
  : "${E2E_DIR:?spec_consolidate needs E2E_DIR (sourced by run.sh)}"

  # Source the plugin's consolidate lib for the AC3 candidate guard (pure — defines
  # functions only). Resolved from E2E_DIR so it is independent of the test CWD.
  # shellcheck source=../../commands/spec/consolidate.lib.sh
  source "$E2E_DIR/../../commands/spec/consolidate.lib.sh"

  local DOM="specs/domains/state.md"
  local ARCH="specs/domains/.archive/state.md"
  _seed_state_domain

  # Skip-mark the lifecycle spec 0001 ONCE (set-and-never-cleared isolation artifact)
  # so it never leaks into any leg's sync (spec 0028 B2). Resolve its dir like run.sh.
  local ONE; ONE="$(find specs -maxdepth 1 -name '0001-*' -type d 2>/dev/null | head -1)"
  [ -n "$ONE" ] || fail "spec_consolidate: lifecycle spec 0001-* not found under specs/"
  touch "$ONE/consolidation-skip"

  local SNAP_DOM; SNAP_DOM="$(mktemp)"; cp "$DOM" "$SNAP_DOM"

  # ---- [cons 1/3] DECLINE: candidate is 0090; nothing written/moved; skip written ----
  _seed_0090_decline_source
  _assert_candidate_singleton "0090-decline-source" "[cons 1/3]"
  echo "==> [cons 1/3] /speccraft:sync consolidation backfill (decline spec 0090 → no write/move)"
  run_claude "/speccraft:sync. When the consolidation backfill proposes folding spec 0090 into specs/domains/state.md, DECLINE it — do not apply, do not move anything." cons-01-decline.log
  # AC4: a sync-decline writes a consolidation-skip marker (pins spec 0025 AC11)...
  exists "specs/0090-decline-source/consolidation-skip"
  # ...and changes nothing else.
  cmp -s "$SNAP_DOM" "$DOM" || fail "consolidation (decline) modified the domain file"
  [ ! -d "specs/.archive/0090-decline-source" ] || fail "consolidation (decline) moved the spec dir"
  [ -d "specs/0090-decline-source" ] || fail "consolidation (decline) lost the spec dir from specs/"
  pass "[cons 1/3] decline wrote 0090's skip marker; domain + specs/ layout byte-unchanged"

  # ---- [cons 2/3] CONFIRM: candidate is 0089; folds in, archives, moves the dir ----
  #
  # spec 0027 — this CONFIRM leg is the inline-at-close-EQUIVALENT coverage: it drives
  # /speccraft:sync but exercises the SAME consolidate.lib.sh route → apply_delta →
  # archive_dir_move that close.md step 9 drives inline. The close-command WIRING is
  # pinned credit-free by specs/0025-spec-consolidation-on-close/verify.sh and the lib
  # MECHANICS (incl. the wholesale `mv`) by tests/hooks/spec-consolidate.bats.
  _seed_0089_confirm_source
  _assert_candidate_singleton "0089-demo-consolidation" "[cons 2/3]"
  echo "==> [cons 2/3] /speccraft:sync consolidation backfill (confirm spec 0089; inline-at-close-equivalent)"
  run_claude "/speccraft:sync. Approve the consolidation backfill for spec 0089: fold its delta (the ADD and the MODIFY) into specs/domains/state.md, archive the superseded text, and move the closed dir to specs/.archive/." cons-02-confirm.log
  # AC6: routed domain carries the merged, provenance-suffixed requirement(s).
  contains "$DOM" "(spec 0089)"
  contains_regex "$DOM" "$PROV_SUFFIX_RE"
  # AC6: the MODIFY's superseded text was archived (archive-B exists + non-empty).
  exists "$ARCH"
  [ -s "$ARCH" ] || fail "archive-B file is empty after a MODIFY consolidation"
  # AC6 / dir-move: the closed dir moved under specs/.archive/ and is gone from specs/.
  exists "specs/.archive/0089-demo-consolidation/spec.md"
  [ ! -d "specs/0089-demo-consolidation" ] || fail "consolidated spec dir still a live silo under specs/"
  pass "[cons 2/3] confirm merged into the domain, archived superseded text, moved the dir"

  # ---- [cons 3/3] CONFLICT: candidate is 0088; conflict recorded, nothing moved ----
  local SNAP_DOM2; SNAP_DOM2="$(mktemp)"; cp "$DOM" "$SNAP_DOM2"
  _seed_0088_conflict_source
  # AC3 + AC7: the singleton is 0088 — which double-verifies 0089's archival removed
  # it from the corpus via the feature's specs/.archive/ exclusion.
  _assert_candidate_singleton "0088-conflict-source" "[cons 3/3]"
  echo "==> [cons 3/3] /speccraft:sync consolidation backfill (spec 0088 → conflict)"
  run_claude "/speccraft:sync. Process the consolidation backfill for spec 0088. Its MODIFY locator matches no line in specs/domains/state.md, so record the conflict and leave the domain file unchanged; the spec must not move." cons-03-conflict.log
  exists "specs/0088-conflict-source/consolidation-conflicts.md"
  cmp -s "$SNAP_DOM2" "$DOM" || fail "a conflict consolidation mutated the domain file"
  [ ! -d "specs/.archive/0088-conflict-source" ] || fail "a spec with an open conflict was moved to .archive"
  [ -d "specs/0088-conflict-source" ] || fail "the conflicted spec dir was lost from specs/"
  pass "[cons 3/3] conflict recorded the sink, left the domain byte-unchanged, did not move the dir"

  # ---- AC8: only the two by-design skips persist; no other isolation skip exists ----
  exists "specs/0090-decline-source/consolidation-skip"          # feature-generated (DECLINE sync)
  exists "$ONE/consolidation-skip"                               # isolation artifact (set once, never cleared)
  [ ! -e "specs/0088-conflict-source/consolidation-skip" ] || fail "AC8: unexpected skip marker on 0088 (conflict, not declined)"
  [ ! -e "specs/.archive/0089-demo-consolidation/consolidation-skip" ] || fail "AC8: unexpected skip marker on archived 0089"
  pass "[cons AC8] only 0090's (feature) and 0001's (isolation) skips persist; nothing cleared"

  # ---- [cons AC6] spec 0029 Fix B — existing-domain-aware routing ----
  # no-match title → propose+create a NEW domain; matching title → route into the
  # existing domain; and consolidation NEVER writes .speccraft/ memory.
  # Snapshot the three .speccraft/ memory files to prove the blast-radius boundary.
  local SNAP_ARCH SNAP_CONV SNAP_HIST
  SNAP_ARCH="$(mktemp)"; SNAP_CONV="$(mktemp)"; SNAP_HIST="$(mktemp)"
  cp .speccraft/architecture.md "$SNAP_ARCH"
  cp .speccraft/conventions.md  "$SNAP_CONV"
  cp .speccraft/history.md      "$SNAP_HIST"
  # Quiesce the lingering conflict spec (0088, still a live candidate) so each AC6
  # sync sees exactly one eligible candidate (spec 0028 leg-isolation discipline).
  touch "specs/0088-conflict-source/consolidation-skip"

  # (AC6a) NO existing domain matches the title → a NEW specs/domains/<area>.md is created.
  mkdir -p specs/0087-billing-webhooks
  cat > specs/0087-billing-webhooks/spec.md <<'EOF'
---
id: "0087"
title: "Billing webhooks"
status: closed
created: 2026-06-02
delta:
  - ADD: retry failed billing webhooks with capped backoff (spec 0087)
---
EOF
  _assert_candidate_singleton "0087-billing-webhooks" "[cons AC6a]"
  echo "==> [cons AC6a] /speccraft:sync (no domain matches 'Billing webhooks' → NEW domain)"
  run_claude "/speccraft:sync. Process the consolidation backfill for spec 0087. No existing specs/domains/ file matches its title (only 'state' exists); propose and, on confirm, CREATE a new domain file (e.g. specs/domains/billing.md) and merge its ADD requirement there. Confirm." cons-ac6a.log
  local NEWDOM
  NEWDOM="$(ls specs/domains/*.md 2>/dev/null | grep -v '/state\.md$' | head -1 || true)"
  [ -n "$NEWDOM" ] || fail "[cons AC6a] no NEW domain file created for a no-match title"
  contains_regex "$NEWDOM" "$PROV_SUFFIX_RE"
  pass "[cons AC6a] no-match title created a new domain file: $NEWDOM"

  # (AC6b) title fits the existing 'state' domain → route into specs/domains/state.md.
  local SNAP_STATE; SNAP_STATE="$(mktemp)"; cp specs/domains/state.md "$SNAP_STATE"
  mkdir -p specs/0086-state-tracking
  cat > specs/0086-state-tracking/spec.md <<'EOF'
---
id: "0086"
title: "State tracking improvements"
status: closed
created: 2026-06-03
delta:
  - ADD: state records the active design lane (spec 0086)
---
EOF
  _assert_candidate_singleton "0086-state-tracking" "[cons AC6b]"
  echo "==> [cons AC6b] /speccraft:sync (title fits existing 'state' domain → route into it)"
  run_claude "/speccraft:sync. Process the consolidation backfill for spec 0086. Its title fits the existing specs/domains/state.md domain; route into THAT existing file (do not create a new one) and merge its ADD requirement. Confirm." cons-ac6b.log
  [ "$(wc -l < specs/domains/state.md)" -gt "$(wc -l < "$SNAP_STATE")" ] \
    || fail "[cons AC6b] existing state.md domain did not gain lines"
  pass "[cons AC6b] matching title routed into the existing state.md domain"

  # AC6 blast-radius invariant: consolidation NEVER wrote .speccraft/ memory.
  cmp -s "$SNAP_ARCH" .speccraft/architecture.md || fail "[cons AC6] consolidation wrote .speccraft/architecture.md"
  cmp -s "$SNAP_CONV" .speccraft/conventions.md  || fail "[cons AC6] consolidation wrote .speccraft/conventions.md"
  cmp -s "$SNAP_HIST" .speccraft/history.md      || fail "[cons AC6] consolidation wrote .speccraft/history.md"
  pass "[cons AC6] .speccraft/{architecture,conventions,history}.md byte-unchanged by consolidation"

  rm -f "$SNAP_DOM" "$SNAP_DOM2" "$SNAP_ARCH" "$SNAP_CONV" "$SNAP_HIST" "$SNAP_STATE"
}
