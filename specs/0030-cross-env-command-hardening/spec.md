---
id: "0030"
title: "Cross-environment command execution hardening"
status: closed
created: 2026-07-24
revision: 1
authors: [claude]
packages: ["tools/cmd/speccraft-state", "tools/internal/speccraft", "commands", "hooks"]
related-specs: ["0015", "0029"]
---

# Spec 0030 — Cross-environment command execution hardening

## Why

Running speccraft as an *installed plugin* (not dogfooded in this repo) in
another project — macOS default `zsh`, a Python codebase — surfaced two
coupled command-execution defects that block core commands outside the Go/bash
devcontainer they were developed in. Both are portability/plumbing bugs
invisible to the current e2e harness. Direct precedent: spec 0029 (zsh
portability + first-use-in-another-repo defects).

- **(A) Plugin-root resolution is unreliable for slash commands.** Command
  docs run bash that dereferences `"$CLAUDE_PLUGIN_ROOT/bin/speccraft-state"`
  and `source "$CLAUDE_PLUGIN_ROOT/commands/.../*.lib.sh"`. But
  `CLAUDE_PLUGIN_ROOT` is only *contractually* exported as an env var to
  **hook** subprocesses (`hooks.json`); for the bash the model runs on behalf
  of a **slash command** it is not guaranteed to be set. In the field it
  resolved to the plugins *parent* directory, not the versioned plugin dir, so
  every `bin/`, `commands/`, and `templates/` path failed. This affected
  `revise`, `review`, and `plan` in one session and by inspection also
  `sync`, `close`, `pm/*`, `arch/*`, `new`, and `history/compact`.
  `commands/init.md` already fallback-guards the variable; no other command
  does.

- **(B) `revise.lib.sh` is not zsh-safe when sourced.** The lib declares a
  bare `status` local, which zsh reserves (`read-only variable: status`),
  aborting the very first `preflight_status_gate` call when the lib is sourced
  into the default macOS interactive shell. The `#!/usr/bin/env bash` shebang
  and `set -euo pipefail` do not help — a *sourced* lib runs in the caller's
  shell, which is zsh.

**Cross-model review (codex + claude-p, 2026-07-24) confirmed a third,
concrete hazard** that the first draft under-specified: `speccraft-state` on
`PATH` in *this* repo resolves to a **stale installed cache copy at v1.1.0**
(`~/.claude/plugins/cache/dcstolf-tools/speccraft/1.1.0/bin/speccraft-state`),
not the repo's own binary. So a naive "parent of `bin/`" self-derivation
resolves to the wrong, old plugin tree while developing. Resolution precedence
across multiple installed versions and dogfood-vs-installed layouts is
therefore load-bearing and is specified explicitly below (see `## What` →
*Resolution precedence*).

## What

Make speccraft's commands execute correctly regardless of (i) whether
`CLAUDE_PLUGIN_ROOT` is present in the slash-command bash environment, (ii)
which of several installed plugin versions is on `PATH`, and (iii) whether the
sourcing shell is bash or zsh.

### Self-resolving plugin root

Add a `speccraft-state plugin-root` subcommand (`tools/cmd/speccraft-state`,
logic in `tools/internal/speccraft`) that prints the plugin's own install
directory and validates it. Command docs invoke it bare (reliable via the
`bin/`-on-`PATH` guarantee) and resolve `PLUGIN_ROOT="$(speccraft-state
plugin-root)"` once, before their first plugin-relative access, failing fast if
it errors — replacing every bare `$CLAUDE_PLUGIN_ROOT/{bin,commands,templates}`
dereference in command docs.

**Root validity predicate.** A candidate directory is a valid plugin root iff
it contains **all** of: `.claude-plugin/plugin.json`, `bin/`, `commands/`, and
`templates/`. The manifest file is the identity anchor — a coincidentally
shaped directory (has the three subdirs but no manifest) is rejected.

**Resolution precedence** (first validating candidate wins; a *set-but-invalid*
source is skipped, not fatal, except the explicit override):

1. `$SPECCRAFT_PLUGIN_ROOT` — explicit developer/override env var. If set, it
   **must** validate or `plugin-root` errors (an override that doesn't point at
   a real root is a misconfiguration, not something to silently ignore).
2. `$CLAUDE_PLUGIN_ROOT` — if set **and** it validates. Validation here is what
   auto-rejects the observed field bug (the var pointing at the plugins
   *parent*, which has no `.claude-plugin/plugin.json`): it fails validation and
   we fall through.
3. **Self-derivation** — `os.Executable()`, passed through
   `filepath.EvalSymlinks`, then ascend parent directories to the **nearest
   ancestor that validates**. The ascent (rather than a fixed "parent of
   `bin/`") transparently handles both the installed layout
   (`<root>/bin/speccraft-state`) and the dogfood layout
   (`<root>/tools/bin/speccraft-state` or `<root>/bin/speccraft-state`).
4. Otherwise: exit non-zero with a stderr message naming each source tried and
   why it failed.

**Documented limitation (accepted, not a defect):** if *both*
`SPECCRAFT_PLUGIN_ROOT` and `CLAUDE_PLUGIN_ROOT` are unset and `PATH` resolves
`speccraft-state` to a different-version install than intended (the stale-1.1.0
case above), `plugin-root` reflects the invoked binary's own install. Set
`SPECCRAFT_PLUGIN_ROOT` to override. This is called out so it is a known,
one-line-fixable dev footgun rather than a silent wrong answer. To close the
footgun for this repo's own dogfooding, `.devcontainer` exports
`SPECCRAFT_PLUGIN_ROOT` pointing at the working tree so dogfood sessions never
resolve to the stale cache copy (see AC12).

### zsh-safe libs

Rename every zsh-reserved plain-variable name in all `commands/**/*.lib.sh`,
and add an exact-form grep guard (mirroring spec 0029's `${BASH_SOURCE[0]:-$0}`
guard) plus a real-zsh source leg so a regression is caught mechanically.

### Convention & version lockstep

Update the sourceable-command-helper convention in `.speccraft/conventions.md`
in the *same* change (paired-update discipline), and bump the plugin version
with a sibling version-assertion test, mirroring 0029.

## Acceptance criteria

**Plugin-root resolution.**

1. `speccraft-state plugin-root` prints the absolute path of a directory that
   satisfies the root-validity predicate (contains `.claude-plugin/plugin.json`,
   `bin/`, `commands/`, and `templates/`) and exits 0 when a valid root is
   resolvable from any working directory; when none is resolvable it exits
   non-zero with a stderr message that names each source it tried
   (`SPECCRAFT_PLUGIN_ROOT`, `CLAUDE_PLUGIN_ROOT`, self-derivation) and why each
   failed.

2. Resolution follows the documented precedence exactly, verified by
   table-driven Go tests over a fixture tree covering at least: (a)
   `CLAUDE_PLUGIN_ROOT` unset, binary under `<root>/bin/`; (b)
   `CLAUDE_PLUGIN_ROOT` unset, binary under `<root>/tools/bin/` (dogfood
   layout) — both resolve to `<root>`; (c) `CLAUDE_PLUGIN_ROOT` set to the
   plugins *parent* (the field bug: no manifest) → skipped, self-derivation
   wins; (d) `SPECCRAFT_PLUGIN_ROOT` set to a valid root → wins over all else;
   (e) `SPECCRAFT_PLUGIN_ROOT` set to an invalid path → hard error; (f) the
   binary reached via a symlink → resolves to the real install (see AC4).

3. `speccraft-state plugin-root` resolves a valid root with `CLAUDE_PLUGIN_ROOT`
   (and `SPECCRAFT_PLUGIN_ROOT`) unset in the environment — i.e. self-derivation
   alone suffices — verified by unsetting both before the call.

4. Self-derivation passes the `os.Executable()` result through
   `filepath.EvalSymlinks` before ascending, so a symlinked launcher resolves
   to the real install directory; this is asserted on the Linux CI leg
   (`/proc/self/exe`) and the EvalSymlinks call is unconditional so macOS
   (`_NSGetExecutablePath`, which may return the invoking symlink path) behaves
   identically.

5. A directory containing `bin/`, `commands/`, and `templates/` but **not**
   `.claude-plugin/plugin.json` is rejected by the validity predicate (negative
   test).

**Command migration.**

6. No command document under `commands/` contains a `$CLAUDE_PLUGIN_ROOT` or
   `${CLAUDE_PLUGIN_ROOT}` dereference for a `bin/`, `commands/`, or
   `templates/` path; each such site instead resolves
   `PLUGIN_ROOT="$(speccraft-state plugin-root)"` once before its first
   plugin-relative access and exits non-zero if that resolution fails. Enforced
   by an exact-form grep guard (a committed `verify.sh` or bats assertion) that
   pins the forbidden pattern. Hook scripts under `hooks/` (which *do* reliably
   receive the env var) are exempt. `commands/init.md` is **migrated** to the
   same `speccraft-state plugin-root` form; its existing empty-var fallback is
   removed, and because `speccraft-state` is on `PATH` via the plugin's `bin/`
   before any command runs, no separate init bootstrap path is required (if
   init-time ordering proves otherwise during planning, that becomes an
   explicit sub-task, not a silent exception).

7. The sourceable-command-helper convention entry in `.speccraft/conventions.md`
   is updated in this same change to prescribe the
   `PLUGIN_ROOT="$(speccraft-state plugin-root)"` form; a grep asserts the old
   `source "$CLAUDE_PLUGIN_ROOT/commands/<group>/<name>.lib.sh"` prescription no
   longer appears as the canonical example.

**zsh safety.**

8. For every `commands/**/*.lib.sh`, `zsh -uc "source <lib>"` exits 0 with empty
   stderr (real-zsh leg; mirrors 0029's sourcing-safety pattern; CI installs the
   pinned zsh version).

9. No zsh-reserved identifier from the pinned set — `status`, `pipestatus`,
   `path`, `cdpath`, `fignore`, `mailpath`, `manpath`, `fpath`, `watch`,
   `psvar`, `signals`, `argv`, `histchars`, `ARGC`, `HISTCHARS` (drawn from the
   zsh `RESERVED` parameter class, `man zshparam`) — is used as an assigned
   shell variable in any `commands/**/*.lib.sh`. The grep guard pins the
   assignment grammar it checks: bare `NAME=`, `local NAME`, `declare/typeset
   NAME`, `read ... NAME`, and `for NAME in`; its exact committed pattern
   excludes comment/string false-positives and is the artifact reviewers check.
   This list is a curated high-risk subset, not a proof of exhaustiveness — the
   real-zsh source leg (AC8) is the **authoritative backstop**: any reserved
   identifier the static grep misses still fails `zsh -uc "source <lib>"`.

10. The field failure is gone, pinned by a concrete fixture: with
    `revise.lib.sh` sourced under `zsh -u`, `preflight_status_gate` against a
    `status: draft` spec.md fixture returns 0, and against a `status: closed`
    fixture returns non-zero — in both cases with **no** `read-only variable:
    status` (or any zsh-reserved-name) diagnostic on stderr.

**Release discipline.**

11. This change bumps the plugin version (intended `1.6.1 → 1.7.0`; the new
    `plugin-root` subcommand is an additive API, hence a minor bump) across the
    version surfaces, with a sibling test asserting the new `const version` and
    the manifest values, mirroring spec 0029's version-bump-with-test pattern.
    Per the release-completeness convention (`.speccraft/conventions.md`
    §Version bumps), "done" is not the edited consts/manifests but the published
    `v1.7.0` GitHub Release: the bump lands on `main`, the `auto-tag` job pushes
    `v1.7.0`, and `release.yml` builds, publishes the four platform tarballs +
    `checksums.txt`, and self-verifies via `scripts/verify-release.sh`. The
    spec's close gate is that automated path completing, not a manual release.

12. This repo's `.devcontainer` exports `SPECCRAFT_PLUGIN_ROOT` pointing at the
    checked-out working tree, so dogfood sessions resolve `plugin-root` to the
    working tree rather than the stale installed cache copy on `PATH` (the
    verified 1.1.0 case). Asserted by a check that, inside the devcontainer,
    `speccraft-state plugin-root` equals the repo root.

## Out of scope

- **Persisting the plugin root** (e.g. a `state.json` field written by the
  session-start hook) as a resolution fallback. Resolved open question OQ1:
  self-derivation + the two env sources are sufficient; persistence adds
  state-coupling and worktree/pre-init ambiguity for no demonstrated benefit.
  Revisit in a follow-up spec only if a concrete self-derivation failure is
  observed.
- Go-shaped assumptions / stack-agnostic test discovery (`*_test.go`,
  `go test ./...`) — deferred to the "Stack-agnostic planning & execution" spec.
- Revision-counter and `*-rN.md` archive-numbering redesign, `set_status`
  helper — deferred to the "Revision-counter & artifact-numbering" spec.
- Diff-focused re-review mode — backlog.
- Filing or waiting on an upstream Claude Code harness change for
  `CLAUDE_PLUGIN_ROOT`; this spec self-resolves instead.

## Open questions

_none_ — both open questions from revision 0 were resolved by the 2026-07-24
cross-model review: OQ1 (persistence) → out of scope (above); OQ2 (authoritative
zsh-reserved list) → pinned in AC9.
