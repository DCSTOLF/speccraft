---
id: "0027"
title: "Restore e2e lifecycle green after inline-at-close consolidation"
status: closed
created: 2026-06-23
authors: [claude]
packages: []
related-specs: ["0025"]
---

# Spec 0027 — Restore e2e lifecycle green after inline-at-close consolidation

## Why

Spec 0025 added an inline, confirm-gated **consolidation** step to
`commands/spec/close.md` (step 9). In the credit-gated e2e lifecycle
(`tests/e2e/run.sh`), the `[10/13] /speccraft:spec:close` step is driven with the
prompt *"Approve all proposed memory updates"*, and `claude -p` swept the
consolidation confirm-gate into that blanket approval. With the throwaway
lifecycle spec `0001-add-farewell-function` carrying no `domains:` frontmatter and
hitting **zero conflicts**, consolidation ran to completion and — as its final,
by-design step — **moved the spec directory** `specs/0001-add-farewell-function/`
→ `specs/.archive/0001-add-farewell-function/`. The pre-0025 post-close assertion
`run.sh:367` (`exists "$SPEC_DIR/changelog.md"`, where
`$SPEC_DIR=specs/0001-add-farewell-function`) then fails: the changelog rode along
to the archived path and is no longer at the asserted location.

This is a **test/feature interaction regression**, not a feature defect — spec 0025
behaved exactly as specified (zero conflicts ⇒ relocate the closed dir as the
commit signal). The break is that a pre-0025 lifecycle assertion was never updated
for the new dir-relocating close. It escaped the merge gate because the bats tier
and `verify.sh` exercise the helpers/doc-contracts in isolation, and the model-tier
lifecycle was credit-gated and deferred — exactly where it surfaced.

## What

A **test-harness-only** fix (no change to the spec-0025 feature code) with two
parts, mirroring the two confirm-gates the lifecycle should exercise separately:

- **(2) Make `[10/13]` decline consolidation.** Change the `run_claude` prompt at
  `tests/e2e/run.sh` (the `[10/13] /speccraft:spec:close` step) so the blanket
  approval covers ONLY the memory-keeper updates and **explicitly declines /
  defers the spec-consolidation step**, leaving the closed spec directory in place
  under `specs/0001-add-farewell-function/`. This keeps the existing post-close
  assertions (changelog at the original path, etc.) valid. Add a structural
  assertion that proves the decline held — the dir was NOT moved to
  `specs/.archive/` — so the decline is verified, not merely assumed.

- **(1) Cover the inline-at-close CONFIRM path positively at `[10e/13]`.** The
  dedicated consolidation fixture (`tests/e2e/spec_consolidate.sh`) currently
  exercises the confirm → merge → archive → dir-move outcome through the
  `/speccraft:sync` backfill path (the same `consolidate.lib.sh` functions
  `close.md` step 9 calls). Ensure the inline-at-close path is positively asserted:
  a confirmed consolidation leaves the spec dir under `specs/.archive/<id>/` (gone
  from `specs/<id>/`), `specs/domains/<area>.md` carries the merged requirement with
  a `(spec NNNN)` / `(specs …)` provenance suffix, and the moved dir retains its
  `changelog.md`/`spec.md`. If the existing sync-driven CONFIRM leg already asserts
  the move + suffixed merge (it does), extend the fixture so the **close-command
  inline wiring** itself is covered (or document the lib-path equivalence
  explicitly), so declining at `[10/13]` does not leave the inline-at-close path
  untested.

Net effect: the two close confirm-gates are tested on separate paths — `[10/13]`
covers close + memory updates with consolidation **declined** (dir stays), and
`[10e/13]` covers consolidation **confirmed** (dir moves + domain merge) — and the
full `tests/e2e/run.sh` lifecycle progresses past `[10/13]` through `[10e/13]`
without any path-based assertion failing because of the consolidation dir-move.

## Acceptance criteria

1. **`[10/13]` declines consolidation; the dir stays and legacy assertions hold.**
   After the `[10/13] /speccraft:spec:close` step, `specs/0001-add-farewell-function/`
   still exists (it is NOT under `specs/.archive/`), `specs/0001-add-farewell-function/changelog.md`
   exists at that original path, and the existing post-close assertions
   (`run.sh:367` `exists "$SPEC_DIR/changelog.md"` and the `[10/13]` history-ADR
   check) pass. A new structural assertion verifies the non-move
   (`[ ! -d specs/.archive/0001-add-farewell-function ]`).

2. **`[10e/13]` positively covers the inline-at-close consolidation path.** The
   `spec_consolidate` fixture asserts, for a CONFIRMED consolidation, structural
   outcomes of the inline-at-close path: the consolidated spec dir is present under
   `specs/.archive/<id>/` and absent from `specs/<id>/`; the routed
   `specs/domains/<area>.md` exists and a merged line matches the
   `(spec NNNN)` / `(specs …)` provenance-suffix regex; and the moved dir retains
   its `changelog.md` (the close-written artifact rides along). These are structural
   predicates only (existence / path / regex), never model prose.

3. **The full lifecycle reaches green through `[10e/13]`.** A `tests/e2e/run.sh`
   run progresses past `[10/13]` and through `[10e/13]` with no path-based
   assertion failing due to the consolidation dir-move. Deterministically
   verifiable now via `bash -n tests/e2e/run.sh` + `bash -n tests/e2e/spec_consolidate.sh`
   and inspection that the changed assertions are structural; the full credit-gated
   run is confirmed by the next `e2e-devcontainer` CI run (same deferral as spec
   0025's model tier).

4. **Blast radius: test harness only.** The change touches ONLY `tests/e2e/run.sh`
   and `tests/e2e/spec_consolidate.sh`. The spec-0025 feature code
   (`commands/spec/consolidate.lib.sh`, `commands/spec/close.md`,
   `commands/sync.md`, `agents/memory-keeper.md`, `skills/speccraft-context/SKILL.md`)
   is byte-unchanged — the feature behaved as designed; this is a harness fix. No
   Go code, no new lib, so no `/speccraft:spec:override` is needed.

## Out of scope

- **Changing spec 0025's consolidation behavior.** The zero-conflict dir-move is
  correct and intended; this spec does not alter `consolidate.lib.sh`, `close.md`,
  or `sync.md`.
- **RCA option (3): a distinct consolidation confirm-gate / opt-out so a generic
  "approve all" never silently relocates a spec dir.** This is a more principled
  UX change to the close flow (so real users aren't surprised) and belongs in its
  own follow-up spec, not this harness hotfix.
- **Re-running / re-pinning the deterministic bats tier or `verify.sh`** — those
  already pass and are unaffected (they test the lib/doc contracts, not the
  lifecycle wiring).

## Open questions

_none — the fix is scoped by the accepted RCA: (2) decline at `[10/13]` keeps the
legacy assertions valid; (1) `[10e/13]` owns the positive confirm-path coverage.
The plan resolves whether (1) extends the existing sync-driven CONFIRM leg with an
explicit close-wiring assertion or adds a separate inline-at-close leg; the
preference is to extend the existing fixture rather than drive a second full,
credit-heavy `/speccraft:spec:close`._
