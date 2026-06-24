---
spec: "0028"
rev: 1
date: 2026-06-24
reviewers: [codex, claude-p]
quorum: 1
verdict: approve-with-comments
round: 2
---

# Cross-model review — 0028 e2e consolidation fixture isolation (round 2)

## codex

**Verdict:** changes-requested

Concerns:

- AC8 and the lazy-seeding design contradict each other. AC8 says "only 0090's skip persists," but the design also skip-marks 0001 ONCE at the start and never clears it. Both 0090 AND 0001 carry persistent skips after the fixture; only the framing (feature-generated vs. isolation-artifact) distinguishes them. The corpus-state table is otherwise internally correct — it relies on 0001 being skip-marked — but that assumption is the unresolved hole: the table proves isolation by RELYING on a persistent 0001 marker while AC8 requires only 0090 to persist.

Suggestions:

- Make 0001 handling explicit and consistent: either document 0001's skip as a deliberate isolation artifact that persists by design, or avoid leaving a new 0001 skip while still proving AC5. Use the framing "the only persistent FEATURE-generated skip is 0090's; 0001's isolation skip also persists by design (set-once, never-cleared); no isolation marker is ever cleared."

All other round-1 items confirmed resolved: AC2/AC3 pin the candidate guard to `consolidate_backfill_candidates` credit-free in `spec-consolidate.bats` with per-leg arrangements + skip-excludes-target regression; CONFIRM sync-driven captured as a decision; 0088 ordering explicit; AC5 `[10/13]` no-skip-on-0001 added.

## claude-p

**Verdict:** approve-with-comments

All five round-1 carry-forwards genuinely resolved: CF-1 credit-free bats meta-test in scope + AC2/AC3 direct invocation; CF-2 lazy seeding decisive + corpus-state table + AC8; CF-3 AC5 `[10/13]` no-skip; CF-4 numbering clean 1-9; CF-5 sync-driven decision + citations + archive-exclusion + inline follow-up.

Concerns:

- The AC2 bats meta-test pins LIBRARY semantics (skip-marked target excluded) credit-free, catching library-logic regressions. But the original 0089 failure was a FIXTURE-SEEDING bug (shared 0089 + decline-skip on it). A synthetic library-level bats test cannot, by construction, exercise `spec_consolidate.sh`'s runtime seeding sequence. The credit-free catch for the seeding class is AC3's direct `consolidate_backfill_candidates` invocation — credit-free in mechanism but currently only fires INSIDE the credit-gated e2e harness. So library drift is caught in the bats job; fixture-seeding drift still needs the credit-gated CI run (now as a fast, named candidate-set failure, not a confusing downstream `state.md` failure).
- AC8 headline "only 0090's skip persists" contradicts the same AC's "0001's skip set once and never cleared" and the corpus-state table (0001 skip-marked at every leg). Both 0090 and 0001 carry persistent skips; only the framing distinguishes them. [Same issue codex blocks on.]

Suggestions:

- Make the corpus-state table EXECUTABLE rather than documentary: have the AC2 bats arrangement-cases mirror the table's EXACT (seeded / skip-marked / archived) sets per leg, so the three bats cases ARE the table. This turns the meta-test into a true credit-free cycle-breaker for the SEEDING class, closing the gap above.
- State explicitly in AC3 that it is LOAD-BEARING, not merely redundant-with-AC2: it is the only check that verifies the LIVE runtime corpus matches the intended per-leg arrangement (AC2 verifies library logic on synthetic inputs). Prevents a future cleanup deleting it as "duplicate coverage."
- Tighten AC8 wording: "the only persistent FEATURE-generated skip is 0090's; 0001's isolation skip also persists by design (set-once, never-cleared); no isolation marker is ever cleared."
- Make the bats path consistent everywhere: `tests/hooks/spec-consolidate.bats` (AC9 parenthetical and the What section must agree).

## Synthesis

QUORUM MET. claude-p approves-with-comments; codex's one remaining concern (AC8 internal contradiction) is a wording fix, not a design flaw — both reviewers agree the lazy-seeding design itself is correct and that 0001's persistent skip is a deliberate, correct isolation artifact. The contradiction is that AC8's headline does not yet say so.

Both reviewers confirm all five round-1 carry-forwards are resolved: independent per-leg seeded specs, lazy seeding decisively stated with a corpus-state table, credit-free bats meta-test in scope, clean AC numbering 1-9, and sync-driven CONFIRM captured as a decision with citations. The isolation design, the corpus-state invariant, the [10/13] no-skip contrast assertion, and the archive-exclusion defense-in-depth are all sound.

Four small items remain (CF-A through CF-D below), all foldable pre-flip per repo precedent (spec 0016, spec 0025 round-2). Status flips to **reviewed** after the folds.

## Carry-forwards (folded into spec.md before status flip)

**CF-A (BOTH — codex blocks; wording fix):** Reconcile the AC8 contradiction. The design is correct; the headline is not. Reword AC8 so it is consistent with the corpus-state table and the design: BOTH 0090 and 0001 carry a persistent skip after the fixture. 0090's is FEATURE-generated (the sync-decline writes it). 0001's is a deliberate ISOLATION ARTIFACT (set-once, never-cleared). The load-bearing invariant is "NO isolation marker is ever CLEARED," not "only 0090 persists." Use claude-p's suggested wording: "the only persistent FEATURE-generated skip is 0090's; 0001's isolation skip also persists by design (set-once, never-cleared); no isolation marker is ever cleared."

**CF-B (claude-p — closes the seeding-class gap):** Make the corpus-state table EXECUTABLE. The AC2 bats arrangement-cases must mirror the table's EXACT per-leg (seeded / skip-marked / archived) sets, so the three bats cases ARE the table. This makes the credit-free meta-test exercise the seeding-class of bug (the actual 0089 bug class), not just library-logic drift on synthetic inputs — closing the gap that AC3 currently covers only inside the credit-gated harness.

**CF-C (claude-p — prevents future cleanup regression):** State explicitly in AC3 that it is LOAD-BEARING: it is the only check that verifies the LIVE runtime corpus matches the intended per-leg arrangement (AC2 verifies library logic on synthetic inputs; AC3 verifies the fixture's seeding sequence at runtime). Mark it as not redundant-with-AC2 so it is not deleted as "duplicate coverage" in a future cleanup.

**CF-D (claude-p — minor consistency):** Make the bats path consistent everywhere in the spec. The canonical path is `tests/hooks/spec-consolidate.bats`; verify the What section, AC2, AC3, and AC9 all use this exact path.

## Recommended next step

Fold CF-A through CF-D into `spec.md` now (pre-reviewed-flip, per 0016/0025 precedent — all four are wording-level or structural clarifications, zero design change), then flip status to `reviewed` and run `/speccraft:spec:plan`.
