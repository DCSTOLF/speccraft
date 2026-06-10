# Conventions

## Go (`tools/`)

- Module path: `github.com/dcstolf/speccraft/tools`. Go 1.22 in `go.mod` (CI runs 1.26.3).
- One binary per subdirectory of `tools/cmd/`. Each has its own `main.go`; no shared `main` package.
- Shared logic lives in `tools/internal/speccraft/` (general) or `tools/internal/delegate/` (aux-agent dispatch). `tools/internal/` packages must not import `tools/cmd/`.
- Errors: wrap with `fmt.Errorf("...: %w", err)`. Sentinel errors live in the package that returns them.
- Logging from `tools/internal/`: return errors, do not print. CLI output (human-readable status, JSON results) belongs in `tools/cmd/*/main.go`. (Advisory — the drift tool can't distinguish real `fmt.Print*` calls from test fixtures that embed the string, so this is checked at code review rather than enforced via regex.)
- Tests: `_test.go` files colocated with the code under test; table-driven for >2 cases; function names start with `Test`. <!-- enforce: regex pattern="^func Test[A-Z]" scope="tools/**/*_test.go" -->
- Test-function naming (introduced by spec 0012): both `Test<UpperCamel>` (e.g. `TestStateRoundTrip`, `TestFarewell`) and `Test_<Subject>_<Scenario>` (e.g. `Test_SetField_ActiveSpec_NullArg_ClearsToJSONNull`) are acceptable. Prefer the underscore form for scenario-specific tests where the name encodes a concrete input → expected output, since it makes the failure line self-documenting. Prefer the camelCase form for broad round-trip / smoke tests where there is no single scenario to name. The `^func Test[A-Z]` enforce-regex above accepts both and stays as is — tightening it would force a rename of every existing camelCase test in the repo, which is out of scope.

## Bash (`hooks/`, `tests/e2e/`, `scripts/`)

- Every script starts with `#!/usr/bin/env bash` and `set -euo pipefail`.
- Use absolute paths derived from `${BASH_SOURCE[0]}`; never assume CWD.
- All filesystem writes to `.speccraft/` go through the `speccraft-state` binary — hooks do not edit `state.json` directly.
- Hooks emit Claude Code hook-protocol JSON on stdout and exit non-zero on guardrail violations.

### E2E language-fixture pattern (`tests/e2e/<lang>_cycle.sh`)

Introduced by spec 0005 (Rust) and codified by spec 0007 (Python). Every supported language has a self-contained Bash fixture script in `tests/e2e/` that drives `speccraft-guard` against a representative project layout through the Claude Code PreToolUse hook flow.

- **File location and naming.** `tests/e2e/<lang>_cycle.sh` (e.g. `rust_inline_cycle.sh`, `rust_integration_cycle.sh`, `python_cycle.sh`). Marked executable. `#!/usr/bin/env bash` + `set -euo pipefail` per the general Bash convention above.
- **Hermetic work dir.** Create `WORK="$(mktemp -d -t <lang>-cycle.XXXXXX)"` and register `trap cleanup EXIT` with a `KEEP_E2E=1` escape hatch. Build any binaries the fixture needs (`speccraft-guard`, `speccraft-state`) into `$WORK`, not into the source tree.
- **Hook protocol.** Drive `speccraft-guard pre-tool-use` via JSON on stdin matching the Claude Code hook envelope (`tool_name`, `tool_input.file_path`, `cwd`). Factor a `hook_input(path)` helper to keep assertion blocks short.
- **Exit-code convention.** `fail()` exits 2 (assertion failure), distinct from setup failures (exit 1) and the script's own success (exit 0). Matches `tests/e2e/run.sh`'s expectations.
- **Progress output.** Use a `note()` helper for intra-scenario progress lines (indented two spaces) and a top-level `echo "==> ..."` for scenario headers, mirroring `rust_inline_cycle.sh` and `python_cycle.sh`.
- **Invocation from `run.sh`.** Each fixture is invoked from `tests/e2e/run.sh` in a hermetic subshell — `( bash "$RUST_E2E_DIR/<lang>_cycle.sh" ) || fail "<lang>_cycle.sh failed"` — so fixture-local `cd` and env mutations cannot leak into later steps. The step counter (`[N/M]`) is updated in the same edit that adds a new fixture.

### Reset state between scenarios

Introduced by spec 0007.

- When a single fixture script exercises multiple acceptance criteria that share the same project directory, the script must reset session state between scenarios so earlier mutations to `state.json` (e.g. `EditedTestFiles`) do not silently mask later reject assertions. The canonical form is a `reset_state()` (or `reset_session()`) helper that rewrites `.speccraft/state.json` from a literal JSON template with empty `edited_test_files` / `edited_prod_files`. See `python_cycle.sh::reset_state` and the equivalent in the Rust fixtures for reference implementations.

### Grep-assertion oracle for doc-only specs

Introduced by spec 0011.

When a spec is documentation- or template-only — no Go code, no hook, no runner, no e2e fixture to write — the RED→GREEN cycle uses a committed `verify.sh` grep-assertion script in the spec directory, not a behavioral test.

- **Location.** `specs/<id>-<slug>/verify.sh`, marked executable, `#!/usr/bin/env bash` + `set -euo pipefail` per the general Bash convention. Resolves repo root from `${BASH_SOURCE[0]}` and `cd`s there so greps see consistent paths regardless of caller CWD.
- **Shape.** Each acceptance criterion becomes a labelled `grep` invocation that either passes or fails; the script accumulates a `fails` counter and exits non-zero on any failure. Pair every "absence" check (`grep ... must return zero`) with a "presence" check (`grep ... must return at least one`) so that satisfying the absence by deleting the whole section is rejected as well.
- **Lifecycle.** Failing against current `main` is the RED state; the edits required to make every check pass are the GREEN state; the script stays in the spec directory after close as the documented AC oracle. Doc-only specs do not wire `verify.sh` into CI — the changes are one-shot and the grep cost is low enough for reviewer inspection.
- **When to use this vs. a behavioral test.** If the package under change contains only Markdown / TOML / templates and an inventory of existing `*_test.go` / `*_test.sh` returns nothing, prefer `verify.sh`. As soon as Go code, a hook, or a runner is in scope, fall back to the normal `_test.go` / `tests/e2e/<lang>_cycle.sh` patterns; `verify.sh` is a complement to, not a replacement for, behavioral tests.

Sibling to the existing E2E language-fixture pattern: the language fixtures are the oracle for behavioral specs; `verify.sh` is the oracle for documentation specs.

## CI

Introduced by spec 0008.

### Job-split convention

`.github/workflows/ci.yml` carries two e2e jobs with different cost and credential profiles. Future e2e additions pick a job by cost:

- **`e2e-language-only` (cheap, hermetic).** Runs on every `push` and `pull_request`. Does NOT receive `ANTHROPIC_API_KEY` (must run on PR-from-fork). Executes `bash tests/e2e/run.sh --language-only` inside the devcontainer. New language fixtures (`tests/e2e/<lang>_cycle.sh`) get exercised here automatically by adding them to `run_language_fixtures()` in `tests/e2e/run.sh`.
- **`e2e-devcontainer` (expensive, credit-gated).** Gated to `push` on `main`. Receives `ANTHROPIC_API_KEY` from repo secrets. Runs the full lifecycle (`claude -p`-driven spec workflow + language fixtures).

Anything that invokes `claude -p` belongs in the lifecycle job. Anything that exercises `speccraft-guard` against a representative project layout (no API calls) belongs in the language-only job.

### `ENVIRONMENT_FAILURE:` annotation pattern

When `claude -p` fails in the lifecycle job, `classify_claude_failure()` in `tests/e2e/run.sh` greps the captured log and emits one of:

- `ENVIRONMENT_FAILURE: credit_exhausted` — Anthropic "Credit balance is too low" string.
- `ENVIRONMENT_FAILURE: auth` — HTTP 401/403, unset/empty `ANTHROPIC_API_KEY`, or one of `invalid x-api-key` / `authentication failed` / `unauthorized` (case-insensitive).
- `ENVIRONMENT_FAILURE: transient_api` — HTTP 5xx, HTTP 429, or one of `network` / `timeout` / `connection refused` (case-insensitive).

Rules:
- **Order matters.** Classification runs credit → auth → transient → none. Credit exhaustion must come first so auth matchers don't eat it.
- **Exit code stays non-zero.** This is observability, not error-swallowing.
- **Unmatched failures are not annotated.** Plain assertion mismatches stay unadorned; the absence of the tag is itself a signal ("this is a real defect").
- **Extend, don't fork.** New environmental failure modes (new categories or new matchers within existing categories) extend `classify_claude_failure`; do not introduce parallel detection mechanisms.

### Mock aux-agent stdin detach

`claude -p` does not EOF the stdin of subagent CLIs it launches. Mock aux-agent CLIs (the ones installed by `.devcontainer/install-mock-agents.sh` for hermetic e2e) must therefore detach stdin at startup:

```bash
#!/usr/bin/env bash
set -euo pipefail
exec </dev/null
# ... rest of mock ...
```

Without this, any mock that reads stdin (e.g. `INPUT="$(cat)"`) blocks forever when invoked through `claude -p`. The opencode mock additionally declares `input = "argv"` in `.speccraft/agents.toml`, so it should not be reading stdin at all — the detach is the load-bearing safety net.

## Markdown frontmatter

- **Slash commands (`commands/**.md`):** YAML frontmatter with at minimum `description:`. Fully qualified command names live in the filename path (e.g. `commands/spec/new.md` becomes `/speccraft:spec:new`).
- **Subagents (`agents/*.md`):** YAML frontmatter with `name:`, `description:`, and `tools:`.
- **Skills (`skills/<name>/SKILL.md`):** YAML frontmatter with `name:` and `description:`.
- **Specs (`specs/NNNN-<slug>/spec.md`):** YAML frontmatter with `id`, `title`, `status`, `created`. `plan.md` and `tasks.md` mirror `id`. `changelog.md` is appended by `/speccraft:spec:close`.

### Optional: `reserves-specs`

Introduced by spec 0005. An optional spec-frontmatter field that lets a spec reserve one or more future spec IDs so that error messages and stderr assertions can name a stable id before the follow-up exists.

```yaml
reserves-specs: ["0006"]
```

- **Purpose.** Reserving spec IDs for follow-up work referenced by acceptance criteria in the reserving spec. Spec 0005 is the first concrete use — its workspace-detection error names spec `0006` (Cargo workspace support) by id, so the assertion stays meaningful even before `0006` exists on disk.
- **Shape.** A YAML list of zero-padded four-digit ID strings (e.g. `["0006"]`, `["0006", "0007"]`). Optional; absent on most specs.
- **Allocation rule.** `/speccraft:spec:new` should skip reserved IDs when computing the next available ID. Enforcement in the tool is **advisory** for now — current `/speccraft:spec:new` does not implement reservation-aware allocation. Tooling implementation is deferred to a follow-up spec; this convention entry exists so reviewers and authors can apply the rule manually until enforcement lands.
- **Lifecycle.** The reservation entry is removed from the reserving spec's frontmatter when the reserved spec is filed (its `spec.md` appears under `specs/`). Removal happens during `/speccraft:spec:close` of the reserving spec or as part of the follow-up's first commit, whichever is sooner.
- **Consistency.** A reserved ID has no `spec.md` on disk and must not be flagged by drift or consistency checks as missing.
- **Lower-bound rule.** A spec may not reserve an ID lower than its own.

## Spec lifecycle

- Spec IDs are zero-padded four-digit (`0001`, `0002`, …) and never reused.
- Closed specs (`status: closed`) are immutable. Corrections go in a follow-up spec.

### Close-commit invariant

Introduced by spec 0008 (codex R3 finding).

The `/speccraft:spec:close` commit must contain **both** the `changelog.md` write **and** the `status: → closed` flip on `spec.md`. The parent commit must still show the pre-close status. Rules:

- **One commit, both edits.** Splitting them across two commits creates a window in which `status:` is `closed` but the changelog is missing the close-gate evidence, or vice versa.
- **Parent commit shows pre-close status.** Verifiable post-hoc with `git show <close-commit>^:specs/<id>/spec.md | grep ^status:`.
- **No post-close edits.** Closed specs are immutable per the existing rule; this invariant extends that to the changelog. If something needs to be added after close, file a follow-up spec instead.
- **Pre-close gate evidence (when applicable).** When a spec's §Post-merge verification names a CI run as a close gate (e.g. spec 0008's first-green-run requirement), the run URL goes in `changelog.md` as part of this same commit — by definition, before the status flip is visible on `main`.

## Rust (`tools/internal/speccraft/`)

Introduced by spec 0005. Conventions for any future Rust-touching code in this repo (not for host-project Rust code — that lives behind the guard).

- **Canonical Rust test ID form.** `<file-stem>::<module-path>::<fn>` for inline tests (e.g. `foo::tests::it_works`) and `<file-stem>::<fn>` for integration tests (e.g. `bar::alpha`). The `<crate-name>::` prefix is stripped by both runner adapters and is never part of the canonical ID. Static discovery (`DiscoverRustTests`) and runner records (parsed by `runner/cargo_parse.go` and `runner/nextest_parse.go`) emit the same form so set-difference is well-defined. New code dealing with Rust test names must use this form end-to-end.
- **Single-writer rule for `Session` state fields.** All fields on `Session` in `.speccraft/state.json` (e.g. `active_spec`, `rust_test_baseline`, `rust_gate_fingerprint`, `override_pending`) are written **only** by `tools/cmd/speccraft-state/main.go` and the helpers in `tools/internal/speccraft/state.go`. A grep-based regression test (`tools/internal/speccraft/state_single_writer_test.go`) enforces this. Adding any new `Session` field requires extending the grep allow-list in that test — this is not Rust-specific.
- **Consume-on-use pattern for single-shot flags.** Single-shot state flags (e.g. `override_pending`) must be consumed atomically: acquire `mu.Lock()` once, call `loadStateLocked`, read the value, clear it, call `saveStateLocked`, then unlock. See `ConsumeOverride` in `state.go` as the canonical implementation. Do not read with one lock acquisition and clear with another — that pattern is racy and leaves a window where a crash can preserve a flag that was logically consumed.
- **Rust static recognition split.** Tokenization (string/comment/raw-string awareness) lives in `tools/internal/speccraft/rusttok/`. Domain-specific recognition (canonical IDs, inline `#[cfg(test)] mod` blocks, stem-mapping, crate-walk discovery, baseline lifecycle) lives in `tools/internal/speccraft/rust_*.go`. Keep the boundary: any new tokenizer-level edge case (e.g. new string-literal form) goes in `rusttok/`; any new test-recognition rule goes in `rust_*.go`.
- **Documented limitations.** §L2 (macro `fn` phantom-ID extraction) is a known false-positive that the runner backstop catches. Do not "fix" it by adding ad-hoc macro detection in the tokenizer — that path leads to a half-parser. The proper fix is `syn`/`tree-sitter-rust`, deferred until incidence warrants it.

## Language extensibility in `speccraft-guard`

Introduced by spec 0005.

- **Dispatch by language.** `tools/cmd/speccraft-guard/main.go` routes through `dispatchByLanguage(input, deps)`. Adding a new language is a localized change: implement a `<lang>Dispatch` function (following the `rustDispatch` template), inject any new dependencies through the `deps` struct, and add a case to `dispatchByLanguage`. Do not introduce parallel codepaths inside `processToolUse`.
- **Production wiring goes through `productionDeps()`.** The testability seam in `processToolUse(input, deps)` accepts injected fakes for `exec` and `runnerFor`. The production caller must use `productionDeps()` to wire the real `exec.Command` and `runner.AdapterFor` — constructing `deps{}` inline silently disables the real runner and gate, a bug we hit and fixed during spec 0005 implementation.
- **Runner-primitive adapter contract.** Per-language test runners implement `runner.Runner` (`Run(ctx, Request) (Result, error)`). Argv construction, output parsing, and outcome classification live entirely inside the adapter. No language-specific code in `tools/cmd/speccraft-guard`.

### Production-guard prologue is a shared tri-state helper

Introduced by spec 0010. When adding a new language dispatcher to `speccraft-guard`, route the red-phase preamble through `prodGuardPrologue` rather than re-implementing the active-spec / override / state-load checks inline. The helper returns one of three `prologueDecision` values:

- `prologueAllow` — the write is permitted unconditionally (override consumed); the dispatcher must return immediately.
- `prologueBlock` — the write is denied; the dispatcher must return the prologue's blocking error.
- `prologueContinue` — all common gates passed; the dispatcher must run its language-specific sibling-test check.

**Rationale:** Before `jsTsDispatch` was added, the red-phase preamble lived inline inside `goPythonProdGuard`. Copying it would have created two independent paths through override consumption and state loading — guaranteed drift the next time override or active-spec semantics changed. See `prodGuardPrologue` in `tools/cmd/speccraft-guard/main.go` as the canonical implementation.

## Templates (`templates/speccraft/`)

- Must remain stack-agnostic. No language- or framework-specific examples in default templates.
- Mirror the schema of the live `.speccraft/` files at the repo root, but with placeholder content.

## External-tool boundaries

Introduced by spec 0011.

When an external tool (MCP server, LSP, code-intel indexer, structural linter, etc.) writes routing rules into the user's environment — typically via global CLAUDE.md installed by the tool's own setup command, or via the MCP server's own instructions surfaced to the model — speccraft must defer to those rules rather than maintaining a parallel copy.

Concretely:

- **No tool-specific routing in skills, commands, agents, or templates.** Skill files (`skills/*/SKILL.md`), command bodies (`commands/**/*.md`), subagent definitions (`agents/*.md`), and templates (`templates/speccraft/**`) must not tell the model which external tool to call, in what order, or under what conditions. That authority belongs to the tool itself.
- **Examples are allowed; recommendations are not.** A single mention framed as "such as <Tool>", "for example, <Tool>", or "e.g., <Tool>" is fine — it helps the user discover the ecosystem. Phrasing that reads as a speccraft recommendation ("prefer X", "use X", "X is the recommended way to ...") is not.
- **Install-suggestion prose is the one acceptable touch-point.** `/speccraft:init` may conditionally suggest installing a category of external tool when the user mentions a matching need (e.g. call-graph or symbol-search capabilities). Conditional discovery prose is value added; unconditional routing prose is duplication.
- **Speccraft owns what speccraft writes.** Spec lifecycle, TDD gate, `state.json`, project memory under `.speccraft/`, and the templates copied into host repos are speccraft's authority. Anything else (code-intel routing, formatting rules, language-server invocation, test-runner selection beyond what `speccraft-guard` requires) is the host environment's authority.

Rationale: the alternative is silent drift. The external tool's own guidance evolves on its own release cadence; speccraft's stale copy then conflicts with the live rule, and the model wastes attention resolving the conflict. The 2026-06-09 cgc + global CLAUDE.md collision that triggered spec 0011 is the concrete instance.
