---
spec: "0019"
closed: 2026-06-15
---

# Changelog — 0019 Bump version to 1.1.0

## What shipped vs spec

- Bumped 1.0.0 → 1.1.0 across every live version surface: both packaging manifests and the three binary `const version` declarations. Implemented exactly as specified; no deviations.
- AC1: `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` both report `"version": "1.1.0"`; no remaining 1.0.0 version field (grep oracle, positive + negative).
- AC2: speccraft-state/guard/drift each declare `const version = "1.1.0"`; `--version` prints 1.1.0 (pinned by new sibling tests).
- AC3: `go build ./...` and `go test ./...` green under `tools/`.
- Out of scope (unchanged): `speccraft-v1-spec.md` historical doc, `-ldflags` version injection (P2-5), CHANGELOG/git tags.

## Files touched

- `.claude-plugin/plugin.json`
- `.claude-plugin/marketplace.json`
- `tools/cmd/speccraft-state/main.go`
- `tools/cmd/speccraft-guard/main.go`
- `tools/cmd/speccraft-drift/main.go`
- `tools/cmd/speccraft-state/version_test.go` (new — asserts `--version` output via `run()` seam)
- `tools/cmd/speccraft-guard/version_test.go` (new — asserts package const)
- `tools/cmd/speccraft-drift/version_test.go` (new — drift's first test file; asserts package const)
- `.speccraft/index.md` (active-spec pointer)

## ADR proposed for history.md

See history.md entry — version-bump policy + first-test-file note for the drift binary.

## Conventions

- New: "On a version bump, pin the new value with a sibling test (`--version` output or the package `const`) so the const edit goes through a real RED→GREEN cycle and version parity across binaries stays asserted." Emerged directly from this spec.
