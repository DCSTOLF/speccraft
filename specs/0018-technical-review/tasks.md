---
id: "0018"
title: "technical-review"
---

# Tasks

- [x] T1 — RED: per-language test-id extractor tests (lang_testids_test.go)
- [x] T2 — GREEN: implement GoTestIDs/PythonTestIDs/JSTSTestIDs (lang_testids.go)
- [x] T3 — RED: RedCandidates Session field accessor tests (state_test.go)
- [x] T4 — GREEN: implement RedCandidates field + Get/SetRedCandidates (state.go)
- [x] T5 — RED→GREEN: extend single-writer allow-list for RedCandidates
- [x] T6 — RED: capture-red-candidates-on-test-edit tests (Go/Python/JS-TS)
- [x] T7 — GREEN: implement captureRedCandidates in IsTestFile dispatch branch
- [x] T8 — RED: config [tdd.go]/[tdd.python]/[tdd.javascript]/[tdd.typescript] tests
- [x] T9 — GREEN: implement Go/Python/JS/TS config sections + defaults
- [x] T10 — RED: Go/Pytest/JSTS adapter Run+classify tests (incl exec-error)
- [x] T11 — GREEN: implement GoAdapter/PytestAdapter/JSTSAdapter (reuse classifyOutcome)
- [x] T12 — RED: AdapterForLanguage factory tests (JS/TS shared, empty=not ok)
- [x] T13 — GREEN: implement AdapterForLanguage
- [x] T14 — RED: siblingRedCheck tests (empty-blocks, runner-absent, timeout, key-resolution)
- [x] T15 — GREEN: implement siblingRedCheck (WithTimeout 30s, D1 intersection)
- [x] T16 — RED: Go/Python prod-guard red-check tests (AC1/2/3/4/6/7/10)
- [x] T17 — GREEN: replace Go/Python touch-check with siblingRedCheck
- [x] T18 — RED: JS/TS dispatch red-check tests (AC1/2/3/5/6/7/8/10)
- [x] T19 — GREEN: replace JS/TS session-membership with siblingRedCheck
- [x] T20 — RED→GREEN: productionDeps wires runnerForLang
- [x] T21 — REFACTOR: dedupe outcome→BLOCK-message helpers (optional — evaluated; messages kept inline/localized, no indirection warranted)
- [x] T22 — RED→GREEN: docs/memory parity (AC11) + doc-grep test
- [x] T23 — VERIFY: go test ./... green, no real toolchain (AC12)

## Added during implementation (integration surface — e2e fixtures encode the old contract)

- [x] T24 — RED→GREEN: GoAdapter/PytestAdapter honor `[tdd.go]`/`[tdd.python]` `command` (closes the parsed-but-unused config gap; enables hermetic stub-based fixtures)
- [x] T25 — REWRITE: `tests/e2e/python_cycle.sh` to the spec-0018 red-check model (configured stub runner; RED-missing/green→block, failing-just-added→allow, collection-error→block, test-file always allowed) — passes
- [x] T26 — REWRITE: `tests/e2e/javascript_cycle.sh` to the red-check model + JS/TS runner-absent fail-closed (D2) scenario — passes
- [x] T27 — RESOLVED (Option 1, user-chosen): new-symbol introduction needs a one-shot `/speccraft:spec:override`. `run.sh` step 9 rewritten (test-edit → override → prod edit); documented in spec AC13 + amendment, guardrails.md; override-command strings corrected to `/speccraft:spec:override`
