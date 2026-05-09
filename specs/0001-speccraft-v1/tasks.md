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

- [ ] T1.1 — speccraft-context SKILL.md
- [ ] T1.2 — hooks.json (SessionStart)
- [ ] T1.3 — session-start.sh (no binary deps)
- [ ] T1.4 — index.md template
- [ ] T1.5 — manual test: index.md content in session

## Phase 2 — /speccraft:init and templates

- [ ] T2.1 — guardrails/architecture/conventions/history templates
- [ ] T2.2 — agents.toml template
- [ ] T2.3 — speccraft-state binary (find-root, get, set, track-edit, reset-session, tasks-done-pct)
- [ ] T2.4 — install-binaries.sh build pipeline
- [ ] T2.5 — commands/speccraft/init.md
- [ ] T2.6 — gitignore append logic
- [ ] T2.7 — e2e: init creates full tree

## Phase 3 — Spec lifecycle commands

- [ ] T3.1 — spec-author agent
- [ ] T3.2 — spec-critic agent
- [ ] T3.3 — spec-format SKILL.md
- [ ] T3.4 — commands/spec/new.md
- [ ] T3.5 — memory-keeper agent (close mode)
- [ ] T3.6 — commands/spec/close.md
- [ ] T3.7 — index.md auto-update on lifecycle events
- [ ] T3.8 — e2e: new -> close happy path

## Phase 4 — TDD enforcement hook

- [ ] T4.1 — speccraft-guard binary (active-spec check, prod-file detection, sibling-test resolution)
- [ ] T4.2 — pre-tool-use.sh
- [ ] T4.3 — post-tool-use.sh (track edits; drift-scan stub)
- [ ] T4.4 — prompt-submit.sh
- [ ] T4.5 — commands/spec/override.md
- [ ] T4.6 — TDD invariant unit tests (sibling-test heuristic)
- [ ] T4.7 — e2e: prod edit blocked without test edit
- [ ] T4.8 — .github/workflows/release.yml (pure-Go matrix build, tarball + checksums upload)
- [ ] T4.9 — scripts/install-binaries.sh (download, verify, extract; source-fallback)
- [ ] T4.10 — verify clean-machine install on each target platform

## Phase 5 — Aux-agent delegation

- [ ] T5.1 — agents.toml loader
- [ ] T5.2 — aux-delegator agent
- [ ] T5.3 — review/implement prompt templates
- [ ] T5.4 — CLI mode (codex, opencode, claude -p)
- [ ] T5.5 — ACP mode via acpx (with graceful absence)
- [ ] T5.6 — commands/spec/delegate.md
- [ ] T5.7 — aux-agents SKILL.md
- [ ] T5.8 — manual test against each CLI

## Phase 6 — Cross-model review + planning

- [ ] T6.1 — cross-reviewer agent
- [ ] T6.2 — parallel invocation in aux-delegator
- [ ] T6.3 — commands/spec/review.md
- [ ] T6.4 — commands/spec/review-code.md
- [ ] T6.5 — review.md output schema
- [ ] T6.6 — tdd-planner agent
- [ ] T6.7 — commands/spec/plan.md (uses `find` for existing tests, no graph)
- [ ] T6.8 — quorum / verdict synthesis logic

## Phase 7 — Drift detection + sync

- [ ] T7.1 — speccraft-drift binary (regex mode only)
- [ ] T7.2 — directive parser for `<!-- enforce: regex pattern="..." [scope="..."] -->`
- [ ] T7.3 — wire post-tool-use.sh to scan-file
- [ ] T7.4 — memory-keeper audit mode
- [ ] T7.5 — commands/speccraft/sync.md

## Phase 8 — Implement command + polish

- [ ] T8.1 — commands/spec/implement.md
- [ ] T8.2 — hooks/stop.sh
- [ ] T8.3 — scripts/doctor.sh
- [ ] T8.4 — full e2e: empty repo to /spec:close
- [ ] T8.5 — README polish
- [ ] T8.6 — CHANGELOG
