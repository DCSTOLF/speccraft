# Architecture & internals

How speccraft is built and how each enforcement mechanism actually works. For the
pitch, see the [README](../README.md); for commands, see
[docs/commands.md](./commands.md).

## What it adds to your repo

```
.speccraft/
├── index.md          # 1-page summary, auto-injected on every session start
├── guardrails.md     # hard rules, optionally enforced by hooks
├── architecture.md   # current shape, layering, key decisions
├── conventions.md    # style and patterns, optionally enforced
├── history.md        # ADR log, compacted to stay bounded
├── agents.toml       # auxiliary agent registry
└── state.json        # runtime state (gitignored)

specs/
├── 0001-some-feature/
│   ├── spec.md       # WHAT, WHY, acceptance criteria
│   ├── plan.md       # test-first plan
│   ├── review.md     # cross-model critique
│   ├── tasks.md      # checklist with status
│   └── changelog.md  # what shipped vs what was specced
└── domains/          # consolidated, current requirements by area
```

`.speccraft/state.json` is gitignored. Everything else is part of your repo and meant
to be committed — your team's intent, conventions, and history live with the code.

## Packaging

speccraft is a Claude Code plugin (`.claude-plugin/plugin.json`, marketplace
`dcstolf-tools`) with three execution surfaces:

- **Shell hooks** (`hooks/`, wired through `hooks/hooks.json`) that gate `Edit`/`Write`
  tool calls.
- **Slash commands** (`commands/`) the user invokes.
- **Subagents** (`agents/`) the orchestrator dispatches: planner, critic, reviewer,
  delegator, memory-keeper, plus pm-/arch-critics.

Hooks and commands call three small Go binaries whose shared logic lives in
`tools/internal/speccraft`:

- `speccraft-state` — session/spec state in `.speccraft/state.json` (single-writer).
- `speccraft-guard` — the TDD red→green invariant.
- `speccraft-drift` — regex scan of `enforce:` rules in memory files.

## TDD enforcement

The `PreToolUse` hook intercepts every `Edit`/`Write`. The rule applied depends on the
file's language; the rest of the flow (active-spec check, override mechanism,
tests/docs/scratch exemptions) is shared. In all cases, tests, docs, README, and
`scratch/` are always allowed. `/speccraft:spec:override "<reason>"` provides a
one-shot bypass with the reason logged. For unsupported languages,
`SPECCRAFT_TDD_MODE=soft` converts blocks to warnings.

### Go — sibling-test heuristic

Edits to `pkg/foo/bar.go` are allowed only if some `pkg/foo/*_test.go` was edited more
recently in this session. Trades precision for simplicity but catches the
"writing prod before tests" pattern for code following Go's idiomatic test colocation.

### Python — two-tier sibling lookup

Tier 1: same-directory siblings (`test_bar.py` or `bar_test.py` beside `bar.py`) — no
config. Tier 2: when no sibling is found and `.speccraft/speccraft.toml` declares
`[tdd] test_roots`, the configured roots are walked recursively for `test_<stem>.py` /
`<stem>_test.py`. This supports projects that keep tests in a separate `tests/` tree.

### TypeScript / JavaScript

JS and TS share one adapter. A production edit requires a sibling test file —
`<stem>.test.<ext>` / `<stem>.spec.<ext>` in the same directory or under `__tests__/`,
across the eight JS/TS extensions — and an observed failing test captured in the
session. The per-language runner is configured under `[tdd.javascript]` /
`[tdd.typescript]` in `.speccraft/speccraft.toml`:

```toml
[tdd.javascript]
command = "vitest run"
```

### Rust — delta classifier + runner-as-oracle

Rust's idiomatic unit tests live **inline** inside the same `.rs` file as the
production code (`#[cfg(test)] mod tests`), so the sibling-edit heuristic can't apply.
The guard combines a delta-based static classifier with an authoritative test runner.

Opt in via `.speccraft/speccraft.toml`:

```toml
[tdd.rust]
runner = "cargo"   # "cargo" (default) | "nextest"
```

`nextest` uses `cargo nextest run -E 'test(=<fqtn>)' --message-format libtest-json` and
requires `cargo-nextest` on PATH. There is **no PATH auto-detection** — selection is
explicit so the same crate behaves the same on every machine.

**Classifying edits.** Two idiomatic test locations are recognized: inline `mod`
items whose preceding attributes contain `#[cfg(test)]` (multi-attribute mods
included), and integration tests at `tests/<stem>.rs` stem-mapped back to their source
module. A string/comment-aware tokenizer skips matches inside string literals, raw
strings, char literals, and comments, so a `"#[cfg(test)] mod ..."` in production code
is **not** misclassified. The classifier computes the canonical-ID delta of
`<file-stem>::<module-path>::<fn>` between pre- and proposed post-edit content to
answer "does this edit add at least one new test function?".

**Red-check via runner.** Each just-added FQTN is invoked through the configured
runner with a targeted single-test filter (never a full-suite run):

- `build_failed` → reject (`"build failed"`). A compile failure is not a valid red state.
- `all_passed` → reject (`"no failing test observed"`). `ignored` counts as ran-and-passed.
- `at_least_one_failed` → accept; the failing-just-added IDs are appended to the baseline.

**Pre-edit gate.** Before every `.rs` edit, the crate is compile-checked via
`cargo check --tests`, short-circuited by a **crate fingerprint** — SHA-256 of sorted
`(path, mtime-nanos, size)` tuples over every `.rs` file under `src/`, `tests/`,
`examples/`, `benches/`, plus `Cargo.toml`, `Cargo.lock`, and optional toolchain/config
files (`target/` excluded). Cache hit → zero subprocesses; miss → `cargo check --tests`.
Whole-crate hashing ensures cross-file breakage doesn't escape the gate.

**Baseline lifecycle** (`rust_test_baseline` in `state.json`, single-writer):
- *Initial capture* — first invocation with the baseline unset walks the crate and
  records all current test IDs; the red-check is skipped this once.
- *Post-accept update* — accepted failing-just-added IDs are appended so the same test
  can't re-satisfy red on the next edit.
- *Manual recapture* — `speccraft-state rust-baseline recapture` overwrites with a
  fresh snapshot; use it when speccraft was installed on a crate that already had
  failing tests.

**Out of scope for Rust:** Cargo workspaces (`[workspace]` is detected and rejected
with a message referencing reserved spec 0006), non-Cargo build systems (Buck2,
Bazel), doctests, proc-macro crates, and benchmarks. Single-crate projects only.

Per the stack-agnostic guardrail, `templates/speccraft/**` ships to host repos without
Rust-specific assumptions — all Rust-specific guidance lives in docs.

## Consolidation & compaction

The common failure of spec-first tools is that performance degrades as the project
grows. speccraft has two mechanisms against this, on top of the always-injected
1-page `index.md` (everything else loads on demand).

**Spec consolidation (on close).** Closing a spec folds its final requirements into a
consolidated, *current* `specs/domains/<area>.md` instead of leaving N permanent
per-feature directories to diff. A domain exists iff its file exists. The merge is
ADD/MODIFY/REMOVE per requirement (the delta-spec model); every MODIFY/REMOVE carries a
required verbatim locator matched by exact-normalized comparison, with a non-blocking
conflict path on 0-or-multiple matches. It runs inline at `/speccraft:spec:close`
(confirm-gated, never blocks close), with a retroactive `/speccraft:sync` backfill. The
closed spec directory then moves wholesale to `specs/.archive/NNNN-slug/`; superseded
requirement text moves to `specs/domains/.archive/<area>.md`. Status stays `closed` —
location signals "consolidated".

**History compaction.** `.speccraft/history.md` is kept bounded rather than
append-only. `/speccraft:history:compact` (confirm-gated) keeps the newest N entries
(default 10) verbatim, folds older ones into a merged thematic `## Compacted` section,
and moves the originals verbatim into an append-only `.speccraft/history-archive/`
folder (double provenance: archive file plus git). A non-blocking nudge fires at
`spec:close` when the log grows past a count/size threshold. The whole mechanism is
clock-free; the recent window is positional (first N by date header in file order).

Both are pure-bash libraries (`commands/spec/consolidate.lib.sh`,
`commands/history/compact.lib.sh`) pinned by bats tests, reusing the `memory-keeper`
subagent in dedicated modes.

## Drift detection

`/speccraft:sync` runs `speccraft-drift`, a regex scan of `enforce:` rules in the
memory files against files in scope, plus a memory-keeper audit that reconciles the
memory against the actual repo state and backfills any un-consolidated closed specs.

## CI

The GitHub Actions workflow (`.github/workflows/ci.yml`) splits e2e coverage into two
jobs:

- **`e2e-language-only`** — runs on **every push and PR**. Builds the devcontainer and
  runs `bash tests/e2e/run.sh --language-only`, exercising the per-language fixtures
  without ever invoking `claude -p`. Does **not** require `ANTHROPIC_API_KEY`. Fast,
  hermetic, free — the primary signal that the language dispatch in `speccraft-guard`
  is correct.
- **`e2e-devcontainer`** — runs **only on push to `main`**. Exercises the full spec
  lifecycle by calling `claude -p`. **Requires `ANTHROPIC_API_KEY`**, costs real
  credits, and is gated to `main` to bound spend.

When `e2e-devcontainer` fails on an environmental problem (not a real assertion
failure), the log includes a literal `ENVIRONMENT_FAILURE: <category>` line —
`credit_exhausted`, `auth`, or `transient_api`. The exit code stays non-zero in every
case; the annotation is observability, not error-swallowing.
