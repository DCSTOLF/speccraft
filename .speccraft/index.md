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

- 2026-07-29 — Crash-safe conductor re-entry completes the design-0001 arc (spec 0040, closed): additive shell + markdown extending orchestrate.lib.sh/.md + the hermetic e2e; ZERO override; full `tests/hooks/` (215) + `go test ./...` green. Closes the crash window (delegated command succeeded, ledger advance did not) so re-entry never double-allocates a spec or re-closes a closed one. Six pure helpers: `orch_status_ordinal`/`orch_status_token`/`orch_phase_completion_status` (status↔ordinal↔token), `orch_reentry` (adopt iff member-ordinal ≥ phase-completion-ordinal; `""`/`blocked` never adopt; adopt JUMPS the pointer to `orch_status_token(status)` so an out-of-band `review`+`closed` lands on `validated`, not a partial replay), `orch_find_member_spec` (crash-safe `new` adoption keyed on the **`informed-by: [design/<id>]`** frontmatter `spec:new` actually writes — NOT `design:`; ≥2 matches OR a get-frontmatter read failure → error, never a false zero), `orch_in_flight_phase` (bare 0039 token or first `phase=<p>`; malformed → error). Runbook: create-if-absent seeding (never re-`spec ""` on an existing row — the restart-clobber fix), `new`-first re-entry, structured `phase=review iteration=<n>`. Three hermetic e2e crash legs (fresh workspace each) prove it DIRECTLY via dispatch sentinels: no-re-close (validate sentinel==0), no-double-allocate (`new` sentinel==0 + dir-count + non-empty ledger spec), restart-safety. Divergence (honest): literal spec-id-before-dispatch is infeasible without changing `spec:new`'s allocation contract → superseded by post-hoc `orch_find_member_spec` adoption. Cross-model (codex changes-requested→resolved; claude-p approve-with-comments, both clean after the agents.toml fix) caught the `design:`→`informed-by` key error + the seeding-clobber + the missing `new` sentinel. Arc complete: 0037→0038→0039→0040.
- 2026-07-29 — Architect conductor ships: /speccraft:arch:orchestrate drives the per-member lifecycle (spec 0039, Spec B orchestration surface of design 0001; closed): shell + markdown (not Go) — a pure `commands/arch/orchestrate.lib.sh` + a `commands/arch/orchestrate.md` runbook; 28 bats tests, full `tests/hooks/` (192) + `go test ./...` green, **ZERO override** (shell/markdown are ungated by the TDD guard; bats is the RED oracle). Deterministic lib helpers: `orch_next_phase`/`orch_completed_token` (token machine `new→reviewed→planned→implemented→validated`; `revise` loops within `review`, never advances), `orch_should_pause` (checkpoint a: after `planned` before `implement`, `--straight-through`-suppressible), `orch_review_verdict` (pass/revise/escalate — checkpoint b), `orch_parse_decomposition` (first-tab split, indented-`#` comments, safe member charset `^[A-Za-z0-9._/-]+$` rejecting a literal `'`), `orch_dispatch` (`(cd '<m>' && /speccraft:spec:<...>)`, six pinned commands incl. `validate→spec:close`, single-quoted, never `--root`), `orch_validate` (`sh -c` tests gate), `orch_apply_result` (failure-isolated ledger transition via `ledger-set`, clears `in_flight` on EVERY completed attempt). `answer-questions` folded into `spec:new`; `validate→spec:close` writes the `closed` status 0038's reconcile keys `Done` on (the self-check's critical catch). Cross-model review reframed it to the orchestration **MVP**: resume-at-pointer + `in_flight` visibility + blocked-set/clear; **full crash-window idempotency deferred to spec 0040** (design 0001's mechanism spikes #1/#4). Runbook seeds member ROWS only (no double-`new`). Aux-config nits logged (agents.toml: codex `--sandbox workspace-write` one-token; claude-p argv overflow → stdin).
- 2026-07-28 — Conductor primitives ship: ledger.md + reconcile rollup (spec 0038, Spec B slice 1 of design 0001; closed): the Go/testable core the `/speccraft:arch:orchestrate` conductor (Spec 0039) will stand on, shipped before any orchestration (mirroring how 0037 shipped topology first). New `tools/internal/speccraft/ledger.go`: `ParseLedger`/`SetLedgerField` over a constrained `## design`/`### member` block grammar (first-`:` split preserving an interior `: `, BOM/CRLF tolerance, `# Ledger` preamble, first-wins, 11 `ledger.md:`-prefixed parse errors); a canonical writer on `AtomicWriteFile` with an injectable `ledgerNow` clock seam (same-value set = byte-identical no-op; `updated` conductor-managed, never settable); and a PURE `Reconcile` taking an INJECTED status resolver so it keys on the member's `spec.md` frontmatter — a disagreement test AND a source-scan prove the impl never references `last_completed_phase` — classifying Blocked→Closed→InProgress with `blocked`-overlay precedence, `Done` iff all Closed. Two `run()`-seam subcommands (`ledger-set`, `reconcile`, printing `done:` + `<status>\t<member>\t<spec-ref>`) at zero override; the ledger is history.md-class, NEVER `state.json` (behavioral + source-scan guards). ONE override (T1 bootstrap) as planned; a shared `resolveSpecStatus` (dual live/`.archive`, tri-state) was extracted from 0037's `get-status` and get-status refactored onto it at ZERO override by riding the standing failing reconcile/ledger-set cmd REDs. Deferred: consolidation → `/speccraft:sync`; no version bump (Spec 0039, the orchestrate command, completes Spec B and carries the release). 22 new tests; `go test ./...` + `go vet` green.
