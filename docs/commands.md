# Command & workflow reference

The full reference for speccraft's slash commands, the spec lifecycle, the optional
PM/Architect lanes, aux agents, and convention enforcement. For the 30-second pitch,
see the [README](../README.md).

## Spec commands

| Command | Purpose |
|---|---|
| `/speccraft:init` | Bootstrap `.speccraft/` and `specs/` in this repo. |
| `/speccraft:sync` | Drift scan + memory-keeper audit. Reconcile drift; backfill consolidation. |
| `/speccraft:spec:new "<title>"` | Start a new spec via Socratic interview. `--from product/<id>\|design/<id>` to seed from an upstream brief/design. |
| `/speccraft:spec:review` | Cross-model review of the active spec. `--quorum N`, `--agents codex,opencode`. |
| `/speccraft:spec:plan` | Generate a test-first (RED→GREEN→REFACTOR) plan and tasks list from a reviewed spec. `--skip-review`. |
| `/speccraft:spec:implement` | Execute the active plan TDD-style; optionally `--delegate <agent>:<task-id>,...`. |
| `/speccraft:spec:delegate <agent> "<task>"` | Hand a discrete task to an aux agent and integrate the result. |
| `/speccraft:spec:review-code [--base <ref>]` | Cross-model review of the current diff against the active spec. |
| `/speccraft:spec:revise` | Re-run the Socratic interview on the active spec; archive stale artifacts, bump revision, return to draft. |
| `/speccraft:spec:override "<reason>"` | One-time bypass of the TDD invariant. Reason is logged into the active spec. |
| `/speccraft:spec:close` | Write changelog, propose memory updates, consolidate into domain specs, close. |

## Optional upstream lanes (PM / Architect)

These are optional and run *upstream* of specs. A product brief or technical design
can seed a spec via `/speccraft:spec:new --from …`. They are independent lanes — you
can ignore them entirely and go straight to specs.

| Command | Purpose |
|---|---|
| `/speccraft:pm:new "<title>"` | Start a product brief; set the PM lane. |
| `/speccraft:pm:prioritize` | Mark the active brief prioritized (draft → prioritized). |
| `/speccraft:pm:review` | pm-critic self-check, then cross-model review of the brief. |
| `/speccraft:pm:close` | Close the active product brief and clear the PM lane. |
| `/speccraft:arch:new "<title>"` | Start a technical design; set the Architect lane. |
| `/speccraft:arch:decide` | Mark the active design decided (draft → decided). |
| `/speccraft:arch:review` | arch-critic self-check, then cross-model review of the design. |
| `/speccraft:arch:close` | Route durable decisions through memory-keeper; clear the Architect lane. |

## Memory maintenance

| Command | Purpose |
|---|---|
| `/speccraft:history:compact [--window N]` | Keep a bounded recent window of `history.md`, merge older entries into a thematic summary, archive originals verbatim. Confirm-gated. |

Each command takes optional flags; run with `--help` for details.

## The spec lifecycle, illustrated

### 1. New spec

```
> /speccraft:spec:new "Rate limit public API"

I'll help you draft this spec. A few questions first.

What problem are you trying to solve? Who's affected?
> Public API gets hammered by scrapers; 99p latency is degrading.

What does success look like, concretely?
> Anonymous clients capped at 60 req/min. Authenticated at 600. 429 with
> Retry-After when over.

What's explicitly out of scope?
> Distributed rate limiting. Per-customer custom limits.

Acceptance criteria — observable behaviors only:
1. Anonymous client at 100 req/min sees ~60 successes, ~40 429s.
2. Authenticated at 700 req/min sees ~600 successes, ~100 429s.
3. X-RateLimit-* headers on all 200 and 429 responses.

Drafting spec.md... done.
Active spec: 0042-rate-limit-public-api
Next: /speccraft:spec:review (recommended) or /speccraft:spec:plan
```

### 2. Cross-model review

```
> /speccraft:spec:review

Routing to: codex, opencode (parallel)

[codex] verdict: changes-requested
  Concern: AC4 implies persistence; spec doesn't say what happens to
  in-flight tokens on restart. Affects test design.

[opencode] verdict: approve-with-comments
  Suggestion: out-of-scope item "cost-based limiting" might re-emerge;
  consider a minimal hook in the bucket interface.

Synthesizing...
Wrote review.md. Status: changes-requested.
```

### 3. Plan

```
> /speccraft:spec:plan

Scanning packages: internal/http, internal/middleware
Drafting plan.md with 7 RED→GREEN→REFACTOR steps...
Wrote plan.md and tasks.md. Status: planned.
```

### 4. Implement (TDD-enforced)

```
> /speccraft:spec:implement

T1 — Bucket tests (RED)
  Edit internal/middleware/ratelimit/bucket_test.go ✓
  go test ./... → FAIL (expected)

T2 — Bucket impl (GREEN)
  > Edit internal/middleware/ratelimit/bucket.go

  speccraft: BLOCKED. TDD invariant.
  bucket.go is a production file. Tests covering it must be edited
  this session before this edit is allowed. Suggested test files:
    - internal/middleware/ratelimit/bucket_test.go
```

The autonomous loop runs the RED→GREEN→REFACTOR cycle on its own and surfaces a
blocker only when a developer decision is genuinely required.

### 5. Close

```
> /speccraft:spec:close

All tasks complete (7/7).

memory-keeper proposes:
[1] history.md ADR — "Rate limiting on public API: token bucket, fail-open."  [approve]
[2] conventions.md — "All HTTP middleware lives under internal/middleware/<name>/." [approve]

Consolidating requirements into specs/domains/http.md...
Wrote changelog.md, updated history.md, conventions.md. Active spec cleared.
```

## Auxiliary agents

speccraft talks to external CLI coding agents through a registry at
`.speccraft/agents.toml`. speccraft is the **dispatcher, not the runtime** — each
agent must be installed and authenticated separately, or that agent simply won't be
available for review/delegation.

```toml
[defaults]
review_quorum = 1
review_timeout_s = 600

[[agents]]
name = "codex"
mode = "cli"
cmd = ["codex", "exec", "--full-auto"]
input = "stdin"
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
```

The default registry ships `codex`, `opencode`, and `claude-p`. The `cmd` is an
arbitrary CLI invocation, so you can register any agent — e.g. a Gemini CLI — by
adding another `[[agents]]` block.

- Codex: https://developers.openai.com/codex/cli
- OpenCode: https://opencode.ai/docs
- Claude Code (`claude -p`): the same CLI you're running speccraft in

**ACP support (opt-in).** If you have [`acpx`](https://github.com/openclaw/acpx)
installed, set `mode = "acp"` and `acp_agent = "codex"` (or any ACP-compatible agent
name) to use a single ACP backend instead of direct shellouts.

```toml
[[agents]]
name = "codex-acp"
mode = "acp"
acp_agent = "codex"
```

Agents can be enabled/disabled per call:

```
/speccraft:spec:review --agents codex,opencode
/speccraft:spec:delegate claude-p "Refactor internal/foo to use slog"
```

## Enforcing conventions

Rules in `guardrails.md` and `conventions.md` can be tagged with an `enforce:`
directive. When a `PostToolUse` hook fires after an edit, speccraft scans files in
scope for tagged rules and surfaces violations.

### Regex enforcement

```markdown
## Logging
- Use `slog` only. No `fmt.Println` outside `cmd/`. <!-- enforce: regex pattern="fmt\\.Print(ln|f)?" scope="!cmd/" -->
```

`scope` is a glob; `!` prefix excludes. The default scope is the entire repo.
Violations show as `<file>:<line>: <rule-source>: matches <pattern>`.

### Advisory rules

Rules **without** an `enforce:` tag — including structural rules like layer
dependencies, no-direct-http, and required test coverage — are **documentation only**.
Claude reads them at session start, but the hook does not act on them. Only
regex-expressible `enforce:` rules are enforced at edit time. Structural rule
enforcement lives outside speccraft — see [Recommended companions](#recommended-companions).

## Recommended companions

speccraft is intentionally narrow in scope. Two external tools complement it well.

### CodeGraphContext — code intelligence as MCP

[CodeGraphContext](https://github.com/CodeGraphContext/CodeGraphContext) is an MCP
server that gives Claude Code call-graph and symbol-search capabilities across your
codebase ("Where is this called from?", "Does this change cross a layering
boundary?"). speccraft deliberately doesn't build this in; the two tools are
complementary.

| Concern | Owned by |
|---|---|
| Spec lifecycle, intent, memory, history | speccraft |
| TDD discipline (sibling-test / delta heuristic) | speccraft |
| Cross-model spec review | speccraft |
| Regex-based guardrails | speccraft |
| Call-graph / symbol queries | CodeGraphContext |
| Structural rule enforcement (layering, etc.) | CodeGraphContext |

### rtk (Rust Token Killer) — tool-call token compression

[rtk](https://github.com/rtk-ai/rtk) compresses the token cost of LLM tool-calling.
Worth considering when you delegate frequently to expensive aux agents, or when
`.speccraft/` memory plus a long diff plus the aux-agent prompt is pushing context
limits.

## FAQ

**Does speccraft replace AGENTS.md / CLAUDE.md?**
Complementary. `.speccraft/index.md` is the always-injected one-pager — similar role
to AGENTS.md. If you use both, point your AGENTS.md at `.speccraft/index.md` so they
don't drift.

**Can I use speccraft without aux agents?**
Yes. Skip `/speccraft:spec:review` and `/speccraft:spec:review-code`. Everything else
(specs, TDD enforcement, memory) works without a single external CLI configured.

**Can I use it in a non-Go repo?**
Spec workflows, memory injection, and drift detection (regex mode) work
language-agnostically. Hook-enforced TDD supports Go, Python, TypeScript/JavaScript,
and Rust — see [docs/architecture.md](./architecture.md). For other languages, set
`SPECCRAFT_TDD_MODE=soft` to convert blocks to warnings.

**What happens to specs after a spec is closed?**
On close, a spec's final requirements are folded into a consolidated, current
`specs/domains/<area>.md`, and the closed spec directory is archived. See
[docs/architecture.md](./architecture.md#consolidation--compaction).

**Can the spec-first invariant be bypassed by editing files outside Claude Code?**
Yes. speccraft only enforces what Claude Code does. If you `vim` a production file
directly, no hook fires. It's a workflow tool, not a security boundary.

**Does it phone home?**
No telemetry. The only network call is the one-time binary download from GitHub
Releases on first install.
