---
spec: "0028"
closed: 2026-06-25
---

# Changelog — 0028 Isolate the consolidation e2e fixture legs; pin decline skip-marker behavior

## What shipped vs spec

- Test-harness-only fix; the third in the 0025 → 0027 → 0028 lineage and the one that
  BREAKS THE CYCLE. The spec-0025 consolidation e2e fixture failed on its first real run
  because its DECLINE and CONFIRM legs shared seeded spec 0089, and a `/speccraft:sync`
  decline writes a permanent `consolidation-skip` marker (across-run skip-permanence), so
  the CONFIRM leg could never consolidate 0089; the whole-corpus `/sync` enumeration also
  left the legs un-isolated (0088 eligible early; the lifecycle spec 0001 leaked in). The
  feature behaved exactly as specified — a fixture-design error, not a feature defect.
- `tests/hooks/spec-consolidate.bats`: 4 NEW credit-free meta-test cases (suite now 35
  tests) that RECONSTRUCT each leg's exact corpus per the spec's corpus-state table and
  assert `consolidate_backfill_candidates` returns exactly the intended singleton
  (decline→`0090-decline-source`, confirm→`0089-demo-consolidation`,
  conflict→`0088-conflict-source`), PLUS a `skip-excludes-target` regression case (a
  skip-marked confirm-target is excluded — the original 0089 bug, reproduced at zero
  credits). The three arrangement cases ARE the corpus-state table (CF-B), so a
  fixture-SEEDING regression — not just library-logic drift — is caught on every CI bats
  job. Discrimination was proven by a throwaway corpus mutation (drop 0090's skip → the
  confirm-leg singleton assertion goes RED → revert → GREEN).
- `tests/e2e/spec_consolidate.sh`: reworked to LAZY per-leg seeding — a new
  `0090-decline-source` per the DECLINE leg, `0001` skip-marked ONCE at entry
  (set-and-never-cleared isolation artifact), each source seeded immediately before its
  own `/speccraft:sync`, and NO marker ever cleared (0090's skip is written by the DECLINE
  sync; 0089 is archived by the CONFIRM move). A LOAD-BEARING per-leg AC3 guard sources
  `consolidate.lib.sh` and asserts `consolidate_backfill_candidates "$PWD"` == the leg's
  singleton via a DIRECT invocation (not model-log parsing) before each `run_claude`,
  turning seeding/order drift into a fast, NAMED failure. Pins the decline-writes-skip
  behavior (spec 0025 AC11, previously untested) and the AC8 "only 0090's (feature) +
  0001's (isolation) skips persist; nothing cleared" invariant.
- `tests/e2e/run.sh` `[10/13]`: assert an INLINE-close decline writes NO
  `consolidation-skip` on 0001 — symmetric to the sync-decline-writes-skip leg; pins the
  skip-semantics contrast (sync-decline writes a skip vs. inline-close-decline does not)
  that produced the original bug. Ordered strictly before the `[10e/13]` isolation
  skip-mark on 0001, so the two never observe the dir in a conflicting state.
- Deviation: none material. No `/speccraft:spec:override` (`.sh`/`.bats` are not
  guard-gated); spec-0025 feature code (`consolidate.lib.sh`, `close.md`, `sync.md`,
  `memory-keeper.md`, `SKILL.md`) is BYTE-UNCHANGED; no Go, no feature change.

## Files touched

- tests/hooks/spec-consolidate.bats
- tests/e2e/spec_consolidate.sh
- tests/e2e/run.sh

## Validation / close gate

- Close gate (GREEN, not deferred — unlike specs 0025/0027 whose model tier was deferred):
  the credit-gated `e2e-devcontainer` CI run **28071351196** (push of commit `91e7835`)
  COMPLETED SUCCESS; the full lifecycle went green through `[10/13]` → `[10e/13]`. Spec
  0028's end-to-end confirmation is DONE.
- Local: bats 35/35 green (4 new), Go untouched-green, `bash -n` clean on
  `spec_consolidate.sh` + `run.sh`, `git diff --name-only` lists ONLY the three test files.

## ADR proposed for history.md

See the 2026-06-25 entry (newest-first) in `.speccraft/history.md`.

## Conventions proposed

- New (§Bash → E2E): "Pin a credit-gated fixture's deterministic precondition at the
  credit-free layer" — a credit-free bats meta-test that reconstructs the exact
  arrangement, plus a load-bearing in-fixture direct-invocation runtime guard. The
  distilled lesson of the 0025 → 0027 → 0028 lineage.

## Architecture updates

- None. A three-test-file harness edit; no new package, layer, or boundary.

## Out of scope / follow-ups

- RCA option (3): a distinct consolidation confirm-gate / opt-out so a generic "approve
  all" never silently relocates a spec dir — still a deferred follow-up spec.
- Genuine inline-at-close e2e coverage (a real `/speccraft:spec:close` driving `close.md`
  step 9 inside the fixture) — deferred follow-up; the CONFIRM leg stays sync-driven by
  recorded decision (a real inline close would double the most expensive credit-gated step
  and reintroduce the sticky-skip collision; the close-command WIRING is pinned by
  `specs/0025-.../verify.sh`, the lib MECHANICS by `tests/hooks/spec-consolidate.bats`).
