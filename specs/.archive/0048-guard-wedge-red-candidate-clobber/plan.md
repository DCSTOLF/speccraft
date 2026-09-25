---
spec: "0048"
status: planned
strategy: tdd
---

# Plan — 0048 Guard wedge and red-candidate clobber

## Stack resolution (recorded, because detection is wrong here)

`speccraft-state detect-stack` returns `language: "unknown"`, and
`speccraft-state test-command` returns `pytest -q` — which is **wrong for this
repo**: the marker parser matches the *documentation example* on
`.speccraft/conventions.md:333` rather than a real marker. Resolved by
inspection instead:

- Go module `github.com/dcstolf/speccraft/tools` (go 1.22) — test command
  `go test ./...` run from `tools/`; `_test.go` colocated with the code under
  test (`test_patterns: ["*_test.go"]`, `inline_tests: false`).
- `bats` suites under `tests/hooks/` for command-runbook prose and shell.

Every `done:` predicate below runs from the repo root and therefore says
`cd tools && go test …` or `bats tests/hooks/…`.

## Design

### New exported symbols — all in `tools/internal/speccraft/buildrepair.go` (one new file)

| Symbol | Kind | Purpose |
|---|---|---|
| `NormalizeStateKey(path string) string` | func | The single canonical path normalizer (§Path identity, AC15). `filepath.Abs` → `filepath.EvalSymlinks` on the deepest existing ancestor, rejoin the non-existent tail, `filepath.Clean`. Must tolerate a file created in-session (absent from disk). |
| `CaptureRedCandidates(root, file string, preIDs, postIDs []string) ([]string, error)` | func | §B's ONE atomic operation: set `baseline[file] = preIDs` **iff absent**, then `candidates[file] = postIDs − baseline[file]`, under one `mu.Lock()` with one `saveStateLocked`. |
| `GetRedBaseline(root string) (map[string][]string, error)` | func | Read accessor for the per-file baseline (AC13's "not rewritten on a later touch" oracle). |
| `RecordBuildRepair(root, file, errText string) (BuildRepairEntry, error)` | func | Atomic: open the attestation iff absent, enforce the cap, append one entry, one save. Returns `ErrBuildRepairBudgetExhausted` when the log already holds `buildRepairMaxEdits`. |
| `ClearBuildRepairAttestation(root string) error` | func | Clean-probe exit: clears the attestation, **never** the log. |
| `GetBuildRepair(root string) (BuildRepairState, error)` | func | Read accessor (attestation + log) for tests and for `speccraft-state build-repair-log`. |
| `BuildRepairEntry{Seq int; Path, Digest, Summary, At string}` | type | Log entry. `Digest` = `sha256` hex over the **full** pre-truncation error bytes; `Summary` = ≤4 KiB with a visible truncation marker. |
| `BuildRepairAttestation{At, Fingerprint string}` | type | Active repair-mode attestation. `Fingerprint` = `sha256` over the raw pre-edit error bytes. Audit metadata only; gates nothing. |
| `BuildRepairState{Attestation *BuildRepairAttestation; Log []BuildRepairEntry}` | type | Read shape. |
| `ErrBuildRepairBudgetExhausted` | sentinel | Mapped by the guard to the user-facing message naming `/speccraft:spec:override`. |

Unexported, same file: `buildRepairMaxEdits = 10`, `buildRepairSummaryCap = 4 << 10`,
`buildRepairTruncMarker`.

**`buildRepairMaxEdits` stays unexported and lives in `internal/speccraft`,
because the cap must be enforced *inside* the atomic record op — that is the only
placement where "recorded before allowed" is race-free.** AC18's test therefore
needs package-internal access, so `tools/internal/speccraft/buildrepair_policy_test.go`
is declared `package speccraft` (an *internal* test file). Every other
`*_test.go` in that directory is `package speccraft_test`; mixing the two in one
directory is legal Go and is the minimum-surface way to satisfy AC18's
"read the compiled value" requirement without exporting a policy constant.

### New `Session` fields — `tools/internal/speccraft/state.go`

```
RedBaseline            map[string][]string     `json:"red_baseline,omitempty"`
BuildRepair            []BuildRepairEntry      `json:"build_repair,omitempty"`
BuildRepairAttestation *BuildRepairAttestation `json:"build_repair_attestation,omitempty"`
```

`ResetSession` already does `s.Session = Session{}`, so AC13's "clears all four
together" is satisfied structurally — but it is pinned by a test, not assumed.

### New cmd-package surface — `tools/cmd/speccraft-guard/buildprobe.go`

Unexported except where the spec pins a name:

- `BuildProber` interface — `Probe(ctx, buildProbeRequest) (buildProbeResult, error)`.
- `goBuildProber` — the only implementation.
- `buildProbeRequest{ModuleRoot, RealPath, PostContent string}`.
- `buildProbeResult{Clean bool; Output, OverlayJSON, OverlayContent, GoCache string}`
  — the three path fields exist **so AC9 can assert they resolve outside the
  repo root**; they are not decoration.
- `buildProbeTimeout(raw string) time.Duration` — `SPECCRAFT_BUILD_PROBE_TIMEOUT`,
  30s default; unset/empty/invalid/zero/negative → default. Mirrors
  `tasksVerifyTimeout` (spec 0047) and `parseLockTimeout` (spec 0045).
- `moduleRootFor(absPath, repoRoot string) (string, bool)` — nearest ancestor
  `go.mod`, bounded by `repoRoot`.
- `runBuildProbe(...)` — the single call site the AC16 source-scan counts.

`deps` gains `proberForLang func(lang string, cfg speccraft.SpeccraftConfig) (BuildProber, bool)`,
shaped exactly like `runnerForLang`. `productionDeps()` resolves `"go"` → `goBuildProber`
and returns `ok == false` for everything else.

`main.go` also gains `var gatedWriteTools = []string{"Edit", "Write", "MultiEdit", "NotebookEdit"}`
— AC10's single enumeration.

### Probe invocation, pinned

Validated by experiment on this host before planning (go1.22.6):

```
GOCACHE=<os.TempDir()>/speccraft-build-probe-cache
GOFLAGS=-mod=readonly
go build -overlay <tmp>/overlay.json -o <tmp>/out ./...      # cwd = module root
go test  -overlay <tmp>/overlay.json -run '^$' -count=1 ./...   # compiles tests, runs none
```

**The second command is correction C1 — it is not in the spec, and without it the
probe has a hole that reopens the one the review spent three rounds closing.** See
§Corrections C1 and R1. The probe is "clean" only if **both** commands exit 0.

Four decisions that are **not** in the spec text but are forced by AC9, and are
recorded here rather than left to the implementer:

1. **`-o <tmpdir>` is mandatory, not cosmetic.** `go build ./...` discards
   binaries when the pattern matches several packages, but writes the executable
   into the *current directory* when the module has exactly one `main` package.
   Verified both ways. `-o <dir>` outside the root makes AC9 true by construction.
2. **`GOFLAGS=-mod=readonly`** guarantees the probe can never rewrite `go.mod` /
   `go.sum`. Also verified.
3. **No build-tag split.** `go build -overlay` is portable to every platform Go
   supports; unlike spec 0047's `syscall.Setpgid`, nothing here is unix-only. The
   `tasks_predicate.go` / `tasks_predicate_other.go` precedent is deliberately
   **not** mirrored. Spec 0047's process-group problem (a grandchild holding the
   captured pipe hangs `Wait` after the timeout) is real here too, and is solved
   portably with `exec.CommandContext` + `cmd.WaitDelay` (Go 1.20+) rather than
   with `Setpgid`. If a later change genuinely needs group signalling, mirror the
   `_other.go` pair then — not now.

4. **`go test -run '^$'` is the test-compile half, and it is load-bearing** (C1).
   `go build` ignores `_test.go` entirely, while the red-check adapter runs
   `go test` — so without this the probe answers a different question than the one
   that produced `OutcomeBuildFailed`. `-run '^$'` matches no test, so nothing
   executes; `-count=1` defeats the result cache; the overlay and `GOCACHE`
   settings are identical, so AC9's no-mutation guarantee is unaffected.

Verified by experiment: an overlay entry may map a path that **does not exist on
disk**, which is what makes AC10's `Write`-creates-a-new-file case work.

### Attestation lifecycle — a clarification the ACs force

§A.2 says the attestation opens on "the first `OutcomeBuildFailed` of a session",
but AC1 requires that a **clean** probe writes no entry and leaves no attestation.
Reconciled: the attestation opens inside `RecordBuildRepair`, i.e. on the first
**still-broken** probe of the current episode. A clean probe only calls
`ClearBuildRepairAttestation`. This is the only reading that satisfies AC1 and
AC2 simultaneously.

### The injected-failure seam (AC3 / AC13 / AC14) — no new production seam needed

`saveStateLocked` writes `<root>/.speccraft/state.json.tmp` then renames. A test
that pre-creates **`state.json.tmp` as a directory** makes `os.WriteFile` fail
with `EISDIR` on every save, deterministically, on every platform, and
**independently of uid** (verified: fails as uid 1000, and a directory cannot be
opened for writing as root either). So the fault injection is real I/O failure
through the real code path, with zero added production surface.

Helper `injectSaveFailure(t *testing.T, root string)` in
`tools/internal/speccraft/buildrepair_test.go` and a sibling in the guard package.
The coupling to the `.tmp` suffix is an internal-implementation dependency and
gets a comment saying so.

### Ordering discipline — how this spec avoids being spec 0047

Spec 0047 spent 5 overrides because a forward reference in a production file
broke the build and the guard then blocked its own repair. Three rules order
every step below:

1. **Compile-stable REDs first.** A test that names a not-yet-existing symbol is
   a build failure, not a RED. Where a RED can be expressed without naming the
   new symbol, it is:
   - T1 pins three new `Session` fields by writing **literal JSON** into
     `state.json`, `LoadState` → `SaveState`, and asserting the keys survive.
     Unknown keys are dropped today → the test fails **at runtime**, compiles
     fine. This is the spec-0031 `decodeEnvelope` trick applied to struct fields.
   - T12 pins the prober by driving `processToolUse` with **existing** `deps`
     fields only and asserting the edit is allowed. No new symbol is named, so it
     is a runtime RED. Tests that construct `deps{proberForLang: …}` come only
     *after* T14 has added the field.
2. **Stubs before callers.** T2 lands every new exported symbol as a
   compile-clean stub; T13 lands `buildprobe.go` self-contained (it references
   nothing that does not yet exist) and T14 wires it. T13 does **not** turn its
   REDs green and is labelled accordingly — that is the point.
3. **One file per edit.** Each GREEN step touches exactly one file, so no step
   can leave the tree half-wired between two tool calls.

### Override budget

**The stated budget is 1, and it is spent (at most once) on T2** — the
from-scratch exported bootstrap of `tools/internal/speccraft/buildrepair.go`.
T2 is called out as its own task so the count is auditable.

T1 exists specifically to give T2 a **runtime** RED anchor
(`Test_Session_RedBaseline_SurvivesLoadSaveRoundTrip` fails on behaviour, and the
`internal/speccraft` test binary still compiles). If that anchor holds, T2 lands
at **0** overrides and the budget goes unspent. If it does not — e.g. another
test file in the package is red for an unrelated reason — T2 consumes the single
budgeted override and nothing else may.

Every other new symbol rides an existing runtime RED:
- The prober is budget **0** by decision (spec §Bootstrap honesty): it lands in
  the `speccraft-guard` cmd package on the compile-stable `processToolUse` seam.
- `speccraft-state build-repair-log` is budget **0**: it rides the `run()` seam,
  where every RED is a runtime "unknown subcommand".
- Markdown and `bats` are ungated by `speccraft-guard` entirely
  (`conventions.md` §Bash), so T23/T25 cost nothing.

Any override actually spent is recorded in `changelog.md` with its reason and
reported against this budget at close.

### Rebuild discipline

`speccraft-guard` gates its own implementation, and the copy first on `PATH` may
be a **stale cached build**. After T9, T14, T16 and T21, rebuild into `./bin/`
and use `./bin/speccraft-guard` — never a bare `speccraft-guard` — before
continuing. Registering a decisive RED uses **Edit**, not a fresh **Write**
(`conventions.md` §"Registering a RED under a stale cached guard").

---

## Test-first sequence

### Step 1 — Session state keys round-trip (RED)
- Add `tools/internal/speccraft/state_buildrepair_test.go` (`package speccraft_test`):
  - `Test_Session_RedBaseline_SurvivesLoadSaveRoundTrip` — writes literal
    `{"session":{"red_baseline":{"/a/foo_test.go":["TestAlpha"]}}}`, `LoadState`,
    `SaveState`, re-reads the raw bytes, asserts the key survives.
  - `Test_Session_BuildRepairLog_SurvivesLoadSaveRoundTrip` — same for
    `build_repair` (one entry with `seq`, `path`, `digest`, `summary`, `at`).
  - `Test_Session_BuildRepairAttestation_SurvivesLoadSaveRoundTrip` — same for
    `build_repair_attestation`.
  - `Test_Session_NewKeys_AreOmittedWhenUnset` — a state with none of the three
    set serialises without any of the keys (the `,omitempty` contract).
- Tests fail: `Session` has no such fields, so `json.Unmarshal` discards the keys
  and `SaveState` writes them away. **Runtime failure, not a build failure** —
  the package still compiles, which is what makes step 2 free.

### Step 2 — From-scratch exported bootstrap (GREEN) — **THE OVERRIDE STEP**
- Create `tools/internal/speccraft/buildrepair.go` in **one** edit containing
  every new exported symbol from §Design as a compile-clean stub
  (`NormalizeStateKey`, `CaptureRedCandidates`, `GetRedBaseline`,
  `RecordBuildRepair`, `ClearBuildRepairAttestation`, `GetBuildRepair`), the three
  types, `ErrBuildRepairBudgetExhausted`, and the three unexported consts
  including `buildRepairMaxEdits = 10`.
- Stubs return zero values / `nil` so later REDs fail on **behaviour**.
- Imports (`crypto/sha256`, `encoding/hex`, `errors`, `fmt`, `os`, `path/filepath`,
  `time`) all land with their uses in this same edit — no import-then-use deadlock.
- This is the one edit permitted to consume the single budgeted override, and
  only if step 1's runtime-RED anchor does not carry it.
- Step 1's tests still fail (fields not added yet). `go build ./...` is green.

### Step 3 — `Session` gains the three fields (GREEN)
- Edit `tools/internal/speccraft/state.go`: add `RedBaseline`, `BuildRepair`,
  `BuildRepairAttestation` with `,omitempty`, each with a doc comment naming
  spec 0048 and the "cleared only by `ResetSession`" rule for the log.
- All step-1 tests pass.

### Step 4 — Normalizer + atomic baseline capture (RED)
- Add `tools/internal/speccraft/buildrepair_test.go` (`package speccraft_test`):
  - `Test_NormalizeStateKey_UncleanedPathCollapsesToSameKey`
  - `Test_NormalizeStateKey_SymlinkedPathCollapsesToSameKey` — asymmetric
    assertion per `conventions.md` §"Assert asymmetrically": normalize only the
    **expected** value, compare `got` untouched.
  - `Test_NormalizeStateKey_NonexistentFile_StillNormalizes` — a test file created
    in-session must get a key, not an error.
  - `Test_CaptureRedCandidates_FirstTouch_SetsBaselineFromPreIDs`
  - `Test_CaptureRedCandidates_LaterTouch_DoesNotRewriteBaseline` — mutate the
    file between touches, assert `GetRedBaseline` is unchanged (AC13).
  - `Test_CaptureRedCandidates_NoNewTest_PreservesStandingCandidates` (AC11 at the
    state layer)
  - `Test_CaptureRedCandidates_Deletion_ShrinksCandidateSet` (AC12)
  - `Test_CaptureRedCandidates_SaveFailure_LeavesNeitherBaselineNorCandidates`
    (AC13; uses `injectSaveFailure`)
  - `Test_ResetSession_ClearsBaselineCandidatesAttestationAndLog` (AC13)
- **Also in this step** (test-file edit, free): extend
  `tools/internal/speccraft/state_single_writer_test.go` —
  `TestRustState_NoExternalWriters_Grep` currently allowlists only
  `internal/speccraft/state.go`, and `buildrepair.go` will assign
  `s.Session.RedCandidates = …` when the map is nil, which the existing
  `\.RedCandidates\s*=[^=]` pattern flags. Add `buildrepair.go` to `allowedFiles`
  and add `\.RedBaseline\s*=[^=]`, `\.BuildRepair\s*=[^=]`,
  `\.BuildRepairAttestation\s*=[^=]` to `patterns`, so the single-writer guardrail
  covers the new fields instead of silently not covering them.
- Tests fail: the step-2 stubs return `nil`.

### Step 5 — Baseline capture implementation (GREEN)
- Implement `NormalizeStateKey`, `CaptureRedCandidates`, `GetRedBaseline` in
  `tools/internal/speccraft/buildrepair.go`.
- `CaptureRedCandidates` takes `mu.Lock()` **once** around
  `loadStateLocked` → baseline-iff-absent → recompute candidates →
  `saveStateLocked`, following `SetRedCandidates` / `ConsumeOverride`.
- All step-4 tests pass.

### Step 6 — Build-repair ledger semantics (RED)
- Extend `tools/internal/speccraft/buildrepair_test.go`:
  - `Test_RecordBuildRepair_FirstEntry_OpensAttestationAndLogsSeq1`
  - `Test_RecordBuildRepair_DigestIsSHA256OfFullPreTruncationBytes` — feed >4 KiB
    of error text, assert `Digest == sha256(full bytes)` and that `Summary` is the
    capped form.
  - `Test_RecordBuildRepair_SummaryCappedAt4KiBWithVisibleMarker`
  - `Test_RecordBuildRepair_NEntries_AreSequenceOrdered` (AC2)
  - `Test_RecordBuildRepair_BudgetIsSessionWide_CleanProbeDoesNotRefund` — the
    **interleaved** AC4 sequence: 6 records → `ClearBuildRepairAttestation`
    (assert attestation nil, log length still 6) → 4 more records → the 5th
    returns `ErrBuildRepairBudgetExhausted` and appends nothing.
  - `Test_RecordBuildRepair_ResetSession_RestoresFullBudget` (AC4)
  - `Test_RecordBuildRepair_SaveFailure_ReturnsErrorAndWritesNoPartialEntry` (AC3)
  - `Test_RecordBuildRepair_PathKeyIsNormalized` (AC15)
  - `Test_ClearBuildRepairAttestation_KeepsLog`
- Tests fail: stubs.

### Step 7 — Build-repair ledger implementation (GREEN)
- Implement `RecordBuildRepair`, `ClearBuildRepairAttestation`, `GetBuildRepair`
  in `buildrepair.go`. Single `mu.Lock()`; the cap check happens **inside** the
  locked section, before the append, so the record-before-allow rule cannot race.
- All step-6 tests pass.

### Step 8 — Guard-level baseline behaviour, incl. AC14 (RED)
- Add `tools/cmd/speccraft-guard/redbaseline_test.go`. All tests drive
  `processToolUse` with existing `deps` fields — compile-stable:
  - `Test_TestFileEdit_NoNewTest_PreservesRedCandidates` — the AC11 session:
    baseline `foo_test.go`, edit 1 adds `TestAlpha`, edit 2 adds only an import
    line, then a `foo.go` production edit backed by a failing `TestAlpha` is
    allowed. This is the case `conventions.md:64-87` works around by renaming.
  - `Test_TestFileEdit_Deletion_ShrinksRedCandidates` (AC12)
  - `Test_TestFileEdit_CaptureFailure_BlocksEdit_AndLeavesDiskByteUnchanged` —
    **AC14 touch 1, the load-bearing test.** `sha256` of the file bytes plus
    `os.Stat` size are captured before, the edit is driven with
    `injectSaveFailure` active, and the assertion order is: (a) `err != nil`,
    (b) the file's bytes are **identical**, (c) `GetRedBaseline` has no entry,
    (d) `GetRedCandidates` has no entry.
  - `Test_TestFileEdit_CaptureFailure_ThenRetry_Recovers` — **AC14 touch 2.**
    Removes the injection, replays the *same* envelope against the *same*
    unchanged content, asserts the baseline is established from the pre-edit ids,
    `TestAlpha` is a candidate, and the `foo.go` production edit is allowed.
  - `Test_TestFileEdit_CaptureFailure_ReportsOnStderr` — via `deps.stderr`.
  - `Test_SiblingLookup_FindsEntryWrittenViaSymlinkedPath` (AC15, behavioural).
- Tests fail: `captureRedCandidates` still swallows every error and still computes
  `postIDs − preIDs` against disk.

### Step 9 — Guard capture path (GREEN)
- Edit `tools/cmd/speccraft-guard/main.go`, one edit:
  - `captureRedCandidates(ti, absPath, root) error` now computes pre/post ids and
    calls `speccraft.CaptureRedCandidates`, returning its error.
  - `dispatchByLanguage`'s `IsTestFile` branch returns that error (blocking the
    test-file edit) and writes the failure to `d.stderr`, naming the file and the
    retry. Its doc comment loses the "best-effort / never blocks" claim.
  - `siblingRedCheck` routes each resolved sibling through
    `speccraft.NormalizeStateKey` before the `redCand[…]` lookup, so both sides of
    the lookup share one normalizer.
- All step-8 tests pass. **Rebuild `./bin/speccraft-guard`.**

### Step 10 — One normalizer, pinned by source-scan (RED)
- Add `tools/internal/speccraft/statekey_normalizer_test.go` (`package speccraft_test`):
  - `Test_NormalizeStateKey_IsTheSoleEntrypoint` — exactly one
    `func NormalizeStateKey(` in the repo (spec-0036 single-entrypoint pattern).
  - `Test_StateKeyConstruction_RoutesThroughNormalizer` — per-function anchored
    scan (spec-0032 rule: anchor on `func X(` and search **within** the body, never
    the first textual match) over `CaptureRedCandidates`, `RecordBuildRepair`,
    `captureRedCandidates` and `siblingRedCheck`: each body must contain
    `NormalizeStateKey(` and must not derive a key with a bare `filepath.Abs(` /
    `filepath.Clean(`.
- Tests fail on whichever call site step 9 did not convert.

### Step 11 — Normalize every remaining key construction (GREEN)
- Edit the offending site(s) named by step 10.
- All step-10 tests pass.

### Step 12 — Prober behaviour through the `processToolUse` seam (RED)
- Add `tools/cmd/speccraft-guard/buildprobe_test.go`, with a `goModuleFixture(t)`
  helper that builds a hermetic temp repo: `.speccraft/`, an in-progress spec, a
  real `go.mod`, a `pkg/` with a production file and a sibling test file.
  **No new symbol is named** — `deps` carries only `runnerForLang`:
  - `Test_BuildProbe_CleanOverlay_AllowsEditSilently` — the adapter returns
    `OutcomeBuildFailed`, the proposed edit repairs the module, so the overlay
    builds clean → `processToolUse` returns `nil`, `GetBuildRepair` has an empty
    log and a nil attestation (AC1).
  - `Test_BuildProbe_CleanOverlay_ClearsAttestationAndReArmsRedCheck` — with an
    attestation already open, a clean probe clears it and the **next** production
    edit is blocked by the ordinary red-check again (AC1).
  - `Test_BuildProbe_StillBrokenOverlay_AllowsAndRecordsEntry` — the proposed edit
    does not repair the module → `nil` returned, attestation active, one log entry
    with `Seq == 1`, a normalized absolute path, a digest over the full error
    bytes, and a capped summary (AC2).
- Tests fail: `siblingRedCheck` returns the `red-check: build/collection failed`
  error on every `OutcomeBuildFailed`. **Runtime failure — the package compiles.**

### Step 13 — `buildprobe.go` lands standalone (GREEN, half 1 — REDs stay red)
- Create `tools/cmd/speccraft-guard/buildprobe.go` with `BuildProber`,
  `buildProbeRequest`, `buildProbeResult`, `goBuildProber`, `buildProbeTimeout`,
  `moduleRootFor`, and `runBuildProbe`.
- The file references **nothing that does not already exist**; it compiles on its
  own and is not yet called from anywhere.
- **Step-12 tests are still red after this step, by design.** This step exists
  only to satisfy stubs-before-callers, so that step 14 is a single compile-clean
  edit rather than a forward reference. Do not tick step 12 here.

### Step 14 — Wire the prober (GREEN, half 2)
- Edit `tools/cmd/speccraft-guard/main.go`, one edit:
  - `deps` gains `proberForLang`; `productionDeps()` resolves `"go"` →
    `&goBuildProber{}` and `ok == false` for every other language.
  - `ToolInput` is threaded `dispatchByLanguage` → `goPythonProdGuard` /
    `jsTsDispatch` → `siblingRedCheck` (signature change and both call sites in
    the same edit).
  - The `OutcomeBuildFailed` branch becomes: resolve the prober; `!ok` → today's
    exact error, unchanged; prober error → block naming **both** the original
    build error and the probe failure; clean → `ClearBuildRepairAttestation` then
    `return nil`; still broken → `RecordBuildRepair` **then** `return nil`, and on
    `ErrBuildRepairBudgetExhausted` or any record error → block.
- All step-12 tests pass. **Rebuild `./bin/speccraft-guard`.**

### Step 15 — Repair-mode boundaries (RED)
- Extend `tools/cmd/speccraft-guard/buildprobe_test.go`. `deps.proberForLang`
  exists now, so fakes may be constructed:
  - `Test_BuildProbe_RecordFailure_BlocksEdit` (AC3) — `injectSaveFailure`, assert
    the still-broken branch returns an **error** and no partial entry is observable.
  - `Test_BuildProbe_BudgetExhausted_BlocksNamingOverride` (AC4) — the 11th
    still-broken edit blocks with a message containing `/speccraft:spec:override`.
  - `Test_BuildProbe_BudgetSurvivesCleanProbe_Interleaved` (AC4) — the guard-level
    replay of the 6 → clean → 4 → block sequence, plus `ResetSession` restoring it.
  - `Test_BuildProbe_SequentialRepairScenario_ZeroOverrides` (AC5) — spec 0047's
    shape: a forward reference breaks `pkg/foo.go`, then five sequential repair
    edits of which the first four leave the module broken and the fifth builds
    clean. Asserts zero `ConsumeOverride` calls, four log entries, one silent
    allow, attestation nil at the end.
  - `Test_BuildProbe_UnrelatedEditWhileBroken_AdmittedAndRecorded` (AC6) — an edit
    to a Go file unrelated to the break is admitted, consumes budget, produces an
    entry, and the sequence terminates at AC4's bound.
  - `Test_BuildProbe_InfraFailure_BlocksNamingBothErrors` (AC8) — a fake prober
    returning an error; assert the message carries the original build error **and**
    the probe failure, and that `GetBuildRepair` gained no entry.
  - `Test_BuildProbeTimeout_Matrix` (AC8) — unset / `""` / `"nonsense"` / `"0s"` /
    `"-5s"` → 30s; `"5s"` → 5s. Follows the spec-0045 `parseLockTimeout` matrix shape.
- Some of these may pass on arrival. Any that does is recorded in §Corrections as
  a PIN, not silently ticked as a RED (spec 0047's C4 convention).

### Step 16 — Repair-mode boundary fixes (GREEN)
- Edit `main.go` / `buildprobe.go` for whatever step 15 exposes — error wording,
  sentinel mapping, `WaitDelay`, ordering of record-before-allow.
- All step-15 tests pass. **Rebuild `./bin/speccraft-guard`.**

### Step 17 — Unsupported languages fall back exactly (RED / PIN)
- Add `tools/cmd/speccraft-guard/buildprobe_fallback_test.go`:
  - `Test_BuildProbe_UnsupportedLanguages_FallBackToBlocking` — table over
    `python`, `js`, `ts`. For each: `OutcomeBuildFailed` returns an error whose
    text matches the **current format** — asserted with a `regexp` built from the
    literal prefix/suffix around the `%s`, never a byte-compare, because
    `res.Stderr` varies per invocation. Also: an instrumented `proberForLang`
    records **zero** calls; `os.TempDir()` gains no `speccraft-build-probe-*`
    entry; `state.json` bytes are unchanged.
  - `Test_RustDispatch_BuildFailed_Unchanged_NoProber` — Rust never reaches
    `siblingRedCheck`, so its own `red-check: build failed: %s` text is pinned
    separately and the prober is never constructed.
- Expected to pass on arrival by construction; if so, record as PIN in §Corrections.

### Step 18 — The probe never mutates the tree (RED / PIN)
- Add `tools/cmd/speccraft-guard/buildprobe_nomutation_test.go`:
  - `Test_BuildProbe_NeverMutatesWorkingTree` — a `snapshotTree(t, root)` helper
    walks the whole root recursively and records `relpath → sha256 + mode`.
    Run across **all three** outcomes (clean, still-broken, infrastructure
    failure) and assert the maps are equal, with no path added or removed.
  - `Test_BuildProbe_OverlayAndCacheResolveOutsideRepoRoot` — calls `runBuildProbe`
    directly and asserts `OverlayJSON`, `OverlayContent` and `GoCache` each fail
    `filepath.Rel(root, p)`'s inside-root test. This is why `buildProbeResult`
    carries those three fields.
- Expected to pass by construction (`-o <tmpdir>`, pinned `GOCACHE`,
  `GOFLAGS=-mod=readonly`); if so, record as PIN.

### Step 19 — The ordinary red-check path is unchanged (RED / PIN)
- Add to `buildprobe_fallback_test.go`:
  - `Test_SiblingRedCheck_OrdinaryPaths_Unchanged_ZeroProberInvocations` — a table
    over **every** non-`OutcomeBuildFailed` branch: `OutcomeAllPassed`,
    `OutcomeAtLeastOneFailed`, a non-nil adapter error, an empty just-added set
    (`main.go:529-536`), a nil `runnerForLang` (`main.go:538-540`), and an
    unresolved runner (`main.go:541-548`). Each case asserts the return value and
    the **exact** error string, plus `probeCalls == 0` on an instrumented
    `proberForLang`.
  - `Test_Prober_ReachedFromExactlyOneCallSite` — source-scan: across the guard
    package's non-test `.go` files, `d.proberForLang(` occurs exactly once.
- Expected to pass; if so, record as PIN.

### Step 20 — Gated write tools, paired enumeration (RED)
- Add `tools/cmd/speccraft-guard/writetools_test.go`:
  - `Test_GatedWriteTools_EnumerationIsTheSingleSource` — extracts the literal
    list from `var gatedWriteTools` in `main.go`, then asserts:
    (a) each name appears as a `case "<name>"` **inside `applyEdit`'s body**
    (anchored on `func applyEdit(`, per the spec-0032 rule);
    (b) `hooks/hooks.json`'s `PreToolUse` **and** `PostToolUse` matchers each equal
    `strings.Join(tools, "|")`;
    (c) `hooks/pre-tool-use.sh`'s `GATED_TOOLS=` equals `strings.Join(tools, " ")`.
    Adding a write tool without extending all three fails here.
  - `Test_BuildProbe_EveryGatedWriteTool_ReachesProberWithDerivedContent` —
    **table driven off `gatedWriteTools` itself**, not a hand-written four-case
    list: for each tool, drive a real envelope (Write → `content`, never
    `new_string`; MultiEdit → `edits[]`; NotebookEdit → `new_source`) and assert
    the prober received the correctly-derived post-edit content.
- Tests fail: `gatedWriteTools` does not exist.

### Step 21 — Land the enumeration (GREEN)
- Edit `main.go`: add `var gatedWriteTools` next to `applyEdit`, with a comment
  naming the three consumers and the test that pins them.
- All step-20 tests pass. **Rebuild `./bin/speccraft-guard`.**

### Step 22 — The log has a consumer (RED)
- Add `tools/cmd/speccraft-state/buildrepair_log_test.go`:
  - `Test_StateCmd_BuildRepairLog_EmptyLog_SaysSo` — exit 0, output states the log
    is empty.
  - `Test_StateCmd_BuildRepairLog_NonEmpty_ListsSeqPathSummary` — one line per
    entry carrying its sequence, path and summary.
  - `Test_StateCmd_BuildRepairLog_NeverNonZeroOnContent` — informational, so a
    non-empty log still exits 0 (it must not gate the close).
  These are `run()`-seam REDs: today they fail as "unknown subcommand" at runtime.
- Extend `tests/hooks/close-gate.bats` (**existing file — the subject matches
  exactly**: it is *the* durable contract pin for `commands/spec/close.md`, and
  spec 0047's own header explains why a spec-local `done:` predicate is not enough
  — it stops executing the moment that spec closes):
  - `@test "close.md: step 2 also reports the build-repair log"`
  - `@test "close.md: the build-repair report is informational and does not gate"`
  - `@test "close.md: the report runs alongside tasks-verify, before the diff"`
- Tests fail: no subcommand, no prose.

### Step 23 — Consumer implementation (GREEN)
- Add `tools/cmd/speccraft-state/buildrepair_log.go` (printer) and one
  `case "build-repair-log":` in `tools/cmd/speccraft-state/main.go`.
- Edit `commands/spec/close.md` step 2 to run `speccraft-state build-repair-log`
  alongside `tasks-verify --run`, stating plainly that it reports and does not gate.
- All step-22 tests pass.

### Step 24 — The policy files name the carve-out (RED)
- Add `tools/internal/speccraft/buildrepair_policy_test.go`, declared
  **`package speccraft`** (internal test — needed to read the compiled constant):
  - `Test_Guardrails_CarveOutSentence_NamesCompiledCap` — the **bidirectional,
    mechanical** AC18 pin. Reads `.speccraft/guardrails.md`, locates the carve-out
    sentence with a regex anchored on the sentence (bounded build-repair mode +
    `/speccraft:spec:override`), and requires
    `fmt.Sprintf("%d", buildRepairMaxEdits)` to appear **within that match**.
    Changing the constant without updating the guardrail fails; deleting the bound
    from the sentence fails even if a stale `10` survives elsewhere.
  - `Test_Guardrails_CarveOut_NamesRecordBeforeAllowAndCloseReport` — the sentence
    must also carry the record-before-allow rule and the close-time report.
  - `Test_Conventions_BuildFailureEntry_NoLongerClaimsNeverRelaxed` — the
    `OutcomeBuildFailed`-is-not-a-valid-RED entry in `.speccraft/conventions.md`
    must no longer assert the rule is never relaxed, and must point at the carve-out.
- Tests fail: neither file has been amended.

### Step 25 — Amend the policy files (GREEN)
- Edit `.speccraft/guardrails.md` §TDD invariant: bypasses are
  `/speccraft:spec:override` **or** bounded build-repair mode — capped at 10 edits
  per session, every admission recorded before it is granted, ended by the first
  clean build, reported at close.
- Edit `.speccraft/conventions.md`'s build-failure entry to point at the carve-out
  instead of prohibiting relaxation. **Both files or neither** (spec §A.5).
- Markdown is ungated by the guard, so this costs nothing.
- All step-24 tests pass.

### Step 26 — Refactor and full verification
- Fold any duplication the GREEN steps introduced: the two `injectSaveFailure`
  helpers, the temp-module fixture builders, the sha256-of-tree helper.
- `cd tools && go test ./... -count=1 && go vet ./...`
- Full `bats tests/hooks/` suite green.
- `speccraft-drift scan-all` clean.
- `GOOS=windows go build ./...` green — cheap proof that the no-build-tag decision
  actually holds (this is the check spec 0047 discovered late, as T15.e).
- This file's own `tasks.md` parses clean structurally.
- All tests still pass.

---

## AC → task traceability

| AC | Subject | Tasks |
|---|---|---|
| AC1 | Clean overlay allows silently, ends repair mode | T12, T13, T14 |
| AC2 | Still-broken allows and records atomically | T6, T7, T12, T14 |
| AC3 | A failed record blocks the edit | T6, T7, T15, T16 |
| AC4 | Budget is session-wide; clean probe does not refund | T6, T7, T15, T16 |
| AC5 | The spec-0047 sequential-repair scenario needs zero overrides | T15, T16 |
| AC6 | Unrelated edit admitted, recorded, bounded | T15, T16 |
| AC7 | Unsupported languages fall back to today's blocking | T17 |
| AC8 | Prober that cannot complete blocks and says why; timeout matrix | T15, T16 |
| AC9 | The probe never mutates the working tree | T18 |
| AC10 | Every modeled write tool, pinned by paired enumeration | T20, T21 |
| AC11 | No-new-test re-edit preserves standing candidates | T4, T5, T8, T9 |
| AC12 | Genuine deletion shrinks the candidate set | T4, T5, T8, T9 |
| AC13 | Baselines first-touch-only and atomic; `ResetSession` clears all four | T4, T5, T6, T7 |
| AC14 | Failed capture blocks; **disk byte-unchanged**; retry recovers | T8, T9 |
| AC15 | Path normalization shared and pinned | T4, T5, T8, T9, T10, T11 |
| AC16 | Ordinary red-check path behaviourally unchanged | T19 |
| AC17 | `/speccraft:spec:close` reports the build-repair log | T22, T23 |
| AC18 | Policy files name the carve-out; bound cannot drift | T24, T25 |

Every AC maps to at least one task, and every AC is mechanically testable as
planned. Three ACs needed a named approach rather than an obvious one, all
recorded above: AC9's tri-outcome recursive snapshot plus the three artifact-path
assertions (which is why `buildProbeResult` carries those fields); AC10's
enumeration-driven table plus tri-file source-scan; AC14's byte-unchanged
assertion sequenced *before* the state assertions so a regression names the right
cause; AC16's full-branch table plus one-call-site scan; AC18's
sentence-anchored regex carrying the compiled constant; and AC17's placement in
`tests/hooks/close-gate.bats` rather than a spec-local predicate.

---

## Delegation

- T22 (bats cases in `tests/hooks/close-gate.bats`) and T25 (the
  `guardrails.md` / `conventions.md` amendment) → delegate to a
  general-purpose subagent (reason: markdown and `bats` only; ungated by
  `speccraft-guard` per `conventions.md` §Bash, so a delegate cannot wedge the
  session, and the acceptance oracle — step 24's tests and the bats suite —
  is already written and mechanical).
- T1–T21, T23, T24, T26 → **do not delegate.** These edits are gated by the very
  binary they modify. A delegate without the override budget, the rebuild-into-`./bin/`
  discipline, and the stubs-before-callers ordering would reproduce spec 0047's
  0→5 overshoot. The `## Corrections` log below only works if one agent holds the
  whole sequence.
- Cross-model review is already complete (3 rounds, `review.md`); no further
  `aux-delegator` dispatch is planned. If one is needed, note that the aux-delegator
  false-quorum defect from spec 0047 is still open — use per-agent, per-round output
  paths and compare digests before trusting a second opinion.

---

## Risk

- **R1 — `go build` does not compile `_test.go` files, so a test-only build break
  becomes a silent, unlogged, unbounded allowance.** The guard's Go adapter runs
  `go test`, so a broken *sibling test file* also yields `OutcomeBuildFailed`; the
  overlay `go build ./...` of the proposed **production** edit then reports clean,
  and AC1 fires: allow silently, write no log entry, clear the attestation. Every
  subsequent Go production edit is admitted the same way for as long as the test
  file stays broken. That is strictly wider than the audited repair-mode allowance
  §A.2 was bounded to.
  → **RESOLVED at plan time — the remedy was adopted, not deferred. See §Corrections
  C1.** The probe is now `go build … && go test -run '^$' -count=1 -overlay … ./...`
  and is clean only if both exit 0. T12.d pins the **fixed** behaviour (a test-file
  break is detected, admitted through repair mode, and logged) rather than pinning
  the gap. The residual risk is now only that the spec text still says `go build`
  alone; that discrepancy is recorded as a spec correction to fold in at close.
- **R2 — the guard gates its own implementation.** → mitigation: the three
  ordering rules in §Design (compile-stable REDs first, stubs before callers, one
  file per edit); T13 exists solely to keep T14 from being a forward reference;
  rebuild `./bin/speccraft-guard` after T9, T14, T16, T21.
- **R3 — a stale cached `speccraft-guard` on `PATH`** (spec 0030's class) will
  ignore every fix landed here and keep blocking. → mitigation: invoke
  `./bin/speccraft-guard` explicitly, never bare; introduce each decisive RED via
  **Edit**, never a fresh **Write**.
- **R4 — `injectSaveFailure` depends on `saveStateLocked`'s `path + ".tmp"`
  detail.** If that write strategy changes, the AC3/AC13/AC14 injections stop
  injecting and the tests pass vacuously. → mitigation: the helper carries a
  comment naming the coupling, and asserts the save **actually failed** (a
  non-nil error) before asserting anything about the resulting state, so a
  neutered injection fails loudly instead of silently.
- **R5 — probe latency.** `go build ./...` over the whole module on every
  still-broken Go edit. → mitigation: `GOCACHE` is a **fixed** directory (not
  per-invocation), so only the first probe is cold; the probe runs only on an
  already-broken tree; the 30s deadline is its own budget, never shared with
  `redCheckTimeout`.
- **R6 — `-mod=readonly` turns a missing `go.sum` entry into a build error**, which
  the probe reads as "still broken" → an admitted, logged edit rather than a
  correct block. Fail-safe direction, bounded at 10, and not reachable in this
  repo (`go.sum` is complete). Recorded, not mitigated.
- **R7 — AC6 is a deliberate trade** carried from `review.md` §Residual risk:
  unrelated edits *are* admitted while the build is broken, because relatedness
  is not inferred. T15 pins it explicitly so the trade stays visible.
- **R8 — the final spec text is unreviewed** (`review.md` §Post-round-3 revisions):
  the capture-failure-blocks behaviour, the conventions amendment, and AC18's
  bidirectional pin all landed after round 3. T8, T24 and T25 implement exactly
  those three; if any turns out incoherent in contact with code, record it in
  §Corrections rather than quietly reinterpreting it.

---

## Corrections

This section is where deviations from the plan get recorded **during**
implementation — a step that turned out to be a PIN rather than a RED, a task that
needed splitting, an override spent and why, a spec ambiguity resolved in code. The
convention was started in spec 0047, whose plan correction C2 (override budget
0 → 5) is the reason this spec exists. Append here as you go; do not rewrite the
sequence above.

### C1 — the probe must compile test files, not just build packages

**Recorded at plan time, before any implementation.**

The spec (§A.1) pins the probe as `go build -overlay <json> ./...`. That is
insufficient, and the gap is not cosmetic: `go build` does not compile `_test.go`
files, while the red-check adapter that produced `OutcomeBuildFailed` runs
`go test`. A broken *sibling test file* therefore yields `OutcomeBuildFailed` from
the adapter, a **clean** overlay from `go build`, and AC1 fires — allow silently,
write no log entry, clear the attestation. Every subsequent Go production edit is
admitted the same way for as long as that test file stays broken.

That is an unbounded, unlogged, unaudited allowance — precisely the hole rounds 1
through 3 of `review.md` were spent closing, reintroduced through a mechanism
detail rather than through policy. None of the 18 ACs catch it: they are all
satisfiable with `go build` alone, and AC5's fixture is a *production* forward
reference, which `go build` does catch.

**Correction:** the probe runs two commands and is clean only if both exit 0:

```
go build -overlay <json> -o <tmpdir> ./...
go test  -overlay <json> -run '^$' -count=1 ./...
```

`-run '^$'` matches no test, so nothing is executed; `-count=1` defeats the result
cache. Same overlay, same `GOCACHE`, same deadline — AC9's no-mutation guarantee
and every other AC oracle are unaffected.

**Status:** adopted in this plan; T12.d and T13 are written against the corrected
behaviour. `spec.md` §A.1 still describes `go build` alone, and it is `reviewed`
and so not edited here. Fold the corrected wording into the spec at close, or
raise a `spec:revise` round if the discrepancy should be reviewed rather than
recorded. Discovered by `tdd-planner`; no reviewer caught it in three rounds,
which is itself worth noting — a probe's *question* can be wrong even when its
policy is right.
