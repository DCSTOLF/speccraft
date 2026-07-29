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
| `/speccraft:arch:orchestrate <design-id>` | Drive the spec lifecycle across a workspace's member repos (see below). |

For single-repo work these lanes are entirely optional. The Architect
**conductor** (`arch:orchestrate`) is the one piece that needs a workspace — covered
next.

## Multi-repo workspaces & the Architect conductor

Most projects are a single repo, and everything above works without ever thinking
about workspaces. When a change spans **several repos**, speccraft models that with a
*workspace*: one coordination root that drives the ordinary per-repo spec lifecycle
across each member. Nothing about the member repos changes — the conductor only
*sequences* the same `/speccraft:spec:*` commands inside each one, and never bypasses
the TDD guard or the review gates.

### Topology: `repo` vs `workspace`

A repo's kind is declared in `.speccraft/speccraft.toml`:

```toml
kind = "workspace"   # absent ⇒ "repo" (a monorepo is a single repo-kind member)
```

Only the `arch:*` commands and the conductor ever resolve the *workspace* root; the
hot-path hook/guard only ever resolve the nearest *repo* root, so member repos behave
exactly as standalone speccraft projects. A lone repo with no workspace ancestor is
treated as a "workspace of one".

### Bootstrapping a workspace — `/speccraft:init --workspace`

```
/speccraft:init --workspace
```

This scaffolds a workspace root: a `speccraft.toml` with `kind = "workspace"`, a
`workspace.yml` member manifest, and the standard `.speccraft/` set with a
workspace-flavored `index.md`. During init, speccraft scans the root's immediate
child directories, proposes each one that is already a speccraft repo as a member for
your approval, and writes only the approved entries. It never creates a ledger eagerly
(that appears on first orchestration), never clobbers a curated `workspace.yml` on a
`--force` re-init, and refuses to migrate an existing `repo`-kind root in place.

`workspace.yml` is a deliberately tiny, non-YAML-dependent manifest at the workspace
root:

```yaml
# speccraft workspace manifest — members orchestrated by /speccraft:arch:orchestrate
members:
  - path: api
  - path: web
#  - path: relative/child-repo
```

Each `path` is a repo-root-relative directory. Membership is authoritative and
presence-preserving: a listed-but-missing member is warned, never dropped. Inspect it
with `speccraft-state list-members` (`<present|missing>\t<path>` per line).

### The conductor lifecycle — `/speccraft:arch:orchestrate <design-id>`

The conductor turns a **technical design** into coordinated per-member specs. The
usual flow:

1. **Draft the design.** `/speccraft:arch:new "Cross-repo auth"` scaffolds
   `design/<id>/design.md` and sets the Architect lane; iterate with
   `/speccraft:arch:review`, settle with `/speccraft:arch:decide`.
2. **Orchestrate.** `/speccraft:arch:orchestrate <design-id>` runs at the workspace
   root and:
   - **Decomposes** the design into a `<member-path> → one-line brief` mapping,
     drafted by the model and **confirmed/edited by you** before anything runs.
   - **Seeds** one ledger row per member (create-if-absent; a captured spec ref is
     never erased on a re-run).
   - **Drives each member** through the ordered phases
     `new → reviewed → planned → implemented → validated`, dispatching each phase with
     the working directory scoped **inside that member** — so its specs land in
     `<member>/specs/`, resolved by the member's own repo root. `new` runs the
     Socratic interview; `review` loops with `revise` under the cross-model verdict;
     `validate` gates on the member's test command, then closes the member spec.
   - **Reconciles** at the end: `speccraft-state reconcile <design-id>` rolls the
     design up across members — done only when *every* member spec is `closed`.

### The ledger

Progress lives in `<workspace-root>/.speccraft/ledger.md` — a `history.md`-class
markdown memory file (never `state.json`), keyed `## design <id>` → `### <member>` →
fields (`spec`, `last_completed_phase`, `in_flight`, `blocked`, `updated`). It is the
conductor's source of truth for resume, and you can read it directly.

### Two human checkpoints

The conductor stops only when a decision is genuinely yours:

- **After `planned`, before `implement`** — approve the plan before code lands.
  Suppress with `--straight-through`.
- **On a stuck review loop** — when revisions hit the escalation ceiling, it
  summarizes the sticking points and waits for your input.

### Resilience: crash-safe resume & blocked isolation

- **Resume-at-pointer.** Re-running `arch:orchestrate` picks up from each member's
  ledger pointer. Before re-dispatching an in-flight phase it inspects the member's
  real `spec.md` status and *adopts* an already-completed result rather than re-running
  it — so a crash between "command succeeded" and "ledger advanced" never
  double-allocates a spec or re-closes a closed one.
- **Failure isolation.** A member whose phase fails is marked `blocked` (and its
  `in_flight` cleared) while its siblings keep advancing; a clean re-attempt clears
  `blocked`. One member's problem never stalls the workspace.

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
