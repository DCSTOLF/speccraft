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

- 2026-06-23 — Bounded, reviewable history.md compaction (spec 0024): make `.speccraft/history.md` bounded instead of unbounded append-only (it had hit 22 entries / ~60KB, bloating the context the `speccraft-context` skill loads). New explicit, confirm-gated `/speccraft:history:compact` keeps the newest N entries (default 10) verbatim, folds older ones into a merged thematic `## Compacted` section, and moves originals VERBATIM into a new append-only `.speccraft/history-archive/` folder (double provenance: archive file + git; never a deletion). Non-blocking nudge at `spec:close`. Three review-driven pins: (1) window is POSITIONAL — first N by `## YYYY-MM-DD` date header in file order, NOT a date sort (live file isn't date-ordered) and NOT keyed on the `(spec NNNN)` suffix (corpus has suffix-less + plural `(specs 0002, 0003)` entries → provenance optional/list-valued); (2) CLOCK-FREE throughout — nudge by count/size (`count>N AND (count>15 OR >40KB)`, the count>N arm kills false alarms), fixed-path append-only archive with full-byte dedup; (3) supersession collapse is OUT-OF-WINDOW only with the pointer on the archived side (resolves the AC2/AC5 contradiction the first review caught). Two-tier per spec 0022: pure-bash `commands/history/compact.lib.sh` + `tests/hooks/history-compact.bats` (19 tests) deterministic; SOURCED credit-gated `tests/e2e/history_compact.sh` model tier; `verify.sh` oracle pins the doc contracts incl. the paired invariant that `history-archive/` is NEVER added to the context-skill load list. `memory-keeper` REUSED (no new store) with a documented `# Mode: compact`. Enhancement beyond the reviewed spec: `history_supersession_seed` pins the deterministic core of the heuristic at bats, leaving only grouping/prose to the model (codex's "deterministic test surface" ask) → new convention "expose the deterministic seed of a model heuristic at the cheap layer". No override needed (all .sh/.md/.bats/e2e); e2e credit-gated (deterministically verified, full run pending user e2e). Tests: bats 96/96, go untouched-green, verify.sh 10/10.
- 2026-06-22 — Milestone version bump to 1.5.0 (spec 0023): coordinated 1.1.0 → 1.5.0 bump across all five live version surfaces — the two manifests (`.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`) and the three binary `const version` declarations (`speccraft-{state,guard,drift}`) — same hardcoded mechanism as spec 0019, only the value moves. Each const bump pinned RED→GREEN by its sibling version test (asserts the NEW value, fails pre-edit); manifests verified by a grep oracle (positive `1.5.0` + no stray `1.1.0`). Marks the spec-0022 milestone; pushing the bumped `plugin.json` to `main` triggers the `auto-tag` CI job (spec 0021) → `v1.5.0` → `release.yml`. Done as its own in-progress spec because production edits require an active spec (the guard's active-spec gate fires before override consumption — `override_pending` cannot bypass "no active spec"). No deviations.
- 2026-06-22 — Optional PM and Architect workflows ship upstream of specs (spec 0022): add advisory `/speccraft:pm:{new,review,prioritize,close}` and `/speccraft:arch:{new,review,decide,close}` namespaces above the spec lifecycle (PM → Architect → Spec → implement) — specs stay fully standalone (AC1), upstream lanes are additive, never flag-gated. PM artifacts under `product/NNNN-slug/` (`brief.md`), Architect under `design/NNNN-slug/` (`design.md`); both reuse existing machinery (`cross-reviewer` backs both `*:review` unchanged; `arch:close` routes durable decisions through the existing `memory-keeper` — no new store). Three AC1/AC7-driven choices: (1) state shape is ADDITIVE SIBLING keys `active_product`/`active_design` (`,omitempty`), `active_spec` byte-identical — a nested/`kind`-discriminated record was REJECTED (it would defeat the `run.sh` close-gate `jq -r '.active_spec // "null"'`, the raw-jq revise preflight, and the four e2e fixture literals); lane independence asserted at the serialization layer + single-writer lock extended. (2) AC3 doc-zone is a markdown-scoped REGRESSION PIN (`product/`/`design/` `*.md` allowed via the pre-existing `ext==".md"` rule; NEGATIVE rows prove a SOURCE file under those trees stays gated), NOT a `prefix()` entry — adding one would reopen the broad bypass. (3) Cross-stage linkage is PULL-ONLY/advisory: `spec:new --from product/<id>|design/<id>` pulls Why/What and writes a non-empty `informed-by` key, plain `spec:new` writes NO key (byte-shape parity); a missing/deleted/closed referent is NON-FATAL (AC8). Closed-artifact immutability stays by-convention (no status-aware guard, out of scope). Four agents added (pm/arch author+critic). New convention: credit-gated e2e fixtures are SOURCED into run.sh (share `run_claude`), not subshelled. Tests: go test green, bats 77/77, verify.sh oracle green; two credit-gated e2e fixtures `bash -n` clean but full lifecycle pending user e2e. ONE override (T3): guard's `applyEdit` models `Edit.new_string` but not `Write.content`, so a Write-created sibling test can't be observed as runtime RED → follow-up spec. Landed in commit `daaa251` (ff to `main`).
