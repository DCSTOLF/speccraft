# Guardrails

Hard rules. Violations block at the hook level when `enforce:` is set.

## Security

- Never log secrets, API keys, tokens, or PII. <!-- enforce: regex pattern="(api[_-]?key|token|password|secret)\\s*[:=]" -->
- Never call `os/exec` with user-controlled input without an allowlist.
- All external HTTP calls must go through `internal/httpclient`.

## Data

- Never write SQL outside `internal/store/`. <!-- enforce: regex pattern="(?i)\\b(SELECT|INSERT|UPDATE|DELETE)\\b" scope="!internal/store/" -->
- Migrations are append-only. Never edit a committed migration file.

## Process

- Never bypass the spec-first invariant by editing files outside Claude Code.
- Never commit `.speccraft/state.json` (gitignored).
