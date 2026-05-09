---
project: speccraft
version: 1.0.0
status: ready-to-implement
target: claude-code-plugin
audience: claude-code (the implementing agent)
language-v1: go
dev-environment: devcontainer (Linux, Ubuntu 22.04)
last-updated: 2026-05-05
---

# speccraft — v1 Specification

> Meta-note: This document is the spec for speccraft itself. If speccraft were already in use here, it would live at `specs/0001-speccraft-v1/spec.md`. The implementation plan in §16 plays the role of `plan.md`. Tasks for execution are in §17.

---

## 1. Summary

speccraft is a Claude Code plugin that turns code changes into spec-first, test-driven workflows. Every change is preceded by a versioned spec; every implementation is preceded by failing tests; every repo carries a small, always-injected memory of guardrails, architecture, conventions, and history. Heavy reading and second-opinion reviews are offloaded to auxiliary CLI agents (Codex, OpenCode, Claude `-p`) so the main session stays focused.

v1 targets Go repositories. Multi-language and multi-repo are explicitly out of scope but the design is forward-compatible. For codebase-wide structural queries (call graphs, symbol search, layer enforcement), speccraft integrates with [CodeGraphContext](https://github.com/CodeGraphContext/CodeGraphContext) as an optional MCP server rather than embedding its own indexer.

---

## 2. Goals

1. **Spec-first by enforcement, not exhortation.** A `PreToolUse` hook hard-blocks edits to production code unless an active spec exists and (for production files) a sibling test file has been touched more recently in the session.
2. **Versioned intent.** Specs live in the repo at `specs/NNNN-slug/` and capture WHAT, WHY, HOW, and what actually shipped.
3. **Always-on memory.** `.speccraft/index.md` (~one screen) is injected on every `SessionStart`. Deeper files are pulled in on demand by the auto-invoked skill.
4. **Cross-model review.** `/spec:review` and `/spec:review-code` route to Codex / OpenCode / Claude `-p` via a configurable adapter. ACP via `acpx` is opt-in.
5. **Drift detection.** Deterministic post-edit regex checks for `enforce:`-tagged guardrails and conventions surface contradictions immediately. Memory additions batch at `/spec:close`.
6. **Composable, not monolithic.** Codebase-wide structural queries (call graphs, layer enforcement, "where is X used") are deferred to dedicated tools — see [§20.1](#201-codebasewide-queries) for the recommended integration with CodeGraphContext.
7. **Forward-compatible.** Root discovery and a small set of clean extension points keep multi-language, multi-repo, and richer enforcement doors open without v1 cost.

## 3. Non-goals (v1)

- Building a code graph or symbol index inside speccraft. Use [CodeGraphContext](https://github.com/CodeGraphContext/CodeGraphContext) (or any MCP-compatible code-intelligence server) when you need that capability — see [§20.1](#201-codebasewide-queries).
- AST-based convention enforcement. Regex enforcement only in v1; AST rules are deferred to v1.x and will likely consume CodeGraphContext output rather than maintaining their own parser.
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
- **sibling test** — for a Go production file `pkg/foo/bar.go`, any `*_test.go` in the same directory (Go's idiomatic test colocation).

---

## 5. Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                       Claude Code session                        │
│                                                                   │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  SessionStart hook → injects .speccraft/index.md         │   │
│  │  speccraft-context skill → pulls deeper files on demand  │   │
│  └──────────────────────────────────────────────────────────┘   │
│                              │                                    │
│  user prompt ──► UserPromptSubmit hook (spec-first nudge)        │
│                              │                                    │
│  Claude reasons, calls tools                                      │
│                              │                                    │
│  Edit/Write ──► PreToolUse hook ──► speccraft-guard (Go)         │
│                              │       checks: active spec? TDD?    │
│                              │       sibling-test heuristic       │
│                              ▼                                    │
│  PostToolUse hook ──► track session edits                         │
│                    └► drift scan (regex against guardrails)      │
│                                                                   │
│  /spec:* commands ──► subagents ──► (optionally) aux-delegator   │
│                                         │                         │
│                                         ▼                         │
│                                  shell out: codex exec / opencode │
│                                  run / claude -p / acpx            │
│                                                                   │
│  Optional MCP: CodeGraphContext for codebase-wide queries         │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
                  ┌──────────────────────────┐
                  │   <repo>/                │
                  │     .speccraft/          │  ← always-injected memory
                  │       index.md           │
                  │       guardrails.md      │
                  │       architecture.md    │
                  │       conventions.md     │
                  │       history.md         │
                  │       agents.toml        │
                  │     specs/               │  ← versioned intent
                  │       0001-foo/          │
                  │         spec.md          │
                  │         plan.md          │
                  │         review.md        │
                  │         tasks.md         │
                  │         changelog.md     │
                  └──────────────────────────┘
```

Two layers:

- **Plugin layer** (this codebase) — slash commands, subagents, skills, hooks, helper Go binaries.
- **Repo layer** (created by `/speccraft:init`) — `.speccraft/`, `specs/`. The plugin reads and writes here; nothing in the plugin itself is repo-specific.

---

## 6. Repo layer: `.speccraft/`

### 6.1 Directory layout

```
.speccraft/
├── index.md              # 1-page session-start summary (always injected)
├── guardrails.md         # hard rules
├── architecture.md       # current shape
├── conventions.md        # style/patterns, with enforce: tags
├── history.md            # append-only ADR log
├── agents.toml           # aux-agent registry
└── state.json            # runtime state: active spec, session edits (gitignored)
```

### 6.2 `index.md` (template)

```markdown
# <project name>

<one-sentence project description>

## Stack
<bulleted list of major technologies, e.g.: Go 1.22, Postgres 15, Redis>

## Architecture in one paragraph
<3-5 sentences describing layering and key boundaries>

## Hard rules (see guardrails.md)
- <rule 1>
- <rule 2>
- <rule 3>

## Where to look
- Domain logic: `internal/domain/`
- HTTP handlers: `internal/http/`
- Storage: `internal/store/`

## Active spec
<auto-updated by /spec:new and /spec:close — points to current spec dir or "none">

## Recent decisions (last 3)
<auto-updated; pulls last 3 entries from history.md>
```

The `Active spec` and `Recent decisions` sections are managed by speccraft and rewritten on lifecycle events. Everything else is human-edited.

### 6.3 `guardrails.md` (example)

```markdown
# Guardrails

Hard rules. Violations block at the hook level when `enforce:` is set.

## Security
- Never log secrets, API keys, tokens, or PII. <!-- enforce: regex pattern="(api[_-]?key|token|password|secret)\\s*[:=]" -->
- Never call `os/exec` with user-controlled input without an allowlist.
- All external HTTP calls must go through `internal/httpclient`.

## Data
- Never write SQL outside `internal/store/`. <!-- enforce: regex pattern="(?i)\\b(SELECT|INSERT|UPDATE|DELETE)\\b.*FROM" scope="!internal/store/" -->
- Migrations are append-only. Never edit a committed migration file.

## Process
- Never bypass the spec-first invariant by editing files outside Claude Code.
- Never commit `.speccraft/state.json` (gitignored).
```

The HTML comments after each rule are the enforcement directives. v1 supports one mode:

- `enforce: regex pattern="..." [scope="..."]` — pattern grep. `scope` is a glob; `!` prefix means exclude.

Rules without an `enforce:` directive are advisory — Claude reads them at session start, but the hook does not act on them. Structural rules ("no direct HTTP outside `internal/httpclient`", "domain layer must not import http") that need AST or call-graph awareness are deferred to v1.x; teams that need them today can run [CodeGraphContext](https://github.com/CodeGraphContext/CodeGraphContext) as an MCP server alongside speccraft.

### 6.4 `architecture.md` (example skeleton)

```markdown
# Architecture

## Layering
1. `cmd/` — entrypoints
2. `internal/http/` — HTTP transport, no business logic
3. `internal/domain/` — pure business logic, no I/O
4. `internal/store/` — persistence
5. `internal/httpclient/` — outbound HTTP

Layer N may depend only on N+1, N+2, …. Layer N must not import layer N-k. (Advisory in v1; enforced via CodeGraphContext if configured.)
## Key decisions
- <decision> — why — link to ADR in history.md

## Boundaries
- Inbound: HTTP only (no message queue in v1)
- Outbound: third-party APIs via `internal/httpclient` with circuit breaker
```

### 6.5 `conventions.md` (example)

```markdown
# Conventions

## Naming
- Exported types and functions: PascalCase
- Unexported: camelCase
- Test functions: `Test_<Subject>_<Scenario>` <!-- enforce: regex pattern="^func Test[A-Z]" scope="**/*_test.go" -->

## Errors
- Wrap with `fmt.Errorf("...: %w", err)`, never bare returns of foreign errors.
- Sentinel errors live alongside the package that returns them.

## Tests
- Table-driven tests are preferred for >2 cases.
- Every exported function in `internal/domain/` should have at least one test. (Advisory in v1.)

## Logging
- Use `slog` only. No `fmt.Println` outside `cmd/`. <!-- enforce: regex pattern="fmt\\.Print(ln|f)?" scope="!cmd/" -->
```

### 6.6 `history.md` (example)

```markdown
# History

Append-only. Newest first.

## 2026-05-03 — speccraft adopted
**Spec:** specs/0001-speccraft-v1/
**Decision:** Adopt speccraft for spec-first TDD workflow.
**Why:** ad-hoc changes were drifting from intent; reviews were inconsistent.
**Consequence:** all future code changes go through `/spec:new`.

## 2026-05-01 — Switch to slog
**Spec:** specs/0023-structured-logging/
**Decision:** Replace logrus with stdlib slog.
**Why:** stdlib option matured; one fewer dependency.
**Consequence:** log format changed; log aggregation queries updated.
```

### 6.7 `agents.toml` (full example)

```toml
# speccraft aux-agent registry
# Each agent has a `mode`: "cli" or "acp".
# CLI mode shells out directly. ACP mode goes through `acpx`.

[defaults]
review_quorum = 1     # how many aux agents must agree for /spec:review
review_timeout_s = 600

[[agents]]
name = "codex"
mode = "cli"
cmd = ["codex", "exec", "--full-auto"]
input = "stdin"       # "stdin" | "argv" | "file"
strengths = ["refactoring", "review"]

[[agents]]
name = "opencode"
mode = "cli"
cmd = ["opencode", "run"]
input = "argv"
strengths = ["analysis", "planning"]

[[agents]]
name = "claude-p"
mode = "cli"
cmd = ["claude", "-p"]
input = "argv"
strengths = ["general"]

# Opt-in ACP. Requires `acpx` installed.
[[agents]]
name = "codex-acp"
mode = "acp"
acp_agent = "codex"
strengths = ["refactoring"]
enabled = false
```

### 6.8 `state.json`

```json
{
  "version": 1,
  "active_spec": "0001-speccraft-v1",
  "session": {
    "id": "<claude-session-id>",
    "edited_test_files": ["pkg/auth/handler_test.go"],
    "edited_prod_files": []
  }
}
```

`session.*` fields are reset on `SessionStart`. `edited_test_files` tracks recency for the TDD invariant. The file is gitignored — it's machine state, not project intent.

---

## 7. Repo layer: `specs/NNNN-slug/`

### 7.1 Layout

```
specs/0042-rate-limiting/
├── spec.md         # WHAT + WHY + acceptance criteria
├── plan.md         # test-first plan
├── review.md       # cross-model critique (output of /spec:review)
├── tasks.md        # decomposed task list
└── changelog.md    # what shipped vs spec; created by /spec:close
```

Slugs are kebab-case, derived from title. IDs are 4-digit zero-padded, allocated by `/spec:new` as `max(existing) + 1` (gaps allowed).

### 7.2 `spec.md` (full example)

```markdown
---
id: "0042"
title: "Rate limiting on public API"
status: in-progress     # draft | reviewed | planned | in-progress | closed | archived
created: 2026-05-03
authors: [claude]
packages: ["internal/http", "internal/middleware"]
related-specs: ["0019-public-api"]
---

# Spec 0042 — Rate limiting on public API

## Why

Public API is hit by aggressive scrapers; current 99p latency degrades during
spikes. We need per-IP and per-key rate limiting at the edge of the HTTP layer.

## What

Add a token-bucket rate limiter applied as middleware to all `/api/v1/*`
routes. Limits:

- Anonymous (per-IP): 60 req/min, burst 10.
- Authenticated (per-API-key): 600 req/min, burst 60.

Headers `X-RateLimit-Limit`, `X-RateLimit-Remaining`, `X-RateLimit-Reset` on
every response. `429 Too Many Requests` with `Retry-After` on exceed.

## Acceptance criteria

1. Anonymous client making 100 req/min sees ~60 successes and ~40 `429`s.
2. Authenticated client making 700 req/min sees ~600 successes and ~100 `429`s.
3. Rate-limit headers present on all 200 and 429 responses.
4. Limiter state survives a single server restart (Redis-backed).
5. Internal endpoints (`/internal/*`, `/healthz`) are unaffected.

## Out of scope

- Distributed rate limiting across regions.
- User-configurable limits.
- Cost-based limiting (large responses count more).

## Open questions

- Should we pre-warm Redis with known API keys? — *resolved: no, lazy is fine.*
```

### 7.3 `plan.md` (full example)

```markdown
---
spec: "0042"
status: in-progress
strategy: tdd
---

# Plan — 0042 Rate limiting

## Test-first sequence

### Step 1 — Token bucket primitive (RED)
- Add `internal/middleware/ratelimit/bucket_test.go`:
  - `Test_Bucket_AllowsBurst`
  - `Test_Bucket_RefillsAtRate`
  - `Test_Bucket_BlocksWhenEmpty`
- Tests fail: `bucket.go` does not exist.

### Step 2 — Token bucket primitive (GREEN)
- Implement `internal/middleware/ratelimit/bucket.go` with `New(rate, burst)`,
  `Allow() bool`, `Remaining() int`, `Reset() time.Time`.
- All step-1 tests pass.

### Step 3 — HTTP middleware (RED)
- Add `internal/middleware/ratelimit/middleware_test.go`:
  - `Test_Middleware_AnonymousLimit`
  - `Test_Middleware_AuthenticatedLimit`
  - `Test_Middleware_HeadersPresent`
  - `Test_Middleware_BypassesInternalRoutes`

### Step 4 — HTTP middleware (GREEN)
- Implement `Middleware(cfg Config) func(http.Handler) http.Handler`.
- Use `internal/store/redis` for shared state.

### Step 5 — Wire-up (RED)
- Update `internal/http/router_test.go` to assert middleware is mounted on
  `/api/v1/*` and not on `/internal/*` or `/healthz`.

### Step 6 — Wire-up (GREEN)
- Mount in `internal/http/router.go`.

### Step 7 — Refactor
- Extract config loading to `internal/config/ratelimit.go`.
- Confirm all tests still pass.

## Delegation

- Step 1 RED test design → delegate to `codex` (strong on test-case enumeration).
- Step 7 refactor review → delegate to `opencode`.
- Final code review (after step 6) → `/spec:review-code` (quorum 1).

## Risk

- Redis becomes single point of failure → mitigation: fail-open (allow on Redis
  error), tracked as separate spec if SLA tightens.
```

### 7.4 `tasks.md` (example, machine-managed)

```markdown
---
spec: "0042"
---

# Tasks

- [x] T1 — Bucket tests written (step 1 RED)
- [x] T2 — Bucket impl (step 2 GREEN)
- [ ] T3 — Middleware tests (step 3 RED)
- [ ] T4 — Middleware impl (step 4 GREEN)
- [ ] T5 — Router tests (step 5 RED)
- [ ] T6 — Router wire-up (step 6 GREEN)
- [ ] T7 — Refactor pass (step 7)
- [ ] T8 — Update architecture.md (note middleware layer)
```

### 7.5 `review.md` (output of `/spec:review`)

```markdown
---
spec: "0042"
reviewers: [codex, opencode]
quorum: 1
verdict: changes-requested
generated: 2026-05-03T14:22:00Z
---

# Cross-model review — 0042

## codex

**Verdict:** changes-requested

Concerns:
1. Acceptance criterion 4 ("survives a single server restart") implies sticky
   state but the spec doesn't say what happens to in-flight tokens — should
   they be discarded? This will affect test design.
2. No mention of clock skew between app servers and Redis.

Suggestions:
- Add an explicit "restart semantics" subsection.
- Specify time source (Redis TIME vs app clock).

## opencode

**Verdict:** approve-with-comments

Concerns:
1. Out-of-scope item "cost-based limiting" might be re-asked for soon; consider
   a minimal hook in the bucket interface.

## Synthesis

Add a "Restart semantics" subsection to the spec. Clock-source decision needed
before plan. Cost-based hook is optional for v1 and can be deferred.

**Action:** spec author updates spec.md, re-runs `/spec:review`, then proceeds
to `/spec:plan`.
```

### 7.6 `changelog.md` (output of `/spec:close`)

```markdown
---
spec: "0042"
closed: 2026-05-08
---

# Changelog — 0042 Rate limiting

## What shipped vs spec

- All acceptance criteria met. Smoke-tested against staging for 24h.
- Deviation: chose Redis Lua script for atomicity (not specified). See ADR.

## Files touched
- internal/middleware/ratelimit/{bucket.go,middleware.go,config.go}
- internal/http/router.go
- internal/config/ratelimit.go
- migrations/20260503_*.sql (none)

## ADR proposed for history.md
2026-05-08 — Rate limiting on public API
- Decision: token bucket, Redis-backed, fail-open.
- Why: simplest model meeting acceptance criteria; Redis already in stack.
- Consequence: hard dep on Redis for `/api/v1/*`. Tracked in dependency.md.

## Conventions proposed
- New: "All HTTP middleware lives under `internal/middleware/<name>/`."
  Rationale: enforced naturally by spec 0042; codifying.
```

---

## 8. Plugin layout

### 8.1 File tree

```
speccraft/
├── .claude-plugin/
│   └── plugin.json
├── README.md
├── commands/
│   ├── speccraft/
│   │   ├── init.md
│   │   └── sync.md
│   └── spec/
│       ├── new.md
│       ├── review.md
│       ├── plan.md
│       ├── implement.md
│       ├── delegate.md
│       ├── review-code.md
│       └── close.md
├── agents/
│   ├── spec-author.md
│   ├── spec-critic.md
│   ├── tdd-planner.md
│   ├── aux-delegator.md
│   ├── cross-reviewer.md
│   └── memory-keeper.md
├── skills/
│   ├── speccraft-context/
│   │   └── SKILL.md
│   ├── spec-format/
│   │   └── SKILL.md
│   └── aux-agents/
│       └── SKILL.md
├── hooks/
│   ├── hooks.json
│   ├── session-start.sh
│   ├── prompt-submit.sh
│   └── post-tool-use.sh
├── tools/                        # Go source for helper binaries
│   ├── go.mod
│   ├── cmd/
│   │   ├── speccraft-guard/      # PreToolUse TDD + active-spec check
│   │   │   └── main.go
│   │   ├── speccraft-drift/      # PostToolUse regex drift scan
│   │   │   └── main.go
│   │   └── speccraft-state/      # state.json read/write helper
│   │       └── main.go
│   └── internal/
│       ├── speccraft/            # path discovery, state I/O
│       └── delegate/             # aux-agent invocation
├── templates/                    # what /speccraft:init copies
│   └── speccraft/
│       ├── index.md
│       ├── guardrails.md
│       ├── architecture.md
│       ├── conventions.md
│       ├── history.md
│       └── agents.toml
├── bin/                          # gitignored; populated by install-binaries.sh
│   └── .gitkeep
├── scripts/
│   ├── install-binaries.sh       # download release tarball or build fallback
│   └── doctor.sh                 # diagnostic
├── .devcontainer/                # development + e2e isolation (see §18)
│   ├── devcontainer.json
│   ├── Dockerfile
│   ├── setup.sh
│   └── install-mock-agents.sh
├── tests/
│   ├── hooks/                    # bats tests per hook script
│   └── e2e/
│       └── run.sh                # full lifecycle, hermetic, runs in container
└── .github/
    └── workflows/
        ├── ci.yml                # unit, hook, e2e jobs
        └── release.yml           # matrix build → GitHub Releases
```

### 8.2 `plugin.json`

```json
{
  "name": "speccraft",
  "version": "1.0.0",
  "description": "Spec-first, test-driven development with cross-model review and regex-enforced guardrails for Claude Code.",
  "author": {
    "name": "Daniel Stolf <daniel.stolf@perforce.com>",
    "url": "https://github.com/dcstolf/speccraft"
  },
  "license": "MIT",
  "homepage": "https://github.com/dcstolf/speccraft",
  "keywords": ["spec", "tdd", "code-review", "delegation", "go"]
}
```

### 8.3 Binary distribution strategy

Helper binaries are **pre-compiled** and shipped via GitHub Releases. End-users do not need `go` or any other toolchain installed. Binaries are pure-Go (no CGO, no C deps), which keeps cross-compilation trivial.

**On first use:** `scripts/install-binaries.sh` (invoked from `hooks/session-start.sh`) detects the user's OS/arch, downloads the matching tarball from the release tagged with the plugin's current version, verifies SHA-256 checksums against `checksums.txt`, and extracts into `<plugin>/bin/`. Subsequent sessions read `<plugin>/.binary-version`, see the version matches, and skip the download (≤10 ms).

**Targets:** `linux-amd64`, `linux-arm64`, `macos-amd64`, `macos-arm64`. Windows is supported via WSL in v1; native Windows is a v1.x follow-up.

**Build pipeline:** `.github/workflows/release.yml` runs an `os × arch` matrix on tag push using `CGO_ENABLED=0`. Artifacts and `checksums.txt` upload to the GitHub Release.

**Fallbacks (in priority order):**
1. Pre-populated `<plugin>/bin/` (e.g., manually placed by an admin in air-gapped environments).
2. Download from GitHub Releases.
3. Build from source under `tools/` if `go` ≥ 1.22 is available. Last-resort path for contributors and unsupported platforms.

**PATH handling:** every hook script begins with `export PATH="$CLAUDE_PLUGIN_ROOT/bin:$PATH"` so binaries are found regardless of installation route.

**Plugin git repo size:** the `bin/` directory is `.gitignore`d. Source under `tools/` stays in the plugin repo for transparency, contribution, and the source-fallback path.

---

## 9. Slash commands

Each command is a markdown file with YAML frontmatter. Frontmatter is the command contract; body is the prompt Claude executes.

### 9.1 `/speccraft:init`

`commands/speccraft/init.md`:

```markdown
---
description: "Bootstrap speccraft in this repository"
argument-hint: "[--force]"
allowed-tools: ["Bash", "Read", "Write", "Edit"]
---

You are bootstrapping speccraft in the current repository.

Steps:

1. Run `bash $CLAUDE_PLUGIN_ROOT/scripts/install-binaries.sh` to ensure helper
   binaries are built.

2. Locate the repo root by walking up from `cwd` to the nearest directory
   containing `.git`. If none, error.

3. If `.speccraft/` already exists and `$1` is not `--force`, refuse and tell
   the user to use `--force` to overwrite.

4. Copy `$CLAUDE_PLUGIN_ROOT/templates/speccraft/*` to `<repo>/.speccraft/`.

5. Create `<repo>/specs/.gitkeep`.

6. Append `.speccraft/state.json` to `.gitignore` (creating if absent).

7. Open `.speccraft/index.md`, `.speccraft/architecture.md`, and
   `.speccraft/conventions.md` in the conversation and ask the user to
   personalize them. Specifically prompt for:
   - Project description (one sentence)
   - Stack
   - Top-level architectural layering
   - Their three most important guardrails

8. Print a summary and next-step suggestion: `/spec:new "..."`.

   If the user mentions they want call-graph or symbol-search capabilities,
   suggest installing CodeGraphContext as an MCP server alongside speccraft
   (see README §"Recommended companions").
```

### 9.2 `/spec:new`

`commands/spec/new.md`:

```markdown
---
description: "Start a new spec via Socratic interview, then draft spec.md"
argument-hint: "<short title>"
allowed-tools: ["Read", "Write", "Edit", "Bash"]
---

Start a new spec titled: "$1"

Steps:

1. Confirm `.speccraft/` exists. If not, suggest `/speccraft:init` and stop.

2. Read `.speccraft/state.json`. If `active_spec` is set and that spec's
   status is `in-progress`, ask the user whether to (a) close the active
   spec first, (b) park it (set status: blocked), or (c) cancel.

3. Allocate next ID: list `specs/NNNN-*` directories, take max + 1, zero-pad
   to 4. Slugify "$1" (lowercase, kebab-case, drop non-[a-z0-9-]).

4. Create `specs/<id>-<slug>/` and a stub `spec.md` with frontmatter
   (status: draft).

5. Invoke the `spec-author` subagent to interview the user Socratically,
   filling in the spec template:
   - Why (motivation, problem, evidence)
   - What (scope, acceptance criteria — must be testable)
   - Out of scope
   - Open questions

   The interview must produce at least 3 acceptance criteria, each phrased
   as an observable behavior. If the user resists detail, the agent should
   note open questions but not fabricate.

6. Save `spec.md`. Update `state.json` to point `active_spec` at the new dir.

7. Update `.speccraft/index.md` "Active spec" section.

8. Suggest next step: `/spec:review` (recommended) or `/spec:plan` (skip review).
```

### 9.3 `/spec:review`

`commands/spec/review.md`:

```markdown
---
description: "Cross-model review of the active spec via aux agents"
argument-hint: "[--quorum N] [--agents codex,opencode]"
allowed-tools: ["Read", "Write", "Bash"]
---

Run cross-model review on the active spec.

Steps:

1. Read `.speccraft/state.json` for `active_spec`. If none, error.

2. Read `.speccraft/agents.toml`. Determine which agents to invoke:
   - If `--agents` flag provided, use that list (validating each exists).
   - Else, all agents with `enabled != false`.

3. For each selected agent, invoke `aux-delegator` subagent with payload:
   - The spec.md content
   - The relevant slice of `.speccraft/` (index.md + guardrails.md +
     architecture.md + conventions.md)
   - The review prompt template (see agents/aux-delegator.md)

   Run agents in parallel. Per-agent timeout from `agents.toml.defaults.review_timeout_s`.

4. Collect verdicts. Each agent returns: verdict (approve | approve-with-comments
   | changes-requested | reject), concerns[], suggestions[].

5. Invoke `cross-reviewer` subagent to synthesize the responses into a
   coherent `review.md` and an action recommendation.

6. Write `specs/<active>/review.md`.

7. If quorum met (default 1 approve or approve-with-comments), update spec
   status to `reviewed`. Else leave at `draft` and surface the synthesis.

8. Suggest next step:
   - If reviewed: `/spec:plan`
   - If changes-requested: edit spec.md, then re-run `/spec:review`
```

### 9.4 `/spec:plan`

`commands/spec/plan.md`:

```markdown
---
description: "Turn the active spec into a test-first plan and tasks list"
allowed-tools: ["Read", "Write", "Edit", "Bash"]
---

Generate plan.md and tasks.md from the active spec.

Steps:

1. Read active spec. Require status >= `reviewed` (or status `draft` if user
   passes `--skip-review`; warn loudly).

2. List existing test files in directories matching `spec.packages` (using
   `find <pkg> -name '*_test.go'`). Pass this to the planner so it can
   reason about which test files to extend vs. create.

3. Invoke `tdd-planner` subagent with:
   - spec.md content
   - relevant `.speccraft/` files
   - the existing-tests inventory from step 2

   The planner must produce a sequence of RED→GREEN→REFACTOR steps. Each
   GREEN step must be preceded by a RED step. The planner names files and
   test functions concretely.

4. Write `plan.md` and `tasks.md`. Update spec status to `planned`.

5. Suggest next step: `/spec:implement` or manually start with the first
   RED test.
```

### 9.5 `/spec:implement`

`commands/spec/implement.md`:

```markdown
---
description: "Execute the active plan TDD-style; optionally delegate tasks"
argument-hint: "[--delegate <agent>:<task-id>,...]"
allowed-tools: ["Read", "Write", "Edit", "Bash", "Task"]
---

Execute the active plan.

Steps:

1. Read active spec, plan.md, tasks.md. Set spec status to `in-progress`
   (and persist active_spec).

2. For each unchecked task in tasks.md, in order:
   a. If task is in the `--delegate` list, route via `aux-delegator`.
      Otherwise, execute in the main session.
   b. Honor TDD discipline: before editing any production file, the
      corresponding test file must have been edited more recently in this
      session. The PreToolUse hook enforces this.
   c. Run `go test ./...` after each step. RED steps expect failure;
      GREEN steps expect success.
   d. On step completion, mark the task `[x]` in tasks.md.

3. After last task, run full test suite. If green, suggest `/spec:close`.

4. If a step fails or stalls (>3 failed retries), pause and surface the
   blockage. Do not silently continue.
```

### 9.6 `/spec:delegate`

`commands/spec/delegate.md`:

```markdown
---
description: "Hand a discrete task to an aux agent and integrate the result"
argument-hint: "<agent> <task description>"
allowed-tools: ["Read", "Write", "Bash", "Task"]
---

Delegate "$2..." to aux agent "$1".

Steps:

1. Validate agent exists in `agents.toml`.
2. Invoke `aux-delegator` subagent with the task and a curated context slice
   (active spec + relevant `.speccraft/` files + the file paths the task
   touches, read directly).
3. The aux agent returns a diff or a written response. If a diff, present
   it for user approval before applying. If a response, integrate into the
   conversation.
4. If a diff was applied, run tests.
```

### 9.7 `/spec:review-code`

`commands/spec/review-code.md`:

```markdown
---
description: "Cross-model review of the current diff against the active spec"
argument-hint: "[--base <ref>]"
allowed-tools: ["Read", "Bash"]
---

Cross-model review of uncommitted changes (or `git diff <base>`).

Steps:

1. Compute the diff: default `git diff` (working tree) plus staged.
   With `--base`, use `git diff <base>...HEAD`.

2. For each enabled agent in `agents.toml`, invoke `aux-delegator` with:
   - the diff
   - the active spec.md
   - relevant `.speccraft/` files (especially conventions.md, guardrails.md)
   - the code-review prompt

3. Synthesize via `cross-reviewer`. Output to stdout (do not write to spec
   dir; this is per-iteration, not per-spec).

4. If any agent flags a `guardrail-violation` or `convention-violation`,
   surface prominently. The user decides whether to fix or override.
```

### 9.8 `/spec:close`

`commands/spec/close.md`:

```markdown
---
description: "Close the active spec: write changelog, propose memory updates"
allowed-tools: ["Read", "Write", "Edit", "Bash"]
---

Close the active spec.

Steps:

1. Read active spec. Verify all tasks in tasks.md are `[x]`. If not, ask
   the user to confirm closure or re-open the spec.

2. Compute the diff between when the spec started (commit recorded in spec
   frontmatter `started_at_sha` if set, else the active-spec creation time
   resolved to a commit SHA) and HEAD.

3. Invoke `memory-keeper` subagent with:
   - The spec, plan, tasks
   - The full diff
   - Current `.speccraft/architecture.md`, `conventions.md`, `history.md`

   The agent proposes:
   - A `changelog.md` for the spec (what shipped vs spec, deviations)
   - An ADR entry for `history.md`
   - Convention additions/changes
   - Architecture updates (if any)

4. Show all proposed changes for user approval. Apply approved ones.

5. Set spec status to `closed`. Clear `active_spec` in state.json.

6. Update `.speccraft/index.md` Active spec and Recent decisions sections.
```

### 9.9 `/speccraft:sync`

`commands/speccraft/sync.md`:

```markdown
---
description: "Reconcile .speccraft/ memory with reality. Detect drift."
allowed-tools: ["Read", "Write", "Edit", "Bash"]
---

Run a drift scan and a memory-keeper audit pass.

Steps:

1. Run `speccraft-drift scan-all` over `enforce:`-tagged conventions and
   guardrails. Report violations with file:line references.

2. Invoke `memory-keeper` subagent in audit mode with:
   - the drift report
   - `git log --since=<last sync>` (or full log if first sync) for context
   - a sampled list of changed files since last sync

   Propose:
   - New conventions implied by repeated patterns visible in recent diffs
   - Architecture updates implied by new top-level packages
   - Stale entries in conventions.md / architecture.md

3. Present proposals for approval. Apply approved ones.
```

---

## 10. Subagents

Subagents are markdown files with YAML frontmatter. The body is the system prompt.

### 10.1 `agents/aux-delegator.md` (full)

```markdown
---
name: aux-delegator
description: "Invokes external CLI coding agents (Codex, OpenCode, Claude -p, ACP). Use whenever a task should be offloaded to a non-Claude-Code model for parallelism, second opinion, or cost reasons."
tools: [Bash, Read]
model: sonnet
---

You are the aux-delegator. Your job is to take a task + context bundle and
shell out to the requested aux agent, then return its output cleanly.

# Inputs you receive
- agent_name (must exist in `.speccraft/agents.toml`)
- task: the prompt text to send
- context_files: list of paths to include
- mode: "review" | "implement" | "analyze" (controls prompt template)

# Steps
1. Read `.speccraft/agents.toml`. Find the agent by name. If `mode` is `acp`
   and `acpx` is not on PATH, error.

2. Compose the prompt:
   - For "review" mode, prefix with the review template at
     `$CLAUDE_PLUGIN_ROOT/templates/prompts/review.md`.
   - For "implement" mode, prefix with the implement template.
   - Append context files inline (use clear `## File: <path>` headers).
   - Append the task last.

3. Build the command:
   - CLI mode: from `agent.cmd` and `agent.input`.
     - `input: stdin` → write composed prompt to stdin.
     - `input: argv` → pass as last argv.
     - `input: file` → write to a tempfile and pass `--file <path>`.
   - ACP mode: `acpx <agent.acp_agent> <prompt>`.

4. Set timeout from `agents.toml.defaults.review_timeout_s` (default 600).
   For Bash tool, request timeout >= timeout + 60s.

5. Capture stdout. Treat non-zero exit as error; return structured failure.

6. Parse the output:
   - If review mode: extract verdict, concerns[], suggestions[]. If the
     agent didn't follow structure, ask Claude to do best-effort
     interpretation (don't fail).
   - If implement mode: extract diff blocks (```diff fences) if any.
   - Else: return raw text.

7. Return a structured result object. Do NOT apply diffs yourself; that's
   the caller's responsibility.

# Failure modes
- Agent not on PATH: report clearly. Suggest install command from
  `agents.toml` if `install_hint` is set.
- Timeout: kill the process. Return partial output if any.
- Auth error: report. Suggest `agent auth` invocation.
```

### 10.2 Other subagents — frontmatter and one-line role

```markdown
---
name: spec-author
description: "Drafts and refines spec.md via Socratic interviewing. Use during /spec:new."
tools: [Read, Write, Edit]
model: opus
---
```
Body: detailed Socratic protocol — asks why before what, demands testable acceptance criteria, refuses vague answers without flagging them as open questions.

```markdown
---
name: spec-critic
description: "Reviews a spec for ambiguity, missing edge cases, untestable criteria. Use during /spec:review or as a self-check before delegating."
tools: [Read]
model: opus
---
```

```markdown
---
name: tdd-planner
description: "Turns a reviewed spec into RED→GREEN→REFACTOR steps with concrete file/test names. Use during /spec:plan."
tools: [Read, Bash]
model: opus
---
```

```markdown
---
name: cross-reviewer
description: "Synthesizes multiple aux-agent review outputs into a coherent verdict and review.md. Use after /spec:review collects responses."
tools: [Read, Write]
model: sonnet
---
```

```markdown
---
name: memory-keeper
description: "Proposes updates to .speccraft/ (history.md, conventions.md, architecture.md) based on completed specs and detected drift. Use during /spec:close and /speccraft:sync."
tools: [Read, Write, Edit, Bash]
model: opus
---
```

---

## 11. Skills

### 11.1 `skills/speccraft-context/SKILL.md` (full)

```markdown
---
name: speccraft-context
description: "Always-on: loads .speccraft/index.md and pulls deeper memory files (guardrails, architecture, conventions, history) when the user's task requires them. Trigger whenever the conversation involves code changes, architecture decisions, or anything project-specific in a repo that has a .speccraft/ directory."
---

# speccraft-context

You are working in a repository that uses speccraft. The session-start hook
has already injected `.speccraft/index.md` into context. This skill teaches
you when and how to pull deeper files.

## When to read each file

- `.speccraft/guardrails.md` — before writing code; before any tool call that
  could violate a hard rule. Read once per session, early.
- `.speccraft/conventions.md` — before writing code in a new package; before
  /spec:plan; before reviewing code.
- `.speccraft/architecture.md` — when the change crosses package boundaries;
  when discussing layering, dependencies, or new modules.
- `.speccraft/history.md` — when about to make a decision that resembles a
  prior one; when investigating "why is this like this".

## Codebase-wide structural queries

For "where is X called?", "what does file Y export?", or "which tests cover this code?" — speccraft does NOT carry a built-in code graph in v1. Use whatever the user has configured:

- If [CodeGraphContext](https://github.com/CodeGraphContext/CodeGraphContext) is connected as an MCP server, prefer its tools for structural queries — they're pre-indexed and far cheaper than re-scanning the source.
- Otherwise, fall back to `rg` / `grep` for symbol search and `git grep` for diff-aware queries. Acknowledge the cost: structural questions on a large repo may want a CodeGraphContext install.

speccraft itself only knows about session edits (via `state.json`) and the literal contents of `.speccraft/`.

## When NOT to use this skill

- The repo has no `.speccraft/` directory. The skill auto-detects and
  silently no-ops.
- The user is asking a generic question unrelated to the repo's code.

## Updating memory

Do not silently rewrite `.speccraft/` files. All updates go through
`/spec:close` or `/speccraft:sync` so the user reviews them.
```

### 11.2 `skills/spec-format/SKILL.md`

Body: the canonical spec.md/plan.md templates, frontmatter rules, status state machine, and examples. Used by `spec-author` and `tdd-planner`.

### 11.3 `skills/aux-agents/SKILL.md`

Body: reference card for each aux agent's strengths, invocation patterns, known quirks (e.g., "Codex `exec` requires `--full-auto` for non-interactive use"; "OpenCode benefits from `opencode run --file` for long prompts").

---

## 12. Hooks

### 12.1 `hooks/hooks.json`

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/hooks/session-start.sh"
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/hooks/prompt-submit.sh"
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/hooks/pre-tool-use.sh"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/hooks/post-tool-use.sh"
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/hooks/stop.sh"
          }
        ]
      }
    ]
  }
}
```

### 12.2 `hooks/session-start.sh`

```bash
#!/usr/bin/env bash
# SessionStart hook: ensure binaries present, find .speccraft/, inject index.md.
set -euo pipefail

# Make plugin-shipped binaries discoverable.
export PATH="$CLAUDE_PLUGIN_ROOT/bin:$PATH"

# Ensure binaries are present (download from GitHub Releases on first use,
# no-op when version stamp matches).
"$CLAUDE_PLUGIN_ROOT/scripts/install-binaries.sh" >&2

# Find .speccraft/ by walking up from cwd.
ROOT="$(speccraft-state find-root 2>/dev/null || true)"
if [ -z "$ROOT" ]; then
  # Not a speccraft repo. Quietly succeed.
  exit 0
fi

# Reset session fields in state.json.
speccraft-state reset-session

# Inject index.md as additional system context.
# Claude Code's hook protocol: print to stdout, it's appended to context.
echo "## speccraft memory (always-injected)"
echo
cat "$ROOT/.speccraft/index.md"
echo
echo "_For deeper detail, the speccraft-context skill knows when to load"
echo "guardrails.md, architecture.md, conventions.md, or history.md._"
```

### 12.3 `hooks/prompt-submit.sh`

```bash
#!/usr/bin/env bash
# UserPromptSubmit hook: nudge if user requests code change with no active spec.
set -euo pipefail
export PATH="$CLAUDE_PLUGIN_ROOT/bin:$PATH"

ROOT="$(speccraft-state find-root 2>/dev/null || true)"
[ -z "$ROOT" ] && exit 0

# Read prompt from stdin (Claude Code provides JSON).
INPUT="$(cat)"
PROMPT="$(echo "$INPUT" | jq -r '.prompt // ""')"

# Heuristic: does the prompt request code change?
if echo "$PROMPT" | grep -iqE '\b(implement|add|fix|refactor|change|update|modify|write|create)\b.*\.(go|md|json|toml)\b|^(fix|add|implement|build|create) '; then
  ACTIVE="$(speccraft-state get active_spec)"
  if [ -z "$ACTIVE" ] || [ "$ACTIVE" = "null" ]; then
    cat <<EOF
## speccraft note
You're requesting a code change but no spec is active. The spec-first invariant
will block edits to production files. Consider:

- \`/spec:new "<title>"\` to start a spec, or
- \`/spec:implement\` if a spec is planned but not in-progress, or
- prefix with \`scratch:\` if this is throwaway work in tests or docs.
EOF
  fi
fi
```

### 12.4 `hooks/pre-tool-use.sh`

```bash
#!/usr/bin/env bash
# PreToolUse hook for Edit|Write: enforce spec-first + TDD invariant.
set -euo pipefail
export PATH="$CLAUDE_PLUGIN_ROOT/bin:$PATH"

ROOT="$(speccraft-state find-root 2>/dev/null || true)"
[ -z "$ROOT" ] && exit 0

# Delegate to the Go binary; it does the real work and exits with 2 on block.
exec speccraft-guard pre-tool-use
```

`speccraft-guard pre-tool-use` reads the hook JSON from stdin, decides:

- Is the target file inside `<root>`? If not, allow.
- Is the target inside `.speccraft/` or `specs/`? Always allow (these are the meta files).
- Is there an `active_spec`? If no, **block** with a message suggesting `/spec:new`. Exception: tests/docs/scratch files (see below) are allowed.
- Is the file a production file (Go: `*.go` not `*_test.go`)? If yes, run the sibling-test invariant: was any `*_test.go` in the same directory edited more recently in this session? If no, **block**.
- Else allow.

Exit code 2 blocks; stderr message is fed back to Claude.

### 12.5 `hooks/post-tool-use.sh`

```bash
#!/usr/bin/env bash
# PostToolUse: track session edits + regex drift scan.
set -euo pipefail
export PATH="$CLAUDE_PLUGIN_ROOT/bin:$PATH"

ROOT="$(speccraft-state find-root 2>/dev/null || true)"
[ -z "$ROOT" ] && exit 0

INPUT="$(cat)"
FILE="$(echo "$INPUT" | jq -r '.tool_input.file_path // ""')"

# Track session edits for the TDD invariant.
speccraft-state track-edit "$FILE"

# Drift scan: only on enforce:-tagged rules. Fast (regex only in v1).
DRIFT="$(speccraft-drift scan-file "$FILE" 2>/dev/null || true)"
if [ -n "$DRIFT" ]; then
  echo "## speccraft drift"
  echo "$DRIFT"
fi
```

### 12.6 `hooks/stop.sh`

```bash
#!/usr/bin/env bash
# Stop hook: gentle close-out reminder.
set -euo pipefail
export PATH="$CLAUDE_PLUGIN_ROOT/bin:$PATH"

ROOT="$(speccraft-state find-root 2>/dev/null || true)"
[ -z "$ROOT" ] && exit 0

ACTIVE="$(speccraft-state get active_spec)"
if [ -n "$ACTIVE" ] && [ "$ACTIVE" != "null" ]; then
  TASKS_DONE="$(speccraft-state tasks-done-pct)"
  if [ "$TASKS_DONE" = "100" ]; then
    echo "## speccraft"
    echo "All tasks for $ACTIVE are complete. Consider \`/spec:close\`."
  fi
fi
```

---

## 13. Codebase-wide queries (deferred)

Earlier drafts of speccraft included a built-in tree-sitter–based code graph stored under `.speccraft/graph/`. v1 removes it. The reasons:

- It nearly doubled the v1 implementation cost and shifted the project's center of gravity from "spec workflow tool" to "code intelligence tool".
- A graph that drifts from the source produces *confidently wrong* answers, and keeping it fresh added meaningful complexity to every hook.
- A high-quality alternative already exists.

**Recommended companion: [CodeGraphContext](https://github.com/CodeGraphContext/CodeGraphContext)**, an MCP server that gives any MCP-compatible client (including Claude Code) call-graph and symbol-search capabilities across a codebase. Users who want "where is X called?", "what does Y export?", or layer-enforcement rules should install it as an MCP server alongside speccraft. The two are complementary: speccraft owns intent, memory, and TDD discipline; CodeGraphContext owns structural queries.

A future v1.x or v2 may consume CodeGraphContext output to power `enforce: ast`-style rules and `/spec:plan` blast-radius analysis. v1 leaves these features advisory.


## 14. Drift detection

`speccraft-drift` is a small Go binary with two subcommands:

- `scan-file <path>` — fast path used by `PostToolUse`: only runs rules whose `scope:` glob matches `<path>`.
- `scan-all` — full pass over the repo, used by `/speccraft:sync`.

It reads `enforce:` directives from HTML comments in `guardrails.md` and `conventions.md`. v1 supports a single mode:

### 14.1 `enforce: regex pattern="..." [scope="..."]`

Runs `regexp.MustCompile(pattern).FindAllIndex` on each in-scope file. `scope` is a glob; `!` prefix excludes. Default scope is the entire repo.

Output (per violation):

```
internal/handlers/charge.go:42: guardrails.md#data: matches /SELECT.*FROM/ (rule: no SQL outside internal/store/)
```

### 14.2 AST-based rules (deferred)

Earlier drafts of this spec included `enforce: ast rule="..."` — a registry of structural rules (layer dependency, domain coverage, no-direct-http) implemented in Go against a tree-sitter graph. These are **deferred**. When AST rules return in v1.x, they'll be powered by [CodeGraphContext](https://github.com/CodeGraphContext/CodeGraphContext) output rather than a speccraft-internal parser. v1 leaves any structural rule advisory: Claude reads it from `architecture.md` / `conventions.md` at session start, but no hook acts on it.

---

## 15. The TDD invariant in detail

`speccraft-guard pre-tool-use` reads the hook JSON:

```json
{
  "tool_name": "Edit",
  "tool_input": {
    "file_path": "/abs/path/internal/auth/handler.go",
    "old_string": "...",
    "new_string": "..."
  },
  "session_id": "...",
  "cwd": "..."
}
```

Logic:

```
1.  Resolve file path relative to repo root.
2.  If outside repo root → allow.
3.  If inside .speccraft/ or specs/ → allow.
4.  If inside docs/, *.md, or scratch/ → allow.
5.  If file matches *_test.go or *.test.* → allow, and mark test edit in
    state.json.session.edited_test_files.
6.  Read state.json. If active_spec is null → block:
      "No active spec. Edits to production code are blocked. Use /spec:new
       or set status: in-progress on an existing spec."
7.  Open active spec frontmatter. If status != in-progress → block:
      "Active spec '<id>' is in status '<s>'. Move to in-progress before
       editing production code."
8.  Determine sibling tests for the production file:
      - Production: <dir>/<base>.go
      - Sibling tests: any file matching <dir>/*_test.go
    (Go's idiomatic test colocation: tests live next to source in the same
    package directory. v1 makes this a hard assumption.)
9.  Intersect sibling-test paths with state.json.session.edited_test_files.
10. If intersection is empty → block:
      "TDD invariant: edit a test in <dir>/ this session before editing the
       production file. If no test exists yet, create one (RED) first.
       Sibling test files found: <list>. (None? Create <dir>/<base>_test.go.)"
11. Else allow, and mark prod edit in state.json.session.edited_prod_files.
```

Block = exit code 2 with message on stderr (Claude Code feeds stderr back to the model).

**Why sibling-test heuristic, not graph-based coverage:** v1 leans on Go's strict convention that tests live in the same directory as the source they test. This is wrong for languages where tests live in separate trees (e.g., Java's `src/test/java/`), which is fine — v1 only targets Go. For projects that want symbol-precise coverage tracking ("which test exercises this exact function?"), the answer in v1 is the same as for other structural queries: install [CodeGraphContext](https://github.com/CodeGraphContext/CodeGraphContext) and a future v1.x can consume its data. The sibling-test heuristic is deliberately coarse: it enforces TDD discipline ("you wrote a test in this package this session before touching production code") without claiming more precision than it has.

**Override:** if the user explicitly invokes a one-time bypass via `/spec:override "<reason>"`, the next single edit is allowed and the reason is logged into the active spec's `tasks.md` under a "Bypasses" section. v1 implements `/spec:override` but logs only; no automatic enforcement of "one-time" — it sets a session flag that's cleared after first use.

---

## 16. Implementation plan

Phased. Each phase has concrete done-criteria. Phases are ordered to allow useful intermediate states (you can stop after any phase and have something working).

### Phase 0 — Plugin scaffold (½ day)
**Build:**
- `.claude-plugin/plugin.json`
- Empty directories: `commands/`, `agents/`, `skills/`, `hooks/`, `tools/`, `templates/`, `bin/` (with `.gitkeep`)
- `.gitignore` with `bin/*` (except `.gitkeep`) and `.binary-version`
- `README.md` with install instructions
- `scripts/install-binaries.sh` (no-op stub for now)

**Done when:** `claude /plugin marketplace add <local-path>` followed by `/plugin install speccraft@<marketplace>` shows the plugin as Enabled. No commands or hooks yet, just the manifest.

### Phase 0.5 — Devcontainer + e2e harness (1 day)
**Build:**
- `.devcontainer/devcontainer.json` with Feature install and named volume mount
- `.devcontainer/Dockerfile` with Go, jq, bats, build chain
- `.devcontainer/setup.sh` (postCreateCommand)
- `.devcontainer/install-mock-agents.sh`
- `tests/e2e/run.sh` (skeleton; assertions added as later phases land)
- `.gitignore` entries for `.env.devcontainer`, `tests/e2e/.logs/`
- `README.md` "Development" section pointing engineers at the devcontainer

**Done when:**
- `Dev Containers: Reopen in Container` opens the workspace, Claude Code is installed, OAuth completes inside the container and persists across rebuilds.
- `bash tests/e2e/run.sh` exits 0 against the empty plugin (just verifies the harness — assertions for actual commands come in later phases).
- A documented checklist confirms: host Claude Code unaffected during container teardown; `/tmp/speccraft-e2e-*` is cleaned up; named volume retains auth across `Dev Containers: Rebuild`.

**Why before Phase 1:** every subsequent phase adds hooks. A buggy hook in Phase 4 (TDD enforcement) without Phase 0.5 in place would block edits across every Claude Code session on the host until the plugin is manually disabled. Doing Phase 0.5 first means every later phase is built and tested in isolation from day one.

### Phase 1 — SessionStart skill + hook (½ day)
**Build:**
- `skills/speccraft-context/SKILL.md`
- `hooks/hooks.json` with SessionStart only
- `hooks/session-start.sh` (without binary dependency yet — just check for `.speccraft/index.md` and cat it)
- `templates/speccraft/index.md` (template)

**Done when:** Creating `.speccraft/index.md` manually in a test repo causes its content to appear in the next Claude Code session's context. Skill description triggers correctly when the user asks repo-specific questions.

### Phase 2 — `/speccraft:init` and templates (1 day)
**Build:**
- All files under `templates/speccraft/`
- `commands/speccraft/init.md`
- Initial Go binary `speccraft-state` (in `tools/cmd/speccraft-state/`) with subcommands: `find-root`, `get`, `set`, `track-edit`, `reset-session`, `tasks-done-pct`. State file is `.speccraft/state.json`.
- For local development before the release pipeline exists (Phase 5), `scripts/install-binaries.sh` falls back to `go build` from `tools/`. End users in Phase 2 are developers building from source; the pre-compiled distribution path is wired up in Phase 5.

**Done when:** In a fresh git repo, running `/speccraft:init` creates the full `.speccraft/` tree, prompts for personalization, and updates `.gitignore`. `state.json` is read/writable via the binary.

### Phase 3 — Spec lifecycle commands (2 days)
**Build:**
- `agents/spec-author.md`, `agents/spec-critic.md`
- `skills/spec-format/SKILL.md`
- `commands/spec/new.md`, `commands/spec/close.md`
- `agents/memory-keeper.md` (close-time only; sync mode in Phase 8)
- Wire `state.json` to track `active_spec`.

**Done when:** `/spec:new "Add health endpoint"` walks through interview, creates `specs/0001-add-health-endpoint/spec.md`, sets active. `/spec:close` proposes a changelog and history.md update; user approves; files are written.

### Phase 4 — TDD enforcement hook (1.5 days)
**Build:**
- `tools/cmd/speccraft-guard/main.go` — full TDD invariant logic per §15: active-spec check, sibling-test heuristic (any `*_test.go` in same dir more recently edited this session), exit-code-2 block with stderr message.
- `tools/internal/speccraft/` — path discovery, state I/O, sibling-test resolution.
- `hooks/pre-tool-use.sh`
- `hooks/post-tool-use.sh` (track edits only; drift-scan stub, fully wired in Phase 7)
- `hooks/prompt-submit.sh`
- `commands/spec/override.md`
- `.github/workflows/release.yml` — matrix build (`linux-amd64`, `linux-arm64`, `macos-amd64`, `macos-arm64`), pure-Go (`CGO_ENABLED=0`), tarball + checksums upload.
- `scripts/install-binaries.sh` — full version: detect platform, download release tarball, verify checksums, extract to `bin/`, source-fallback if Go available.

**Done when:** With an active spec in `in-progress` and no test edited in the session, editing a `*.go` file in `pkg/foo/` is blocked. After editing `pkg/foo/something_test.go` in the same session, edits to `pkg/foo/*.go` are allowed. With no active spec, all production edits blocked. Tests/docs/scratch always allowed. A pushed git tag produces a complete release; `install-binaries.sh` downloads and installs on a clean machine with no Go.

### Phase 5 — Aux-agent delegation (2 days)
**Build:**
- `agents/aux-delegator.md`
- `tools/internal/delegate/` — TOML loader, command builder, ACP support.
- `commands/spec/delegate.md`
- `templates/prompts/review.md`, `templates/prompts/implement.md`
- `templates/speccraft/agents.toml` (the default content from §6.7)
- `skills/aux-agents/SKILL.md`

**Done when:** `/spec:delegate codex "Generate table-driven tests for internal/auth/hash.go"` shells out, captures output, presents a diff (if produced), and the user can accept/reject. Works for codex, opencode, claude-p. ACP path tested with acpx if installed; gracefully errors if not.

### Phase 6 — Cross-model review + planning (1.5 days)
**Build:**
- `agents/cross-reviewer.md`
- `commands/spec/review.md`, `commands/spec/review-code.md`
- Parallel agent invocation in `aux-delegator`.
- `commands/spec/plan.md` and `agents/tdd-planner.md` — planner reads the spec + a directory listing of existing tests in declared packages (no graph; just `find`).

**Done when:** `/spec:review` invokes 2+ agents in parallel (timeout-bounded), `cross-reviewer` produces a `review.md`, status flows to `reviewed`. `/spec:review-code` works on a current diff and prints the synthesis. `/spec:plan` generates a real test-first plan with concrete file paths.

### Phase 7 — Drift detection + sync (1 day)
**Build:**
- `tools/cmd/speccraft-drift/main.go` — regex-mode only (`enforce: regex pattern="..." [scope="..."]`); reads directives from HTML comments in `guardrails.md` / `conventions.md`.
- `commands/speccraft/sync.md`
- Extend `memory-keeper` to handle audit mode (drift report + recent-diff inputs).
- Extend `hooks/post-tool-use.sh` to call `speccraft-drift scan-file`.

**Done when:** Adding `<!-- enforce: regex pattern="fmt\\.Print" -->` to conventions.md causes any post-edit using `fmt.Print` to surface a drift warning with file:line reference. `/speccraft:sync` runs a full drift scan and proposes memory updates based on recent diffs.

### Phase 8 — Implement command + polish (1 day)
**Build:**
- `commands/spec/implement.md` (now that all dependencies are in place).
- `hooks/stop.sh`
- Error messages and recovery paths across all hooks.
- `scripts/doctor.sh` — checks: `git`, `jq`, `curl`, network reachability of GitHub Releases, presence of `<plugin>/bin/*`, version stamp matches plugin version, optional `acpx`, configured aux agents on PATH. Reports `go` only as informational (used only for source fallback).
- Full end-to-end test: empty repo → init → spec → review → plan → implement → close.

**Done when:** A scripted end-to-end run of a small feature spec passes from `/speccraft:init` through `/spec:close` without manual intervention beyond the expected approval prompts.

**Total estimate:** ~11 working days for a careful implementation with tests at each phase. Aggressive: 7–8 days. Phases 0–4 (plus 0.5) are the minimum useful product and should be ~6 days.

**Per-phase test addendum.** Every phase (1 onward) adds one line to its done criteria:

> The phase's tests pass when run via `bash tests/e2e/run.sh` (or, for unit/hook tests, the appropriate command) inside the devcontainer.

The implementing agent should never test against the host Claude Code installation. If a phase appears to require host testing, that is a sign the test design needs revision — file as an open question.

---

## 17. Tasks (machine-checklist)

```markdown
- [ ] T0.1 — plugin.json with manifest fields
- [ ] T0.2 — directory skeleton
- [ ] T0.3 — README install instructions
- [ ] T0.4 — verify plugin loads via /plugin

- [ ] T0.5.1 — .devcontainer/devcontainer.json (Feature install, named volume)
- [ ] T0.5.2 — .devcontainer/Dockerfile (Go, jq, bats, build chain)
- [ ] T0.5.3 — .devcontainer/setup.sh (postCreateCommand)
- [ ] T0.5.4 — .devcontainer/install-mock-agents.sh (mock codex, opencode)
- [ ] T0.5.5 — tests/e2e/run.sh (skeleton; assertions added per later phase)
- [ ] T0.5.6 — .gitignore: .env.devcontainer, tests/e2e/.logs/
- [ ] T0.5.7 — README "Development" section
- [ ] T0.5.8 — verify: host Claude Code unaffected; auth persists across rebuilds; e2e harness exits 0

- [ ] T1.1 — speccraft-context SKILL.md
- [ ] T1.2 — hooks.json (SessionStart)
- [ ] T1.3 — session-start.sh (no binary deps)
- [ ] T1.4 — index.md template
- [ ] T1.5 — manual test: index.md content in session

- [ ] T2.1 — guardrails/architecture/conventions/history templates
- [ ] T2.2 — agents.toml template
- [ ] T2.3 — speccraft-state binary (find-root, get, set, track-edit, reset-session, tasks-done-pct)
- [ ] T2.4 — install-binaries.sh build pipeline
- [ ] T2.5 — commands/speccraft/init.md
- [ ] T2.6 — gitignore append logic
- [ ] T2.7 — e2e: init creates full tree

- [ ] T3.1 — spec-author agent
- [ ] T3.2 — spec-critic agent
- [ ] T3.3 — spec-format SKILL.md
- [ ] T3.4 — commands/spec/new.md
- [ ] T3.5 — memory-keeper agent (close mode)
- [ ] T3.6 — commands/spec/close.md
- [ ] T3.7 — index.md auto-update on lifecycle events
- [ ] T3.8 — e2e: new -> close happy path

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

- [ ] T5.1 — agents.toml loader
- [ ] T5.2 — aux-delegator agent
- [ ] T5.3 — review/implement prompt templates
- [ ] T5.4 — CLI mode (codex, opencode, claude -p)
- [ ] T5.5 — ACP mode via acpx (with graceful absence)
- [ ] T5.6 — commands/spec/delegate.md
- [ ] T5.7 — aux-agents SKILL.md
- [ ] T5.8 — manual test against each CLI

- [ ] T6.1 — cross-reviewer agent
- [ ] T6.2 — parallel invocation in aux-delegator
- [ ] T6.3 — commands/spec/review.md
- [ ] T6.4 — commands/spec/review-code.md
- [ ] T6.5 — review.md output schema
- [ ] T6.6 — tdd-planner agent
- [ ] T6.7 — commands/spec/plan.md (uses `find` for existing tests, no graph)
- [ ] T6.8 — quorum / verdict synthesis logic

- [ ] T7.1 — speccraft-drift binary (regex mode only)
- [ ] T7.2 — directive parser for `<!-- enforce: regex pattern="..." [scope="..."] -->`
- [ ] T7.3 — wire post-tool-use.sh to scan-file
- [ ] T7.4 — memory-keeper audit mode
- [ ] T7.5 — commands/speccraft/sync.md

- [ ] T8.1 — commands/spec/implement.md
- [ ] T8.2 — hooks/stop.sh
- [ ] T8.3 — scripts/doctor.sh
- [ ] T8.4 — full e2e: empty repo to /spec:close
- [ ] T8.5 — README polish
- [ ] T8.6 — CHANGELOG
```

---

## 18. Test strategy

All tests run inside the speccraft devcontainer. The devcontainer is the only supported development and testing environment, because hooks fire on every `Edit`/`Write` in any active Claude Code session — running development against the host Claude Code installation risks a buggy hook locking up unrelated work in unrelated repos.

### 18.1 Devcontainer setup

The repo ships a `.devcontainer/` directory:

```
.devcontainer/
├── devcontainer.json        # Feature install, named volume for ~/.claude
├── Dockerfile               # Ubuntu + Go + jq + bats; non-root vscode user
├── setup.sh                 # post-create: build binaries, install mock agents
└── install-mock-agents.sh   # canned codex/opencode for hermetic tests
```

**Authentication.** Claude Code is installed via the official Dev Container Feature (`ghcr.io/anthropics/devcontainer-features/claude-code:1.0`). A named Docker volume mounts at `/home/vscode/.claude` and persists the OAuth token across container rebuilds. **The host `~/.claude` is never bind-mounted into the container** — Anthropic's docs warn that this exposes credentials to any project running inside, and we follow that guidance.

Two auth flows are supported:

- **Interactive (default):** run `claude` once inside the container, complete the browser flow on the host. Token lands in the named volume; subsequent rebuilds reuse it.
- **Non-interactive (for automated e2e):** on the host, run `claude setup-token` to mint a long-lived OAuth token, store it in `~/.env.devcontainer` (gitignored, outside the repo), and uncomment the `CLAUDE_CODE_OAUTH_TOKEN` line in `devcontainer.json`. The container reads it via `${localEnv:CLAUDE_CODE_OAUTH_TOKEN}`.

**Aux agents.** The devcontainer installs **mock** `codex` and `opencode` binaries at `/usr/local/bin` that emit canned, structured responses. This makes e2e tests hermetic: no API costs, no auth setup, deterministic outputs. Real CLIs can be installed in the Dockerfile (or via `npm`) at any time and override the mocks via PATH order.

**Isolation guarantees:**

| Risk | Mitigation |
|---|---|
| Buggy hook locks up host Claude Code sessions | Plugin only installed in container; host untouched. |
| Helper binary segfault corrupts host filesystem | All writes go to bind-mounted workspace; container can't touch the rest of the host. |
| Test scenarios collide with real repos | Tests run in `/tmp/speccraft-e2e-$$`, removed on exit. |
| OAuth token leak from a malicious test fixture | Named volume is container-private; never shared with host. |
| Tree-sitter CGO build affects host Go install | Build happens in container's `/usr/local/go`; host Go untouched. |

### 18.2 Unit tests (Go tools)

Run inside the container:

```bash
cd tools && go test ./...
```

- TDD invariant: temp-dir tests for `speccraft-guard` covering active-spec checks, sibling-test resolution (correct dir, with/without prior test edit, scratch/docs paths), and exit-code semantics.
- Drift rules: regex-directive parser tests in `tools/internal/speccraft/drift_test.go` with fixture pairs `(input.go, want-violations.json)`.
- State management: temp-dir tests for `speccraft-state` (find-root walks up correctly, get/set are atomic, track-edit deduplicates, reset-session clears only session.* fields).

### 18.3 Hook tests (bats)

```bash
bats tests/hooks/
```

Each hook script has a `tests/hooks/<name>.bats` that pipes a known JSON payload to it and asserts exit code, stdout, stderr. `bats-core` is preinstalled in the Dockerfile.

### 18.4 End-to-end tests

`tests/e2e/run.sh` drives the full lifecycle non-interactively against a throwaway Go module. It:

1. Creates `/tmp/speccraft-e2e-$$/` with a tiny Go module + initial test.
2. Installs the plugin from the workspace via `/plugin marketplace add`.
3. Runs `/speccraft:init` with scripted answers.
4. Runs `/spec:new "Add farewell function"` with scripted answers.
5. Runs `/spec:review` against mock aux agents.
6. Runs `/spec:plan --skip-review` and verifies plan/tasks files.
7. Tests the TDD invariant: writes a test first (allowed), then production code (allowed because a sibling `*_test.go` was touched).
8. Runs `/spec:close` and verifies changelog, history.md update, cleared active_spec.

Each step calls `claude -p --permission-mode bypassPermissions --output-format text "<prompt>"` and asserts on filesystem state.

**Run with:**

```bash
bash tests/e2e/run.sh
```

**Useful flags:**

- `KEEP_TEST_DIR=1 bash tests/e2e/run.sh` — preserve `/tmp/speccraft-e2e-$$` for inspection on failure.
- `PLUGIN_DIR=/some/path bash tests/e2e/run.sh` — test a different checkout.

Exit codes: `0` pass, `1` setup failure, `2` assertion failure, `3` claude -p failure.

### 18.5 CI matrix

GitHub Actions runs:

| Job | Runner | What runs |
|---|---|---|
| `unit-linux` | `ubuntu-latest` | `cd tools && go test ./...` |
| `unit-macos` | `macos-14` (Apple Silicon) | same; verifies macOS binary builds |
| `hooks` | `ubuntu-latest` | `bats tests/hooks/` |
| `e2e-devcontainer` | `ubuntu-latest` | builds the devcontainer, runs `tests/e2e/run.sh` inside it via `devcontainer/cli` |
| `release-matrix` | `ubuntu-latest` × `macos-14` | pure-Go matrix build (`CGO_ENABLED=0`), only on tag push |

`e2e-devcontainer` uses `CLAUDE_CODE_OAUTH_TOKEN` from a GitHub Actions secret minted via `claude setup-token` from a CI service account.

### 18.6 Workflow for the implementing agent

When implementing speccraft, Claude Code should:

1. Open the repo in VS Code on the host.
2. Reopen in the devcontainer (`Cmd+Shift+P` → `Dev Containers: Reopen in Container`).
3. Authenticate Claude Code inside the container (one-time, browser flow).
4. Start a session inside the container. All subsequent work happens here.
5. After each phase, run the appropriate test commands inside the container.
6. **Never `claude` from the host shell while developing the plugin** — the plugin is being written, hooks may be partial, this is exactly what the container exists to isolate.

If the host's Claude Code session is needed for an unrelated task during development, that's fine — the container's plugin install is scoped to the container's `~/.claude` (the named volume), and the host's `~/.claude` is untouched.

---

## 19. Acceptance criteria for v1 release

1. `claude /plugin install speccraft@<marketplace>` works on macOS and Linux.
2. `/speccraft:init` produces the full repo layout in a fresh Go module.
3. SessionStart injects `index.md` content into context. The `speccraft-context` skill triggers on repo-specific questions.
4. `/spec:new` produces a structured `spec.md` via the spec-author agent.
5. The TDD invariant blocks production-file edits when no sibling test was touched in the session, and allows after one is touched.
6. `/spec:delegate codex "..."` succeeds when `codex` is on PATH; surfaces a clean error when not.
7. `/spec:review` with two aux agents in parallel produces a `review.md`.
8. `enforce: regex` directives produce drift warnings on matching post-edit content.
9. `/spec:close` produces a changelog and proposes (with user approval) updates to `history.md` and `conventions.md`.
10. The doctor script reports correctly on a clean machine vs. one missing dependencies.

---

<a id="201-codebasewide-queries"></a>
## 20. Open questions / future work

### 20.1 Codebase-wide queries

v1 explicitly defers structural code analysis (call graphs, symbol search, layer enforcement, "where is X used"). The recommended path forward:

- **Today:** users who need these capabilities should install [CodeGraphContext](https://github.com/CodeGraphContext/CodeGraphContext) as an MCP server. It plugs into Claude Code (and any MCP-compatible client) without any speccraft-side change. The two tools are complementary: speccraft owns intent/memory/TDD-discipline; CodeGraphContext owns structural queries.
- **v1.x:** add an `enforce: cgc rule="<rule-name>"` directive that calls into CodeGraphContext via MCP for layer enforcement, no-direct-http, and similar structural rules. This requires a stable MCP integration point and a small rule shim in `speccraft-drift`.
- **v2:** consider whether richer planning (`/spec:plan` blast-radius, `memory-keeper` architectural-drift detection at `/spec:close`) should optionally consume CodeGraphContext output when available.

### 20.2 Other open questions

- **Session-edit recency window.** Currently "edited in this session". For a long-running session that pauses between specs, this is fine. For server-side or batch flows, a per-spec window would be better.
- **Override audit trail.** v1 logs bypasses to `tasks.md`. Should there be a separate `bypasses.md` per spec? Likely yes in v1.1.
- **Sibling-test heuristic across languages.** The Go-specific same-directory rule won't extend to Java, Rust workspaces, or split src/test trees. v1.x needs per-language sibling resolvers — likely keyed off file extension and `architecture.md`'s "Layering" section.
- **Multi-package monorepo.** specs declare which packages they touch; the spec-first invariant scopes per package; `/speccraft:sync` learns to detect new top-level packages.
- **Multi-repo workspace.** A separate `.speccraft-workspace/` marker at the parent of multiple `.speccraft/` repos. v2 conversation.
- **Marketplace publishing.** Once v1 stabilizes, publish via the Claude Code plugin marketplace.
- **Telemetry.** Opt-in anonymous usage stats so we can tune defaults.

---

## Appendix A — Prompt templates

### A.1 `templates/prompts/review.md`

```markdown
You are reviewing a software specification. Be rigorous but constructive.

Output in this exact structure:

```yaml
verdict: <approve | approve-with-comments | changes-requested | reject>
concerns:
  - "<concern 1>"
  - "<concern 2>"
suggestions:
  - "<suggestion 1>"
guardrail_violations:
  - rule: "<which rule>"
    location: "<which paragraph>"
convention_violations:
  - rule: "<which rule>"
    location: "<which paragraph>"
```

Then a free-form discussion section after the YAML.

Specification follows below. Repo memory (guardrails, conventions, architecture)
is included as additional context.
```

### A.2 `templates/prompts/implement.md`

```markdown
You are an auxiliary coding agent receiving a delegated task. The task,
relevant repository memory, and the active spec are below. Produce a unified
diff (```diff fenced) implementing the task. Do not modify files outside the
indicated scope. If the task is ambiguous, return a brief question instead
of a diff.
```

---

## Appendix B — Minimal sample after Phase 2

After Phase 2 succeeds in a fresh repo, this is what exists:

```
my-repo/
├── .git/
├── .gitignore                    # appended .speccraft/state.json
├── .speccraft/
│   ├── index.md                  # personalized
│   ├── guardrails.md             # template + user-added top-3 rules
│   ├── architecture.md           # personalized one-liner
│   ├── conventions.md            # template
│   ├── history.md                # one entry: "speccraft adopted"
│   ├── agents.toml               # default
│   └── state.json                # {"active_spec": null, ...}
├── specs/
│   └── .gitkeep
├── go.mod
├── main.go
└── main_test.go
```

This is the floor. Everything else builds upward from here.

---

## Appendix C — `scripts/install-binaries.sh` (reference implementation)

```bash
#!/usr/bin/env bash
# Download (or build) speccraft helper binaries into <plugin>/bin/.
# Idempotent: skips when .binary-version matches plugin version.
set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BIN_DIR="$PLUGIN_DIR/bin"
VERSION_FILE="$PLUGIN_DIR/.binary-version"
RELEASE_BASE="https://github.com/dcstolf/speccraft/releases/download"

EXPECTED="$(jq -r '.version' "$PLUGIN_DIR/.claude-plugin/plugin.json")"
INSTALLED="$([ -f "$VERSION_FILE" ] && cat "$VERSION_FILE" || echo "none")"

# Fast path: already correct.
if [ "$INSTALLED" = "$EXPECTED" ] && [ -x "$BIN_DIR/speccraft-state" ]; then
  exit 0
fi

# Detect platform.
OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
case "$OS" in
  darwin) OS="macos" ;;
  linux)  OS="linux" ;;
  *) echo "speccraft: unsupported OS $OS (Windows: use WSL)" >&2; exit 1 ;;
esac

ARCH="$(uname -m)"
case "$ARCH" in
  arm64|aarch64) ARCH="arm64" ;;
  x86_64|amd64)  ARCH="amd64" ;;
  *) echo "speccraft: unsupported arch $ARCH" >&2; exit 1 ;;
esac

PLATFORM="${OS}-${ARCH}"
TARBALL="speccraft-${EXPECTED}-${PLATFORM}.tar.gz"
URL="${RELEASE_BASE}/v${EXPECTED}/${TARBALL}"
SUMS_URL="${RELEASE_BASE}/v${EXPECTED}/checksums.txt"

mkdir -p "$BIN_DIR"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "speccraft: installing helper binaries (v${EXPECTED}, ${PLATFORM})..." >&2

if curl -fsSL "$URL" -o "$TMP/${TARBALL}" 2>/dev/null \
   && curl -fsSL "$SUMS_URL" -o "$TMP/checksums.txt" 2>/dev/null; then
  # Verify checksum for our platform's tarball.
  ( cd "$TMP" && grep "${TARBALL}" checksums.txt | sha256sum -c - >&2 )
  tar -xzf "$TMP/${TARBALL}" -C "$BIN_DIR"
  chmod +x "$BIN_DIR"/*
  echo "$EXPECTED" > "$VERSION_FILE"
  echo "speccraft: installed." >&2
  exit 0
fi

# Source fallback.
if command -v go >/dev/null 2>&1; then
  echo "speccraft: download unavailable; building from source..." >&2
  ( cd "$PLUGIN_DIR/tools" \
    && for cmd in speccraft-state speccraft-guard speccraft-drift; do
         CGO_ENABLED=0 go build -o "$BIN_DIR/$cmd" "./cmd/$cmd"
       done )
  echo "$EXPECTED" > "$VERSION_FILE"
  echo "speccraft: built from source." >&2
  exit 0
fi

cat >&2 <<EOF
speccraft: failed to install helper binaries.

Tried:
  1. Download from ${URL}
  2. Build from source (requires 'go' on PATH; not found)

Check network connectivity, or install Go ≥ 1.22 to build from source.
Run \`bash $PLUGIN_DIR/scripts/doctor.sh\` for a full diagnostic.
EOF
exit 1
```

The owner (`dcstolf`) is already substituted in this file. The script is idempotent and safe to call from every `SessionStart` — the fast path is a single `cat` and a string compare.

---

*End of v1 specification.*
