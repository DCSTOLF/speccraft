# Cross-model review — spec 0045 (ledger write-locking)

**Final verdict: approved** (quorum met). Converged over three rounds; both
reviewers at approve-tier with zero remaining concerns, only plan-time notes.

| Round | codex | claude-p |
|-------|-------|----------|
| 1 (full)   | changes-requested | approve-with-comments |
| 2 (scoped) | approve-with-comments | approve |
| 3 (scoped) | approve-with-comments | approve |

## Round 1 — must-fix (all resolved)

1. **AC4 CAS was internally inconsistent (both reviewers).** The spec described a
   *byte-level* CAS while `--expect` is the `reconcile <design> | sha256sum`
   fingerprint — a **semantic projection**, not a raw-byte digest, so it cannot
   establish whole-ledger byte identity. → **Resolved (AC5):** kept as a semantic
   CAS on the existing fingerprint, re-derived from the ledger bytes read *under
   the lock* and compared before any write; the whole-ledger byte-identity claim
   was dropped (and a raw-byte token explicitly rejected in Out of scope). The
   `ledger-set` vs `ledger-archive` asymmetry (only archive takes `--expect`) is
   now stated deliberately.
2. **Lock must span the whole two-file archive transaction (codex).** AC1 named
   only the live-ledger interval. → **Resolved (AC1):** one held lock spans
   both-present crash recovery, archive append+rename, live-ledger
   removal+rename, and every error path.
3. **Timeout interface underspecified (both).** → **Resolved (AC3):**
   `SPECCRAFT_LEDGER_LOCK_TIMEOUT` (Go duration, default `10s`), non-zero exit,
   verbatim `ledger busy` on stderr, deterministic forced-busy test.

### Round 1 — should-fix (all resolved)

- Non-authoritative pre-lock reads → AC1 (authoritative read only under the lock).
- Real contention seam, not wall-clock → AC2 (barrier/injectable hold, three pair combos).
- Portability precision → AC6 (POSIX flock; linux+macOS only; Windows + network-fs OOS).
- Lock-file lifecycle → AC4 (mode `0644`, ensures `.speccraft/` first, never parsed, gitignored like `state.json`, descriptor closed).
- Workspace-root resolver named → AC1 (`FindWorkspaceRoot`; never a member repo).
- AC1/AC3 exit-release overlap → AC4 (success/error/crash unified as one exit clause).
- AC5 "byte-identical to today" wording → AC7 (scoped to `ledger.md`/`ledger.archive.md` contents; names the new `ledger.lock` sidecar).

## Round 2 → 3 — minor comments (folded in as clarifications)

- **In-process fingerprint (claude-p, load-bearing).** AC5 defined `<fp>` in
  shell-pipeline terms while AC1 forbids shell-outs in the critical section. →
  AC1 now states the `--expect` re-verification is an **in-process** computation
  over the just-read bytes (equal to what the pipeline would yield), preserving
  the bounded critical-section cost.
- **Distinct-target contention (codex).** AC2 now scopes "both land" to distinct
  ledger targets (well-defined regardless of acquisition order) and points
  same-field races at AC5's defined last-writer-wins.
- **Timeout fallback (codex).** AC3 now defines unset/empty/invalid/zero/negative
  → fall back to `10s`, and notes `flock(LOCK_EX)` has no native deadline so the
  bound is by-discretion (`LOCK_NB` polling or cancellation goroutine); the
  contract, not the mechanism, is normative.
- **Symlink/adversarial mutation (codex).** AC4 now states adversarial mutation
  of the lock path is outside the cooperating-writer threat model.

## Carried to plan.md (implementation notes, not spec changes)

- **codex S1:** if the timeout is implemented via a cancellation goroutine, a
  timed-out acquisition must be cancelled so a leaked goroutine cannot *later*
  grab and hold the lock after `ledger busy` was already returned.
- **codex S2 / AC3:** add tests for the timeout fallback on empty, invalid, zero,
  and negative values (now observable behavior).
- **claude-p S1:** any existing test asserting *exactly* `ledger busy` moves to a
  substring/`Contains` match (AC3 loosened "prints exactly" → "stderr contains").
- **claude-p S2:** record the chosen bound mechanism (poll vs cancel-goroutine)
  consciously in plan.md — observably different under contention, neither leaks.

## Guardrail / convention violations

None across all three rounds.

## Per-agent final verdicts

- **codex — approve-with-comments** (round 3): 0 concerns, 0 guardrail/convention
  violations, 2 plan-time suggestions (S1, S2 above).
- **claude-p — approve** (round 3): 0 concerns, "no spec change requested," 2
  nice-to-have implementation-integration notes (carried to plan).
reviewed_sha256: 0e942ea5975fd446d5694e5fcf4a24f02fab5cd2cd70451d3b6a72bc14b3cd05
