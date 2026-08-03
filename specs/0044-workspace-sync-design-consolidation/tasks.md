---
spec: "0044"
---

# Tasks

- [x] T1 — ledger-archive Go test: four-case + --expect + byte-identity + splice boundaries + both-present recovery + archive-absent + corrupt-refuse (RED)
- [x] T2 — implement ledger-archive + factor reconcileOutput (GREEN, AC1/AC2)
- [x] T3 — sync_resolve_design_dir bats: happy/missing/ambiguous (RED, AC4)
- [x] T4 — implement sync_resolve_design_dir (GREEN, AC4)
- [x] T5 — sync_design_fingerprint + sync_design_rollup_body bats (RED, AC5)
- [x] T6 — implement both helpers (GREEN, AC5)
- [x] T7 — sync_done_live_designs bats: mix/all-in-progress (RED, AC3)
- [x] T8 — implement sync_done_live_designs (GREEN, AC3)
- [x] T9 — sync_consolidate_design bats: happy/matching-fp/crash-rerun/conflict/stale-fp-rewrite (RED, AC6)
- [x] T10 — implement sync_consolidate_design (GREEN, AC6)
- [x] T11 — sync.md W4 source-scan bats: under :workspace anchor, after W1-W3 (RED, AC7)
- [x] T12 — wire commands/sync.md W4 (GREEN, AC7)
- [x] T13 — Refactor: shared fingerprint/format, tidy (no behavior change)
- [x] T14 — e2e workspace_consolidate_cycle.sh + register in run.sh (AC8/AC9)
