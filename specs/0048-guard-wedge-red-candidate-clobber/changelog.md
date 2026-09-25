---
spec: "0048"
closed: 2026-09-25
---

# Changelog — 0048 Guard wedge and red-candidate clobber

**Status:** closed · **Ships in:** unreleased at 1.16.0 · **Date:** 2026-09-25

## What shipped

Two defects in `speccraft-guard`'s red-check path, both of which made the guard
block edits it had no business blocking, and both of which had already been
papered over with avoidance advice in `conventions.md` — the tell that they were
product defects rather than user error.

### Defect A — a broken build made the guard forbid its own repair

`OutcomeBuildFailed` blocked the edit. The rule ("a build failure is not a valid
RED") is right; its blast radius was not. When the break was in **production**
code, every later production edit in that package hit `OutcomeBuildFailed` —
including the edit that would repair the break. Spec 0047 stated an override
budget of 0 and spent 5 on exactly this.

Now, on `OutcomeBuildFailed` for Go, the guard probes whether the **proposed**
edit leaves the module compiling, and branches four ways:

| probe result | behaviour |
|---|---|
| no prober for the language | today's exact refusal, unchanged (AC7) |
| probe could not complete | **block**, naming both the build error and the probe failure |
| overlay builds clean | the edit repairs it — close repair mode, allow silently |
| overlay still broken | allow, but **record first** against a bounded budget |

The bound is 10 edits per session, enforced *inside* the atomic record operation
(the only placement where "recorded before allowed" is race-free) and derived
solely from the log's length, so a clean probe ends repair mode without refunding
spent budget.

### Defect B — an edit that added no test clobbered the red candidates

An edit to a test file adding no new `func Test…` reset that file's registered
candidates to `[]`, blocking a legitimately-RED production edit. The cause was
the guard computing the just-added set as `postIDs − preIDs`: on a second edit
those are identical, so the difference is empty.

Now a per-file `red_baseline` is captured **first touch only**, and candidates are
always recomputed as `postIDs − baseline`. A no-new-test edit recomputes the same
set; a genuine deletion still shrinks it. The first-touch check is `_, ok :=`
rather than a length check, because a brand-new test file whose baseline is
legitimately empty has still been touched.

### Supporting work

- **One state-key normalizer** (`NormalizeStateKey`), pinned by a repo-wide
  single-definition assertion and per-package anchored routing scans. Two
  normalizers that disagree is how a baseline gets registered under a key the
  lookup can never see.
- **`var gatedWriteTools`** as the single source for the gated tool set, which was
  previously duplicated across four consumers with nothing connecting them.
- **`speccraft-state build-repair-log`**, reported by `close.md` step 2 —
  informational, always exit 0.
- **`guardrails.md` and `conventions.md` amended together**, with the documented
  cap pinned to the compiled one bidirectionally.
- **`saveStateLocked` now routes its rename through the package's single
  `atomicRename` seam** (spec 0035, previously used only by `WriteReviewFile`) —
  the retrofit spec 0035 explicitly skipped. The plan called for a new
  `injectSaveFailure`; reusing the existing seam keeps ONE fault-injection point
  for every durable write in `internal/speccraft`.

## Files touched

27 files, +3787 / −90. `started_at_sha: 9f7329d7` is set on this spec, so
`git diff <sha>...HEAD` is exact and self-scoping — unlike spec 0049, whose close
diff was empty and whose file list had to be reconstructed by hand.

**Production (Go):**

- `tools/internal/speccraft/buildrepair.go` (new) — the state layer:
  `NormalizeStateKey`, `CaptureRedCandidates`, `GetRedBaseline`,
  `RecordBuildRepair`, `ClearBuildRepairAttestation`, `GetBuildRepair`, the
  unexported cap/summary/marker constants, and `ErrBuildRepairBudgetExhausted`
- `tools/internal/speccraft/state.go` — three new `,omitempty` `Session` fields;
  `saveStateLocked` routed through the spec-0035 `atomicRename` seam
- `tools/cmd/speccraft-guard/buildprobe.go` (new) — `BuildProber`,
  `goBuildProber`, `buildRepairBranch`, `runBuildProbe`, `buildProbeTimeout`,
  `buildFailedBlockError`, `moduleRootFor`
- `tools/cmd/speccraft-guard/main.go` — `deps.proberForLang`, `deps.toolInput`,
  `var gatedWriteTools`, the capture path made blocking and normalized, both
  `redCand` read sites normalized, `OutcomeBuildFailed` → `buildRepairBranch`
- `tools/cmd/speccraft-state/buildrepair_log.go` (new) + `main.go` —
  `case "build-repair-log":`

**Tests (all new unless noted):** `state_buildrepair_test.go`,
`buildrepair_test.go`, `buildrepair_inject_test.go` (internal package, reuses
`atomicRename`), `buildrepair_policy_test.go` (internal package, reads the
compiled cap), `statekey_normalizer_test.go`, `state_single_writer_test.go`
(allowlist +3 field patterns), `redbaseline_test.go`, `buildprobe_test.go`,
`buildprobe_fallback_test.go`, `buildprobe_nomutation_test.go`,
`statekey_routing_test.go`, `writetools_test.go`, `buildrepair_log_test.go`.

**Docs / policy / harness:** `.speccraft/guardrails.md` (the carve-out sentence),
`.speccraft/conventions.md` (the spec-0018-AC13 entry and the now-fixed clobber
bullet), `commands/spec/close.md` (step 2's informational report),
`tests/hooks/close-gate.bats`.

**Incidental, not covered by any AC:** `.gitignore` gains `.DS_Store`. Named here
so the diff has no unexplained lines.

The spec itself moved `status: blocked` → `in-progress` and was stamped with
`started_at_sha` at the start of this session. It had been parked as `blocked`
during spec 0049 — whose implementation was blocked live by defect B, the bug this
spec fixes.

## Override accounting

**Stated budget: 1. Actually spent: 3.** All three are logged with reasons in
`tasks.md` §Bypasses. None was spent where the plan expected.

The plan budgeted its one override for T2, the from-scratch exported bootstrap.
That landed at **zero**, because T1's RED was written as raw-JSON round-trips
through `LoadState`/`SaveState` rather than as Go field assignments — so the
package kept compiling and the failure was a genuine runtime one. The
compile-stable-RED technique worked exactly as designed.

The three that were spent:

1. **T9** — the read-side normalization. The RED was verifiably failing at that
   moment, but **defect B reset the test file's candidates** after an edit that
   added no new `func Test…` line, and the guard refused the repair. Fourth
   occurrence in the session; the first three were routed around by adding
   genuinely useful tests, and a fourth invented test would have been padding.
2. **T9 again** — `siblingRedCheck` reads `redCand` in **two** places, and I
   normalized only one. Both should have been a single edit, since
   `ConsumeOverride` is per-EDIT. Spec 0049's lesson, applied one task late.
3. **T14** — self-inflicted: I wired the branch to call `buildRepairBranch`
   before writing it, breaking the build, so the guard forbade the edit that
   completes its own repair. **Defect A, experienced first-hand while fixing
   defect A.** The plan mandates stubs-before-callers (T13 exists only for that)
   and I followed it for T13 then broke it one step later.

Defect B fired **four times** while being fixed; defect A once. That is the
strongest evidence available that both were worth fixing.

## Corrections made during implementation

- **The probe is ONE command, not two.** Plan correction C1 established that
  `go build` alone is wrong — it does not compile `_test.go` files, so a
  build-only probe calls an overlay clean while a sibling test file is
  unbuildable. C1 therefore specified two commands. Implementing it surfaced the
  converse: `go build -o <dir> ./...` **fails with "no main packages to build" on
  a library-only module**, which would have reported every edit to such a module
  as still-broken and pushed it into repair mode — a false positive on the most
  ordinary case in this very repo. `go test -overlay -run '^$' ./...` alone
  compiles non-test *and* test files — verified directly: a compile error in a
  test-less package still fails the probe —
  runs nothing, and links into `GOCACHE` rather than the tree, so it needs no
  `-o` and cannot drop a binary into the author's repo. C1's intent is fully
  preserved; the command it added is the one that survived. **The spec text and
  plan §Design still describe the two-command form** — this is the residual
  discrepancy R1 flagged for folding in at close.
- **`ToolInput` is carried on `deps`**, not threaded through `siblingRedCheck`'s
  signature as plan §Step 14 specified. That signature has six call sites;
  changing it is only safe as one atomic edit, and any intermediate state leaves
  the package uncompilable — where the red-check returns `OutcomeBuildFailed` and
  the guard forbids the rest of its own change. It costs mixing request data into
  a dependency bag.
- **`buildRepairBranch` lives in `buildprobe.go`**, beside the probe, not inline
  in `main.go`. T14's and T16's predicates were retargeted to the real placement
  rather than the code bent to fit them.
- **The routing scan is split per package.** The plan had one test reaching into
  `cmd/speccraft-guard` from `internal/speccraft` by file path. Beyond being
  brittle, the TDD red-check is **package-scoped**, so a structural RED in one
  package cannot authorise an edit in another — discovered when the guard refused
  T11 with a perfectly good failing test sitting in the wrong package.
- **T16 needed no code change.** T15's seven boundary groups all passed against
  T14's branch as landed, so T16 is recorded as a PIN set rather than a fabricated
  RED→GREEN.
- **AC7's assertion was corrected.** An earlier version required `proberForLang`
  never to be *consulted*. That was wrong: it is shaped exactly like
  `runnerForLang`, where resolving and checking `ok` **is** the mechanism, and
  gating on language first would duplicate the "only Go" knowledge at the branch
  instead of keeping it in `productionDeps`. It now asserts no probe *runs*.
- **Two vacuous or misdirected predicates were fixed, not worked around.** T25's
  asserted the absence of `must not be relaxed` — a phrase that never appeared in
  `conventions.md`, so it could never fail. T15's record-failure test used
  ".speccraft as a regular file", which makes the prologue unable to resolve an
  active spec and **allow** the edit, so it would have passed for the wrong
  reason; it now makes `state.json.tmp` a directory, breaking only the save.

## Review

Three rounds, cross-model; six outputs, six distinct md5s — **no false quorum in
any round.** codex `changes-requested` ×3; claude-p `changes-requested` →
`approve` → `approve`. Recorded as `approve-with-comments` rather than plain
approve because codex never withdrew: its standing position is that a bounded,
logged bypass is still a bypass. That is answered by policy — §A.5 amends the
guardrail explicitly — rather than by mechanism, which is why `guardrails.md` was
edited in the same pass as the code.

Round 1's headline, reached independently by both reviewers: the draft's
"still broken → allow" branch was an **unbounded** bypass, and the draft's defence
(an unobservable signal is not really a bypass) did not survive contact —
unobservable-therefore-allow-everything is not a narrower rule, it is no rule.
That produced the bounded, self-closing, logged mode that shipped. Round 2 caught
that the bound was per-episode rather than per-session. Round 3 found a real logic
error in the poison-recovery text, which is why a failed capture now blocks.

**Three changes landed after round 3 and are therefore unreviewed** — capture
failure blocking the test-file edit, the `conventions.md` amendment, and AC18's
bidirectional pin. Each is a direct adoption of a reviewer proposal (T8/T24/T25).

## Verification

- `go test ./... -count=1` — 8/8 packages green; `go vet ./...` clean
- `bats tests/hooks/` — 333/333 green, with the freshly built `./bin` prefixed to
  `PATH` (spec 0049's rule: without it `speccraft-state` resolves to the cached
  1.11.0 plugin build in this devcontainer and two unrelated suites fail).
  `tasks-verify.bats` is excluded from T26.b's predicate and run separately — it
  invokes the verifier that is executing the predicate
- `speccraft-drift scan-all` — clean
- `GOOS=windows go build ./...` and `GOOS=darwin go build ./...` — both green,
  which is the evidence for the no-build-tag-split decision (`exec.CommandContext`
  + `WaitDelay` instead of unix-only `Setpgid`)

## Follow-ups

- **The spec text still describes the two-command probe** (§Design and AC1/AC2
  prose). Closed-spec immutability applies from here, so this is recorded rather
  than edited.
- A prober for Python/JS/TS. Only Go has one; the other languages keep the
  unmodified blocking behaviour, which is correct but leaves the wedge in place
  for them.
