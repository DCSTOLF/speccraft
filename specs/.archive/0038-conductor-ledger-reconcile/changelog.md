# Changelog — Spec 0038 Conductor primitives: ledger.md + reconcile rollup

Closed 2026-07-28. The Go/testable core of design 0001's conductor (Spec B, first
slice). Implemented test-first: 22 new test cases, full `go test ./...` green,
`go vet` clean, **one** `/speccraft:spec:override` (as planned).

## What shipped (vs spec)

- **AC1 — `ParseLedger`** (`tools/internal/speccraft/ledger.go`): the constrained
  `ledger.md` grammar — `## design <id>` / `### <member>` block form, first-`:`
  split with one-space strip (interior `: ` preserved), spaceless `spec:0007-x`,
  BOM/CRLF tolerance, `# Ledger` preamble ignored, first-wins on dup keys. Missing
  file ⇒ empty `Ledger`, nil error. Eleven parse-error classes, each with a stable
  `ledger.md: ` prefix.
- **AC2 — `SetLedgerField` + canonical writer**: idempotent upsert via
  `AtomicWriteFile`, `updated` stamped through the injectable `ledgerNow` seam;
  `updated` and unknown fields rejected (nothing written); same-value set is a
  byte-identical no-op; a golden-output test + a byte-stable equivalent-states
  test pin the deterministic layout.
- **AC3 — ledger-is-not-state.json**: a behavioral write-target test + a
  source-scan (sibling to `state_single_writer_test.go`) keep the single-writer
  rule intact.
- **AC4/AC5 — `Reconcile`** (pure, injected resolver): keys on the resolver's
  status, never the ledger `last_completed_phase` (proven by a disagreement test
  **and** a source-scan that the impl never references the pointer). Classification
  Blocked→Closed→InProgress with `blocked`-overlay precedence over resolved-closed;
  `Done` iff every member Closed; empty/absent design vacuously Done.
- **AC6 — cmd surfaces (run() seam)**: `speccraft-state ledger-set` and
  `reconcile <design-id>` (`done: <bool>` + `<status>\t<member>\t<spec-ref>` in
  ledger order; malformed ledger ⇒ non-zero, nothing on stdout). A shared
  `resolveSpecStatus` (dual live/`.archive`, tri-state outcome) was extracted and
  `get-status` refactored onto it with **zero** extra override — the refactor rode
  the standing failing `reconcile`/`ledger-set` cmd REDs. 0037's get-status
  regression stays green.

## Notable during implementation (dogfood)

- **Exactly 1 override** (T1 bootstrap), as the plan predicted — the get-status
  refactor sequencing (author cmd REDs first, land the refactor while they stand)
  held, costing zero.
- **Two guard interactions** the plan/memory anticipated: (1) a second Write of a
  test file with unchanged test names disarmed its red-candidates — re-armed by an
  Edit adding a fresh RED; (2) a literal BOM in Go source (from a `﻿` test
  fixture) was fixed mechanically via Bash (`perl`), the sanctioned path for a
  build-break the guard would misread.
- The `ledger.md:`-prefix source-scan (AC3) initially caught the string in a
  ledger.go *comment*; reworded.

## Deviations

- Consolidation deferred (still no `specs/domains/`) → `/speccraft:sync`.
- No version bump — Spec B completes only when the `/speccraft:arch:orchestrate`
  command (Spec 0039) lands on these primitives; that carries the release.

## Verified end-to-end (beyond unit tests)

In a temp `kind = workspace`: `ledger-set` produced the canonical `ledger.md`;
`reconcile D` printed `done: false` + `closed\t./api\t0007-a` +
`in-progress\t./web\t0012-b`; `ledger-set … updated …` was rejected non-zero.
