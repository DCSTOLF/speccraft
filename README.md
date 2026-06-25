![speccraft logo](images/speccraft-logo-banner.png)

> **Spec-first, test-driven development for [Claude Code](https://claude.com/code) — actually enforced.**

Other spec-driven tools help you *write* a spec. speccraft makes the discipline
**non-optional**: a hook blocks production edits until a failing test exists, specs and
diffs are reviewed by *other* models before code lands, an autonomous loop runs the
TDD cycle and only stops when a real decision is needed — and project memory stays
bounded and current as the codebase grows, instead of degrading the model the bigger it
gets.

```
/plugin marketplace add dcstolf/speccraft
/plugin install speccraft@dcstolf-tools
/reload-plugins
```

Then, in your project root:

```
/speccraft:init
/speccraft:spec:new "Add a /healthz endpoint"
```

That's "it works." The full install picture — helper binaries, requirements,
configuration — is in **[INSTALL.md](./INSTALL.md)**.

---

## Why speccraft

### 1. Hook-enforced TDD — the edit is *blocked*, not nudged

A `PreToolUse` hook intercepts every `Edit`/`Write` and blocks edits to production
files until a covering test has been written **and observed failing** in the session.
The rule is language-aware: Go and Python use a sibling-test heuristic,
TypeScript/JavaScript use a sibling + runner check, and Rust uses a delta-based static
classifier plus the test runner as an oracle (because Rust's unit tests live inline).
No competitor blocks the edit — they suggest. Tests, docs, and `scratch/` are always
free, and `/speccraft:spec:override "<reason>"` gives a logged one-shot bypass.

### 2. Cross-model review — catch what one model can't

`/speccraft:spec:review` and `/speccraft:spec:review-code` route a spec or a diff in
**parallel** to the external CLI agents you've configured, then synthesize the
verdicts into `review.md`. The default registry ships Codex and OpenCode (plus
`claude -p`); the registry is just CLI commands, so you can add any other agent. A
single-model tool can't flag what its own model is blind to. (Review depends on those
agents being installed and authenticated — speccraft is the dispatcher, not the
runtime.)

### 3. Autonomous implementation loop — stops only when *you* matter

`/speccraft:spec:implement` runs the RED→GREEN→REFACTOR cycle on its own, from a
reviewed spec and plan, delegating discrete tasks to aux agents where useful. It
surfaces a blocker only when a developer decision is genuinely required — not at every
step.

### 4. Context-bloat resilience — memory that stays bounded *and* true

The common failure of spec-first tools is that performance degrades as the project
grows: specs pile up, memory bloats, stale context misleads the model. speccraft is
built against this. Closed specs **consolidate** into current `specs/domains/<area>.md`
files instead of accumulating as per-feature silos; `history.md` is **compacted**
(newest entries kept verbatim, older ones folded into a thematic summary, originals
archived) instead of growing append-only; and only a one-page `index.md` is always
injected — guardrails, architecture, conventions, and history load on demand. Memory
stays bounded, current, and enforced as the codebase scales.

**Also worth knowing:** `.speccraft/` memory is auto-injected (a one-page always-on
index, deeper files on demand), and `enforce:` regex guardrails in `guardrails.md` /
`conventions.md` fire at edit time. See [docs/architecture.md](./docs/architecture.md).

---

## Commands

| Command | Purpose |
|---|---|
| `/speccraft:init` | Bootstrap `.speccraft/` and `specs/` in this repo. |
| `/speccraft:spec:new "<title>"` | Start a new spec via Socratic interview. |
| `/speccraft:spec:review` | Cross-model review of the active spec. |
| `/speccraft:spec:plan` | Generate a test-first (RED→GREEN→REFACTOR) plan. |
| `/speccraft:spec:implement` | Run the TDD implementation loop. |
| `/speccraft:spec:review-code` | Cross-model review of the current diff. |
| `/speccraft:spec:delegate <agent> "<task>"` | Hand a task to an aux agent. |
| `/speccraft:spec:close` | Changelog, memory updates, consolidate, close. |
| `/speccraft:sync` | Drift scan + memory audit. |

Optional PM/Architect lanes (`/speccraft:pm:*`, `/speccraft:arch:*`) sit upstream of
specs, and `/speccraft:history:compact` keeps history bounded. **Full reference,
including the illustrated lifecycle, aux-agent setup, and convention enforcement:
[docs/commands.md](./docs/commands.md).**

---

## How speccraft compares

Spec-driven tools sit on a spectrum from *structure* (help me write a good spec) to
*enforcement* (make the discipline non-optional). speccraft is built around
enforcement. The others land elsewhere, and specsmith specializes in the upstream
"idea → spec" step.

### Capability matrix

| Capability | speccraft | delta-spec | shipspec | specsmith |
|---|---|---|---|---|
| **Type** | Claude Code plugin | Claude Code plugin | Claude Code plugin | Hosted SaaS CLI |
| **Spec generation from rough ideas** | ✅ Socratic interview | ✅ proposal-driven | ✅ PRD interview | ✅ clarifying chat |
| **Identifies ambiguity / missing edge cases** | ✅ cross-model review | ⚠️ manual | ✅ PRD agent | ✅ core feature |
| **Acceptance criteria / Definition of Done** | ✅ | ✅ GWT scenarios | ✅ per-task | ✅ |
| **Spec formalism** | prose + AC | RFC-2119 + GIVEN/WHEN/THEN | numbered REQ-IDs | structured AC + DoD |
| **Versioned specs in-repo** | ✅ `specs/NNNN-slug/` | ✅ delta-merged by domain | ✅ per-feature dir | ❌ (specs are output) |
| **Test-first plan generation** | ✅ RED→GREEN→REFACTOR | ❌ | ✅ task breakdown | ❌ |
| **TDD enforcement (blocks prod edits)** | ✅ hook-enforced, Go/Python/JS·TS/Rust | ❌ | ❌ | ❌ |
| **Cross-model / multi-agent review** | ✅ Codex + OpenCode in parallel | ❌ | ⚠️ Claude subagents only | ❌ |
| **Autonomous iteration loop** | ✅ surfaces a blocker only when a developer decision is required | ❌ | ✅ Ralph loop (retry until verified) | ❌ |
| **Auto-injected repo memory** | ✅ guardrails / architecture / conventions / history | ⚠️ git history | ⚠️ per-feature docs | ❌ |
| **Convention enforcement (regex guardrails)** | ✅ `enforce:` directives | ❌ | ❌ | ❌ |
| **Spec consolidation (merge closed specs → domain files)** | ✅ on close | ✅ delta-merge on archive | ❌ per-feature silos | ❌ |
| **Memory compaction (bounded history)** | ✅ compacts `history.md` | ⚠️ git is the archive | ⚠️ context deleted per feature | ❌ |
| **External tracker integration** | ❌ | ❌ | ❌ | ✅ Jira, GitHub |
| **Runs fully local / offline** | ✅ (one-time binary download) | ✅ pure shell | ✅ | ❌ cloud API required |
| **Install footprint** | helper binaries + `jq` | trivial (shell only) | medium | `pip` + cloud key |
| **License / cost** | MIT, free | MIT, free | MIT, free | MIT client, paid platform |

✅ first-class · ⚠️ partial / indirect · ❌ not offered

### Drift & scale: how each keeps memory bounded *and* true

The common failure of spec-first tools is that performance degrades as the project
grows — specs pile up, memory bloats, and stale context starts misleading the model.
Each tool picks one defense, and most trade away something for it.

| Strategy | Tool | Keeps context bounded by… | Catches spec↔code drift? |
|---|---|---|---|
| **Consolidation + compaction + enforcement** | **speccraft** | merging closed specs into domain files **and** compacting `history.md`, on top of a 1-page always-injected index | ✅ edit-time hook + `/speccraft:sync` drift scan |
| Consolidation only | delta-spec | collapsing deltas into domain specs at archive | ❌ nothing automatic between archives |
| Ephemeral re-extraction | shipspec | deleting per-feature context, re-deriving each time | ⚠️ only within a feature's own loop |
| Externalize entirely | specsmith | keeping nothing locally | ❌ spec frozen at generation |


speccraft is the only tool here that keeps project memory **bounded, current, and
enforced at the same time**: closed specs fold into consolidated domain specs instead
of accumulating as silos, `history.md` is compacted rather than growing append-only,
and an edit-time hook plus `/speccraft:sync` catch drift between spec and code.

---

## Scope & limitations

speccraft is deliberately small in scope. What it does **not** do, stated plainly:

- **Enforcement covers four languages.** Hook-enforced TDD supports Go, Python,
  TypeScript/JavaScript, and Rust. For any other language, set
  `SPECCRAFT_TDD_MODE=soft` to convert blocks to warnings.
- **Only `enforce:` regex rules are enforced.** Advisory rules in `guardrails.md` /
  `conventions.md` *without* an `enforce:` tag are documentation only — Claude reads
  them, but the hook does not act on them. Enforcement is limited to what a regex can
  express.
- **Structural/architectural rules are out of scope.** Layer dependencies, call-graph
  constraints, and symbol queries are delegated to
  [CodeGraphContext](https://github.com/CodeGraphContext/CodeGraphContext) (see
  [Recommended companions](./docs/commands.md#recommended-companions)).
- **Cross-model review needs the agents available.** It's not zero-config — Codex,
  OpenCode, or whatever you configure must be installed and authenticated, or that
  agent is simply skipped. speccraft is the dispatcher, not the runtime.
- **Not a security boundary.** The hook only enforces what Claude Code does. Edit a
  production file with `vim` and no hook fires.

---

## Documentation

- **[INSTALL.md](./INSTALL.md)** — install, helper binaries, requirements,
  configuration, troubleshooting.
- **[docs/commands.md](./docs/commands.md)** — full command reference, illustrated
  lifecycle, aux-agent setup, convention enforcement, FAQ.
- **[docs/architecture.md](./docs/architecture.md)** — how the hooks, the Rust delta
  classifier, the Go/Python sibling heuristic, and consolidation/compaction work; CI.
- **[CONTRIBUTING.md](./CONTRIBUTING.md)** — devcontainer setup and running tests.

---

## License

MIT. See [LICENSE](./LICENSE).

## Acknowledgments

speccraft borrows ideas from many places, particularly:

- The [oh-my-claudecode](https://github.com/Yeachan-Heo/oh-my-claudecode) family of
  plugins, which pioneered multi-CLI orchestration in Claude Code.
- Spec-driven development tools for the spec → plan → implement structure.
- [AGENTS.md](https://agents.md) for the always-injected memory pattern.
- [CodeGraphContext](https://github.com/CodeGraphContext/CodeGraphContext) for handling
  code-intelligence so speccraft doesn't have to.
- [rtk](https://github.com/rtk-ai/rtk) for tackling tool-call token economics as a
  separable concern.
- [ACP](https://github.com/openclaw/acpx) for showing what a unified agent protocol
  looks like.