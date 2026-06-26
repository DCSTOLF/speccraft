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

specs/0029-consolidation-routing-hardening/

## Recent decisions (last 3)

- 2026-06-25 — Pin the e2e consolidation fixture's load-bearing corpus precondition at the credit-free layer (spec 0028): the THIRD test-harness-only fix in the 0025→0027→0028 lineage and the one that BREAKS THE CYCLE. The spec-0025 consolidation e2e fixture failed on its first real run because its DECLINE and CONFIRM legs shared seeded spec 0089 and a `/speccraft:sync` decline writes a PERMANENT `consolidation-skip` marker (across-run skip-permanence) → CONFIRM could never consolidate 0089; plus whole-corpus `/sync` enumeration left the legs un-isolated (0088 eligible early; lifecycle spec 0001 leaked in). Feature behaved exactly as specified — fixture-design error, code BYTE-UNCHANGED. Fix: (1) 4 NEW credit-free `spec-consolidate.bats` cases (31→35) that RECONSTRUCT each leg's exact corpus per the corpus-state table and assert `consolidate_backfill_candidates` returns exactly the singleton (decline→0090/confirm→0089/conflict→0088) + a skip-excludes-target regression (the 0089 bug at zero credits) — the bats cases ARE the table, so a fixture-SEEDING regression is caught on every CI bats job not only on a credit-gated run; (2) LAZY per-leg seeding (skip-mark 0001 once, seed each source just before its sync, never clear a marker) + a LOAD-BEARING per-leg AC3 guard (direct `consolidate_backfill_candidates "$PWD"` == singleton) turning seeding drift into a fast named failure; (3) `run.sh [10/13]` asserts an inline-close decline writes NO skip on 0001 (skip-semantics contrast). New convention: pin a credit-gated fixture's deterministic PRECONDITION at the credit-free layer (bats reconstructs the exact arrangement) + a load-bearing in-fixture runtime guard. Close gate GREEN (not deferred): e2e-devcontainer CI run 28071351196 (commit 91e7835) success through [10/13]→[10e/13]. No override. Follow-ups deferred: RCA option(3) consolidation opt-out; genuine inline-at-close e2e coverage.
- 2026-06-24 — Decline-vs-confirm: separate e2e paths for the inline-at-close consolidation gate (spec 0027): test-harness-only fix for a regression spec 0025 introduced. Spec 0025's inline consolidation at `close.md` step 9 was swept into the e2e `[10/13]` "approve all" blanket approval; with the throwaway spec `0001-add-farewell-function` at zero conflicts it MOVED the dir to `specs/.archive/`, breaking the pre-0025 assertion `run.sh:367 exists "$SPEC_DIR/changelog.md"` (changelog rode along via the wholesale `mv`). Fix tests the two close confirm-gates on SEPARATE paths: `[10/13]` now DECLINES consolidation (dir stays; legacy assertions hold) with a structural non-move guard `[ ! -d specs/.archive/0001-add-farewell-function ]` (turns a model slip into an immediate named failure); `[cons 2/3]` in `spec_consolidate.sh` is documented as the inline-at-close-EQUIVALENT CONFIRM coverage (drives `/speccraft:sync` over the SAME `consolidate.lib.sh` path close.md step 9 drives; wiring pinned by 0025 `verify.sh`, mechanics incl. changelog-rides-along `mv` by `spec-consolidate.bats`). Feature code byte-unchanged (AC4); no Go/bats/new file → NO override. RED = the observed CI failure (run 28057150956); GREEN = the two edits; `bash -n` clean, bats 31/31 + 0025 verify.sh green; AC3 full-lifecycle green deferred to e2e-devcontainer CI run 28066411890. Follow-up: RCA option (3) — a distinct consolidation opt-out so a generic "approve all" never silently relocates a dir — deferred to its own spec.
- 2026-06-23 — Version bump to 1.6.0 (spec 0026): coordinated 1.5.0 → 1.6.0 bump across all five live version surfaces — the two manifests (`.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`) and the three binary `const version` declarations (`speccraft-{state,guard,drift}`) — same lockstep mechanism as specs 0019/0023; each const pinned RED→GREEN by its sibling version test. Marks the README/docs restructure release (README slimmed to a hero + four differentiators; detail split into `INSTALL.md`, `docs/commands.md`, `docs/architecture.md`, `CONTRIBUTING.md`; docs paths added to CI `paths-ignore`). Pushing the bumped `plugin.json` to `main` triggers the `auto-tag` CI job (spec 0021) → `v1.6.0` → `release.yml`. Done as its own in-progress spec because production edits require an active spec.