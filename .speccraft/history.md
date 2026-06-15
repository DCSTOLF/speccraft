# History

Append-only. Newest first.

## 2026-06-15 — Bump version to 1.1.0 across all live surfaces (spec 0019)

**Spec:** specs/0019-bump-version-to-1-1-0/
**Decision:** Bump 1.0.0 → 1.1.0 on every live version surface in one coherent release cut:
the two packaging manifests (`.claude-plugin/plugin.json`, `marketplace.json`) and the three
binary `const version` declarations (speccraft-state/guard/drift). The hardcoded `const version`
mechanism is unchanged — only its value. Each const bump was gated by a real RED→GREEN version
test (the test asserts the NEW value, so it fails before the edit), and manifests were verified
by a grep oracle (positive 1.1.0 matches plus a negative check for stray 1.0.0), since manifests
aren't assertable from `package main`. Planned with `--skip-review`.
**Why:** Feature work had accumulated past 1.0.0 (latest = spec 0018) while every `--version`
surface still reported 1.0.0. A single coordinated bump keeps the manifests and binaries telling
one story for the next release.
**Consequence:** `--version` parity across the three binaries is now pinned by tests — a regression
on any one binary's reported version fails CI. The drift binary gained its first test file as a
result. Build-time `-ldflags` version injection (P2-5, deferred from the spec 0018 technical
review) remains a follow-up; until then version is a hand-edited const and future bumps must touch
all five surfaces.

## 2026-06-13 — Real red→green TDD check for Go/Python/JS-TS; runner primitive generalized beyond Rust (spec 0018)

**Spec:** specs/0018-technical-review/
**Decision:** Close technical-review finding P0-1: the marketed "red→green invariant" was a
true observed-failure check only for Rust, while Go/Python/JS-TS merely verified that *a*
sibling test file was *touched* this session (`hasSiblingTestEdited`, `main.go:390`; the
JS/TS session-membership loop, `main.go:446-452`). A blank line in any matching test file
unlocked every production file in its directory. Spec 0018 makes all four languages run the
session's just-added sibling test through a real runner and require an observed failure. The
spec-0005 test-runner invocation primitive — explicitly scoped to Rust at the time, with
"retroactive adoption by Go/Python is a non-goal" written into `architecture.md` — was
generalized: new `GoAdapter`/`PytestAdapter`/`JSTSAdapter` (one shared JS/TS adapter, JS and
TS differing only by configured command) reuse `classifyOutcome`, and a new
`runner.AdapterForLanguage(lang, cfg) (Runner, bool)` factory resolves them. The
"which test failed" rule mirrors Rust's just-added model via a new capture mechanism:
`Session.RedCandidates map[string][]string` (JSON `red_candidates,omitempty`,
single-writer, cleared on `SessionStart`) is populated in the `IsTestFile` dispatch branch
by `captureRedCandidates`, which diffs pre-edit disk content against the `applyEdit`-modelled
post-edit content through the per-language regex extractors `GoTestIDs`/`PythonTestIDs`/`JSTSTestIDs`.
A shared `siblingRedCheck` (used by both the Go/Python guard and the JS/TS dispatcher)
unions those candidates over the resolved siblings, runs the adapter under a 30s
`context.WithTimeout`, and accepts only when a `failed` record's id is in the just-added set.
**Why:** This was the project's highest-impact correctness gap — speccraft sold one guarantee
and enforced it for one of four supported languages. The decided direction (over the
honest-rename alternative the review also offered) was to make the red→green name *true*. Two
deliberate, load-bearing divergences from the Rust reference were required. First, the empty
just-added set **blocks** for Go/Python/JS-TS (Rust *allows* on empty because its persisted
`rust_test_baseline` already attests a prior RED; these languages have no such baseline, so
allowing-on-empty would reopen P0-1 via a blank-line touch — claude-p caught that an
implementer copying Rust's `if len(justAdded)==0 { return nil }` would silently regress).
Second, an unresolved/uninvocable runner **fails closed** (BLOCK "no test runner available"),
never falling back to the touch-check, because a fallback would let an arranged-absent runner
re-open the exact bypass. The 30s deadline (AC9) closes a real hang vector: a runtime runner
called with `context.Background()` could wedge the interactive hook indefinitely; a timeout
surfaces as a Go error (the `Outcome` taxonomy does not grow) and blocks.
**Consequence:**
- New convention codified: the **capture-at-test-edit RedCandidates model** for
  runtime-runner languages that lack a persisted baseline. When a language's red-check has no
  equivalent of `rust_test_baseline`, the just-added test set is captured at *test-edit* time
  (post-edit minus pre-edit ids via a per-language extractor) into a single-writer `Session`
  map, and an empty just-added set must BLOCK, not allow.
- `architecture.md` layer-8 and §Key-decisions were rewritten in this spec to record the
  generalization and scrub the spec-0005 "non-goal" sentence at both sites (AC11). A new
  Go-test oracle `tools/internal/speccraft/docs_parity_test.go` greps `architecture.md`/
  `index.md`/`guardrails.md`/`speccraft-technical-review.md` so the parity claims cannot
  silently drift back.
- `Session` gains `red_candidates`; the single-writer grep allow-list
  (`state_single_writer_test.go`) was extended per the existing "adding a `Session` field
  requires extending the allow-list" rule.
- A documented limitation (AC13), added via the spec-0013 mid-implementation amendment
  convention (its fourth use, after 0013 T6, 0015 T18, 0017): introducing a brand-new
  production symbol whose just-added test cannot compile until the symbol exists is a build
  failure, which AC6 refuses to treat as RED — and the gated production edit is the one that
  would make it compile. The sanctioned path is a one-shot `/speccraft:spec:override`,
  identical to Rust today; `run.sh` step 9 was rewritten to test-edit → override → production
  edit. The amendment also corrected stale `/spec:override` strings to the fully-qualified
  `/speccraft:spec:override`. Deferred follow-up: an apply-edit-in-memory red-check that runs
  against the post-edit package so a new symbol's test compiles and fails at runtime,
  eliminating the override step.
- The hermetic e2e fixtures `python_cycle.sh` and `javascript_cycle.sh` were rewritten to the
  red-check model using a *configured-stub* runner (no real pytest/node), still running in
  the cheap `e2e-language-only` job with no API key.
- This closes P0-1 only. The other review findings (P0-2 fail-open on corrupt state, P1
  MultiEdit/NotebookEdit parsing, e2e-on-PR, quorum/verdict hardening, CI static analysis,
  the P2 cleanups) remain tracked for follow-up specs.
- Close gate: PR #1 merged to `main` (merge `ddc1136`, feature `8c74168`); CI green
  (`unit`/`hooks`/`e2e-language-only` on the PR), with the credit-gated `e2e-devcontainer`
  lifecycle job — which exercises AC13 at step 9 — running on push to `main`.

## 2026-06-12 — Pin the e2e harness model explicitly; Sonnet default reverted after it failed the validation gate (spec 0017)

**Spec:** specs/0017-e2e-default-model/
**Decision:** `run_claude()` in `tests/e2e/run.sh` now passes
`--model "${CLAUDE_MODEL:-claude-opus-4-8}"` as the first argument after
`-p`, so every `claude -p` lifecycle call selects an explicit, pinned
model that is overridable via the `CLAUDE_MODEL` env var. The `--help`
usage block gained an `env:` section documenting `CLAUDE_MODEL` and
`CLAUDE_BIN`, and the spec-0008 capture probe
`tests/e2e/assertions/test_run_claude_capture.sh` gained check #4 pinning
the `--model` line via `grep -qE` on the extracted `run_claude` body. The
spec was reviewed and approved with a `claude-sonnet-4-6` default (the
cost-optimization thesis); a same-cycle amendment (2026-06-12) reverted
the default to `claude-opus-4-8`. The override var, the docs, and probe
check #4 were retained — only the default string changed.
**Why:** Before this spec the harness passed no `--model`, silently
inheriting whatever the account/CLI default happened to be — a mutable,
invisible dependency for the only CI job that actually drives Claude. The
original motivation was to cut CI cost by defaulting the credit-gated
`e2e-devcontainer` lifecycle to Sonnet 4.6. Both cross-model reviewers
(codex, claude-p) returned approve-with-comments and explicitly flagged
the risk: switching the default tier changes the model under test, with no
evidence Sonnet passes the ~10-call lifecycle. claude-p named the next
`e2e-devcontainer` run as the validation gate. That gate run
[27367642623](https://github.com/DCSTOLF/speccraft/actions/runs/27367642623)
(commit `537b769`) failed at `[9/13] TDD invariant` with a genuine
assertion failure and **no** `ENVIRONMENT_FAILURE` tag: on Sonnet 4.6 the
model invoked `/speccraft:spec:override` on the GREEN step — unnecessary,
since the test was already written and the TDD guard would have allowed
the edit — then stalled without writing `farewell()`, so `contains
main.go: farewell` failed. For contrast, the prior commit `4529323`'s
Opus-default run [27348320071](https://github.com/DCSTOLF/speccraft/actions/runs/27348320071)
failed the same step only with `ENVIRONMENT_FAILURE: credit_exhausted` —
an env issue, not a defect. The Sonnet failure was a real model-behaviour
regression, so the cost-optimization thesis was abandoned and the default
reverted.
**Consequence:**
- The cost-optimization goal was **not** achieved. The durable win that
  remains: the e2e harness's model selection is now explicit and pinned in
  `run.sh` (not silently inherited from a mutable account/CLI default) and
  overridable via `CLAUDE_MODEL` — codex's stronger framing in review.
  Anyone wanting Sonnet (or any model) for a local run sets `CLAUDE_MODEL=...`.
- The mid-implementation amendment convention (spec 0013) was reused: the
  revert is a strictly bounded one-line default change plus its paired
  probe check, the spec's own validation gate kept CI red until it landed,
  and the theme is identical (this spec's subject *is* the e2e default
  model). AC1/AC3 were updated in place to name `claude-opus-4-8`; AC2/AC4
  unchanged. This is the third use of the amendment pattern after specs
  0013 (T6) and 0015 (T18).
- The Sonnet `[9/13]` failure is a concrete instance of the spec-0014
  "structural over content" lesson generalised one level: the e2e
  lifecycle's *behaviour* (not just its assertion phrasing) varies by
  model. A model-behaviour failure in the credit-gated `e2e-devcontainer`
  run — the model reaching for `/speccraft:spec:override` on a GREEN step
  — is a legitimate close/no-close signal, and the spec-0008
  `ENVIRONMENT_FAILURE:` classifier is exactly what let CI distinguish it
  from the prior commit's `credit_exhausted` env flake. No new convention
  codified; the existing 0014 and 0008 entries are canonical.
- No architecture change. `tests/e2e/run.sh` and its assertion fixtures are
  already the documented e2e surface in architecture.md §Layering item 12;
  the `--model` flag is a behavioural pin within that surface, not a new
  layer or boundary.
- Close gate: CI run
  [27386675522](https://github.com/DCSTOLF/speccraft/actions/runs/27386675522)
  on commit `a016dae` (Opus default) is fully green including
  `e2e-devcontainer`.

## 2026-06-11 — Scrub README + v1-spec CodeGraphContext routing prose (spec 0016)

**Spec:** specs/0016-scrub-readme-v1-spec-cgc-routing/
**Decision:** Doc-only scrub applying spec 0011's
"External-tool boundaries" principle to the two human-facing
prose surfaces spec 0011 explicitly deferred: `README.md`
(3 edit sites at lines 355, 365, 383) and `speccraft-v1-spec.md`
(5 edit sites at lines 33, 697, 1132, 1369, 1792). Eight
prescriptive routing phrases — "prefer X", "should install X",
"X is the recommended way" — replaced with neutral factual
descriptions and example framing ("such as CodeGraphContext").
The neutral anchors `Recommended companions` (README section
header) and `**Recommended companion:**` (v1-spec §13 bolded
label, line 1369) were preserved as the surviving discovery
prose. A new `specs/0016-scrub-readme-v1-spec-cgc-routing/verify.sh`
(108 lines, 12 labelled `grep -F` checks: 5+1 README, 5+1
v1-spec) is the AC oracle — every check is file-scoped to
`README.md` or `speccraft-v1-spec.md` by name (AC3); repo-wide
`grep -r` is forbidden because the absence-target strings
literally appear inside this spec's own `spec.md`. A defensive
paraphrase pin (check #5, `prefer CodeGraphContext for structural
queries`) is trivially green in this cycle — its job is to fail
RED if a future rewrite reintroduces a near-variant of the
banned wording.
**Why:** Spec 0011 codified the External-tool boundaries
principle in `templates/speccraft/conventions.md` and scrubbed
the three model-loaded surfaces it identified
(`skills/speccraft-context/SKILL.md`, `commands/init.md`,
`templates/speccraft/architecture.md`) but explicitly deferred
the two human-facing prose surfaces. The deferred work was
queued as a follow-up across specs 0011 → 0013 → 0014 → 0015;
this spec closes that gap before the stale prose drifts further
or new contributors absorb it as the convention. The
prescriptive prose at README:365 (`It's the recommended way to
answer`) was an exact match for the conventions.md banned
phrasing pattern — the most acute violation among the eight,
caught by claude-p in round 1 and pinned as AC1 absence check
#3. Two-round review caught real gaps round 1 missed: round 1
returned `changes-requested` from both reviewers; the author
applied five edits between rounds (AC1 expanded from 2→5 README
pins, AC2 expanded from 2→5 v1-spec pins, AC2 presence anchor
added, AC3 file-scoped grep rule added, an Out-of-scope
contradiction resolved). Round 2 both `approve-with-comments`,
quorum met. claude-p's round-2 catch — that the spec body
itself misattributed the `**Recommended companion:**` bolded
label to §20.1 when it actually lives at §13 line 1369 — was
fixed pre-commit, before flipping `status: reviewed`. The
README:544 borderline-prescriptive sentence was explicitly
disclosed in §Out-of-scope and intentionally left in place
under the AC1 narrowing — future-reader signal, not a missed
scrub.
**Consequence:**
- Spec 0011's queued "README + `speccraft-v1-spec.md`
  CodeGraphContext cleanup" follow-up is **resolved** by this
  spec. Combined with spec 0015 resolving the
  `/speccraft:spec:revise` follow-up, every queued item from
  spec 0011's §Out-of-scope is now closed except the
  closed-spec residual in `specs/0001-speccraft-v1/spec.md`,
  which spec 0011's history.md entry already accepted as
  historical record.
- The "Grep-assertion oracle for doc-only specs" convention
  from spec 0011 has now been used a second time (after spec
  0011 itself). The pattern generalised cleanly — file-scoped
  greps, labelled checks, paired absence/presence per file, a
  defensive paraphrase pin for forward-protection — without
  needing refinement. No new convention codified; the existing
  rule in `.speccraft/conventions.md` is canonical.
- The codex round-2 implementation note (label presence checks
  as explicitly as absence checks so failure messages
  distinguish over-deletion from missed scrub) was folded into
  `verify.sh` directly via labels like `[presence: README
  "Recommended companions" section header]`. Future doc-only
  specs that copy this `verify.sh` as a template will inherit
  the labelling discipline implicitly.
- No architecture change. README.md and `speccraft-v1-spec.md`
  are top-level repo prose, not part of any execution surface
  in `.speccraft/architecture.md` §Layering. The eight edits
  preserved descriptive content (factual MCP-server capability
  descriptions, factual roadmap mentions) and only removed
  prescriptive verb/phrasing — `verify.sh` checks plus the T4
  semantic-drift refactor pass guard against half-sentence
  artefacts.
- AC4 closed-spec immutability held: `git diff cf0d094..HEAD --
  specs/0001-speccraft-v1/spec.md` is empty, confirming the
  spec-immutability rule from spec 0011's close was respected.

## 2026-06-11 — /speccraft:spec:revise + commands/<group>/<name>.lib.sh colocation (spec 0015)

**Spec:** specs/0015-spec-revise-command/
**Decision:** Add `/speccraft:spec:revise` as a first-class sibling
under `commands/spec/` for pre-implementation spec revision.
Mechanism: a new `agents/spec-reviser.md` subagent
(tools `[Read, Write, Edit, Bash]` — no `Agent`, per spec 0011)
re-runs a Socratic interview against the existing spec body, while
the command body owns all command-only frontmatter mutations
(`revision:`, `status:`, `id:`, `created:`). The command's
preflight + cross-check + diff + archive logic is extracted into
**`commands/spec/revise.lib.sh`** — the first sourceable Bash
helper under `commands/spec/`, sourced both by the `.md` body at
runtime and by `tests/hooks/spec-revise-preflight.bats` at test
time. Drift items surfaced by the optional `packages[]` cross-check
are emitted by the subagent with the load-bearing `^Q-DRIFT:`
prefix anchored at column 0 — pinned in the agent prompt body so
the e2e grep is a structural anchor, not a content guess
(per spec 0014). After the agent runs, the command re-checks the
four command-owned frontmatter fields against a pre-agent snapshot
(`frontmatter_integrity_check`) and refuses the run if the agent
ignored the forbidden-edits contract. T18 mid-implementation
amendment (2026-06-11) reworded AC3/AC4 from "state.json
byte-identical" to "`active_spec` field unchanged" — the original
predicate was over-specified, since the PostToolUse hook
correctly updates `session.edited_prod_files` when the agent
issues `Edit spec.md`.
**Why:** Pre-implementation revision had been an unowned gap
since the 2026-06-09 `/speccraft:spec:new` session that
improvised the flow — the issue was deferred across specs 0011,
0013, 0014 as queued follow-up. The two existing repair paths
were inadequate: hand-editing spec.md + re-running `/spec:review`
left no audit trail, and the spec-0013 "mid-implementation
amendment" convention applies only to `in-progress` specs.
Pre-implementation revision needed the same Socratic rigor as
`/spec:new` plus a structural audit trail (revision counter,
archived `review-r<N>.md` / `plan-r<N>.md` / `tasks-r<N>.md`).
Extracting the Bash mechanism into `revise.lib.sh` was the only
test-layer choice that kept AC1/AC2/AC9/AC10 (preflight error
paths, no model in the loop) out of the credit-gated lifecycle
job — they live in bats at zero credit cost, while AC3–AC8/AC13
(agent-dependent) live in `tests/e2e/run.sh` `[5/13]`–`[7/13]`.
T18's AC3/AC4 rework was triggered by the false positive on CI
run 27314550595's first attempt (commit `0c063ed`): the byte-
compare assertion treated normal hook session-tracking as a
contract violation. The contract revise actually needs is
single-writer discipline + `active_spec` stability, not whole-file
byte equality.
**Consequence:**
- New convention codified under §Bash → "Sourceable command
  helpers: `commands/<group>/<name>.lib.sh` colocation". Helper
  Bash backing a slash command lives next to the `.md` body;
  sourced by both runtime and tests; pure functions only (no
  top-level side effects) so bats can source the file without
  triggering work. Canonical reference is
  `commands/spec/revise.lib.sh` + `tests/hooks/spec-revise-preflight.bats`.
  This pattern is sibling to the `tools/cmd/speccraft-*` Go binary
  pattern, distinct in that `.lib.sh` runs in-process inside the
  command's shell rather than as a separately invoked binary.
- §"Markdown frontmatter" contract tightened to match the
  de-facto convention already observed across the codebase:
  subagent contract is `name/description/tools/model` (6/6 files
  under `agents/` already carry `model:`); slash command contract
  is `description/argument-hint/allowed-tools` (8/8 files under
  `commands/spec/` already carry all three). The pre-tightening
  conventions.md text understated what speccraft itself had been
  shipping since spec 0005.
- §Layering bullet 3 in architecture.md updated to call out the
  new sourceable-helper colocation pattern under `commands/`.
- Spec 0011's queued `/speccraft:spec:revise` follow-up is
  resolved by this spec. The remaining queued follow-ups (README
  + `speccraft-v1-spec.md` CodeGraphContext cleanup) are carried
  forward — neither was touched here.
- Mid-implementation amendment convention (spec 0013) reused
  cleanly: T18 added a dated `## Amendment (2026-06-11)` section
  to spec.md, a T18 entry to tasks.md, and reworded AC3/AC4 in
  place. The three conditions held (bounded edit, CI-blocking,
  theme overlap). This is the second use of the pattern after
  spec 0013's own T6.
- New e2e step trio `[5/13]` / `[6/13]` / `[7/13]` introduced in
  `tests/e2e/run.sh`; downstream `[N/M]` markers renumbered to a
  unified `/13` scheme, resolving the pre-existing `[N/9]` vs
  `[N/11]` inconsistency carried over from spec 0014.
- CI close gate: run 27314550595 on commit `0c824f9` green
  across all jobs, including the new `[5-7/13]` revise lifecycle
  and the 53 new bats tests under `spec-revise-preflight.bats`.

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
