---
id: "0045"
title: "ledger write-locking"
status: draft
created: 2026-08-03
authors: [claude]
packages: []
related-specs: ["0043", "0044"]
---

# Spec 0045 — ledger write-locking

## Why

Specs 0043 (workspace ledger/membership reconciliation) and 0044 (design
consolidation & ledger-row archival) both shipped under an explicit
**single-writer assumption** and *bounded-but-deferred* the residual
concurrent-writer race: every ledger writer (`ledger-set`, `ledger-archive`,
the conductor) does read → modify → atomic-rename, but there is no mutual
exclusion, so two writers that read the same bytes can both write and the
last rename silently clobbers the first's change. `ledger-archive --expect`
closes the *caller → op* handoff window but **not** the op's own read → rename
window — it is not a filesystem CAS. As the conductor and `/speccraft:sync`
run more autonomously, concurrent ledger writes become plausible, and a lost
update to the ledger is a silent correctness failure.

This spec closes exactly that window. Two adjacent follow-ups the arc deferred
alongside it — `/speccraft:sync --recursive` and `ledger.archive.md`
compaction — are **split into their own specs** (see Out of scope); 0045 is
the load-bearing concurrency fix only.

## What

Make the ledger safe under concurrent cooperating writers on one host by
serializing **every** ledger writer's *entire* transaction behind a host-level
exclusive advisory lock (`syscall.Flock`, `LOCK_EX`, on a sidecar
`<root>/.speccraft/ledger.lock`), and by moving each writer's **authoritative
read inside the lock** so the read → modify → rename is one indivisible
critical section. `ledger-archive`'s two-file transaction
(`ledger.archive.md` + `ledger.md`) is held under the *same* lock end to end.

The `--expect` compare-and-set is **kept as a semantic CAS on the existing
`reconcile | sha256sum` fingerprint** — but the fingerprint is now re-derived
from the ledger bytes read *under the lock* and compared before any write, so a
caller-supplied `--expect` can never be applied to a ledger that changed after
the caller computed it. The lock closes the op's own read → rename window
through serialization; `--expect` remains the caller → op semantic guard.
(There is **no** claim of whole-ledger byte identity — a reconcile projection
cannot establish that, and none is needed.)

The lock is taken by the Go ops that own ledger writes (`ledger-set`,
`ledger-archive`) so any caller — the conductor, `/speccraft:sync`, a human —
is serialized without changing the callers. The ledger grammar, `Reconcile`,
and the `orch_*` token machine are untouched.

## Acceptance criteria

1. **Whole-transaction critical section.** `ledger-set` and `ledger-archive`
   acquire an exclusive advisory lock (`syscall.Flock`, `LOCK_EX`) on
   `<root>/.speccraft/ledger.lock` — where `<root>` is resolved via
   `FindWorkspaceRoot` so the lock always lands at the workspace root, never a
   member repo — **before their first authoritative ledger read**, and hold it
   until the whole transaction is complete. For `ledger-archive` the single
   held lock spans the full two-file sequence: both-present crash recovery,
   archive append + rename, and live-ledger removal + rename, plus every error
   path. The critical section wraps only in-process work (read → in-memory
   transform → atomic rename) — never a shell-out or network call — so the lock
   is never held across arbitrary latency. In particular the `--expect`
   fingerprint re-verification (AC5) is an **in-process** computation over the
   just-read bytes, equal to what `reconcile <design> | sha256sum` would yield,
   not a shelled-out pipeline. Any read taken before the lock is held is
   non-authoritative and must be re-read under the lock.
2. **No lost update under real contention.** Two concurrent writers serialize —
   both writes land, neither is clobbered — proven by a test that forces both
   writers into the contested interval via a synchronization seam (a barrier /
   injectable hold, not wall-clock timing). Cases target **distinct** ledger
   targets so "both land" is a well-defined invariant regardless of acquisition
   order: `ledger-set` vs `ledger-set` (distinct fields both persist),
   `ledger-set` vs `ledger-archive` (distinct designs), and two
   `ledger-archive`s on distinct designs. (Same-field `ledger-set` races have a
   defined last-writer-wins outcome — AC5 — and are not a lost-update case.)
3. **Bounded acquisition, pinned contract.** Lock acquisition does not block
   indefinitely: acquisition is bounded by a timeout read from
   `SPECCRAFT_LEDGER_LOCK_TIMEOUT` (a Go duration string, default `10s`; an
   unset, empty, invalid, zero, or negative value falls back to the `10s`
   default). Because `syscall.Flock(LOCK_EX)` has no native deadline, the bound
   is implemented at the writer's discretion (`LOCK_NB` polling or a
   cancellation goroutine) — the *contract*, not the mechanism, is normative. On
   contention beyond the timeout the writer exits **non-zero** and its stderr
   contains `ledger busy`. A test sets the timeout to a tiny value against a
   held lock to force the busy path deterministically.
4. **Crash-safe, self-cleaning lock.** The lock is advisory and released by the
   kernel on process exit, so `on success` / `on error` (deferred unlock +
   descriptor close) and `on crash` (kernel release) are the same exit clause —
   a crashed writer leaves **no stale lock** that wedges the next writer, proven
   by a test that holds the lock in a child process, kills it, and shows the
   next acquisition succeeds. The lock file: is created with mode `0644` under
   an `.speccraft/` directory the writer ensures exists first; is never parsed
   as ledger content; is git-ignored the same way `state.json` is (never
   committed); and its descriptor is always closed after unlocking. Adversarial
   filesystem mutation of the lock path (e.g. replacing `ledger.lock` with a
   symlink) is outside the cooperating-writer threat model and not defended
   against.
5. **Semantic CAS re-verified under the lock.** `ledger-archive --expect <fp>`
   keeps its existing meaning — `<fp>` is the `reconcile <design> | sha256sum`
   fingerprint — and still refuses with `conflict: <id> changed` (non-zero) on
   mismatch. The mismatch check is now computed from the ledger bytes read
   *after* the lock is held and *before* any write, closing the op's own
   read → rename window; there is no whole-ledger byte-identity check.
   `ledger-set` intentionally takes **no** `--expect`: it sets a single member
   field, so serialization (AC1/AC2) is sufficient and last-writer-wins on the
   same field is acceptable (this asymmetry is deliberate).
6. **Platform scope stated and tested.** `syscall.Flock` is POSIX; speccraft
   ships linux + macOS binaries only. The lock code compiles and its tests run
   on both; there is no Windows target (a future Windows tarball would need a
   different primitive — out of scope). "Per-host" mutual exclusion is the
   guarantee (advisory flock on a shared local sidecar); network-filesystem
   semantics are out of scope.
7. **No behavior change for the happy path.** With no contention, `ledger-set`
   and `ledger-archive` produce **byte-identical `ledger.md` / `ledger.archive.md`
   contents** to today (existing Go + bats + e2e suites stay green); the only
   new on-disk artifact is the ignored `ledger.lock` sidecar, and locking is
   transparent when uncontended.

## Out of scope

- **`/speccraft:sync --recursive`** (per-member repo-mode fan-out) — split into
  its own spec.
- **`ledger.archive.md` compaction** (bounding the append-only archive) — split
  into its own spec; mechanism still open.
- **Cross-host / network-filesystem locking** — advisory `flock` is per-host;
  the workspace is assumed local, the same scope every ledger writer already
  has.
- **Whole-ledger raw-byte CAS token** — a distinct raw-byte digest was
  considered and rejected; the semantic `reconcile` fingerprint re-verified
  under the lock is sufficient for the caller→op guard.
- **Multi-writer conflict-merge** — the fix is mutual exclusion (serialize) plus
  semantic CAS (refuse), not automatic three-way merge.
- **Windows support** — no Windows binary is shipped; `syscall.Flock` targets
  the shipped linux/macOS platforms only.
- Changes to the ledger grammar, `Reconcile`, or the `orch_*` token machine.

## Open questions

_none_
