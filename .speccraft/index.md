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

- 2026-07-25 — Post-0030/0031 CI regression hardening; test/fixture/prompt-only, no version bump, zero overrides (spec 0033): three CI failures fixed after shipping 0030 (1.7.0) + 0031 (1.7.1). (1) macOS-only Go test Test_ResolvePluginRoot_SymlinkedExe — /var→/private/var symlink + the resolver EvalSymlinks the exe → got≠want; fixed with an ASYMMETRIC assertion (normalize only want=EvalSymlinks(root); normalizing both sides would mask a skipped-EvalSymlinks regression). (2) tests/e2e/rust_integration_cycle.sh sent a tool_name:"Write" payload with content in new_string (the exact 0031 mis-simulation in a shell fixture) → 0031's applyEdit reads empty content → no rejection; fixed by using `content`. (3) tests/e2e/spec_consolidate.sh [cons 1/3] decline prompt wasn't imperative → the credit-gated model proposed-and-waited instead of writing the consolidation-skip marker; fixed with an imperative prompt (write marker, don't move, WITHOUT asking, keep memory-audit separate). Recurrence guard: NEW Go test e2e_fixture_shape_test.go — a per-envelope scanner over tests/e2e/*.sh for the Write+new_string shape (extends 0031's Go-ONLY guard to shell fixtures — the gap that let #2 through) + a credit-free meta-test pinning the [cons 1/3] prompt's three terminal phrases. Zero product code, no `const version` bump. Caveat: AC1's macOS failure isn't reproducible on the Linux dev host (oracle = Linux go test green + correct-by-construction; confirmed by next macOS CI). #3 is a pre-existing consolidation-lineage flake, not a 0030/0031 regression. 0032 stays reserved (0031); 0033 skipped it. Own close ran no consolidation.
- 2026-07-24 — TDD guard Write-tool red-candidate blind spot fixed override-free; version 1.7.1 (spec 0031): fixes the exact guard limitation that cost spec 0030 three overrides. `speccraft-guard`'s red-candidate capture modeled post-edit content by payload *shape* (`applyEdit`: empty `old_string` → "Write, use `new_string`"), but the Write tool sends `content` and `ToolInput` had no such field → Write-authored test files captured ZERO red-candidates → the sibling prod edit was wrongly blocked. Hidden because the `captureCase` fixture mis-simulated Write via `new_string`. Fix discriminates on TOOL IDENTITY: add `ToolInput.Content` (`json:"content"`) + a `ToolName` field (`json:"-"`) injected in `dispatchByLanguage`; `applyEdit` switches on `ti.ToolName` (Write→Content incl. empty; Edit→replace even when old empty; default MultiEdit/NotebookEdit→unchanged, reserved spec 0032). META-PAYOFF: shipped with ZERO overrides — the driving REDs were authored at the JSON-envelope boundary (`json.Unmarshal` a real `{"tool_name":"Write",...,"content":...}` envelope) so they compiled against current code and failed on behavior, dodging the build-failed-≠-RED trap. Verified: 7 JSON-boundary capture/E2E tests + AC1/AC2 unit pins + AC5 static fixture guard + AC7 MultiEdit/NotebookEdit characterization; go test green, bats 0-fail, verify.sh green. Version 1.7.0→1.7.1. Two red-candidate-tracking notes surfaced (both resolved without override): a no-new-test test-file edit CLEARS a standing RED (`SetRedCandidates` replaces per-file); the guard refuses a comment-only prod edit. Own close ran no consolidation (no `specs/domains/` tree).
- 2026-07-24 — Cross-environment command execution hardening; version 1.7.0 (spec 0030): two coupled command-execution defects found running speccraft as an *installed* plugin (not dogfooded) on macOS/zsh + Python — the sequel to 0029's first-use lineage. (A) plugin-root resolution was unreliable for slash-command bash — docs dereferenced `$CLAUDE_PLUGIN_ROOT/{bin,commands,templates}`, but that var is only exported to HOOKS, not slash-command bash, and in the field resolved to the plugins *parent*; fixed with a new `speccraft-state plugin-root` subcommand (precedence `SPECCRAFT_PLUGIN_ROOT` → validated `CLAUDE_PLUGIN_ROOT` → `os.Executable()`+`EvalSymlinks`+walk-up to the `.claude-plugin/plugin.json`-manifest-valid ancestor; handles `bin/` and dogfood `tools/bin/`). (B) `revise.lib.sh`'s bare `status` local is zsh-reserved (`read-only variable: status`); renamed `spec_status`. 15 command docs migrated to `PLUGIN_ROOT="$(speccraft-state plugin-root)"` (bare binary calls on PATH); `init.md` fallback removed; conventions.md + architecture.md updated in lockstep; `.devcontainer` exports `SPECCRAFT_PLUGIN_ROOT` to override the stale 1.1.0 cache copy on PATH. Version 1.6.1 → 1.7.0. Verified: 11 Go table tests + real-zsh `lib-zsh-safety.bats` + `verify.sh` oracle; `go test ./...` green, bats 142/0. THREE `/speccraft:spec:override` (plan predicted zero) — root cause is a NEW finding: the TDD guard's red-candidate capture reads the Edit tool's `new_string` but Write sends `content`, so Write-authored RED tests register zero candidates (compounded by compiled-language new-symbol bootstrap). AC11's published-release half deferred to merge-time (auto-tag → release.yml → verify-release.sh on `main`). Own close ran no consolidation (no `specs/domains/` tree yet — non-blocking decline).
