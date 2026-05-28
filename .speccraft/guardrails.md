# Guardrails

Hard rules. Violations block at the hook level when `enforce:` is set. Rules without `enforce:` are advisory and checked at code review.

## Build artefacts

- Never commit compiled binaries from `bin/` or `tools/bin/`. Both are gitignored; do not `git add -f` them. (Advisory: path-based, not content-based; enforced by `.gitignore` + reviewer attention.)

## TDD invariant

- Never bypass the red→green invariant enforced by `speccraft-guard` except via `/speccraft:spec:override`, which records a reason in the spec's `changelog.md`.
- `speccraft-state` is the only writer of `.speccraft/state.json`. No hook, command, or test may edit it directly.

## Spec immutability

- Never modify `spec.md`, `plan.md`, or `tasks.md` for a spec whose status is `closed`. File a follow-up spec instead.

## Template purity

- `templates/speccraft/**` must stay stack-agnostic. Do not introduce Go-, Python-, HTTP-, or database-specific examples there. Real project memory for this repo lives in `.speccraft/` at the root, not in `templates/`.

## Hook contract

- Every hook script in `hooks/` must `set -euo pipefail` and exit non-zero on guardrail violation. Silent failure is a bug. (Advisory — this is a presence requirement, and `speccraft-drift` only flags forbidden patterns, not missing ones. Checked at code review.)

## Secrets

- Never log or echo API keys, tokens, or `ANTHROPIC_API_KEY` values. CI passes these via env; tests must not write them to stdout. <!-- enforce: regex pattern="(?i)(api[_-]?key|token|password|secret)\\s*[:=]\\s*['\"]" -->
