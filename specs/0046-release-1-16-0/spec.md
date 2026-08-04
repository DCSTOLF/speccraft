---
id: "0046"
title: "Release 1.16.0 — ledger write-locking"
status: closed
created: 2026-08-04
authors: [claude]
packages: ["tools/cmd/speccraft-state", "tools/cmd/speccraft-guard", "tools/cmd/speccraft-drift"]
related-specs: ["0045"]
---

# Spec 0046 — Release 1.16.0 — ledger write-locking

## Why

Spec 0045 (ledger write-locking) shipped and closed without a version bump —
the version-bump work landed after `spec:close` had already flipped 0045 to
`closed`, so the closed-spec-immutability rule (spec 0036) rules out bumping
under 0045's own umbrella. This is that release step: a **minor** version bump
`1.15.0 → 1.16.0` (new backward-compatible surface — `.speccraft/ledger.lock`
sidecar, new `SPECCRAFT_LEDGER_LOCK_TIMEOUT` env; existing writer contracts
unchanged from the caller's POV). No behavior change beyond the reported
version; pushing the bump + tag triggers the existing auto-tag → release.yml
→ verify-release.sh pipeline (spec 0021).

## What — the six version locations

The single source pattern established by prior bumps (specs 0032/0034/0035/
0036/0041/0042/0043/0044):

- **3 Go `const version`** — `tools/cmd/speccraft-{state,guard,drift}/main.go`.
- **3 grep/const oracles** — the sibling `version_test.go` for each binary, and
  `tools/internal/speccraft/manifest_version_test.go` (the JSON-manifest grep
  oracle).
- **2 JSON manifests** — `.claude-plugin/plugin.json` and
  `.claude-plugin/marketplace.json`.

Each version-test function name encodes the version (`…Const1150` / `…Is1150`),
so a bump **renames** the test (registering a fresh red-candidate under the TDD
guard) and updates its expectation to `1.16.0` — a runtime RED against the
still-`1.15.0` const — before the `const`/manifest edit makes it GREEN. The
stale-version negative checks advance to reject `1.15.0`.

## Acceptance criteria

1. **Binary consts.** `speccraft-state --version`, and the `version` const in
   `speccraft-guard`/`speccraft-drift`, all report `1.16.0`. Each binary's
   renamed `version_test.go` (`…Const1160` / `…Is1160`) asserts it; the stale-
   version guard rejects `1.15.0`.
2. **JSON manifests.** `.claude-plugin/plugin.json` and `marketplace.json`
   carry `"version": "1.16.0"`; `manifest_version_test.go` (renamed to
   `…VersionIs1160`, `want = "1.16.0"`, `stale = "1.15.0"`) is green.
3. **No stale `1.15.0`** remains in any of the six locations; `go test ./...` +
   `go vet` are green; the binaries rebuild to `./bin/`.

## Out of scope

- Any behavior/feature change — this is a version bump only.
- Pushing, tagging, and the CI release/publish (auto-tag → release.yml →
  verify-release.sh) — triggered by the maintainer pushing this bump.
- A major/minor policy change — 1.16.0 is a routine minor for the added,
  backward-compatible ledger-lock surface.

## Open questions

_none — mechanical bump against a fixed six-location surface._
