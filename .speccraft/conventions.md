# Conventions

## Go (`tools/`)

- Module path: `github.com/dcstolf/speccraft/tools`. Go 1.22 in `go.mod` (CI runs 1.26.3).
- One binary per subdirectory of `tools/cmd/`. Each has its own `main.go`; no shared `main` package.
- Shared logic lives in `tools/internal/speccraft/` (general) or `tools/internal/delegate/` (aux-agent dispatch). `tools/internal/` packages must not import `tools/cmd/`.
- Errors: wrap with `fmt.Errorf("...: %w", err)`. Sentinel errors live in the package that returns them.
- **`omitempty` for cleared-string state fields (introduced by spec 0012).** When a string field on a JSON-serialised struct represents the disjoint shapes "unset" OR "set to a concrete value," the JSON tag must carry `,omitempty` so the cleared shape on disk is an absent key, not an empty string or a sentinel string like `"null"`. Combined with a clear-semantics special-case in the setter (treat argv `"null"` or `""` as "clear"), this produces a disk shape that satisfies `jq -r '.<field> // "null"' state.json` returning the literal string `null` — the assertion shape `tests/e2e/run.sh` uses for the lifecycle close gate. Sentinel-string fallbacks are forbidden; they break the jq-default convention silently. See `State.ActiveSpec` in `tools/internal/speccraft/state.go` as the canonical implementation.
- Logging from `tools/internal/`: return errors, do not print. CLI output (human-readable status, JSON results) belongs in `tools/cmd/*/main.go`. (Advisory — the drift tool can't distinguish real `fmt.Print*` calls from test fixtures that embed the string, so this is checked at code review rather than enforced via regex.)
- Tests: `_test.go` files colocated with the code under test; table-driven for >2 cases; function names start with `Test`. <!-- enforce: regex pattern="^func Test[A-Z]" scope="tools/**/*_test.go" -->
- Test-function naming (introduced by spec 0012): both `Test<UpperCamel>` (e.g. `TestStateRoundTrip`, `TestFarewell`) and `Test_<Subject>_<Scenario>` (e.g. `Test_SetField_ActiveSpec_NullArg_ClearsToJSONNull`) are acceptable. Prefer the underscore form for scenario-specific tests where the name encodes a concrete input → expected output, since it makes the failure line self-documenting. Prefer the camelCase form for broad round-trip / smoke tests where there is no single scenario to name. The `^func Test[A-Z]` enforce-regex above accepts both and stays as is — tightening it would force a rename of every existing camelCase test in the repo, which is out of scope.

## Bash (`hooks/`, `tests/e2e/`, `scripts/`)

- Every script starts with `#!/usr/bin/env bash` and `set -euo pipefail`.
- Use absolute paths derived from `${BASH_SOURCE[0]}`; never assume CWD.
- All filesystem writes to `.speccraft/` go through the `speccraft-state` binary — hooks do not edit `state.json` directly.
- Hooks emit Claude Code hook-protocol JSON on stdout and exit non-zero on guardrail violations.

### PreToolUse hook tool enumeration

Introduced by spec 0012.

When a hook in `hooks/` gates behavior on the Claude Code tool name (e.g. `tool_name` from the PreToolUse envelope), the gated set is declared in **one** shell variable inside the hook script (current canonical form: `GATED_TOOLS="Edit Write MultiEdit NotebookEdit"` in `hooks/pre-tool-use.sh`). Two paired-update rules:

- **`hooks/hooks.json` matcher must be extended in lockstep.** The matcher regex in `hooks.json` controls which tool names Claude Code routes to the hook in the first place. A tool name listed in `GATED_TOOLS` but missing from the matcher is unreachable — the hook never sees it and the guardrail silently doesn't fire. Verify by reading both files together when changing either. Pair the `PreToolUse` and `PostToolUse` matchers too if the tool name needs to surface in both phases.
- **One-line change.** Adding a future write-tool name (e.g. a hypothetical `BulkEdit`) is a one-line change in two places: append to `GATED_TOOLS` in the hook source, extend the pipe-separated matcher regex in `hooks.json`. Anything more is a smell — refactor before extending.

Coverage assertion: `tests/hooks/pre-tool-use-state-guard.bats` exercises one case per gated tool name so a missing matcher extension fails at test time, not silently at runtime.

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

### E2E assertion predicates: structural over content

Introduced by spec 0014.

When an e2e assertion verifies that a model-driven step happened — memory-keeper applied an ADR, spec-author wrote a plan, the planner emitted a `## Risk` section, the close hook updated the changelog, etc. — the predicate must target a STRUCTURAL signal the agent's contract guarantees, not a CONTENT signal the agent's free-text choice happens to produce.

- **Structural signal examples (good).** A dated ADR-header line shape (`^## 20[0-9]{2}-[0-9]{2}-[0-9]{2}`), a YAML frontmatter key being present, a status field having a specific enumerated value, a JSON field being absent vs `null`, a file existing. These are pinned by the agent's prompt/template, not by the model's word choice.
- **Content signal examples (bad).** A specific feature-named keyword (the spec title's main noun, a function name from the test fixture), a specific ADR title phrasing, the literal word the user happened to type in the spec's "Why" section. These are the model's free-text choice and will be wrong on the random-seed days the model picks a different phrasing.
- **Why this rule matters.** Three consecutive CI attempts on commit `ed3fe24` (spec 0014's pre-fix baseline) failed identically because the `tests/e2e/run.sh:278` assertion grepped `history.md` for the literal word `farewell` — which lives in the test-spec title and only ends up in `history.md` if memory-keeper happens to pick a feature-named ADR title. On the failing attempts, memory-keeper picked design-rationale titles like *"Defer stdout-capture testing for main()"* that never mention the feature. The previous "green" run on `9c1330d` was the same flake getting lucky.
- **Wrong layer to fix.** Tightening the agent's prompt to make titles feature-deterministic is much larger and indirect — it changes the agent's surface semantics for every spec. Tightening the assertion is bounded and correct: the e2e contract is verifying *that memory-keeper's output was applied*, and the deterministic signal for that is the dated ADR header memory-keeper's documented format guarantees, not the title content the model chose.
- **When in doubt.** If you cannot point to a literal in the agent's prompt, template, or output-format documentation that pins the string you want to grep for, the string is a content signal, not a structural one. Pick a different predicate.

### Shared assertion helpers via `tests/e2e/lib.sh` ("exact predicate" invariant)

Introduced by spec 0014.

When a sibling fixture under `tests/e2e/` needs to exercise the *same predicate* `tests/e2e/run.sh` uses (e.g. to pin the predicate's shape against synthetic inputs without running the full lifecycle), the assertion helpers MUST be extracted to `tests/e2e/lib.sh` and both `run.sh` and the fixture MUST `source` it. The two non-acceptable alternatives:

- **Naive `source tests/e2e/run.sh`.** `run.sh` executes at body level — sourcing it runs the entire harness, including the throwaway-repo creation and the `claude -p` invocations.
- **Duplicating helper definitions in the fixture.** Invites drift the moment one site's helper changes semantics; the fixture's "exact predicate" invariant collapses silently.

The `lib.sh` extraction is the only path that keeps the predicate provably identical without restructuring `run.sh`.

- **Shape.** `tests/e2e/lib.sh` carries `#!/usr/bin/env bash` + `set -euo pipefail` per the general Bash convention (defensive — the file is sourced, but the shebang documents intent and the strict-mode flags become active in the sourcing shell if not already set). Helpers are pure functions: `fail`, `pass`, `exists`, `contains` (fixed-string, `grep -qF`), `contains_regex` (extended regex, `grep -qE`), `status_is`. New helpers added there, not in `run.sh`.
- **`fail()` must be `set -u`-safe when called from fixture context.** `run.sh`'s `fail()` reads `$LAST_LOG` / `$LOG_DIR` to dump the most recent `claude -p` log; fixtures don't set those. The shared `fail()` guards its log-cat block with `${VAR:-}` default-empty expansion on every variable reference so calling it from a fixture context is safe under `set -u`.
- **Sibling, not flag.** When a new assertion shape is needed, add a sibling helper (e.g. `contains_regex` next to `contains`) rather than overloading an existing helper with a mode flag. Call sites declare predicate type explicitly at the call site; existing callers' semantics are not touched.
- **Sibling fixtures source `lib.sh` directly.** Compute `LIB_DIR` from `${BASH_SOURCE[0]}` per the existing Bash convention and `source "$LIB_DIR/lib.sh"`. Wire the fixture into a sibling `run_helper_unit_tests()` (not `run_language_fixtures()` — that name describes language-cycle fixtures specifically). Helper-first ordering in dispatch is preferred: a helper regression should fail before the language cycles or `claude -p` steps consume budget.
- **Canonical reference.** `tests/e2e/lib.sh` + `tests/e2e/contains_adr_assertion_test.sh` (spec 0014). Both files document the load-bearing constraints inline.

### Sourceable command helpers: `commands/<group>/<name>.lib.sh` colocation

Introduced by spec 0015.

When a slash command under `commands/<group>/<name>.md` needs Bash logic complex enough to deserve unit tests — preflight gates, file-shape parsing, snapshot/diff, multi-step state transitions — extract the helpers into a sibling `commands/<group>/<name>.lib.sh` colocated with the `.md` body. The `.md` command sources the lib at runtime; the bats suite under `tests/hooks/<name>.bats` sources the same file at test time.

- **Shape.** `#!/usr/bin/env bash` + `set -euo pipefail` per the general Bash convention. Every helper is a pure function — no top-level side effects, no top-level `cd`, no global state mutations at source time. Sourcing the file from bats must be a no-op other than defining functions and any read-only constants. Functions emit human-readable errors on stderr (typically via a central `<name>_error()` envelope) and reserve stdout for structured output (drift items, diff signals, identifier tokens).
- **Runtime sourcing.** From the `.md` body: `source "$CLAUDE_PLUGIN_ROOT/commands/<group>/<name>.lib.sh"`. The command body then becomes a thin driver that calls named functions in order, each independently testable from bats.
- **Test sourcing.** From the bats file: `source "$PLUGIN_DIR/commands/<group>/<name>.lib.sh"` in `setup()`. Because every helper is pure, the bats harness exercises each function in isolation with seeded fixtures — preflight error paths, identifier extraction, frontmatter integrity, snapshot diff, archive renames — at zero credit cost. Agent-dependent ACs stay in `tests/e2e/run.sh` (credit-gated); helper-mechanics ACs come back to the cheap bats layer.
- **Why this rule matters.** Before spec 0015, `commands/spec/*` was Markdown-only — every command's mechanism prose was un-unit-testable shell embedded inside an instructions document. Spec 0015's `revise` introduced 13 distinct preflight + parsing + diff + archive helpers; pushing AC1's three status sub-cases plus AC9/AC10 (preflight error paths) into the credit-gated lifecycle job would have cost a real budget for what is purely deterministic Bash. Extracting to `revise.lib.sh` made 53 bats tests possible at zero credit cost, and the pure-function discipline is what makes those tests trivial to author — `setup()` seeds a fixture, the `@test` body sources the lib and calls one helper, the assertion checks stdout/stderr/exit. No mocks, no harness.
- **Pairing with the e2e layer.** The bats layer covers helper mechanics; the e2e layer covers the agent-dependent integration. The split is the same as the spec-0014 "structural over content" rule generalised to layer: bats can verify "helper X returns Y for input Z" because that's deterministic; only the e2e layer can verify "the spec-reviser agent emitted `^Q-DRIFT:` on a real-change revise" because that's model-driven. Pick the cheap layer first; only escalate ACs that genuinely need `claude -p`.
- **Canonical reference.** `commands/spec/revise.lib.sh` (574 lines, 13 helpers + `revise_error()` envelope) + `tests/hooks/spec-revise-preflight.bats` (933 lines, 53 tests covering every helper in isolation). Both files document the pure-function constraint inline; the lib's header comment names the bats file as the test oracle.

Sibling to the existing E2E language-fixture pattern and the verify.sh grep oracle: language fixtures exercise `speccraft-guard` against representative project layouts, `verify.sh` exercises documentation specs, and `commands/<group>/<name>.lib.sh` + bats exercises command-mechanism shell.

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

- **Slash commands (`commands/**.md`):** YAML frontmatter with `description:`, `argument-hint:`, and `allowed-tools:`. Fully qualified command names live in the filename path (e.g. `commands/spec/new.md` becomes `/speccraft:spec:new`). The `argument-hint:` field may be `""` for commands that take no positional arguments (e.g. `commands/spec/close.md`, `commands/spec/revise.md`); it MUST still be present as a key so the contract is uniform. `allowed-tools:` is a YAML list of the tools the command body uses. See "Markdown frontmatter contract tightening" below.
- **Subagents (`agents/*.md`):** YAML frontmatter with `name:`, `description:`, `tools:`, and `model:`. The `tools:` list is a YAML list of tool names the agent is permitted to call; `model:` is a non-empty model identifier (e.g. `opus`, `sonnet`). See "Markdown frontmatter contract tightening" below.
- **Skills (`skills/<name>/SKILL.md`):** YAML frontmatter with `name:` and `description:`.
- **Specs (`specs/NNNN-<slug>/spec.md`):** YAML frontmatter with `id`, `title`, `status`, `created`. `plan.md` and `tasks.md` mirror `id`. `changelog.md` is appended by `/speccraft:spec:close`.

### Markdown frontmatter contract tightening

Introduced by spec 0015.

The slash-command and subagent frontmatter contracts above are stricter than the pre-spec-0015 conventions, which mandated only `description:` for slash commands and only `name/description/tools` for subagents. The tightening reflects the de-facto convention already shipping in the repo: every file under `agents/*.md` (6/6) carries `model:` and every file under `commands/spec/*.md` (8/8) carries the `description/argument-hint/allowed-tools` triple. The previous understated rule meant new contributors could legitimately read the convention and ship a non-conforming file, then have it work by accident because the surrounding code happened to tolerate the gap.

- **Why this rule matters.** Slash command frontmatter is read by Claude Code's command registration logic; `allowed-tools:` materially constrains which tool calls the command body can make. Subagent frontmatter is read by the orchestrator dispatching the agent; `model:` materially constrains which model handles the invocation. Both fields are load-bearing at runtime, not optional documentation. Documenting them as required matches reality and prevents the next new-command author from skipping `allowed-tools:` and discovering at the wrong time that the runtime is silently permissive about the omission.
- **Asymmetric tooling enforcement.** This convention is currently advisory — there is no `enforce:` comment + drift scanner check against `agents/*.md` or `commands/**.md` frontmatter shape. The verify.sh oracle pattern (spec 0011) is the cheapest path to enforcement: any new agent or command spec can add `verify.sh` checks for its own frontmatter, as spec 0015's `specs/0015-spec-revise-command/verify.sh` does for `agents/spec-reviser.md` (AC11) and `commands/spec/revise.md` (AC12). A repo-wide enforcement pass is queued as a future spec.
- **Canonical references.** `agents/spec-reviser.md` (the file this convention tightening was authored alongside) and `commands/spec/revise.md` are the canonical reference files. Pre-existing agents and commands already conform — no migration is required.

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

### Mid-implementation amendment

Introduced by spec 0013.

When CI surfaces a defect between the implementation push and the close commit, and the defect is bounded and shares the active spec's theme, the issue MAY be folded into the active spec rather than filed as a follow-up. All three conditions must hold:

- **Strictly bounded edit.** Typically a single file, always a small additive change. Not a redesign.
- **CI stays red until it lands.** The issue blocks the spec's own close gate or a recently-closed predecessor's close gate. If main CI is green without the fix, file a follow-up spec instead.
- **Theme overlap.** The fix relates to the active spec's subject matter or to a predecessor spec the active spec is cleaning up after. Unrelated drive-by fixes go to their own spec.

When all three hold, fold the work in by:

1. Appending a dated `## Amendment (YYYY-MM-DD) — <one-line summary>` section to `spec.md` describing the trigger, the fix, and the rationale for folding-in rather than spinning off.
2. Adding the new task(s) to `tasks.md`. Out-of-order task numbering is acceptable when the amendment lands between already-checked tasks (e.g. T6 inserted after T4 but before the verification-gate T5 in spec 0013).
3. Adding any new acceptance criteria to `spec.md` numbered continuously with the existing ACs.
4. The `changelog.md` written at close calls out the amendment as an explicit deviation under "What shipped vs spec".

Spec 0013's T6 (the `.github/workflows/ci.yml` `hooks:` job fix) is the canonical example: the CI miss surfaced after the T1–T5 push, fix was one file, main CI was red until it landed, and the theme ("post-0012 cleanup") aligned. Filing a separate spec would have meant carrying a red main CI through a second spec-new / spec-plan cycle for a one-line workflow edit.

Counter-case: if a CI run surfaces a defect in a part of the codebase the active spec doesn't touch, file a follow-up spec even if the fix is bounded. The amendment path is for on-theme, on-author follow-ups, not arbitrary drive-bys.

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
- **Single-writer enforcement is layered (introduced by spec 0012).** The single-writer rule above is enforced at two layers, not one:
  - **Source-level:** the grep-based regression test `tools/internal/speccraft/state_single_writer_test.go` blocks any new compiled-in code path that writes `.speccraft/state.json` outside `speccraft-state` / `state.go`.
  - **Runtime:** the PreToolUse hook in `hooks/pre-tool-use.sh` rejects any `Edit`/`Write`/`MultiEdit`/`NotebookEdit` whose `file_path` canonicalises to `<root>/.speccraft/state.json`, catching the case a `claude -p` lifecycle session would otherwise use to bypass the source-level test by hand-editing at runtime.

  Both layers are load-bearing: source-level catches accidental code paths a code review missed; runtime catches in-session model workarounds the source tree never sees. Adding a future single-writer file under `.speccraft/` requires extending both — add the path to the grep allow-list **and** add the runtime branch in `pre-tool-use.sh`.
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
