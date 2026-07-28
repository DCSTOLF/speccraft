---
spec: "0038"
---

# Tasks

- [x] T1 — Bootstrap ledger.go: stub the full exported inventory (Ledger/LedgerDesign/LedgerMember/Rollup/MemberStatus, ParseLedger, SetLedgerField, Reconcile, ledgerNow) — the ONE /speccraft:spec:override
- [x] T2 — ParseLedger tests (RED): happy path + missing-file + first-wins + parse-error fixture table (AC1)
- [x] T3 — ParseLedger grammar (GREEN): implement the accepted subset with `ledger.md:` error prefix (AC1)
- [x] T4 — SetLedgerField tests (RED): round-trip, golden layout, byte-stable, same-value no-op, invalid-field-unchanged (AC2)
- [x] T5 — SetLedgerField + canonical serializer (GREEN) via AtomicWriteFile + ledgerNow (AC2)
- [x] T6 — Ledger-not-state.json: behavioral write-target test + source-scan meta-test (AC3)
- [x] T7 — Reconcile tests (RED): keys-on-resolver, classification/precedence table, order+counts, empty-design-Done (AC4/AC5)
- [x] T8 — Reconcile (GREEN) + no-LastCompletedPhase source scan (AC4/AC5)
- [x] T9 — Cmd REDs (RED, authored first, kept STANDING): ledger-set + reconcile run()-seam tests (AC6)
- [x] T10 — Extract resolveSpecStatus, refactor get-status, add reconcile/ledger-set subcommands + main.go/usage (GREEN, rides T9 REDs) (AC6)
- [x] T11 — get-status 0037 regression stays green + resolveSpecStatus tri-state unit pin (verification) (AC6)

## Bypasses

- 2026-07-28 — override: T1 bootstrap — create `tools/internal/speccraft/ledger.go` stubbing the complete new-exported-symbol inventory (`Ledger`/`LedgerDesign`/`LedgerMember`/`Rollup`/`MemberStatus`, `ParseLedger`, `SetLedgerField`, `Reconcile`, unexported `ledgerNow`). New exported internal symbols cannot compile in a first test until they exist (build-failure ≠ runtime RED, spec-0018-AC13). The ONE override for this spec; every later step fills in a stub (runtime RED) or rides the `run()` seam.
