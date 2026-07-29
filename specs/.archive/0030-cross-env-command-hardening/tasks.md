---
spec: "0030"
---

# Tasks

## Phase 1 — Self-resolving plugin root (Go) — AC1–AC5

- [x] T1 — RED: pluginroot_test.go (precedence a–f, symlink, none-resolvable, manifest predicate) + pluginroot_cmd_test.go (AC1–AC5)
- [x] T2 — GREEN: pluginroot.go (IsValidPluginRoot, ResolvePluginRootFrom, ResolvePluginRoot) + wire `case "plugin-root":` in main.go + usage (AC1–AC5)
- [x] T3 — REFACTOR: candidate validation already routed through the single IsValidPluginRoot predicate (env sources + each ascended ancestor); no duplication to collapse (AC2/AC4)

## Phase 2 — Command migration + convention lockstep + verify.sh — AC6, AC7

- [x] T4 — RED: add specs/0030-.../verify.sh grep oracle (AC6 forbidden+positive, AC7 convention, AC9 reserved-id, AC11 manifest, AC12 config); fails on main
- [x] T5 — GREEN: migrate 15 command docs + init.md to `PLUGIN_ROOT="$(speccraft-state plugin-root)"`; update conventions.md §Runtime sourcing (AC6, AC7 sections green)

## Phase 3 — zsh-safe libs — AC8, AC9, AC10

- [x] T6 — RED: add tests/hooks/lib-zsh-safety.bats (real-zsh source of every lib; preflight_status_gate draft→0 / closed→nonzero, no reserved diagnostic) (AC8, AC10)
- [x] T7 — GREEN: rename bare `status` → `spec_status` in revise.lib.sh preflight_status_gate (AC8/AC9/AC10 sections green)

## Phase 4 — Version bump — AC11

- [x] T8 — RED: version_test.go (state/guard/drift) assert 1.7.0 (rename Reports161→Reports170)
- [x] T9 — GREEN: bump const version + plugin.json + marketplace.json to 1.7.0; release via auto-tag → release.yml → verify-release.sh (AC11)

## Phase 5 — devcontainer — AC12

- [x] T10 — RED: verify.sh AC12 section pins SPECCRAFT_PLUGIN_ROOT in devcontainer.json (fails on main)
- [x] T11 — GREEN: add `"SPECCRAFT_PLUGIN_ROOT": "${containerWorkspaceFolder}"` to devcontainer.json containerEnv (AC12)

## Verify

- [x] T12 — Final VERIFY: go test ./... green, bats tests/hooks/ green, specs/0030-.../verify.sh fully green, real-zsh source of every lib clean, bash -n on edited shell

## Bypasses

Root cause for all three (T2): the guard's red-candidate capture reads
`tool_input.new_string` (Edit tool) but the **Write** tool sends `content`, so
the RED tests (authored via Write) registered zero candidates; compounded for
the new package by the compiled-language bootstrap (a brand-new Go symbol's test
can't compile → guard sees OutcomeBuildFailed, not a valid failing RED). Logged
as a new action-plan finding (guard Write-tool blind spot).

- 2026-07-24 — override: create tools/internal/speccraft/pluginroot.go (new ResolvePluginRootFrom/IsValidPluginRoot symbols).
- 2026-07-24 — override: wire `case "plugin-root"` into tools/cmd/speccraft-state/main.go.
- 2026-07-24 — override: add the plugin-root line to main.go usage() (cosmetic help text; no natural test — package already compiled+passed after the case was added, so no RED obtainable).
