---
spec: "0020"
---

# Tasks

- [x] T1 — Add `tests/e2e/revise_noop_assertion_test.sh` meta-test: Scenario A (run.sh no-op line uses `contains_regex`), Scenario B (pattern matches `no changes — spec unchanged`, `no-op`, `byte-identical` — AC1), Scenario C (rejects unrelated line); mirrors ADR fixture conventions (RED)
- [x] T2 — Wire `revise_noop_assertion_test.sh` into `run_helper_unit_tests` in `tests/e2e/run.sh` (subshell `|| fail`), runs in `--language-only` + full paths (still RED)
- [x] T3 — Replace fixed-string `contains` at `tests/e2e/run.sh:289` with `contains_regex "$LOG_DIR/06-revise-noop.log" "[Nn]o.?op|[Nn]o changes|byte-identical|unchanged"` (AC1, GREEN)
- [x] T4 — Confirm `^revision: 1` structural assertion at the no-op step retained unchanged (AC2)
- [x] T5 — Verify `bash -n tests/e2e/run.sh` and `bash -n tests/e2e/revise_noop_assertion_test.sh` parse cleanly; reuse existing `contains_regex` (no new helper) (AC3)
- [x] T6 — (optional refactor) Not needed — fixture is small and readable as written; no extraction helper introduced
