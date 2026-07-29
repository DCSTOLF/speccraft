---
id: "0019"
title: "Bump version to 1.1.0"
status: closed
created: 2026-06-15
authors: [claude]
packages: []
related-specs: []
---

# Spec 0019 — Bump version to 1.1.0

## Why

speccraft has accumulated feature work beyond the 1.0.0 release (most recently
the real red→green TDD check for Go/Python/JS-TS in spec 0018). The published
plugin version and the binaries' `--version` output still report `1.0.0`,
which no longer distinguishes the current build from the initial release. Bumping
to 1.1.0 gives the next release a coherent, advertised version across every
surface a user or marketplace consumer reads.

## What

Update the version string from `1.0.0` to `1.1.0` in every authoritative,
live version surface:

- `.claude-plugin/plugin.json` — plugin manifest `version`
- `.claude-plugin/marketplace.json` — marketplace entry `version`
- `tools/cmd/speccraft-state/main.go` — `const version`
- `tools/cmd/speccraft-guard/main.go` — `const version`
- `tools/cmd/speccraft-drift/main.go` — `const version`

This keeps the plugin manifests and the three binaries' `--version` output in
sync at 1.1.0.

## Acceptance criteria

1. `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` both
   report `"version": "1.1.0"` and contain no remaining `1.0.0` version field.
2. Each of `speccraft-state`, `speccraft-guard`, and `speccraft-drift` declares
   `const version = "1.1.0"`, and invoking each binary with `--version` prints
   `1.1.0`.
3. The Go module still builds and its existing test suite passes after the bump
   (`go build ./...` and `go test ./...` succeed under `tools/`).

## Out of scope

- The historical `speccraft-v1-spec.md` document (its frontmatter `version: 1.0.0`
  and the example JSON at line 619) — these record the v1 spec, not the live
  plugin version, and are left unchanged.
- Build-time version injection via `-ldflags -X` (P2-5 in the technical review);
  this spec keeps the hardcoded `const version` mechanism and only changes its value.
- Any CHANGELOG, release notes, or git tag creation.

## Open questions

_none_
