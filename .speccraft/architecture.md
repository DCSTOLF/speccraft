# Architecture

## Layering

speccraft is not a service; it is a Claude Code plugin. Its "layers" are execution surfaces, not request paths.

1. `.claude-plugin/plugin.json` + root `marketplace.json` — packaging entry exposed via the `dcstolf-tools` marketplace.
2. `hooks/` — Bash hook scripts (`session-start.sh`, `prompt-submit.sh`, `pre-tool-use.sh`, `post-tool-use.sh`, `stop.sh`) registered through `hooks/hooks.json`. Hooks are the only layer that runs without explicit user invocation.
3. `commands/` — Markdown slash commands. Top-level: `init.md`, `sync.md`. Spec lifecycle: `commands/spec/{new,plan,implement,review,review-code,delegate,close,override,revise}.md`. A command may colocate a sourceable Bash helper alongside its `.md` body using the `commands/<group>/<name>.lib.sh` pattern (introduced by spec 0015; first instance: `commands/spec/revise.lib.sh`). The `.md` body sources the lib at runtime; the bats suite under `tests/hooks/<name>.bats` sources the same file at test time. Helpers MUST be pure functions (no top-level side effects). This pattern is sibling to the `tools/cmd/speccraft-*` Go binary layer (item 6) but distinct: `.lib.sh` runs in-process inside the command's shell, not as a separately invoked binary.
4. `agents/` — Markdown subagent definitions: `spec-author`, `tdd-planner`, `spec-critic`, `cross-reviewer`, `aux-delegator`, `memory-keeper`.
5. `skills/<name>/SKILL.md` — model-loaded skills: `speccraft-context`, `spec-format`, `aux-agents`.
6. `tools/cmd/speccraft-{state,guard,drift}` — Go entrypoints, one binary each, that hooks and commands shell out to.
7. `tools/internal/speccraft/` — shared Go logic (state, config, files, root discovery, drift scan, Rust static recognition).
8. `tools/internal/speccraft/runner/` — language-neutral test-runner invocation primitive (Outcome enum, TestRecord, Runner interface, AdapterFor + AdapterForLanguage factories, crate fingerprint, pre-edit gate). Per-language adapters live here; Rust was the first concrete implementation (cargo + nextest). Spec 0018 extended the primitive to Go (`go test`), Python (`pytest`), and JS/TS (one shared `JSTSAdapter` driven by a configured command), so the red→green invariant is a real observed-failure check for all four languages — superseding spec 0005's original Rust-only validation boundary.
9. `tools/internal/speccraft/rusttok/` — Rust string/comment-aware tokenizer + `fn`-name extractor. Used by the Rust static-classification code in `tools/internal/speccraft/rust_*.go`.
10. `tools/internal/delegate/` — auxiliary-agent delegation config parsing (`agents.toml`).
11. `templates/speccraft/` — stack-agnostic Markdown templates copied into host repos by `/speccraft:init`.
12. `tests/e2e/run.sh` + `tests/hooks/` — devcontainer-based end-to-end and hook unit tests. `run.sh` supports two execution modes: the default lifecycle path (Go module setup, five `claude -p` invocations, then language fixtures) and `--language-only` mode (no `claude -p`, no API key), which exercises 10 per-language cycle fixtures (Go, Python, Rust×2, JS/TS — plus lifecycle). CI runs both as separate jobs (`e2e-devcontainer` and `e2e-language-only`) — see `.github/workflows/ci.yml`.

## Dependency direction

- Hooks and slash commands depend on Go binaries (`tools/bin/`), never the reverse.
- Go binaries under `tools/cmd/` depend on `tools/internal/`; `tools/internal/` packages never import `tools/cmd/`.
- `templates/speccraft/` must not depend on anything in this repo — it is copied verbatim into other projects.

## Key boundaries

- **Dogfooding boundary:** the `.speccraft/` directory at the repo root is *real* project memory describing this codebase. The user-facing templates live separately under `templates/speccraft/` and must stay stack-agnostic. Do not edit one when you mean the other.
- **Hook output contract:** hooks emit JSON on stdout per Claude Code's hook protocol. Any failure must exit non-zero with a clear stderr message.
- **State file boundary:** `.speccraft/state.json` is the single source of truth for active-spec and TDD session state, written only by `speccraft-state` (including the new `speccraft-state init` creation path). The single-writer rule is enforced at two layers since spec 0012: a source-level grep test (`tools/internal/speccraft/state_single_writer_test.go`) and a runtime PreToolUse hook check (`hooks/pre-tool-use.sh`) that rejects `Edit`/`Write`/`MultiEdit`/`NotebookEdit` calls targeting that path. Gitignored.
- **Plugin install path:** Claude Code resolves this plugin via `.claude-plugin/plugin.json`; do not introduce another entrypoint.
- **Dispatch-by-language pattern in `speccraft-guard`:** `tools/cmd/speccraft-guard/main.go` routes tool-use events through `dispatchByLanguage`, which delegates to per-language handlers. Currently supported: Go, Python, Rust, JavaScript, and TypeScript. Adding a new language is a localized change: implement `<lang>Dispatch` (reusing the shared `prodGuardPrologue` tri-state helper for the red-phase preamble), add a case to `dispatchByLanguage`, and extend `IsTestFile` in `tools/internal/speccraft/files.go`. The prologue helper was extracted in spec 0010 alongside the JS/TS dispatcher to keep gate semantics symmetric across languages. The open-coded language switch present before spec 0005 is gone.
- **Runner-invocation primitive boundary:** `tools/internal/speccraft/runner/` is the source of truth for "did a real test fail?" — the static file-classification step answers "did this edit add a test?" only. No language-specific code lives in `tools/cmd/speccraft-guard`; all runner detail (argv shape, output parsing, outcome classification) is owned by the per-language adapter in the runner package. The interface accepts a `Request{WorkDir, FullyQualifiedTestName}` and returns a normalized `Result{Outcome, Records, Stderr}`.

## Key decisions

See `history.md` for full ADR-style entries. Headlines:

- Plugin packaged via the `dcstolf-tools` marketplace, single plugin entry `speccraft`.
- Python TDD support added without forking the Go helper layout (specs 0002, 0003).
- Slash-command names fully qualified as `/speccraft:spec:*` to avoid collisions with host-repo commands.
- Rust language support introduces a shared **test-runner invocation primitive** (`tools/internal/speccraft/runner/`) and a **dispatch-by-language pattern** in `speccraft-guard` (spec 0005). Spec 0018 retired that spec's Rust-only scope: the primitive now backs a real red→green check for Go, Python, and JS/TS too (each production edit runs the session's just-added sibling test and requires an observed failure; an unresolved runner fails closed rather than falling back to a touch-check).
- CI is split into two jobs with different cost and credential profiles: `e2e-language-only` (cheap, hermetic, every push/PR, no API key) and `e2e-devcontainer` (expensive, gated to `push` on `main`, full `claude -p` lifecycle). Lifecycle-job failures classified by `classify_claude_failure` emit `ENVIRONMENT_FAILURE: <category>` lines so log triage distinguishes environmental issues from real defects. (spec 0008)

## Boundaries

- Inbound: user-invoked slash commands and Claude-Code-fired hooks.
- Outbound: Go helper binaries invoked via shell; aux-agent CLIs (`codex`, `opencode`, `claude -p`) per `.speccraft/agents.toml`.
