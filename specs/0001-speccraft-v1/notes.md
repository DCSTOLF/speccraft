# Notes — speccraft v1 implementation

## Environment

- Container: Ubuntu 22.04, aarch64, Go 1.22.6
- Claude Code: v2.1.138
- Workspace: /workspaces/speccraft
- Git identity configured: Daniel Stolf <daniel.stolf@perforce.com>

## Things to verify outside container

- T0.4: Plugin load via `/plugin` — requires host VS Code with Claude Code extension
- T0.5.8: "host Claude Code unaffected during container teardown" — must be verified by user on host
- T4.10: Clean-machine binary install — needs a clean environment without Go to test download path

## Implementation decisions

- Phase 0.5 devcontainer files are already seeded in the repo; treat as partially done.
  Need to verify they're correct and that `bash tests/e2e/run.sh` exits 0.
- `speccraft-state find-root` walks up from cwd to nearest `.git`; this is the canonical
  way to locate the repo root. Not configurable in v1.
- Binary targets: linux-amd64, linux-arm64, macos-amd64, macos-arm64. Container is arm64.

## Gotchas

- `speccraft-guard` reads hook JSON from stdin. The exact JSON schema from Claude Code
  hooks must match what the Go binary expects. Verify with bats tests.
- `state.json` is gitignored — do not commit it.
- The `bin/` directory is gitignored except `.gitkeep`. Build artifacts go there only.
- The session-start hook must not fail on non-speccraft repos (graceful no-op).
