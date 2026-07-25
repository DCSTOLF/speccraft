---
id: "0034"
title: "Stack-agnostic planning & execution"
status: closed
created: 2026-07-25
revision: 2
authors: [claude]
packages: ["tools/internal/speccraft", "tools/cmd/speccraft-state", "agents", "commands/spec", "templates/speccraft"]
related-specs: ["0030", "0002", "0005", "0010", "0018"]
---

# Spec 0034 — Stack-agnostic planning & execution

## Why

Field feedback from running speccraft as an *installed* plugin in a **Python**
repo (the same engagement that produced specs 0030/0031) surfaced finding #5:
the **planning and execution prose is Go-shaped**. The user had to mentally
translate every instruction because the plugin told the model to think in Go:

- `agents/tdd-planner.md` rule 3 hardcodes *"For Go: tests live in the same
  directory … (`*_test.go` sibling files)"*, rule 7 says every step is
  *"verifiable by `go test ./...`"*, and its example paths are Go.
- `commands/spec/plan.md` discovers tests with `find <pkg> -name '*_test.go'`.
- `commands/spec/implement.md` and `commands/spec/delegate.md` mandate
  `go test ./...` after each step.
- `templates/speccraft/conventions.md` — the file `/speccraft:init` **copies
  into every host repo** — ships a Go-specific test regex
  (`pattern="^func Test[A-Z]" scope="**/*_test.go"`), Go error-wrapping
  (`fmt.Errorf`), and `slog`/`cmd/` rules. Shipping Go conventions into a
  Python project is a direct violation of the standing guardrail *"plugin
  templates must stay stack-agnostic."*

Crucially, the **execution substrate is already stack-aware** — this spec only
surfaces it, it does not change it. Two existing paths already resolve a
per-language test command:

- **go / python / js / ts** route through `runner.AdapterForLanguage(lang, cfg)`,
  whose command comes from `cfg.TDD.<Lang>.Command`
  (`cfg.TDD.Go.Command`, `cfg.TDD.Python.Command`, `cfg.TDD.JavaScript.Command`,
  `cfg.TDD.TypeScript.Command`).
- **rust** routes through a *separate* path — `runner.AdapterFor(cfg)` selects
  `CargoAdapter` or `NextestAdapter` from `cfg.TDD.Rust.Runner`
  (`"cargo"`→`cargo test`, `"nextest"`→`cargo nextest run`).

So all five languages the plugin executes (go, rust, python, js, ts) already have
a resolvable effective test command; the gap is entirely in the **authoring
layer** — the prose the model reads and the template it copies. This spec closes
that gap by reading those same config-backed commands, surfacing them as a
first-class subcommand, seeding project memory at init, and making the prose
reference the *project's* test command instead of Go's.

## What

Per the 2026-07-25 scoping decision — **detect-at-init seeds `conventions.md`
(which is the editable source of truth thereafter)** and the fix reaches
**prose + the shipped template** — deliver four coordinated layers. Revision-2
pins the interface contracts the 2026-07-25 review flagged.

### 1. Detection core (Go, TDD-heavy)

A new `DetectStack(root, cfg)` in `tools/internal/speccraft` inspects **only the
exact repo-root manifest paths** (never subdirectories or workspaces) and returns
a typed result reusing the config-backed commands above:

```go
type Stack struct {
    Language     string   // "go" | "rust" | "python" | "js" | "ts" | "unknown"
    TestCommand  string   // e.g. "go test ./...", "" for unknown
    TestPatterns []string // ordered filename globs; NEVER carries non-glob prose
    InlineTests  bool     // true for rust (#[test] modules aren't a filesystem glob)
}
```

Manifest → language mapping (root-level presence only):

| Root manifest | Language | TestCommand source | TestPatterns | InlineTests |
|---|---|---|---|---|
| `go.mod` | `go` | `cfg.TDD.Go.Command` (dflt `go test ./...`) | `["*_test.go"]` | false |
| `Cargo.toml` | `rust` | from `cfg.TDD.Rust.Runner` (`cargo`→`cargo test`, `nextest`→`cargo nextest run`) | `["tests/*.rs"]` | **true** |
| `pyproject.toml` \| `setup.py` \| `setup.cfg` \| `requirements.txt` | `python` | `cfg.TDD.Python.Command` (dflt pytest) | `["test_*.py","*_test.py"]` | false |
| `package.json` + `tsconfig.json` | `ts` | `cfg.TDD.TypeScript.Command` | `["*.test.ts","*.spec.ts"]` | false |
| `package.json` (no `tsconfig.json`) | `js` | `cfg.TDD.JavaScript.Command` | `["*.test.js","*.spec.js"]` | false |
| none of the above | `unknown` | `""` | `[]` | false |

**Polyglot precedence (fixed, documented public contract).** When several
manifests coexist, the primary language is chosen by this order, highest first:

> **go > rust > python > ts > js**

Rationale: a compiled-language manifest (`go.mod`, `Cargo.toml`) is almost never
present as mere auxiliary tooling, whereas `package.json` frequently is (build
tooling in a non-JS repo), so JS/TS ranks last; Python sits between. `ts` outranks
`js` because `tsconfig.json` is a strict refinement of a `package.json` repo. The
order is data in one place in the code and pinned by AC2 at every adjacent
boundary — it is NOT filesystem-iteration-order dependent.

### 2. Two `speccraft-state` subcommands surfacing it

- `speccraft-state detect-stack` — resolves the repo root via the existing
  `find-root` logic (walk up to the `.speccraft/`-bearing ancestor; error
  non-zero if none) and prints a **versioned JSON object**:
  `{"schema":1,"language":"python","test_command":"pytest -q","test_patterns":["test_*.py","*_test.py"],"inline_tests":false}`.
  Exit 0 for a resolvable root **including** `unknown` (language `"unknown"`,
  `test_command":""`); non-zero only on an I/O / no-repo-root error.
- `speccraft-state test-command` — prints the **effective** test command as raw
  text (no shell evaluation — it is data) and exits 0; prints nothing and exits
  **non-zero** when the effective command is empty/unknown, so command docs can
  branch. Precedence: the value recorded in `.speccraft/conventions.md`'s marker
  (below) if present and non-empty, else the `detect-stack` fallback.

### 3. The conventions.md marker (grammar pinned)

Recorded on a single line, an HTML comment so it is inert in rendered Markdown:

```
<!-- speccraft:test-command = "pytest -q" -->
```

- **Regex (applied per-line, never across newlines):**
  `<!--\s*speccraft:test-command\s*=\s*"((?:\\.|[^"\\])*)"\s*-->` — the body is a
  proper quoted string: each character is either an escape pair (`\"`, `\\`) or a
  non-`"`/non-`\` char, so an *unescaped* interior `"` cannot match and falls to
  the malformed case. On read, unescape `\"`→`"` and `\\`→`\`. The per-line,
  `[^\n]`-equivalent body pins the match to a single-line comment so a future
  multiline HTML comment cannot smuggle a match across lines.
- **Empty value** (`""`) → treated as *not recorded* → detection fallback.
- **Malformed** (no regex match) → ignored → detection fallback (never an error
  that blocks `test-command`).
- **Duplicate markers** → the **first** occurrence wins (deterministic); pinned
  by test.
- A command containing quotes or shell operators (`&&`, `|`) round-trips
  verbatim — `test-command` emits it as data, does not evaluate it.

### 4. `/speccraft:init` seeds conventions.md (preserve-existing)

- If `.speccraft/conventions.md` **already exists**, init **preserves it
  untouched** — it is the editable source of truth (idempotent; re-init never
  clobbers user edits).
- On a fresh init, copy the neutral template, then run `detect-stack` and fill
  the testing section + marker from the result. `unknown` → a clearly-marked
  `TODO` placeholder + an empty-value marker, never a wrong Go default.

### 5. Stack-neutral authoring prose + template

Rewrite `tdd-planner.md`, `plan.md`, `implement.md`, `delegate.md` to reference
*the project's* command (`speccraft-state test-command` / the conventions.md
value) and test naming, keeping a language name only inside a clearly-labeled
example. Strip `templates/speccraft/conventions.md` of Go-specific `enforce:`
rules and idioms.

The plugin's **own** repo is Go, so speccraft's own CI still runs `go test ./...`
— correct and unchanged. What must become stack-neutral is only what the plugin
*tells host repos and the authoring model* to do.

## Acceptance criteria

1. **Detection table (core).** `DetectStack(root, cfg)` is table-tested over
   single-manifest fixture roots and returns the exact `Stack` (language,
   config-backed `TestCommand`, `TestPatterns` list, `InlineTests`) per the
   §What table — including `Cargo.toml`→`rust` with `InlineTests:true` and its
   command derived from `cfg.TDD.Rust.Runner` (both `cargo` and `nextest`
   asserted), and `package.json`±`tsconfig.json`→`ts`/`js`.

2. **Polyglot precedence + unknown (both direct-asserted).** For a root holding
   *multiple* manifests, `DetectStack` returns the primary language by the
   documented order **go > rust > python > ts > js**, with a test case pinning
   **each adjacent boundary** (go beats rust; rust beats python; python beats ts;
   ts beats js) so the order cannot silently change. For a root with **no**
   recognized manifest it returns `Language:"unknown"`, `TestCommand:""`,
   `TestPatterns:[]` — asserted directly, not by absence.

3. **`detect-stack` subcommand (versioned JSON).** `speccraft-state detect-stack`
   at a fixture root prints the `{"schema":1,…}` object; a Python fixture's
   `test_command` is the pytest command and is NOT `go test ./...`; a Go fixture's
   is `go test ./...`. Exit is 0 for a resolvable root including `unknown`, and
   non-zero when no `.speccraft/` repo root can be resolved (run outside a repo).

4. **`test-command` precedence + marker grammar.** `speccraft-state test-command`
   returns the conventions.md marker value when present and non-empty (asserted:
   an edited marker overrides detection; a marker holding a command with a shell
   operator and an escaped `\"` round-trips verbatim), and falls back to
   `detect-stack` when the marker is **absent, empty, or malformed**. With two
   markers the **first** wins. When the effective command is empty/unknown it
   prints nothing and exits non-zero. Parsing is the single-line regex above.

5. **init seeds, not hardcodes; preserves existing.** After `/speccraft:init` in
   a non-Go fixture repo with no prior `conventions.md`, the resulting
   `.speccraft/conventions.md` contains that project's detected test command +
   naming + the marker, and does **not** contain the Go-specific
   `scope="**/*_test.go"` enforce rule or `fmt.Errorf`/`slog` idioms. Re-running
   init, or running it where `conventions.md` already exists, leaves that file
   **byte-identical** (idempotent preserve). `unknown` stack → a `TODO`
   placeholder + empty marker, not a Go default. (Verified by an init-path test
   or bats over a Python/JS fixture and an existing-file fixture.)

6. **Authoring prose is stack-neutral (mechanical recurrence guard).** A meta-test
   (spirit of spec 0033's fixture-shape guard) scans `agents/tdd-planner.md` and
   `commands/spec/{plan,implement,delegate}.md` for fenced code blocks containing
   a concrete language test command (`go test`, `cargo test`/`cargo nextest`,
   `pytest`, `npm test`/`npm run`, `jest`, `find … -name '*_test.go'`). A block is
   a **violation** unless it is *either* immediately preceded — the nearest
   non-blank line above matching the label regex `^\s*(#+\s*|>\s*)?example\b`
   (case-insensitive), so a genuine "Example" heading/label qualifies but prose
   merely ending in "…for example:" does not — *or* it invokes
   `speccraft-state test-command`. This mechanical labeled-example-or-`test-command`
   rule replaces subjective "mandate vs example" detection. The test passes on the
   rewritten prose.

7. **Shipped template is stack-agnostic.** `templates/speccraft/conventions.md`
   contains no language-specific `enforce:` regex bound to a language file glob
   and no language-specific idiom (`fmt.Errorf`, `slog`, `^func Test`,
   `*_test.go`). A test asserts the shipped template is free of these tokens
   (promoting the "templates stay stack-agnostic" guardrail from advisory to an
   executable check).

8. **Scope + green suite + version bump.** Changes are contained to: the
   detection core + tests (`tools/internal/speccraft`), the two `speccraft-state`
   subcommands + tests (`tools/cmd/speccraft-state`), the four authoring docs,
   `templates/speccraft/conventions.md`, `commands/spec/init.md` (seeding wiring),
   and the two new meta-tests (AC6, AC7). `go test ./...` and `tests/hooks/*.bats`
   stay green. Because this adds user-facing subcommands and changes shipped
   command/template behavior, `const version` is bumped **1.7.1 → 1.8.0** and the
   §Version bumps convention applies. Per spec 0030 AC11's precedent, the
   published-verified-release half (auto-tag → `release.yml` → `verify-release.sh`
   on `main`) is **inherited as a merge-time obligation**, not a pre-close gate.

## Out of scope

- Changing `speccraft-guard`'s runtime language dispatch, `AdapterForLanguage`,
  `AdapterFor`, or any red→green execution behavior — the execution layer is
  already stack-aware; this spec only surfaces and documents it.
- Adding NEW language support (e.g. Ruby, Java). Detection covers exactly the
  five languages the plugin already runs: go, rust, python, js, ts.
- MultiEdit/NotebookEdit payload modeling (reserved spec 0032).
- **Migrating already-initialized host repos.** Seeding happens at
  `/speccraft:init` time only. Because init **preserves** an existing
  `conventions.md` byte-for-byte (§4/AC5), a repo initialized before 1.8.0 keeps
  its Go-shaped `conventions.md` until the user **manually edits or removes it**
  — re-running init alone does NOT migrate it. AC5's benefit is therefore
  **opt-in for existing installs**; the 1.8.0 upgrade does not auto-heal an
  existing `conventions.md`.
- Workspace / monorepo detection (nested manifests) — detection reads only
  exact repo-root manifest paths.
- A deeper redesign of the `speccraft.toml` config schema — `test-command` reads
  the existing `SpeccraftConfig` commands; the only new persisted surface is the
  single conventions.md marker line.

## Open questions

_none_ — the two scoping decisions (source: **both**, detect seeds conventions.md
which then wins; surface: **prose + template**) were resolved at authoring time,
and the revision-2 interface contracts (Rust path, polyglot order, marker
grammar, JSON encoding, typed patterns, AC6 mechanical rule, init preserve,
out-of-root behavior, migration + release-verify notes) were pinned from the
2026-07-25 cross-model review.
