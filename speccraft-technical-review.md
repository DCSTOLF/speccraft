# speccraft — Technical Improvement Report

_Reviewer: staff-level engineering review · Date: 2026-06-11 · Commit: `4529323` (main)_

Scope: architecture, abstractions, command flow, TDD enforcement, guardrails, state
management, CI/validation, maintainability, and developer experience. Read-only review —
no production code changed, no commits. Findings are evidence-backed with `file:line`
references. Tests were run (`go test ./...`, `go vet ./...`) but no lab experiments.

---

## 1. Executive summary

### Overall assessment

speccraft is a genuinely well-engineered plugin. The architecture is clean and the team
clearly practices what the tool preaches: small single-purpose Go binaries behind a thin
bash hook layer, a disciplined single-writer state model, dependency-injection seams for
testing (`tools/cmd/speccraft-guard/main.go:35-39`), an atomic temp-file state writer
(`state.go:95-101`), and a dogfooded spec history with changelogs and ADRs. Test coverage
of the Go core is good and the suite is green locally (`go test ./...` → all `ok`; `go vet`
clean).

But there is a **central gap between the product's promise and its enforcement**: speccraft
markets a "TDD red→green invariant," and that is literally true **only for Rust**. For Go,
Python, and JS/TS the guard verifies nothing about red or green — it only checks that *a*
sibling test file was *touched this session* (`main.go:390`, `main.go:446-452`). A one-character
edit to an unrelated test satisfies the invariant. This is the highest-impact finding and it
undercuts the core value proposition for the majority of speccraft's supported languages.

### Main risks

1. **TDD invariant is a touch-check, not a red→green check, for Go/Python/JS/TS** (P0). The
   guard never runs the test, never observes failure. Trivially satisfiable.
2. **Guard fails open on a corrupt/unreadable `state.json`** (P0). `prodGuardPrologue`
   returns `(prologueBlock, nil)`; the caller returns the `nil` error, so the edit is
   *allowed* — enforcement silently disappears exactly when state is broken
   (`main.go:347-351`, `main.go:377-383`).
3. **`MultiEdit`/`NotebookEdit` are gated but not parsed** (P1). The guard's `ToolInput`
   models only `file_path`/`old_string`/`new_string` (`main.go:26-30`); `MultiEdit` nests
   its edits under `edits[]` and `NotebookEdit` uses `notebook_path`. Verified: no `edits`
   or `notebook_path` handling exists anywhere (`grep` across `hooks/`+`tools/`).
4. **The full claude-driven e2e never runs on PRs** (P1) — only post-merge on `main`
   (`ci.yml:83`), so a PR can be fully green while the actual command lifecycle is broken.
5. **No static analysis in CI** (P1) — no shellcheck on the critical bash hooks, no `gofmt`,
   no `go vet`, no linter (verified: `grep` over `.github/workflows/` → none).

### Highest-impact improvement opportunities

- Make the Go/Python/JS/TS guard actually observe a failing test (or be honest that it is a
  "test-adjacent-edit" discipline, not red→green). This is the single biggest correctness win.
- Decide fail-open vs fail-closed deliberately and *log* when the guard no-ops, so silent
  non-enforcement is observable.
- Parse `MultiEdit`/`NotebookEdit` payloads or drop them from the matcher; fix the bats tests
  that give false confidence by sending synthetic `file_path` keys real tools never emit.
- Run the claude-driven e2e on PRs (or a cheaper smoke variant) so the lifecycle is gated
  before merge.

---

## 2. Architecture review

### What is well designed

- **Surface separation is crisp.** Hooks gate tool calls, commands drive workflow, subagents
  do model work, Go binaries own deterministic logic. The "one paragraph" architecture in
  `.speccraft/index.md` is accurate to the code.
- **Single-writer state model.** `state.json` is mutated only through `speccraft-state`,
  enforced on three axes: a source-level grep test
  (`state_single_writer_test.go`), a runtime bash guard (`pre-tool-use.sh:25-63`), and prose
  policy in `commands/spec/close.md:47-54`. This is unusually disciplined and the rationale
  is documented inline.
- **Atomic writes + a single mutex.** `saveStateLocked` writes to `path + ".tmp"` then
  `os.Rename` (`state.go:95-101`); all mutations take `mu` (`state.go:54`). Crash-safe and
  race-safe within a process.
- **Test seams.** `deps{exec, runnerFor, stderr}` (`main.go:35-39`) lets the Rust red-check
  be unit-tested without a real cargo toolchain — `speccraft-guard` has the largest test file
  in the repo (`main_test.go`, 878 lines).
- **Language dispatch is extensible by design.** `dispatchByLanguage` (`main.go:130-145`) is a
  clean switch; "adding a language = one case + one handler."

### What could be simplified

- **The Rust subsystem dominates the codebase.** Roughly half the Go (`rust_*.go`, `rusttok/`,
  `runner/`) serves one language, and it's the *only* language that gets a real red-check.
  This is a large maintenance surface for a single language and creates a stark capability
  asymmetry (see §4). Either generalize the red-check mechanism to other languages or
  consciously scope Rust as the "reference implementation" and document the asymmetry.
- **Two TOML parsers coexist.** `config.go:90-112` hand-rolls a line-oriented TOML reader for
  `speccraft.toml`, while `tools/internal/delegate/toml.go` uses `BurntSushi/toml` for
  `agents.toml`. The hand-rolled parser silently mishandles multi-line arrays, inline tables,
  and comments-after-values. Since the dependency is already vendored, use it for both.
- **`splitLines` is duplicated** verbatim in `state.go:367-380` and `main.go:506-518`. Minor,
  but it's exactly the kind of drift the project's own conventions warn about.

### Coupling / layering issues

- **The bash hook re-implements path logic that belongs in Go.** `pre-tool-use.sh:40-62`
  does jq extraction + `realpath -m` canonicalization for the state.json guard, duplicating
  responsibility that `speccraft-guard` could own in one place. The file's own comment
  (`pre-tool-use.sh:12-14`) acknowledges this. The split also means the single-writer guard
  and the TDD guard have *different* tool-payload assumptions (the bash side reads `file_path`
  for all four tools; the Go side bails when `file_path` is empty), which is the root of the
  `NotebookEdit` gap.
- **Status gate reads frontmatter with a bespoke parser** (`main.go:480-504`) that only
  matches `field: value` with a single space and treats a *missing* `status` as pass
  (`main.go:362`: `status != "in-progress" && status != ""`). A spec with no `status` line, or
  `status:value` (no space), or `status:  value` (two spaces) silently passes the gate.

---

## 3. Spec-driven workflow review

### Strengths

- The lifecycle is complete and legible: `new → review → revise → plan → implement → close`,
  each a discrete command with frontmatter-scoped `allowed-tools`. The status state machine
  (`draft → reviewed → planned → in-progress → closed`) is real and gated.
- **Traceability is excellent.** Every closed spec has `spec.md`, `plan.md`, `tasks.md`,
  `review.md`, and `changelog.md`; ADRs land in `history.md`. This is better spec hygiene than
  most production teams maintain.
- `spec:revise` is thoughtfully built: a snapshot + `frontmatter_integrity_check` restores
  command-owned keys (`revision`/`status`/`id`/`created`) if the subagent touches them
  (`commands/spec/revise.md`), with the logic extracted to a sourceable `revise.lib.sh`
  exercised by 933 lines of bats.

### Gaps and drift risks

- **Spec→implementation traceability is by convention only.** `plan.md`/`tasks.md` name files
  and tests, but nothing links a code change back to an AC. `close.md` diffs
  `started_at_sha...HEAD`, but `started_at_sha` is described as optional ("if set, else
  creation time resolved to a commit SHA", `close.md:22-23`) — when unset, the diff basis is
  fuzzy and the changelog's "shipped vs spec" claim rests on model judgment.
- **The "in-progress" gate is soft.** Because a missing/blank `status` passes (`main.go:362`),
  a spec can be `active_spec` with no enforced status and still permit production edits. The
  gate's intent ("move to in-progress first") is bypassable by omission.
- **Review quorum defaults to 1** (`agents.toml`, `delegate/toml.go` default `ReviewQuorum=1`).
  A single aux agent (possibly `claude-p`, i.e. the same model family) can advance a spec to
  `reviewed`. There is no diversity requirement, so "cross-model review" can degenerate to
  "one model agreed with itself." Worth defaulting to 2 with distinct providers, or at least
  warning when quorum is met by a single same-family agent.
- **Aux-agent verdict parsing is best-effort** (`agents/aux-delegator.md`: "if unstructured,
  do best-effort interpretation, don't fail on missing structure"). A malformed/plain-text
  response can be silently read as approval, advancing status on a non-verdict.
- **No spec content sanitization before delegation.** Spec prose is concatenated into prompts
  sent to external CLIs (`codex exec --full-auto`, `claude -p`). For a tool that ingests
  arbitrary user prose this is a (low, but real) prompt-injection surface; at minimum it
  deserves a documented trust note.

---

## 4. TDD and guardrail review

### How enforcement actually works (verified in `main.go`)

> **Resolved by spec 0018.** The matrix below describes the state at the time of
> this review (commit `4529323`). Spec 0018 closed P0-1: Go, Python, and JS/TS now
> run the session's just-added sibling test through a real runner and require an
> observed failure (the `siblingRedCheck` path), reaching red→green parity with
> Rust. The "Runs the test?" column is now **Yes** for all four languages, and an
> unresolved runner fails closed instead of falling back to the touch-check.

| Language    | What the guard checked before allowing a production edit (pre-0018) | Ran the test? |
|-------------|----------------------------------------------------------|----------------|
| Rust        | Pre-edit `cargo check --tests` gate, then per-just-added-FQTN red-check that **observes a failing test** (`main.go:157-252`) | **Yes** |
| Go / Python | A sibling test file was *edited this session* (`hasSiblingTestEdited`, `main.go:390`) — **spec 0018: now runs the just-added test and requires an observed failure** | No → **Yes (0018)** |
| JS / TS     | A candidate sibling test path appears in `session.EditedTestFiles` (`main.go:446-452`) — **spec 0018: now runs the just-added test via the configured runner** | No → **Yes (0018)** |

### Weaknesses in test-first behavior

- **P0 — "red→green" is real only for Rust.** For Go/Python/JS/TS the invariant is satisfied
  by *touching* any matching test file this session. Concretely: add a blank line to
  `foo_test.go`, and every production `.go` file in that directory is now editable with no
  test having ever failed or even been run. The marketing term "red→green invariant"
  (in `index.md`, `guardrails.md`) overstates what is enforced. Either (a) run the sibling
  test and require a failure/observe a green transition, or (b) rename the invariant honestly
  (e.g. "test-touch discipline") so users don't trust a guarantee that isn't there.
- **P0 — Fail-open on broken state.** `prodGuardPrologue` returns `(prologueBlock, nil)` when
  `LoadState` errors (`main.go:347-351`); the caller's `case prologueBlock: return err`
  (`main.go:379-381`) returns a `nil` error, which `main` treats as success → **edit allowed**.
  The variable name says "block," the behavior is "allow." A corrupt `state.json` therefore
  disables the TDD invariant *silently*. This is both a fail-open guardrail and a
  naming/control-flow trap waiting to bite a future maintainer.
- **Session-only tracking is itself a soft bypass.** Because the check is "edited this
  session," `SessionStart` resets it (`ResetSession`, `state.go:315-324`). Long sessions
  accumulate "credit": touch one test early, edit production freely for the rest of the
  session. On-disk test existence is explicitly *not* sufficient (`main.go:412` comment), so
  the rule is neither "a test exists" nor "a test failed" — it's "a test was touched recently,"
  which is the weakest of the three.

### Bypass paths, false positives, false negatives

- **`MultiEdit` Rust red-check is effectively skipped** (P1). `applyEdit` (`main.go:318-323`)
  models only single Edit (`old→new`) or Write (empty `old` ⇒ `new` is whole file). A
  `MultiEdit` arrives with empty `old_string`/`new_string` at the top level, so `applyEdit`
  returns `""` → post-content empty → `postIDs=[]` → the just-added set omits the new tests →
  red-check doesn't fire. Rust TDD is bypassable via `MultiEdit`.
- **`NotebookEdit` bypasses the guard entirely** (P1, low real-world impact). It sends
  `notebook_path`, not `file_path`; the guard returns `nil` at `main.go:91-94`. It's in the
  matcher (`hooks.json:25`) but unparseable. Notebooks aren't a supported speccraft language,
  so impact is low — but the **bats tests give false confidence**: `pre-tool-use-state-guard.bats:66`
  asserts "rejects NotebookEdit on state.json" using a synthesized `file_path` key that a real
  `NotebookEdit` never sends (`hook_input` always emits `file_path`, `:31-36`). The test passes
  against a payload shape that cannot occur in production.
- **`prompt-submit.sh` heuristic is inconsistent with the supported languages** (P2). The nudge
  regex (`prompt-submit.sh:15`) matches `\.(go|md|json|toml)` but **not** `.py`, `.rs`, `.ts`,
  `.js` — so "implement the parser in `foo.py`" gets no nudge (false negative for two of four
  supported languages), while `.md` edits (always allowed by the guard) *do* trigger it (false
  positive). The languages the nudge cares about and the languages the guard enforces don't
  match.
- **The `scratch:` advice is misleading** (P2). `prompt-submit.sh:25` tells users to "prefix
  with `scratch:`" to do throwaway work, but the guard only allows the `scratch/` *path*
  (`files.go:137-143`). A `scratch:` prompt prefix does nothing. Users following the hint will
  still be blocked and won't know why.

### Do the guardrails help without blocking legitimate work?

Mostly yes — `IsAlwaysAllowed` (`files.go:119-144`) sensibly exempts `.md`, `docs/`,
`specs/`, `.speccraft/`, and `scratch/`, and the `/spec:override` one-shot
(`ConsumeOverride`, `state.go:184-199`) is a clean, atomic, logged escape hatch. The Rust
red-check, by contrast, runs **cargo synchronously inside a PreToolUse hook** on cache miss
(`main.go:176-180`, `main.go:219-238`); on a large crate this can stall an edit for many
seconds. The fingerprint cache mitigates steady state, but the first edit after any source
change pays full cost on the interactive path. Worth a visible "running red-check…" signal so
the user doesn't think the editor hung.

---

## 5. CI and validation

### Existing coverage (`.github/workflows/ci.yml`)

- `unit-linux` + `unit-macos`: `go test ./...` on Go `1.26.3`, both OSes. Good.
- `hooks`: builds binaries, runs bats hook tests. Good.
- `e2e-language-only`: runs on **push and PR**, no API key — the per-language fixtures.
- `e2e-devcontainer`: the full `claude -p` lifecycle, but **`if: github.event_name == 'push'
  && github.ref == 'refs/heads/main'`** (`ci.yml:83`) — i.e. **post-merge only**.

### Commands executed during this review

- `go test ./...` → all packages `ok` (cached/clean).
- `go vet ./...` → no findings.
- Verified absence of static-analysis steps and of `edits`/`notebook_path` handling via grep.

### Failures / flaky behavior observed

- None locally. The suite is green and fast.
- **Latent flakiness risk** in e2e assertions: `lib.sh` `status_is`/`contains` use unanchored or
  prefix `grep` that can match prose, and the project's own history (spec 0014/0015) records
  multiple "assertion tripped on model-chosen content" amendments — evidence that the e2e
  oracle has been brittle and was hardened reactively rather than designed structurally.

### Missing CI checks worth adding

1. **Run the claude-driven e2e on PRs** (P1) — even a reduced single-language smoke. Today the
   lifecycle is only validated *after* merge, so PR-green ≠ working.
2. **shellcheck** on `hooks/*.sh`, `scripts/*.sh`, `tests/e2e/*.sh`, `commands/spec/*.lib.sh`
   (P1). The hooks are load-bearing bash with `set -euo pipefail`, jq, and `realpath`
   subtleties; shellcheck would catch quoting/word-splitting bugs the test suite can't.
3. **`gofmt -l` and `go vet`** as explicit gates (P2). Currently neither runs in CI.
4. **Go version coherence** (P2): `go.mod` says `go 1.22` (`go.mod:3`), `release.yml` builds on
   `"1.22"` (`:33`), CI tests on `"1.26.3"`. Tests and releases run on different toolchains, and
   no `toolchain` directive pins it. Align them, or add a `toolchain` line, for reproducible
   release binaries.
5. **Version stamping** (P2): binaries hardcode `version = "1.0.0"` (`main.go:16`) with no
   `-ldflags` injection in `release.yml`, so `--version` cannot distinguish builds. `doctor.sh`
   and `install-binaries.sh` both reason about versions, making this a real diagnostic gap.

---

## 6. Code quality and maintainability

- **Complexity hotspot: `speccraft-guard/main.go` (519 lines)** mixes hook I/O, language
  dispatch, the entire Rust red-check pipeline, the prologue gate, frontmatter parsing, and
  string utilities. `rustDispatch`/`computeJustAddedForEdit` are the densest logic in the repo.
  Splitting Rust dispatch into its own file (mirroring the `rust_*.go` convention already used
  in `internal/`) would shrink the cognitive load of the binary's entrypoint.
- **Misleading enum: `prologueBlock` that allows.** (`main.go:336-340`, `:347-351`,
  `:379-381`) — already covered as a correctness bug in §4; it's also a readability landmine.
  A future edit that "tidies" the error return could flip behavior without anyone noticing.
- **Hand-rolled parsers where stdlib/vendored libs exist.** The TOML reader (`config.go`),
  frontmatter reader (`main.go:480-504`), and `splitLines` duplication are all places where
  simpler, shared code would be safer. The frontmatter reader in particular silently fails on
  legal YAML variants.
- **`sortStrings` is an insertion sort** (`state.go:286-292`) reimplementing `sort.Strings`.
  Harmless at current scale but unnecessary.
- **Stale "Phase N" comments.** Several files still carry scaffolding comments — `stop.sh:3`
  ("Full implementation in Phase 8"), `post-tool-use.sh:3` ("Full drift scan wired in Phase
  7"), `prompt-submit.sh:2` ("Full implementation in Phase 4"), `install-binaries.sh:4` ("Phase
  0 stub"). These read as unfinished even where the code is shipped, and mislead new readers
  about completeness.
- **Naming is otherwise strong** — `IsAlwaysAllowed`, `ConsumeOverride`, `CaptureInitialRustBaseline`
  are self-describing, and the inline rationale comments (e.g. the `,omitempty` explanation at
  `state.go:11-22`) are genuinely excellent and rare.

---

## 7. Developer experience

### What works

- `doctor.sh` is a strong diagnostic: required tools, claude version, binary/version skew,
  GitHub reachability, Go fallback, aux-agent presence. This is a real DX investment.
- Command frontmatter (`description`, `argument-hint`, `allowed-tools`) makes commands
  self-documenting in the Claude Code UI.
- Error messages on the *enforced* paths are excellent — the TDD-block message names the
  directory, lists found sibling tests, and points to `/spec:override` (`main.go:398-405`); the
  state.json guard message is similarly actionable (`pre-tool-use.sh:46-57`).

### Friction and confusion

- **The `scratch:` nudge actively misleads** (see §4, P2). Users will follow advice that does
  nothing.
- **The no-spec nudge under-fires for Python/Rust/TS** (see §4) — exactly the users who'd most
  benefit from the spec-first reminder may never see it.
- **Empty-message blocks.** Because the prologue can return a `nil` error on the block path,
  some failure modes can surface as an edit that's allowed-when-it-shouldn't-be (fail-open) —
  the inverse problem (a *block* with no explanation) is also reachable via the
  `LoadState`-error path if the control flow were tightened without care. Either way the user
  gets no message. Every block should carry a reason string.
- **Silent fail-open is undiscoverable.** When the guard no-ops on any internal error
  (`FindRoot`, `Abs`, `Rel`, JSON decode, `LoadState` — all `return nil`), the user has no
  signal that enforcement *didn't run*. A one-line stderr breadcrumb ("speccraft: guard
  skipped — could not read state") would make non-enforcement observable without changing the
  fail-open policy.
- **Documentation gap: the enforcement asymmetry isn't stated.** Nothing user-facing tells a Go
  or Python developer that their "TDD invariant" is a touch-check while Rust's is a true
  red-check. Users will assume parity. Document the matrix in §4 explicitly.
- **Long Rust red-checks look like a hang** (see §4). Add progress output.

---

## 8. Prioritized recommendations

### P0 — critical correctness / workflow-breaking

| # | Finding | Component | Why it matters | Evidence | Suggested fix | Effort |
|---|---------|-----------|----------------|----------|---------------|--------|
| P0-1 ✅ **Resolved by spec 0018** | TDD invariant is a "test was touched this session" check for Go/Python/JS/TS, not red→green | `main.go:390`, `:446-452` | The core product promise ("red→green invariant") is unenforced for 3 of 4 languages; trivially satisfied by editing any sibling test | Guard never invokes a runner outside Rust; only Rust path calls `adapter.Run` (`main.go:219-238`) | **Done (spec 0018):** runs the session's just-added sibling test and requires an observed failure (`siblingRedCheck`), with fail-closed on an unresolved runner | Large (real check) |
| P0-2 | Guard fails open on corrupt/unreadable `state.json` | `main.go:347-351`, `:379-381` | Enforcement silently vanishes precisely when state is broken; `prologueBlock` returns a `nil` error so the edit is allowed | `prodGuardPrologue` `return prologueBlock, nil`; caller `case prologueBlock: return err` with nil err | Return a non-nil error on the block path (fail-closed for prod edits) **or** explicitly choose fail-open and `log` it; fix the misleading name/flow | Small |

### P1 — important reliability / usability

| # | Finding | Component | Why it matters | Evidence | Suggested fix | Effort |
|---|---------|-----------|----------------|----------|---------------|--------|
| P1-1 | `MultiEdit`/`NotebookEdit` gated but not parsed | `main.go:26-30`; grep: no `edits`/`notebook_path` anywhere | `MultiEdit` skips the Rust red-check (empty old/new ⇒ empty post-content); `NotebookEdit` bypasses the guard; bats tests pass against payloads real tools never send | `ToolInput` has only `file_path/old_string/new_string`; `applyEdit` (`:318-323`); false-confidence test (`pre-tool-use-state-guard.bats:66`) | Parse `edits[]` and `notebook_path`, or drop them from the matcher and fix the tests to reflect reality | Medium |
| P1-2 | Full claude-driven e2e runs only post-merge | `ci.yml:83` | PRs can be fully green while the command lifecycle is broken; only caught after merge to `main` | `if: github.event_name == 'push' && github.ref == 'refs/heads/main'` | Add a reduced single-language claude e2e on PRs (guard with API-key-present conditional) | Medium |
| P1-3 | No shellcheck on load-bearing hooks | `.github/workflows/` (none) | Hooks use `set -euo pipefail`, jq, `realpath`; quoting/word-split bugs won't be caught by Go tests | grep: no `shellcheck/gofmt/vet/lint` in CI | Add a shellcheck job over `hooks/`, `scripts/`, `tests/e2e/`, `commands/spec/*.lib.sh` | Small |
| P1-4 | Review quorum defaults to 1, no provider diversity | `delegate/toml.go` default; `agents.toml` | "Cross-model review" can be a single same-family agent approving itself | `ReviewQuorum=1` default | Default quorum 2 with distinct providers, or warn when a single same-family agent meets quorum | Small |
| P1-5 | Aux-agent verdict parsing is best-effort | `agents/aux-delegator.md` | A malformed/plain-text response can be read as approval and advance status | "don't fail on missing structure" instruction | Require a structured verdict token; treat unparseable output as `needs-changes`, not approval | Small |

### P2 — cleanup / maintainability

| # | Finding | Component | Why it matters | Evidence | Suggested fix | Effort |
|---|---------|-----------|----------------|----------|---------------|--------|
| P2-1 | `prompt-submit.sh` heuristic misses `.py/.rs/.ts/.js`, fires on always-allowed `.md` | `prompt-submit.sh:15` | False negatives for half the supported languages; false positive on `.md` | regex matches `\.(go\|md\|json\|toml)` | Align the extension set with the guard's supported languages; drop `.md` | Small |
| P2-2 | `scratch:` advice does nothing | `prompt-submit.sh:25` vs `files.go:137-143` | Users follow a hint that has no effect and stay blocked | Guard allows the `scratch/` *path*, not a prompt prefix | Fix the message to reference the `scratch/` directory, or implement a real prefix escape | Small |
| P2-3 | Status-gate frontmatter parser passes on missing/oddly-spaced `status` | `main.go:362`, `:480-504` | The "move to in-progress first" gate is bypassable by omission/format | `status != "in-progress" && status != ""` | Use a real YAML parse; treat missing `status` as a block, not a pass | Small |
| P2-4 | Two TOML parsers; hand-rolled one is fragile | `config.go:90-112` vs `delegate/toml.go` | Multi-line arrays / inline tables silently mishandled; `BurntSushi/toml` already vendored | — | Use `BurntSushi/toml` for `speccraft.toml` too | Medium |
| P2-5 | Go toolchain incoherence + no version stamping | `go.mod:3`, `release.yml:33`, `ci.yml:30`, `main.go:16` | Releases (`1.22`) and tests (`1.26.3`) run on different toolchains; `--version` can't distinguish builds | hardcoded `version="1.0.0"`, no `-ldflags` | Add a `toolchain` directive; inject version via `-ldflags -X` at release | Small |
| P2-6 | Duplicated `splitLines`, insertion-sort `sortStrings`, stale "Phase N" comments | `state.go:367-380`/`main.go:506-518`, `state.go:286-292`, `stop.sh:3` et al. | Drift risk + "looks unfinished" signal to new readers | — | De-dup to a shared util; use `sort.Strings`; delete scaffolding comments | Small |
| P2-7 | Rust red-check blocks the interactive edit with no progress signal | `main.go:176-180`, `:219-238` | First edit after any source change runs cargo synchronously; looks like a hang | synchronous `adapter.Run` in PreToolUse | Emit a "running red-check…" breadcrumb to stderr | Small |

---

## Things that are simply done well (no action needed)

- Single-writer state model and its triple enforcement (source grep + runtime hook + policy).
- Atomic state writes with a process mutex (`state.go:80-101`).
- Dependency-injection seam making the Rust red-check unit-testable (`main.go:35-39`).
- The actionable, well-worded error messages on enforced paths.
- The spec/changelog/ADR discipline — traceability most teams never achieve.
- `doctor.sh` as a first-class diagnostic.
- Inline rationale comments that explain *why* (e.g. `,omitempty`, `realpath -m`).

---

### One-line takeaway

The scaffolding is excellent; the **enforcement is honest only for Rust and fails open when
state breaks**. Close P0-1 and P0-2 and speccraft delivers on its core promise across all four
languages — everything else on this list is polish on an already-solid foundation.
