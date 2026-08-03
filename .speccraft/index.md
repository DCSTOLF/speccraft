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
- Architect conductor & workspace topology: `commands/arch/orchestrate.{md,lib.sh}`, `tools/internal/speccraft/ledger.go` (`ParseLedger`/`SetLedgerField`/`Reconcile`), `FindWorkspaceRoot`/`ParseWorkspaceMembers`; the workspace ledger is `<workspace>/.speccraft/ledger.md` (a history.md-class memory file, never `state.json`)
- User-facing memory templates: `templates/speccraft/`
- E2E test harness: `tests/e2e/run.sh`
- Specs: `specs/NNNN-<slug>/`

## Active spec

none

## Recent decisions (last 3)

- 2026-08-03 — Release 1.15.0: workspace sync — design-level consolidation & ledger-row archival (spec 0044, closed; `informed-by: design/0001`): completes the workspace-sync arc (A+B in 0043, **C** here). 0043 reconciled the ledger but it only *grows* — done designs' rows accumulate forever. Adds a confirm-gated **`W4`** pass to `/speccraft:sync`'s workspace branch: every `reconcile`-`done` design is folded into a durable colocated `design/<id>-<slug>/outcome.md` rollup and its rows **archived** out of live `.speccraft/ledger.md` into a sibling `.speccraft/ledger.archive.md` (same grammar, `ParseLedger`-valid) — bounding the live ledger as designs accumulate. Three OQs resolved with the user (colocated outcome.md via a `sync_resolve_design_dir` glob resolver; sibling archive file; `W4`-in-sync not a separate command). New Go op **`speccraft-state ledger-archive <design> [--expect <fp>]`** — single-read atomic authority: four-case contract on a **text-level presence check** (so `Reconcile`'s vacuous-done-for-absent never leaks), byte-level **section splice** (untouched designs byte-identical), transactional **append-archive-first/remove-live-second** + both-present crash recovery, and an **`--expect` CAS** closing the caller→op handoff. Cmd-package (`run()` seam) → **override budget 0**; `reconcileCmd` refactored onto shared `reconcileOutput` (fingerprint = `reconcile | sha256sum`). Five pure `sync.lib.sh` helpers + the `W4` runbook; crash-safety via a **fingerprinted `consolidated:` marker** (missing/stale → atomic rewrite, so the record never describes an older snapshot than the archived rows). **Four-round** cross-model (codex + claude-p converging) drove the four-case contract, transactional splice, fingerprinted marker, and the `--expect` CAS; the residual concurrent-writer race is **bounded + deferred** (same single-writer scope 0043 ratified — a workspace-wide lock / `--expect-bytes` CAS is the follow-up). Minor bump 1.14.0 → 1.15.0 (renamed-version-test technique, six locations, NO override); `go test ./...`+`go vet` green, 282 bats green, drift clean, all four workspace e2e pass (new `workspace_consolidate_cycle.sh`), binaries report 1.15.0. Push + tag `v1.15.0` triggers the release pipeline (spec 0021).
- 2026-07-31 — Release 1.14.0: workspace sync — ledger + membership drift reconciliation (spec 0043, closed; `informed-by: design/0001`): the out-of-band pass that makes a workspace root's own memory (ledger + `workspace.yml`) match reality — the workspace analog of `/speccraft:sync`. `/speccraft:sync` now auto-detects `kind` (via the 0042 `config-kind` oracle) and branches: `repo` = unchanged repo flow; `workspace` reconciles **ledger drift (B)** + **membership drift (A)**. Core insight: **ledger drift is out-of-band re-entry** — 0040's `orch_reentry` already answers "does the member's live status prove this phase completed?", so sync asks it for every member of every design; `adopt` ⇒ ledger behind reality. Reuses the token machine + `ws_detect_members` wholesale; adds one read-only oracle **`speccraft-state ledger-get [<design>]`** (raw stored pointers — `reconcile` only exposes *computed* status; `run()` seam → **override budget 0**), a pure `commands/sync.lib.sh` (`sync_status_ahead`/`sync_stale_in_flight`/`sync_ledger_drift`/`sync_membership_audit`/`sync_apply_member_plan`), and a `commands/sync.md` branch with `<!-- speccraft:sync:repo|workspace -->` anchors. Contracts: tool-managed ledger fixes auto-applied via `ledger-set`; curated `workspace.yml` + dangling refs **advisory only**; live-run-**conservative** (clear `in_flight` only on `adopt`); conflict-safe per-member plan (re-read + byte-compare once → `conflict`, no write; residual TOCTOU + true CAS deferred); 6-field findings parsed with `awk -F '\t'` (never `IFS=$'\t' read`); parse-level corruption fails `ledger-get` globally vs a parsed bad-token row → per-member `malformed-row` advisory. **Three-round** cross-model (codex changes-requested→resolved, claude-p approve-with-comments; both converged): drove the AC10 conflict guard, argv-safe structured findings, the AC8+AC10 captured-snapshot batch apply, `awk` empty-field parsing, parse/semantic split. Minor bump 1.13.0 → 1.14.0 (renamed-version-test technique, six locations, NO override); `go test ./...`+`go vet` green, 270 bats green, drift clean, both workspace e2e (`workspace_init_cycle` regression + new `workspace_sync_cycle`) pass, binaries report 1.14.0. Push + tag `v1.14.0` triggers the release pipeline (spec 0021). Follow-up: class C (design consolidation) next.
- 2026-07-29 — Release 1.13.0: `init --workspace` scaffolds a workspace root (spec 0042, closed; `informed-by: design/0001`): closes the last conductor-arc gap — 0037–0041 could *read/drive* a workspace but nothing *created* one. Adds a `--workspace` mode to `/speccraft:init` that WRITES a `kind = "workspace"` speccraft.toml + a canonical `workspace.yml` manifest (readers untouched). Five pure `init.lib.sh` helpers (`ws_arg_parse`/`ws_toml_body`/`ws_manifest_body`/`ws_detect_members`/`ws_write_root`, 26 bats) + two new `speccraft-state` oracle subcommands (`config-kind`, `find-workspace-root`) riding the `run()` seam → **override budget 0**. Contracts: lazy ledger, manifest-before-toml ordering (no orphan workspace kind), curated `workspace.yml` preserved on `--force`, `repo → workspace` migration refused. Two-round cross-model review (codex+claude-p) → all fixes resolved incl. the AC9 atomicity-overclaim reword. Minor bump 1.12.0 → 1.13.0 via the renamed-version-test technique (six single-source locations, NO override); `go test ./...`+`go vet` green, 241 bats green, drift clean, binaries report 1.13.0. Hermetic e2e `workspace_init_cycle.sh` proves AC1/2/3a/4/5/8. Push + tag `v1.13.0` triggers the release pipeline (spec 0021).
