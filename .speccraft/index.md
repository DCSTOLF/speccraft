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

_none_

## Recent decisions (last 3)

- 2026-07-28 — Workspace topology foundation ships (spec 0037, Spec A of design 0001; closed): `.speccraft/speccraft.toml` gains a top-level `kind = "repo" | "workspace"` (a TOML key via `parseSpeccraftTOML`, NOT frontmatter — there is no YAML reader in `tools/`), absent ⇒ `repo`; a `readConfigRaw` split makes non-strict `ReadConfig` COERCE an unknown kind to `repo` while `ReadConfigStrict` ERRORS (a bad value can never silently promote a repo to a workspace). `FindWorkspaceRoot(dir)` = nearest `kind=workspace` ancestor, else exact `FindRoot` value+error parity; consumed only by `arch:*`/the conductor and kept off the Edit/Write hot path by a source-scan guard test (`hotpath_findroot_test.go`, sibling to the spec-0012 single-writer test). `ParseWorkspaceMembers` parses a constrained hand-rolled `workspace.yml` subset (no YAML dep) and is authoritative + presence-preserving — a listed-but-missing path is kept as `Member{Present:false}` (never dropped) for Spec B's `blocked` overlay. Three `run()`-seam subcommands (zero override): `list-members`, `get-status <spec-ref>` (dual `specs/`→`specs/.archive/` resolution, live-wins), `get-frontmatter <spec.md> <key>`; both frontmatter readers route through the single spec-0036 `parseFrontmatterBlock` grammar via a new `ReadFrontmatterField` (no 2nd parser). TWO `/speccraft:spec:override`s (not the planned one): `Config.Kind` in config.go's struct is a build-barrier separate from the new-symbols file (both logged in tasks.md `## Bypasses`); every other step rode a runtime RED at zero override. Deferred: consolidation (no `specs/domains/` yet) → `/speccraft:sync`; no version bump (the conductor, Spec B, carries the release). Stale-cached-guard now moot — cached binaries refreshed to 1.11.0 ([[dogfood-stale-cached-guard-on-path]]). 44 new tests; `go test ./...` + `go vet` green.
- 2026-07-28 — Architect becomes a lifecycle conductor across single- and multi-repo workspaces (design 0001, DECIDED/closed): the architect graduates from advisory design-writer to a **conductor** that SEQUENCES the existing per-spec lifecycle (`new → answer-questions → (review → revise)* → plan → implement → validate`) across N member repos — never bypassing the per-spec commands or the TDD red→green guard, only sequencing them one member at a time and tracking progress in a ledger. Topology: `.speccraft/ kind: repo|workspace` (absent⇒repo; a monorepo is a single repo-kind member); a `kind: workspace` root holds the `design/` tree + a `ledger.md` (history.md-class, DELIBERATELY OUTSIDE the state.json single-writer rule) but no specs of its own; `workspace.yml` `members:` is authoritative; `find-workspace-root` is a peer of `FindRoot` consumed only by arch/conductor (hot path untouched). Reconcile reads each child spec's status from its `spec.md` frontmatter (dual live/`.archive` location), never `state.json`, never the ledger pointer; a design is done when every child is `closed`. Advisory throughout (never gates a member; failure-isolated — one blocked member never stalls siblings). Delivered as two specs: Spec A = topology foundation ([[spec 0037]]), Spec B = the conductor + `/speccraft:arch:orchestrate`. A cross-model review caught a real status-source bug (reconcile reading `state.json` instead of `spec.md` frontmatter) that the single-model self-check missed. Full arch flow dogfooded: `arch:new → review → decide → close`.
- 2026-07-27 — One revision-and-artifact-numbering contract + a single sanctioned byte-safe frontmatter writer; version 1.11.0 (spec 0036): the frontmatter `revision:` counter is the sole authority, healed FORWARD only from on-disk `*-r<N>.md` evidence — `Effective = hasArchived ? max(fmRev, maxArchived+1) : fmRev` (`tools/internal/speccraft/revision.go` `ComputeRevisionState`/`RevisionState`). Self-healing revise: `archive_rename` computes `A = effective-revision` once and archives the disposable set (review/plan/tasks, never spec.md) under one ordinal via `speccraft-state archive-artifact` (cmd-package `moveArtifactNoReplace`: `link(2)` no-clobber + `os.SameFile` inode-identity interrupted-move recovery, NOT byte-equality); `preflight_archive_collisions` DELETED (a pre-existing `review-rN.md` self-heals past instead of deadlocking). Single shared `parseFrontmatterBlock` grammar (BOM/mixed-EOL/column-0/first-wins) drives reader AND the unexported byte-safe `setFrontmatterField` (first-match-only, per-line terminators, deterministic insertion, skip-write no-op, no `.bak`, on `AtomicWriteFile`), behind exported `SetStatus` (enum-validated) / `SetRevision` (monotonic-forward, refuses demotion), both enforcing closed-spec immutability IN the exported op. Five run()-seam subcommands (no cmd override): `effective-revision`/`set-status`/`set-revision`/`reconcile-revision`/`archive-artifact`. `bump_revision` is now a thin reconcile-then-set-status helper (archive→counter→status LAST, no raw sed); `close.md` uses `set-status`. New semantics: within-draft edits keep the same revision (counter advances only on archive). AC10 meta-guard `frontmatter-writer-guard.bats` (fixture-first, per-tool matching regime) forbids raw sed/perl in-place field rewrites in command libs. Version 1.10.0→1.11.0. A 5-round cross-model review drove out 6 pre-implementation defects (a `--force` closed-spec guardrail violation, the `A+1`-vs-heal retry bug, `spec.md`-archive contradiction, byte-equality data-safety). ONE override (T1 bootstrap; AC12 budget ≤1). Deviations: `parseFrontmatterBlock` lives in `revision.go` not its own file (tested single-entrypoint property holds); T9/T10 collapsed (T8 writer already covered the edges). Recurring stale-1.1.0-cached-guard friction ([[dogfood-stale-cached-guard-on-path]]): REDs via Edit, Bash only for mechanical build-fixes (import-then-use + literal-BOM breaks), no-new-test-edit-clears-RED on the version bump. Own close ran no consolidation.
