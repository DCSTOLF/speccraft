---
spec: "0045"
---

# Tasks

- [x] T1 — RED: held lock forces `ledger-set` (and `ledger-archive`) down the `ledger busy` timeout path (AC1/AC3)
- [x] T2 — GREEN: `withLedgerLock` + unix flock primitive + build-tag stub; wrap both writers' whole transactions (AC1/AC3/AC6)
- [x] T3 — timeout fallback: empty/invalid/zero/negative → 10s, valid wins (AC3, codex S2)
- [x] T4 — deterministic contention via the `ledgerLockHold` barrier seam: set/set, set/archive, archive/archive all land (AC2/AC5)
- [x] T5 — crash-safe lock: killed holder leaves no stale lock; next acquire + `ledger-set` succeed; lock file 0644 under `.speccraft/` (AC4)
- [x] T6 — git-ignore `.speccraft/ledger.lock` + proof test (AC4/AC7)
- [x] T7 — verify happy-path byte-identity via existing ledger/bats/e2e suites (AC7)
- [x] T8 — `ledgerLockPath` helper factored (single lock-path source)
- [x] T9 — full verification: `go test ./...` + `go vet` green, 282 bats, e2e all pass, `-race -count=5` clean (only new artifact is `ledger.lock`)
