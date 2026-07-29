---
spec: "0028"
---

# Tasks

- [x] T1 — Credit-free bats meta-test: add 4 `@test` cases to `tests/hooks/spec-consolidate.bats` encoding the per-leg corpus table (decline→0090, confirm→0089, conflict→0088 singletons) + skip-excludes-target-0089 regression; prove discrimination via a throwaway corpus mutation (RED) — AC2, AC9
- [x] T2 — Fixture lazy seeding: rework `tests/e2e/spec_consolidate.sh` — add NEW `0090-decline-source` closed seed, skip-mark `0001` once at entry, seed `0090`/`0089`/`0088` each just before its leg, repoint DECLINE prompt at `0090` (GREEN) — AC1
- [x] T3 — Fixture AC3 runtime guard: source `consolidate.lib.sh`, assert `consolidate_backfill_candidates "$PWD"` equals each leg's singleton (0090 / 0089 / 0088) via direct invocation before each `run_claude` (GREEN, load-bearing) — AC3
- [x] T4 — Fixture assertions: DECLINE pins `exists specs/0090-decline-source/consolidation-skip` + domain/layout byte-unchanged (AC4); keep CONFIRM 0089 positive asserts (AC6) + CONFLICT 0088 asserts (AC7); end-of-fixture assert both `0090` and `0001` skips persist and no other isolation skip exists (AC8) — AC4, AC6, AC7, AC8
- [x] T5 — run.sh [10/13]: assert `[ ! -e "$SPEC_DIR/consolidation-skip" ]` after spec 0027's non-move assertion (inline-close decline writes NO skip on 0001), ordered before the [10e/13] isolation skip-mark — AC5
- [x] T6 — Verify: `bash -n` on `spec_consolidate.sh` + `run.sh`; run extended bats suite credit-free (MUST pass); confirm `git diff --name-only` lists ONLY the three test files (feature code byte-unchanged); full lifecycle through [10e/13] deferred to next credit-gated e2e CI — AC9
