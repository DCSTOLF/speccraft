---
spec: "0044"
---

# Plan — 0044 workspace sync: design-level consolidation & ledger-row archival

Test-first (RED→GREEN→REFACTOR). **Override budget: 0.** The only Go surface
(`ledger-archive`) lives in the cmd package and rides the `run()` seam — its RED is a
passing test asserting the pre-impl `unknown subcommand`/non-zero. Shell
(`commands/sync.lib.sh`) and markdown (`commands/sync.md`) are ungated; `bats` is their
RED oracle.

## The fingerprint (shared shell↔Go contract)

The `--expect` fingerprint and the `consolidated:` marker fingerprint are the **same**
value: `sha256` of a design's `reconcile` output. A `reconcileOutput(design) string`
helper factored out of `reconcileCmd` produces the exact bytes both `reconcileCmd`
prints and `ledger-archive --expect` hashes; the shell computes `speccraft-state
reconcile <design> | sha256sum`. Identical bytes → identical fingerprint.

## Surfaces

- **Go:** `speccraft-state ledger-archive <design> [--expect <fp>]` — new
  `tools/cmd/speccraft-state/ledger_archive_cmd.go` + dispatch/usage in `main.go`;
  reuses exported `ParseLedger`/`Reconcile`/`AtomicWriteFile` + a text-level `## design
  <id>` section splice + `reconcileOutput` fingerprint. Unit-tested in
  `ledger_archive_cmd_test.go`.
- **Shell:** `commands/sync.lib.sh` gains `sync_resolve_design_dir`,
  `sync_design_fingerprint`, `sync_design_rollup_body`, `sync_done_live_designs`,
  `sync_consolidate_design`. Bats in `tests/hooks/sync-workspace.bats`.
- **Markdown:** `commands/sync.md` gains the `W4` step under the
  `<!-- speccraft:sync:workspace -->` anchor, after W1–W3.
- **E2E:** `tests/e2e/workspace_consolidate_cycle.sh` registered in `tests/e2e/run.sh`.

## Steps

1. **RED** (T1) `ledger_archive_cmd_test.go`: four-case contract (present+done→archive;
   present+not-done→`design not done`; absent-live+in-archive→no-op 0; absent-both→
   `unknown design`); `--expect` mismatch→`conflict`; other designs byte-identical after
   a move; splice **boundary cases** (target at start / end / sole / flanked);
   both-present crash-residue→completed; re-run→no-op; archive absent→created w/ `#
   Ledger` preamble & `ParseLedger`-valid; parse-corrupt archive→refuse.
2. **GREEN** (T2) implement `ledger-archive` + factor `reconcileOutput`; dispatch + usage
   line. (AC1, AC2)
3. **RED** (T3) `sync_resolve_design_dir` bats: happy (one match), missing (0), ambiguous
   (≥2).
4. **GREEN** (T4) implement `sync_resolve_design_dir`. (AC4)
5. **RED** (T5) `sync_design_fingerprint` + `sync_design_rollup_body` bats: fingerprint
   equals `reconcile | sha256sum`; rollup body has one `<member> → <spec> → <status>` line
   per member in reconcile order.
6. **GREEN** (T6) implement both. (AC5)
7. **RED** (T7) `sync_done_live_designs` bats: done+in-progress mix → only the done id
   (LC_ALL=C sorted); all-in-progress → empty.
8. **GREEN** (T8) implement `sync_done_live_designs`. (AC3)
9. **RED** (T9) `sync_consolidate_design` bats: happy (outcome + rows archived);
   matching-fingerprint re-run (no rewrite/dup); record-then-crash-then-rerun (rows
   eventually archived); snapshot-changed → `conflict`, no archive; **stale-fingerprint
   re-run → outcome rewritten** before archival.
10. **GREEN** (T10) implement `sync_consolidate_design` (resolve dir → capture fp → write
    outcome via mktemp+mv with fingerprinted marker → `ledger-archive --expect`). (AC6)
11. **RED** (T11) `sync.md` W4 source-scan bats: W4 block under the `:workspace` anchor,
    **after** W1–W3, calls `sync_done_live_designs`/`sync_consolidate_design`.
12. **GREEN** (T12) wire `commands/sync.md` W4. (AC7)
13. **REFACTOR** (T13) fold shared fingerprint/format; tidy; no behavior change.
14. **E2E** (T14) `tests/e2e/workspace_consolidate_cycle.sh` (one done + one in-progress
    design, real `design/<id>-<slug>/`): `sync_done_live_designs` → only done id;
    `sync_consolidate_design` → `outcome.md` w/ member lines; rows gone from `ledger-get`
    but present in `ledger.archive.md` (ParseLedger-valid); in-progress untouched; second
    run no-op both ways. Register in `run.sh`. (AC8, AC9)

## Falsifiable coverage map

- AC1 → T1/T2 · AC2 → T1/T2 · AC3 → T7/T8 · AC4 → T3/T4 · AC5 → T5/T6
- AC6 → T9/T10 · AC7 → T11/T12 · AC8 → T14 (e2e) · AC9 → T14 (e2e)
- Interactive W4 prompt: source-scan fence only (credit-gated, spec-0042/0043 convention).
