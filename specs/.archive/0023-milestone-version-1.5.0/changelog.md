---
spec: "0023"
closed: 2026-06-22
---

# Changelog — 0023 Milestone version bump to 1.5.0

## What shipped vs spec

Coordinated 1.1.0 → 1.5.0 bump across all five live version surfaces, exactly as
spec 0019 did for the previous bump — hardcoded mechanism unchanged, only the
value moved:

- Manifests: `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`
  (AC1 — grep oracle: positive `1.5.0`, no stray `1.1.0`).
- Binary consts: `speccraft-{state,guard,drift}` `const version` (AC2), each
  pinned by its sibling version test asserting the NEW value (RED pre-edit →
  GREEN). `speccraft-state --version` prints `1.5.0`.
- `go test ./...` green (AC3).

Marks the spec-0022 milestone (PM + Architect upstream workflows). Pushing the
bumped `plugin.json` to `main` triggers the `auto-tag` CI job (spec 0021), which
pushes `v1.5.0` and fires `release.yml`.

## Deviations

None. Standard RED→GREEN on the three const tests; manifests verified by grep
oracle (not assertable from `package main`).

## Follow-ups

- Build-time `-ldflags` version injection (deferred since spec 0018) remains a
  future option; the hardcoded-const mechanism is retained.
