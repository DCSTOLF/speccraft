---
spec: "0014"
---

# Tasks

- [x] T1 — Create `tests/e2e/lib.sh` with `fail` (guarded log-cat),
  `pass`, `exists`, `contains`, `contains_regex` (new — `grep -qE`),
  `status_is`. Sourceable, `set -euo pipefail`, `${VAR:-}` defaults
  on the `fail()` log-block guards.
- [x] T2 — Refactor `tests/e2e/run.sh` to `source "$E2E_DIR/lib.sh"`
  immediately after the `E2E_DIR=` assignment; delete the now-duplicated
  helper definitions (`fail`, `pass`, `exists`, `contains`, `status_is`)
  from `run.sh`. Verify `bash tests/e2e/run.sh --language-only` passes
  locally.
- [x] T3 — Add `tests/e2e/contains_adr_assertion_test.sh` (executable)
  that sources `lib.sh`, sanity-checks AC3 against
  `templates/speccraft/history.md`, exercises a positive case (ADR
  header present) and a negative case (template-only, subshell-inverted
  exit) of `contains_regex` against `^## 20[0-9]{2}-[0-9]{2}-[0-9]{2}`.
- [x] T4 — Add `run_helper_unit_tests()` sibling function to `run.sh`
  that invokes the new fixture; call it from both the `--language-only`
  short-circuit and the lifecycle dispatch (immediately before
  `run_language_fixtures` in both). Bump the cosmetic `[N/M]` step
  counters (`/10` → `/11`); add new `[11/11] Helper unit tests (spec
  0014)` echo line in the lifecycle block.
- [x] T5 — Flip the brittle assertion at `tests/e2e/run.sh:278` from
  `contains ".speccraft/history.md" "farewell"` to
  `contains_regex ".speccraft/history.md" "^## 20[0-9]{2}-[0-9]{2}-[0-9]{2}"`.
  Verify AC1 mechanically: presence grep returns 1, absence grep
  returns 0.
- [x] T6 — AC3 RED-baseline sanity grep: `grep -nE '^## 20[0-9]{2}-[0-9]{2}-[0-9]{2}'
  templates/speccraft/history.md` returns zero matches. Already
  verified during planning; re-confirm post-edit in case any
  unrelated template change snuck in.
- [x] T7 — Local verification gate: `bash tests/e2e/run.sh
  --language-only` runs green (all four existing language cycles +
  the new helper-unit-test step). Then push for AC4 — the next
  `e2e-devcontainer` CI run on `main` passes step `[7/9]
  /speccraft:spec:close` regardless of memory-keeper's ADR title;
  the run URL goes in `changelog.md` per the spec-0008 close-commit
  invariant.
