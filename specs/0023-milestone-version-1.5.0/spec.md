---
id: "0023"
title: "Milestone version bump to 1.5.0"
status: closed
created: 2026-06-22
authors: [claude]
packages: []
related-specs: ["0019", "0022"]
---

# Spec 0023 — Milestone version bump to 1.5.0

## Why

Spec 0022 (optional PM and Architect workflows) is a significant milestone: the
plugin now ships three upstream surfaces above the spec lifecycle. Mark it with a
coordinated version bump 1.1.0 → 1.5.0 across all live version surfaces. Pushing
the bumped `plugin.json` to `main` triggers the `auto-tag` CI job (spec 0021),
which creates and pushes `v1.5.0`, firing `release.yml` to publish binaries.

## What

Coordinated 1.1.0 → 1.5.0 bump across every version surface, exactly as spec 0019
did for 1.0.0 → 1.1.0. The hardcoded mechanism is unchanged; only the value moves:

- The two packaging manifests: `.claude-plugin/plugin.json`,
  `.claude-plugin/marketplace.json`.
- The three binary `const version` declarations:
  `speccraft-{state,guard,drift}`.

Each const bump is pinned by its existing sibling version test (the test asserts
the NEW value, so it fails pre-edit — satisfying the TDD gate on a one-line const
change). `--version` parity across the three binaries stays test-pinned.

## Acceptance criteria

1. `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` both report
   version `1.5.0`, with no stray `1.1.0` left in either manifest.
2. `speccraft-{state,guard,drift}` each report `1.5.0` via their `const version`
   (and `speccraft-state --version` prints `1.5.0`), pinned by the sibling
   version tests.
3. `go test ./...` is green after the bump.

## Out of scope

- Build-time `-ldflags` version injection (deferred since spec 0018) — the
  hardcoded-const mechanism is retained.
- Any behavioral change to the binaries; this is a version-string bump only.

## Open questions

_none_
