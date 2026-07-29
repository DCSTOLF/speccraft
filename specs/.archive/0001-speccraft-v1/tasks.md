---
spec: "0001"
---

# Tasks — speccraft v1

## Phase 0 — Plugin scaffold

- [x] T0.1 — plugin.json with manifest fields
- [x] T0.2 — directory skeleton
- [x] T0.3 — README install instructions (already in README)
- [ ] T0.4 — verify plugin loads via /plugin (needs user verification; see notes.md)

## Phase 0.5 — Devcontainer + e2e harness

- [x] T0.5.1 — .devcontainer/devcontainer.json (Feature install, named volume) — seeded, verified correct
- [x] T0.5.2 — .devcontainer/Dockerfile (Go, jq, bats, build chain) — seeded, verified; fixed stale comment
- [x] T0.5.3 — .devcontainer/setup.sh (postCreateCommand) — seeded, verified correct
- [x] T0.5.4 — .devcontainer/install-mock-agents.sh (mock codex, opencode) — seeded, verified correct
- [x] T0.5.5 — tests/e2e/run.sh (skeleton; assertions added per later phase) — seeded full lifecycle; fixed stale .speccraft/graph check
- [x] T0.5.6 — .gitignore: .env.devcontainer, tests/e2e/.logs/
- [x] T0.5.7 — README "Development" section — added
- [ ] T0.5.8 — verify: host Claude Code unaffected; auth persists across rebuilds; e2e harness exits 0 (needs user verification; see notes.md)

## Phase 1 — SessionStart skill + hook

- [x] T1.1 — speccraft-context SKILL.md
- [x] T1.2 — hooks.json (all hooks registered; non-Phase-1 scripts are stubs)
- [x] T1.3 — session-start.sh (pure-bash root-walk; falls back to binary when available)
- [x] T1.4 — index.md template
- [ ] T1.5 — manual test: index.md content in session (needs user verification)

## Phase 2 — /speccraft:init and templates

- [x] T2.1 — guardrails/architecture/conventions/history templates
- [x] T2.2 — agents.toml template
- [x] T2.3 — speccraft-state binary (find-root, get, set, track-edit, reset-session, tasks-done-pct)
- [x] T2.4 — install-binaries.sh build pipeline (source-fallback + download paths)
- [x] T2.5 — commands/speccraft/init.md
- [x] T2.6 — gitignore append logic (in init.md command steps)
- [ ] T2.7 — e2e: init creates full tree (requires Phase 3+ for full e2e)

## Phase 3 — Spec lifecycle commands

- [x] T3.1 — spec-author agent
- [x] T3.2 — spec-critic agent
- [x] T3.3 — spec-format SKILL.md
- [x] T3.4 — commands/spec/new.md
- [x] T3.5 — memory-keeper agent (close mode; audit mode also included)
- [x] T3.6 — commands/spec/close.md
- [x] T3.7 — index.md auto-update on lifecycle events (in close.md command steps)
- [ ] T3.8 — e2e: new -> close happy path (Phase 8 full e2e)

## Phase 4 — TDD enforcement hook

- [x] T4.1 — speccraft-guard binary (active-spec check, prod-file detection, sibling-test resolution)
- [x] T4.2 — pre-tool-use.sh
- [x] T4.3 — post-tool-use.sh (track edits + drift-scan)
- [x] T4.4 — prompt-submit.sh
- [x] T4.5 — commands/spec/override.md
- [x] T4.6 — TDD invariant unit tests (sibling-test heuristic, guard tests)
- [ ] T4.7 — e2e: prod edit blocked without test edit (Phase 8 full e2e)
- [x] T4.8 — .github/workflows/release.yml (pure-Go matrix build, tarball + checksums upload)
- [x] T4.9 — scripts/install-binaries.sh (download, verify, extract; source-fallback)
- [ ] T4.10 — verify clean-machine install on each target platform (needs user verification; see notes.md)

## Phase 5 — Aux-agent delegation

- [x] T5.1 — agents.toml loader (tools/internal/delegate/toml.go)
- [x] T5.2 — aux-delegator agent
- [x] T5.3 — review/implement prompt templates
- [x] T5.4 — CLI mode (codex, opencode, claude -p) — in aux-delegator.md
- [x] T5.5 — ACP mode via acpx (with graceful absence) — in aux-delegator.md
- [x] T5.6 — commands/spec/delegate.md
- [x] T5.7 — aux-agents SKILL.md
- [ ] T5.8 — manual test against each CLI (requires live agents; verified via mocks in e2e)

## Phase 6 — Cross-model review + planning

- [x] T6.1 — cross-reviewer agent
- [x] T6.2 — parallel invocation documented in aux-delegator
- [x] T6.3 — commands/spec/review.md
- [x] T6.4 — commands/spec/review-code.md
- [x] T6.5 — review.md output schema (in cross-reviewer.md)
- [x] T6.6 — tdd-planner agent
- [x] T6.7 — commands/spec/plan.md (uses `find` for existing tests, no graph)
- [x] T6.8 — quorum / verdict synthesis logic (in cross-reviewer.md)

## Phase 7 — Drift detection + sync

- [x] T7.1 — speccraft-drift binary (regex mode only)
- [x] T7.2 — directive parser for `<!-- enforce: regex pattern="..." [scope="..."] -->`
- [x] T7.3 — wire post-tool-use.sh to scan-file
- [x] T7.4 — memory-keeper audit mode (in memory-keeper.md)
- [x] T7.5 — commands/speccraft/sync.md

## Phase 8 — Implement command + polish

- [x] T8.1 — commands/spec/implement.md
- [x] T8.2 — hooks/stop.sh
- [x] T8.3 — scripts/doctor.sh
- [ ] T8.4 — full e2e: empty repo to /spec:close (needs running Claude session)
- [ ] T8.5 — README polish (pending final e2e verification)
- [ ] T8.6 — CHANGELOG
