---
spec: "0030"
closed: 2026-07-24
---

# Changelog — 0030 Cross-environment command execution hardening

## What shipped vs spec

All 12 ACs implemented across the Go tier (resolver + subcommand + version
tests), the doc/config tier (`verify.sh` grep oracle), and the real-zsh tier
(bats). Two coupled command-execution defects — surfaced running speccraft as an
installed plugin in another project (macOS zsh, Python codebase) — fixed inside
existing surfaces plus one additive `speccraft-state` subcommand. Natural sequel
to spec 0029 (same first-use-in-another-repo, cross-shell/plumbing theme).

- **Self-resolving plugin root (AC1–AC5).** New pure resolver
  `tools/internal/speccraft/pluginroot.go`: `IsValidPluginRoot(dir)` (manifest-
  identity predicate — requires `.claude-plugin/plugin.json` + `bin/` +
  `commands/` + `templates/`), `ResolvePluginRootFrom(speccraftRoot, claudeRoot,
  exePath)` (injected-input core, table-testable), and the thin I/O wrapper
  `ResolvePluginRoot()`. Precedence: `SPECCRAFT_PLUGIN_ROOT` (must validate or
  hard-error) → `CLAUDE_PLUGIN_ROOT` (used only if it validates; the field bug —
  var pointing at the plugins *parent*, no manifest — is skipped, not fatal) →
  self-derivation (`os.Executable()` → `filepath.EvalSymlinks` → ascend to the
  nearest validating ancestor, handling both `<root>/bin/` and dogfood
  `<root>/tools/bin/` layouts). Wired as `speccraft-state plugin-root` in
  `tools/cmd/speccraft-state/main.go` + `usage()`. Pinned by 9 table cases in
  `pluginroot_test.go` (precedence a–f, symlink, none-resolvable error naming all
  sources, manifest-negative) + 2 subcommand cases in `pluginroot_cmd_test.go`.
- **Command-doc migration (AC6/AC7).** Every plugin-relative access in the 15
  command docs (`sync.md`, `pm/{new,review,prioritize,close}.md`,
  `spec/{close,new,review,review-code,revise}.md`, `arch/{review,new,decide,close}.md`,
  `history/compact.md`) migrated: `.lib.sh`/`templates/` sources go through
  `PLUGIN_ROOT="$(speccraft-state plugin-root)"`; bare `bin/speccraft-state X`
  invocations become bare `speccraft-state X` (reachable on `PATH`).
  `commands/init.md` migrated too — its empty-var fallback + alternative-locations
  block removed for the same resolve idiom, and Step 8's binary call made bare.
  `.speccraft/conventions.md` §Runtime sourcing updated in lockstep. Pinned by
  `specs/0030-.../verify.sh` (forbidden-pattern absence + positive-idiom +
  convention lockstep).
- **zsh-safe libs (AC8/AC9/AC10).** `commands/spec/revise.lib.sh`
  `preflight_status_gate` renamed its bare `status` local → `spec_status` (zsh
  reserves `status` as a read-only alias of `$?`; a bare `status` local aborted
  the first call with `read-only variable: status` when the lib is sourced into
  macOS zsh). New `tests/hooks/lib-zsh-safety.bats` runs REAL zsh over every
  `commands/**/*.lib.sh` (`zsh -uc "source <lib>"` exits 0, empty stderr) — the
  authoritative backstop — plus the two `preflight_status_gate` fixtures
  (draft→0, closed→non-zero, no reserved-var diagnostic) and a bash no-regression
  loop. `verify.sh` adds the static reserved-identifier grep guard over the pinned
  set.
- **Version 1.6.1 → 1.7.0 (AC11).** Additive-subcommand minor bump across the two
  manifests + three binary `const version` (each RED→GREEN via its sibling
  version test, `Reports161`/`Const161` → `…170`).
- **Devcontainer dogfood export (AC12).**
  `.devcontainer/devcontainer.json` `containerEnv` gains
  `"SPECCRAFT_PLUGIN_ROOT": "${containerWorkspaceFolder}"` so dogfood sessions
  resolve the working tree, not the stale `~/.claude/plugins/cache/.../1.1.0`
  copy first on `PATH`. Pinned by `verify.sh`.

## Files touched

- `tools/internal/speccraft/pluginroot.go` (new)
- `tools/internal/speccraft/pluginroot_test.go` (new)
- `tools/cmd/speccraft-state/pluginroot_cmd_test.go` (new)
- `tools/cmd/speccraft-state/main.go` (+`plugin-root` case, usage, version)
- `tools/cmd/speccraft-{guard,drift}/main.go` (version)
- `tools/cmd/speccraft-{state,guard,drift}/version_test.go` (1.7.0)
- `commands/init.md`, `commands/sync.md`
- `commands/spec/{close,new,review,review-code,revise}.md`
- `commands/spec/revise.lib.sh` (`status` → `spec_status`)
- `commands/pm/{new,review,prioritize,close}.md`
- `commands/arch/{new,review,decide,close}.md`
- `commands/history/compact.md`
- `.speccraft/conventions.md` (§Runtime sourcing lockstep), `.speccraft/index.md`
- `.claude-plugin/{plugin,marketplace}.json` (1.7.0)
- `.devcontainer/devcontainer.json` (`SPECCRAFT_PLUGIN_ROOT`)
- `tests/hooks/lib-zsh-safety.bats` (new)
- `specs/0030-cross-env-command-hardening/verify.sh` (new)

## Test coverage

`go test ./...` green (resolver precedence a–f + symlink + manifest-negative +
subcommand wiring + three version tests at 1.7.0); `bats tests/hooks` 142/0 (new
`lib-zsh-safety.bats` real-zsh + preflight + bash-backstop legs); `bash
specs/0030-.../verify.sh` fully green (AC6/AC7/AC9/AC11-manifest/AC12); every
`commands/**/*.lib.sh` sources clean under `zsh -uc`.

## Deviations

- **THREE `/speccraft:spec:override` were used — the plan predicted ZERO (T2).**
  Root cause: the guard's red-candidate capture reads `tool_input.new_string`
  (the Edit tool), but the RED test files were authored via the **Write** tool,
  which sends `content` — so those tests registered zero red-candidates.
  Compounded for the brand-new Go package by the compiled-language bootstrap: a
  brand-new symbol's test can't compile until the symbol exists, so the pre-edit
  run is `OutcomeBuildFailed`, which is correctly not treated as a valid RED. Net
  effect: no obtainable runtime RED for the three symbol-introduction edits, so an
  override was the sanctioned path (same class as spec 0018 AC13 / spec 0022 T3).
  The three: (1) create `tools/internal/speccraft/pluginroot.go`
  (`ResolvePluginRootFrom`/`IsValidPluginRoot`), (2) wire `case "plugin-root"`
  into `speccraft-state/main.go`, (3) add the `plugin-root` line to `usage()`
  (cosmetic; package already compiled+passed, no RED obtainable). This surfaced a
  NEW finding — the guard's **Write-tool blind spot** (`red_candidates` empty when
  the RED is authored via Write rather than Edit) — now tracked in the action plan.
  It is the recurring cost that overrides keep paying; the durable fix is the
  deferred apply-edit-in-memory red-check (and/or teaching `captureRedCandidates`
  to read the Write tool's `content`).
- **AC11's "published release" half is deferred to merge-time.** The source-level
  bump (manifests + three consts) and the sibling version tests are done and
  green. The published, self-verified `v1.7.0` GitHub Release is produced
  automatically when the bump lands on `main`: `auto-tag` (`ci.yml`) pushes
  `v1.7.0` via `RELEASE_TAG_PAT` → `release.yml` builds+publishes the four
  platform tarballs + `checksums.txt` → `scripts/verify-release.sh` self-verifies
  (per §Version bumps). This spec's close gate is that automated path completing,
  not a manual release — same deferral shape as prior version-bump specs.
- **Consolidation was NOT run on 0030's own close** — 0030 carries no
  `domains:`/`delta:` block and this repo still has no `specs/domains/` tree; per
  the inline-at-close contract that is a non-blocking decline (spec closes,
  nothing moves). Eligible for a future `/speccraft:sync` backfill if a domain
  layer is ever started here.

## ADR proposed for history.md

See the HISTORY-ADR section returned to the reviewer (dated 2026-07-24) — not
yet applied to `.speccraft/history.md`.

## Conventions proposed

Two proposals returned to the reviewer (not yet applied): (a) command docs MUST
resolve the plugin root via `PLUGIN_ROOT="$(speccraft-state plugin-root)"` and
never dereference bare `$CLAUDE_PLUGIN_ROOT` for `bin/`/`commands/`/`templates/`
paths; (b) `commands/**/*.lib.sh` must avoid zsh-reserved parameter names as
assigned variables (extends spec 0029's cross-shell lib convention). The
§Runtime sourcing entry already updated in lockstep (this cycle) covers the
`.lib.sh`-sourcing instance of (a); the dedicated convention generalizes it to
`templates/` paths and bare-binary calls.
