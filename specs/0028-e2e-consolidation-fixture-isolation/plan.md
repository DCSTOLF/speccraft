---
spec: "0028"
status: planned
strategy: tdd
---

# Plan — 0028 Isolate the consolidation e2e fixture legs; pin decline skip-marker behavior

> **Override needs: NONE.** This is a TEST-HARNESS-ONLY change touching three test
> files (`tests/hooks/spec-consolidate.bats`, `tests/e2e/spec_consolidate.sh`,
> `tests/e2e/run.sh`). The spec-0025 feature code (`commands/spec/consolidate.lib.sh`,
> `commands/spec/close.md`, `commands/sync.md`, plus `memory-keeper.md` / `SKILL.md`)
> is BYTE-UNCHANGED. `.bats` and `.sh` test files are NOT guard-gated, so the
> TDD red→green cycle here requires no `/speccraft:spec:override`.

## Orientation (confirmed against the tree)

- `consolidate_backfill_candidates()` lives at `commands/spec/consolidate.lib.sh:349`.
  It enumerates `"$repo"/specs/*/` (the glob hides `.archive`), `continue`s on
  `domains`, requires `^status:[[:space:]]*closed` in `spec.md`, `continue`s on any
  dir carrying a `consolidation-skip` file, and `printf`s the basename — one per line.
  **DO NOT MODIFY.**
- The bats suite (`tests/hooks/spec-consolidate.bats`) `setup()` (lines 10-46) builds a
  `mktemp -d` `TEST_REPO`; tests `source "$LIB"` then call helpers. The existing
  candidate test is at line 390; its assertion idiom is
  `run consolidate_backfill_candidates "$TEST_REPO"` then
  `printf '%s\n' "$output" | grep -qx "<dir>"` (and `! … | grep -qx` for exclusions).
  The new cases mirror this exactly.
- The fixture `tests/e2e/spec_consolidate.sh` has `_spec_consolidate_seed()` (line 34)
  and `spec_consolidate()` (line 79): DECLINE leg lines 91-92 (currently declines
  **0089** — MUST repoint to a NEW `0090-decline-source`), CONFIRM leg lines 115-116
  (0089), CONFLICT leg lines 131-132 (0088). `fail/pass/exists/contains/contains_regex`
  come from `tests/e2e/lib.sh` (in scope when sourced by `run.sh`).
- `tests/e2e/run.sh` `[10/13]` step is lines 365-376; `SPEC_DIR` resolves to
  `specs/0001-add-farewell-function` (line 279). Spec 0027's non-move assertion is
  lines 374-375. AC5's new no-skip assertion is appended right after it.

## Per-leg corpus-state table the fixture + bats meta-test must realize

| Leg                 | seeded & under `specs/` | skip-marked     | archived (`specs/.archive/`) | candidate singleton |
|---------------------|-------------------------|-----------------|------------------------------|---------------------|
| `[cons 1/3]` DECLINE | `0001`, `0090`          | `0001`          | —                            | `0090`              |
| `[cons 2/3]` CONFIRM | `0001`, `0090`, `0089`  | `0001`, `0090`  | —                            | `0089`              |
| `[cons 3/3]` CONFLICT| `0001`, `0090`, `0088`  | `0001`, `0090`  | `0089`                       | `0088`              |

`0090`'s skip appears only AFTER the DECLINE leg's sync-decline writes it (feature
behavior). `0089` is archived only AFTER the CONFIRM leg's `mv`. **Nothing is ever
cleared.**

## Test-first sequence

> Ordering rationale: the DETERMINISTIC, CREDIT-FREE bats meta-test goes FIRST — it is
> the cycle-breaker (the candidate-set logic is what broke in 0025→0027→0028), runs on
> every CI bats job at zero credits, and is the real local gate. The credit-gated
> fixture rework follows, then the `run.sh` AC5 assertion, then verify.

### Step 1 — Credit-free bats meta-test: encode the per-leg corpus table + the skip-excludes-target regression (RED) — AC2

- Extend `tests/hooks/spec-consolidate.bats` (after the existing candidate test that
  ends at line 409). Add FOUR `@test` cases, each building its corpus inside `TEST_REPO`
  (mirroring `setup()`'s `mkdir -p` + heredoc + `touch` idiom) and asserting via
  `run consolidate_backfill_candidates "$TEST_REPO"` then
  `printf '%s\n' "$output" | grep -qx "<dir>"` / `! … | grep -qx`:
  - `Test_consolidate_backfill_candidates_decline_leg_singleton_is_0090`
    — seed CLOSED `0001-add-farewell-function` + `0090-decline-source` under `specs/`,
    skip-mark `0001` (`touch …/consolidation-skip`); assert output is EXACTLY `0090-decline-source`
    (present; `0001` excluded; nothing else).
  - `Test_consolidate_backfill_candidates_confirm_leg_singleton_is_0089`
    — seed CLOSED `0001`, `0090`, `0089-demo-consolidation`; skip-mark `0001` AND `0090`;
    assert output is EXACTLY `0089-demo-consolidation`.
  - `Test_consolidate_backfill_candidates_conflict_leg_singleton_is_0088`
    — seed CLOSED `0001`, `0090`, `0088-conflict-source`; skip-mark `0001` AND `0090`;
    place `0089` under `specs/.archive/0089-demo-consolidation/` (archived, excluded by
    the `specs/*/` glob); assert output is EXACTLY `0088-conflict-source`.
  - `Test_consolidate_backfill_candidates_skip_excludes_confirm_target_0089`
    — the original-bug regression: seed CLOSED `0089-demo-consolidation` AND carry a
    `consolidation-skip` on it; assert output does NOT contain `0089-demo-consolidation`
    (`! … | grep -qx`). This reproduces the 0089 sticky-skip collision at zero credits.
- **RED nature (stated honestly):** these cases pin EXISTING-CORRECT library behavior,
  so against the unmodified `consolidate.lib.sh` they PASS on first run. The
  discriminating power (the "RED") is demonstrated by a THROWAWAY corpus mutation — e.g.
  drop the `0090` skip-mark in the confirm-leg case, observe the singleton assertion FAIL
  (output now `0090-decline-source\n0089-demo-consolidation`), then revert. The test
  fails iff someone (a) breaks the lib OR (b) mis-encodes the table — which is precisely
  the fixture-seeding regression class this guards. Record the mutation check in the
  task as the proof-of-discrimination step.

### Step 2 — Fixture: lazy per-leg seeding + new 0090 source + repoint DECLINE (GREEN) — AC1

- Rework `tests/e2e/spec_consolidate.sh`:
  - Split `_spec_consolidate_seed()` (line 34) into the domain-only seed plus
    per-source seed helpers (or inline lazy seeds). Concretely add a NEW closed source
    `_spec_consolidate_seed_0090()` writing `specs/0090-decline-source/spec.md`
    (`status: closed`, `domains: [state]`, a trivial well-formed `delta:` — a single ADD
    such as `ADD: a farewell helper note (spec 0090)`). Keep the `0089` and `0088` seeds
    as separate per-leg helpers (`_seed_0089`, `_seed_0088`) so each lands immediately
    before its own leg's sync.
  - In `spec_consolidate()` (line 79): seed `specs/domains/state.md` once; **skip-mark
    `0001-add-farewell-function` ONCE at entry** (`mkdir -p specs/0001-add-farewell-function`
    if needed, `touch specs/0001-add-farewell-function/consolidation-skip`) — the
    set-once isolation artifact that keeps `0001` out of every leg.
  - DECLINE leg (was lines 91-92): seed `0090` first, then **repoint the prompt at
    `0090-decline-source` (NOT 0089)** — "When the consolidation backfill proposes
    folding spec 0090 … DECLINE it".
  - CONFIRM leg (lines 115-116): seed `0089` immediately before its sync; prompt
    unchanged in intent (confirm 0089).
  - CONFLICT leg (lines 131-132): seed `0088` immediately before its sync; prompt
    unchanged (0088 conflict).
- All Step-1 bats cases still pass (lib untouched). `bash -n` clean.

### Step 3 — Fixture: per-leg AC3 runtime candidate-singleton guard (GREEN, LOAD-BEARING) — AC3

- In `tests/e2e/spec_consolidate.sh`, immediately BEFORE each leg's `run_claude`, add a
  DIRECT invocation guard (NOT log parsing): `source` the plugin's
  `commands/spec/consolidate.lib.sh` once near the top of `spec_consolidate()`, then per
  leg compute `cands="$(consolidate_backfill_candidates "$PWD")"` and assert it equals
  the leg's singleton — e.g.
  `[ "$cands" = "0090-decline-source" ] || fail "[cons 1/3] candidate set not singleton 0090: <$cands>"`,
  then `0089-demo-consolidation` for CONFIRM, `0088-conflict-source` for CONFLICT.
  (Resolve the lib path from the same plugin dir `run.sh` uses; a single-line equality
  on the trimmed output is sufficient because each leg's corpus is engineered to a
  singleton.)
- This is the ONLY check that verifies the LIVE corpus the fixture built; it turns a
  seeding drift into a fast, NAMED failure rather than a confusing downstream `state.md`
  failure. Step-1 bats still pass.

### Step 4 — Fixture: DECLINE pins the skip marker; CONFIRM/CONFLICT/AC8 asserts (GREEN) — AC4, AC6, AC7, AC8

- DECLINE leg (AC4): after the decline `run_claude`, assert
  `exists "specs/0090-decline-source/consolidation-skip"` (positively pinning spec 0025
  AC11 "declining writes a skip marker"); keep the byte-unchanged domain assertion
  (`cmp -s "$SNAP_DOM" "$DOM"`) and the `specs/`-layout-unchanged checks, repointed to
  `0090` (the dir must remain under `specs/`, not moved to `.archive`).
- CONFIRM leg (AC6): keep the existing positive asserts on `0089` (lines 119-127):
  `contains "$DOM" "(spec 0089)"`, `contains_regex "$DOM" "$PROV_SUFFIX_RE"`,
  `exists "$ARCH"` + non-empty, `exists specs/.archive/0089-demo-consolidation/spec.md`,
  `[ ! -d specs/0089-demo-consolidation ]`.
- CONFLICT leg (AC7): keep the existing conflict asserts on `0088` (lines 134-138). The
  Step-3 AC3 guard for this leg (`cands == 0088-conflict-source`) double-verifies that
  `0089`'s CONFIRM-leg archival removed it from the corpus via the feature's
  `specs/.archive/` exclusion.
- End-of-fixture (AC8): after all three legs, assert BOTH persistent skips remain
  (set-once, never-cleared): `exists "specs/0090-decline-source/consolidation-skip"`
  (feature-generated, from the DECLINE sync) AND
  `exists "specs/0001-add-farewell-function/consolidation-skip"` (isolation artifact);
  and assert no OTHER isolation skip exists — e.g. `[ ! -e specs/0088-conflict-source/consolidation-skip ]`
  and `[ ! -e specs/.archive/0089-demo-consolidation/consolidation-skip ]` (0089 was
  archived by CONFIRM, never skip-marked). `bash -n` clean.

### Step 5 — run.sh [10/13]: assert inline-close decline writes NO skip on 0001 (GREEN) — AC5

- In `tests/e2e/run.sh`, in the `[10/13]` step, immediately AFTER spec 0027's non-move
  assertion (lines 374-375) add:
  `[ ! -e "$SPEC_DIR/consolidation-skip" ] || fail "[10/13] inline-close decline wrote a consolidation-skip on 0001 (sync-decline semantics leaked into inline close)"`.
- This pins the sync-decline (writes skip) vs inline-close-decline (writes NO skip)
  contrast — symmetric to AC4. **Temporal note:** this assertion runs at `[10/13]`,
  strictly BEFORE the `[10e/13]` fixture's set-once isolation skip-mark on `0001`, so the
  two never conflict (0001 carries no skip at [10/13]; it acquires the isolation skip
  only once spec_consolidate() runs).

### Step 6 — Verify (no new code) — AC9

- `bash -n tests/e2e/spec_consolidate.sh` and `bash -n tests/e2e/run.sh` — must be clean.
- Run the extended bats suite (`bats tests/hooks/spec-consolidate.bats`) — credit-free,
  MUST pass. This is the real local gate.
- Confirm `git diff --name-only` shows ONLY `tests/e2e/spec_consolidate.sh`,
  `tests/e2e/run.sh`, `tests/hooks/spec-consolidate.bats` changed; feature files
  (`commands/spec/consolidate.lib.sh`, `commands/spec/close.md`, `commands/sync.md`,
  `agents/memory-keeper.md`, plugin `SKILL.md`) byte-unchanged.
- The full lifecycle going green through `[10e/13]` is DEFERRED to the next
  `e2e-devcontainer` CI run (credit-gated; same deferral as specs 0025/0027). No
  `/speccraft:spec:override` — `.bats`/`.sh` are not guard-gated.

## Delegation

- Steps 1-6 → keep in-thread (the work is shell + bats with no language-specialist
  strength to match). No sub-agent delegation needed; this is a single-surface
  test-harness edit.

## Risk

- **(i) The meta-test pins LIBRARY logic on SYNTHETIC corpora.** AC2's bats cases
  reconstruct each leg's corpus by hand, so they exercise
  `consolidate_backfill_candidates` against inputs the test author wrote — the fixture's
  actual SEEDING sequence (`_seed_0090` → DECLINE → `_seed_0089` → CONFIRM → …) is
  exercised end-to-end only in the credit-gated `e2e-devcontainer` run (claude-p's
  caveat: a meta-test on synthetic inputs cannot prove the live fixture builds those
  inputs). **Mitigation:** the bats cases mirror the table's EXACT per-leg sets (CF-B's
  exact-table-mirroring), so a *mis-encoded table* is caught credit-free; and AC3's
  per-leg DIRECT `consolidate_backfill_candidates "$PWD"` invocation reduces any live
  seeding drift to a fast, NAMED candidate-set `fail` at the top of the offending leg —
  not a confusing downstream `state.md`/`contains` failure.
- **(ii) Lazy-seeding ORDER is load-bearing.** `0090`'s skip exists only AFTER the
  DECLINE sync; `0089` is archived only AFTER the CONFIRM `mv`; nothing is ever cleared.
  A mis-ordered seed (e.g. seeding `0089` before the DECLINE leg) would make two
  candidates eligible. **Mitigation:** the AC3 per-leg singleton guard runs before EACH
  leg acts and fails the instant the corpus is not the intended singleton, catching any
  mis-order deterministically.
- **(iii) AC5 temporal coupling with the isolation skip on 0001.** The `[10/13]`
  no-skip-on-0001 assertion and the `[10e/13]` fixture's set-once isolation skip-mark on
  `0001` both target the same dir. **Mitigation:** they are ordered — `[10/13]` asserts
  NO skip at close time (correct, since inline-close decline writes none), and the
  fixture only ADDS the isolation skip later at `[10e/13]`; the two never observe the
  dir in a conflicting state.
- **(iv) Blast-radius regression.** A stray edit to feature code would violate AC9.
  **Mitigation:** Step 6 gates on `git diff --name-only` listing exactly the three test
  files.
