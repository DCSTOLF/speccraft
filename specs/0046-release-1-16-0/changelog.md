# Changelog — 0046 Release 1.16.0 — ledger write-locking

**Status:** closed · **Shipped in:** 1.16.0 · **Date:** 2026-08-04

## What shipped

The release-only spec that carries the `1.15.0 → 1.16.0` minor version bump for
spec 0045 (ledger write-locking). Six single-source locations bumped via the
renamed-version-test technique (specs 0032/0034/0035/0036/0041/0042/0043/0044
precedent):

- **3 Go `const version`** — `tools/cmd/speccraft-{state,guard,drift}/main.go`
  each `"1.15.0"` → `"1.16.0"`.
- **3 grep/const oracles** — sibling `version_test.go` in each cmd package
  (renamed `…Const1150`/`…Is1150` → `…Const1160`/`…Is1160`, stale-version
  negative check advanced to reject `1.15.0`) plus
  `tools/internal/speccraft/manifest_version_test.go` (renamed to
  `…VersionIs1160`, `want = "1.16.0"`, `stale = "1.15.0"`).
- **2 JSON manifests** — `.claude-plugin/plugin.json` and `marketplace.json`
  both `"version": "1.16.0"`.

## Verification

- `go test ./...` + `go vet` green.
- 282 bats green (`tests/hooks/`).
- Drift clean.
- Binaries rebuilt to `./bin/` — `speccraft-state --version`,
  `speccraft-guard --version`, `speccraft-drift --version` all report `1.16.0`.

## Release

Pushing + tagging `v1.16.0` triggers the auto-tag → release.yml →
verify-release.sh pipeline (spec 0021).
