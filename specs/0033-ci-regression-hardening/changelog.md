---
spec: "0033"
closed: 2026-07-25
---

# Changelog — 0033 Post-0030/0031 CI regression hardening

## What shipped vs spec

All five acceptance criteria shipped. This is a test/fixture/prompt-only spec:
every change is a Go test file or an e2e shell fixture — no product code, no
version bump, and (per plan) ZERO `/speccraft:spec:override`. Three CI failures
that surfaced after shipping specs 0030 (v1.7.0) and 0031 (v1.7.1) are fixed, and
a recurrence guard is added for the class that let one of them through.

- **Fix 1 — asymmetric symlink assertion (AC1).**
  `Test_ResolvePluginRoot_SymlinkedExe_ResolvesRealInstall` in
  `tools/internal/speccraft/pluginroot_test.go` built its expected root via
  `filepath.Abs(t.TempDir())` and compared `got != root`. On macOS `t.TempDir()`
  sits under `/var`, a symlink to `/private/var`; the resolver *correctly*
  `EvalSymlinks`-normalizes the executable path (spec 0030 AC4) to `/private/var/…`,
  so `got != want` and the test failed — on macOS only (Linux `/tmp` is not
  symlinked, so it passed). The code was right; the test's expected value was not
  normalized. Fixed by normalizing **only the expected** value:
  `want, err := filepath.EvalSymlinks(root)` (fail on err) and `got == want`, with
  `got` left untouched. The asymmetry is load-bearing: normalizing BOTH sides would
  let a resolver that *stopped* calling `EvalSymlinks` still pass, masking exactly
  the spec-0030 AC4 regression this test exists to catch. The through-symlink exe
  path (the exe is reached via a symlink in a separate tempdir) preserves that
  sensitivity — a skipped-`EvalSymlinks` resolver would ascend from the wrong
  directory and error. On Linux `EvalSymlinks(root) == root`, so the assertion is
  unchanged and stays green.

- **Fix 2 — `rust_integration_cycle.sh` Write payload (AC2).**
  `tests/e2e/rust_integration_cycle.sh` Step 2 sent a `{"tool_name":"Write"}`
  payload carrying the file content in `"new_string"` (with `"old_string":""`) —
  the *exact* Write mis-simulation spec 0031 fixed in `captureCase`, reproduced in a
  shell fixture. Spec 0031's `applyEdit` now correctly reads `content` for a Write;
  the fixture set no `content`, so post-edit content was empty → no just-added test
  → the guard did not reject → the leg failed ("expected rejection from shim-only
  path"). Fixed by replacing the `old_string`/`new_string` pair with
  `"content": "fn it_works() {}\n"` (the real Write shape, matching what the
  harness's `cat >` wrote to disk). `bash tests/e2e/rust_integration_cycle.sh` now
  reaches "OK".

- **Fix 3 — imperative `[cons 1/3]` decline prompt (AC4 behavioral half).**
  `tests/e2e/spec_consolidate.sh`'s `[cons 1/3]` decline leg prompt was not
  imperative, so the credit-gated model ran `/speccraft:sync`, produced a
  memory-audit report (P1–P4 proposals) plus a decline *description*, then stopped
  to ask for confirmation instead of writing
  `specs/0090-decline-source/consolidation-skip` — the propose-and-wait-vs-APPLY
  failure the spec-0029 convention warns about (the model conflated the
  approval-gated memory proposals with the mechanical decline action). Fixed with an
  imperative prompt that instructs the model to DECLINE by **writing** the marker,
  to NOT move the spec directory, to apply the decline immediately and **without
  asking for confirmation**, and to treat any `/speccraft:sync` memory-audit / drift
  proposals as a SEPARATE matter that must not block or gate the skip marker.

- **Recurrence guard + credit-free prompt oracle (AC3, AC4 credit-free half).** New
  Go test `tools/internal/speccraft/e2e_fixture_shape_test.go` (package
  `speccraft_test`), with an `e2eDir(t)` helper that walks up from the test's CWD to
  the nearest ancestor containing `tests/e2e` (mirrors the ascend idiom in
  `pluginroot.go`):
  - `Test_E2EFixtures_NoWritePayloadUsesNewString` scans every `tests/e2e/*.sh`,
    segments each file on the literal `"tool_name"`, and for any segment whose
    tool-name is `Write` asserts that one envelope's fields contain no `new_string`.
    The invariant is unconditional (a Write's content lives in `content`, never
    `new_string`) and the association is per-envelope, not a repo-wide proximity
    grep. This generalizes spec 0031's Go-ONLY AC5 static guard to shell fixtures —
    the exact gap that let Fix 2 slip past 0031. It failed on the pre-fix
    `rust_integration_cycle.sh` and is green post-Fix-2.
  - `Test_ConsolidateDeclineLeg_ImperativePrompt` reads the LIVE `[cons 1/3]`
    decline prompt (anchored on `cons-01-decline.log`) and asserts it pins the three
    terminal actions — write the `consolidation-skip` marker, do NOT move the
    directory, act WITHOUT asking — via tolerant regexes. This is a credit-free
    meta-test that makes the wording requirement deterministic without a model run;
    the credit-gated marker-exists/dir-unmoved post-condition remains the behavioral
    backstop.

- **Containment (AC5).** Exactly four files changed — `pluginroot_test.go`,
  `rust_integration_cycle.sh`, `spec_consolidate.sh`, and the new
  `e2e_fixture_shape_test.go` — plus `.speccraft/index.md`'s active-spec pointer. No
  `.go` product source (guard/state/drift), command doc, hook, template, or
  manifest changed, and no `const version` bump. `go test ./...` and the
  `tests/hooks/*.bats` suite stay green.

## Deviations

- **No version bump.** Stated positively: nothing shipped in a plugin binary,
  manifest, command doc, hook, or user-facing command/agent prompt — only a Go
  test, two e2e shell fixtures, and one new Go test. The changed `[cons 1/3]`
  string is **test-driver input** inside `tests/e2e/`, not a user-facing prompt. The
  §Version bumps convention triggers on shipped behavior/API changes; none occur
  here, so no `const version` bump.

- **ZERO overrides — no product code touched.** All changes are test files or e2e
  shell fixtures, none of which `speccraft-guard` gates, so no
  `/speccraft:spec:override` was needed anywhere (the plan predicted zero and hit
  zero). The RED→GREEN sequencing was still real: the new guard test and the
  credit-free prompt meta-test FAIL against the pre-fix fixtures and the fixture/
  prompt edits make them pass — the guard test literally drove the Fix-2 edit.

- **AC1 is not reproducible on the Linux dev host.** The macOS failure cannot be
  reproduced locally (Linux `/tmp` is not symlinked). The local oracle was Linux
  `go test` staying green plus the assertion being provably macOS-correct by
  construction (asymmetric, `want = EvalSymlinks(root)`, sensitivity preserved by
  the through-symlink exe path). Real confirmation is the next macOS CI unit run.

- **Fix 3 is NOT a 0030/0031 regression.** It is a pre-existing flake in the
  historically-flaky 0025→0027→0028→0029 consolidation lineage, bundled here solely
  because it blocks the same required e2e lifecycle gate as Fixes 1 and 2. It is an
  independent CI-unblock / consolidation-fixture stabilization item, not caused by
  0030/0031.

- **ID allocation.** 0032 remains RESERVED by spec 0031 (for MultiEdit/NotebookEdit
  payload modeling). This spec intentionally SKIPS it and takes 0033, and does NOT
  itself reserve 0032 (a reservation cannot name an ID lower than the reserving
  spec's own). 0033's own close ran no consolidation.

## Files touched

- `tools/internal/speccraft/pluginroot_test.go` (asymmetric assertion — AC1)
- `tools/internal/speccraft/e2e_fixture_shape_test.go` (NEW — recurrence guard +
  credit-free prompt oracle — AC3, AC4)
- `tests/e2e/rust_integration_cycle.sh` (Write payload → `content` — AC2)
- `tests/e2e/spec_consolidate.sh` (`[cons 1/3]` imperative decline prompt — AC4)
- `.speccraft/index.md` (active-spec pointer)

## ADR proposed for history.md

See the HISTORY-ADR proposal below (dated 2026-07-25, top of `.speccraft/history.md`).

## Conventions proposed

Two additions, both under §Go / §Bash → E2E in `.speccraft/conventions.md`:

- **New:** "When a test pins a normalization the product performs (EvalSymlinks,
  path cleaning, …), normalize only the EXPECTED value — never the actual —
  because normalizing both sides masks a regression where the product stops
  normalizing."
  Rationale: emerged from AC1's macOS symlink fix; symmetric normalization would
  have silently defeated spec 0030 AC4's regression check.

- **New (generalization of spec 0031's AC5):** "A Write payload in ANY e2e fixture
  — Go or `tests/e2e/*.sh` — must carry its content in `content`, never
  `new_string`; pinned by the per-envelope Go scanner
  `Test_E2EFixtures_NoWritePayloadUsesNewString`." Plus a short note that a
  credit-gated e2e leg's imperative wording can be pinned credit-free by a meta-test
  that reads the LIVE prompt (complements spec 0029's APPLY-not-propose convention).
  Rationale: spec 0031's static Write-shape guard scanned only Go fixtures, so a
  shell fixture with the same bug (Fix 2) slipped through.
