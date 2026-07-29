---
id: "0010"
status: planned
---

# Plan — 0010 JavaScript and TypeScript support

This plan follows strict RED→GREEN→REFACTOR cycles. Every GREEN step is
preceded by a RED step whose failing tests pin the contract. Steps are
ordered so the spec's gate-symmetry mandate is honored: the shared guard
prologue is extracted (with its own RED/GREEN/REFACTOR pair) **before**
`jsTsDispatch` is added.

Coverage map (acceptance criteria → steps):

- AC #1 (16 suffix variants)                → Steps 1, 2
- AC #2 (`__tests__/` segment)               → Steps 3, 4
- AC #3 (production extensions)              → Steps 7, 8
- AC #4 (node_modules/dist exclusion)        → Steps 5, 6
- AC #5 (`IsTestFile` delegation)            → Steps 9, 10
- AC #6 (guard blocks production write)      → Steps 13, 14, 15, 16
- AC #7 (guard allows after session edit)    → Steps 15, 16
- AC #8 (e2e RED scenario)                   → Step 17
- AC #9 (e2e GREEN scenario)                 → Step 17
- AC #10 (--language-only wires the fixture) → Step 18
- AC #11 (non-test files not misclassified)  → Steps 1, 2, 5, 6, 11, 12

---

## Step 1 — RED: classifier suffix patterns
File: `tools/internal/speccraft/files_test.go`
Test: `TestIsJSTSTestFile_SuffixPatterns`
What to write: table-driven test asserting `IsJSTSTestFile` returns true
for all 16 suffix variants (`.test.{js,ts,jsx,tsx,mjs,cjs,mts,cts}` and
`.spec.{js,ts,jsx,tsx,mjs,cjs,mts,cts}`) and false for benign neighbors
in the same table (`src/foo.ts`, `src/foo.specs.ts`, `src/types.d.ts`).
Fails because: `speccraft.IsJSTSTestFile` does not exist yet — the
package will not compile.

## Step 2 — GREEN: implement `IsJSTSTestFile` suffix matching
File: `tools/internal/speccraft/files.go`
What to implement: add `IsJSTSTestFile(path string) bool` that splits
the basename on `.`, checks for a `.test.<ext>` or `.spec.<ext>` suffix
where `<ext>` is in `{js,ts,jsx,tsx,mjs,cjs,mts,cts}`, and returns true
on match. For the .d.ts/.d.mts/.d.cts and `.specs.ts` cases in Step 1's
table, return false (these are addressed by the early-out: only exact
`.test.` / `.spec.` infixes count; declaration files match neither).
Passes: Step 1.

## Step 3 — RED: `__tests__/` directory convention
File: `tools/internal/speccraft/files_test.go`
Test: `TestIsJSTSTestFile_TestsDirectorySegment`
What to write: table cases asserting true for `src/__tests__/foo.test.ts`,
`__tests__/bar.js`, `lib/__tests__/baz.mts`, `pkg/__tests__/sub/q.tsx`;
and false for `__tests__.ts` (bare filename — segment must be a
directory) and `src/my__tests__dir/foo.ts` (not an exact segment).
Fails because: current `IsJSTSTestFile` only checks suffix patterns;
`__tests__` segment logic is absent.

## Step 4 — GREEN: add `__tests__/` segment recognition
File: `tools/internal/speccraft/files.go`
What to implement: extend `IsJSTSTestFile` to also return true when the
slash-separated components of `filepath.ToSlash(filepath.Clean(path))`
contain `__tests__` as an exact segment AND the basename has one of
the 8 JS/TS production extensions. Filename `__tests__.ts` does NOT
satisfy (basename, not segment).
Passes: Step 3 and keeps Step 1 green.

## Step 5 — RED: node_modules / dist exclusion
File: `tools/internal/speccraft/files_test.go`
Test: `TestIsJSTSTestFile_NodeModulesDistExcluded`
What to write: table cases asserting `IsJSTSTestFile` returns false for
`node_modules/jest/build/index.js`, `node_modules/pkg/__tests__/foo.test.ts`,
`dist/bundle.test.js`, and `pkg/dist/foo.test.ts`. Also asserts true
(NOT excluded) for `src/distribution/foo.test.ts` and
`src/distutils/__tests__/foo.ts` (non-exact segment matches).
Fails because: exclusion logic not yet present — these paths currently
match either the suffix or `__tests__/` arm.

## Step 6 — GREEN: implement segment-exact exclusion
File: `tools/internal/speccraft/files.go`
What to implement: introduce an unexported `isExcludedJSTSPath(path)`
helper that runs `filepath.Clean` + `filepath.ToSlash`, splits on `/`,
and returns true if any segment equals `node_modules` or `dist`. Call
it from `IsJSTSTestFile` as a short-circuit before suffix and segment
checks.
Passes: Step 5 and keeps Steps 1, 3 green.

## Step 7 — RED: `IsProductionJSTSFile` accept set
File: `tools/internal/speccraft/files_test.go`
Test: `TestIsProductionJSTSFile_AcceptsProductionExtensions`
What to write: table cases asserting true for `src/index.ts`,
`src/utils.mjs`, `lib/helpers.cts`, `app/main.jsx`, `src/foo.cjs`,
`src/foo.mts`, `src/foo.js`, `src/foo.tsx`. Asserts false for
`src/foo.test.ts`, `src/__tests__/foo.ts`, `node_modules/x/index.js`,
`dist/bundle.js`, `src/types.d.ts`, `src/types.d.mts`, `src/types.d.cts`,
and `src/README.md`.
Fails because: `speccraft.IsProductionJSTSFile` does not exist.

## Step 8 — GREEN: implement `IsProductionJSTSFile`
File: `tools/internal/speccraft/files.go`
What to implement: add `IsProductionJSTSFile(path string) bool` that
returns false on `isExcludedJSTSPath`, false on `IsJSTSTestFile`,
false on `.d.ts` / `.d.mts` / `.d.cts` basenames, and true when the
basename ends in one of the 8 production extensions.
Passes: Step 7.

## Step 9 — RED: `IsTestFile` delegation
File: `tools/internal/speccraft/files_test.go`
Test: `TestIsTestFile_DelegatesToJSTS`
What to write: assert `IsTestFile("src/foo.test.ts") == true`,
`IsTestFile("src/foo.spec.js") == true`,
`IsTestFile("src/__tests__/bar.tsx") == true`, and the existing
Go/Python positive cases still return true. Negative cases include
`src/foo.ts` (production, not test) and `src/types.d.ts` (declaration).
Fails because: current `IsTestFile` only checks Go/Python suffixes.

## Step 10 — GREEN: wire `IsJSTSTestFile` into `IsTestFile`
File: `tools/internal/speccraft/files.go`
What to implement: extend the existing `IsTestFile` to also return
`IsJSTSTestFile(path)`. No other branches changed; existing Go and
Python tests stay green.
Passes: Step 9 and `TestIsTestFile` (pre-existing).

## Step 11 — RED: declaration-file and basename edge cases
File: `tools/internal/speccraft/files_test.go`
Test: `TestIsJSTSTestFile_NonTestEdgeCases`
What to write: table-driven test pinning AC #11 — `src/foo.specs.ts`,
`src/types.d.ts`, `src/types.d.mts`, `src/types.d.cts`, and
`__tests__.ts` (filename, not segment) all return false from
`IsJSTSTestFile`. Plus `src/types.d.ts`/`.d.mts`/`.d.cts` return false
from `IsProductionJSTSFile`.
Fails-as-pass: if Steps 2, 6, 8 were implemented carefully these may
already pass — this step exists to nail the edge cases down explicitly.
Where it does fail, the corresponding refactor in Step 12 fixes it.

## Step 12 — GREEN/REFACTOR: tighten edge-case logic
File: `tools/internal/speccraft/files.go`
What to implement: only if Step 11 reveals a regression, tighten the
matching predicates (e.g. add an explicit `.d.<ext>` short-circuit at
the top of `IsJSTSTestFile`). Behavior preserved on all earlier tests.
Passes: Step 11 plus Steps 1, 3, 5, 7, 9.

## Step 13 — RED: extract shared guard prologue
File: `tools/cmd/speccraft-guard/main_test.go`
Test: `TestProdGuardPrologue_ReturnsActiveSpecError` and
`TestProdGuardPrologue_ReturnsStatusError` and
`TestProdGuardPrologue_ConsumesOverrideReturnsAllow` and
`TestProdGuardPrologue_PassThroughReturnsContinue`
What to write: four table-style tests that call a not-yet-existing
helper `prodGuardPrologue(absPath, root) (decision, error)` returning
a tri-state (`allow`, `block`, `continue`). They assert: (a) empty
`active_spec` produces an error containing `"No active spec"`,
(b) non-`in-progress` status produces an error containing `"in status"`,
(c) `override_pending=true` returns `allow` and consumes the flag, and
(d) all gates clear returns `continue`.
Fails because: `prodGuardPrologue` does not yet exist; the package
will not compile.

## Step 14 — GREEN: introduce `prodGuardPrologue` and rewire goPythonProdGuard
File: `tools/cmd/speccraft-guard/main.go`
What to implement: factor lines 332–355 of `goPythonProdGuard`
(active-spec check, status check, `ConsumeOverride` short-circuit)
into a `prodGuardPrologue(absPath, root string) (prologueDecision, error)`
helper returning the tri-state described in Step 13. Update
`goPythonProdGuard` to call the helper. No behavior change for
Go/Python callers — all pre-existing main_test.go tests
(`TestGoPythonProdGuard_OverridePending_*`) remain green.
Passes: Step 13 and all pre-existing prologue-related tests.

## Step 15 — RED: jsTsDispatch sibling-test session lookup
File: `tools/cmd/speccraft-guard/main_test.go`
Tests:
  - `TestJsTsDispatch_RejectsWhenNoSiblingTestRegistered`
  - `TestJsTsDispatch_AcceptsWhenSiblingSuffixTestRegistered`
  - `TestJsTsDispatch_AcceptsWhenSiblingTestsDirRegistered`
  - `TestJsTsDispatch_OnDiskTestNotInSessionDoesNotSatisfy`
  - `TestJsTsDispatch_ReusesPrologueGates`
What to write:
  - Reject test scaffolds an in-progress spec, calls `processToolUse`
    against `src/foo.ts` with empty `session.edited_test_files`, and
    asserts a non-nil error whose message names `src/foo.ts`.
  - Accept-suffix test pre-populates session state with
    `src/foo.test.ts` (via `speccraft.TrackEditTest`/state helper),
    then asserts `processToolUse` returns nil for `src/foo.ts`.
  - Accept-`__tests__` test pre-populates session state with
    `src/__tests__/foo.test.ts` and asserts nil for `src/foo.ts`.
  - On-disk test creates `src/foo.test.ts` on the filesystem WITHOUT
    registering it in session state and asserts the rejection still
    fires (session-only semantics).
  - Reuse-prologue test sets `active_spec=""`, asserts the same
    "No active spec" error fires for a JS/TS path (proving the shared
    prologue from Step 14 is wired into the new dispatch).
Fails because: `dispatchByLanguage` does not yet route JS/TS paths;
the default arm returns nil, so every rejection assertion fails.

## Step 16 — GREEN: implement `jsTsDispatch` and dispatcher arm
File: `tools/cmd/speccraft-guard/main.go`
What to implement:
  1. Add `jsTsDispatch(absPath, root string, cfg speccraft.SpeccraftConfig) error`
     that (a) calls `prodGuardPrologue` and respects its decision,
     then (b) builds the candidate set: same-dir
     `<dir>/<stem>.{test,spec}.<ext>` and
     `<dir>/__tests__/<stem>.{test,spec}.<ext>` and bare
     `<dir>/__tests__/<stem>.<ext>` across the 8 JS/TS extensions,
     all in `filepath.Clean` form, (c) iterates
     `state.Session.EditedTestFiles` (also Clean-normalized) and
     returns nil on the first hit, (d) otherwise returns a
     `fmt.Errorf` whose message contains `"no sibling test registered for "`
     followed by the relative path of the production file.
  2. Add a new case to `dispatchByLanguage` ordered AFTER the existing
     `IsTestFile` check (so JS/TS test files are still always allowed
     via the delegation added in Step 10) and AFTER the Go/Python
     production arm:
     ```go
     case speccraft.IsProductionJSTSFile(absPath):
         return jsTsDispatch(absPath, root, cfg)
     ```
Passes: Step 15 plus all earlier guard tests.

## Step 17 — RED + GREEN: e2e fixture `javascript_cycle.sh`
File: `tests/e2e/javascript_cycle.sh` (new)
What to write: a hermetic shell-only fixture modeled on
`tests/e2e/python_cycle.sh`:
  - Build `speccraft-guard` + `speccraft-state` into `$WORK`.
  - Scaffold a temp project with `src/`, `.speccraft/`,
    `specs/0010-javascript-typescript-support/spec.md` (status:
    in-progress), and `state.json`.
  - `reset_state()` between scenarios, `hook_input(path)` helper.
  - Scenario A (RED, AC #6/#8): `reset_state`; emit hook JSON for
    `src/foo.ts`; assert non-zero exit and stderr substring
    `"no sibling test registered for"`. Also exercise a TypeScript-
    specific path (e.g. `src/handler.ts`) and a `*.test.ts`-on-disk
    case to prove session-only semantics.
  - Scenario B (GREEN, AC #7/#9): `reset_state`;
    `speccraft-state track-edit src/foo.test.ts`; emit hook JSON for
    `src/foo.ts`; assert exit 0.
  - Scenario C (GREEN, `__tests__/` variant): `reset_state`;
    `speccraft-state track-edit src/__tests__/handler.test.ts`; emit
    hook JSON for `src/handler.ts`; assert exit 0.
  - Optional scenario D: test-file write always allowed.
Marked executable. Drives no JS runtime — pure shell + hook JSON.
First commit of this file is RED in the sense that without Step 16's
GREEN code it would not actually pass; with Steps 1–16 already merged
this step closes both RED and GREEN halves of AC #8 and #9 in one file
add (the fixture itself is the test; the production code is already
landed).

## Step 18 — GREEN: wire fixture into `run_language_fixtures`
File: `tests/e2e/run.sh`
What to implement: append after the existing python_cycle invocation:
```bash
( bash "$E2E_DIR/javascript_cycle.sh" ) || fail "javascript_cycle.sh failed"
pass "javascript_cycle.sh"
```
This satisfies AC #10. The `--language-only` short-circuit already
invokes `run_language_fixtures` so no further wiring is needed in
CI; the existing `e2e-language-only` job (spec 0008) exercises the
new fixture by virtue of it being registered.
Passes: AC #10 plus AC #8 and AC #9 by transitive invocation.

## Step 19 — REFACTOR (optional): tidy `IsTestFile` and shared lookups
File: `tools/internal/speccraft/files.go`
What to change: if `IsTestFile`, `IsJSTSTestFile`, and the production
classifiers accumulate duplicated extension lists or basename slicing,
extract a small unexported `jsTsExts()` (or const slice) and reuse it.
Behavior unchanged; all tests stay green. Skip if the code in Step 6
and Step 8 is already cohesive.

---

## Risk register

- **Filename vs path semantics.** `__tests__` must match as a path
  segment, not a basename substring. Mitigation: pin via Step 3
  (`__tests__.ts` returns false) and Step 5 (`distribution` does NOT
  match `dist`).
- **Prologue extraction regresses existing override tests.** Spec 0009
  added `TestGoPythonProdGuard_OverridePending_*` cases that pin the
  consume-on-use semantics. Mitigation: Step 14 keeps
  `goPythonProdGuard` semantically identical; the test list in
  `main_test.go` is run as part of every step from Step 14 onward.
- **Session vs disk drift in e2e.** Spec 6/AC #6 specifically forbids
  on-disk test files satisfying the invariant. Mitigation: explicit
  test in Step 15 (`OnDiskTestNotInSessionDoesNotSatisfy`) and a
  matching scenario in Step 17.
- **`filepath.Clean` normalization across platforms.** The plan
  presumes POSIX path semantics — the e2e fixture and unit tests run
  on Linux CI only. Mitigation: use `filepath.ToSlash` everywhere a
  segment check happens; do not hand-roll string splitting on `\`.
