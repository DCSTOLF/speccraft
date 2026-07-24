---
spec: "0031"
closed: 2026-07-24
---

# Changelog — 0031 TDD guard Write-tool red-candidate blind spot

## What shipped vs spec

All seven acceptance criteria shipped.

- **The bug (root cause).** `speccraft-guard`'s red-candidate capture modeled the
  post-edit content of a write-tool call by *payload shape*: `applyEdit` treated an
  empty `old_string` as "Write tool → `new_string` is the whole post-edit file." But
  the **Write** tool does not send `new_string` — it sends `content`, and the guard's
  `ToolInput` had no `content` field. So a test file *created or overwritten* with the
  Write tool yielded an empty post-edit content, extracted **zero** test IDs, and
  recorded **zero** red-candidates — after which the sibling production edit was blocked
  with "no failing test observed" even though a real RED test existed on disk. This cost
  **three `/speccraft:spec:override`** in spec 0030. It stayed invisible because the
  fixture (`captureCase`) mis-simulated Write via `NewString`, encoding the same wrong
  assumption as the bug — the suite was green while the real path was broken.

- **The fix (AC1, AC2).** Added `Content string \`json:"content"\`` to `ToolInput` plus
  a `ToolName string \`json:"-"\`` field injected from `HookInput.ToolName` in
  `dispatchByLanguage` (`input.ToolInput.ToolName = input.ToolName`). `applyEdit` now
  switches on `ti.ToolName` instead of payload shape: `Write` → `Content` (including the
  empty string; `new_string` ignored); `Edit` → `strings.Replace(pre, old, new, 1)`
  **preserved even when `old_string` is empty** (an Edit is never reclassified as a
  Write); `default` (MultiEdit/NotebookEdit/any other) → pre-edit content unchanged (no
  modeled change → empty just-added set). Because `applyEdit` is reached via both
  `captureRedCandidates` and `computeJustAddedForEdit`, the tool name is carried on
  `ToolInput` once at dispatch rather than threaded as a new parameter. `captureCase` was
  corrected to the real Write shape (`ToolName: "Write"` + `Content`), so the pre-existing
  `Test_TestFileEdit_CapturesRedCandidates_{Go,Python,JSTS}` now exercise the true payload
  and serve as AC5's behavioral proof.

- **Verification (AC3–AC7).** 7 JSON-envelope-boundary capture tests (Write create +
  overwrite for Go and Python, one JS/TS create as the shared-extractor representative);
  two two-ordered-call E2E tests (`Test_WriteThenEditProd_NoOverride_Allows_{Go,Python}`)
  with a fake runner asserting the runner is invoked exactly once with the captured ID,
  returns `OutcomeAtLeastOneFailed` for that ID, and the prod edit returns nil, with no
  override provisioned; AC1(a–d) + AC2 `applyEdit` unit pins including the
  `NewString`-ignored-on-Write and empty-`old_string`-still-replaces cases; AC5 static
  guard `Test_NoWriteHelperSetsNewStringWithoutContent`; AC7 MultiEdit/NotebookEdit
  characterization pins (native envelope → zero red-candidates). `go test ./...` green,
  bats 0-fail, `specs/0031-.../verify.sh` green. Version bumped `1.7.0 → 1.7.1` (guard
  behavior fix; patch) across the three `const version` + two `.claude-plugin/*.json`,
  with the three sibling version tests renamed to `…171`/`…Const171`.

## Deviations

- **`applyEdit` signature was NOT changed.** The plan proposed a new
  `applyEdit(preContent, toolName string, ti ToolInput)` signature threaded through both
  call sites. The shipped fix instead carries the tool name on `ToolInput.ToolName`
  (`json:"-"`, injected once in `dispatchByLanguage`), keeping `applyEdit(preContent,
  ti)` unchanged. Behaviorally identical to the spec; a strictly smaller edit that touches
  neither call site's signature. The AC1 unit pins call `applyEdit("PRE",
  ToolInput{ToolName: "Write", ...})` accordingly.
- **The `default` branch folds empty `ToolName` into `Edit`, not into the unmodeled
  default.** `applyEdit`'s switch is `case "Write"` / `case "Edit", ""` / `default`. The
  empty-`ToolName` case is treated as an Edit (single search-and-replace) so older
  in-package test fixtures that omit `ToolName` keep working; production Edit envelopes
  always carry `tool_name`. AC7's MultiEdit/NotebookEdit pins land in the `default` branch
  as specified (their real envelopes carry a non-empty, non-Edit `tool_name`).

- **ZERO `/speccraft:spec:override` — the deliberate payoff.** The driving REDs were
  authored at the **JSON-envelope boundary**: each `json.Unmarshal`s a real
  `{"tool_name":"Write",...,"content":...}` envelope and calls `processToolUse`, so it
  **compiles against current code** (no reference to the not-yet-existing `Content` field
  or a new signature) and **fails on behavior** (the `content` key is silently dropped →
  zero candidates captured → assertion fails). This sidestepped the compiled-language
  "build-failed ≠ RED" trap (`OutcomeBuildFailed`) that forced spec 0030's three
  overrides. The signature/field-referencing AC1/AC2 pins were added in the same GREEN
  edit, after the field existed, in the never-TDD-gated test file. The fix for the
  override-forcing bug thus shipped override-free.

## Field notes (red-candidate tracking brittleness)

- **A no-new-test edit clears a just-added RED.** A two-step edit to
  `speccraft-state/version_test.go` had its second (assertion-only) edit **overwrite the
  file's red-candidates with empty** — `SetRedCandidates` replaces the per-file set, and an
  edit that adds no new test name computes an empty just-added set that clears the RED —
  briefly blocking the `const version` bump. Resolved without an override by a single-edit
  rename that re-registered the test as a new id. Test edits that must PRESERVE a RED
  should be single-shot (or re-register via a rename).
- **A comment-only production edit is correctly refused.** One stale doc comment in
  `computeJustAddedForEdit` was left un-updated because the guard rightly refuses a
  comment-only production edit that has no failing test behind it — the guard behaving
  exactly as designed, not a defect.

## Deferred

- **MultiEdit/NotebookEdit payload modeling** is out of scope and reserved as **spec
  0032** (`reserves-specs: ["0032"]` in the spec frontmatter). AC7 pins their current
  no-capture behavior as an observable contract until then; the `applyEdit` `default`-branch
  comment names the reservation.
- **AC6 published-release half** is deferred to merge-time: the `v1.7.1` GitHub Release is
  produced automatically by `auto-tag → release.yml → verify-release.sh` when the bump
  lands on `main` (§Version bumps). The source-level bump + sibling version tests + manifest
  oracle are done.
- **Own close ran NO consolidation** — no `domains:`/`delta:` frontmatter and the repo has
  no `specs/domains/` tree yet (non-blocking decline).

## Files touched

- `tools/cmd/speccraft-guard/main.go` (`ToolInput.Content` + `ToolName`; `ToolName`-driven
  `applyEdit`; dispatch injection; version const)
- `tools/cmd/speccraft-guard/main_test.go` (JSON-boundary REDs, E2E pins, AC1/AC2 unit
  pins, AC5 static guard, AC7 characterization, corrected `captureCase`)
- `tools/cmd/speccraft-guard/version_test.go` (`…Const171`)
- `tools/cmd/speccraft-state/main.go`, `tools/cmd/speccraft-state/version_test.go`
- `tools/cmd/speccraft-drift/main.go`, `tools/cmd/speccraft-drift/version_test.go`
- `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` (1.7.0 → 1.7.1)
- `specs/0031-guard-write-tool-red-candidate-blindspot/verify.sh` (new; manifest oracle)
- `.speccraft/index.md` (active-spec pointer)

## ADR proposed for history.md

2026-07-24 — TDD guard Write-tool red-candidate blind spot fixed; the fix for the
override-forcing bug shipped override-free; version 1.7.1 (spec 0031). See proposed
`history.md` entry.

## Conventions proposed

- **New:** "JSON-envelope-boundary RED for a change to a gated package's own surface."
  When a failing test must justify a change to `speccraft-guard`'s OWN package (or any
  change where referencing the new symbol/signature would make the sibling test fail to
  COMPILE), author the RED at the JSON/decode boundary so it compiles against current code
  and fails on behavior — a build-failed test is not a valid RED (`OutcomeBuildFailed`), so
  a compile-stable behavioral RED is the override-free path. Spec 0031 is the canonical
  instance.
  Rationale: this is precisely the bootstrap trap this spec fixes; the plan's load-bearing
  move was to keep every driving RED at the envelope boundary, which is why the fix for the
  Write-tool blind spot needed zero overrides where spec 0030 spent three.
- **New (optional):** red-candidate tracking gotcha — `SetRedCandidates` replaces per-file;
  a follow-up test-file edit that adds no new test id clears the just-added RED. Make test
  edits that must preserve a RED single-shot, or re-register via a rename.
</content>
</invoke>
