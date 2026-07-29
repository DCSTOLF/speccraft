---
spec: "0033"
status: planned
strategy: tdd
---

# Plan — 0033 Post-0030/0031 CI regression hardening

All changes are to TEST files and e2e SHELL fixtures — no product code — so
NOTHING is TDD-gated and NO `/speccraft:spec:override` is needed anywhere. The
RED→GREEN sequencing is still real: the new recurrence-guard Go test and the
credit-free prompt meta-test (T1) FAIL against the current fixtures on `main`,
and the fixture/prompt fixes (T2/T3) make them pass — the guard test literally
drives the (2) fixture fix.

## RED preconditions confirmed at plan time (on `main`)

- `tools/internal/speccraft/pluginroot_test.go` `Test_ResolvePluginRoot_SymlinkedExe_ResolvesRealInstall`
  compares `got` to `root` (= `filepath.Abs(t.TempDir())`); it already exercises
  `EvalSymlinks` (the exe is passed through a symlink `link → realExe` in a
  SEPARATE tempdir, so a resolver that skipped `EvalSymlinks` would ascend from
  the wrong dir and ERROR — strong sensitivity). It fails only where `t.TempDir()`
  itself is under a symlink (macOS `/var`→`/private/var`).
- `tests/e2e/rust_integration_cycle.sh` Step 2 sends
  `{"tool_name":"Write","tool_input":{"file_path":…,"old_string":"","new_string":"fn it_works() {}\n"}}`
  — a Write payload carrying content in `new_string`. Post spec 0031 `applyEdit`
  reads `content` (absent → empty) → no just-added test → no rejection → the leg
  fails "expected rejection from shim-only path".
- `tests/e2e/spec_consolidate.sh` `[cons 1/3]` decline prompt does not imperatively
  instruct the model to WRITE the `0090` `consolidation-skip` marker without
  asking, so a credit-gated run can propose-and-wait.
- No existing Go test scans `tests/e2e/*.sh` for the Write-payload shape (the gap
  that let (2) through spec 0031's Go-only AC5 guard).

## Test-first sequence

### Phase 1 — recurrence guard + prompt meta-test (RED)

#### Step 1 — new Go test `e2e_fixture_shape_test.go` (RED) — AC3, AC4(credit-free)
- Add `tools/internal/speccraft/e2e_fixture_shape_test.go` (package
  `speccraft_test`). A `repoRoot(t)` helper walks up from the test's CWD
  (`tools/internal/speccraft`) to the nearest ancestor containing a `tests/e2e`
  directory (mirrors the ascend idiom in `pluginroot.go`), so the test is
  location-robust and reads the real fixtures.
  - `Test_E2EFixtures_NoWritePayloadUsesNewString` (AC3) — for each
    `tests/e2e/*.sh`, split the file content on the literal `"tool_name"`; for
    every segment whose tool-name value is `Write` (matches `"tool_name"\s*:\s*"Write"`),
    assert the segment (up to the next `"tool_name"` or end of file — i.e. that
    one envelope's fields) contains NO `new_string`. The invariant is
    unconditional: a `Write` `tool_input` must never carry `new_string` (a Write's
    content lives in `content`). Fails on `rust_integration_cycle.sh` today.
  - `Test_ConsolidateDeclineLeg_ImperativePrompt` (AC4 credit-free) — read
    `tests/e2e/spec_consolidate.sh`, locate the `[cons 1/3]` decline `run_claude`
    prompt string, and assert it pins the three terminal actions:
    (i) writes/creates the `consolidation-skip` marker for `0090`,
    (ii) does NOT move the directory, (iii) does the action WITHOUT asking for
    confirmation. Use tolerant substring/regex matches (`consolidation-skip`;
    `not move`|`do NOT move`|`leave .* in place`; `without asking`|`do not ask`|
    `without confirmation`). Fails against the current prompt today.
- Both tests COMPILE and FAIL (they only read files) → valid RED, no gating.

### Phase 2 — fixture + prompt fixes (GREEN)

#### Step 2 — correct the rust integration Write payload (GREEN → AC2, AC3) — AC2, AC3
- Edit `tests/e2e/rust_integration_cycle.sh` Step-2 `EDIT_INPUT`: replace the
  `"old_string":""` + `"new_string":"fn it_works() {}\n"` pair with
  `"content":"fn it_works() {}\n"` (the real Write shape, matching what the
  harness's `cat >` wrote to disk). Keep `tool_name:"Write"`, `file_path`, `cwd`.
- Result: `applyEdit` (Write→Content) models the added integration test → the
  shim-only path yields "no failing test observed" → the leg reaches "OK".
  `Test_E2EFixtures_NoWritePayloadUsesNewString` (Step 1a) goes GREEN.
- Verify by RUNNING it: `bash tests/e2e/rust_integration_cycle.sh` → "OK:
  rust_integration_cycle e2e passed" (AC2).

#### Step 3 — make the decline leg imperative (GREEN → AC4) — AC4
- Edit the `[cons 1/3]` decline `run_claude` prompt in
  `tests/e2e/spec_consolidate.sh` to be imperative: instruct the model to DECLINE
  spec 0090's consolidation by **writing** `specs/0090-decline-source/consolidation-skip`
  (do NOT move the directory), to do so IMMEDIATELY and **without asking for
  confirmation**, and to keep any `/speccraft:sync` memory-audit proposals
  SEPARATE from (and not gating) this mechanical decline. Preserve the leg's
  corpus/seed setup and post-conditions unchanged.
- `Test_ConsolidateDeclineLeg_ImperativePrompt` (Step 1b) goes GREEN. (The
  credit-gated post-condition — marker exists on 0090, dir unmoved — is unchanged
  and re-verified only on a full credit-gated e2e run.)

### Phase 3 — macOS symlink test correctness (GREEN)

#### Step 4 — asymmetric assertion in the symlink test (fix) — AC1
- Edit `Test_ResolvePluginRoot_SymlinkedExe_ResolvesRealInstall` in
  `tools/internal/speccraft/pluginroot_test.go`: compute
  `want, err := filepath.EvalSymlinks(root)` (fail the test on err) and assert
  `got == want`. Do NOT normalize `got`. On Linux `EvalSymlinks(root) == root`
  (no symlink) so the assertion is unchanged and stays green; on macOS `want`
  becomes `/private/var/…` and matches the resolver's `EvalSymlinks`-resolved
  `got`. Sensitivity is preserved: the exe is still reached through a symlink in a
  separate tempdir, so a resolver that skipped `EvalSymlinks` would ascend from
  the wrong directory and ERROR (not silently pass).
- This is a test-file edit (ungated). RED = the reported macOS CI failure (not
  reproducible on the Linux dev host); GREEN oracle here = Linux `go test`
  stays green AND the assertion is provably macOS-correct by construction.

### Step 5 — Final VERIFY (all green together)
- `go test ./...` in `tools/` green: the two new Step-1 tests now pass, the fixed
  symlink test passes, nothing else regresses.
- `bash tests/e2e/rust_integration_cycle.sh` → "OK" (AC2); `bash
  tests/e2e/rust_inline_cycle.sh` still "OK" (no collateral).
- `bats tests/hooks/*.bats` → 0 failures (AC5 containment).
- Diff review: only `pluginroot_test.go`, `e2e_fixture_shape_test.go` (new),
  `rust_integration_cycle.sh`, and `spec_consolidate.sh` changed — no `.go`
  product source, command doc, hook, template, or manifest, and NO `const version`
  bump (AC5 + the no-version-bump decision).

## Delegation

- All steps → in-thread. Pure test/fixture/prompt edits, tight loop, no product
  code and no gating; the Go guard test drives the fixture fix directly.

## Risk

- **AC3 scanner false positives** (a Write envelope followed by an unrelated Edit
  envelope with `new_string`) → mitigation: associate fields within ONE envelope
  by segmenting on `"tool_name"` and scanning only up to the next `"tool_name"`;
  the invariant checked is per-segment, not repo-wide proximity.
- **AC4 meta-test brittleness** (over-fitting exact prompt words) → mitigation:
  tolerant alternation matches on the three semantic actions, not a verbatim
  string; the credit-gated post-condition remains the behavioral backstop.
- **AC1 not reproducible on the Linux dev host** → mitigation: the fix is a
  provably-correct assertion change (asymmetric, `EvalSymlinks(root)` for `want`)
  that keeps Linux green and cannot mask a skipped-`EvalSymlinks` regression (the
  through-symlink exe path preserves sensitivity); confirmed against the macOS
  failure signature in the CI log.
- **Scope creep into the flaky consolidation lineage** → mitigation: (3) is a
  single imperative-prompt edit + a credit-free wording meta-test; no
  re-architecture of `/speccraft:sync` or the consolidation e2e (explicit
  out-of-scope).

## AC → step coverage

| AC | Step(s) |
| --- | --- |
| AC1 (asymmetric symlink assertion; Linux-green, macOS-correct, sensitivity preserved) | 4 |
| AC2 (`rust_integration_cycle.sh` reaches OK via `content`) | 2 |
| AC3 (Go recurrence guard: no Write payload uses `new_string`, per-envelope) | 1 (RED), 2 (GREEN) |
| AC4 (imperative `[cons 1/3]` prompt + credit-free meta-test) | 1 (RED), 3 (GREEN) |
| AC5 (containment: only the 4 files; go test + bats green; no version bump) | 5 |
