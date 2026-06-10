# speccraft

A Claude Code plugin that enforces spec-first TDD via hooks, slash commands, subagents, and cross-model review.

## Stack

- Bash 5+ hooks (`hooks/`) wired through `hooks/hooks.json`
- Go helper binaries under `tools/cmd/speccraft-{state,guard,drift}` sharing `tools/internal/{speccraft,delegate}` (module `github.com/dcstolf/speccraft/tools`; `go.mod` declares Go 1.22, CI runs Go 1.26.3)
- Markdown slash commands (`commands/`) and subagents (`agents/`)
- Markdown skills (`skills/<name>/SKILL.md`)
- Stack-agnostic memory templates (`templates/speccraft/`) copied into a host repo by `/speccraft:init`
- Devcontainer-based end-to-end test (`tests/e2e/run.sh`) driven by GitHub Actions (`.github/workflows/ci.yml`)

## Architecture in one paragraph

speccraft is packaged as a Claude Code plugin (`.claude-plugin/plugin.json`, marketplace `dcstolf-tools`) and ships three execution surfaces: shell hooks that gate Edit/Write tool calls, slash commands the user invokes (`/speccraft:init`, `/speccraft:spec:*`, `/speccraft:sync`), and subagents the orchestrator dispatches (planner, critic, reviewer, delegator, memory-keeper). Hooks and commands call small Go binaries — `speccraft-state` (session/spec state in `.speccraft/state.json`), `speccraft-guard` (TDD red→green invariant), and `speccraft-drift` (regex scan of `enforce:` rules in memory files) — whose shared logic lives in `tools/internal/speccraft`. The repo dogfoods its own plugin: `.speccraft/` here is real project memory for this very codebase, not a fixture.

## Hard rules (see guardrails.md)

- Never commit built binaries from `bin/` or `tools/bin/`.
- Never bypass the TDD red→green invariant without `/speccraft:spec:override` with a recorded reason.
- Plugin templates under `templates/speccraft/` must stay stack-agnostic (no Go-, Python-, or HTTP-specific assumptions).

## Where to look

- Hooks: `hooks/` (entry: `hooks/hooks.json`)
- Slash commands: `commands/` (top-level + `commands/spec/`)
- Subagents: `agents/`
- Skills: `skills/<name>/SKILL.md`
- Go helper binaries: `tools/cmd/speccraft-*/main.go`
- Shared Go logic: `tools/internal/speccraft/`, `tools/internal/delegate/`
- User-facing memory templates: `templates/speccraft/`
- E2E test harness: `tests/e2e/run.sh`
- Specs: `specs/NNNN-<slug>/`

## Active spec

none

## Recent decisions (last 3)

- 2026-06-10 — Runtime single-writer enforcement for state.json (spec 0012): `,omitempty` on `State.ActiveSpec` + `SetField` null/"" clear semantics; new `speccraft-state init` subcommand replaces literal-JSON Write in `commands/init.md`; `hooks/pre-tool-use.sh` gates `Edit|Write|MultiEdit|NotebookEdit` against `.speccraft/state.json` via `realpath -m` canonicalisation; three new conventions ("Single-writer enforcement is layered" + "`omitempty` for cleared-string state fields" + "PreToolUse hook tool enumeration"); 6 new bats cases under `tests/hooks/pre-tool-use-state-guard.bats`
- 2026-06-09 — Defer code-intel routing to user globals (spec 0011): SKILL.md/init.md/templates/architecture.md scrubbed of CodeGraphContext routing (one example mention retained as "such as CodeGraphContext"); new "External-tool boundaries" + "Grep-assertion oracle for doc-only specs" conventions; `verify.sh` grep-oracle pattern codified as sibling to E2E language-fixture pattern
- 2026-06-09 — JavaScript and TypeScript support (spec 0010): `IsJSTSTestFile` + `IsProductionJSTSFile` classifiers; `jsTsDispatch` with session-state-only sibling resolver; `prodGuardPrologue` tri-state helper extracted for gate symmetry; `javascript_cycle.sh` e2e fixture wired as step `[10/10]`
