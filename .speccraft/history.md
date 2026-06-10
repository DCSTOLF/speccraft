# History

Append-only. Newest first.

## 2026-06-10 — E2E contracts encode structural predicates, not model-chosen content (spec 0014)

**Spec:** specs/0014-tighten-e2e-history-assertion/
**Decision:** When an e2e assertion verifies that a model-driven
step happened (memory-keeper applied an ADR, spec-author wrote a
plan, planner emitted a `## Risk` section, etc.), the predicate
must target a STRUCTURAL signal the agent's contract guarantees,
not a CONTENT signal the agent's free-text choice happens to
produce. Concretely: `tests/e2e/run.sh`'s `[7/9]
/speccraft:spec:close` assertion at line 278 now matches the
dated ADR-header shape `^## 20[0-9]{2}-[0-9]{2}-[0-9]{2}` (via a
new `contains_regex` helper, `grep -qE`) rather than the literal
word `farewell` from the test-spec title. Helpers are extracted
to a new `tests/e2e/lib.sh` that both `run.sh` and a new fixture
(`tests/e2e/contains_adr_assertion_test.sh`) source, so the
predicate is provably identical between production harness and
fixture.
**Why:** CI run 27276707529 on commit `ed3fe24` failed identically
across attempts 2 and 3 (attempt 1 was
`ENVIRONMENT_FAILURE: credit_exhausted`). Both failed attempts
produced model-chosen ADR titles like *"Defer stdout-capture
testing for main()"* — design-rationale phrasings that never
mention the feature. The previous green run on `9c1330d`
(27275588005) was the same flake getting lucky; plugin code was
identical between the two commits, only the model's random seed
differed. The principle generalises: agent-driven artefacts have
free-text surfaces the e2e harness cannot pin without making the
agent's prompt deterministic, which is a much larger surface to
change than the assertion. Tightening the assertion is the
correct layer of fix; CI run 27287309940 on the post-spec push
(`b535629`) is the first run in which the structural assertion
fires deterministically.
**Consequence:**
- New convention: e2e assertions verifying model-driven steps
  target structural signals (header shape, exit code, field
  presence) not content signals (specific words, titles, free-
  text choices). Codified under §Bash → "E2E assertion
  predicates: structural over content".
- New convention: shared assertion helpers used by both
  `tests/e2e/run.sh` and any sibling fixture live in
  `tests/e2e/lib.sh` (sourced, not duplicated). The "exact
  predicate" invariant — that a fixture testing the production
  harness's predicate must use the *same* helper implementation,
  not a copy — is load-bearing. Naive `source run.sh` from a
  fixture executes the entire harness; helper duplication
  invites silent drift between fixture and production. Codified
  under §Bash → "Shared assertion helpers via tests/e2e/lib.sh".
- New `contains_regex` helper (in `lib.sh`) is sibling to the
  existing `contains` (fixed-string `grep -qF`). Pick fixed-
  string vs regex explicitly at the call site rather than
  overloading `contains` with a flag.
- New `run_helper_unit_tests()` in `run.sh` is sibling to
  `run_language_fixtures()` and runs first in both the
  `--language-only` short-circuit and the full lifecycle path —
  helper regressions fail fast before the language cycles or
  `claude -p` steps run.
- Step-counter `[N/M]` in `run.sh` bumped from `/10` to `/11`
  for the lifecycle path. The plan literally specified the new
  helper-test echo as `[11/11]` placed above the existing
  `[8/10]` line; the executor's variant placement at `[8/11]`
  (first, sequential) is cosmetic-only and functionally
  equivalent.

## 2026-06-10 — Post-0012 dead-code cleanup + amendment precedent (spec 0013)

**Spec:** specs/0013-remove-dead-active-spec-null-checks/
**Decision:** Post-0012 cleanup completed: the two defensive
`ActiveSpec == "null"` reads at
`tools/internal/speccraft/root.go:45` and
`tools/cmd/speccraft-guard/main.go:353` were removed under
sibling-test pins (one classical RED→GREEN, one
assertion-pinning refactor). The `omitempty` + clear-semantics
work from spec 0012 made both clauses unreachable; this spec
flips the in-process behavior so future readers see one truth
("`null` is an ordinary string id; the cleared shape is key
absent") instead of two false-positive fallbacks. A
mid-implementation amendment (T6) added a Go setup +
helper-binary build step to the CI `hooks:` job; without it,
spec 0012's new `pre-tool-use-state-guard.bats` reject cases
were silently no-op'ing because `speccraft-state` was not on
`$PATH` in CI.
**Why:** The dead clauses themselves were harmless but corrosive
— leaving them invited future readers to invent nonexistent
semantics for the literal string `"null"`. The CI miss was the
real teaching moment: spec 0012 closed against a green
`e2e-devcontainer` run that never actually exercised the new
bats guard, because the bats job lacked the binaries the hook
depends on. CI run 27275588005 (on commit 9c1330d) is the first
run in which both spec 0012's AC5 close gate and spec 0013's
AC5 close gate were truly satisfied.
**Consequence:**
- Mid-implementation amendment precedent codified in
  `conventions.md` § Spec lifecycle. When CI surfaces a bounded
  issue between push and close that shares the active spec's
  theme and (a) is a strictly one-file edit, (b) keeps main CI
  red until it lands, and (c) does not require any AC change
  other than additive, the issue MAY be folded into the active
  spec as a new task + new AC + a dated `## Amendment` section
  in `spec.md`, rather than filed as a follow-up spec.
- Close-gate-pending workaround formalised. When a spec closes
  with a `<!-- TODO: <github-actions-run-url> -->` marker in its
  changelog (close gate not yet green at close time), and a
  subsequent spec's CI run satisfies the gate, the URL is
  recorded in the **subsequent** spec's changelog with an
  explicit cross-reference to the predecessor. The predecessor's
  TODO marker is left in place per the "No post-close edits"
  rule. A post-close backfill exception was evaluated this
  close batch and explicitly rejected in favor of strict
  immutability.
- The two defensive `== "null"` clauses flagged in 0012's ADR
  are gone. No further dead-code follow-up is queued from the
  0012 era.
- T6 reinforces an existing convention rather than creating a
  new one: the spec-0008 CI job-split convention already implies
  "build what each job needs" — the bats job was missing the
  binaries the hook depends on at runtime. No fresh CI
  convention is proposed.

## 2026-06-10 — Runtime single-writer enforcement for .speccraft/state.json (spec 0012)

**Spec:** specs/0012-clear-active-spec-correctly-on-close/
**Decision:** Single-writer rules for files speccraft owns are now enforced
at two layers — source-level grep (existing `state_single_writer_test.go`)
plus a runtime PreToolUse hook check that rejects any
`Edit`/`Write`/`MultiEdit`/`NotebookEdit` whose `file_path` canonicalises
to `<root>/.speccraft/state.json`. Source-level enforcement alone is
insufficient because a `claude -p` lifecycle session can write through a
tool call the grep test never sees. Adjacent: `State.ActiveSpec` carries
`,omitempty` so the cleared shape on disk is "key absent" rather than a
sentinel string, and a new `speccraft-state init` subcommand replaces the
old Write-the-canonical-JSON path in `commands/init.md` so the new hook
cannot break first-run `/speccraft:init`.
**Why:** Triggered by CI run 27178536892 on 2026-06-09. The
`e2e-devcontainer` job's step `[7/9] /speccraft:spec:close` failed the
assertion `jq -r '.active_spec // "null"' state.json` because a tooling
bug (`speccraft-state set active_spec null` wrote the literal string
`"null"`) induced a model workaround — a direct `Edit` of `state.json`
to clean up the artifact. The source-layer grep test caught no
source-tree regression; the violation lived in a runtime tool call.
Source + runtime enforcement together close that gap.
**Consequence:**
- New `speccraft-state init` subcommand is now the only sanctioned
  creation path for `.speccraft/state.json`. Idempotent: silently no-ops
  if the file already exists, so `/speccraft:init` re-runs cannot nuke
  session state. Both behaviors pinned by
  `tools/cmd/speccraft-state/main_test.go`.
- `hooks/pre-tool-use.sh` gates on the full set of Claude Code write
  tools via a `GATED_TOOLS` enumeration; `hooks/hooks.json` matchers
  must be extended in lockstep when a new write-tool name is added.
  Codified as a convention so the next write-tool name is a paired
  one-line change, not a hidden gap. Six new bats cases under
  `tests/hooks/pre-tool-use-state-guard.bats` cover the reject path
  for each gated tool plus an allow case for sibling memory files.
- `State.ActiveSpec` is now serialised with `,omitempty`. Two
  defensive reads for the literal `"null"` string at
  `tools/cmd/speccraft-guard/main.go:353` and
  `tools/internal/speccraft/root.go:45` became dead code; left in
  place under the TDD-hook constraint and queued for a follow-up spec.
- §What item 4's test-naming clarification landed concurrently: both
  `Test<UpperCamel>` and `Test_<Subject>_<Scenario>` are documented as
  acceptable in `.speccraft/conventions.md`. The enforce regex
  `^func Test[A-Z]` is unchanged — tightening would force a global
  rename, which is out of scope.

## 2026-06-09 — Defer code-intel routing to user globals (spec 0011)

**Spec:** specs/0011-code-intel/
**Decision:** Speccraft does not duplicate routing authority for external
code-intelligence tools it does not own. The `speccraft-context` skill,
the `init` command, and the `architecture.md` template no longer name
CodeGraphContext (or any other code-intel tool) as the way to answer
structural queries; instead they defer to whatever the user's installed
tool has registered in the environment, typically via global CLAUDE.md
or the MCP server's own instructions. One example mention of
CodeGraphContext survives in the conditional install-suggestion in
`commands/init.md`, framed as "such as CodeGraphContext" — examples
allowed, brand endorsements not.
**Why:** Triggered by a real `/speccraft:spec:new` session on 2026-06-09
where speccraft's skill ("prefer codegraph MCP tools") and the user's
global CLAUDE.md (written by `codegraphcontext mcp setup`, encoding the
heavy/lightweight tool distinction and Explore-subagent quarantine
rule) gave conflicting routing guidance for the same tool family. The
model resolved the conflict in favor of the more specific global rule,
but the conflict itself was wasted attention and would silently drift
further as cgc's rules evolved. Speccraft owns spec lifecycle, TDD
gate, and project memory — it does not own how to call other people's
MCP servers.
**Consequence:**
- New principle codified in conventions.md under "External-tool
  boundaries": when an external tool writes routing rules into the
  user's environment, speccraft defers rather than maintaining a
  parallel copy.
- Doc-only specs now have a documented oracle pattern: a committed
  `verify.sh` grep-assertion script that fails RED on current main and
  passes GREEN after the edits. Sibling to the E2E language-fixture
  pattern; codified in conventions.md.
- README.md and `speccraft-v1-spec.md` retain stale CodeGraphContext
  copy (out of scope here); follow-up cleanup pass is queued.
- `specs/0001-speccraft-v1/spec.md` also retains the original
  CodeGraphContext integration claim. Spec is closed and immutable;
  residual reference is accepted as historical record.

## 2026-06-09 — JavaScript and TypeScript support (spec 0010)
**Spec:** specs/0010-javascript-typescript-support/
**Decision:** Add JS/TS as a first-class language in `speccraft-guard` via pure file classification plus session-state sibling lookup. No Node/npm/Jest/Vitest is invoked. Test recognition uses 16 suffix variants (`.test`/`.spec` × `.js/.ts/.jsx/.tsx/.mjs/.cjs/.mts/.cts`) plus the `__tests__/` immediate-directory convention. Production recognition uses the same extension set minus declaration files and test files. Both classifiers apply a segment-exact exclusion for `node_modules` and `dist`. Before adding `jsTsDispatch`, the shared red-phase preamble in `goPythonProdGuard` was lifted into a tri-state `prodGuardPrologue` helper returning `prologueAllow` / `prologueBlock` / `prologueContinue`.
**Why:** JS/TS is the largest active language ecosystem and a foreseeable adoption blocker. Keeping the guard runtime-free preserves the "no real runner in the hook" invariant established in 0002/0005 and avoids dragging a Node toolchain into every speccraft install. Extracting the prologue first kept the new dispatcher honest about gate symmetry with Go/Python and prevented subtle drift between languages.
**Consequence:** Adding the next language (e.g., Ruby, C#) is now a smaller change: implement `<lang>Dispatch` reusing `prodGuardPrologue`, add a case in `dispatchByLanguage`, extend `IsTestFile`, ship a `tests/e2e/<lang>_cycle.sh` fixture, and bump the run.sh step counter. Four rounds of spec review were needed to reach this shape — reviewers pushed back on real-Jest invocation, runtime sibling resolution, and test/production extension asymmetry, all of which would have broken the existing language model. `--language-only` CI now runs 10 language fixtures.

## 2026-06-08 — fix override no-op (spec 0009)

**Spec:** specs/0009-override/
**Decision:** The Go/Python production-edit guard now consults a persisted, single-shot `OverridePending` flag on `Session` (in `.speccraft/state.json`). The flag is consumed atomically by a new `ConsumeOverride(root) (bool, error)` API that reads-and-clears under a single `mu.Lock()` via `loadStateLocked` / `saveStateLocked`. The flag is owned exclusively by `speccraft-state` (enforced by the single-writer grep test).
**Why:** The previous override mechanism was a no-op for the guard — toggling it had no effect on the production-edit-without-sibling-test rule, so users had no working escape hatch. The fix needed to be (a) single-shot so an override can't silently persist, (b) crash-safe so a half-applied override can't leave the repo in a permissive state, and (c) consistent with the existing single-writer invariant for state fields.
**Consequence:**
- Override is now genuinely single-shot and atomic: a single edit is allowed, the next is blocked again.
- Pattern established for "consume-on-use" state fields: lock once, load-locked, mutate, save-locked, return. Future single-shot flags should follow `ConsumeOverride` rather than the read-then-separately-write pattern.
- `commands/spec/override.md` documentation is stale (still says edit `state.json` directly) — known gap, deferred.
- The single-writer allow-list is no longer Rust-specific; any new field added to `Session` must be added to `state_single_writer_test.go`'s grep patterns.

## 2026-05-29 — CI hardening (spec 0008)

**Spec:** specs/0008-ci-hardening/
**Decision:** Split the e2e workflow into two CI jobs with different cost and credential profiles: `e2e-language-only` (cheap, hermetic, no `ANTHROPIC_API_KEY`, runs on every push and PR) executes the language-dispatch fixtures via a new `tests/e2e/run.sh --language-only` flag; `e2e-devcontainer` (expensive, requires API credits, gated to `push` on `main`) continues to run the full `claude -p`-driven lifecycle. Layer in an `ENVIRONMENT_FAILURE:` annotation model so the lifecycle job's failure logs distinguish environmental issues (credit exhaustion, auth, transient upstream) from real assertion failures. Defensive idempotent ownership fix for `~/.claude/session-env` in `.devcontainer/setup.sh`. Record the pre-close gate (first green `e2e-language-only` run on `main`) verbatim in the spec's `changelog.md` as the first concrete enforcement of the §Post-merge verification convention.
**Why:** The single-job e2e pipeline conflated three failure modes — credit exhaustion, authentication, transient API — with real code defects, and the upstream `EACCES` on `~/.claude/session-env` blocked the `/speccraft:spec:review` step entirely. The combined effect: spec 0005's Rust fixtures and spec 0007's Python fixture, both wired into `run.sh`, had never actually run green in CI. Splitting cheap signals from expensive ones gives PR signal on language dispatch without burning API credits; the `ENVIRONMENT_FAILURE:` tag makes log triage cheap; the pre-close gate prevents closing on optimism.
**Consequence:**
- Future expensive e2e steps (anything calling `claude -p`) belong in the lifecycle job; future cheap dispatch-style e2e belongs in `e2e-language-only` via `run_language_fixtures()`. New `<lang>_cycle.sh` fixtures get picked up automatically when added to that helper. Codified in `.speccraft/conventions.md`.
- The `ENVIRONMENT_FAILURE:` annotation is now the canonical pattern for environmental-failure observability. Categories are `credit_exhausted`, `auth`, `transient_api`; ordering is credit → auth → transient. Exit code stays non-zero. Future env failure modes extend this list, not create parallel mechanisms.
- The §Post-merge verification "pre-close gate" convention now has its first concrete enforcement in the codebase. Spec 0007's deferred T10 was retroactively satisfied by the first green `e2e-language-only` run (https://github.com/DCSTOLF/speccraft/actions/runs/26658905606) without editing spec 0007's files — the closed-spec-immutability rule held.
- Integration surfaced a latent mock-stdin bug: `claude -p`-launched subagent CLIs never EOF child stdin, so mocks doing `INPUT="$(cat)"` block forever. The fix — `exec </dev/null` at the top of every mock aux-agent script — is now a convention for any future mock CLI invoked through the aux-delegator path.
- AC #1's exact CI-side root cause was not reproduced locally; the defensive idempotent ownership fix in `.devcontainer/setup.sh` covers both the named-volume-on-first-create race and any base-image ownership oddity. Recorded in 0008's changelog.

## 2026-05-29 — Python e2e fixture (spec 0007)

**Spec:** specs/0007-python-e2e-fixture/
**Decision:** Add an end-to-end fixture for Python (`tests/e2e/python_cycle.sh`) modeled structurally on `rust_inline_cycle.sh` and wire it into `tests/e2e/run.sh` as step `[9/9]`. The fixture exercises the sibling-test resolver (spec 0002) and the separate-tree resolver (spec 0003) through the full PreToolUse hook flow, asserting both rejection messages and acceptance-after-`track-edit`. No Go code changed.
**Why:** Until this spec, Python TDD support had unit coverage in `tools/internal/speccraft/files_test.go` but no end-to-end test that drove `speccraft-guard` against a real Python project layout. The asymmetry surfaced during spec 0005's CI hardening when wiring the Rust e2e step into `run.sh` — Go has e2e via the throwaway Go module in step 1, Rust now has it in step 8, and Python had none. This spec is the smallest possible follow-up that restores parity across all three supported languages.
**Consequence:**
- Every supported language (Go, Python, Rust) now has an end-to-end fixture in `tests/e2e/`. Future language additions are expected to ship with their own `<lang>_cycle.sh` modeled on the same template (codified in `.speccraft/conventions.md`).
- The fixture surfaced a real subtle bug in the spec body: AC #3 originally colocated `bar.py` with the AC #2 sibling pair, but tier-1 of `SiblingTestFiles` is a directory glob and would have hidden the tier-2 behavior. Implementation moved `bar.py` to `src/pkg/` and `orphan.py` to `src/loners/`. Documented in the spec's changelog as a deviation. Reinforces the convention that each AC scenario in a multi-scenario fixture should isolate its directory layout.
- Planning was performed with `/speccraft:spec:plan --skip-review` against a `status: draft` spec at user direction. Cross-model review was bypassed; spec+plan are a paired artifact for PR review. Future reviewers should be aware when reading 0007 that the normal review gate did not run.
- T10 (CI green) is deferred. Two pre-existing infrastructure failures upstream of step `[9/9]` (devcontainer `EACCES` on `~/.claude/session-env` during `/speccraft:spec:review`; `"Credit balance is too low"` during `/speccraft:spec:plan`) prevent the new step from being reached in CI. A follow-up spec (`0008`, CI hardening) will be filed immediately after this closure to fix the upstream issues and retroactively verify T10.

## 2026-05-29 — Rust language support (spec 0005)

**Spec:** specs/0005-rust-language-support/
**Decision:** Add Rust as a first-class supported language with three architectural extensions: (1) a new shared **test-runner invocation primitive** in `tools/internal/speccraft/runner/` (language-neutral interface, per-language adapters); (2) a **dispatch-by-language pattern** in `speccraft-guard` (`dispatchByLanguage` + `rustDispatch`, preserving the existing Go/Python codepath unchanged); (3) a **`reserves-specs` spec-frontmatter field** for forward-referencing follow-up specs by stable ID before they exist on disk.
**Why:** Rust's idiomatic unit tests live inline inside `#[cfg(test)] mod tests` blocks within the same `.rs` file as the production code under test. Sibling-edit detection (the basis for Go and Python support) cannot distinguish "added a test" from "edited prod" within a single file edit. The runner becomes the authoritative oracle for "did the just-added test actually fail?", while a delta-based static classifier handles "did this edit add a test?" — making the system sound even with the inline-tests model. The dispatch-by-language pattern keeps the new wiring isolated from the proven Go/Python paths. The `reserves-specs` field lets AC #5's workspace-detection error name spec `0006` by stable ID before `0006` exists.
**Consequence:**
- `tools/internal/speccraft/runner/` is now shared infrastructure intended for future per-language adapters; the interface has been validated against Rust only. Retroactive adoption by Go/Python is **explicitly a non-goal** and is deferred to a separate spec if ever pursued.
- Adding a new language to `speccraft-guard` is now a localized change: implement a `<lang>Dispatch` function and add a case to `dispatchByLanguage`. The previous open-coded switch is gone.
- The `reserves-specs` field is documented in `.speccraft/conventions.md` as advisory — `/speccraft:spec:new` does not yet implement reservation-aware ID allocation. Tooling support is deferred.
- `.speccraft/state.json` gains `rust_test_baseline` (list) and `rust_gate_fingerprint` (string). The single-writer rule for state.json is extended to cover both, asserted by a grep-based regression test.
- Cargo workspaces are explicitly unsupported in this release; spec id `0006` is reserved for the follow-up.

## 2026-05-22 — Slash-command names fully qualified to `/speccraft:spec:*`

**Spec:** none (maintenance; commits 697c868, 5041bc6, a4ff4db)
**Decision:** Migrate all slash commands from bare names (`/spec:new`) to the fully qualified plugin form (`/speccraft:spec:new`) in README, e2e tests, and every command file's "next steps" hints.
**Why:** Bare names collide with host-repo commands once the plugin is installed via marketplace. Fully qualified names are unambiguous and match Claude Code's plugin command namespacing.
**Consequence:** All user-facing documentation, e2e assertions, and inter-command references must use the qualified form. Any new command added under `commands/spec/` is invoked as `/speccraft:spec:<name>`.

## 2026-05-15 — Python TDD support (specs 0002, 0003)

**Spec:** specs/0002-python-tdd-support/, specs/0003-python-separate-test-roots/
**Decision:** Extend `speccraft-guard`'s red→green detection to Python projects via a `speccraft.toml` config that declares language, test command, and test-file discovery strategy (sibling vs separate tree).
**Why:** First non-Go host-repo adopter needed pytest-driven TDD enforcement without forking the guard binary.
**Consequence:** Guard logic is now language-pluggable through config rather than hard-coded. Future languages add a config recipe, not a new binary. Spec immutability rule still applies: 0002 and 0003 are closed.

## 2026-05-10 — Plugin packaged via `dcstolf-tools` marketplace

**Spec:** none (packaging work, pre-0001 closure; commit 6950511)
**Decision:** Ship speccraft as a single-plugin entry inside the `dcstolf-tools` Claude Code marketplace (`.claude-plugin/plugin.json` + root `marketplace.json`).
**Why:** Distribution channel for Claude Code plugins; lets users install with one command and pins versioning.
**Consequence:** The plugin's install path is now load-bearing — do not introduce a second entrypoint. `marketplace.json` schema must validate against the upstream JSON Schema.

## 2026-05-28 — speccraft adopted

**Spec:** specs/0001-speccraft-v1/
**Decision:** Adopt speccraft for spec-first TDD workflow.
**Why:** Establish disciplined spec-first development from day one.
**Consequence:** All future code changes go through `/speccraft:spec:new`.
