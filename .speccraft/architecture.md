# Architecture

## Layering

speccraft is not a service; it is a Claude Code plugin. Its "layers" are execution surfaces, not request paths.

1. `.claude-plugin/plugin.json` + root `marketplace.json` — packaging entry exposed via the `dcstolf-tools` marketplace.
2. `hooks/` — Bash hook scripts (`session-start.sh`, `prompt-submit.sh`, `pre-tool-use.sh`, `post-tool-use.sh`, `stop.sh`) registered through `hooks/hooks.json`. Hooks are the only layer that runs without explicit user invocation.
3. `commands/` — Markdown slash commands. Top-level: `init.md`, `sync.md`. Spec lifecycle: `commands/spec/{new,plan,implement,review,review-code,delegate,close,override}.md`.
4. `agents/` — Markdown subagent definitions: `spec-author`, `tdd-planner`, `spec-critic`, `cross-reviewer`, `aux-delegator`, `memory-keeper`.
5. `skills/<name>/SKILL.md` — model-loaded skills: `speccraft-context`, `spec-format`, `aux-agents`.
6. `tools/cmd/speccraft-{state,guard,drift}` — Go entrypoints, one binary each, that hooks and commands shell out to.
7. `tools/internal/speccraft/` — shared Go logic (state, config, files, root discovery, drift scan).
8. `tools/internal/delegate/` — auxiliary-agent delegation config parsing (`agents.toml`).
9. `templates/speccraft/` — stack-agnostic Markdown templates copied into host repos by `/speccraft:init`.
10. `tests/e2e/run.sh` + `tests/hooks/` — devcontainer-based end-to-end and hook unit tests.

## Dependency direction

- Hooks and slash commands depend on Go binaries (`tools/bin/`), never the reverse.
- Go binaries under `tools/cmd/` depend on `tools/internal/`; `tools/internal/` packages never import `tools/cmd/`.
- `templates/speccraft/` must not depend on anything in this repo — it is copied verbatim into other projects.

## Key boundaries

- **Dogfooding boundary:** the `.speccraft/` directory at the repo root is *real* project memory describing this codebase. The user-facing templates live separately under `templates/speccraft/` and must stay stack-agnostic. Do not edit one when you mean the other.
- **Hook output contract:** hooks emit JSON on stdout per Claude Code's hook protocol. Any failure must exit non-zero with a clear stderr message.
- **State file boundary:** `.speccraft/state.json` is the single source of truth for active-spec and TDD session state, written only by `speccraft-state`. It is gitignored.
- **Plugin install path:** Claude Code resolves this plugin via `.claude-plugin/plugin.json`; do not introduce another entrypoint.

## Key decisions

See `history.md` for full ADR-style entries. Headlines:

- Plugin packaged via the `dcstolf-tools` marketplace, single plugin entry `speccraft`.
- Python TDD support added without forking the Go helper layout (specs 0002, 0003).
- Slash-command names fully qualified as `/speccraft:spec:*` to avoid collisions with host-repo commands.

## Boundaries

- Inbound: user-invoked slash commands and Claude-Code-fired hooks.
- Outbound: Go helper binaries invoked via shell; aux-agent CLIs (`codex`, `opencode`, `claude -p`) per `.speccraft/agents.toml`.
