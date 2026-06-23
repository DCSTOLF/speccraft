---
spec: "0025"
---

# Tasks

- [x] T1 — RED: `spec-consolidate.bats` for `consolidate_parse_delta` (delta parse/validate, locator-required) — AC1 [det-bats]
- [x] T2 — GREEN: create `consolidate.lib.sh`; implement `consolidate_parse_delta` — AC1 [det-bats]
- [x] T3 — RED: bats for `consolidate_locator_match` (exact-normalized, 0/>1 → conflict seed) — AC1 [det-bats]
- [x] T4 — GREEN: implement `consolidate_locator_match` (suffix+whitespace-stripped match) — AC1 [det-bats]
- [x] T5 — RED: bats for `consolidate_routing_seed` (deterministic key; explicit `domains:` authoritative) — AC2 [det-bats]
- [x] T6 — GREEN: implement `consolidate_routing_seed` — AC2 [det-bats]
- [x] T7 — RED: bats for `consolidate_archiveB_append` (self-describing header + full-entry byte-dedup, no loss) — AC3 [det-bats]
- [x] T8 — GREEN: implement `consolidate_archiveB_append` (append-only `specs/domains/.archive/<area>.md`) — AC3 [det-bats]
- [x] T9 — RED: bats for `consolidate_apply_delta` incl. both CF-1 crash-window cases (write order) — AC6/CF-1 [det-bats]
- [x] T10 — GREEN: implement `consolidate_apply_delta` + shared provenance helper (archive-B FIRST → mutation) — AC6/CF-1/AC5 [det-bats]
- [x] T11 — RED: bats for `consolidate_blast_radius_ok` + byte-unchanged blast-radius integration check — AC4 [det-bats]
- [x] T12 — GREEN: implement `consolidate_blast_radius_ok` path allow-list — AC4 [det-bats]
- [x] T13 — RED: bats for `consolidate_assert_domain_invariants` (suffix grammar; `.archive` never in load list) — AC5 [det-bats]
- [x] T14 — GREEN: implement domain invariants + `consolidate_record_conflict` / `consolidate_clear_conflict` / `consolidate_archive_dir_move` (move-last, status unchanged) — AC5/AC6/AC8/CF-2 [det-bats]
- [x] T15 — RED: bats for backfill candidate predicate + history-parser-coupling order + marker state machine — AC11/CF-3 [det-bats]
- [x] T16 — GREEN: implement `consolidate_backfill_candidates` / `consolidate_backfill_order` (reuse 0024 parser) / `consolidate_marker_state` — AC11/CF-3 [det-bats]
- [x] T17 — REFACTOR: factor shared suffix-grammar + encode/dedup idioms into `_consolidate_*` helpers — [det-bats]
- [x] T18 — RED: `verify.sh` checks that `close.md` sources the lib + wires inline confirm-gated consolidation — AC9 [doc-verify]
- [x] T19 — GREEN: wire inline consolidation into `commands/spec/close.md` (after existing close steps; never gates close) — AC9/AC7/AC10 [doc-verify + model-e2e]
- [x] T20 — RED: `verify.sh` checks that `sync.md` sources the lib + adds the backfill propose loop — AC11 [doc-verify]
- [x] T21 — GREEN: wire backfill propose loop into `commands/sync.md` (predicate + presented order + skip marker) — AC11 [doc-verify + model-e2e]
- [x] T22 — RED: `verify.sh` checks for memory-keeper `# Mode: consolidate`, SKILL lazy-domain load + `.archive` absence, template purity — AC5/AC7/AC8/AC9/AC11 [doc-verify]
- [x] T23 — GREEN: add memory-keeper `# Mode: consolidate`; add lazy `specs/domains/<area>.md` to SKILL load list; confirm template purity — AC5/AC7/AC8/AC9/AC11 [doc-verify]
- [x] T24 — RED→GREEN: add SOURCED credit-gated `tests/e2e/spec_consolidate.sh` (structural only) + wire `[10e/13]` step into `run.sh` and bump counter — AC7–AC12 [model-e2e]
