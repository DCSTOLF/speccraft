---
spec: "0031"
status: planned
strategy: tdd
---

# Plan — 0031 TDD guard Write-tool red-candidate blind spot

Shape: a single production-Go change in `tools/cmd/speccraft-guard/main.go`
(add `ToolInput.Content`; replace the `old_string == ""` shape heuristic in
`applyEdit` with a `ToolName`-driven switch; thread the tool name through both
call sites — `captureRedCandidates` and the Rust-only `computeJustAddedForEdit`)
plus fixture corrections in the sibling `main_test.go`, a MultiEdit/NotebookEdit
characterization pin, and a version bump `1.7.0 → 1.7.1` across the same five
surfaces spec 0030 bumped. Sequenced so **both driving REDs come first at the
JSON-envelope boundary** (they compile against current code and fail on
behavior), then the one production GREEN turns them green and locks the AC1/AC2
unit contract, then fixtures/guard, then MultiEdit/NotebookEdit disposition,
then the version bump.

## No `/speccraft:spec:override` is required anywhere — the JSON-boundary RED is the enabler

This spec fixes the exact bootstrap trap that would otherwise force an override
here, so the plan must not fall into it. `tools/cmd/speccraft-guard` is
production Go gated by `speccraft-guard` itself: the Step-3 edit to `main.go`
(new `Content` field, new `applyEdit` signature) needs an **observed failing
sibling RED** to be allowed. If that RED referenced the not-yet-existing
`Content` field or the new `applyEdit(pre, toolName, ti)` signature, the
`package main` test file would **not compile** → the runner reports
`OutcomeBuildFailed` → **not a valid RED** → the edit is blocked and an override
would be needed (the precise thing this spec removes).

The escape is to author the driving REDs (Steps 1 and 2) **at the JSON-envelope
boundary using raw envelope strings**, never a direct `Content:` / new-signature
reference:

- Each RED builds a real `{"tool_name":"Write","tool_input":{"file_path":"…","content":"…"}}`
  string, `json.Unmarshal`s it into `HookInput`, and calls `processToolUse`.
- Against current code the `content` key is silently dropped (no struct field),
  so `applyEdit`'s `old_string == ""` branch returns `NewString == ""` → post-edit
  content empty → **zero** red-candidates captured → the assertion fails.
- Crucially it **compiles** (no `Content` token, no new signature) and fails on
  **behavior** → a valid, observed RED that needs no override.

The Step-3 GREEN (`Content` field + `ToolName` switch) makes both REDs pass. The
finer-grained AC1 unit cases (which *do* reference the new `applyEdit` signature)
and the AC2 Edit-regression pin are added **in the same Step-3 edit, after the
signature exists**, as characterization pins locked to the new contract — they
land in `main_test.go`, which is a test file and is never TDD-gated, so no
override is implicated there either.

Contrast with spec 0030: 0030 also needed no override, but only because its new
symbols lived in a **fresh** `pluginroot.go` whose sibling test could compile
against a stub-free package. Here the change mutates an **existing** gated
package's exported-in-package surface, so the compile-stable RED must live at the
JSON boundary — that is the specific, load-bearing move of this plan.

## RED preconditions confirmed at plan time (on `main`)

- `tools/cmd/speccraft-guard/main.go`: `ToolInput` (l.27–31) has `FilePath`,
  `OldString`, `NewString` — **no** `Content` field. `HookInput` (l.20–25)
  already decodes `ToolName string json:"tool_name"`.
- `applyEdit(preContent string, ti ToolInput) string` (l.374–382) is the buggy
  shape heuristic: `if ti.OldString == "" { return ti.NewString }` else
  `strings.Replace(pre, old, new, 1)`. Called by `captureRedCandidates` (l.345)
  and `computeJustAddedForEdit` (l.292, Rust path via `rustDispatch` l.219).
- `main_test.go` `captureCase` (l.781–803) builds
  `ToolInput{FilePath, NewString: newContent}` with **no** `ToolName`/`Content`
  (comment: "OldString empty ⇒ Write semantics") — the mis-simulated fixture.
- `const version = "1.7.0"` in all three `tools/cmd/*/main.go`; `"version":
  "1.7.0"` in `.claude-plugin/{plugin,marketplace}.json`. Sibling version tests
  assert `"1.7.0"` (`Test_StateCmd_Version_Reports170`, `…_Guard…Const170`,
  `…_Drift…Const170`).
- Spec 0031 frontmatter already carries `reserves-specs: ["0032"]`.

## Test-first sequence

### Phase 1 — Driving REDs at the JSON-envelope boundary (compile-stable, no override)

#### Step 1 — Write-envelope capture RED (RED) — AC3
- Add to `tools/cmd/speccraft-guard/main_test.go` (package `main`), each building
  a raw Write envelope **string**, `json.Unmarshal` → `HookInput`, then
  `processToolUse(input, deps{})` and asserting `speccraft.GetRedCandidates(root)`
  for the file's abspath contains the just-added id. Reuse `makeTestRepo(t,
  "0031-…", "in-progress")`; seed disk pre-content for the overwrite cases only.
  - `Test_WriteEnvelope_CapturesRedCandidates_Go_Create` — no file on disk;
    envelope `content` adds `func TestNew(t *testing.T){}` → expect captured set
    to include `TestNew`.
  - `Test_WriteEnvelope_CapturesRedCandidates_Go_Overwrite` — a pre-existing
    `foo_test.go` on disk with `TestExisting`; `content` replaces it with
    `TestExisting`+`TestNew` → expect `TestNew` captured, `TestExisting` not.
  - `Test_WriteEnvelope_CapturesRedCandidates_Python_Create` — `content` adds
    `def test_new():` → expect `test_new`.
  - `Test_WriteEnvelope_CapturesRedCandidates_Python_Overwrite` — pre-existing
    `test_foo.py` overwritten to add `test_new` → expect `test_new`, not the old id.
  - `Test_WriteEnvelope_CapturesRedCandidates_JSTS_Create` — `foo.test.ts`,
    `content` adds `test('brandnew', () => {})` → expect `brandnew`. Documented as
    the single representative of the **shared** JS/TS extractor (per AC3).
- Tests fail: the `content` key has no `ToolInput` field, so post-edit content is
  empty and **zero** candidates are captured — the assertions fail. All compile
  (raw JSON string; no `Content` token).

#### Step 2 — Two-ordered-call end-to-end RED (RED) — AC4
- Add to `main_test.go`, modeled on
  `TestPreToolUse_RustSecondInvocation_AfterCapture_RunnerIsConsulted` but for the
  Go/Python red-check path. Seed with `redCheckRepo`-style layout: prod file
  (`pkg/foo.go`) and sibling test file (`pkg/foo_test.go`) **both physically on
  disk** (the on-disk glob in `resolveSiblingTests`/`SiblingTestFiles` must find
  the sibling; PreToolUse runs before the apply, so materialize the post-Write
  test file on disk to represent the file the approved Write creates).
  `override_pending` is never set at any point.
  - `Test_WriteThenEditProd_NoOverride_Allows_Go`:
    - Call 1 — raw `Write` envelope **string** for `pkg/foo_test.go` whose
      `content` adds `func TestNew(t *testing.T){}`; `processToolUse(input,
      deps{})` returns nil; assert `GetRedCandidates` for that path includes
      `TestNew`.
    - Call 2 — `Edit` envelope for `pkg/foo.go` with a
      `deps{runnerForLang: fixedRunnerForLang(rec, true)}` where `rec` is a
      `recordingRunner` whose `nextResult` is
      `runner.Result{Outcome: runner.OutcomeAtLeastOneFailed, Records:
      []runner.TestRecord{{TestName:"TestNew", Status:"failed"}}}`.
    - Assert: Call 2 returns **nil** (edit allowed); `rec.calls` has **exactly
      one** entry whose `FullyQualifiedTestName == "TestNew"` (proves the
      runner-backed authorization ran, not an override/other allow branch); and
      `override_pending` was never provisioned.
  - `Test_WriteThenEditProd_NoOverride_Allows_Python` — same shape with
    `pkg/test_foo.py` sibling → `test_new`, `pkg/foo.py` prod.
- Tests fail: Call 1 captures nothing (content dropped) → Call 2's
  `siblingRedCheck` sees an empty just-added set → blocks with "add a failing
  test" → Call 2 returns non-nil. Compiles (raw JSON Write envelope; `Edit`
  envelope and `recordingRunner` are existing types).

### Phase 2 — Production GREEN + AC1/AC2 unit pins

#### Step 3 — ToolName-driven `applyEdit` + thread the tool name (GREEN) — AC1, AC2, AC3, AC4, AC5(fixtures)
- Edit `tools/cmd/speccraft-guard/main.go`:
  - Add `Content string \`json:"content"\`` to `ToolInput`.
  - Change the signature to `applyEdit(preContent, toolName string, ti ToolInput)
    string` and replace the body with a `switch toolName`:
    - `"Write"` → `return ti.Content` (including the empty string; `NewString` is
      ignored);
    - `"Edit"` → `return strings.Replace(preContent, ti.OldString, ti.NewString,
      1)` (**preserved even when `OldString == ""`** — an Edit is never
      reclassified as a Write);
    - `default:` → `return preContent` (no modeled change) with a code comment
      naming MultiEdit/NotebookEdit as the conservative-default tenants pinned by
      AC7 / reserved spec 0032.
  - Thread the tool name into both call sites:
    `captureRedCandidates(input.ToolInput, input.ToolName, absPath, root)` (update
    its signature + `applyEdit(pre, toolName, ti)` call) at the `IsTestFile` branch
    (l.153); and `computeJustAddedForEdit(absPath, input.ToolName, input.ToolInput,
    root)` from `rustDispatch` (l.219), updating that function to call
    `applyEdit(preContent, toolName, ti)` and refreshing its stale doc comment
    (l.280–281) to say "`Content` for a Write".
  - **Fix the fixture in the same edit (mechanically required):** rewrite
    `captureCase` (`main_test.go` l.781–803) to build
    `HookInput{ToolName: "Write", ToolInput: ToolInput{FilePath, Content:
    newContent}, CWD: root}`. Without this the switch's `default` branch would fire
    for `captureCase`'s empty `ToolName` and break the pre-existing
    `Test_TestFileEdit_CapturesRedCandidates_{Go,Python,JSTS}` — those tests now
    become AC5's behavioral proof that fixtures exercise the real Write payload.
- Result: Step-1 and Step-2 REDs pass; the whole existing suite stays green.
- In the **same** edit (now that the new signature exists), add the AC1/AC2
  characterization pins to `main_test.go` — a test file, never TDD-gated:
  - `Test_ApplyEdit_Write_NonEmptyContent_ReturnsContent` (a) — non-empty
    `Content` returned regardless of `preContent`.
  - `Test_ApplyEdit_Write_PopulatedNewString_Ignored` (a) — `Write` with both
    `Content` and a populated `NewString` returns `Content`, proving the branch is
    keyed on `ToolName`, not field population.
  - `Test_ApplyEdit_Write_EmptyContent_ReturnsEmpty` (b) — `Write` + empty
    `Content` → `""`.
  - `Test_ApplyEdit_Edit_NonEmptyOldString_Replaces` (c) — equals
    `strings.Replace(pre, old, new, 1)`.
  - `Test_ApplyEdit_Edit_EmptyOldString_StillReplaces` (d) — empty `OldString` is
    **not** treated as a Write; still performs the replacement.
  - `Test_ApplyEdit_Edit_RegressionUnchanged` (AC2) — table over the current Edit
    payloads asserting the Edit branch is byte-for-byte unchanged from today.
  - `Test_ApplyEdit_UnknownTool_ReturnsPreContent` — the `default` branch returns
    `preContent` (the AC7 unit-level anchor).

#### Step 4 — Refactor: AC5 static regression guard (pin) — AC5(guard)
- Add `Test_NoWriteHelperSetsNewStringWithoutContent` to `main_test.go`: reads the
  guard package's `*_test.go` source via `os.ReadFile` and asserts no test helper
  constructs a `ToolName: "Write"` payload that sets `NewString` without also
  setting `Content`. Passes immediately (Step 3 corrected `captureCase`); it is a
  forward regression guard, not a driving RED (introduces no production code), so
  it needs no preceding RED. All tests still pass.

### Phase 3 — MultiEdit/NotebookEdit disposition (characterization) — AC7

#### Step 5 — Pin current MultiEdit/NotebookEdit behavior (characterization pin) — AC7
- Add to `main_test.go`, each building a native envelope string and asserting
  `GetRedCandidates(root)` captures **nothing**:
  - `Test_MultiEditEnvelope_CapturesNoRedCandidates` — `{"tool_name":"MultiEdit",
    "tool_input":{"file_path":"…_test.go","edits":[…]}}` (the `edits[]` payload is
    unmodeled by `ToolInput`) → zero candidates.
  - `Test_NotebookEditEnvelope_CapturesNoRedCandidates` — a `NotebookEdit`
    envelope → zero candidates.
- These pin the **current** fail-closed behavior (observable contract, not
  bug-entrenchment): today because `edits[]` isn't decoded and `OldString==""`
  yields empty content; after Step 3 because the `default` branch returns
  `preContent` → empty just-added set. The `applyEdit` `default`-branch comment
  (Step 3) plus the already-present `reserves-specs: ["0032"]` frontmatter name
  the deliberate follow-up. No production fix here — the disposition is the
  deliverable. (No new dir for 0032 — the frontmatter reservation is the
  mechanism per §"Optional: `reserves-specs`".)

### Phase 4 — Version bump 1.7.0 → 1.7.1 — AC6

#### Step 6 — Version-assertion tests + manifest oracle to 1.7.1 (RED) — AC6
- Edit `tools/cmd/speccraft-state/version_test.go`: rename
  `Test_StateCmd_Version_Reports170 → …Reports171`, assert `"1.7.1"`.
- Edit `tools/cmd/speccraft-guard/version_test.go` and
  `tools/cmd/speccraft-drift/version_test.go`: rename `…Const170 → …Const171`,
  assert `version == "1.7.1"`.
- Add `specs/0031-guard-write-tool-red-candidate-blindspot/verify.sh` (modeled on
  `specs/0030-…/verify.sh`: `set -euo pipefail`, repo-root from `${BASH_SOURCE[0]:-$0}`,
  a `present`/`absent` helper pair, exit-non-zero-names-each-failure). It pins the
  two JSON manifests: `.claude-plugin/plugin.json` and
  `.claude-plugin/marketplace.json` each `present` `"version": "1.7.1"` and
  `absent` the stale `"1.7.0"`.
- Tests fail on `main`: the three consts and both manifests are still `1.7.0`. The
  version tests compile (`version` const exists; assert wrong value → runtime
  fail), so editing each `main.go` const in Step 7 has its observed sibling RED —
  no override for the const edits either.

#### Step 7 — Bump all five version surfaces to 1.7.1 (GREEN) — AC6
- Set `const version = "1.7.1"` in `tools/cmd/{speccraft-state,speccraft-guard,
  speccraft-drift}/main.go`.
- Set `"version": "1.7.1"` in `.claude-plugin/plugin.json` and
  `.claude-plugin/marketplace.json`.
- Step-6 Go tests pass; `verify.sh` passes.
- **"Done" is the published, self-verified `v1.7.1` release, not the edited
  consts** (per `.speccraft/conventions.md` §Version bumps / §"A version bump must
  mechanically produce a published, verified release"): the bump landing on `main`
  triggers `auto-tag` (pushes `v1.7.1` via `RELEASE_TAG_PAT`) → `release.yml`
  (builds+publishes the four platform tarballs + `checksums.txt`) →
  `scripts/verify-release.sh` self-verify. Do not hand-build tarballs or push the
  tag manually.

### Step 8 — Final VERIFY (all green together)
- `go test ./...` in `tools/` green: Step-1 Write-capture (create+overwrite,
  Go/Python/JS-TS), Step-2 two-call E2E (Go+Python), AC1/AC2 unit pins, AC5 static
  guard, AC7 MultiEdit/NotebookEdit pins, and the three 1.7.1 version tests.
- `bash specs/0031-…/verify.sh` fully green (both manifests at 1.7.1, no stale
  1.7.0).
- Confirm `reserves-specs: ["0032"]` present in `spec.md` frontmatter and the
  `applyEdit` `default`-branch comment names the reservation.

## Delegation

- Steps 1–5 (Go REDs + the single `main.go` GREEN + unit pins + fixtures + AC7
  pins) → keep in the implementing thread. Pure in-package Go, tightest RED→GREEN
  loop, and the loop is self-gating through `speccraft-guard` on its own package —
  the JSON-boundary REDs are precisely what keep it override-free, so they must be
  authored and observed in the same thread that makes the edit.
- Steps 6–7 (version bump + `verify.sh`) → keep in-thread; mechanically identical
  to spec 0030's version-bump phase, and the release itself is produced by the
  automated `auto-tag → release.yml → verify-release.sh` pipeline, not by hand.

## Risk

- **Referencing `Content`/the new `applyEdit` signature in the driving RED →
  `OutcomeBuildFailed` → not a valid RED → forces an override** (the exact trap
  this spec fixes) → mitigation: Steps 1 and 2 build **raw JSON envelope strings**
  and `json.Unmarshal` them; they compile against current code and fail on
  behavior. The signature-referencing AC1/AC2 pins are added only in Step 3 *after*
  the GREEN, in the never-gated test file.
- **Changing `applyEdit`'s switch without fixing `captureCase` in the same edit →
  the existing `Test_TestFileEdit_*` break** (empty `ToolName` hits the `default`
  branch → no capture) → mitigation: the `captureCase` correction is folded into
  Step 3; `go test ./...` stays green at the step boundary, and those tests become
  AC5's behavioral proof.
- **AC4's on-disk sibling resolution finds nothing** (`SiblingTestFiles` globs
  disk; PreToolUse runs before the write is applied) → mitigation: seed both the
  prod file and the sibling test file physically on disk (mirror `redCheckRepo`),
  representing the file the approved Write creates; the two calls then exercise the
  real capture→consume ordering.
- **MultiEdit/NotebookEdit `default`-branch is a conservative fail-closed
  blind spot, not a fix** → mitigation: AC7 pins it as an observable current
  contract and reserved spec 0032 (already in frontmatter) tracks the payload
  modeling; out of scope here by design.
- **Treating the const/manifest edit as "done" and skipping the published
  release** → mitigation: Step 7 states the close gate is the published,
  self-verified `v1.7.1` release via the existing automated pipeline triggered by
  the bump landing on `main`.

## AC → step coverage

| AC | Step(s) |
| --- | --- |
| AC1 (`applyEdit` selects by tool name; unit cases a–d incl. NewString-ignored) | 3 |
| AC2 (Edit path behaviorally unchanged) | 3 |
| AC3 (full Write envelope captures ids; create+overwrite; Go/Python + 1 JS/TS) | 1 (RED), 3 (GREEN) |
| AC4 (two-ordered-call E2E; runner invoked once with captured id; nil; no override) | 2 (RED), 3 (GREEN) |
| AC5 (fixtures use `ToolName:"Write"`+`content`; static no-`NewString`-without-`Content` guard) | 3 (fixtures), 4 (guard) |
| AC6 (bump 1.7.0→1.7.1; sibling version tests; manifest oracle; published release) | 6 (RED), 7 (GREEN) |
| AC7 (MultiEdit/NotebookEdit pinned to current no-capture behavior; reserve 0032) | 5 |
