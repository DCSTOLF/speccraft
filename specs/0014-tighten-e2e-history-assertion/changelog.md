---
spec: "0014"
closed: 2026-06-10
---

# Changelog — 0014 Tighten e2e history.md assertion to ADR structural match

## What shipped vs spec

Shipped as specified. Two coupled changes landed across seven tasks:

1. New `tests/e2e/lib.sh` (T1) extracting `fail`, `pass`, `exists`,
   `contains`, `contains_regex` (NEW — `grep -qE`), and `status_is`
   into a sourceable shared module. `fail()` guards its log-cat
   block with `${VAR:-}` default-empty expansion on `$LAST_LOG` /
   `$LOG_DIR` / `$LOG_DIR/$LAST_LOG` so it is `set -u`-safe when
   called from fixtures that don't set those variables.
2. `tests/e2e/run.sh` refactored (T2) to `source "$E2E_DIR/lib.sh"`
   immediately after the `E2E_DIR=` capture at line 23 (before any
   `cd`). The duplicate helper definitions were removed.
3. New fixture `tests/e2e/contains_adr_assertion_test.sh` (T3) that
   sources the same `lib.sh` and exercises the *exact* predicate
   the production assertion uses against two synthetic histories
   (positive: well-formed ADR header; negative: template-only,
   subshell-inverted exit). Includes the AC3 precondition sanity
   check against `templates/speccraft/history.md`.
4. New sibling `run_helper_unit_tests()` in `run.sh` (T4) called
   from both the `--language-only` short-circuit AND the full
   lifecycle dispatch — helper-first ordering so a helper
   regression fails fast before the language cycles run.
5. The brittle assertion at `run.sh:278` flipped (T5) from
   `contains ".speccraft/history.md" "farewell"` to
   `contains_regex ".speccraft/history.md" "^## 20[0-9]{2}-[0-9]{2}-[0-9]{2}"`.

## Deviations

- **Step-counter placement.** Plan §Step 4 literally specified the
  new helper-test echo line as `[11/11]` added *above* the existing
  `[8/10]` line. The executor placed it as `[8/11]` instead — first
  in sequential order, matching the planner's stated fail-fast
  intent without the visual oddity of `11` appearing before `8`.
  Functionally equivalent (single edit, same dispatch ordering,
  same CI pickup); cosmetic only. The remaining language-dispatch
  echoes were bumped to `[9/11]`, `[10/11]`, `[11/11]` in lockstep.
- No aux-agent delegation occurred. Plan §Delegation said none was
  needed; executor agreed. No deviation from plan, noted for the
  record.

## AC4 close-gate evidence

CI run 27287309940 on commit `b535629` (post-spec push):
https://github.com/DCSTOLF/speccraft/actions/runs/27287309940

- All five jobs green.
- `e2e-devcontainer` step `[7/9] /speccraft:spec:close` emitted
  `PASS: contains_regex .speccraft/history.md: ^## 20[0-9]{2}-[0-9]{2}-[0-9]{2}`
  — the structural pattern matching memory-keeper's ADR header
  regardless of the model-chosen ADR title.
- `e2e-language-only` ran the new
  `contains_adr_assertion_test.sh` fixture as the first sibling
  step before the existing language cycles.

Pre-spec baseline failure for comparison: CI run 27276707529
attempt 2/3 on commit `ed3fe24` failed at step `[7/9]` with
`FAIL: expected 'farewell' in .speccraft/history.md`. Three
attempts on `ed3fe24` failed identically (one
`ENVIRONMENT_FAILURE: credit_exhausted` per spec 0008, two with
non-feature-named ADR titles like *"Defer stdout-capture testing
for main()"*). The previous green run on commit `9c1330d`
(27275588005) was the same flake getting lucky.

## Files touched

- `tests/e2e/lib.sh` (new)
- `tests/e2e/contains_adr_assertion_test.sh` (new)
- `tests/e2e/run.sh` (refactor: source `lib.sh`, drop duplicate
  helpers, add `run_helper_unit_tests`, flip assertion at line
  278, renumber `[N/M]` counters)
- `.speccraft/index.md` (active_spec bump)
- `specs/0014-tighten-e2e-history-assertion/` (spec, plan, tasks,
  review, this changelog)

## Conventions proposed

Two additions, both under §Bash:
- "E2E assertion predicates: structural over content" — the
  principle (structural signals over model-chosen content).
- "Shared assertion helpers via `tests/e2e/lib.sh` (exact
  predicate invariant)" — the mechanism (extract to lib.sh,
  source both sides, sibling-not-flag for new predicates).

## Out-of-scope follow-ups still queued

- README + `speccraft-v1-spec.md` CodeGraphContext cleanup (from
  spec 0011's §Out of scope).
- `/speccraft:spec:revise` command (from spec 0011's §Out of
  scope).

Neither was touched by this spec; both remain queued.
