---
spec: "0001"
status: in-progress
strategy: phased-build
---

# Plan — 0001 speccraft v1

## Phase 0 — Plugin scaffold (½ day)
- `.claude-plugin/plugin.json`
- Empty directories: `commands/`, `agents/`, `skills/`, `hooks/`, `tools/`, `templates/`, `bin/` (with `.gitkeep`)
- `.gitignore` with `bin/*`, `.binary-version`
- `scripts/install-binaries.sh` (no-op stub)

**Done when:** plugin manifest exists and loads.

## Phase 0.5 — Devcontainer + e2e harness (1 day)
- `.devcontainer/` files (already seeded — verify/update as needed)
- `tests/e2e/run.sh` skeleton
- `.gitignore` entries for e2e artifacts

**Done when:** `bash tests/e2e/run.sh` exits 0 (smoke-only); auth persists across rebuild.

## Phase 1 — SessionStart skill + hook (½ day)
- `skills/speccraft-context/SKILL.md`
- `hooks/hooks.json` (SessionStart only)
- `hooks/session-start.sh` (no binary deps)
- `templates/speccraft/index.md`

**Done when:** index.md content appears in next session after manual creation.

## Phase 2 — `/speccraft:init` and templates (1 day)
- All files under `templates/speccraft/`
- `commands/speccraft/init.md`
- `speccraft-state` binary with subcommands: find-root, get, set, track-edit, reset-session, tasks-done-pct
- `scripts/install-binaries.sh` (build-from-source fallback)

**Done when:** `/speccraft:init` creates full `.speccraft/` tree in a fresh repo.

## Phase 3 — Spec lifecycle commands (2 days)
- `agents/spec-author.md`, `agents/spec-critic.md`
- `skills/spec-format/SKILL.md`
- `commands/spec/new.md`, `commands/spec/close.md`
- `agents/memory-keeper.md` (close mode)

**Done when:** `/spec:new` + `/spec:close` happy path works end-to-end.

## Phase 4 — TDD enforcement hook (1.5 days)
- `tools/cmd/speccraft-guard/main.go` (full TDD invariant per §15)
- `tools/internal/speccraft/` (path discovery, state I/O, sibling-test resolution)
- `hooks/pre-tool-use.sh`, `hooks/post-tool-use.sh`, `hooks/prompt-submit.sh`
- `commands/spec/override.md`
- `.github/workflows/release.yml` (matrix build)
- `scripts/install-binaries.sh` (full: download + verify + source fallback)

**Done when:** TDD invariant blocks/allows correctly; release workflow produces artifacts.

## Phase 5 — Aux-agent delegation (2 days)
- `agents/aux-delegator.md`
- `tools/internal/delegate/` (TOML loader, command builder, ACP support)
- `commands/spec/delegate.md`
- `templates/prompts/review.md`, `templates/prompts/implement.md`
- `skills/aux-agents/SKILL.md`

**Done when:** `/spec:delegate codex "..."` shells out, captures output, presents diff.

## Phase 6 — Cross-model review + planning (1.5 days)
- `agents/cross-reviewer.md`
- `commands/spec/review.md`, `commands/spec/review-code.md`
- `commands/spec/plan.md`, `agents/tdd-planner.md`

**Done when:** `/spec:review` produces review.md; `/spec:plan` generates test-first plan.

## Phase 7 — Drift detection + sync (1 day)
- `tools/cmd/speccraft-drift/main.go` (regex mode only)
- `commands/speccraft/sync.md`
- Extend `memory-keeper` for audit mode
- Wire drift-scan into `post-tool-use.sh`

**Done when:** `enforce: regex` in conventions.md triggers drift warning on match.

## Phase 8 — Implement command + polish (1 day)
- `commands/spec/implement.md`
- `hooks/stop.sh`
- `scripts/doctor.sh`
- Full e2e test

**Done when:** Scripted init→spec→review→plan→implement→close passes without intervention.
