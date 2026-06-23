---
id: "0026"
title: "Bump plugin version to 1.6.0"
status: closed
created: 2026-06-23
authors: [claude]
packages: []
related-specs: ["0023", "0019"]
---

# Spec 0026 — Bump plugin version to 1.6.0

## Why

The README/docs were restructured (README slimmed to a sales-focused hero +
differentiators, with detail split into `INSTALL.md`, `docs/commands.md`,
`docs/architecture.md`, and `CONTRIBUTING.md`). Ship that as the 1.6.0 release.
Bumping `plugin.json` on `main` triggers the `auto-tag` CI job (spec 0021) →
`v1.6.0` → `release.yml`, which builds and publishes the helper-binary tarballs.

Version surfaces are kept in lockstep (spec 0023 convention): a tag must not
out-run the binary `const version` it ships, or `--version` and the tarball name
disagree.

## What

Coordinated `1.5.0` → `1.6.0` bump across all five live version surfaces:

- `.claude-plugin/plugin.json`
- `.claude-plugin/marketplace.json`
- `tools/cmd/speccraft-state/main.go` (`const version`)
- `tools/cmd/speccraft-guard/main.go` (`const version`)
- `tools/cmd/speccraft-drift/main.go` (`const version`)

Each binary const is pinned RED→GREEN by its sibling `version_test.go`, which is
updated to assert the new value before the const changes.

## Acceptance criteria

1. `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` both report
   `"version": "1.6.0"`, and no stray `1.5.0` remains in either manifest.
2. `const version == "1.6.0"` in all three of `speccraft-{state,guard,drift}`, and
   `speccraft-state --version` prints `1.6.0`; each is asserted by its sibling
   version test (which fails against the pre-edit `1.5.0` const).
3. `cd tools && go test ./...` passes with the three updated version tests green.

## Out of scope

- Any functional or behavioral change to the binaries or hooks.
- New features; this is a version-string bump only.

## Open questions

_none_
