---
spec: "0018"
closed: 2026-06-13
---

# Changelog — 0018 technical-review (red→green parity for Go/Python/JS-TS)

## What shipped vs spec

Closes technical-review finding **P0-1**: the "TDD red→green invariant" was a real
observed-failure check only for Rust; Go/Python/JS-TS merely verified a sibling test file
was *touched* this session. After this spec, all four languages run the session's
just-added sibling test through a real runner and require an observed failure before
unlocking a production edit.

- **Just-added capture model (D1).** New `Session.RedCandidates map[string][]string`
  (JSON `red_candidates,omitempty`, single-writer in `state.go`, cleared on `SessionStart`).
  Captured in the `IsTestFile` dispatch branch via `captureRedCandidates`: pre-edit disk
  content vs `applyEdit`-modelled post-edit content, each run through the per-language
  test-id extractors `GoTestIDs`/`PythonTestIDs`/`JSTSTestIDs` (regex, `lang_testids.go`);
  just-added = post-edit minus pre-edit ids, keyed on the absolute test-file path.
- **siblingRedCheck** (shared by the Go/Python guard and the JS/TS dispatcher) resolves the
  sibling test files, unions their captured `RedCandidates`, resolves an adapter via the new
  factory, runs it under a 30s deadline, and accepts only when a `failed` record's id is in
  the just-added set.
- **D1 deliberate divergence:** an empty just-added set **blocks** (unlike Rust's
  allow-on-empty, which is backed by the persisted `rust_test_baseline`). This is what
  closes the blank-line-touch bypass (AC10).
- **D2 fail-closed:** `runner.AdapterForLanguage(lang, cfg) (Runner, bool)`; `ok==false`
  (e.g. empty JS/TS command, unknown lang) → BLOCK "no test runner available", never a
  touch-check fallback.
- **Adapters** `GoAdapter`/`PytestAdapter`/`JSTSAdapter` (one shared JS/TS adapter; JS and
  TS differ only by configured command) reuse `classifyOutcome`; honor new
  `[tdd.go]`/`[tdd.python]`/`[tdd.javascript]`/`[tdd.typescript]` `command` config
  (Go default `go test`, Python default `pytest`, JS/TS no default → fail-closed).
  `splitCommand` helper added in `runner.go`.
- **AC9:** real adapter invocation bounded by `context.WithTimeout(30s)`; a timeout/error
  surfaces as a Go error (not a new `Outcome`), and the guard blocks. **AC6:**
  build/collection failure (`OutcomeBuildFailed`) is *not* a valid RED and blocks distinctly.
- The old touch-check (`hasSiblingTestEdited`) and the JS/TS session-membership loop were
  removed.
- **Docs/memory (AC11):** `architecture.md` layer-8 + §Key-decisions scrubbed of the
  spec-0005 Rust-only non-goal; `guardrails.md`, `index.md`, and the
  `speccraft-technical-review.md` §4 matrix updated to state red→green parity. A new Go-test
  oracle `docs_parity_test.go` greps those surfaces to keep them honest.

### Deviations from spec

- **Parsed-but-unused config gap (T24).** Implementation found `GoAdapter`/`PytestAdapter`
  needed to actually honor the `[tdd.go]`/`[tdd.python]` `command` keys to support hermetic
  stub-based fixtures; added as an in-cycle task.
- **E2E fixtures encoded the old contract (T25/T26).** `python_cycle.sh` and
  `javascript_cycle.sh` were rewritten to the red-check model using a hermetic
  *configured-stub* runner (no real pytest/node); `javascript_cycle.sh` adds a
  runner-absent fail-closed (D2) scenario.

### Mid-implementation amendment (2026-06-12, AC13)

The pre-edit red-check cannot observe a brand-new symbol's just-added test as a runtime RED:
the test won't compile until the symbol exists, so the pre-edit run is a build failure, which
AC6 correctly refuses to treat as RED — and the gated production edit is the one that would
make it compile. This is identical to Rust's existing behavior; the pre-0018 touch-check
merely hid it. Resolution (chosen over relaxing AC6 or an apply-edit-in-memory redesign): a
one-shot `/speccraft:spec:override` for the symbol-introduction edit, documented as AC13.
`run.sh` step 9 was rewritten to test-edit → `/speccraft:spec:override` → production edit.
The guard/spec override-command strings were also corrected from `/spec:override` to the
fully-qualified `/speccraft:spec:override`. **Deferred follow-up:** an apply-edit-in-memory
red-check that runs against the post-edit package (so a new symbol's test compiles and fails
at runtime, eliminating the override step).

## Files touched

- tools/cmd/speccraft-guard/main.go, main_test.go
- tools/internal/speccraft/lang_testids.go (new), lang_testids_test.go (new)
- tools/internal/speccraft/state.go, state_test.go, state_single_writer_test.go
- tools/internal/speccraft/config.go, config_test.go
- tools/internal/speccraft/docs_parity_test.go (new)
- tools/internal/speccraft/runner/go_adapter.go (new) + _test.go
- tools/internal/speccraft/runner/pytest_adapter.go (new) + _test.go
- tools/internal/speccraft/runner/jsts_adapter.go (new) + _test.go
- tools/internal/speccraft/runner/runner.go, runner_test.go
- tests/e2e/run.sh, tests/e2e/python_cycle.sh, tests/e2e/javascript_cycle.sh
- .speccraft/architecture.md, .speccraft/guardrails.md, .speccraft/index.md
- speccraft-technical-review.md (the review report, committed with the spec)
- specs/0018-technical-review/{spec,plan,tasks,review}.md

## Review

Two-round cross-model review (codex + claude-p). Round 1: both `changes-requested` (five
blockers — runner-absent fallback, missing architecture.md AC, AC1 conflation, selector
granularity, no timeout contract). Round 2: both `approve-with-comments`; quorum 1 met.
Planning settled OQ-A as config-only JS/TS detection and AC9 default timeout `d`=30s.

## Post-merge / close gate

PR #1 merged to `main` (merge commit `ddc1136`; feature commit `8c74168`, parent `46d3788`).
CI green per user confirmation: `e2e-language-only` + `unit` (linux/macos) + `hooks` on the
PR; `e2e-devcontainer` — the credit-gated full `claude -p` lifecycle job — runs on push to
`main` post-merge and is the gate that exercises AC13 (test-edit → `/speccraft:spec:override`
→ new-symbol production edit, `farewell()`) at step 9.
