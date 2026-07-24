---
spec: "0030"
status: planned
strategy: tdd
---

# Plan — 0030 Cross-environment command execution hardening

Same shape as spec 0029: a Go binary change (new `plugin-root` subcommand) + a
bash-lib zsh-safety fix + a command-doc migration + a convention lockstep + a
version bump + a `verify.sh` grep oracle + real-zsh bats legs + a devcontainer
config. Sequenced so the **Go `plugin-root` subcommand + precedence tests come
first** (they are the foundation the doc migration depends on), then the doc
migration + convention lockstep + `verify.sh`, then the zsh rename + real-zsh
legs, then the version bump + its assertion tests, then devcontainer.

**No `/speccraft:spec:override` is needed anywhere.**
- The new Go code (`pluginroot.go`) is gated by `speccraft-guard`, but Step 1's
  failing `pluginroot_test.go` is the ordinary RED that precedes it — that IS the
  normal red→green path, not an override case.
- The const-version bump (`main.go`) is likewise preceded by its failing
  `version_test.go` (Step 8 RED before Step 9 GREEN).
- The doc-only / config-only surfaces — `commands/**/*.md`, `.speccraft/conventions.md`,
  `.claude-plugin/{plugin,marketplace}.json`, `.devcontainer/devcontainer.json` —
  are **not** Go, so they are outside the TDD gate. Each has **no natural Go/bats
  failing test**; it is pinned instead by an exact-form grep assertion in the new
  `specs/0030-.../verify.sh`, and that failing grep on `main` **is its RED**.

**RED preconditions confirmed at plan time (on `main`):**
- `bin/speccraft-state` has no `plugin-root` subcommand (`main.go` `switch` has no
  such `case`); `tools/internal/speccraft/pluginroot.go` does not exist.
- 8 libs under `commands/**/*.lib.sh`; `commands/spec/revise.lib.sh:53,55` declares
  and assigns a bare `status` local — `zsh -uc "source .../revise.lib.sh"` then
  `preflight_status_gate` aborts with `read-only variable: status` under `set -u`.
- 15 command docs under `commands/` dereference `$CLAUDE_PLUGIN_ROOT/{bin,commands,templates}`
  (grep-confirmed); `commands/init.md` additionally carries the empty-var fallback.
- `const version = "1.6.1"` in all three `tools/cmd/*/main.go`; `"version": "1.6.1"`
  in `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`.
- `.devcontainer/devcontainer.json` `containerEnv` has no `SPECCRAFT_PLUGIN_ROOT`.

## Test-first sequence

### Phase 1 — Self-resolving plugin root (Go foundation) — AC1–AC5

#### Step 1 — plugin-root resolver + subcommand tests (RED) — AC1, AC2, AC3, AC4, AC5
- Add `tools/internal/speccraft/pluginroot_test.go` (package `speccraft_test`,
  mirrors `root_test.go`/`files_test.go`). A `newValidRoot(t)` helper builds a
  fixture root under `t.TempDir()` containing `.claude-plugin/plugin.json`, `bin/`,
  `commands/`, `templates/`. Tests call the **pure** resolver
  `speccraft.ResolvePluginRootFrom(speccraftRoot, claudeRoot, exePath string)`
  (injected inputs — no `os.Getenv`/`os.Executable` I/O, so it is table-testable
  exactly like `FindRoot(dir)`):
  - `Test_ResolvePluginRoot_SelfDerive_BinLayout` — both env args empty, `exePath`
    = `<root>/bin/speccraft-state` → resolves `<root>` (AC2a, AC3: self-derivation
    alone suffices with both env unset).
  - `Test_ResolvePluginRoot_SelfDerive_ToolsBinLayout` — `exePath` =
    `<root>/tools/bin/speccraft-state`; ascent reaches the nearest validating
    ancestor `<root>` (AC2b, dogfood layout).
  - `Test_ResolvePluginRoot_ClaudeEnvInvalidParent_Skipped_SelfDeriveWins` —
    `claudeRoot` = the plugins *parent* (no manifest → invalid); it is skipped
    (not fatal) and self-derivation from `exePath` wins (AC2c, the field bug).
  - `Test_ResolvePluginRoot_SpeccraftEnvValid_WinsOverAll` — `speccraftRoot` = a
    valid root, `claudeRoot` = a *different* valid root, `exePath` under a third →
    `speccraftRoot` wins (AC2d).
  - `Test_ResolvePluginRoot_SpeccraftEnvInvalid_HardError` — `speccraftRoot` = an
    existing-but-invalid dir → error even though self-derivation *could* succeed
    (AC2e: the explicit override must validate or hard-error).
  - `Test_ResolvePluginRoot_SymlinkedExe_ResolvesRealInstall` — create a real
    symlink `link → <root>/bin/speccraft-state`, pass the link as `exePath`; assert
    the result is the real `<root>` (proves `filepath.EvalSymlinks` is applied
    unconditionally before ascending — AC4; `/proc/self/exe`-equivalent on Linux CI).
  - `Test_ResolvePluginRoot_NoneResolvable_ErrorNamesAllSources` — all env empty,
    `exePath` under a tree with no validating ancestor → error whose message names
    `SPECCRAFT_PLUGIN_ROOT`, `CLAUDE_PLUGIN_ROOT`, and self-derivation (AC1 failure
    contract).
  - `Test_IsValidPluginRoot_RequiresManifest` — a dir with `bin/`+`commands/`+
    `templates/` but **no** `.claude-plugin/plugin.json` → `false` (AC5 negative).
  - `Test_IsValidPluginRoot_AcceptsCompleteRoot` — the full fixture → `true`.
- Add `tools/cmd/speccraft-state/pluginroot_cmd_test.go` (package `main`, reuses the
  `makeRepo`/`runCmd` helpers used by `version_test.go`; sets env via `t.Setenv`):
  - `Test_StateCmd_PluginRoot_PrintsValidRoot_Exit0` — `t.Setenv("SPECCRAFT_PLUGIN_ROOT", <valid fixture>)`,
    run `plugin-root` → exit 0, stdout == the fixture's absolute path.
  - `Test_StateCmd_PluginRoot_Unresolvable_Exit1_NamesSources` — unset both env vars
    (`t.Setenv(..., "")`); `os.Executable()` (the test binary) has no validating
    ancestor → exit non-zero, stderr names each source tried.
- Tests fail: `speccraft.ResolvePluginRootFrom` / `IsValidPluginRoot` do not exist
  (compile error); `plugin-root` is an unknown subcommand (`Exit1`, stderr
  `unknown subcommand`) so the happy-path cmd test fails.

#### Step 2 — Implement the resolver + wire the subcommand (GREEN) — AC1, AC2, AC3, AC4, AC5
- Add `tools/internal/speccraft/pluginroot.go` (sibling to `root.go`):
  - `func IsValidPluginRoot(dir string) bool` — true iff `dir` contains all of
    `.claude-plugin/plugin.json` (regular file), `bin/`, `commands/`, `templates/`
    (dirs).
  - `func ResolvePluginRootFrom(speccraftRoot, claudeRoot, exePath string) (string, error)`
    — precedence: (1) if `speccraftRoot != ""` → validate or **error**; (2) if
    `claudeRoot != ""` and it validates → use it (else fall through); (3) self-derive:
    `p, _ := filepath.EvalSymlinks(exePath)`, then ascend `filepath.Dir(p)` to the
    nearest validating ancestor; (4) else `error` naming all three sources + why
    each failed. Factor the ascent as an unexported `ascendToValidRoot(dir)`.
  - `func ResolvePluginRoot() (string, error)` — thin I/O wrapper: reads
    `os.Getenv("SPECCRAFT_PLUGIN_ROOT")`, `os.Getenv("CLAUDE_PLUGIN_ROOT")`, calls
    `os.Executable()`, delegates to `ResolvePluginRootFrom`.
- Edit `tools/cmd/speccraft-state/main.go`: add `case "plugin-root":` that calls
  `speccraft.ResolvePluginRoot()`, prints the root to stdout on success, prints the
  error to stderr and returns 1 on failure; add the line to `usage()`.
- All Step-1 tests pass.

#### Step 3 — Refactor: share ascend/validate (optional) — AC2, AC4
- If `ResolvePluginRootFrom` and `ascendToValidRoot` duplicate the manifest-probe
  logic, collapse the probe into the single `IsValidPluginRoot` predicate so every
  candidate (env + each ascended ancestor) is validated through one function.
- All tests still pass.

### Phase 2 — Command migration + convention lockstep + verify.sh oracle — AC6, AC7 (and the AC9/AC11/AC12 grep pins land here, go green in later phases)

#### Step 4 — `specs/0030-.../verify.sh` grep oracle (RED on main) — AC6, AC7, AC9, AC11(manifest), AC12(config)
- Add `specs/0030-cross-env-command-hardening/verify.sh`, modeled on
  `specs/0029-.../verify.sh` (`set -euo pipefail`, `HERE`/`REPO_ROOT`, a
  `present`/`absent` helper pair, exit-0-all-pass, non-zero names each failing
  check). It pins:
  - **AC6 (forbidden pattern)** — `absent` over `commands -name '*.md'` (hooks/ are
    a different tree, so auto-exempt) of the exact form
    `\$\{?CLAUDE_PLUGIN_ROOT\}?/(bin|commands|templates)` — zero matches required.
  - **AC6 (positive form)** — each migrated doc that has a plugin-relative access
    contains the literal `PLUGIN_ROOT="$(speccraft-state plugin-root)"`.
  - **AC7 (convention lockstep)** — `.speccraft/conventions.md` §Runtime sourcing
    `present` the new `PLUGIN_ROOT="$(speccraft-state plugin-root)"` form and
    `absent` the old canonical `source "$CLAUDE_PLUGIN_ROOT/commands/<group>/<name>.lib.sh"`.
  - **AC9 (reserved-identifier grep guard)** — over `commands/**/*.lib.sh`, no
    pinned reserved identifier (`status pipestatus path cdpath fignore mailpath
    manpath fpath watch psvar signals argv histchars ARGC HISTCHARS`) appears as an
    **assigned** shell variable. The committed pattern pins the assignment grammar:
    bare `NAME=`, `local NAME`, `declare|typeset NAME`, `read ... NAME`, `for NAME in`
    — anchored to exclude comment/string false-positives. (Backstopped by AC8.)
  - **AC11 (manifest surfaces)** — `.claude-plugin/plugin.json` and
    `.claude-plugin/marketplace.json` each `present` `"version": "1.7.0"`.
  - **AC12 (config)** — `.devcontainer/devcontainer.json` `present` a
    `SPECCRAFT_PLUGIN_ROOT` entry in `containerEnv`.
- Tests fail on `main`: AC6/AC7 forbidden forms are present and the new form is
  absent; AC9 flags `revise.lib.sh`'s `status`; AC11 finds `1.6.1`; AC12 finds no
  devcontainer export. This single oracle is the RED for every doc/config-only
  surface; its sections go green across Steps 5, 7, 9, 11 (tracked below).

#### Step 5 — Migrate command docs + init.md + convention lockstep (GREEN → AC6/AC7) — AC6, AC7
- Rewrite every plugin-relative access in the 15 command docs under `commands/`
  (`sync.md`, `pm/{new,review,prioritize,close}.md`, `spec/{close,new,review,review-code,revise}.md`,
  `arch/{review,new,decide,close}.md`, `history/compact.md`) to resolve
  `PLUGIN_ROOT="$(speccraft-state plugin-root)"` once, before the first
  plugin-relative access, exiting non-zero if it fails; replace each
  `$CLAUDE_PLUGIN_ROOT/{bin,commands,templates}/...` with `$PLUGIN_ROOT/...`.
- Migrate `commands/init.md`: replace Step 1's `echo "${CLAUDE_PLUGIN_ROOT:-}"`
  discovery + empty-var fallback (Step 1's alternative-locations block) with the
  same `PLUGIN_ROOT="$(speccraft-state plugin-root)"` resolution, and change Step 8's
  `"$CLAUDE_PLUGIN_ROOT/bin/speccraft-state" init` to `speccraft-state init` (bare;
  `bin/` is on `PATH` before any command runs, so no separate init bootstrap is
  needed — the init-ordering question resolves to "no exception required").
- Update `.speccraft/conventions.md` §Runtime sourcing (line 187) to prescribe
  `PLUGIN_ROOT="$(speccraft-state plugin-root)"` + `source "$PLUGIN_ROOT/commands/<group>/<name>.lib.sh"`,
  removing the old `$CLAUDE_PLUGIN_ROOT` form as the canonical example.
- `verify.sh` AC6 + AC7 sections pass. (AC9/AC11/AC12 sections remain RED pending
  Steps 7/9/11.)

### Phase 3 — zsh-safe libs — AC8, AC9, AC10

#### Step 6 — real-zsh source leg + preflight fixture leg (RED) — AC8, AC10
- Add `tests/hooks/lib-zsh-safety.bats` (mirrors 0029's real-zsh leg in
  `spec-consolidate.bats`; `PLUGIN_DIR` resolved from `$BATS_TEST_FILENAME`):
  - `Test_all_command_libs_source_under_real_zsh` — fail LOUD if `zsh` absent
    (`command -v zsh || { echo 'zsh required — never silent-skip'; false; }`); for
    **each** `commands/**/*.lib.sh`, run `zsh -uc "source '$lib'"` and assert exit 0
    **and** empty stderr (AC8).
  - `Test_all_command_libs_source_under_bash_unchanged` — same loop under
    `bash -uc` exits 0 (no-regression backstop).
  - `Test_revise_preflight_status_gate_zsh_draft_returns_0_no_reserved_diagnostic`
    — seed a `status: draft` `spec.md` fixture; run
    `zsh -uc "source '$REVISE_LIB'; preflight_status_gate '$fixture'"`; assert exit 0
    and stderr contains **no** `read-only variable` (nor any pinned reserved-name
    diagnostic) (AC10).
  - `Test_revise_preflight_status_gate_zsh_closed_returns_nonzero_no_reserved_diagnostic`
    — `status: closed` fixture; assert non-zero exit **and** no reserved-name
    diagnostic on stderr (the failure is the status gate, not the zsh abort) (AC10).
- Tests fail on `main`: `revise.lib.sh` declares a bare `status` local, so under
  `zsh -u` the source/first-call aborts with `read-only variable: status` — both the
  AC8 loop (for `revise.lib.sh`) and both AC10 cases fail. (The AC9 grep guard added
  to `verify.sh` in Step 4 is also RED on `main` for the same root cause.)

#### Step 7 — Rename the zsh-reserved local (GREEN → AC8/AC9/AC10) — AC8, AC9, AC10
- Edit `commands/spec/revise.lib.sh` `preflight_status_gate` (lines 53–68): rename
  the `status` local to `spec_status` at its `local` declaration (53), its
  assignment (55), the `case "$spec_status" in` (56), and both stderr messages
  (61, 65). Pure rename; behavior unchanged.
- Step-6 bats tests pass (real-zsh source clean, both preflight cases correct with
  no reserved diagnostic); `verify.sh` AC9 section goes green. No CI change needed —
  the `hooks` job already runs `bats tests/hooks/` and already installs `zsh`
  (spec 0029, `ci.yml:70-73`), so the new file runs faithfully.

### Phase 4 — Version bump — AC11

#### Step 8 — Version-assertion tests to 1.7.0 (RED) — AC11
- Edit `tools/cmd/speccraft-state/version_test.go`: rename
  `Test_StateCmd_Version_Reports161` → `Test_StateCmd_Version_Reports170` and assert
  `"1.7.0"`.
- Edit `tools/cmd/speccraft-guard/version_test.go` and
  `tools/cmd/speccraft-drift/version_test.go`: assert `version == "1.7.0"`.
- Tests fail: the three `const version` are still `"1.6.1"`.

#### Step 9 — Bump all version surfaces to 1.7.0 (GREEN → AC11) — AC11
- Set `const version = "1.7.0"` in `tools/cmd/speccraft-state/main.go`,
  `tools/cmd/speccraft-guard/main.go`, `tools/cmd/speccraft-drift/main.go`.
- Set `"version": "1.7.0"` in `.claude-plugin/plugin.json` and
  `.claude-plugin/marketplace.json`.
- Step-8 Go tests pass; `verify.sh` AC11 manifest section goes green.
- **"Done" is the published, self-verified `v1.7.0` release, not the edited
  consts.** Per `.speccraft/conventions.md` §Version bumps: this bump landing on
  `main` triggers `auto-tag` (pushes `v1.7.0` via the `RELEASE_TAG_PAT`) →
  `release.yml` (builds+publishes the four platform tarballs + `checksums.txt`) →
  `scripts/verify-release.sh` self-verify. Do **not** hand-build tarballs or push
  the tag manually; the close gate is that automated path completing.

### Phase 5 — devcontainer dogfood export — AC12

#### Step 10 — devcontainer config pin (RED) — AC12
- (No natural Go/bats test for a JSON config edit.) The RED is the `verify.sh` AC12
  section from Step 4, which asserts `SPECCRAFT_PLUGIN_ROOT` appears in
  `.devcontainer/devcontainer.json` `containerEnv` — failing on `main`.

#### Step 11 — Export SPECCRAFT_PLUGIN_ROOT in the devcontainer (GREEN → AC12) — AC12
- Edit `.devcontainer/devcontainer.json` `containerEnv`: add
  `"SPECCRAFT_PLUGIN_ROOT": "${containerWorkspaceFolder}"` (= `/workspaces/speccraft`,
  the checked-out working tree — which is itself a valid plugin root: it has
  `.claude-plugin/plugin.json`, `bin/`, `commands/`, `templates/`). This overrides
  the stale `~/.claude/plugins/cache/.../1.1.0` copy on `PATH` for dogfood sessions.
- `verify.sh` AC12 section goes green; the runtime assertion — inside the
  devcontainer, `speccraft-state plugin-root` == repo root (`/workspaces/speccraft`)
  — holds (verified on next container rebuild).

### Step 12 — Final VERIFY (all green together)
- `go test ./...` in `tools/` green (resolver precedence + predicate + cmd wiring +
  three version tests at 1.7.0).
- `bats tests/hooks/` green (new `lib-zsh-safety.bats` real-zsh + preflight legs;
  existing suites untouched-green).
- `bash specs/0030-.../verify.sh` fully green (AC6, AC7, AC9, AC11-manifest, AC12).
- `zsh -uc "source '<each commands/**/*.lib.sh>'"` exits 0 with empty stderr.
- `bash -n` on `revise.lib.sh` and `specs/0030-.../verify.sh`; every migrated
  command `.md` still documents a runnable resolve-then-use sequence.

## Delegation

- Steps 1–3 (Go resolver + subcommand) → keep in the implementing thread; pure Go,
  table-driven, tightest RED→GREEN loop, gated by `speccraft-guard`.
- Steps 4–5 (verify.sh oracle + doc/convention migration) → keep in-thread; the
  migrated command bodies and convention prose are load-bearing against the exact
  `present`/`absent` regexes and must be authored against them.
- Steps 6–7 (zsh bats legs + rename) → keep in-thread; deterministic shell, mirrors
  the 0029 real-zsh pattern.
- Steps 8–9 (version bump) → keep in-thread; the release itself is produced by the
  automated `auto-tag → release.yml → verify-release.sh` pipeline, not by hand.
- Steps 10–11 (devcontainer) → keep in-thread; one-line config edit pinned by
  verify.sh.

## Risk

- **`os.Executable()`/`EvalSymlinks` untestable if resolution does its own I/O** →
  mitigation: the core `ResolvePluginRootFrom(speccraftRoot, claudeRoot, exePath)`
  takes injected inputs (exactly like `FindRoot(dir)`); a thin `ResolvePluginRoot()`
  wrapper does the `os.Getenv`/`os.Executable` I/O. The symlink case (AC4) is proved
  with a real tmp symlink, not a mock.
- **Stale-1.1.0 `speccraft-state` on `PATH` self-derives to the wrong old tree while
  dogfooding** (documented limitation, not a defect) → mitigation: AC12's
  `.devcontainer` `SPECCRAFT_PLUGIN_ROOT` export overrides it for this repo; the
  precedence rule makes the override authoritative (Step 2, case 1).
- **AC6 grep false-positive on `hooks/` (which is exempt) or on a legitimately
  different form** → mitigation: scope the `absent` grep to `commands -name '*.md'`
  (hooks live in a separate tree) and pin the exact
  `\$\{?CLAUDE_PLUGIN_ROOT\}?/(bin|commands|templates)` form.
- **AC9's curated reserved-identifier list is not exhaustive** → mitigation: AC8's
  real-zsh `source` leg over every lib is the authoritative backstop — any reserved
  name the static grep misses still fails `zsh -uc "source <lib>"`.
- **Treating the const/manifest edit as "done" and skipping the published release**
  → mitigation: Step 9 states the close gate is the published, self-verified
  `v1.7.0` release via the existing `auto-tag → release.yml → verify-release.sh`
  path, triggered by the bump landing on `main`; no manual tarballs.
- **init-time ordering** (is `speccraft-state` on `PATH` before `init.md` runs?) →
  resolved in Step 5: `bin/` is on `PATH` before any command runs, so bare
  `speccraft-state` works and no init bootstrap path is required; if that proved
  false it would become an explicit sub-task, not a silent exception.

## AC coverage

| AC | Step(s) |
| --- | --- |
| AC1 (prints valid root / names sources on failure) | 1, 2 |
| AC2 (precedence, table-driven a–f) | 1, 2, 3 |
| AC3 (self-derivation alone with both env unset) | 1 (BinLayout case), 2 |
| AC4 (EvalSymlinks before ascend) | 1 (Symlink case), 2 |
| AC5 (manifest-identity negative predicate) | 1, 2 |
| AC6 (no bare `$CLAUDE_PLUGIN_ROOT` deref; init.md migrated) | 4, 5 |
| AC7 (convention lockstep) | 4, 5 |
| AC8 (real-zsh source of every lib) | 6, 7 |
| AC9 (reserved-identifier grep guard) | 4, 7 |
| AC10 (preflight_status_gate zsh fixture) | 6, 7 |
| AC11 (version bump 1.7.0 + sibling tests + published release) | 4, 8, 9 |
| AC12 (devcontainer SPECCRAFT_PLUGIN_ROOT) | 4, 10, 11 |
