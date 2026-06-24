---
id: "0028"
title: "Isolate the consolidation e2e fixture legs; pin decline skip-marker behavior"
status: in-progress
created: 2026-06-24
revision: 1
authors: [claude]
packages: []
related-specs: ["0025", "0027"]
---

# Spec 0028 — Isolate the consolidation e2e fixture legs; pin decline skip-marker behavior

## Why

The consolidation e2e fixture (`tests/e2e/spec_consolidate.sh`, added by spec 0025,
documented by spec 0027) has now yielded **two latent bugs on its first real
end-to-end run** — both because the credit-gated lifecycle was deferred and never
executed until spec 0027 cleared the `[10/13]` blocker ahead of it. The legs were
written to *read* plausibly but were never validated against the feature's actual
**whole-corpus** and **sticky-skip** semantics.

The failure that surfaced: `[cons 2/3]` asserts `contains "$DOM" "(spec 0089)"`, but
spec 0089 is never consolidated. Root cause — **the DECLINE leg and the CONFIRM leg
share the same seeded spec (0089)**, which collides with spec 0025's own design:

1. `[cons 1/3]` DECLINE drives `/speccraft:sync` and declines spec 0089. Per spec
   0025 (sync.md / AC11), **declining a backfill candidate writes a
   `consolidation-skip` marker** — the deliberate *across-run skip-permanence*
   invariant: a declined spec is excluded from every future run.
2. `[cons 2/3]` CONFIRM drives `/speccraft:sync` again and asks to approve spec 0089
   — but 0089 now carries `consolidation-skip`, so `consolidate_backfill_candidates`
   correctly **excludes it** (the run log shows `CANDIDATES = [0001-add-farewell-function,
   0088-conflict-source]`, 0089 absent). The model faithfully refused to override a
   recorded decline, so the delta never landed and the assertion failed.

The model and the feature both behaved **exactly as specified** — this is a
**fixture-design error**, not a feature defect: "decline X, then confirm X" is
self-contradictory under sticky-skip semantics.

Two further isolation gaps in the same fixture, exposed by the same run, must be
fixed alongside:

- **B1 — `/speccraft:sync` enumerates the whole candidate corpus, not one spec.**
  Each `[cons N/3]` leg fires `/speccraft:sync`, which sees *all* eligible closed
  specs; the per-spec prompts only pretend to scope. At `[cons 2/3]`, spec 0088 (the
  conflict spec intended for `[cons 3/3]`) is already an eligible candidate and could
  be acted on early. The legs are not mutually isolated.
- **B2 — cross-contamination from the lifecycle spec.** The candidate set at
  `[cons 2/3]` includes `0001-add-farewell-function` — the throwaway lifecycle spec
  that `[10/13]` just closed *in place* (spec 0027 made `[10/13]` decline
  consolidation **inline**, and an inline-close decline does NOT write a
  `consolidation-skip` marker; only a *sync* decline does). So 0001 leaks into the
  consolidation fixture's sync runs.

Beyond fixing this one failure, the fixture needs a deliberate pass so a green run
**means what it claims**: each leg isolated to a single, intended candidate.

## What

A **test-harness-only** fix (no change to the spec-0025 feature code, whose
sticky-skip and whole-corpus semantics are correct). Rework `tests/e2e/spec_consolidate.sh`
so its three legs are mutually isolated and each `/speccraft:sync` run has exactly
one eligible candidate.

- **Independent seeded source spec per leg.** Give each leg its own closed seeded
  spec so one leg's side effects cannot poison another:
  - DECLINE leg → a dedicated source (e.g. `0090-decline-source`),
  - CONFIRM leg → `0089` (the existing ADD+MODIFY delta source),
  - CONFLICT leg → `0088` (the existing non-matching-locator source).
  Seed all three (plus `specs/domains/state.md`) without interdependence.

- **One eligible candidate per `/speccraft:sync` run, via LAZY per-leg seeding
  (isolation).** Arrange the corpus so each leg's `/speccraft:sync` sees ONLY its
  intended spec as a backfill candidate. The mechanism is **lazy per-leg seeding**,
  decisively — NOT pre-mark-and-clear. Concretely:
  - Skip-mark the lifecycle spec `0001-add-farewell-function` ONCE at the start
    (set-and-never-clear, low hazard) so it never leaks into any leg's sync.
  - Seed each leg's source (`0090`, then `0089`, then `0088`) **immediately before
    that leg's own `/speccraft:sync`**, so an unseeded spec simply isn't a candidate.
  - Let each leg self-remove its own source from the candidate corpus afterward: the
    DECLINE leg's `/speccraft:sync` writes `0090`'s own `consolidation-skip`, and the
    CONFIRM leg's archive-move relocates `0089` under `specs/.archive/` (excluded by
    the candidate predicate). **No skip marker ever needs to be cleared.** This is why
    lazy seeding is chosen over pre-mark-and-clear: pre-marking would force a fragile
    skip-marker CLEAR on `0088` between the CONFIRM and CONFLICT legs — exactly the
    kind of ordering step where a 4th latent bug hides.

  Per-leg corpus-state table (state at the moment of each leg's `/speccraft:sync`):

  | Leg            | seeded & under `specs/`        | skip-marked            | archived (`specs/.archive/`) | candidate singleton |
  |----------------|--------------------------------|------------------------|------------------------------|---------------------|
  | `[cons 1/3]` DECLINE | `0001`, `0090`            | `0001`                 | —                            | `0090`              |
  | `[cons 2/3]` CONFIRM | `0001`, `0090`, `0089`   | `0001`, `0090`         | —                            | `0089`              |
  | `[cons 3/3]` CONFLICT| `0001`, `0090`, `0088`   | `0001`, `0090`         | `0089`                       | `0088`              |

  This neutralizes B1 (whole-corpus enumeration) and B2 (lifecycle-spec
  contamination) deterministically, and makes the ordering invariant reviewable
  rather than emergent.

- **Credit-free bats meta-test over the candidate-set logic (in scope).** The
  candidate-set / corpus-arrangement logic is the part that has broken all three
  times (0025 → 0027 → 0028), and it is PURE SHELL — deterministically testable
  WITHOUT the model. Extend the existing `tests/hooks/spec-consolidate.bats` (which
  already tests `consolidate_backfill_candidates` for the closed/under-`specs/`/no-skip
  predicate) with: (a) one case per leg arrangement asserting
  `consolidate_backfill_candidates` returns EXACTLY the intended singleton, and
  (b) the **skip-excludes-target regression case** — a corpus where the confirm-target
  carries a `consolidation-skip` marker, asserting that spec is excluded (this is the
  exact 0089 bug, reproduced at zero credits). This is the primary guard; it runs on
  every CI bats job credit-free and would have caught the original bug without a
  credit-gated run. A bats meta-test is ordinary RED→GREEN TDD, NOT an
  override-requiring bypass — `.bats` is not guard-gated, so "no `/speccraft:spec:override`"
  still holds.

- **Pin the decline skip-marker behavior (new coverage).** The DECLINE leg
  additionally asserts that declining writes a `consolidation-skip` marker on its
  target spec — `exists "specs/0090-decline-source/consolidation-skip"` — positively
  pinning spec 0025's AC11 *"declining writes a skip marker so it is not re-offered"*
  behavior, which is currently untested. It still asserts the domain file and
  `specs/` layout are byte-unchanged.

- **CONFIRM leg stays sync-driven (DECISION).** The CONFIRM leg drives
  `/speccraft:sync` and asserts the positive outcome (the routed domain file carries
  the `(spec 0089)`/suffix-regex requirement, archive-B is non-empty, the dir moved
  under `specs/.archive/` and is gone from `specs/`). This is a recorded decision, not
  an open question: a genuine inline-at-close `/speccraft:spec:close` would double the
  most expensive credit-gated step, reintroduce the sticky-skip collision, and buy
  coverage that two cheaper checks already provide. The CONFIRM leg exercises the same
  `consolidate.lib.sh` route → apply_delta → archive_dir_move path that `close.md`
  step 9 drives inline; the equivalence to a real close is pinned by testable
  artifacts: the close-command **wiring** by
  `specs/0025-spec-consolidation-on-close/verify.sh` (close.md sources
  `consolidate.lib.sh`, confirm-gated) and the lib **mechanics** (incl. the wholesale
  `mv`) by `tests/hooks/spec-consolidate.bats`.

- **Intentional reliance on archive exclusion.** The design INTENTIONALLY relies on
  the spec-0025 feature excluding `specs/.archive/` from the candidate predicate: the
  CONFLICT leg's candidate-set check double-verifies that `0089`'s archival (from the
  CONFIRM leg) removed it from the corpus. This is deliberate defense-in-depth, not an
  accident of ordering.

## Acceptance criteria

1. **Legs use independent seeded specs; no cross-leg poisoning.** The DECLINE,
   CONFIRM, and CONFLICT legs each operate on a distinct seeded spec
   (`0090-decline-source`, `0089-demo-consolidation`, `0088-conflict-source`).
   Declining one leg's spec does not change another leg's candidate eligibility; in
   particular, the CONFIRM leg consolidates `0089` successfully even though the
   DECLINE leg ran first.

2. **Credit-free bats meta-test makes the corpus-state table EXECUTABLE.**
   `tests/hooks/spec-consolidate.bats` is extended with one case per leg arrangement
   that **reconstructs the table's EXACT per-leg corpus** — the same `seeded & under
   specs/` / `skip-marked` / `archived` sets the corpus-state table lists for that leg
   (e.g. CONFIRM: `0001`,`0090`,`0089` seeded, `0001`,`0090` skip-marked, none archived)
   — and asserts a direct invocation of `consolidate_backfill_candidates` returns
   EXACTLY the intended singleton (`0090`, `0089`, `0088` respectively). The three
   bats cases ARE the table, so a fixture-SEEDING regression (not just library-logic
   drift) is caught credit-free. It additionally includes the **skip-excludes-target
   regression case**: a corpus where the confirm-target carries a `consolidation-skip`
   marker yields a candidate set that EXCLUDES that target (reproducing the original
   0089 bug at zero credits). These cases run credit-free on every CI bats job and are
   the primary scoping guard.

3. **Runtime structural candidate guard — LOAD-BEARING, not redundant.** In the
   fixture, before each leg acts, the candidate set is asserted by a DIRECT,
   deterministic invocation of `consolidate_backfill_candidates` (enumerate closed
   specs under `specs/`, minus archived, minus `consolidation-skip`) and compared to
   the leg's intended singleton — NOT by parsing model logs or prose. This is the ONLY
   check that verifies the LIVE runtime corpus the fixture actually built matches the
   intended per-leg arrangement; AC2 verifies the library logic on synthetic inputs,
   so AC3 is NOT duplicate coverage and must not be removed as such — it is what
   catches a fixture-seeding drift at runtime (as a fast, named candidate-set failure
   rather than a confusing downstream `state.md` failure).

4. **Decline writes the skip marker (spec 0025 AC11 coverage).** The DECLINE leg
   asserts that, on decline, `specs/0090-decline-source/consolidation-skip` exists
   and the domain file + `specs/` layout are byte-unchanged (nothing merged, nothing
   moved).

5. **Inline-close decline writes NO skip on 0001 (skip-semantics contrast).** The
   lifecycle `[10/13] /speccraft:spec:close` step in `tests/e2e/run.sh` asserts that
   the inline-close decline writes NO `consolidation-skip` marker on
   `0001-add-farewell-function` — symmetric to AC4, covering the exact sync-decline
   (writes skip) vs. inline-close-decline (writes no skip) distinction that produced
   the original bug.

6. **CONFIRM positive outcome holds deterministically.** Given the isolation, the
   CONFIRM leg's assertions pass: `specs/domains/state.md` contains `(spec 0089)` and
   matches the provenance-suffix regex; `specs/domains/.archive/state.md` exists and
   is non-empty; `specs/.archive/0089-demo-consolidation/spec.md` exists and
   `specs/0089-demo-consolidation` is gone from `specs/`.

7. **CONFLICT leg unaffected; archive-exclusion double-verified.** The CONFLICT leg
   (`0088`, non-matching MODIFY locator) still records
   `specs/0088-conflict-source/consolidation-conflicts.md`, leaves the domain
   byte-unchanged, and does not move the dir — and is reached without the earlier legs
   having consumed or contaminated it. Its candidate-set check (AC3) confirms `0088`
   is the singleton, which double-verifies that `0089`'s archival (from the CONFIRM
   leg) removed it from the corpus via the feature's `specs/.archive/` exclusion.

8. **Lazy seeding: no isolation marker is ever cleared.** The load-bearing invariant
   is that no `consolidation-skip` marker is ever CLEARED during the fixture (that is
   what kills the fragile pre-mark-and-clear hazard). Two persistent skips remain after
   the fixture, and the spec distinguishes them by origin: the only persistent
   FEATURE-generated skip is `specs/0090-decline-source/consolidation-skip` (written by
   the DECLINE leg's own sync-decline); `0001-add-farewell-function`'s skip is a
   deliberate ISOLATION ARTIFACT, set ONCE at the start and never cleared. The fixture
   asserts both persist (set-once, never-cleared) and that no other isolation skip
   marker is created or removed.

9. **Blast radius + green confirmation.** The change touches ONLY
   `tests/e2e/spec_consolidate.sh`, `tests/e2e/run.sh` (the `[10/13]` no-skip
   assertion), and `tests/hooks/spec-consolidate.bats` (the credit-free meta-test).
   The spec-0025 feature code (`consolidate.lib.sh`, `close.md`, `sync.md`,
   `memory-keeper.md`, `SKILL.md`) is byte-unchanged. `bash -n
   tests/e2e/spec_consolidate.sh` and `bash -n tests/e2e/run.sh` are clean; the
   extended bats suite passes credit-free; the full lifecycle going green through
   `[10e/13]` is confirmed by the next `e2e-devcontainer` CI run (credit-gated; same
   deferral as specs 0025/0027). The bats meta-test is ordinary RED→GREEN TDD on a
   non-guard-gated `.bats` file → no `/speccraft:spec:override`.

## Out of scope

- **Changing spec 0025's consolidation behavior.** The sticky `consolidation-skip`
  (across-run skip-permanence) and the whole-corpus `/speccraft:sync` enumeration are
  CORRECT and intended; this spec adapts the fixture to them, it does not alter them.
- **The deferred RCA option (3) follow-up** (a distinct consolidation confirm-gate /
  opt-out so a generic "approve all" never silently relocates a spec dir) — still its
  own future spec; unrelated to fixture isolation.
- **Genuine inline-at-close e2e coverage** (a real `/speccraft:spec:close` driving
  `close.md` step 9 inside the fixture) — explicitly tracked as a SEPARATE follow-up
  spec, not built here. The CONFIRM leg stays sync-driven (see What); equivalence to a
  real close is stood in by the cited `verify.sh` wiring check and the
  `tests/hooks/spec-consolidate.bats` lib mechanics.

## Open questions

_none_
