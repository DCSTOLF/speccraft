---
id: "0041"
title: "Release 1.12.0 — design-0001 conductor arc"
status: closed
created: 2026-07-29
authors: [claude]
packages: ["tools/cmd/speccraft-state", "tools/cmd/speccraft-guard", "tools/cmd/speccraft-drift"]
related-specs: []
---

# Spec 0041 — Release 1.12.0 — design-0001 conductor arc

## Why

Specs 0037–0040 shipped the whole design-0001 conductor (workspace topology,
`ledger.md` + reconcile, the `/speccraft:arch:orchestrate` command, and crash-safe
re-entry), each closed without a version bump by design ("a release step can bundle
the arc"). This spec is that release step: a **minor** version bump `1.11.0 → 1.12.0`
(new backward-compatible surface — new `speccraft-state` subcommands and the new
`arch:orchestrate` command; nothing removed or broken). No behavior change beyond the
reported version; pushing the bump + tag triggers the existing auto-tag → release.yml
→ verify-release.sh pipeline (spec 0021).

## What — the six version locations

The single source pattern established by prior bumps (specs 0032/0034/0035/0036):
- **3 Go `const version`** — `tools/cmd/speccraft-{state,guard,drift}/main.go`.
- **3 grep/const oracles** — the sibling `version_test.go` for each binary, and
  `tools/internal/speccraft/manifest_version_test.go` (the JSON-manifest grep oracle).
- **2 JSON manifests** — `.claude-plugin/plugin.json` and
  `.claude-plugin/marketplace.json`.

Each version-test function name encodes the version (`…Const1110` / `…Is1110`), so a
bump **renames** the test (registering a fresh red-candidate under the TDD guard) and
updates its expectation to `1.12.0` — a runtime RED against the still-`1.11.0` const —
before the `const`/manifest edit makes it GREEN. The stale-version negative checks
advance to reject `1.11.0`.

## Acceptance criteria

1. **Binary consts.** `speccraft-state --version`, and the `version` const in
   `speccraft-guard`/`speccraft-drift`, all report `1.12.0`. Each binary's renamed
   `version_test.go` (`…Const1120` / `…Is1120`) asserts it; the stale-version guard
   rejects `1.11.0`.
2. **JSON manifests.** `.claude-plugin/plugin.json` and `marketplace.json` carry
   `"version": "1.12.0"`; `manifest_version_test.go` (renamed to `…VersionIs1120`,
   `want = "1.12.0"`, `stale = "1.11.0"`) is green.
3. **No stale `1.11.0`** remains in any of the six locations; `go test ./...` +
   `go vet` are green; the binaries rebuild to `./bin/`.

## Out of scope

- Any behavior/feature change — this is a version bump only.
- Pushing, tagging, and the CI release/publish (auto-tag → release.yml →
  verify-release.sh) — triggered by the maintainer pushing this bump.
- A major/minor policy change — 1.12.0 is a routine minor for the added,
  backward-compatible conductor surface.

## Open questions

_none — mechanical bump against a fixed six-location surface._
