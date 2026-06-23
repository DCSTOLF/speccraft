# Changelog — Spec 0026: Bump plugin version to 1.6.0

**Status:** closed · **Closed:** 2026-06-23

## What shipped

Coordinated `1.5.0` → `1.6.0` bump across all five live version surfaces, done
RED→GREEN per the spec-0023 lockstep convention:

| Surface | Change |
|---|---|
| `.claude-plugin/plugin.json` | `version` → `1.6.0` |
| `.claude-plugin/marketplace.json` | plugin `version` → `1.6.0` |
| `tools/cmd/speccraft-state/main.go` | `const version = "1.6.0"` |
| `tools/cmd/speccraft-guard/main.go` | `const version = "1.6.0"` |
| `tools/cmd/speccraft-drift/main.go` | `const version = "1.6.0"` |

Each binary const was pinned by its sibling `version_test.go`, updated to assert
`1.6.0` (RED against the pre-edit `1.5.0` const) before the const changed (GREEN).

This release ships the README/docs restructure (committed separately): README
slimmed to a hero + four differentiators, with detail split into `INSTALL.md`,
`docs/commands.md`, `docs/architecture.md`, and `CONTRIBUTING.md`.

## Acceptance criteria — all met

1. ✅ Both manifests report `1.6.0`; no stray `1.5.0` remains.
2. ✅ `const version == "1.6.0"` in all three binaries; `speccraft-state --version`
   prints `1.6.0`; each asserted by its sibling version test.
3. ✅ `cd tools && go test ./cmd/...` green.

## Deviations from spec

- **No `plan.md` / `tasks.md`.** A version-string bump is mechanical and identical
  in shape to spec 0023; it was executed directly rather than through the
  plan/implement loop.
- **Release tag not created by hand.** Per spec 0021, pushing the bumped
  `plugin.json` to `main` triggers the `auto-tag` CI job → `v1.6.0` → `release.yml`.

## Release trigger

Commit `6ea189e` (the `plugin.json` bump) is on `main`. The `auto-tag` job creates
and pushes `v1.6.0`, which fires `release.yml` to build and publish the per-platform
helper-binary tarballs.
