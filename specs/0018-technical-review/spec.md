---
id: "0018"
title: "technical-review"
status: closed
created: 2026-06-12
authors: [claude]
packages: [tools/cmd/speccraft-guard, tools/internal/speccraft, tools/internal/speccraft/runner]
related-specs: ["0005", "0002", "0010"]
supersedes-note: "Retires the spec-0005 architecture.md non-goal 'retroactive adoption by Go/Python is a non-goal of spec 0005' — see Why and AC11."
---

# Spec 0018 — technical-review

## Why

The technical review (`speccraft-technical-review.md`, finding **P0-1**) shows that
the marketed "TDD red→green invariant" is enforced as a true red→green check **only
for Rust**. For Go, Python, and JS/TS the guard never runs a test and never observes a
failure — it only checks that *a* sibling test file was *touched this session*
(`hasSiblingTestEdited`, `tools/cmd/speccraft-guard/main.go:390`; the JS/TS
session-membership check, `main.go:446-452`). Concretely: adding a blank line to any
matching `foo_test.go` marks the directory as test-touched and unlocks every
production `.go` file in it, with no test having ever failed or even run. Only the Rust
path invokes a runner and requires an observed failure (`main.go:199-246`, via the
spec-0005 `runner.Runner` adapter).

This is the project's highest-impact correctness gap: speccraft sells one guarantee and
enforces it for one of four supported languages. The decided direction (over the
honest-rename alternative) is to **close the gap by making Go/Python/JS/TS perform a
real red-check** — run the relevant sibling test(s) and require an observed failure in a
test the current session added/modified, before unlocking production edits — bringing all
four languages to red→green parity with Rust.

This spec **deliberately reverses a documented non-goal.** `.speccraft/architecture.md`
(layer 8 and §Key decisions) currently states the runner primitive was *"Validated
against Rust only — retroactive adoption by Go/Python is a non-goal of spec 0005."* Spec
0018 retires that limitation: the runner primitive is extended beyond Rust to Go, Python,
and JS/TS. Updating that memory surface is part of this spec (AC11), so project memory
does not contradict shipped reality.

## What

Extend the speccraft-guard so that production-file edits in Go, Python, and JS/TS are
gated by an **observed failing test**, mirroring the Rust flow's contract: a test the
session just added/modified is executed; the edit is allowed only when at least one such
targeted test is observed to *fail*; build/collection errors and runner-absence are
**not** a valid red state and **never** fall back to the old touch-check.

In scope:

- A language-neutral red-check path for Go/Python/JS/TS that reuses the existing
  `runner.Runner` interface, `Outcome` taxonomy (`OutcomeBuildFailed` /
  `OutcomeAllPassed` / `OutcomeAtLeastOneFailed`), and the dependency-injection seam
  (`deps{exec, runnerFor, stderr}`) already established by spec 0005 for Rust, so the
  new behavior is unit-testable without invoking a real toolchain.
- Per-language adapters that invoke the conventional runner and parse pass/fail:
  - Go → `go test` (targeted at the sibling test file/package).
  - Python → `pytest` (targeted at the sibling test file/node).
  - JS/TS → the project's configured test runner (e.g. `vitest`/`jest`), targeted at the
    candidate sibling test file. JavaScript and TypeScript share **one** adapter and one
    resolution path (the existing `jsTsDispatch` candidate-path set); the separate
    `[tdd.javascript]` / `[tdd.typescript]` config keys below select the command, not a
    second adapter.
  Per the runner-primitive adapter contract (conventions.md §"Runner-primitive adapter
  contract"), **all** argv construction, output parsing, and outcome classification live
  **inside the adapter** in `tools/internal/speccraft/runner/`. No language-specific
  runner logic is added to `tools/cmd/speccraft-guard`; the dispatcher only routes and
  consumes the normalized `Result`.
- A "which test(s) to run" rule per language — see **Decisions §D1** (just-added model,
  mirroring Rust). The session's just-added/modified test functions in the edited sibling
  test file(s) are the target set; the resolution of *which file is the sibling* reuses
  the existing `SiblingTestFiles` (Go/Python) and `jsTsDispatch` candidate-path logic.
- Honest, actionable block/allow messaging that distinguishes three blocking states:
  "no failing test observed" (RED missing), "build/collection failed" (not a valid red
  state), and "no test runner available" (cannot verify RED) — consistent in tone with
  the Rust messages at `main.go:236` and `main.go:240-245`.
- Per-language runner configuration via `speccraft.toml`, mirroring `cfg.TDD.Rust.Runner`.
  Sketch (final shape settled in planning):
  ```toml
  [tdd.go]         # runner = "go test"   (default)
  [tdd.python]     # runner = "pytest"    (default)
  [tdd.javascript] # runner = "<cmd>"     (no safe default — see Open questions §OQ-A)
  [tdd.typescript] # runner = "<cmd>"
  ```
  Override semantics match Rust: an explicit value opts in; defaults apply otherwise.
- Documentation updates so the §4 enforcement matrix in `speccraft-technical-review.md`,
  `.speccraft/guardrails.md`, `.speccraft/index.md`, **and** `.speccraft/architecture.md`
  describe red→green parity across all four languages and retire the spec-0005 Rust-only
  non-goal (AC11).

## Decisions (resolved during review)

- **D1 — Test-selector granularity = just-added model (mirrors Rust's *accept* branch,
  with one deliberate divergence).** The guard runs the sibling test(s) and requires the
  observed failure to be in a test **the current session added or modified** in the
  sibling test file(s) — not merely *any* failing test in the file. This matches the
  shape of what Rust does today (`computeJustAddedForEdit` → run the runner per just-added
  FQTN → accept on a failed *just-added* record, `main.go:199-246`), and it closes the
  "a pre-existing, unrelated failing test in the file unlocks edits" hole a whole-file
  selector would reopen. Consequently, per-language extraction of test-function
  identifiers (the analog of `CanonicalIDsForFile` / `DiscoverRustTests`) is **in scope**.
  Whole-suite execution remains out of scope.
  - **Deliberate divergence on the empty just-added set.** Rust's cited range includes
    `if len(justAdded) == 0 { return nil }` — it **allows** a production edit when nothing
    new was added (a green/refactor edit), because Rust is backed by a persisted
    `rust_test_baseline` that already attests a prior RED. Go/Python/JS-TS have **no such
    baseline**, so for these languages an empty just-added set **blocks** (not allows) —
    otherwise a blank-line-only test touch would reopen P0-1 (this is exactly AC2 / AC10).
    An implementer must **not** copy Rust's allow-on-empty branch. This is the one place
    the new languages intentionally diverge from the Rust reference.
- **D2 — Runner-absent / unresolvable = fail-closed.** When the configured or conventional
  runner for an in-scope language cannot be resolved or invoked, the guard **blocks** the
  production edit with a "no test runner available — configure one or use
  `/speccraft:spec:override`" message. It **never** falls back to the legacy touch-check. Falling
  back would reopen the exact P0-1 bypass (arrange an absent runner → a touched-but-unrun
  test unlocks edits), which would violate the TDD-invariant guardrail. `/speccraft:spec:override`
  remains the one sanctioned escape hatch.

## Acceptance criteria

1. **Go — green sibling blocks.** For a Go production-file edit where the active spec is
   `in-progress` and the resolved sibling test, when run, returns `OutcomeAllPassed`, the
   guard **blocks** with a "no failing test observed" message. (Driven through
   `processToolUse` with an injected fake runner.)
2. **Go — no targeted test blocks.** For the same Go edit where no test was added/modified
   by the session in the sibling file (no just-added target to run), the guard **blocks**
   with a "no failing test observed / add a failing test first" message — a distinct path
   from AC1 (runner is not invoked), observable through the `deps{}` seam.
3. **Go — failing just-added test allows.** For the same Go edit where the runner reports
   `OutcomeAtLeastOneFailed` with a failed record **whose test identifier is in the
   session's just-added set**, the guard **allows** the edit (parity with the Rust accept
   branch). A failure outside the just-added set does not satisfy this AC — see AC7.
4. **Python parity.** A Python production-file edit exhibits AC1/AC2/AC3 behavior via the
   Python adapter: `OutcomeAllPassed` → block, no just-added target → block,
   `OutcomeAtLeastOneFailed` on a just-added test → allow.
5. **JS/TS parity.** A JS/TS production-file edit exhibits AC1/AC2/AC3 behavior via the
   JS/TS adapter.
6. **Build/collection failure is not RED.** When the targeted runner reports
   `OutcomeBuildFailed`, the guard **blocks** with a message that distinguishes a build/
   collection failure from a missing RED test, for all three languages.
7. **Pre-existing unrelated failure does not unlock (D1 enforcement).** When the runner
   reports a failed record whose test identifier is **not** in the session's just-added
   set, the guard **blocks** — a pre-existing failing test elsewhere in the sibling file
   does not by itself satisfy the invariant. (Observable via a fake runner returning a
   failed record outside the just-added set.)
8. **Runner-absent is fail-closed (D2).** When the runner for an in-scope language cannot
   be resolved/invoked, the guard **blocks** with a "no test runner available" message and
   does **not** fall back to the touch-check. (Fake/stub runner-resolution returning
   "unavailable"; regression mirroring AC10.)
9. **Hang/timeout is not an allow.** The real adapter invocation must be bounded by a
   `context.WithTimeout(d)` (today the runner is called with `context.Background()`,
   `gate.go:50` — an unbounded `go test`/`pytest`/`node` hang would wedge the hook). A
   deadline overrun surfaces as a Go `error` from `adapter.Run` (which already blocks),
   **not** as a new `Outcome` enum value — the `Outcome` taxonomy does not grow. The guard
   **blocks** (non-RED) on timeout or runner error, never allows. The default duration `d`
   is settled during planning. (Observable via a fake runner returning a timeout/error.)
10. **Blank-line bypass closed, per language.** A blank-line-only edit to a sibling test
    file no longer suffices on its own to unlock a production edit — asserted separately
    for Go, Python, and JS/TS (the three bypasses live in different code paths:
    `main.go:390` vs `main.go:446-452`), with the runner reporting `OutcomeAllPassed`.
    This is the direct regression test for the P0-1 finding.
11. **Docs/memory reflect parity.** The §4 enforcement matrix in
    `speccraft-technical-review.md`, the `.speccraft/index.md` invariant description, and
    `.speccraft/architecture.md` are updated to state red→green enforcement for all four
    languages, with no surviving wording that describes Go/Python/JS/TS as a touch-only
    check. The two architecture.md non-goal sites are scrubbed by name — the layer-8 line
    (*"retroactive adoption by Go/Python is a non-goal of spec 0005"*) and the §Key
    decisions line (*"Runner adoption by Go/Python is a non-goal"*) — so neither survives.
    `.speccraft/guardrails.md` is verified to carry no per-language touch-only wording
    (its invariant text is already generic) — it is a no-regression check, not an edit
    site, unless a stale claim is found there at implementation time.
12. **Testability seam.** The new red-check is exercised entirely through the `deps{}`
    injection seam in unit tests — `go test ./...` passes and the Go/Python/JS/TS guard
    paths have direct test coverage that does not shell out to a real `go`/`pytest`/`node`
    toolchain.
13. **New-symbol introduction is the one override case (added by the 2026-06-12
    amendment).** Introducing a brand-new production symbol whose just-added test cannot
    compile until that symbol exists is the single workflow the pre-edit red-check cannot
    observe as a runtime RED (the pre-edit run is a build failure, which AC6 correctly
    refuses to treat as RED). The sanctioned path is a one-shot `/speccraft:spec:override`
    for the symbol-introduction edit — identical to the Rust red-check's behavior today.
    Oracle: `tests/e2e/run.sh` step 9 drives test-edit → `/speccraft:spec:override` →
    production edit and asserts the production edit lands. This is a documented limitation,
    not a fail-open: the guard still blocks by default and only the explicit, logged
    override unlocks the edit.

## Out of scope

- The other technical-review findings (P0-2 fail-open on corrupt state, P1-1
  MultiEdit/NotebookEdit parsing, P1-2 e2e-on-PR, quorum/verdict, CI static analysis,
  and all P2 cleanups). Each is tracked separately; this spec closes **P0-1 only**.
- Rust behavior changes — the Rust red-check is the reference implementation and stays
  as-is; this spec brings the other languages up to its contract, it does not modify it.
- The honest-rename alternative from the review (renaming the invariant to a
  "test-touch discipline"). The decided direction is the real red-check, so the
  red→green name is *kept* and made true.
- Whole-suite execution and multi-package / monorepo test targeting nuances beyond
  single-package sibling resolution (Rust workspace support remains reserved under spec
  0006; the analogous multi-package story for the other languages is deferred).
- Performance optimization of the interactive red-check (e.g. a fingerprint cache like
  Rust's `RunPreEditGate`) beyond a basic "running red-check…" breadcrumb and the
  deadline/timeout boundary specced in AC9. Latency hardening is a follow-up.

## Open questions

- **OQ-A — JS/TS runner detection (deferrable to planning).** How is the JS/TS test
  command resolved when not explicitly set in `speccraft.toml` — config-only (no
  inference), or inference from `package.json` `scripts.test` / presence of
  `vitest`/`jest`? This is a config-surface/UX choice that does **not** affect the
  invariant: under D2, an unresolved JS/TS runner fails closed (AC8) regardless of which
  detection strategy is chosen. Settled during planning as **config-only** (see plan.md
  §Planner-settled open questions).

## Amendment (2026-06-12) — new-symbol introduction requires a one-shot override

**Trigger.** Implementation surfaced that the pre-edit red-check deadlocks the canonical
"introduce a brand-new function via TDD" flow for compiled/loaded languages: the
just-added test references a symbol that does not exist until the production edit lands,
so the pre-edit run is a **build/collection failure**, which AC6 (correctly) refuses to
treat as a valid RED. The production edit that would make the test compile is the very
edit being gated. This is **identical to the Rust red-check's behavior today** — the
pre-0018 touch-check merely hid it for Go/Python/JS-TS. It is invisible to the `deps{}`
unit tests and the stub-runner language fixtures; it only manifests where a real toolchain
runs against a new symbol (the credit-gated `tests/e2e/run.sh` step 9, new `farewell()`).

**Resolution (chosen over relaxing AC6 or an apply-edit-in-memory redesign).** Keep AC6 as
reviewed. Treat new-symbol introduction as the one sanctioned `/speccraft:spec:override`
case and **document it** (new AC13). The lifecycle e2e step 9 now runs test-edit →
`/speccraft:spec:override` → production edit. The override is the existing, logged escape
hatch; the guard still blocks by default, so this is not a fail-open.

**Why fold in rather than spin off (mid-implementation amendment convention).** Strictly
bounded (no production-code change — docs + one e2e step + AC13); the lifecycle close gate
(`e2e-devcontainer`) stays red until step 9 reflects the new model; squarely on-theme
(it is the direct consequence of this spec's own red-check). Also corrected in this
amendment: the guard's override-prompt strings and this spec's D2 wording now use the
fully-qualified `/speccraft:spec:override` (the short `/spec:override` form was inaccurate).

**Deferred follow-up.** An apply-edit-in-memory red-check (run against the post-edit
package so a new symbol's test compiles and fails at runtime, eliminating the override
step) is a larger design with its own ACs and latency profile, and would also diverge from
Rust's pre-edit model. It is explicitly out of scope here and a candidate follow-up spec.
