# Contributing to speccraft

speccraft is dogfood: it's developed in a speccraft-managed repo. The `.speccraft/`
directory here is real project memory for this very codebase, not a fixture.

## Development environment

speccraft is developed inside its own devcontainer. This ensures that buggy hooks
under development can't lock up unrelated Claude Code sessions on your host machine.

**Prerequisites:** VS Code with the Dev Containers extension installed.

1. Clone the repo and open it in VS Code.
2. `Cmd+Shift+P` → `Dev Containers: Reopen in Container`. The container installs Go,
   the Rust toolchain (via rustup), `jq`, `bats`, and mock aux-agent CLIs
   automatically.
3. **Authenticate Claude Code inside the container** (one-time): run `claude` in the
   integrated terminal and complete the browser flow. The OAuth token lands in a named
   Docker volume and persists across `Rebuild Container`.
4. Start a Claude Code session *inside the container*. All hook development and testing
   happens here — never against the host.

## Running tests

```bash
# Go unit tests
cd tools && go test ./...

# Hook tests (bats)
bats tests/hooks/

# End-to-end lifecycle
bash tests/e2e/run.sh

# Fast, hermetic, no API key (language dispatch only)
bash tests/e2e/run.sh --language-only
```

`KEEP_TEST_DIR=1 bash tests/e2e/run.sh` preserves the throwaway module on failure for
inspection.

**Non-interactive e2e (CI / no browser):** run `claude setup-token` on the host, store
the result in `~/.env.devcontainer` (gitignored), and uncomment
`CLAUDE_CODE_OAUTH_TOKEN` in `.devcontainer/devcontainer.json`.

## Contributing a change

speccraft is built with itself:

1. `/speccraft:spec:new "<your change>"` to draft a spec.
2. `/speccraft:spec:review` to get cross-model critique.
3. `/speccraft:spec:plan` then `/speccraft:spec:implement`.
4. PR with the spec, plan, and implementation.

Before opening a PR, run:

```bash
go test ./tools/...
bash scripts/doctor.sh
```

## Hard rules

- Never commit built binaries from `bin/` or `tools/bin/`.
- Never bypass the TDD red→green invariant without `/speccraft:spec:override` with a
  recorded reason.
- Plugin templates under `templates/speccraft/` must stay stack-agnostic (no Go-,
  Python-, or HTTP-specific assumptions).

Issues and discussions welcome.
