# Changelog — Spec 0041 Release 1.12.0

Closed 2026-07-29. Minor version bump **1.11.0 → 1.12.0** bundling the design-0001
conductor arc (specs 0037–0040), each of which closed without a bump by design.

## What shipped

- 3 Go `const version` (speccraft-state/guard/drift) → `1.12.0`, each via the
  renamed-version-test TDD technique (`…Const1120`/`…Is1120`; stale-guard now rejects
  `1.11.0`) — no override.
- `manifest_version_test.go` → `…VersionIs1120` (want `1.12.0`, stale `1.11.0`).
- `.claude-plugin/plugin.json` + `marketplace.json` → `"version": "1.12.0"`.
- `go test ./...` + `go vet` green; `./bin` rebuilt; all three binaries report `1.12.0`.

## Deferred (maintainer action)

Pushing this bump + tagging `v1.12.0` triggers the existing auto-tag → release.yml →
verify-release.sh pipeline (spec 0021) that builds and publishes the release binaries.
Nothing here is pushed.
