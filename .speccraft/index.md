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

specs/0028-e2e-consolidation-fixture-isolation/

## Recent decisions (last 3)

- 2026-06-24 — Decline-vs-confirm: separate e2e paths for the inline-at-close consolidation gate (spec 0027): test-harness-only fix for a regression spec 0025 introduced. Spec 0025's inline consolidation at `close.md` step 9 was swept into the e2e `[10/13]` "approve all" blanket approval; with the throwaway spec `0001-add-farewell-function` at zero conflicts it MOVED the dir to `specs/.archive/`, breaking the pre-0025 assertion `run.sh:367 exists "$SPEC_DIR/changelog.md"` (changelog rode along via the wholesale `mv`). Fix tests the two close confirm-gates on SEPARATE paths: `[10/13]` now DECLINES consolidation (dir stays; legacy assertions hold) with a structural non-move guard `[ ! -d specs/.archive/0001-add-farewell-function ]` (turns a model slip into an immediate named failure); `[cons 2/3]` in `spec_consolidate.sh` is documented as the inline-at-close-EQUIVALENT CONFIRM coverage (drives `/speccraft:sync` over the SAME `consolidate.lib.sh` path close.md step 9 drives; wiring pinned by 0025 `verify.sh`, mechanics incl. changelog-rides-along `mv` by `spec-consolidate.bats`). Feature code byte-unchanged (AC4); no Go/bats/new file → NO override. RED = the observed CI failure (run 28057150956); GREEN = the two edits; `bash -n` clean, bats 31/31 + 0025 verify.sh green; AC3 full-lifecycle green deferred to e2e-devcontainer CI run 28066411890. Follow-up: RCA option (3) — a distinct consolidation opt-out so a generic "approve all" never silently relocates a dir — deferred to its own spec.
- 2026-06-23 — Version bump to 1.6.0 (spec 0026): coordinated 1.5.0 → 1.6.0 bump across all five live version surfaces — the two manifests (`.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`) and the three binary `const version` declarations (`speccraft-{state,guard,drift}`) — same lockstep mechanism as specs 0019/0023; each const pinned RED→GREEN by its sibling version test. Marks the README/docs restructure release (README slimmed to a hero + four differentiators; detail split into `INSTALL.md`, `docs/commands.md`, `docs/architecture.md`, `CONTRIBUTING.md`; docs paths added to CI `paths-ignore`). Pushing the bumped `plugin.json` to `main` triggers the `auto-tag` CI job (spec 0021) → `v1.6.0` → `release.yml`. Done as its own in-progress spec because production edits require an active spec.
- 2026-06-23 — Closed specs consolidate into current domain specs at close (spec 0025): closing a spec folds its final requirements into a consolidated, *current* `specs/domains/<area>.md` (open-set: a domain exists iff its file exists) instead of leaving N permanent per-feature dirs to diff — the spec-0024 unbounded-growth fix applied to the spec corpus itself. Merge = ADD/MODIFY/REMOVE per requirement (delta-spec model); every MODIFY/REMOVE carries a REQUIRED verbatim locator matched by exact-normalized comparison (suffix stripped), the deterministic SEED of the model heuristic (bats-pinned); 0-or->1 match → non-blocking conflict path. Runs INLINE at `/speccraft:spec:close` (confirm-gated, NEVER blocks close) + a retroactive `/speccraft:sync` backfill. Two clock-free archives: the closed spec DIR moves wholesale to `specs/.archive/NNNN-slug/` as the LAST step at zero conflicts (status stays `closed` — location signals "consolidated"; relocation ≠ content-edit so immutability holds); superseded TEXT → `specs/domains/.archive/<area>.md` with a self-describing header (area+spec+op) under FULL-ENTRY byte-dedup. Three review carry-forwards folded in pre-`reviewed`: (CF-1, codex) pinned per-delta write order archive-B FIRST → mutation → move, both crash windows bats-pinned; (CF-2) conflict sink = `consolidation-conflicts.md` in the spec dir (not state.json/not the domain file), deleted on resolution, its absence the dir-move precondition; (CF-3 + dev correction) backfill predicate is location-based+clock-free (`closed` AND under `specs/` AND no `consolidation-skip`), replay ordered by `.speccraft/history.md` chronology oldest-first NOT ascending spec-ID (ID ≠ closure order: 0001 dated 2026-05-28 vs 0002/0003 2026-05-15), a 0024-compacted-out spec falls to a `created:`-then-ID fallback (fails safe via the conflict path). Pure shell + bats + a SOURCED credit-gated e2e fixture (`[10e/13]`), NO Go binary → NO override; `consolidate.lib.sh` REUSES spec 0024's `history_parse_entries`/`history_provenance_ids` (cross-lib `source`, new convention) + `memory-keeper` gains `# Mode: consolidate`. Deviation: MODIFY new-text is author-authoritative (no mechanical suffix-merge). Tests: bats 127/127 (31 new), go untouched-green, verify.sh all-pass; e2e credit-gated (deterministically verified, full run pending user e2e).