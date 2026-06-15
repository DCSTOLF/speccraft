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

specs/0020-robust-e2e-revise-noop-assertion/

## Recent decisions (last 3)

- 2026-06-15 — Bump version to 1.1.0 across all live surfaces (spec 0019): coordinated 1.0.0 → 1.1.0 bump across the two packaging manifests (`.claude-plugin/plugin.json`, `marketplace.json`) and the three binary `const version` declarations (speccraft-state/guard/drift); hardcoded-const mechanism unchanged, only its value. Each const bump gated by a real RED→GREEN version test (test asserts the NEW value so it fails pre-edit, satisfying the TDD gate on a one-line const change); manifests verified by a grep oracle (positive 1.1.0 + negative no-stray-1.0.0), since they aren't assertable from `package main`. `--version` parity across the three binaries is now test-pinned; the drift binary gained its first test file. New convention: "version bumps pin the new value with a sibling test." Build-time `-ldflags` injection (P2-5, deferred from spec 0018) remains a follow-up. Planned with `--skip-review`; `go test ./...` green. Pushed to `main` (commit `158f5f5`).
- 2026-06-13 — Real red→green TDD check for Go/Python/JS-TS; runner primitive generalized beyond Rust (spec 0018): closed technical-review finding P0-1 — the red→green invariant was a true observed-failure check only for Rust, while Go/Python/JS-TS merely verified a sibling test was *touched* this session (`hasSiblingTestEdited` main.go:390; JS/TS session-membership main.go:446-452), so a blank-line edit unlocked production edits with no test run. Now all four languages run the session's just-added sibling test through a real runner and require an observed failure (`siblingRedCheck`). The spec-0005 runner primitive (then scoped Rust-only, "non-goal for Go/Python") was generalized with `GoAdapter`/`PytestAdapter`/`JSTSAdapter` (one shared JS/TS adapter; JS/TS differ only by configured `[tdd.<lang>] command`) reusing `classifyOutcome`, resolved by a new `AdapterForLanguage(lang,cfg)(Runner,bool)` factory. The "which test" rule mirrors Rust's just-added model via a new capture mechanism: `Session.RedCandidates` (single-writer, `red_candidates,omitempty`, cleared on SessionStart) is populated in the `IsTestFile` dispatch branch by `captureRedCandidates`, diffing pre/post-edit test-ids via regex extractors (`lang_testids.go`). Two deliberate divergences from Rust: (1) an **empty just-added set BLOCKS** (Rust allows-on-empty because it has `rust_test_baseline`; baseline-less languages would reopen P0-1 via blank-line touch — claude-p caught the trap); (2) an unresolved runner **fails closed** (BLOCK "no test runner available"), never falling back to the touch-check (D2). AC9: real invocation bounded by `context.WithTimeout(30s)`; timeout/error → Go error (no new `Outcome`) → block. AC6: build/collection failure is not a valid RED. Two-round cross-model review (codex+claude-p): round-1 changes-requested (5 blockers) → round-2 approve-with-comments, quorum 1. Mid-implementation amendment (2026-06-12, AC13, 4th use of the pattern after 0013/0015/0017): a brand-new symbol's just-added test can't compile until the symbol exists → pre-edit run is a build failure (AC6 won't treat as RED) → the symbol-introduction edit needs a one-shot `/speccraft:spec:override` (identical to Rust); `run.sh` step 9 rewritten test-edit → override → prod edit; stale `/spec:override` strings corrected to `/speccraft:spec:override`. New convention: "capture-at-test-edit RedCandidates model for runtime-runner languages without a persisted baseline". architecture.md scrubbed of both spec-0005 non-goal sites (AC11), pinned by a new `docs_parity_test.go` grep oracle; hermetic e2e fixtures `python_cycle.sh`/`javascript_cycle.sh` rewritten to the red-check model with a configured-stub runner. Closes P0-1 only (P0-2/P1/P2 findings tracked for follow-ups). Deferred follow-up: apply-edit-in-memory red-check to eliminate the new-symbol override. Close gate: PR #1 merged to `main` (merge `ddc1136`, feature `8c74168`); CI green (`unit`/`hooks`/`e2e-language-only` on PR; credit-gated `e2e-devcontainer` exercises AC13 at step 9 on push to main).
- 2026-06-12 — Pin the e2e harness model explicitly; Sonnet default reverted after it failed the validation gate (spec 0017): `run_claude()` in `tests/e2e/run.sh` now passes `--model "${CLAUDE_MODEL:-claude-opus-4-8}"` as the first arg after `-p`, making the e2e lifecycle's model selection explicit/pinned (no longer inheriting a mutable account/CLI default) and overridable via `CLAUDE_MODEL`; `--help` gained an `env:` block (CLAUDE_MODEL + CLAUDE_BIN) and the spec-0008 capture probe gained check #4 (`grep -qE` on the extracted `run_claude` body). Original thesis was a cheaper Sonnet 4.6 default; both reviewers (codex, claude-p) approve-with-comments and flagged that switching the default tier changes the model under test — claude-p named the next `e2e-devcontainer` run as the validation gate. That gate (run 27367642623, commit `537b769`) FAILED at `[9/13] TDD invariant` with a real assertion failure (no ENVIRONMENT_FAILURE tag): on Sonnet 4.6 the model reached for `/speccraft:spec:override` on the GREEN step then stalled without implementing `farewell()`. Contrast: prior commit `4529323`'s Opus run (27348320071) failed the same step only with `ENVIRONMENT_FAILURE: credit_exhausted` (env, not defect). Mid-implementation amendment (2026-06-12, third use after 0013/0015) reverted default Sonnet 4.6 → Opus 4.8, keeping the override var + docs + probe; AC1/AC3 updated in place. Cost-optimization goal dropped honestly; the explicit/overridable-model win (codex's stronger framing) survives. No new convention (0014 "structural over content" + 0008 ENVIRONMENT_FAILURE already cover the model-behaviour-vs-env distinction), no architecture change. Close gate: CI run 27386675522 (commit `a016dae`, Opus) fully green incl. `e2e-devcontainer`
