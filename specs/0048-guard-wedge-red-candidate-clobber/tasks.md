---
spec: "0048"
contract: done-means-v1
---

# Tasks

- [x] **T1** — RED: the three new session keys survive a load/save round-trip (compile-stable field RED)
  done: $ grep -q 'func Test_Session_RedBaseline_SurvivesLoadSaveRoundTrip(' tools/internal/speccraft/state_buildrepair_test.go && cd tools && go test ./internal/speccraft/ -run 'Test_Session_(RedBaseline|BuildRepairLog|BuildRepairAttestation)_SurvivesLoadSaveRoundTrip|Test_Session_NewKeys_AreOmittedWhenUnset' -count=1
- [x] **T2** — GREEN: from-scratch exported bootstrap in `buildrepair.go` — **THE ONE BUDGETED OVERRIDE STEP** (budget 1; spend 0 if T1's runtime RED carries it)
  done: $ [ "$(grep -cE '^func (NormalizeStateKey|CaptureRedCandidates|GetRedBaseline|RecordBuildRepair|ClearBuildRepairAttestation|GetBuildRepair)\(' tools/internal/speccraft/buildrepair.go)" = 6 ] && grep -qE '^\s*buildRepairMaxEdits\s*=\s*10' tools/internal/speccraft/buildrepair.go && cd tools && go build ./...
- [x] **T3** — GREEN: `Session` gains `red_baseline`, `build_repair`, `build_repair_attestation` (all `,omitempty`)
  done: $ grep -q 'red_baseline,omitempty' tools/internal/speccraft/state.go && grep -q 'build_repair,omitempty' tools/internal/speccraft/state.go && grep -q 'build_repair_attestation,omitempty' tools/internal/speccraft/state.go && cd tools && go test ./internal/speccraft/ -run 'Test_Session_' -count=1
- [x] **T4** — RED: normalizer + atomic baseline capture semantics, and the single-writer allowlist extended to cover the new fields
  - [x] **T4.a** — normalizer: uncleaned, symlinked, and not-yet-existing paths
  - [x] **T4.b** — first-touch baseline, later-touch immutability, no-new-test preservation, deletion shrink
  - [x] **T4.c** — injected save failure leaves neither baseline nor candidates
  - [x] **T4.d** — `TestRustState_NoExternalWriters_Grep` allowlists `buildrepair.go` and gains the three new field patterns
  done: $ grep -q 'buildrepair.go' tools/internal/speccraft/state_single_writer_test.go && grep -q 'RedBaseline' tools/internal/speccraft/state_single_writer_test.go && cd tools && go test ./internal/speccraft/ -run 'Test_NormalizeStateKey_|Test_CaptureRedCandidates_|Test_ResetSession_ClearsBaselineCandidatesAttestationAndLog|TestRustState_NoExternalWriters_Grep' -count=1
- [x] **T5** — GREEN: implement `NormalizeStateKey`, `CaptureRedCandidates`, `GetRedBaseline` under one `mu.Lock()` and one save
  done: $ grep -q 'mu.Lock()' tools/internal/speccraft/buildrepair.go && [ "$(grep -c 'saveStateLocked' tools/internal/speccraft/buildrepair.go)" -ge 1 ] && cd tools && go test ./internal/speccraft/ -run 'Test_NormalizeStateKey_|Test_CaptureRedCandidates_' -count=1
- [x] **T6** — RED: build-repair ledger semantics — attestation, sha256 digest, 4 KiB summary cap, session-wide budget, save-failure atomicity
  - [x] **T6.a** — first entry opens the attestation and logs seq 1; N entries are sequence-ordered
  - [x] **T6.b** — digest is sha256 over the FULL pre-truncation bytes; summary capped with a visible marker
  - [x] **T6.c** — AC4 interleaved: 6 → clean → log still 6 → 4 more → 5th exhausted; `ResetSession` restores
  - [x] **T6.d** — injected save failure returns an error and writes no partial entry
  done: $ grep -q 'Test_RecordBuildRepair_BudgetIsSessionWide_CleanProbeDoesNotRefund' tools/internal/speccraft/buildrepair_test.go && cd tools && go test ./internal/speccraft/ -run 'Test_RecordBuildRepair_|Test_ClearBuildRepairAttestation_' -count=1
- [x] **T7** — GREEN: implement `RecordBuildRepair`, `ClearBuildRepairAttestation`, `GetBuildRepair` with the cap enforced inside the lock
  done: $ grep -q 'ErrBuildRepairBudgetExhausted' tools/internal/speccraft/buildrepair.go && grep -q 'buildRepairMaxEdits' tools/internal/speccraft/buildrepair.go && cd tools && go test ./internal/speccraft/ -count=1
- [x] **T8** — RED: guard-level baseline behaviour, including AC14's byte-unchanged assertion
  - [x] **T8.a** — no-new-test re-edit preserves candidates; the prod edit is allowed (AC11)
  - [x] **T8.b** — deletion shrinks the candidate set (AC12)
  - [x] **T8.c** — capture failure BLOCKS the test-file edit and leaves `foo_test.go` byte-unchanged (AC14 touch 1)
  - [x] **T8.d** — the retry re-captures from that unchanged content and the prod edit is allowed (AC14 touch 2)
  - [x] **T8.e** — the sibling lookup finds an entry written through a symlinked path (AC15)
  done: $ grep -q 'Test_TestFileEdit_CaptureFailure_BlocksEdit_AndLeavesDiskByteUnchanged' tools/cmd/speccraft-guard/redbaseline_test.go && cd tools && go test ./cmd/speccraft-guard/ -run 'Test_TestFileEdit_|Test_SiblingLookup_FindsEntryWrittenViaSymlinkedPath' -count=1
- [x] **T9** — GREEN: guard capture path calls the atomic op, blocks on failure, reports on stderr, and normalizes both sides of the sibling lookup
  done: $ grep -q 'speccraft.CaptureRedCandidates(' tools/cmd/speccraft-guard/main.go && grep -q 'speccraft.NormalizeStateKey(' tools/cmd/speccraft-guard/main.go && ! grep -q 'Best-effort: a capture error never blocks' tools/cmd/speccraft-guard/main.go && cd tools && go test ./cmd/speccraft-guard/ -count=1
- [x] **T10** — RED: one normalizer, pinned by an anchored per-function source-scan
  done: $ grep -q 'Test_NormalizeStateKey_IsTheSoleEntrypoint' tools/internal/speccraft/statekey_normalizer_test.go && cd tools && go test ./internal/speccraft/ -run 'Test_NormalizeStateKey_IsTheSoleEntrypoint|Test_StateKeyConstruction_RoutesThroughNormalizer' -count=1
- [x] **T11** — GREEN: every remaining state-key construction routes through `NormalizeStateKey`
  done: $ [ "$(grep -rc 'func NormalizeStateKey(' tools/internal/speccraft/buildrepair.go)" = 1 ] && cd tools && go test ./internal/speccraft/ -run 'Test_StateKeyConstruction_RoutesThroughNormalizer' -count=1
- [x] **T12** — RED: prober behaviour through the compile-stable `processToolUse` seam (AC1/AC2) plus the R1 known-gap pin
  - [x] **T12.a** — clean overlay allows silently, writes no entry (AC1)
  - [x] **T12.b** — clean overlay clears the attestation and re-arms the ordinary red-check (AC1)
  - [x] **T12.c** — still-broken overlay allows and records one entry with seq, normalized path, digest, capped summary (AC2)
  - [x] **T12.d** — correction C1: a broken sibling TEST file is detected by the probe's `go test -run '^$'` half, so it is admitted through bounded repair mode and LOGGED — never silently allowed
  done: $ grep -q 'Test_BuildProbe_CleanOverlay_AllowsEditSilently' tools/cmd/speccraft-guard/buildprobe_test.go && grep -q 'Test_BuildProbe_ProductionCleanTestBroken_IsDetectedAndLogged' tools/cmd/speccraft-guard/buildprobe_test.go && cd tools && go test ./cmd/speccraft-guard/ -run 'Test_BuildProbe_(CleanOverlay|StillBrokenOverlay|ProductionCleanTestBroken)' -count=1
- [x] **T13** — GREEN (half 1, stubs-before-callers): `buildprobe.go` lands standalone and compiles; T12 stays RED on purpose. Includes correction C1's two-command probe.
  done: $ grep -q 'func runBuildProbe(' tools/cmd/speccraft-guard/buildprobe.go && grep -q 'WaitDelay' tools/cmd/speccraft-guard/buildprobe.go && grep -q 'GOFLAGS=-mod=readonly' tools/cmd/speccraft-guard/buildprobe.go && grep -q -- "-run" tools/cmd/speccraft-guard/buildprobe.go && grep -q -- '-count=1' tools/cmd/speccraft-guard/buildprobe.go && cd tools && go build ./... && GOOS=windows go build ./...
- [x] **T14** — GREEN (half 2): wire `deps.proberForLang`, carry `ToolInput` on `deps` (NOT threaded through `siblingRedCheck`'s signature — see Bypasses), replace the `OutcomeBuildFailed` return with a call to `buildRepairBranch`, which lives in `buildprobe.go` beside the probe rather than inline in `main.go`. Predicate retargeted to the actual placement: `main.go` wires the factory and calls the branch; `buildprobe.go` resolves `d.proberForLang` exactly once and owns the only `runBuildProbe` call site
  done: $ grep -q 'proberForLang' tools/cmd/speccraft-guard/main.go && grep -q 'buildRepairBranch(' tools/cmd/speccraft-guard/main.go && [ "$(grep -c 'd.proberForLang(' tools/cmd/speccraft-guard/buildprobe.go)" = 1 ] && grep -q 'runBuildProbe(' tools/cmd/speccraft-guard/buildprobe.go && (cd tools && go test ./cmd/speccraft-guard/ -run 'Test_BuildProbe_' -count=1)
- [x] **T15** — RED: repair-mode boundaries — AC3 record-failure, AC4 budget, AC5 zero-override repair run, AC6 unrelated edit, AC8 infra failure + timeout matrix
  - [x] **T15.a** — a failed record BLOCKS and leaves no partial entry (AC3)
  - [x] **T15.b** — the 11th still-broken edit blocks naming `/speccraft:spec:override` (AC4)
  - [x] **T15.c** — the interleaved 6 → clean → 4 → block sequence, and `ResetSession` restoring the budget (AC4)
  - [x] **T15.d** — spec 0047's five-edit sequential repair runs at ZERO overrides (AC5)
  - [x] **T15.e** — an unrelated Go edit while broken is admitted, recorded, and bounded (AC6)
  - [x] **T15.f** — a prober that cannot complete blocks naming BOTH errors; no entry written (AC8)
  - [x] **T15.g** — `SPECCRAFT_BUILD_PROBE_TIMEOUT` matrix: unset/empty/invalid/zero/negative → 30s (AC8)
  done: $ grep -q 'Test_BuildProbe_SequentialRepairScenario_ZeroOverrides' tools/cmd/speccraft-guard/buildprobe_test.go && cd tools && go test ./cmd/speccraft-guard/ -run 'Test_BuildProbe_(RecordFailure|BudgetExhausted|BudgetSurvivesCleanProbe|SequentialRepairScenario|UnrelatedEditWhileBroken|InfraFailure)|Test_BuildProbeTimeout_Matrix' -count=1
- [x] **T16** — GREEN: repair-mode boundary fixes — **NO CODE CHANGE NEEDED.** T15's seven boundary groups (AC3 record-failure, AC4 budget + interleaving, AC5 the zero-override five-edit repair run, AC6 unrelated edit, AC8 probe-failure + timeout matrix) all passed against T14's `buildRepairBranch` as landed: record-before-allow ordering, the `ErrBuildRepairBudgetExhausted` sentinel mapping and the override wording were already correct. Recorded as a PIN set rather than a fake RED→GREEN. Predicate retargeted to `buildprobe.go`, where the branch lives (see T14)
  done: $ grep -q 'ErrBuildRepairBudgetExhausted' tools/cmd/speccraft-guard/buildprobe.go && grep -q 'speccraft:spec:override' tools/cmd/speccraft-guard/buildprobe.go && (cd tools && go test ./cmd/speccraft-guard/ -count=1)
- [x] **T17** — RED/PIN: unsupported languages fall back to today's exact blocking behaviour (AC7), Rust included and pinned separately
  done: $ grep -q 'Test_RustDispatch_BuildFailed_Unchanged_NoProber' tools/cmd/speccraft-guard/buildprobe_fallback_test.go && cd tools && go test ./cmd/speccraft-guard/ -run 'Test_BuildProbe_UnsupportedLanguages_FallBackToBlocking|Test_RustDispatch_BuildFailed_Unchanged_NoProber' -count=1
- [x] **T18** — RED/PIN: the probe never mutates the tree — tri-outcome recursive snapshot plus overlay/content/GOCACHE all outside the root (AC9)
  done: $ grep -q 'Test_BuildProbe_OverlayAndCacheResolveOutsideRepoRoot' tools/cmd/speccraft-guard/buildprobe_nomutation_test.go && cd tools && go test ./cmd/speccraft-guard/ -run 'Test_BuildProbe_(NeverMutatesWorkingTree|OverlayAndCacheResolveOutsideRepoRoot)' -count=1
- [x] **T19** — RED/PIN: the ordinary red-check path is behaviourally unchanged — full branch table plus a one-call-site source-scan (AC16)
  done: $ grep -q 'Test_Prober_ReachedFromExactlyOneCallSite' tools/cmd/speccraft-guard/buildprobe_fallback_test.go && cd tools && go test ./cmd/speccraft-guard/ -run 'Test_SiblingRedCheck_OrdinaryPaths_Unchanged_ZeroProberInvocations|Test_Prober_ReachedFromExactlyOneCallSite' -count=1
- [ ] **T20** — RED: gated write tools pinned by paired enumeration across `hooks.json`, `pre-tool-use.sh`, `applyEdit` and the prober table (AC10)
  done: $ grep -q 'Test_GatedWriteTools_EnumerationIsTheSingleSource' tools/cmd/speccraft-guard/writetools_test.go && cd tools && go test ./cmd/speccraft-guard/ -run 'Test_GatedWriteTools_EnumerationIsTheSingleSource|Test_BuildProbe_EveryGatedWriteTool_ReachesProberWithDerivedContent' -count=1
- [ ] **T21** — GREEN: land `var gatedWriteTools` in `main.go` as the single source the three consumers agree with
  done: $ grep -q 'gatedWriteTools' tools/cmd/speccraft-guard/main.go && grep -q 'Edit|Write|MultiEdit|NotebookEdit' hooks/hooks.json && grep -q 'GATED_TOOLS="Edit Write MultiEdit NotebookEdit"' hooks/pre-tool-use.sh && cd tools && go test ./cmd/speccraft-guard/ -run 'Test_GatedWriteTools_' -count=1
- [ ] **T22** — RED: the log gets a consumer — `speccraft-state build-repair-log` (run() seam) plus durable bats cases in `close-gate.bats` (AC17)
  done: $ grep -q 'build-repair-log' tests/hooks/close-gate.bats && grep -q 'Test_StateCmd_BuildRepairLog_NonEmpty_ListsSeqPathSummary' tools/cmd/speccraft-state/buildrepair_log_test.go && cd tools && go test ./cmd/speccraft-state/ -run 'Test_StateCmd_BuildRepairLog_' -count=1
- [ ] **T23** — GREEN: `case "build-repair-log":` plus the informational report in `commands/spec/close.md` step 2
  done: $ grep -q 'case "build-repair-log":' tools/cmd/speccraft-state/main.go && grep -q 'build-repair-log' commands/spec/close.md && bats tests/hooks/close-gate.bats
- [ ] **T24** — RED: AC18's bidirectional anti-drift pin — the compiled cap must appear inside the guardrail's carve-out sentence
  - [ ] **T24.a** — internal test file (`package speccraft`) so the unexported constant is readable
  - [ ] **T24.b** — regex anchored on the carve-out SENTENCE, never on a bare numeral
  - [ ] **T24.c** — `conventions.md` no longer claims the build-failure rule is never relaxed
  done: $ head -1 tools/internal/speccraft/buildrepair_policy_test.go | grep -qx 'package speccraft' && grep -q 'buildRepairMaxEdits' tools/internal/speccraft/buildrepair_policy_test.go && cd tools && go test ./internal/speccraft/ -run 'Test_Guardrails_CarveOut|Test_Conventions_BuildFailureEntry_NoLongerClaimsNeverRelaxed' -count=1
- [ ] **T25** — GREEN: amend `.speccraft/guardrails.md` and `.speccraft/conventions.md` together (both or neither, spec §A.5)
  done: $ grep -q 'build-repair' .speccraft/guardrails.md && grep -q '10' .speccraft/guardrails.md && ! grep -q 'must not be relaxed' .speccraft/conventions.md && cd tools && go test ./internal/speccraft/ -run 'Test_Guardrails_CarveOut|Test_Conventions_BuildFailureEntry' -count=1
- [ ] **T26** — REFACTOR + full verification: dedupe test helpers, whole suite, vet, drift, cross-compile
  - [ ] **T26.a** — `go test ./... -count=1` and `go vet ./...` green
  - [ ] **T26.b** — full `bats tests/hooks/` suite green. NOTE: the `done:` predicate below deliberately EXCLUDES `tasks-verify.bats`, because that suite invokes `speccraft-state tasks-verify`, which is the verifier executing this predicate — the spec-0047 no-self-recursion rule. Run it manually as part of this task; it is not a silent omission.
  - [ ] **T26.c** — `speccraft-drift scan-all` clean
  - [ ] **T26.d** — `GOOS=windows go build ./...` green (proves the no-build-tag decision)
  - [ ] **T26.e** — overrides actually spent are recorded in `changelog.md` against the stated budget of 1
  - [ ] **T26.f** — R1 follow-up spec filed for the test-compile blind spot
  done: $ cd tools && go test ./... -count=1 && go vet ./... && GOOS=windows go build ./... && cd .. && bats $(ls tests/hooks/*.bats | grep -v tasks-verify)

## Bypasses

- 2026-09-25 — override: T9, the read-side normalization in `siblingRedCheck`.
  **The budgeted override, spent on the wedge itself rather than on T2's
  bootstrap.** T2 landed free because T1's raw-JSON RED is compile-stable, so the
  budget was available. `Test_SiblingRedCheck_FindsCandidateRegisteredUnderUnnormalizedKey`
  was demonstrably FAILING at the moment of this edit (verified: "TDD invariant:
  no failing test observed for …/link/pkg"), but the preceding edit to
  `redbaseline_test.go` added no new `func Test…` line, so **defect B — the very
  bug this spec fixes — reset that file's registered candidates to `[]` and the
  guard refused the repair.** Fourth occurrence this session; routed around the
  first three by adding genuinely useful tests, and declined to invent a fourth
  test purely to appease the bookkeeping.
- 2026-09-25 — override: T9, second read site. **BUDGET OVERRUN: stated 1, actual
  2.** `siblingRedCheck` indexes `redCand` in TWO places — once gathering
  `justAdded`, and again at `ids := redCand[sib]` to decide which ids to RUN. I
  normalized only the first, so the adapter never fired and the test moved from
  "no failing test for …/link/pkg" to "no failing test among the tests added".
  The test caught the incomplete fix; the cost is that the follow-up is a second
  EDIT, and `ConsumeOverride` is per-edit (spec 0049's lesson, applied one task
  too late). Both sites should have been one edit. No new test was needed to
  justify this, and inventing one to appease the clobbered bookkeeping would have
  been padding.
- 2026-09-25 — override: T14, adding `buildRepairBranch` after having already
  referenced it. **Overrun continues: 3 spent against a budget of 1.** Entirely
  self-inflicted and instructive: the plan mandates stubs-before-callers precisely
  so a forward reference never breaks the build (T13 exists only to satisfy it, and
  I followed it there). I then wired the `OutcomeBuildFailed` branch to call a
  helper I had not written yet, so `cmd/speccraft-guard` stopped compiling, the
  red-check returned `OutcomeBuildFailed`, and the guard forbade the edit that
  completes its own repair — **defect A, experienced first-hand while fixing
  defect A.** The lesson is the plan's, not new: write the callee first, always.
