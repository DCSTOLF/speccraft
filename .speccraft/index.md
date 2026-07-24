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

none

## Recent decisions (last 3)

- 2026-07-24 — TDD guard Write-tool red-candidate blind spot fixed override-free; version 1.7.1 (spec 0031): fixes the exact guard limitation that cost spec 0030 three overrides. `speccraft-guard`'s red-candidate capture modeled post-edit content by payload *shape* (`applyEdit`: empty `old_string` → "Write, use `new_string`"), but the Write tool sends `content` and `ToolInput` had no such field → Write-authored test files captured ZERO red-candidates → the sibling prod edit was wrongly blocked. Hidden because the `captureCase` fixture mis-simulated Write via `new_string`. Fix discriminates on TOOL IDENTITY: add `ToolInput.Content` (`json:"content"`) + a `ToolName` field (`json:"-"`) injected in `dispatchByLanguage`; `applyEdit` switches on `ti.ToolName` (Write→Content incl. empty; Edit→replace even when old empty; default MultiEdit/NotebookEdit→unchanged, reserved spec 0032). META-PAYOFF: shipped with ZERO overrides — the driving REDs were authored at the JSON-envelope boundary (`json.Unmarshal` a real `{"tool_name":"Write",...,"content":...}` envelope) so they compiled against current code and failed on behavior, dodging the build-failed-≠-RED trap. Verified: 7 JSON-boundary capture/E2E tests + AC1/AC2 unit pins + AC5 static fixture guard + AC7 MultiEdit/NotebookEdit characterization; go test green, bats 0-fail, verify.sh green. Version 1.7.0→1.7.1. Two red-candidate-tracking notes surfaced (both resolved without override): a no-new-test test-file edit CLEARS a standing RED (`SetRedCandidates` replaces per-file); the guard refuses a comment-only prod edit. Own close ran no consolidation (no `specs/domains/` tree).
- 2026-07-24 — Cross-environment command execution hardening; version 1.7.0 (spec 0030): two coupled command-execution defects found running speccraft as an *installed* plugin (not dogfooded) on macOS/zsh + Python — the sequel to 0029's first-use lineage. (A) plugin-root resolution was unreliable for slash-command bash — docs dereferenced `$CLAUDE_PLUGIN_ROOT/{bin,commands,templates}`, but that var is only exported to HOOKS, not slash-command bash, and in the field resolved to the plugins *parent*; fixed with a new `speccraft-state plugin-root` subcommand (precedence `SPECCRAFT_PLUGIN_ROOT` → validated `CLAUDE_PLUGIN_ROOT` → `os.Executable()`+`EvalSymlinks`+walk-up to the `.claude-plugin/plugin.json`-manifest-valid ancestor; handles `bin/` and dogfood `tools/bin/`). (B) `revise.lib.sh`'s bare `status` local is zsh-reserved (`read-only variable: status`); renamed `spec_status`. 15 command docs migrated to `PLUGIN_ROOT="$(speccraft-state plugin-root)"` (bare binary calls on PATH); `init.md` fallback removed; conventions.md + architecture.md updated in lockstep; `.devcontainer` exports `SPECCRAFT_PLUGIN_ROOT` to override the stale 1.1.0 cache copy on PATH. Version 1.6.1 → 1.7.0. Verified: 11 Go table tests + real-zsh `lib-zsh-safety.bats` + `verify.sh` oracle; `go test ./...` green, bats 142/0. THREE `/speccraft:spec:override` (plan predicted zero) — root cause is a NEW finding: the TDD guard's red-candidate capture reads the Edit tool's `new_string` but Write sends `content`, so Write-authored RED tests register zero candidates (compounded by compiled-language new-symbol bootstrap). AC11's published-release half deferred to merge-time (auto-tag → release.yml → verify-release.sh on `main`). Own close ran no consolidation (no `specs/domains/` tree yet — non-blocking decline).
- 2026-06-27 — Consolidation routing hardening + zsh portability fix; released 1.6.1 (spec 0029): three first-use defects in spec 0025's inline-at-close consolidation, found running speccraft from scratch in another project. (A) zsh portability — `consolidate.lib.sh` self-located via a bare `${BASH_SOURCE[0]}`, which under zsh+`set -u` aborts the `source` (exit 127) and takes down EVERY consolidate function + `/speccraft:sync` backfill, so an agent silently skipped consolidation; fixed with the canonical `${BASH_SOURCE[0]:-$0}`. (B) routing couldn't see existing domains — `consolidate_routing_seed` only slugified the title; added a SEPARATE deterministic `consolidate_existing_domains` (live-only, `.archive`-excluded, bytewise-sorted) to ground the proposal (prefer existing, else propose new), seed byte-unchanged. (C) docs let an agent fold requirements into `.speccraft/architecture.md`/`conventions.md` (the `Mode: close` files 0025 forbids consolidation from touching) and call it done; hardened `close.md` step 9 + `memory-keeper` so consolidation routes ONLY to `specs/domains/`, a missing `delta:`/`domains:` is a fallback not a skip, and `Mode: close` updates are NOT a substitute. Pinned by a REAL-zsh source test (a bash simulated-unset harness can't reproduce the bug — bash re-populates `BASH_SOURCE` during `source`) + an exact-form `${BASH_SOURCE[0]:-$0}` guard across all 8 `*.lib.sh`, `specs/0029-.../verify.sh`, and a credit-gated AC6 e2e leg. Two conventions codified: cross-shell lib self-location, and "a credit-gated e2e leg must instruct the model to APPLY, not propose-and-wait" (AC6 first failed in CI on proposal-style wording → model stopped at "Confirm?"; fixed to imperative). `ci.yml` installs zsh. Version 1.6.0 → 1.6.1 across the five surfaces. No override. 0029's own close ran no consolidation (no `domains:`/`delta:`, no `specs/domains/` yet — non-blocking decline). Landed `0d595d7` + `ddf38da`; tag `v1.6.1`.
