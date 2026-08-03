---
id: "0044"
title: "workspace sync: design-level consolidation & ledger-row archival"
status: reviewed
created: 2026-07-31
authors: [claude]
packages: ["commands", "tools/cmd/speccraft-state"]
related-specs: ["0037", "0038", "0039", "0040", "0042", "0043"]
informed-by: [design/0001-architect-lifecycle-orchestration]
---

# Spec 0044 — workspace sync: design-level consolidation & ledger-row archival

## Why

Spec 0043 gave `/speccraft:sync` a workspace mode that reconciles **ledger drift** and
**membership drift** — but the ledger only ever *grows*. Every design the conductor
drives leaves a permanent per-member section in `.speccraft/ledger.md`, even long after
that design is fully `done` (all members `closed`). This is the workspace analog of the
context-bloat problem speccraft fights everywhere else: closed specs consolidate into
`specs/domains/<area>.md` and their silos archive to `specs/.archive/`; `history.md`
compacts; only a bounded working set stays live. The workspace ledger has no such bound —
a workspace that has shipped twenty designs carries twenty designs' worth of stale member
rows in the file every `ledger-get`/`reconcile` reads.

This spec closes that gap: **drift class C**, design-level consolidation. When a design is
fully `done`, sync folds it into a durable **rollup record** and **archives its ledger
rows** out of the live ledger — keeping the active ledger bounded and current as designs
accumulate, exactly as spec consolidation keeps `specs/` bounded. It completes the
workspace-sync arc (A + B in 0043, C here) and applies the same consolidate-then-archive
discipline the repo side already enforces.

## What

Add a **design-consolidation pass** (step `W4`) to `/speccraft:sync`'s workspace branch,
after 0043's ledger/membership reconciliation. For every design whose rows are still live
but which `reconcile` reports **`done`**, sync proposes — confirm-gated — to (1) write a
durable rollup record colocated with the design and (2) archive that design's rows out of
`.speccraft/ledger.md`. Declining leaves everything byte-identical. Confirmed design
decisions (the three flagged OQs, now resolved with the user): the rollup record is a
**colocated `design/<id>-<slug>/outcome.md`** (no `history.md` note); the archive is a
**sibling `.speccraft/ledger.archive.md`** (same grammar, `ParseLedger`-valid); the pass
is **folded into `/speccraft:sync` as `W4`**, not a separate command.

**Decomposition.** Deterministic mechanics extend `commands/sync.lib.sh` (bats-tested);
`commands/sync.md`'s workspace branch gains the confirm-gated `W4` step. One new sanctioned
Go ledger operation does the byte-safe row move.

- **`speccraft-state ledger-archive <design> [--expect <fingerprint>]`** (new) — the
  sanctioned archival op **and the single atomic authority** for the move, implemented
  **entirely in `tools/cmd/speccraft-state/`** (like spec 0036's `moveArtifactNoReplace`),
  so it rides the `run()` seam (a pre-impl call is a runtime `unknown subcommand`, not a
  build failure) → **override budget 0**; it reuses only the already-exported
  `ParseLedger`/`Reconcile`/`AtomicWriteFile`. It reads the live ledger **once** and, within
  that single read, verifies done-ness, verifies `--expect` (when given) against the freshly
  recomputed fingerprint, and does the row move as a **byte-level section splice** on the raw
  `ledger.md` text (keyed on the `## design <id>` boundary), never a parse→re-serialize
  round-trip — so untouched designs stay **byte-identical** (a genuine splice). Collapsing the
  verify+splice into one process closes the *caller→op* handoff skew (the shell no longer
  validates in one process and archives in another). A residual write-back race against a
  *concurrently running* conductor remains — the op's read-to-rename is not a filesystem CAS,
  the same single-writer assumption every existing ledger writer (`ledger-set`, the conductor
  itself) operates under and that spec 0043 explicitly deferred (see Out of scope). Its full
  contract is AC1 (four-case + `--expect`) + AC2 (transactional + byte-preserving).
- **`sync_resolve_design_dir <root> <id>`** (shell) — resolve the ledger's bare `<id>` to
  its on-disk `design/<id>-<slug>/` directory by globbing `design/<id>-*/`; exactly one
  match prints the path, zero matches → non-zero "no design dir", ≥2 → non-zero
  "ambiguous". Pure/testable.
- **`sync_design_rollup_body <root> <design>`** (shell) — render the outcome record body
  from `reconcile`: an optional `consolidated: <date>` header line + one
  `<member> → <spec-ref> → <status>` line per member in `reconcile` order.
- **`sync_done_live_designs <root>`** (shell) — the candidates: design ids both present in
  `ledger-get` and `reconcile`-`done`, `LC_ALL=C`-sorted, one per line.
- **`sync_consolidate_design <root> <design>`** (shell) — orchestrate one design's
  consolidation, crash-safe and snapshot-bound (AC6): resolve its dir, capture **this
  design's** `reconcile` rows as a snapshot + a fingerprint, write
  `design/<id>-<slug>/outcome.md` via a byte-safe writer carrying a **fingerprinted**
  `consolidated:` marker **before** archival, and re-validate the snapshot byte-equal
  immediately before `ledger-archive` (changed → a named `conflict`, archive skipped). The
  fingerprint in the marker is what makes the outcome idempotent *and* skew-proof across
  runs: a re-run recaptures the design's current rows and rewrites `outcome.md` unless the
  marker's fingerprint already matches — so a stale outcome left by an earlier conflicted
  run is never archived behind (it is rewritten to match the rows that get archived).

## Acceptance criteria

1. **`ledger-archive` four-case contract (no vacuous-done hole).** `speccraft-state
   ledger-archive <design>` distinguishes, using a **text-level presence check** on the
   live ledger and the archive plus `Reconcile` for the done test (so `Reconcile`'s
   vacuous-done-for-absent semantics never leak):
   - **present in live + `done`** → archive it (AC2). When `--expect <fingerprint>` is
     given, the op recomputes this design's fingerprint from its single ledger read and, if
     it differs from `<fingerprint>`, **refuses** with message `conflict: <id> changed` and
     writes nothing (the atomic guard against a mutation between the caller's capture and the
     archive read).
   - **present in live + not `done`** → exit non-zero, message `design not done: <members>`;
     both files byte-unchanged.
   - **absent from live + present in archive** → idempotent no-op, exit 0 (already archived).
     (The `present in BOTH files` crash-residue state is the recovery leg of AC2, not a
     refusal.)
   - **absent from both** → exit non-zero, distinct message `unknown design: <id>`.
   The four exit messages are stable strings callers/tests can assert on. Rides the `run()`
   seam, logic in the cmd package (**override budget 0**). Go-tested for all four cases
   (files byte-unchanged on both refuse paths).

2. **Transactional, byte-preserving section move.** On a `done` design, `ledger-archive`
   **appends** the design's section to `.speccraft/ledger.archive.md` **first**, then
   **removes** it from `.speccraft/ledger.md` — so a crash leaves a recoverable
   both-present state, never lost history. Re-entry with the section present in **both**
   files verifies they are equal, then completes by removing the live copy (exit 0). Writes
   go through `AtomicWriteFile` (temp+rename). Untouched designs in `ledger.md` remain
   **byte-identical** (section splice, not re-serialize); the archived section round-trips
   verbatim and `.speccraft/ledger.archive.md` parses via `ParseLedger`. A parse-corrupt
   `ledger.archive.md` makes `ledger-archive` **refuse** (non-zero, no write), mirroring
   0043's parse-vs-semantic split (message `ledger.archive.md: <parse error>`). The section
   detector keys on the same heading grammar `ParseLedger` accepts (a line equal to
   `## design` or prefixed `## design `). If `.speccraft/ledger.archive.md` does not yet
   exist it is **created** via `AtomicWriteFile` carrying the standard `# Ledger` preamble
   the serializer uses, so the archive is byte-shaped like a real ledger and
   `ParseLedger`-valid. Go-tested including the splice **boundary cases** — the target
   section at file start, at file end, as the sole section, and flanked by two others (so an
   "empty after splice" or start/end-of-file splice cannot regress) — plus: multi-design →
   only the target moves & other sections byte-identical; both-present crash-residue →
   completed; re-run → no-op; corrupt archive → refuse; **`--expect` mismatch → `conflict`,
   no write**. The `--expect` verification and the splice share the **same single
   `ParseLedger`/read of `ledger.md`**, closing the caller→op handoff window (a value the
   caller captured earlier can never be archived under a different one without a `conflict`).
   This is not a filesystem compare-and-swap: a write by a *concurrently running* conductor
   between the op's read and its rename is still possible under active concurrency — bounded
   by the single-writer assumption shared by all ledger writers and deferred to the same
   follow-up as spec 0043's `ledger-set --expect` lock (see Out of scope). The append-first/
   remove-second order keeps even that failure mode non-destructive of archived history.

3. **`sync_done_live_designs` enumerates exactly the candidates.** Given a mix of done and
   in-progress designs, `sync_done_live_designs <root>` prints exactly the design ids both
   present in `ledger-get` and `reconcile`-`done`, one per line, **`LC_ALL=C`-sorted**. A
   workspace whose live designs are all in progress prints nothing. bats-tested
   (mix → only the done id; all-in-progress → empty).

4. **`sync_resolve_design_dir` resolves id → slugged dir with error cases.**
   `sync_resolve_design_dir <root> <id>` globs `design/<id>-*/`: exactly one match prints
   its path (exit 0); zero → non-zero "no design dir for <id>"; ≥2 → non-zero "ambiguous
   design dir for <id>". bats-tested (happy, missing, ambiguous).

5. **`sync_design_rollup_body` renders a deterministic per-member record.**
   `sync_design_rollup_body <root> <design>` emits one `<member> → <spec-ref> → <status>`
   line per member in `reconcile` order, covering every member. The header MAY carry a
   `consolidated: <date>` line (used by AC6's idempotency marker); the falsifiable assertion
   is the deterministic set of member lines, not the date. bats-tested for a two-member done
   design.

6. **`sync_consolidate_design` is crash-safe, atomic, snapshot-bound, and skew-proof
   across runs.** It (a) resolves the design dir via `sync_resolve_design_dir`; (b) captures
   **this design's** `reconcile` rows (per-design, NOT the whole workspace — so a conductor
   touching an *unrelated* design never false-conflicts this one) and computes a
   **fingerprint** over them; (c) writes `design/<id>-<slug>/outcome.md` through a byte-safe
   writer (`AtomicWriteFile` or shell `mktemp`+`mv`) **before** archival, carrying a
   `consolidated: <date> fingerprint: <fp>` marker; (d) treats the outcome as "already
   recorded" **iff** the file exists AND its marker fingerprint **equals the current
   captured fingerprint** — a missing marker (partial write) OR a *mismatching* fingerprint
   (a stale outcome from an earlier conflicted run, describing older rows) forces an atomic
   rewrite, so the outcome always matches the rows that will be archived; (e) invokes
   `ledger-archive <design> --expect <fp>`, delegating the mutation-guard to the Go op's
   atomic read-verify-splice (AC1/AC2) — the shell does **not** do a separate re-read-then-
   invoke (which would leave a check-to-use window); a conductor touching *this* design
   between capture and archive makes the Go op's recomputed fingerprint differ from `<fp>`,
   so it returns `conflict` and writes nothing, and `sync_consolidate_design` reports it
   (the outcome file, already fingerprint-matched, is corrected on the next run). This closes
   the cross-run skew: Run 1 conflicts and leaves an
   `outcome.md` marked with fingerprint(A); if the design then advances to B, Run 2's
   captured fingerprint(B) ≠ the marker's fingerprint(A) → `outcome.md` is rewritten to B
   before B is archived — the durable record can never describe an older snapshot than the
   archived rows. bats: happy path (outcome written + rows archived); matching-fingerprint
   re-run (no rewrite, no duplicate); record-then-simulated-crash-then-re-run (rows
   eventually archived, no duplicate); snapshot-changed mid-run → `conflict`, no archive;
   **stale-fingerprint re-run → `outcome.md` rewritten to the current rows before archival.**

7. **`W4` is confirm-gated and declines cleanly.** `commands/sync.md`'s workspace branch
   gains a `W4` step after 0043's W1–W3: it runs `sync_done_live_designs`, presents each
   done design's proposed rollup + the rows to be archived, and applies
   `sync_consolidate_design` **only on confirm**; declining leaves `ledger.md`,
   `ledger.archive.md`, and `design/` byte-identical. No done-and-live design → proposes
   nothing. Asserted by a source-scan fence: the `W4` block appears under the
   `<!-- speccraft:sync:workspace -->` anchor, **after** the W1–W3 ledger/membership steps
   (the ordering is load-bearing — W3's `ledger-set` fixes must land before W4's `reconcile`
   decides a design is done), and calls `sync_done_live_designs`/`sync_consolidate_design`;
   the interactive prompt is credit-gated (spec-0042/0043 convention).

8. **Consolidation takes the design off the hot path (structural predicate).** After a
   design is consolidated, `speccraft-state ledger-get` emits **no rows** for it and 0043's
   `sync_ledger_drift` emits **nothing** for it — the falsifiable assertion is the *absence
   of live rows*, NOT `reconcile` reporting vacuous `done`. Proven by the e2e (AC9).

9. **Hermetic e2e detect→consolidate round-trip.** `tests/e2e/workspace_consolidate_cycle.sh`
   (registered in `tests/e2e/run.sh`) builds a hermetic workspace with a real
   `design/<id>-<slug>/` dir, one fully-`done` design (members `closed`), and one
   in-progress design; runs `sync_done_live_designs` (asserts only the done id),
   `sync_consolidate_design`, then asserts: `design/<id>-<slug>/outcome.md` exists with each
   member's outcome line; the done design's rows are gone from `ledger-get` but present in
   `.speccraft/ledger.archive.md` (re-read parses via `ParseLedger`); the in-progress
   design's rows are byte-untouched; and a second run is a clean no-op **both ways** —
   `outcome.md` byte-unchanged AND `ledger-archive` exits 0 via AC1's "absent from live +
   present in archive" branch. No model credits.

## Out of scope

- **Un-consolidation / re-opening a consolidated design** — moving rows back from the
  archive. Archival is one-directional; re-opening is a manual edit if ever needed.
- **Compaction of `ledger.archive.md`** — it grows append-only (off the hot path). A future
  compaction pass (à la `/speccraft:history:compact`) could bound it; not now.
- **Auto-consolidation without confirmation** — `W4` always proposes and never archives a
  design without an explicit confirm (parity with spec consolidation at close).
- **A `history.md` note for consolidated designs** — the colocated `outcome.md` is the sole
  rollup record (OQ1 resolved); no secondary `.speccraft/history.md` entry is written by W4.
- **Cross-design/domain rollup** — folding multiple designs into a shared workspace
  "domains" file (the design analog of `specs/domains/`). One rollup record per design here;
  a domain-level merge is a later idea.
- **Any change to the 0043 ledger-drift / membership passes or the 0040 token machine** —
  W4 runs after them and only adds the done-design archival.
- **A workspace-wide ledger lock / true rename-time compare-and-swap across all writers** —
  `ledger-archive --expect` closes the caller→op handoff skew (outcome and archived rows can
  never describe different snapshots), but the op's own read-to-rename is not a filesystem
  CAS, so a *concurrently running* conductor could still lose a write in a narrow window.
  This is the identical single-writer limitation every existing ledger writer (`ledger-set`,
  the conductor) already has and that spec 0043 explicitly deferred; closing it fully needs a
  shared lock or a rename-time CAS spanning **all** writers (a `ledger-set --expect` +
  `ledger-archive --expect-bytes` cross-cutting change), which is the follow-up — not this
  spec. As with 0043's W3 apply, running consolidation concurrently with a live
  `arch:orchestrate` is the user's call.

## Open questions

_none — the three prior OQs are resolved: colocated `design/<id>-<slug>/outcome.md`
(no history.md note), sibling `.speccraft/ledger.archive.md`, and a `W4` step inside
`/speccraft:sync`._
