# Conventions

## Go (`tools/`)

- Module path: `github.com/dcstolf/speccraft/tools`. Go 1.22 in `go.mod` (CI runs 1.26.3).
- One binary per subdirectory of `tools/cmd/`. Each has its own `main.go`; no shared `main` package.
- Shared logic lives in `tools/internal/speccraft/` (general) or `tools/internal/delegate/` (aux-agent dispatch). `tools/internal/` packages must not import `tools/cmd/`.
- Errors: wrap with `fmt.Errorf("...: %w", err)`. Sentinel errors live in the package that returns them.
- Logging from `tools/internal/`: return errors, do not print. CLI output (human-readable status, JSON results) belongs in `tools/cmd/*/main.go`. (Advisory — the drift tool can't distinguish real `fmt.Print*` calls from test fixtures that embed the string, so this is checked at code review rather than enforced via regex.)
- Tests: `_test.go` files colocated with the code under test; table-driven for >2 cases; function names start with `Test`. <!-- enforce: regex pattern="^func Test[A-Z]" scope="tools/**/*_test.go" -->

## Bash (`hooks/`, `tests/e2e/`, `scripts/`)

- Every script starts with `#!/usr/bin/env bash` and `set -euo pipefail`.
- Use absolute paths derived from `${BASH_SOURCE[0]}`; never assume CWD.
- All filesystem writes to `.speccraft/` go through the `speccraft-state` binary — hooks do not edit `state.json` directly.
- Hooks emit Claude Code hook-protocol JSON on stdout and exit non-zero on guardrail violations.

## Markdown frontmatter

- **Slash commands (`commands/**.md`):** YAML frontmatter with at minimum `description:`. Fully qualified command names live in the filename path (e.g. `commands/spec/new.md` becomes `/speccraft:spec:new`).
- **Subagents (`agents/*.md`):** YAML frontmatter with `name:`, `description:`, and `tools:`.
- **Skills (`skills/<name>/SKILL.md`):** YAML frontmatter with `name:` and `description:`.
- **Specs (`specs/NNNN-<slug>/spec.md`):** YAML frontmatter with `id`, `title`, `status`, `created`. `plan.md` and `tasks.md` mirror `id`. `changelog.md` is appended by `/speccraft:spec:close`.

## Spec lifecycle

- Spec IDs are zero-padded four-digit (`0001`, `0002`, …) and never reused.
- Closed specs (`status: closed`) are immutable. Corrections go in a follow-up spec.

## Templates (`templates/speccraft/`)

- Must remain stack-agnostic. No language- or framework-specific examples in default templates.
- Mirror the schema of the live `.speccraft/` files at the repo root, but with placeholder content.
