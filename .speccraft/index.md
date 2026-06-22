# speccraft

A Claude Code plugin that enforces spec-first TDD via hooks, slash commands, subagents, and cross-model review.

## Stack

- Bash 5+ hooks (`hooks/`) wired through `hooks/hooks.json`
- Go helper binaries under `tools/cmd/speccraft-{state,guard,drift}` sharing `tools/internal/{speccraft,delegate}` (module `github.com/dcstolf/speccraft/tools`; `go.mod` declares Go 1.22, CI runs Go 1.26.3)
- Markdown slash commands (`commands/`) and subagents (`agents/`)
- Markdown skills (`skills/<name>/SKILL.md`)
- Stack-agnostic memory templates (`templates/speccraft/`) copied into a host repo by `/speccraft:init`
- Devcontainer-based end-to-end test (`tests/e2e/run.sh`) driven by GitHub Actions (`.github/workflows/ci.yml`)

## Architecture in one paragraph

speccraft is packaged as a Claude Code plugin (`.claude-plugin/plugin.json`, marketplace `dcstolf-tools`) and ships three execution surfaces: shell hooks that gate Edit/Write tool calls, slash commands the user invokes (`/speccraft:init`, `/speccraft:spec:*`, `/speccraft:sync`), and subagents the orchestrator dispatches (planner, critic, reviewer, delegator, memory-keeper). Hooks and commands call small Go binaries — `speccraft-state` (session/spec state in `.speccraft/state.json`), `speccraft-guard` (TDD red→green invariant), and `speccraft-drift` (regex scan of `enforce:` rules in memory files) — whose shared logic lives in `tools/internal/speccraft`. The repo dogfoods its own plugin: `.speccraft/` here is real project memory for this very codebase, not a fixture.

## Hard rules (see guardrails.md)

- Never commit built binaries from `bin/` or `tools/bin/`.
- Never bypass the TDD red→green invariant without `/speccraft:spec:override` with a recorded reason.
- Plugin templates under `templates/speccraft/` must stay stack-agnostic (no Go-, Python-, or HTTP-specific assumptions).

## Where to look

- Hooks: `hooks/` (entry: `hooks/hooks.json`)
- Slash commands: `commands/` (top-level + `commands/spec/`)
- Subagents: `agents/`
- Skills: `skills/<name>/SKILL.md`
- Go helper binaries: `tools/cmd/speccraft-*/main.go`
- Shared Go logic: `tools/internal/speccraft/`, `tools/internal/delegate/`
- User-facing memory templates: `templates/speccraft/`
- E2E test harness: `tests/e2e/run.sh`
- Specs: `specs/NNNN-<slug>/`

## Active spec

specs/0022-pm-architect-upstream-workflows/

## Recent decisions (last 3)

- 2026-06-18 — Release pipeline self-verifies and auto-tags on version bump; the source-build fallback is no longer silent (spec 0021): fixed the root cause of "plugin compiles from source at runtime instead of downloading release assets" — no `vX.Y.Z` tag had ever been pushed, so the tag-triggered `release.yml` never ran, every asset URL 404'd, and `install-binaries.sh`'s `curl … 2>/dev/null && …` chain masked it by falling through to `go build`. New `auto-tag` CI job (`push` to `main`) runs pure `scripts/auto-tag.sh should_tag` and pushes `vX.Y.Z` via `secrets.RELEASE_TAG_PAT` — NOT `GITHUB_TOKEN`, whose built-in loop guard suppresses `on: push: tags` re-triggers (claude-p's highest-priority latent-correctness catch, CF-1). New `scripts/verify-release.sh` is a strong-form oracle (downloads each of the 4 tarballs + `checksums.txt`, recomputes SHA-256, fails loud+named) reused as `release.yml`'s final self-verify step keyed to `github.ref_name` — deadlock-free (guard keys off the tag, never bare `plugin.json`). `install-binaries.sh` replaces the silent chain with `if ! curl …; then warn(URL); fi` (set -e safe) + a gitignored `.binary-provenance` marker (`download`|`source`); `doctor.sh` reports the distinct "built from source (download unavailable)" state. Asset-name contract fixed: publish `checksums.txt` (was `checksums-merged.txt`), regenerated `sha256sum *.tar.gz` to fix a per-arch collision (beyond named scope). All 4 scripts hermetic via `SPECCRAFT_RELEASE_BASE` `file://` fixtures, pinned by sibling shell tests in `run_helper_unit_tests()`. Deviation: NO `/speccraft:spec:override` needed — `speccraft-guard` does not gate `.sh` files (plan wrongly assumed it would). Orthogonal CI tweak: `paths-ignore` denylist extended for doc-only `LICENSE`/`speccraft-technical-review.md`/`speccraft-v1-spec.md` (denylist, never allowlist; `plugin.json` must keep triggering CI). Two-round review, quorum met rev 2 with 4 carry-forwards folded in (CF-1 PAT, CF-2 cheap-hermetic tier, CF-3 AC5 wording, CF-4 strong-form checksums). Ops: `RELEASE_TAG_PAT` secret DONE; the landing push auto-tags `v1.1.0` (the first real release) — verify in CI run history.
- 2026-06-15 — Tolerant regex for the e2e revise no-op assertion; meta-test reads run.sh's live predicate (spec 0020): the `[6/13] revise no-op` step in `tests/e2e/run.sh` grepped the live `claude -p` log with fixed-string `contains "...06-revise-noop.log" "no changes"`; the command's no-op branch emits a deterministic marker (`no changes — spec unchanged`) but the model paraphrased it ("no-op"/"byte-identical"), so the grep missed — a phrasing flake, not a defect. Swapped to `contains_regex "[Nn]o.?op|[Nn]o changes|byte-identical|unchanged"`; the structural `^revision: 1` check stays load-bearing. Did NOT touch `revise.md`/`revise.lib.sh` (per spec 0017, hardening model output isn't durable). RED→GREEN on a shell-only change via new meta-test `tests/e2e/revise_noop_assertion_test.sh` (mirrors spec 0014's `contains_adr_assertion_test.sh`): it reads run.sh's *live* assertion line + pattern at runtime so the two can't silently diverge, and is wired into `run_helper_unit_tests()` — a real close gate that runs credit-free in `--language-only` (contrast spec 0017/0018's credit-gated model-behaviour steps). Third spec treating model phrasing as untrustworthy at the assertion layer (after 0014, 0017); "meta-test reads run.sh's live predicate" codified as a named convention on its second use. Planned with `--skip-review`; `bash -n` clean, both helper fixtures pass. Committed locally to `main` (not pushed).
- 2026-06-15 — Bump version to 1.1.0 across all live surfaces (spec 0019): coordinated 1.0.0 → 1.1.0 bump across the two packaging manifests (`.claude-plugin/plugin.json`, `marketplace.json`) and the three binary `const version` declarations (speccraft-state/guard/drift); hardcoded-const mechanism unchanged, only its value. Each const bump gated by a real RED→GREEN version test (test asserts the NEW value so it fails pre-edit, satisfying the TDD gate on a one-line const change); manifests verified by a grep oracle (positive 1.1.0 + negative no-stray-1.0.0), since they aren't assertable from `package main`. `--version` parity across the three binaries is now test-pinned; the drift binary gained its first test file. New convention: "version bumps pin the new value with a sibling test." Build-time `-ldflags` injection (P2-5, deferred from spec 0018) remains a follow-up. Planned with `--skip-review`; `go test ./...` green. Pushed to `main` (commit `158f5f5`).
