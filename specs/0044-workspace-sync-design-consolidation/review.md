# Review — 0044 workspace sync: design-level consolidation & ledger-row archival

**Outcome:** reviewed (quorum met). Four-round cross-model review (codex `gpt-5.6-sol`
+ `claude -p`). codex drove four rounds of substantive hardening; `claude -p` reached
approve-with-comments (all comments addressed). The one residual codex concern is a
system-wide concurrency limitation explicitly bounded + deferred (consistent with the
already-shipped spec 0043 decision), not an 0044-specific defect.

## Verdicts

| Round | codex | claude -p |
|---|---|---|
| 1 | changes-requested | changes-requested |
| 2 | changes-requested | approve-with-comments |
| 3 | changes-requested | — |
| 4 | changes-requested (bounded/deferred) | — |

## Design decisions (the three flagged OQs) — confirmed with the user + reviewers

- **OQ1 rollup record:** colocated `design/<id>-<slug>/outcome.md` via a
  `sync_resolve_design_dir` resolver (glob `design/<id>-*/`, error 0/>1); the optional
  `history.md` note is dropped. Both reviewers pushed for this over the bare `design/<id>/`.
- **OQ2 archive destination:** sibling `.speccraft/ledger.archive.md` (same grammar,
  `ParseLedger`-valid). Both reviewers agreed.
- **OQ3 trigger:** folded into `/speccraft:sync` as step `W4`. Both reviewers agreed.

## Round 1 — both changes-requested (converged, code-grounded)

Both models read the live `ledger.go` and converged on:
- **`Reconcile` vacuous-done hole** — an absent design is `Done=true`, so a typo'd
  `ledger-archive` would silently no-op. → **AC1 four-case contract** on a text-level
  presence check (present+done→archive; present+not-done→refuse+name member;
  absent-live+in-archive→idempotent no-op; absent-both→refuse "unknown design").
- **Two-file move not transactional** (codex) → **AC2 state machine**: append archive
  first, remove live second, both-present crash-residue recovered (verify-equal→remove).
- **outcome.md path ambiguity** (both) → `sync_resolve_design_dir` (AC4).
- **idempotency mechanism + AtomicWriteFile** (both) → AC6 `consolidated:` marker written
  via the byte-safe writer.
- **byte-identity overclaim** (codex) → **byte-level section splice** (not re-serialize),
  genuinely byte-preserving for untouched designs.
- **AC7 vacuous-done predicate** (both) → **AC8** reworded to the structural predicate
  (`ledger-get` emits no rows + `sync_ledger_drift` emits nothing).
- **override-budget-0 placement** (claude, convention) → pinned `ledger-archive` entirely
  in the cmd package (`run()` seam). Plus `LC_ALL=C` sort (AC3).

## Round 2 — claude approve-with-comments; codex one blocker

- **Cross-run snapshot skew** (codex): a conflicted run leaves a stale marked `outcome.md`;
  a later run sees the marker, skips the rewrite, and archives a newer snapshot →
  outcome(A) vs archive(B). → **Fingerprinted marker** (AC6): `consolidated: <date>
  fingerprint: <fp>`; "recorded" iff the marker fingerprint equals the current per-design
  fingerprint, else atomic rewrite before archival. Snapshot scope pinned **per-design**
  (claude), splice boundary cases + archive-file creation + named refusal messages added.

## Round 3 — codex: intra-run TOCTOU

- The shell re-validated then invoked `ledger-archive` as a separate process → check-to-use
  window. → **`ledger-archive <design> --expect <fingerprint>`** (AC1/AC2): the Go op reads
  the ledger once and verifies+splices within that single read; `sync_consolidate_design`
  delegates the guard (no separate shell re-read). This is the atomic compare-and-set for
  the caller→op handoff that 0043 deferred as `ledger-set --expect`.

## Round 4 — codex: residual write-back race (BOUNDED + DEFERRED)

codex confirmed the caller→op skew is closed, then escalated to the deepest variant: the op's
own read→`AtomicWriteFile`(rename) is not a *filesystem* CAS, so a **concurrently running
conductor** could lose a write between the op's read and its rename.

**Scope decision (author, consistent with prior art):** this is the identical single-writer
limitation **every** existing ledger writer already has (`ledger-set`, the conductor itself)
and that **spec 0043 explicitly deferred** (its W3 apply documents the same residual TOCTOU +
scopes a true lock/CAS as a follow-up). Solving it requires a workspace-wide lock or
rename-time CAS spanning **all** writers — a cross-cutting change beyond this spec. Rather
than build that subsystem (or leave a false blanket-atomicity claim codex rightly falsifies),
the spec now: (a) drops the overclaim ("no conductor write can slip"); (b) states the honest
bounded guarantee (caller→op skew closed; residual concurrent-writer race under the shared
single-writer assumption); (c) keeps the append-first/remove-second order so even that failure
mode never destroys archived history; (d) adds an explicit Out-of-scope bullet deferring the
workspace lock / `--expect-bytes` CAS to the same follow-up as 0043. Running consolidation
concurrently with a live `arch:orchestrate` is the user's call — parity with 0043.

## Guardrail / convention violations

Round-1 flagged the override-budget-0 placement (resolved: cmd-package, `run()` seam). None
outstanding.

## Recommendation

Proceed to `/speccraft:spec:plan`. The spec leans on tested primitives
(`ParseLedger`/`Reconcile`/`AtomicWriteFile`, 0043's `sync_ledger_drift`/`ledger-get`), adds
one cmd-package Go op (`ledger-archive`, override budget 0) + five pure `sync.lib.sh` helpers
+ a `W4` step, and its concurrency guarantee is honest and bounded consistent with the shipped
0043 decision.
reviewed_sha256: 7effb5d8f8ac9c9122e14395a0d1afd235ef51d370dc3e3d0a6a10192ee341b5
