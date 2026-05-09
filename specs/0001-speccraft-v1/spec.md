---
id: "0001"
title: "speccraft v1"
status: in-progress
created: 2026-05-09
authors: [claude]
packages: ["tools/cmd/speccraft-state", "tools/cmd/speccraft-guard", "tools/cmd/speccraft-drift", "tools/internal/speccraft", "tools/internal/delegate"]
related-specs: []
---

# Spec 0001 — speccraft v1

## 1. Summary

speccraft is a Claude Code plugin that turns code changes into spec-first, test-driven workflows. Every change is preceded by a versioned spec; every implementation is preceded by failing tests; every repo carries a small, always-injected memory of guardrails, architecture, conventions, and history. Heavy reading and second-opinion reviews are offloaded to auxiliary CLI agents (Codex, OpenCode, Claude `-p`) so the main session stays focused.

v1 targets Go repositories. Multi-language and multi-repo are explicitly out of scope but the design is forward-compatible. For codebase-wide structural queries (call graphs, symbol search, layer enforcement), speccraft integrates with [CodeGraphContext](https://github.com/CodeGraphContext/CodeGraphContext) as an optional MCP server rather than embedding its own indexer.

## 2. Goals

1. **Spec-first by enforcement, not exhortation.** A `PreToolUse` hook hard-blocks edits to production code unless an active spec exists and (for production files) a sibling test file has been touched more recently in the session.
2. **Versioned intent.** Specs live in the repo at `specs/NNNN-slug/` and capture WHAT, WHY, HOW, and what actually shipped.
3. **Always-on memory.** `.speccraft/index.md` (~one screen) is injected on every `SessionStart`. Deeper files are pulled in on demand by the auto-invoked skill.
4. **Cross-model review.** `/spec:review` and `/spec:review-code` route to Codex / OpenCode / Claude `-p` via a configurable adapter. ACP via `acpx` is opt-in.
5. **Drift detection.** Deterministic post-edit regex checks for `enforce:`-tagged guardrails and conventions surface contradictions immediately. Memory additions batch at `/spec:close`.
6. **Composable, not monolithic.** Codebase-wide structural queries (call graphs, layer enforcement, "where is X used") are deferred to dedicated tools.
7. **Forward-compatible.** Root discovery and a small set of clean extension points keep multi-language, multi-repo, and richer enforcement doors open without v1 cost.

## 3. Non-goals (v1)

- Building a code graph or symbol index inside speccraft.
- AST-based convention enforcement. Regex enforcement only in v1.
- Multi-repo workspaces or federation across `.speccraft/` roots.
- Cross-language edge resolution (HTTP/gRPC/CLI boundaries).
- Marketplace publishing. v1 ships installable via local path / git URL.
- A GUI or web dashboard. CLI only.

## 4. Glossary

- **spec** — a directory under `specs/` capturing one unit of intended change.
- **plan** — the test-first decomposition of a spec into red→green→refactor steps.
- **guardrail** — a hard rule (`never X`, `always Y`) loaded into every session.
- **convention** — a stylistic or structural rule, optionally with `enforce:` mode.
- **history** — append-only ADR log of significant changes and decisions.
- **aux-agent** — an external CLI coding agent (Codex, OpenCode, Claude `-p`, …).
- **active spec** — the spec marked `status: in-progress` when a code edit happens.
- **production file** — a non-test source file. For Go: `*.go` not matching `*_test.go`.
- **sibling test** — for a Go production file `pkg/foo/bar.go`, any `*_test.go` in the same directory.

## 5. Architecture

Two layers:

- **Plugin layer** (this codebase) — slash commands, subagents, skills, hooks, helper Go binaries.
- **Repo layer** (created by `/speccraft:init`) — `.speccraft/`, `specs/`. The plugin reads and writes here; nothing in the plugin itself is repo-specific.

Key components:
- SessionStart hook injects `.speccraft/index.md` into context
- UserPromptSubmit hook nudges toward spec-first
- PreToolUse hook (`speccraft-guard`) enforces active-spec + TDD invariant
- PostToolUse hook tracks session edits + runs regex drift scan
- Slash commands orchestrate the spec lifecycle
- Subagents handle Socratic authoring, TDD planning, memory keeping, aux delegation, cross-review

## 6. Repo layer: `.speccraft/`

Directory layout:
```
.speccraft/
├── index.md              # 1-page session-start summary (always injected)
├── guardrails.md         # hard rules
├── architecture.md       # current shape
├── conventions.md        # style/patterns, with enforce: tags
├── history.md            # append-only ADR log
├── agents.toml           # aux-agent registry
└── state.json            # runtime state (gitignored)
```

`enforce:` directives in HTML comments drive the drift scanner. v1 supports regex mode only:
- `enforce: regex pattern="..." [scope="..."]` — pattern grep. `scope` is a glob; `!` prefix means exclude.

## 7. Repo layer: `specs/NNNN-slug/`

Layout per spec:
```
specs/NNNN-slug/
├── spec.md         # WHAT + WHY + acceptance criteria
├── plan.md         # test-first plan
├── review.md       # cross-model critique (output of /spec:review)
├── tasks.md        # decomposed task list
└── changelog.md    # what shipped vs spec; created by /spec:close
```

IDs are 4-digit zero-padded. Slugs are kebab-case derived from title. Status state machine: `draft` → `reviewed` → `planned` → `in-progress` → `closed` | `archived`.

## Acceptance criteria (v1 release)

1. `claude /plugin install speccraft@<marketplace>` works on macOS and Linux.
2. `/speccraft:init` produces the full repo layout in a fresh Go module.
3. SessionStart injects `index.md` content into context.
4. `/spec:new` produces a structured `spec.md` via the spec-author agent.
5. TDD invariant blocks production-file edits when no sibling test was touched in the session.
6. `/spec:delegate codex "..."` succeeds when `codex` is on PATH; surfaces a clean error when not.
7. `/spec:review` with two aux agents in parallel produces a `review.md`.
8. `enforce: regex` directives produce drift warnings on matching post-edit content.
9. `/spec:close` produces a changelog and proposes updates to `history.md` and `conventions.md`.
10. Doctor script reports correctly on a clean machine vs. one missing dependencies.
