---
id: "0018"
title: "technical-review"
status: planned
strategy: tdd
---

# Plan — 0018 technical-review (red→green parity for Go/Python/JS-TS)

Closes P0-1: Go/Python/JS-TS only check that a sibling test file was *touched
this session* (`main.go:390`, `:446-452`). This plan replaces the touch-check
with a REAL red-check that runs the session's just-added/modified sibling
test(s) and requires an OBSERVED FAILURE before unlocking production edits,
reaching parity with Rust.

## Planner-settled open questions

- **OQ-A — JS/TS runner detection → config-only.** `[tdd.javascript]` and
  `[tdd.typescript]` each carry a `command` key; JS and TS share ONE adapter
  and ONE resolution path (the config key only selects the argv). No default
  command, NO inference from `package.json` `scripts.test` / vitest-jest
  presence. Justification: under D2 an unresolved JS/TS runner fails closed
  regardless, so inference buys nothing but parser complexity and a
  cross-toolchain probe; config-only is the simplest defensible default and
  keeps the hand-rolled TOML parser honest. An unresolved command ⇒ empty ⇒
  fail-closed (AC8).
- **AC9 — default timeout `d` = 30s.** Bounds the real adapter invocation via
  `context.WithTimeout(ctx, 30*time.Second)`. A deadline overrun surfaces as a
  Go `error` from `adapter.Run` (NOT a new Outcome enum value), and the guard
  BLOCKs on any such error. 30s comfortably covers a single targeted Go/pytest/
  node test while bounding a hang; not exposed as config in this spec.

## The D1 model (resolved concretely)

Go/Python/JS-TS have no persisted baseline like `rust_test_baseline`. We adopt
the recommended capture-at-test-edit model:

1. When a sibling TEST file is edited during the session (the `IsTestFile`
   dispatch branch, currently a bare `return nil`), the guard reads the
   pre-edit on-disk content, models the post-edit content via the existing
   `applyEdit`, extracts test-function identifiers from each, and computes the
   set INTRODUCED by this edit (post − pre). It persists that set, keyed by the
   absolute test-file path, into a NEW single-writer Session field
   `RedCandidates map[string][]string` (JSON `red_candidates`).
2. At the PRODUCTION-file edit, the "just-added set" = the union of
   `RedCandidates[siblingFile]` over the resolved sibling test file(s). The
   guard runs the resolved adapter once per sibling test file (targeted at the
   file/its members), collects records, and accepts iff a `failed` record's
   test id is IN the just-added set.
3. **D1 divergence (deliberate):** empty just-added set ⇒ BLOCK "add a failing
   test first" — the runner is NOT invoked. We MUST NOT copy Rust's
   allow-on-empty branch (`main.go:203-206`), because Go/Python/JS-TS have no
   baseline attesting a prior RED.

Why this still closes P0-1 and honors D1: a blank-line-only edit introduces no
new test identifier, so `RedCandidates[file]` is empty ⇒ BLOCK (AC10). A green
sibling (all pass) yields no `failed` record in the set ⇒ BLOCK (AC1). A
pre-existing unrelated failure has an id OUTSIDE the just-added set ⇒ BLOCK
(AC7). Only a just-added test that actually fails unlocks (AC3).

## Seam shapes (chosen)

- **Adapter factory:** add `runner.AdapterForLanguage(lang string, cfg
  speccraft.SpeccraftConfig) (Runner, bool)` returning `(adapter, ok)`; `ok ==
  false` is the runner-absent signal (D2/AC8). `AdapterFor(cfg)` (Rust) stays
  untouched. New `GoAdapter`, `PytestAdapter`, `JSTSAdapter` structs mirror
  `CargoAdapter` (struct{exec execFn; …}; build argv; `execOrDefault()`; parse;
  REUSE `classifyOutcome`). No language-specific code leaks into
  speccraft-guard.
- **deps seam:** the guard resolves its red-check adapter through a NEW
  `d.runnerForLang func(lang string, cfg) (runner.Runner, bool)`. `productionDeps()`
  wires it to `runner.AdapterForLanguage`. Existing `d.runnerFor` (Rust) stays.
- **Single shared red-check helper** `siblingRedCheck(absPath, root, cfg, lang,
  d)` used by BOTH `goPythonProdGuard` and `jsTsDispatch` after
  `prodGuardPrologue` (tri-state, KEPT). `jsTsDispatch` gains `cfg` + `d`
  params.

## Test-first sequence

### Step 1 — Per-language test-id extractors (RED)
- CREATE `tools/internal/speccraft/lang_testids_test.go`:
  - `Test_GoTestIDs_ExtractsFuncTestNames` — `func TestFoo(t *testing.T)` →
    `["TestFoo"]`; ignores `func helper()`, commented-out tests.
  - `Test_PythonTestIDs_ExtractsDefTestNames` — `def test_bar(self):` →
    `["test_bar"]`; ignores `def helper`, indented non-test defs handled.
  - `Test_JSTSTestIDs_ExtractsTestItDescribe` — `test('x',`, `it("y",`,
    `describe('z',` → `["x","y","z"]`; ignores strings in comments.
- Tests fail: `GoTestIDs` / `PythonTestIDs` / `JSTSTestIDs` undefined.

### Step 2 — Implement extractors (GREEN)
- Implement `tools/internal/speccraft/lang_testids.go` with `GoTestIDs(src
  string) []string`, `PythonTestIDs(src string) []string`, `JSTSTestIDs(src
  string) []string` (regex-based, sibling to `rust_canonical.go`; Go
  `func\s+(Test\w+)`, Python `def\s+(test\w+)`, JS/TS
  `(?:test|it|describe)\s*\(\s*['"` + "`" + `]([^'"` + "`" + `]+)`). Source order preserved.
- All step-1 tests pass.

### Step 3 — `RedCandidates` Session field + accessors (RED)
- EXTEND `tools/internal/speccraft/state_test.go`:
  - `Test_SetRedCandidates_PersistsPerFile` — write `{file: [ids]}`, reload,
    read back.
  - `Test_GetRedCandidates_EmptyWhenUnset` — returns empty map, no error.
  - `Test_ResetSession_ClearsRedCandidates` — set then `ResetSession`, empty.
- Tests fail: `RedCandidates` field + `SetRedCandidates`/`GetRedCandidates`
  undefined.

### Step 4 — Implement `RedCandidates` storage (GREEN)
- EXTEND `tools/internal/speccraft/state.go`: add `RedCandidates
  map[string][]string` with JSON tag `red_candidates,omitempty` to `Session`;
  add `GetRedCandidates(root)`, `SetRedCandidates(root, file string, ids
  []string)` (single-writer, `mu.Lock`, dedup, overwrite per file).
  `ResetSession` already zeroes `Session` — covered.
- All step-3 tests pass.

### Step 5 — Single-writer allow-list regression (RED→GREEN, guardrail)
- EXTEND `tools/internal/speccraft/state_single_writer_test.go`: add pattern
  `\.RedCandidates\s*=[^=]` to `patterns`. Run: it FAILS only if a non-allowed
  file assigns `RedCandidates` (it won't, since Step 4 puts the writer in
  `state.go`, already allow-listed). This step is the AC-aligned no-regression
  assertion — RED would appear only if a future GREEN step leaks a writer.
- Test passes with Step-4 wiring intact.

### Step 6 — Capture red-candidates on sibling test-file edit (RED)
- EXTEND `tools/cmd/speccraft-guard/main_test.go`:
  - `Test_TestFileEdit_CapturesRedCandidates_Go` — `processToolUse` with an
    `Edit` to `foo_test.go` adding `func TestNew(...)` → after the call,
    `GetRedCandidates(root)[abs(foo_test.go)]` contains `"TestNew"`; still
    returns nil (allowed).
  - `Test_TestFileEdit_BlankLineEdit_CapturesEmptyForGo` — blank-line-only edit
    → captured set for that file is empty.
  - `Test_TestFileEdit_CapturesRedCandidates_Python` / `_JSTS` — parity.
- Tests fail: the `IsTestFile` dispatch branch is a bare `return nil`; no
  capture happens.

### Step 7 — Implement test-edit capture (GREEN)
- EXTEND `tools/cmd/speccraft-guard/main.go`: in `dispatchByLanguage`, the
  `IsTestFile` branch calls a new `captureRedCandidates(input, absPath, root)`:
  read pre-edit disk content, `applyEdit` → post, select extractor by file kind
  (Go/Python/JS-TS), compute post−pre, `SetRedCandidates(root, absPath, added)`,
  then `return nil`. Note: capture goes through speccraft-state's writer
  (state.go) — guard calls the helper, single-writer preserved.
- All step-6 tests pass.

### Step 8 — Config: Go/Python/JS-TS sections + defaults + validation (RED)
- EXTEND `tools/internal/speccraft/config_test.go`:
  - `Test_ParseConfig_GoPythonJSTSCommands` — `[tdd.go] command="go test"`,
    `[tdd.python] command="pytest"`, `[tdd.javascript] command="vitest run"`,
    `[tdd.typescript] command="vitest run"` parse into the new structs.
  - `Test_ApplyDefaults_GoPythonCommands` — Go defaults `go test`, Python
    defaults `pytest`, JS/TS default empty (no default).
  - `Test_ReadConfigStrict_RejectsEmptyJSCommandIsNotError` — empty JS/TS
    command is VALID at parse (fail-closed happens at runtime, AC8), so strict
    read returns no error.
- Tests fail: `TDDConfig.Go/Python/JavaScript/TypeScript` fields undefined.

### Step 9 — Implement config sections (GREEN)
- EXTEND `tools/internal/speccraft/config.go`: add `Go GoConfig`, `Python
  PythonConfig`, `JavaScript JSConfig`, `TypeScript TSConfig` (each
  `{Command string}`) to `TDDConfig`; extend `parseSpeccraftTOML` `section`
  switch with `[tdd.go]`/`[tdd.python]`/`[tdd.javascript]`/`[tdd.typescript]`
  reading `command`; extend `applyDefaults` (Go→`go test`, Python→`pytest`,
  JS/TS→`""`). No new strict-validation enum (commands are free-form).
- All step-8 tests pass.

### Step 10 — Adapters: Go/Pytest/JSTS Run + classify (RED)
- CREATE `tools/internal/speccraft/runner/go_adapter_test.go`,
  `pytest_adapter_test.go`, `jsts_adapter_test.go` (mirror
  `cargo_adapter_test.go`, fake `exec`):
  - `Test_GoAdapter_AllPassed` / `_AtLeastOneFailed` / `_BuildFailed` — fake
    `go test -json`-style stdout → records → `classifyOutcome`.
  - `Test_PytestAdapter_AllPassed` / `_AtLeastOneFailed` / `_CollectionFailed`
    (collection error ⇒ `OutcomeBuildFailed`, AC6).
  - `Test_JSTSAdapter_AllPassed` / `_AtLeastOneFailed` / `_BuildFailed`;
    `Test_JSTSAdapter_CommandFromConfig` — argv uses configured command.
  - `Test_*Adapter_ExecError_PropagatesError` — exec returns error (timeout/
    hang surrogate) ⇒ `Run` returns a Go error, no Outcome (AC9).
- Tests fail: `GoAdapter` / `PytestAdapter` / `JSTSAdapter` undefined.

### Step 11 — Implement adapters (GREEN)
- CREATE `runner/go_adapter.go`, `pytest_adapter.go`, `jsts_adapter.go`: each a
  struct `{exec execFn; …}`, `Run(ctx, req)` builds argv (Go: `go test
  -run '^<name>$' -json ./...`; pytest: `pytest -k <name> --no-header`; JS/TS:
  configured command + targeted filter), `execOrDefault()`, parse → `[]TestRecord`,
  REUSE `classifyOutcome(recs, exitCode)`. Exec error propagates verbatim.
- All step-10 tests pass.

### Step 12 — `AdapterForLanguage` factory (RED)
- EXTEND `tools/internal/speccraft/runner/runner_test.go`:
  - `Test_AdapterForLanguage_Go` / `_Python` return the right adapter, `ok=true`.
  - `Test_AdapterForLanguage_JSShared` / `_TSShared` — both return a
    `*JSTSAdapter`, command from `[tdd.javascript]` resp. `[tdd.typescript]`.
  - `Test_AdapterForLanguage_JSTS_EmptyCommand_NotOK` — empty configured
    command ⇒ `ok=false` (D2/AC8).
  - `Test_AdapterForLanguage_UnknownLang_NotOK`.
- Tests fail: `AdapterForLanguage` undefined.

### Step 13 — Implement factory (GREEN)
- EXTEND `runner/runner.go`: `AdapterForLanguage(lang string, cfg) (Runner,
  bool)` switch on `lang` (`"go"`/`"python"`/`"js"`/`"ts"`); JS and TS both
  build `*JSTSAdapter` selecting command from the matching config key; empty
  command or unknown lang ⇒ `(nil, false)`.
- All step-12 tests pass.

### Step 14 — Shared `siblingRedCheck` helper, timeout-bounded (RED)
- EXTEND `tools/cmd/speccraft-guard/main_test.go` (fake `runnerForLang`):
  - `Test_SiblingRedCheck_EmptyJustAdded_Blocks_NoRunnerInvoked` — no captured
    candidates for resolved siblings ⇒ BLOCK "add a failing test first", fake
    runner's `Run` NEVER called (AC2).
  - `Test_SiblingRedCheck_RunnerAbsent_FailsClosed` — `runnerForLang` returns
    `ok=false` ⇒ BLOCK "no test runner available — configure one or use
    /spec:override" (AC8/D2).
  - `Test_SiblingRedCheck_TimeoutError_Blocks` — fake runner returns a Go error
    ⇒ BLOCK, never allow; assert the call used a deadline context (fake records
    `ctx.Deadline() ok==true`) (AC9).
  - `Test_SiblingRedCheck_ResolvesCapturedKey` — capture and lookup both key on
    `filepath.Abs` (risk-mitigation).
- Tests fail: `siblingRedCheck` undefined.

### Step 15 — Implement `siblingRedCheck` (GREEN)
- EXTEND `tools/cmd/speccraft-guard/main.go`: add `siblingRedCheck(absPath,
  root, cfg, lang, d)`:
  1. Resolve siblings via `SiblingTestFiles`.
  2. `justAdded` = union of `GetRedCandidates(root)[sibling]`. Empty ⇒ BLOCK
     "add a failing test first" (D1 divergence), runner NOT invoked.
  3. `adapter, ok := d.runnerForLang(lang, cfg)`; `!ok` ⇒ BLOCK runner-absent.
  4. `ctx, cancel := context.WithTimeout(context.Background(), redCheckTimeout)`
     where `const redCheckTimeout = 30 * time.Second`.
  5. Run adapter per sibling; on `err != nil` ⇒ BLOCK (timeout/error);
     `OutcomeBuildFailed` ⇒ BLOCK build/collection-failure message (AC6);
     accept iff a `failed` record's id ∈ `justAdded`; else BLOCK "no failing
     test observed".
- All step-14 tests pass.

### Step 16 — Wire Go/Python guard to red-check (RED)
- EXTEND `tools/cmd/speccraft-guard/main_test.go` (fakes):
  - `Test_GoProdGuard_GreenSibling_Blocks` — captured TestNew, fake runner
    `OutcomeAllPassed` ⇒ BLOCK "no failing test observed" (AC1).
  - `Test_GoProdGuard_NoTargetedTest_Blocks` — no candidates ⇒ BLOCK, runner
    not invoked (AC2).
  - `Test_GoProdGuard_FailingJustAdded_Allows` — failed record id ∈ justAdded
    ⇒ ALLOW (AC3).
  - `Test_GoProdGuard_UnrelatedFailure_Blocks` — failed record id ∉ justAdded
    ⇒ BLOCK (AC7).
  - `Test_GoProdGuard_BuildFailed_Blocks` — `OutcomeBuildFailed` ⇒ BLOCK
    build-failure message (AC6).
  - `Test_GoProdGuard_BlankLineBypassClosed` — blank-line sibling edit then
    prod edit, runner `OutcomeAllPassed` ⇒ BLOCK (AC10, Go path `:390`).
  - `Test_PythonProdGuard_*` — AC1/AC2/AC3 + AC6 + AC10 parity (AC4).
- Tests fail: `goPythonProdGuard` still calls `hasSiblingTestEdited` touch-check.

### Step 17 — Replace Go/Python touch-check with red-check (GREEN)
- EXTEND `tools/cmd/speccraft-guard/main.go`: in `goPythonProdGuard`, after
  `prodGuardPrologue`, REPLACE the `hasSiblingTestEdited` block with
  `return siblingRedCheck(absPath, root, cfg, langFor(absPath), d)`
  (`langFor` ⇒ `"go"`|`"python"`). `goPythonProdGuard` gains `d deps`; update
  `dispatchByLanguage` call site. Remove now-dead `hasSiblingTestEdited` (and
  its test `TestHasSiblingTestEdited`) only after green.
- All step-16 tests pass.

### Step 18 — Wire JS/TS dispatch to red-check (RED)
- EXTEND `tools/cmd/speccraft-guard/main_test.go`:
  - `Test_JSTSDispatch_GreenSibling_Blocks` (AC1/AC5).
  - `Test_JSTSDispatch_NoTargetedTest_Blocks` (AC2/AC5).
  - `Test_JSTSDispatch_FailingJustAdded_Allows` (AC3/AC5).
  - `Test_JSTSDispatch_UnrelatedFailure_Blocks` (AC7).
  - `Test_JSTSDispatch_BuildFailed_Blocks` (AC6).
  - `Test_JSTSDispatch_RunnerAbsent_FailsClosed` — empty `[tdd.javascript]`
    command ⇒ BLOCK "no test runner available" (AC8/D2).
  - `Test_JSTSDispatch_BlankLineBypassClosed` — AC10, JS/TS path `:446-452`.
- Tests fail: `jsTsDispatch` still runs the session-membership candidate loop
  and takes only `(absPath, root)`.

### Step 19 — Replace JS/TS session-membership with red-check (GREEN)
- EXTEND `tools/cmd/speccraft-guard/main.go`: change `jsTsDispatch(absPath,
  root)` → `jsTsDispatch(absPath, root, cfg, d)`; after `prodGuardPrologue`,
  REPLACE the candidate-loop with `return siblingRedCheck(absPath, root, cfg,
  "ts" or "js" by extension, d)`. Update `dispatchByLanguage` call site. JS and
  TS resolve through the one `JSTSAdapter`; the lang token only selects the
  config command key.
- All step-18 tests pass.

### Step 20 — `productionDeps` wires `runnerForLang` (RED→GREEN)
- EXTEND `tools/cmd/speccraft-guard/main_test.go`:
  `Test_ProductionDeps_HasRunnerForLang` — `productionDeps().runnerForLang !=
  nil` and resolves `"go"` to a real adapter.
- EXTEND `main.go`: add `runnerForLang` to `deps`; `productionDeps()` sets it
  to `runner.AdapterForLanguage`.
- Test passes.

### Step 21 — Refactor: dedupe outcome→message mapping (optional)
- Extract the BLOCK-message construction (build-failure vs no-RED vs
  runner-absent vs timeout) out of `siblingRedCheck` into small named helpers;
  ensure Rust `rustDispatch` and the new path share wording where identical.
- All tests still pass.

### Step 22 — Docs/memory parity (AC11) (RED→GREEN, doc-verifying test)
- EXTEND `tools/cmd/speccraft-guard/main_test.go` OR add
  `tools/internal/speccraft/docs_parity_test.go`:
  - `Test_Docs_NoSurvivingTouchOnlyWording` — grep
    `speccraft-technical-review.md` §4 matrix, `.speccraft/index.md`,
    `.speccraft/architecture.md` (lines 14 + 42) for the stale
    "non-goal"/"touch-check for Go/Python/JS-TS" phrasings; FAIL if present.
  - Asserts `.speccraft/guardrails.md` invariant text is generic (no-regression,
    not an edit unless stale).
- Tests fail until docs updated.
- GREEN: update `speccraft-technical-review.md` §4 matrix (P0-1 row → resolved,
  parity), `.speccraft/index.md` invariant description,
  `.speccraft/architecture.md:14` (drop "retroactive adoption by Go/Python is a
  non-goal") and `:42` (drop "Runner adoption by Go/Python is a non-goal") to
  state red→green parity for all four languages. Verify `guardrails.md` is
  already generic (no edit).
- Test passes.

### Step 23 — Full-suite verification + AC12 seam check (REFACTOR/verify)
- Run `go test ./...` from `tools/`. Confirm no test shells out to a real
  go/pytest/node toolchain (all adapter + guard tests use fake `exec` /
  `runnerForLang`). Confirm the red-check tests are satisfied by construction
  using fakes (AC12).

## Acceptance-criterion → task map

| AC | Tasks |
|----|-------|
| AC1 Go green sibling blocks | T16 (`_GreenSibling_Blocks`), helper T14/T15 |
| AC2 Go no targeted test blocks (runner not invoked) | T14 (`_EmptyJustAdded`), T16 (`_NoTargetedTest`) |
| AC3 Go failing just-added allows | T16 (`_FailingJustAdded_Allows`) |
| AC4 Python parity (AC1/2/3) | T16 (`_PythonProdGuard_*`), T10/T11/T13 (pytest adapter) |
| AC5 JS/TS parity, one adapter/path | T18/T19, T12/T13 (`_JSShared`/`_TSShared`) |
| AC6 build/collection failure ≠ RED | T10 (`_BuildFailed`/`_CollectionFailed`), T15, T16, T18 |
| AC7 pre-existing unrelated failure blocks (D1) | T16 (`_UnrelatedFailure`), T18 |
| AC8 runner-absent fail-closed (D2) | T12 (`_EmptyCommand_NotOK`), T14 (`_RunnerAbsent`), T18 |
| AC9 timeout bounded, error blocks | T10 (`_ExecError`), T14 (`_TimeoutError_Blocks`), T15 (`WithTimeout`) |
| AC10 blank-line bypass closed per language | T6 (`_BlankLineEdit`), T16/T18 (`_BlankLineBypassClosed` Go/Python/JS-TS) |
| AC11 docs/memory parity | T22 |
| AC12 testability seam, no real toolchain | T14–T20 (fakes), T23 |
| D1 model (capture + intersection) | T1/T2 (extractors), T3/T4 (RedCandidates), T6/T7 (capture), T15 (intersection) |
| Config sections (OQ-A) | T8/T9 |

## EXTEND vs CREATE

- **CREATE:** `tools/internal/speccraft/lang_testids.go` (+`_test.go`);
  `runner/go_adapter.go`, `runner/pytest_adapter.go`, `runner/jsts_adapter.go`
  (+ each `_test.go`).
- **EXTEND:** `tools/internal/speccraft/state.go` + `state_test.go`;
  `state_single_writer_test.go` (allow-list pattern); `config.go` +
  `config_test.go`; `runner/runner.go` + `runner_test.go`;
  `tools/cmd/speccraft-guard/main.go` + `main_test.go` (largest, all dispatch
  ACs). Docs: `speccraft-technical-review.md`, `.speccraft/index.md`,
  `.speccraft/architecture.md`.
- **REMOVE after green:** `hasSiblingTestEdited` + `TestHasSiblingTestEdited`
  (T17); JS/TS candidate-loop body (T19).

## Delegation

- Adapter argv/parse work (T10/T11) → delegate to a Go-implementer agent
  (reason: mechanical mirror of `CargoAdapter`, parser-heavy, well-bounded).
- Docs parity (T22) → delegate to docs/memory-keeper agent (reason: prose +
  grep-assertion, no production-code coupling).
- Guard dispatch ACs (T14–T20) → keep on the core agent (reason: touches the
  shared red-check seam and single-writer invariant; highest blast radius).

## Risk

- **Test-id extractor false negatives** (e.g. table-driven Go subtests, pytest
  parametrize, JS template-literal test names) → could make `justAdded` empty
  and over-block. Mitigation: extractor keys on the OUTER `func Test…`/`def
  test_…`/`test(`/`it(` declaration only (sufficient for the targeted-run
  filter); document the granularity; over-block is fail-closed (safe), never
  fail-open.
- **`SiblingTestFiles` path resolution mismatch vs capture key** (abs vs rel,
  `__tests__/` patterns) → just-added lookup misses. Mitigation: capture and
  lookup both key on `filepath.Abs`; add an explicit
  `Test_SiblingRedCheck_ResolvesCapturedKey` in T14.
- **`go test -run <name>` matching too broadly** (`-run TestFoo` also matches
  `TestFooBar`) → an unrelated failure could be mistaken for just-added.
  Mitigation: intersection is by exact id from `RedCandidates`, and `-run` is
  anchored (`-run '^TestFoo$'`); assert in T10.
- **Single-writer regression** if any new writer of `RedCandidates` lands
  outside `state.go` → P0-class guardrail break. Mitigation: T5 extends the
  grep allow-list pattern before any writer exists.
- **Doc-grep brittleness** (T22 fails on benign rephrasings) → Mitigation:
  match on the specific stale phrases ("non-goal", "touch") scoped to the named
  files/sections, not broad terms.
