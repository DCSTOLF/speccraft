# Changelog — 0044 workspace sync: design-level consolidation & ledger-row archival

**Status:** closed · **Shipped in:** 1.15.0 · **Date:** 2026-08-03

## What shipped

**Drift class C** — the design-consolidation pass (`W4`) of `/speccraft:sync`'s
workspace branch, completing the workspace-sync arc (A + B in 0043, C here). When a
design is fully `done` (all members `closed`), sync — confirm-gated — folds it into a
durable colocated rollup record and **archives its ledger rows out of the live ledger**,
keeping `.speccraft/ledger.md` bounded as designs accumulate (the workspace analog of
spec consolidation keeping `specs/` bounded).

The three flagged design decisions were resolved with the user: colocated
`design/<id>-<slug>/outcome.md` (no `history.md` note); sibling
`.speccraft/ledger.archive.md` (same grammar, `ParseLedger`-valid); the pass is `W4`
inside `/speccraft:sync`, not a separate command.

### Surfaces

- **`speccraft-state ledger-archive <design> [--expect <fp>]`**
  (`tools/cmd/speccraft-state/ledger_archive_cmd.go`) — the sanctioned, **single-read**
  archival op and atomic authority for the move. Four-case contract on a text-level
  presence check (so `Reconcile`'s vacuous-done-for-absent never leaks): present+done →
  archive; present+not-done → refuse `design not done: <members>`; absent-live+in-archive
  → idempotent no-op; absent-both → refuse `unknown design`. Byte-level **section splice**
  on the raw `ledger.md` text (untouched designs byte-identical — not a re-serialize);
  transactional **append-to-archive-first, remove-from-live-second** with both-present
  crash-residue recovery; `--expect <fp>` compare-and-set (`conflict: <id> changed`)
  closing the caller→op handoff window. Refuses a parse-corrupt archive. Lives entirely in
  the cmd package (rides the `run()` seam) → **override budget 0**. Reuses only exported
  `ParseLedger`/`Reconcile`/`AtomicWriteFile`; `reconcileCmd` was refactored onto a shared
  `reconcileOutput` so the `--expect` fingerprint equals `reconcile <design> | sha256sum`.
- **Five pure `commands/sync.lib.sh` helpers:** `sync_resolve_design_dir` (id→slugged-dir,
  glob `design/<id>-*/`, error on 0/>1), `sync_design_fingerprint`,
  `sync_design_rollup_body` (member `→` lines + fingerprinted `consolidated:` marker),
  `sync_done_live_designs` (live ∩ reconcile-done, `LC_ALL=C`-sorted), and
  `sync_consolidate_design` (resolve → capture fingerprint → write `outcome.md` byte-safe
  with a fingerprint-matched idempotency check → `ledger-archive --expect`).
- **`commands/sync.md` W4 step** — confirm-gated, under the `<!-- speccraft:sync:workspace
  -->` anchor, **after** the W1–W3 ledger/membership passes (load-bearing order).

### Contracts

- **Fingerprinted crash-safety.** `outcome.md` is written *before* archival with a
  `consolidated: <date> fingerprint: <fp>` marker; "recorded" iff the marker fingerprint
  equals the current per-design reconcile fingerprint — a missing OR stale marker forces an
  atomic rewrite, so the durable record can never describe an older snapshot than the
  archived rows (closes cross-run skew).
- **Bounded, honest concurrency.** `--expect` closes the caller→op skew; the op's own
  read→rename is not a filesystem CAS, so a *concurrently running* conductor could still
  lose a write in a narrow window — the identical single-writer limitation every ledger
  writer has, explicitly deferred (a workspace-wide lock / `--expect-bytes` CAS is the
  follow-up, as with spec 0043).

### Tests

- Go: `ledger_archive_cmd_test.go` (11 cases — four-case, `--expect` match/mismatch,
  byte-identity, both-present recovery, sole-design, corrupt-archive-refuse).
- bats: 13 new in `tests/hooks/sync-workspace.bats` (resolver, fingerprint, rollup body,
  done-live enumeration, consolidate happy/crash-rerun/stale-fp-rewrite/not-done, W4 fence).
- e2e: `tests/e2e/workspace_consolidate_cycle.sh` — hermetic detect→consolidate→archive
  round-trip (one done + one in-progress design), archive ParseLedger-valid, second-run
  no-op both ways. Registered in `run.sh`.
- Full suite: `go test ./...` + `go vet` green, **282 bats** green, drift clean, all four
  workspace e2e pass. **Override budget: 0.**

## Spec vs shipped — deviations

- **One new `speccraft-state` subcommand (`ledger-archive`)** + a `reconcileCmd` refactor
  onto `reconcileOutput` (behavior-identical, verified by the reconcile regression tests) —
  both anticipated in the spec's What.
- **The interactive W4 prompt** is source-scan-fenced (anchor + after-W1–W3 order + helper
  calls) and credit-gated; the detect→consolidate→archive *mechanism* is proven
  deterministically by the e2e (spec-0042/0043 convention).

## Cross-model review — four rounds

codex drove four rounds of deep, code-grounded hardening (both models converged): the
`Reconcile` vacuous-done hole → four-case contract; the non-transactional two-file move →
append-first/remove-second state machine; the byte-identity overclaim → section splice;
cross-run outcome/archive skew → fingerprinted marker; the caller→op TOCTOU →
`ledger-archive --expect` atomic CAS. The residual concurrent-writer race was bounded +
deferred (consistent with 0043's ratified single-writer scope). claude-p
approve-with-comments. Full trail in `review.md`.

## Follow-ups / not done

- **Workspace-wide ledger lock / rename-time CAS across all writers** (`ledger-set
  --expect` + `ledger-archive --expect-bytes`) — closes the residual concurrent-writer
  window; deferred (shared with 0043).
- **Compaction of `ledger.archive.md`** — grows append-only, off the hot path; a future
  compaction pass could bound it.
- **Un-consolidation** (moving rows back from the archive) — out of scope; archival is
  one-directional.
- **Inline domain consolidation** (close step 9): deferred — 0044 stays a live silo for a
  later `/speccraft:sync` backfill.
