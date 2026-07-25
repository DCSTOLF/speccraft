---
spec: "0032"
status: planned
strategy: tdd
---

# Plan — 0032 payloads (model MultiEdit + NotebookEdit in applyEdit)

## Overview

Spec 0032 teaches the guard's in-memory `applyEdit` model to derive post-edit
content for two tools it currently drops into the `default:` fallback:
`MultiEdit` (sequential `edits[]`, first-occurrence replacement on the RUNNING
content) and `NotebookEdit` (`new_source` is the whole post-edit body). The change
is confined to package `main` under `tools/cmd/speccraft-guard`, plus the version
bump (three `const version` binaries + two JSON manifests).

This spec **extends an EXISTING type** (`ToolInput`) and an **EXISTING function**
(`applyEdit`). It introduces no wholly-new top-level symbol that a test must name
before it exists, so it MUST ship **override-free**. Every driving RED about the
new `Edits []MultiEditEntry` / `NewSource string` fields is authored at the
**envelope boundary** — decode a real JSON byte slice with `json.Unmarshal` and
assert on `applyEdit` / red-candidate BEHAVIOR. An unknown JSON key parses to the
zero value, so such a test COMPILES against today's code and fails only on the
behavior assertion (a runtime RED, not a build failure — the spec-0018-AC13 trap).
Struct-literals naming `Edits`/`NewSource` are used ONLY in GREEN-and-later steps,
after the fields exist.

The `dispatchByLanguage` ToolName injection (main.go:156) is already present, so
AC8 is a **regression PIN**, not a driving RED. The unknown-tool fallback (AC9
`FutureEdit`) is likewise green-on-arrival — both ride along in the AC9 RED step
so the package still reports RED (the recurrence-grep is the decisive failing
assertion there) until the "reserved for spec 0032" language is scrubbed.

## Phases

### Phase 1 — Model MultiEdit + NotebookEdit payloads (drives one GREEN)

#### Step 1 — applyEdit exact oracles (RED)
- Add `tools/cmd/speccraft-guard/apply_multinotebook_test.go`. Each test decodes a
  JSON payload into a `ToolInput` (unknown `edits`/`new_source` keys are dropped
  today), sets `ti.ToolName`, then calls `applyEdit`. No test names `ti.Edits` or
  `ti.NewSource`, so all COMPILE against current code:
  - `Test_ApplyEdit_MultiEdit_SequentialDistinct` — AC1: payload
    `{"edits":[{"old_string":"a","new_string":"b"},{"old_string":"c","new_string":"d"}]}`,
    `applyEdit("a c a", ti)` == exactly `"b d a"`.
  - `Test_ApplyEdit_MultiEdit_RunningContentDependency` — AC2: edits `a→b` then
    `b→c` over pre `"a"` == exactly `"c"` (independent application would give `"b"`).
  - `Test_ApplyEdit_MultiEdit_EmptyEditsReturnsPre` — AC3a: `{"edits":[]}` → preContent.
  - `Test_ApplyEdit_MultiEdit_AbsentOldStringNoOp` — AC3b: an entry with no
    `old_string` is a no-op.
  - `Test_ApplyEdit_MultiEdit_EmptyOldStringSkipped` — AC3c:
    `applyEdit("PRE", edits:[{"":"X"}])` == `"PRE"` (SKIPPED, never prepended).
  - `Test_ApplyEdit_NotebookEdit_NewSourceReplaces` — AC4: `{"new_source":"X"}`,
    `applyEdit("PRE", ti)` == `"X"`.
  - `Test_ApplyEdit_NotebookEdit_EmptyNewSourceEmpty` — AC4: `{"new_source":""}`,
    `applyEdit("PRE", ti)` == `""` (NOT preContent, NOT `Content`/`NewString`).
- Tests fail: `Edits`/`NewSource` fields do not exist, so the decoded `ti` carries
  no payload and `applyEdit` hits `default:` returning `preContent` — mismatching
  every oracle.

#### Step 2 — Invert the 0031 characterization tests (RED)
- In `tools/cmd/speccraft-guard/main_test.go`, invert + rename (via the **Edit**
  tool — see Risk) the two 0031 characterization tests (lines ~1453-1512):
  - `Test_MultiEditEnvelope_CapturesNoRedCandidates` → `Test_MultiEditEnvelope_CapturesRedCandidate`
    — AC5: real `MultiEdit` envelope adding a new test id, assert `len(rc[abs]) > 0`.
  - `Test_NotebookEditEnvelope_CapturesNoRedCandidates` → `Test_NotebookEditEnvelope_CapturesRedCandidate`
    — AC6: real `NotebookEdit` envelope adding a new test id, assert `len(rc[abs]) > 0`.
  These already drive real JSON through `map[string]any` → `json.Marshal` →
  `json.Unmarshal` into `HookInput` → `processToolUse` — the envelope-boundary
  pattern. Rewrite each assertion (`!= 0` → `== 0` failure) and its error string.
- Tests fail: the payloads are still unmodeled, so zero candidates are captured.
- Note: leave the stale `default:`-branch comment in main.go ("reserved for spec
  0032") in place — it is the surviving phrase that keeps the AC9 grep RED (Phase 3).

#### Step 3 — End-to-end override-free flow (RED)
- Add `tools/cmd/speccraft-guard/multiedit_e2e_test.go`:
  - `Test_MultiEditSiblingRed_NoOverride_Allows_Go` — AC7: using `redCheckRepo` /
    `processToolUse`, author a sibling test file via a real `MultiEdit` envelope
    whose new test body asserts against an ALREADY-EXISTING production symbol
    (a runtime RED, not a compile failure), then edit the production file and
    assert the edit is ALLOWED with NO override.
- Test fails: without MultiEdit modeling the sibling RED captures no candidate, so
  the production red-check observes no failing just-added test and blocks the edit.

#### Step 4 — Implement MultiEdit + NotebookEdit modeling (GREEN)
- In `tools/cmd/speccraft-guard/main.go`:
  - Add `type MultiEditEntry struct { OldString string `json:"old_string"`;
    NewString string `json:"new_string"` }`.
  - Add fields to `ToolInput`: `Edits []MultiEditEntry `json:"edits"`` and
    `NewSource string `json:"new_source"``.
  - Add helper `func applyMultiEdit(pre string, edits []MultiEditEntry) string`:
    fold over `edits` applying `strings.Replace(running, e.OldString, e.NewString, 1)`
    on the RUNNING content; SKIP any entry whose `OldString == ""`.
  - In `applyEdit`, add `case "MultiEdit": return applyMultiEdit(preContent, ti.Edits)`
    and `case "NotebookEdit": return ti.NewSource`. Keep `default:` unchanged as the
    pre-edit fallback (its comment is scrubbed in Phase 3, not here).
- Steps 1-3 pass; `go test ./...` green.

### Phase 2 — (folded into Phase 3) regression pins

AC8 and the AC9 unknown-tool fallback are green-on-arrival, so they are added in
the Phase 3 RED step (which is red on the recurrence-grep) rather than as their own
GREEN — this keeps the RED→GREEN discipline intact without a passing-only "GREEN".

### Phase 3 — Recurrence guard + fallback/dispatch pins (AC8, AC9)

#### Step 5 — Reserved-slot guard + fallback + dispatch pins (RED)
- Add `tools/cmd/speccraft-guard/reserved_slot_test.go`:
  - `Test_NoReservedSlotLanguage_ForWriteTools` — AC9: read every `*.go` in the
    package dir EXCEPT `reserved_slot_test.go` (self-exclusion), normalize
    (lower-case + collapse runs of whitespace to a single space), and assert none
    contains the needles `"reserved spec 0032"`, `"reserved for spec 0032"`,
    `"unmodeled"`. Build the needles from concatenated fragments
    (e.g. `"reserved for " + "spec 0032"`, `"un" + "modeled"`) so this test's own
    source carries no literal phrase. RED today: main.go's `default:` comment still
    reads "Modeling them is reserved for spec 0032."
  - `Test_FutureEditEnvelope_ReturnsPreContentUnchanged` — AC9 fallback (PIN,
    green-on-arrival): a `FutureEdit` envelope → `applyEdit` returns `preContent`
    unchanged via `default:`.
  - `Test_DispatchByLanguage_InjectsToolName_MultiEdit` and
    `Test_DispatchByLanguage_InjectsToolName_NotebookEdit` — AC8 (PINs,
    green-on-arrival): send each envelope through `processToolUse` to a TEST file
    (with `ToolInput.ToolName` unset by the `json:"-"` boundary) and assert the
    candidate is captured — which only happens if main.go:156 injects
    `input.ToolInput.ToolName = input.ToolName`, routing `applyEdit` to the right
    case instead of `default:`. Remove line 156 and these go red.
- Step is RED overall: the recurrence-grep fails while the two pins pass.

#### Step 6 — Scrub reserved-slot language (GREEN)
- In `tools/cmd/speccraft-guard/main.go`, rewrite the `default:`-branch comment to
  describe the genuine unknown-tool fallback (payload not modeled → return pre-edit
  content), deleting the now-false "reserved for spec 0032" / "unmodeled" language.
  Scrub any residual phrase left in `main_test.go` from the Phase-1 inversion.
- `Test_NoReservedSlotLanguage_ForWriteTools` passes; all pins stay green.

### Phase 4 — Version bump 1.8.0 → 1.9.0 (AC10)

Per conventions §Version bumps, each `const version` is forced through a sibling
version-test edit FIRST (RED), then the const edit (GREEN). Do this per binary.

#### Step 7 — Guard version test to 1.9.0 (RED)
- Edit `tools/cmd/speccraft-guard/version_test.go`: rename
  `Test_GuardCmd_Version_Const180` → `_Const190`, assert `version == "1.9.0"`.
- Fails: `const version` is still `"1.8.0"`.

#### Step 8 — Guard const 1.9.0 (GREEN)
- Edit `tools/cmd/speccraft-guard/main.go:17` → `const version = "1.9.0"`.

#### Step 9 — State version test to 1.9.0 (RED)
- Edit `tools/cmd/speccraft-state/version_test.go`: rename
  `Test_StateCmd_Version_Is180` → `_Is190`, assert `--version` == `"1.9.0"`. Fails.

#### Step 10 — State const 1.9.0 (GREEN)
- Edit `tools/cmd/speccraft-state/main.go:13` → `const version = "1.9.0"`.

#### Step 11 — Drift version test to 1.9.0 (RED)
- Edit `tools/cmd/speccraft-drift/version_test.go`: rename
  `Test_DriftCmd_Version_Const180` → `_Const190`, assert `version == "1.9.0"`. Fails.

#### Step 12 — Drift const 1.9.0 (GREEN)
- Edit `tools/cmd/speccraft-drift/main.go:12` → `const version = "1.9.0"`.

#### Step 13 — Manifest grep test to 1.9.0 (RED)
- Edit `tools/internal/speccraft/manifest_version_test.go`: rename
  `Test_Manifests_VersionIs180` → `_Is190`, positive needle `"version": "1.9.0"`,
  stale-negative `"1.8.0"`, over `.claude-plugin/plugin.json` +
  `.claude-plugin/marketplace.json`. Fails: manifests still `"1.8.0"`.

#### Step 14 — Bump manifests (GREEN)
- Edit `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`:
  `"version": "1.8.0"` → `"version": "1.9.0"`. Grep oracle passes.
- Merge-time obligation (AC10 "Done"): merge auto-tags → `release.yml` →
  `verify-release.sh` publishes and self-verifies `v1.9.0` tarballs + checksums.

## Risk

- **Override-free / envelope-boundary (mandatory).** This spec extends an EXISTING
  type and function and introduces NO new top-level symbol a test must name before
  it exists, so it MUST ship with ZERO guard overrides. Every driving RED about
  `Edits`/`NewSource` (Steps 1-3) is authored by decoding real JSON via
  `json.Unmarshal([]byte(envelope), &ti/&in)` and asserting on `applyEdit` /
  red-candidate behavior — NEVER via a Go struct-literal naming `Edits`/`NewSource`
  before they exist (that fails to COMPILE = a build failure, not a runtime RED,
  and would need an override). Struct-literals appear only from Step 4 onward, once
  the fields exist. **If any override appears necessary, the author has mis-sequenced
  — re-author the RED at the envelope boundary instead of granting an override.**

- **Guard-dogfooding stale cache (operational).** The `speccraft-guard` first on
  PATH this in-repo session may be a STALE cached build with the pre-0031 Write
  blind spot (reads `new_string`, but a fresh Write sends `content`). When
  registering a decisive failing test in-session, ADD/modify it via the **Edit**
  tool (which the old guard models correctly) rather than a fresh **Write** — this
  applies to Step 2 (inverting in-place, naturally Edit) and to the new files in
  Steps 1/3/5 (seed a minimal stub, then Edit in the decisive body), or run
  `./bin/`-built fresh guard binaries so the in-session gate is not blind.

- **AC9 grep self-match.** `reserved_slot_test.go` must not match its own needles:
  build needles from concatenated fragments AND exclude its own filename from the
  scanned set. Normalize case + whitespace so the guard is whitespace-tolerant.

- **AC9 phrase-ordering.** Model the payloads (Steps 1-4) and invert the capture
  tests (Step 2) BEFORE scrubbing the "reserved" language (Step 6); leave main.go's
  `default:` comment as the surviving phrase so the recurrence-grep has a genuine
  RED in Step 5 that Step 6 turns green.

- **AC8/fallback are pins, not drivers.** The ToolName injection (main.go:156) and
  the `default:` fallback already exist, so those tests pass on arrival; they ride
  in the Step-5 RED (kept red by the grep) to preserve RED→GREEN framing without a
  passing-only GREEN.

## Test strategy

- `go test ./...` after every step; each step is independently verifiable.
- Driving REDs (Steps 1-3) exercise `applyEdit` and the full `processToolUse`
  capture path through real JSON envelopes; exact-oracle assertions (AC1-4) pin the
  running-content semantics and the empty-`old_string`/empty-`new_source` edges.
- AC5-7 exercise the integration path (envelope → capture → red-check → allow).
- AC8/AC9 pins guard against regression of the injection line and the fallback.
- Version bump uses const-assertion tests (three binaries) + a grep-oracle over the
  two JSON manifests (positive 1.9.0, negative 1.8.0).
