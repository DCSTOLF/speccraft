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

- 2026-06-11 — Scrub README + v1-spec CodeGraphContext routing prose (spec 0016): doc-only scrub applying spec 0011's "External-tool boundaries" principle to the two human-facing prose surfaces 0011 explicitly deferred — `README.md` (3 edit sites at lines 355, 365, 383) and `speccraft-v1-spec.md` (5 edit sites at lines 33, 697, 1132, 1369, 1792); eight prescriptive routing phrases ("prefer X", "should install X", "X is the recommended way") replaced with neutral factual descriptions and example framing ("such as CodeGraphContext"); neutral anchors `Recommended companions` (README header) and `**Recommended companion:**` (v1-spec §13 line 1369 bolded label) preserved as surviving discovery prose; new `verify.sh` oracle (108 lines, 12 labelled `grep -F` checks, file-scoped by name, defensive paraphrase pin #5 for forward-protection) is the second use of the spec-0011 "Grep-assertion oracle for doc-only specs" convention and held up cleanly without refinement; two-round review caught real gaps round 1 missed (round 1 changes-requested → round 2 approve-with-comments after 5 between-round edits); claude-p round-2 catch of a §20.1-vs-§13 misattribution in the spec body fixed pre-`reviewed`; README:544 borderline-prescriptive sentence explicitly disclosed in §Out-of-scope as intentionally retained under the AC1 narrowing; AC4 closed-spec immutability held (`specs/0001-speccraft-v1/spec.md` byte-identical); no new convention, no architecture change; CI run 27347943883 (commit `14aea82`) queued at close time but not a gating condition per the doc-only spec convention; spec 0011's queued "README + speccraft-v1-spec.md cleanup" follow-up is resolved by this spec
- 2026-06-11 — `/speccraft:spec:revise` + `commands/<group>/<name>.lib.sh` colocation (spec 0015): new `/speccraft:spec:revise` slash command + `agents/spec-reviser.md` subagent (tools `[Read, Write, Edit, Bash]`, no `Agent` per spec 0011) for pre-implementation spec revision; preflight + cross-check + diff + archive logic extracted into `commands/spec/revise.lib.sh` — the first sourceable Bash helper under `commands/spec/`, sourced both by the `.md` body at runtime and by `tests/hooks/spec-revise-preflight.bats` at test time (53 new bats cases); load-bearing `^Q-DRIFT:` prefix pinned in agent prompt body (spec-0014 structural-anchor rule) and asserted by verify.sh + e2e; post-agent `frontmatter_integrity_check` enforces the four command-owned keys (`revision`/`status`/`id`/`created`) prose contract against agent edits; T18 mid-implementation amendment (2026-06-11) reworded AC3/AC4 from "state.json byte-identical" to "`active_spec` field unchanged" after CI 27314550595's first attempt tripped the over-specified predicate on normal PostToolUse session-tracking; two new conventions (`commands/<group>/<name>.lib.sh` colocation + Markdown frontmatter contract tightening for subagents/slash-commands) + architecture.md §Layering update; CI run 27314550595 (post-amendment commit `0c824f9`) satisfies the close gate
- 2026-06-10 — E2E contracts encode structural predicates, not model-chosen content (spec 0014): brittle `tests/e2e/run.sh:278` assertion flipped from `contains "farewell"` to `contains_regex "^## 20[0-9]{2}-[0-9]{2}-[0-9]{2}"`; new `tests/e2e/lib.sh` extracts shared helpers (incl. new `contains_regex`); new `tests/e2e/contains_adr_assertion_test.sh` fixture sources the same `lib.sh` to exercise the *exact* predicate; new `run_helper_unit_tests()` sibling to `run_language_fixtures()` (helper-first, fail-fast); two new conventions ("E2E assertion predicates: structural over content" + "Shared assertion helpers via tests/e2e/lib.sh"); AC4 close gate satisfied by CI run 27287309940
