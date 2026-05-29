![speccraft logo](images/speccraft-logo-banner.png) 

> Spec-first, test-driven development for [Claude Code](https://claude.com/code).
> Versioned intent. Auto-injected memory. Cross-model review. Hook-enforced TDD.

speccraft is a Claude Code plugin that turns code changes into deliberate, reviewable, test-driven workflows. Every change starts from a versioned spec; every implementation starts from a failing test; every repo carries a small, always-injected memory of guardrails, architecture, and conventions. Heavy work and second-opinion reviews can be offloaded to auxiliary CLI agents like Codex and OpenCode.

**v1 status:** Go repositories. Multi-language and multi-repo are coming.

---

## Table of contents

- [Why speccraft](#why-speccraft)
- [Install](#install)
- [Quick start](#quick-start)
- [What it adds to your repo](#what-it-adds-to-your-repo)
- [The workflow](#the-workflow)
- [Commands](#commands)
- [Auxiliary agents](#auxiliary-agents)
- [Enforcing conventions](#enforcing-conventions)
- [Recommended companions](#recommended-companions)
- [Configuration](#configuration)
- [Requirements](#requirements)
- [Troubleshooting](#troubleshooting)
- [FAQ](#faq)
- [Roadmap](#roadmap)
- [Contributing](#contributing)
- [License](#license)

---

## Why speccraft

Most Claude Code sessions look like this: prompt → code change → maybe tests → next prompt. Intent lives in your head, drifts across sessions, and gets re-derived from grep every time. Conventions are enforced by hope. Reviews are whatever Claude decides to flag.

speccraft fixes three specific problems:

- **Intent is ephemeral.** Specs live alongside code under `specs/NNNN-slug/`, version-controlled, written *before* implementation, and reviewed by a second model before code is written.
- **Project memory is too long for every prompt.** A small `.speccraft/index.md` is auto-injected at session start; deeper files (guardrails, architecture, conventions, history) load on demand.
- **Reviews are single-model.** `/speccraft:spec:review` and `/speccraft:spec:review-code` route to Codex, OpenCode, or any CLI agent you configure, in parallel, and synthesize the verdicts.

It also enforces TDD with a hook, not a prompt: edits to production files are blocked unless a sibling `*_test.go` was edited more recently in the same session.

speccraft is **deliberately small in scope**. For codebase-wide structural queries (call graphs, symbol search) and tool-call token compression, it composes with existing tools — see [Recommended companions](#recommended-companions).

---

## Install

In a Claude Code session:

```
/plugin marketplace add dcstolf/speccraft
/plugin install speccraft@dcstolf-tools
/reload-plugins
```

Then in your project root:

```
/speccraft:init
```

This creates `.speccraft/` and `specs/` in the repo and walks you through personalizing the memory files.

> **Helper binaries are downloaded automatically** the first time speccraft runs in a session — about 5 MB, cached forever, version-stamped. Pure Go, no C toolchain. See [Requirements](#requirements).

---

## Quick start

In a Go repo, after `/speccraft:init`:

```
/speccraft:spec:new "Add a /healthz endpoint"
```

speccraft interviews you Socratically — *why*, *what*, *acceptance criteria* — and writes `specs/0001-add-a-healthz-endpoint/spec.md`.

```
/speccraft:spec:review
```

Codex and OpenCode (whichever you've configured) review the spec in parallel, flag ambiguity, missing edge cases, and untestable criteria. The synthesis lands in `review.md`.

```
/speccraft:spec:plan
```

A test-first plan: each step is RED → GREEN → REFACTOR with concrete file paths and test function names.

```
/speccraft:spec:implement
```

speccraft executes the plan. The TDD hook ensures you write failing tests before production code. Tasks can be delegated:

```
/speccraft:spec:delegate codex "Generate table-driven tests for internal/health/handler.go"
```

When done:

```
/speccraft:spec:close
```

A changelog is written, the `memory-keeper` agent proposes additions to `history.md` and `conventions.md`, you approve.

That's the loop.

---

## What it adds to your repo

```
.speccraft/
├── index.md          # 1-page summary, auto-injected on every session start
├── guardrails.md     # hard rules, optionally enforced by hooks
├── architecture.md   # current shape, layering, key decisions
├── conventions.md    # style and patterns, optionally enforced
├── history.md        # append-only ADR log
├── agents.toml       # auxiliary agent registry
└── state.json        # runtime state (gitignored)

specs/
└── 0001-some-feature/
    ├── spec.md       # WHAT, WHY, acceptance criteria
    ├── plan.md       # test-first plan
    ├── review.md     # cross-model critique
    ├── tasks.md      # checklist with status
    └── changelog.md  # what shipped vs what was specced
```

`.speccraft/state.json` is gitignored. Everything else is part of your repo and intended to be committed — that's the point. Your team's intent, conventions, and history live with the code.

---

## The workflow

A complete spec lifecycle, illustrated:

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

Open questions?
> Should limiter state survive a server restart?
[noted as open question]

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
Update spec.md and re-run /speccraft:spec:review.
```

### 3. Plan

```
> /speccraft:spec:plan

Scanning packages: internal/http, internal/middleware
- Existing test files: internal/http/router_test.go, internal/middleware/auth_test.go
- Probable test files to extend: internal/http/router_test.go

Drafting plan.md with 7 RED→GREEN→REFACTOR steps...
Wrote plan.md and tasks.md.
Status: planned.
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
    - internal/middleware/ratelimit/bucket_test.go (already edited ✓)

  [retrying — already edited, allowed]
  Edit internal/middleware/ratelimit/bucket.go ✓
  go test ./... → PASS
```

The hook didn't actually block the second attempt — the test *was* already edited in T1, so by T2 the invariant is satisfied. The block message above is illustrative of what would happen if you skipped T1.

### 5. Close

```
> /speccraft:spec:close

Reading diff from started_at_sha to HEAD...
All tasks complete (7/7).

memory-keeper proposes:

[1] history.md ADR
    2026-05-08 — Rate limiting on public API
    Decision: token bucket, Redis-backed, fail-open.
    [Approve / Edit / Reject]
    > approve

[2] conventions.md addition
    "All HTTP middleware lives under internal/middleware/<name>/."
    Rationale: enforced naturally by 0042; codifying.
    [Approve / Edit / Reject]
    > approve

Wrote changelog.md, updated history.md, conventions.md.
Active spec cleared.
```

---

## Commands

| Command | Purpose |
|---|---|
| `/speccraft:init` | Bootstrap `.speccraft/` and `specs/` in this repo. |
| `/speccraft:sync` | Drift scan + memory-keeper audit. Reconcile drift. |
| `/speccraft:spec:new "<title>"` | Start a new spec via Socratic interview. |
| `/speccraft:spec:review` | Cross-model review of the active spec. |
| `/speccraft:spec:plan` | Generate a test-first plan from a reviewed spec. |
| `/speccraft:spec:implement` | Execute the active plan TDD-style. |
| `/speccraft:spec:delegate <agent> "<task>"` | Hand a discrete task to an aux agent. |
| `/speccraft:spec:review-code [--base <ref>]` | Cross-model review of the current diff. |
| `/speccraft:spec:close` | Write changelog, propose memory updates, close the spec. |
| `/speccraft:spec:override "<reason>"` | One-time bypass of the TDD invariant. Logged. |

Each command takes optional flags; run with `--help` for details.

---

## Auxiliary agents

speccraft talks to external CLI coding agents through a small registry at `.speccraft/agents.toml`:

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

Each agent needs to be installed and authenticated separately — speccraft is the dispatcher, not the runtime. See:

- Codex: https://developers.openai.com/codex/cli
- OpenCode: https://opencode.ai/docs
- Claude Code (`claude -p`): the same CLI you're running speccraft in

**ACP support (opt-in).** If you have [`acpx`](https://github.com/openclaw/acpx) installed, set `mode = "acp"` and `acp_agent = "codex"` (or any ACP-compatible agent name) to use a single ACP backend instead of direct shellouts.

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

---

## Enforcing conventions

Rules in `guardrails.md` and `conventions.md` can be tagged with an `enforce:` directive. When a `PostToolUse` hook fires after an edit, speccraft scans only files in scope for tagged rules and surfaces violations.

### Regex enforcement

```markdown
## Logging
- Use `slog` only. No `fmt.Println` outside `cmd/`. <!-- enforce: regex pattern="fmt\\.Print(ln|f)?" scope="!cmd/" -->
```

`scope` is a glob; `!` prefix excludes. The default scope is the entire repo. Violations show as `<file>:<line>: <rule-source>: matches <pattern>`.

### Advisory rules

Rules without an `enforce:` tag — including structural rules like layer dependencies, no-direct-http, and required test coverage — are documentation only in v1. Claude reads them at session start, but the hook doesn't act on them.

If you need *enforced* structural rules today, install [CodeGraphContext](https://github.com/CodeGraphContext/CodeGraphContext) (see [Recommended companions](#recommended-companions)) and use its tools to check architectural invariants. A future v1.x will add a bridge directive (`enforce: cgc rule="..."`) that wires CodeGraphContext output back into the speccraft drift hook.

---

## Recommended companions

speccraft is intentionally narrow in scope. Two external tools complement it well, and we recommend installing them alongside speccraft for non-trivial projects.

### CodeGraphContext — code intelligence as MCP

[CodeGraphContext](https://github.com/CodeGraphContext/CodeGraphContext) is an MCP server that gives Claude Code (and any MCP-compatible client) call-graph and symbol-search capabilities across your codebase. It's the recommended way to answer:

- "Where is this function called from?"
- "What does this file/package export?"
- "Which tests exercise this code?"
- "Does this change cross a layering boundary?"

speccraft v1 deliberately doesn't build this in. Earlier drafts included a JSON code graph at `.speccraft/graph/`; we removed it in favor of pointing users at a dedicated tool that's already solving the problem well. The two tools are complementary:

| Concern | Owned by |
|---|---|
| Spec lifecycle, intent, memory, history | speccraft |
| TDD discipline (sibling-test heuristic) | speccraft |
| Cross-model spec review | speccraft |
| Regex-based guardrails | speccraft |
| Call-graph / symbol queries | CodeGraphContext |
| Structural rule enforcement (layering, etc.) | CodeGraphContext (v1.x bridge planned) |

Install CodeGraphContext per its README; once it's a Claude Code MCP server, the speccraft skill will note its presence and prefer it over `grep`/`find` for structural questions.

### rtk (Rust Token Killer) — tool-call token compression

[rtk](https://github.com/rtk-ai/rtk) compresses the token cost of LLM tool-calling. If you're hammering aux agents through `/speccraft:spec:delegate` or `/speccraft:spec:review`, or if your sessions tend to chain many tool calls, rtk can cut per-message overhead substantially without changing semantics.

It's especially worth considering when:

- You delegate frequently to expensive aux agents (Codex, OpenCode running large models).
- Your `.speccraft/` memory plus a long diff plus the aux-agent prompt template is pushing context limits.
- You're iterating quickly and tool-call overhead is starting to dominate latency.

rtk is independent of speccraft — it operates at the LLM API layer, not the plugin layer — but it's the right tool to reach for when token economics start to bite. Install per its README; it integrates with most major LLM clients.

---

## TDD enforcement (how it works)

The `PreToolUse` hook intercepts every `Edit`/`Write`. For Go production files, it uses a **sibling-test heuristic**: edits to `pkg/foo/bar.go` are allowed only if some `pkg/foo/*_test.go` was edited more recently in this session.

This trades precision for simplicity. It correctly catches the "writing prod before tests" pattern in 100% of cases for code that follows Go's idiomatic test colocation. It can't tell you *which specific test* covers a given function — for that, install CodeGraphContext.

Tests, docs, README, and `scratch/` are always allowed without restriction. `/speccraft:spec:override "<reason>"` provides a one-shot bypass with the reason logged into the active spec.

---

## Rust

Rust support (spec 0005) ships a different model than Go and Python because Rust's idiomatic unit tests live **inline** inside the same `.rs` file as the production code under test (`#[cfg(test)] mod tests`). The sibling-edit heuristic doesn't apply; instead, the guard combines a delta-based static classifier with an authoritative test-runner invocation.

### Config

Opt into Rust support via `.speccraft/speccraft.toml`:

```toml
[tdd.rust]
runner = "cargo"   # one of: "cargo" (default) | "nextest"
```

- `runner = "cargo"` — uses `cargo test --exact <fqtn>`. Always available wherever a Rust toolchain is installed.
- `runner = "nextest"` — uses `cargo nextest run -E 'test(=<fqtn>)' --message-format libtest-json`. Requires `cargo install cargo-nextest --locked`. The guard exits with a clear error if `cargo-nextest` is not on PATH when this value is configured.
- Unknown values produce a config-parse error that names the file, key, and allowed enum.
- **No PATH auto-detection.** Selection is explicit so the same crate behaves the same on every machine.

### How edits are classified

Two idiomatic test locations are recognized:

- **inline tests** — `mod <ident>` items inside `src/**/*.rs` whose preceding attribute list contains `#[cfg(test)]` (or `#[cfg(any(test, ...))]`). Multi-attribute mod items (e.g. `#[cfg(test)] / #[allow(dead_code)] / mod tests { ... }`) are recognized too. A string/comment-aware tokenizer skips matches inside string literals, raw strings (`r"..."`, `r#"..."#`, etc.), char literals, and line/block comments — so a `let s = "#[cfg(test)] mod ..."` in production code is **not** misclassified as a test edit.
- **integration tests** — files at `tests/<stem>.rs` are stem-mapped to `src/<stem>.rs` (Rust 2015/2018 file form), `src/<stem>/mod.rs` (directory submodule), or the Rust 2018+ path form. `src/lib.rs` is the library crate root, not a stem-mapping target.

The classifier asks "does this edit add at least one new test function?" by computing the canonical-ID delta of `<file-stem>::<module-path>::<fn>` between pre-edit and proposed post-edit content. This precisely answers the test-add question without the false positives a naive regex would produce.

### Red-check via runner

The runner is the authoritative oracle for whether a real failing test exists. Each just-added FQTN is invoked through the configured runner (cargo or nextest, always with a targeted single-test filter — never a full-suite run). The three outcomes:

- `build_failed` → reject (`"build failed"`). Compile failure is **not** a valid red state.
- `all_passed` → reject (`"no failing test observed"`). Records with `status == "ignored"` count as ran-and-passed and do **not** satisfy the accept branch.
- `at_least_one_failed` → accept, and the failing-just-added IDs are appended to the baseline.

### Pre-edit gate

Before every `.rs` edit, a pre-edit gate compile-checks the crate via `cargo check --tests`. The gate is short-circuited by a **crate fingerprint** — SHA-256 of sorted `(path, mtime-nanos, size)` tuples over every `.rs` file under `src/`, `tests/`, `examples/`, `benches/`, plus `Cargo.toml`, `Cargo.lock`, and optional `rust-toolchain.toml` / `.cargo/config.toml`. `target/` is excluded. Cache hit → zero subprocesses. Cache miss → `cargo check --tests`. Whole-crate (not per-file) hashing ensures cross-file breakage doesn't escape the gate.

### Baseline lifecycle

The guard maintains `rust_test_baseline` in `.speccraft/state.json` (single-writer: `speccraft-state` only). Three mutation rules:

- **Initial capture.** On the first guard invocation with the baseline unset, the crate is walked and all current canonical test IDs are written as the baseline. The red-check is **skipped** on this invocation; stderr announces `rust_test_baseline captured: N tests`. This snapshots the "prior green state" so subsequent edits can compute a meaningful just-added set.
- **Post-accept update.** When the red-check accepts, the failing-just-added IDs are appended to the baseline. This prevents the same test from re-satisfying red on the next edit.
- **Manual recapture.** Run `speccraft-state rust-baseline recapture` to overwrite the baseline with a freshly-walked snapshot. Use this when speccraft was installed on a crate that already had pre-existing failing tests — recapture clears the stale entries after you fix them.

### Workspace handling

Cargo workspaces (`[workspace]` in root `Cargo.toml`) are **out of scope** in this release. The guard detects them and exits with an actionable message referencing spec 0006 (Cargo workspace support, reserved). Single-crate projects only — a `Cargo.toml` with `[package]` and no `[workspace]` table.

### What's out of scope

- Cargo workspaces (reserved spec 0006).
- Non-Cargo build systems (Buck2, Bazel).
- Doctests (`/// # Examples`). Run `cargo test --doc` yourself outside the speccraft loop.
- Proc-macro crates.
- Benchmarks (`#[bench]`, criterion).
- Retroactive runner-invocation adoption by Go and Python — the runner primitive is shared infrastructure, but Go/Python continue to use sibling-edit detection.

### Documentation policy

Spec 0005 added the runner primitive, Rust adapters, and the baseline lifecycle. Per the **stack-agnostic** guardrail, `templates/speccraft/**` was **not** modified — the templates ship to host repos without Rust-specific assumptions. All Rust-specific guidance lives here in the README.

---

## Configuration

Beyond `agents.toml`, a few environment variables tune behavior:

| Variable | Default | Effect |
|---|---|---|
| `SPECCRAFT_TDD_MODE` | `hybrid` | `hard` (block all prod edits without spec), `hybrid` (block prod, allow tests/docs), `soft` (warn only). |
| `SPECCRAFT_REVIEW_TIMEOUT` | `600` | Seconds. Overrides `agents.toml` default. |
| `SPECCRAFT_LOG_LEVEL` | `info` | `debug`, `info`, `warn`, `error`. |

---

## Requirements

**On your machine:**

- Claude Code (any recent version)
- `git`
- `jq` (for hook JSON parsing — install via your package manager)
- `curl` (for the first-run binary download)
- macOS (Apple Silicon or Intel) or Linux (x86_64 or ARM64). Windows users should run inside WSL.

**Optional:**

- `go` ≥ 1.22 — only needed if you want to build helper binaries from source instead of downloading the release tarball.
- `acpx` — only needed if you opt into ACP-mode aux agents.
- `codex`, `opencode`, etc. — only needed if you actually call them via `/speccraft:spec:delegate` or `/speccraft:spec:review`.
- [CodeGraphContext](https://github.com/CodeGraphContext/CodeGraphContext) — for codebase-wide structural queries (see [Recommended companions](#recommended-companions)).
- [rtk](https://github.com/rtk-ai/rtk) — for tool-call token compression in heavy aux-agent workflows.

**Inside your repo (for v1):**

- A Go module (`go.mod` at repo root, or in a discoverable parent). speccraft's spec lifecycle, memory, and TDD enforcement work language-agnostically, but the sibling-test heuristic assumes Go's `<dir>/foo.go` ↔ `<dir>/foo_test.go` colocation. v1.x will add per-language sibling resolvers.

---

## Troubleshooting

**`speccraft-state: command not found`**
First-run binary download failed. Run:
```
bash $CLAUDE_PLUGIN_ROOT/scripts/doctor.sh
```
to diagnose. Common causes: no network, corporate proxy blocking GitHub Releases, no `curl`. Fall back to building from source with Go ≥ 1.22 installed.

**Edits to test files are being blocked**
That's a bug — tests/docs/scratch should always be allowed. Check `SPECCRAFT_TDD_MODE`; if set to `hard` it blocks all edits without an active spec. Default is `hybrid`. File a bug if it reproduces with `hybrid`.

**`/speccraft:spec:review` reports "agent not found"**
The aux agent's CLI isn't on `PATH` in the Claude Code session's environment. Verify with:
```
which codex
which opencode
```
If the binary is in a non-default location, add it to `PATH` in your shell rc *and* restart Claude Code (it inherits the shell's environment at launch).

**TDD invariant blocks an edit but I did write a test**
The hook checks **same-directory** sibling tests for Go: editing `pkg/foo/bar.go` requires a recently-edited `pkg/foo/*_test.go`. Tests in a different package don't satisfy it. If your project keeps tests in a separate tree, set `SPECCRAFT_TDD_MODE=soft` until the per-language resolver lands in v1.x, or use `/speccraft:spec:override "<reason>"` for one-off cases.

**"Where is X called?" — speccraft can't tell me**
Correct, by design. v1 doesn't carry a code graph. Install [CodeGraphContext](https://github.com/CodeGraphContext/CodeGraphContext) as an MCP server and Claude Code will pick up its tools automatically. See [Recommended companions](#recommended-companions).

**`/speccraft:init` doesn't update `.gitignore`**
Likely the `.gitignore` already had a conflicting `.speccraft/` line. Check and reconcile manually; speccraft is conservative about overwriting existing patterns.

**Hooks don't seem to fire**
Run `/plugin` to verify speccraft is Enabled. Check that `hooks/hooks.json` exists in the plugin install. Hooks may be globally disabled by your Claude Code config — check `~/.claude/settings.json` for `"hooks": false` or matcher overrides.

**The doctor**
When in doubt:
```
bash $CLAUDE_PLUGIN_ROOT/scripts/doctor.sh
```
Reports on every dependency, the binary version stamp, network reachability, and configured aux agents.

---

## FAQ

**Does speccraft replace AGENTS.md / CLAUDE.md?**
Complementary. `.speccraft/index.md` is the always-injected one-pager — similar role to AGENTS.md or CLAUDE.md. Some teams use them in parallel; in that case, point your AGENTS.md at `.speccraft/index.md` so they don't drift.

**Can I use speccraft without aux agents?**
Yes. Skip `/speccraft:spec:review` and `/speccraft:spec:review-code`. Everything else (specs, TDD enforcement, memory) works without a single external CLI configured.

**Can I use it in a non-Go repo?**
Spec workflows, memory injection, and drift detection (regex mode) all work language-agnostically. TDD enforcement supports Go and Python:

- **Go:** same-directory `*_test.go` sibling (no config needed).
- **Python, colocated tests:** `test_bar.py` or `bar_test.py` beside `bar.py` (no config needed).
- **Python, separate `tests/` tree:** add `.speccraft/speccraft.toml`:
  ```toml
  [tdd]
  test_roots = ["tests"]
  ```
  `/speccraft:init` detects `tests/` and `test/` at the repo root and offers to write this file automatically.

For other languages, set `SPECCRAFT_TDD_MODE=soft` to convert blocks to warnings.

**What happens to specs after a spec is closed?**
They stay in `specs/`, marked `status: closed`. They become history. `/speccraft:sync` can `archive` very old closed specs (move under `specs/archive/`) but it never deletes them — they're git-versioned and serve as a record of decisions.

**Will the TDD invariant block me when I'm just experimenting?**
Three escape hatches: (1) edit tests/docs/scratch freely, (2) `/speccraft:spec:override "<reason>"` for a one-time bypass with a logged reason, (3) `SPECCRAFT_TDD_MODE=soft` to convert all blocks to warnings.

**Why doesn't speccraft have a built-in code graph?**
Earlier drafts did. We removed it because (a) it nearly doubled the v1 implementation cost, (b) a graph that drifts from the source produces confidently wrong answers, and (c) [CodeGraphContext](https://github.com/CodeGraphContext/CodeGraphContext) already does this well as an MCP server. speccraft v1 is small on purpose; install CodeGraphContext alongside it when you need structural queries.

**My aux-agent runs are eating tokens. Anything I can do?**
Look at [rtk](https://github.com/rtk-ai/rtk) — it's a tool-call token compressor that sits at the LLM API layer and can substantially cut overhead in workflows that chain many tool calls. See [Recommended companions](#recommended-companions).

**Can the spec-first invariant be bypassed by editing files outside Claude Code?**
Yes. speccraft only enforces what Claude Code does. If you `vim` a production file directly, no hook fires. The plugin is a workflow tool, not a security boundary.

**Does it phone home?**
No telemetry. The only network call is the one-time binary download from GitHub Releases on first install.

---

## Roadmap

**v1.x**
- Per-language sibling-test resolvers (Python, TypeScript, Rust, Java)
- Native Windows support (currently WSL only)
- Per-spec bypass audit log (`bypasses.md`)
- `enforce: cgc rule="..."` directive — bridge regex-mode drift to CodeGraphContext for structural rules

**v2**
- Multi-package monorepo awareness (per-package spec scoping)
- Multi-repo workspaces (federated `.speccraft/`)
- Marketplace publishing

See [SPEC.md](./speccraft-v1-spec.md) for the full v1 spec and detailed roadmap (§20).

---

## Development

speccraft is developed inside its own devcontainer. This ensures that buggy hooks under development can't lock up unrelated Claude Code sessions on your host machine.

**Prerequisites:** VS Code with the Dev Containers extension installed.

1. Clone the repo and open it in VS Code.
2. `Cmd+Shift+P` → `Dev Containers: Reopen in Container`. The container installs Go, jq, bats, and mock aux-agent CLIs automatically.
3. **Authenticate Claude Code inside the container** (one-time): run `claude` in the integrated terminal and complete the browser flow. The OAuth token lands in a named Docker volume and persists across `Rebuild Container`.
4. Start a Claude Code session *inside the container*. All hook development and testing happens here — never against the host.

**Run tests inside the container:**

```bash
# Go unit tests
cd tools && go test ./...

# Hook tests (bats)
bats tests/hooks/

# End-to-end lifecycle
bash tests/e2e/run.sh
```

`KEEP_TEST_DIR=1 bash tests/e2e/run.sh` preserves the throwaway Go module on failure for inspection.

**Non-interactive e2e (CI / no browser):** run `claude setup-token` on the host, store the result in `~/.env.devcontainer` (gitignored), and uncomment `CLAUDE_CODE_OAUTH_TOKEN` in `.devcontainer/devcontainer.json`.

---

## Contributing

speccraft is dogfood: it's developed in a speccraft-managed repo. The spec for v1 is itself a speccraft spec at `specs/0001-speccraft-v1/`.

If you want to contribute:

1. `/speccraft:spec:new "<your change>"` to draft a spec.
2. `/speccraft:spec:review` to get cross-model critique.
3. PR with the spec, plan, and implementation.

Before opening a PR, run:

```
go test ./tools/...
bash scripts/doctor.sh
```

Issues and discussions welcome.

---

## License

MIT. See [LICENSE](./LICENSE).

---

## Acknowledgments

speccraft borrows ideas from many places, particularly:

- The [oh-my-claudecode](https://github.com/Yeachan-Heo/oh-my-claudecode) family of plugins, which pioneered multi-CLI orchestration in Claude Code.
- [Forge](https://github.com/) and similar spec-driven development tools for the spec → plan → implement structure.
- [AGENTS.md](https://agents.md) for the always-injected memory pattern.
- [CodeGraphContext](https://github.com/CodeGraphContext/CodeGraphContext) for handling code-intelligence so speccraft doesn't have to.
- [rtk](https://github.com/rtk-ai/rtk) for tackling tool-call token economics as a separable concern.
- [ACP](https://github.com/openclaw/acpx) for showing what a unified agent protocol looks like.
