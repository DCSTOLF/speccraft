---
spec: "0020"
closed: 2026-06-15
---

# Changelog — 0020 Robust e2e revise no-op assertion

## What shipped vs spec

Implemented exactly as specified; no deviations.

- AC1: the `[6/13] /speccraft:spec:revise no-op` step in `tests/e2e/run.sh` now uses
  `contains_regex "$LOG_DIR/06-revise-noop.log" "[Nn]o.?op|[Nn]o changes|byte-identical|unchanged"`
  (was fixed-string `contains "no changes"`). The pattern matches the command's deterministic
  marker (`no changes — spec unchanged`) and the model paraphrases that broke CI (`no-op`,
  `byte-identical`).
- AC2: the structural `contains_regex "$SPEC_DIR/spec.md" "^revision: 1"` check at the no-op
  step is retained unchanged — it remains the load-bearing proof the no-op branch ran.
- AC3: `bash -n` clean on both `run.sh` and the new fixture; the existing `lib.sh`
  `contains_regex` helper is reused (no new helper).

## Files touched

- `tests/e2e/run.sh` — no-op assertion swapped to `contains_regex` (+ explanatory comment);
  `run_helper_unit_tests` now also invokes the new meta-test.
- `tests/e2e/revise_noop_assertion_test.sh` (new, 112 lines, mode 100755) — meta-test mirroring
  the spec-0014 `contains_adr_assertion_test.sh`. Reads run.sh's *live* no-op assertion line
  (anchored on `06-revise-noop.log`, fails unless exactly one match), then: Scenario A asserts
  the line is a `contains_regex` call (the spec-0020 RED); Scenario B extracts run.sh's live
  pattern and asserts it matches `no changes — spec unchanged`, `no-op`, `byte-identical`;
  Scenario C asserts it rejects an unrelated real-change line (inverted via subshell).

## Process notes

- Genuine RED→GREEN on a shell-only change (no Go hook gates `.sh`): the meta-test was observed
  RED (Scenario A failed on the fixed-string `contains`, exit 2) before the run.sh swap, GREEN
  after.
- Design choice — duplication vs extraction of the regex: did NOT extract a shared pattern var
  (consistent with the ADR precedent + the spec's out-of-scope "no new helper"), but the fixture
  reads run.sh's LIVE pattern at runtime, so the two cannot silently diverge.
- The meta-test runs inside `run_helper_unit_tests`, which executes in BOTH the credit-free
  `--language-only` path and the full-lifecycle path — so it is a real close gate without API
  credits (contrast spec 0017/0018, whose model-behaviour e2e steps are credit-gated and
  nondeterministic).
- Planned with `--skip-review`. Go suite unaffected (no Go changed).

## Memory updates

- `history.md`: ADR `2026-06-15 — Tolerant regex for the e2e revise no-op assertion; meta-test
  reads run.sh's live predicate (spec 0020)`.
- `conventions.md`: new sub-section "Assertion meta-test reads run.sh's LIVE predicate" under the
  existing spec-0014 `lib.sh` "exact predicate" entry (second use of the pattern).
- `architecture.md`: no change (helper-unit-test fixtures are below the granularity of item 12).

## Follow-ups

_none._ The original CI failure (brittle no-op assertion) is resolved and guarded by the meta-test.
