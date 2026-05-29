---
spec: "0005"
reviewers: [codex, claude-p, opencode]
quorum: 1
verdict: approve-with-comments
generated: 2026-05-28T00:00:00Z
round: 3
supersedes: "round-2 review (2026-05-28) and round-1 review (2026-05-28)"
---

# Cross-model review — 0005 (Round 3)

This review supersedes the round-1 and round-2 results. The spec underwent a substantive rewrite after round 2. Two real agents ran in parallel: `codex-cli 0.135.0` (gpt-5.5) and claude-p. `opencode` remains a stub and was excluded.

## Reviewer availability

| Agent | Status | Model | Counted toward quorum |
|-------|--------|-------|-----------------------|
| codex | Real review — `changes-requested` | gpt-5.5 via codex-cli 0.135.0 | Yes |
| claude-p | Real review — `approve-with-comments` | claude-p | Yes |
| opencode | Unavailable — stub binary exits 1; not replaced | — | No |

## codex

**Verdict:** changes-requested

Concerns:

- AC #7's template guardrail collision is resolved: README-only documentation plus an explicit `templates/speccraft/**` is-not-modified constraint satisfies the stack-agnostic template rule.
- AC #2 is more concrete but has a residual spec/implementation mismatch: §What.2 says a preceding attribute list may contain `#[cfg(test)]`, while the same bullet says the regex matches `cfg` immediately followed by `mod`. Whether intervening attributes such as `#[allow(...)]` are accepted is left undefined.
- AC #4's runner outcome enum is directionally sufficient, but the just-added set in AC #8 is defined as test function names while runner output commonly returns fully qualified Rust test names. The spec must define normalization so static discovery and runner records compare the same identifiers.
- The 0006 reservation is a satisfactory replacement for the forward reference: the spec reserves the ID in frontmatter and requires the workspace error to reference the reserved ID and title.
- AC #10 introduces a likely guardrail conflict: it says touched-file content hashes are tracked via speccraft-state/current session state but does not specify whether this is in `.speccraft/state.json`. If so, transient hook-cache writes would expand persistent single-writer state and may create noisy state churn.
- AC #4 requires automated tests for both cargo and cargo-nextest modes, while AC #9 only requires rustc/cargo in CI/devcontainer. The spec does not say how nextest is made available, skipped, or stubbed, so CI acceptance is under-specified.
- The remaining open question about default runner selection is not fully late-bindable: the config schema, validation rules, CI setup, and AC #4's nextest coverage all depend on the accepted runner values and selection behavior.

Suggestions:

- Define a canonical Rust test ID format (e.g., fully qualified libtest names) and require AC #8's just-added baseline to store that same normalized form.
- Tighten the inline-test regex contract with explicit accepted/rejected examples, especially for multiple attributes, visibility modifiers, and whitespace/newlines.
- Move the content-hash cache for AC #10 into an explicitly transient session store, or specify the exact speccraft-state API and `state.json` field if persistence is intentional.
- Resolve runner selection now: declare allowed values (e.g., `cargo` and `nextest`), default `cargo`, explicit opt-in only, and validation behavior for unknown values.
- For nextest tests, either require CI/devcontainer installation of `cargo-nextest` or state that adapter tests use a fake runner/output fixture rather than invoking the real binary.

Guardrail violations:

- **Rule:** speccraft-state is the only writer of `.speccraft/state.json`
  **Location:** AC #10 / §What.4, if the touched-file hash cache is persisted in `.speccraft/state.json` without an explicit speccraft-state-owned field/API

Convention violations:

- **Rule:** Specifications should be concrete enough that acceptance criteria do not depend on unresolved choices
  **Location:** Open questions / AC #4 / AC #9: runner selection and nextest availability remain unresolved while acceptance criteria require nextest behavior

## claude-p

**Verdict:** approve-with-comments

Concerns:

- AC #10's wall-clock assertion (`microbenchmark or timing test`, <100ms target) is fragile in CI — shared runners produce noisy timing and a hard 100ms threshold will flake. The behavioral property the spec actually wants is "cache hit path spawns zero `cargo` subprocesses", not a latency number.
- The normalized runner record shape `{test_name, status, scope}` is introduced in the Why section and §What.3, and is load-bearing for AC #4, but `scope` is never defined. Two implementers will pick different meanings (module path? crate? file path? test target — bin/lib/integration?), and AC #4's tests would still pass under either reading.
- AC #10's cache key (per-file content hash) is narrower than the cargo invocation it gates (whole-crate `cargo check --tests`). If file A is unchanged since its last successful gate but file B has since been edited with a compile error, the next pre-edit gate on A short-circuits to no-op and misses B's breakage. Soundness of the cache vs. the scope of the underlying tool needs explicit reconciliation.
- AC #2's regex specification (`#[cfg(test)]` immediately followed by `mod <ident> {` at the same indentation) excludes the common multi-attribute pattern (`#[cfg(test)] / #[allow(dead_code)] / mod tests { ... }`). The runner-as-oracle clause makes this recoverable, but the false-negative class should be named explicitly so the test fixture in AC #2 does not accidentally codify the narrower form.
- `reserves-specs: ["0006"]` in the frontmatter is a new field with no precedent in `.speccraft/conventions.md` or the spec-format skill. It is sensible, but either spec-format should be extended to document it, or AC #5's `stderr-contains-'0006'` test risks being the only enforcement of an undocumented convention.

Suggestions:

- Rewrite AC #10's assertion as a behavioral one: "on a cache hit, the guard invokes zero `cargo`/`rustc` subprocesses (asserted by a fake `cargo` shim on PATH that records invocations)." Drop the <100ms timing target from the AC or move it to a separate perf-tracking job outside CI gating.
- Add one sentence to §What.3 defining `scope` — e.g., "scope is the test's containing module path (`crate::foo::tests` for inline tests, `tests::<file-stem>` for integration tests), used by AC #8 to compute set-difference against the baseline."
- Tighten AC #10's cache key to "the touched file's content hash AND no other `.rs` file or `Cargo.toml` in the crate has changed since the last successful gate run in this session" — or explicitly accept the narrower per-file cache with a note that cross-file invalidation is deferred to the cache-miss path.
- Loosen AC #2's regex prose to allow intervening attribute items between `#[cfg(test)]` and the `mod` item, and add one more fixture case (multi-attribute mod) to the AC #2 test list.
- Acknowledge `cargo test`'s libtest text format as a de facto stable interface (not contractually stable); recommend nextest mode as the preferred CI path as a known-risk note.
- Promote §What.7's resolution from a buried sub-paragraph into the spec body as a named limitation: "no cross-file unlock from a sibling `src/foo_tests.rs` to `src/foo.rs` — the only cross-file unlock for Rust is `tests/<stem>.rs` → `src/<stem>.rs`." This is the right call but deserves visibility.
- Either pre-register `reserves-specs` in the spec-format skill before merge, or add a one-line note in this spec explaining the new frontmatter field so future readers do not treat it as a typo.

Guardrail violations: none

Convention violations: none

## opencode

**Status:** Unavailable. The `opencode` stub binary exits 1 with no output. Not replaced between rounds. No review produced.

## Synthesis

### Aggregate verdict

**Quorum is MET.** claude-p returned `approve-with-comments`, which satisfies the `review_quorum = 1` threshold in `.speccraft/agents.toml`. The spec moves to `status: reviewed`.

The two real reviewers diverged: codex returned `changes-requested`; claude-p returned `approve-with-comments`. Both agents agree that the round-2 blockers were resolved in the rewrite. They disagree on whether the new round-3 concerns are non-blocking comments (claude-p) or fresh blockers (codex). Under the quorum rule, approval-quorum is met; the user may address codex's concerns inline before `/speccraft:spec:plan` (Path A) or carry them as plan-time TODOs (Path B). Both paths are valid. Path A is recommended.

---

### Round-2 disposition

Using claude-p's assessment as the basis, supplemented by codex's confirmations:

| Prior round-2 blocker | Round-3 status |
|-----------------------|----------------|
| AC #7 template guardrail violation | Fully resolved (codex confirmed; README-only path adopted) |
| AC #2 detection algorithm undefined | Partially resolved — regex approach specified, but multi-attribute case still ambiguous (both reviewers) |
| AC #4 "just-added test" undefined | Partially resolved — runner-record shape added, but `scope` field undefined and identifier normalization unspecified (both reviewers) |
| AC #4 brittle output matching | Directionally resolved (outcome enum added); normalization gap remains (codex) |
| AC #5 forward reference to nonexistent spec | Fully resolved (`reserves-specs: ["0006"]` in frontmatter; codex confirmed) |
| Config schema open question | Fully resolved |
| Inline-only-file edge case | Design resolved (§What.7 commits to integration-test-only cross-file unlock); visibility is low (claude-p suggests promotion) |
| AC #3 lib.rs factual error | Fully resolved |
| Pre-edit gate latency | Fully resolved — AC #10 adds caching strategy |
| CI/devcontainer Rust toolchain | Fully resolved — AC #9 added |

Summary: 7 fully resolved, 2 partially resolved with new narrower issues (AC #2 multi-attribute and AC #4 scope/normalization), 1 design-resolved-but-needs-visibility (§What.7).

---

### Convergent round-3 concerns — both reviewers flagged

These are the highest-priority items to address before `/speccraft:spec:plan`.

**1. `scope` field undefined in runner record shape**

Both codex (concern #3) and claude-p (concern #2) flagged this independently. The `{test_name, status, scope}` record shape is introduced in the Why section and §What.3 and is load-bearing for AC #4. `scope` is never defined. Two implementers reading the spec will choose different representations — module path, crate name, file path, or test target — and AC #4's tests would pass under any of them. This is the highest-priority new concern in round 3.

**2. AC #2 regex excludes the multi-attribute case**

Both codex (concern #2) and claude-p (concern #4) flagged this. The regex specification as written matches `#[cfg(test)]` immediately followed by `mod`, excluding the common pattern where an intervening attribute such as `#[allow(dead_code)]` appears between `#[cfg(test)]` and the `mod` item. The runner-as-oracle clause provides a recovery path, but the false-negative class should be named explicitly and the AC #2 test fixture should include a multi-attribute case to avoid accidentally codifying the narrower form.

**3. Open question on runner selection should be closed**

Codex raised this explicitly (concern #7); claude-p's remarks on nextest availability reflect the same gap. The allowed runner values, the default, opt-in semantics, and validation behavior for unknown values are all unresolved, yet they feed the config schema, validation rules, CI matrix, and AC #4's nextest coverage requirement. This cannot be fully deferred to plan time without leaving AC #4 and AC #9 in conflict.

---

### Codex-only round-3 concerns — worth addressing

**Identifier normalization for AC #8 and AC #4 (codex concern #3 expanded)**

AC #8 defines the just-added baseline as "test function names" while runner output returns fully qualified libtest names (e.g., `module::submodule::test_fn`). Without a canonical form, the set-difference computation in AC #8 is undefined. The spec should pick one representation — fully qualified libtest path is the natural choice — and require both the static discovery baseline and the runner records to use it.

**Nextest CI availability (codex concern #6)**

AC #4 requires automated tests for both `cargo test` and `cargo nextest run` adapter modes. AC #9 only provisions `rustc`/`cargo` in CI/devcontainer. The spec does not say how nextest is made available, conditionally skipped, or stubbed. Either `cargo-nextest` should be added to the CI/devcontainer provisioning requirement in AC #9, or AC #4 should split its nextest coverage into adapter-fixture tests (using a fake runner/output fixture, no real binary) and real-runner e2e (cargo only).

**AC #10 cache storage and the single-writer guardrail (codex concern #5)**

AC #10 says touched-file content hashes are tracked via speccraft-state/current session state but does not specify whether this is persisted in `.speccraft/state.json`. If it is, the existing single-writer guardrail requires all writes to go through the `speccraft-state` binary. The spec should either name the speccraft-state API field for this cache entry or explicitly designate it as transient (in-process/session-only), which would exempt it from the state.json guardrail.

---

### Claude-p-only round-3 concerns — worth addressing

**AC #10 timing assertion is the wrong shape (claude-p concern #1)**

Wall-clock `<100ms` assertions are flaky in CI on shared runners. The behavioral property the spec actually wants is "cache hit path spawns zero `cargo` subprocesses", which is deterministic and assertable with a fake `cargo` shim on PATH. Claude-p's recommendation is strong: drop the `<100ms` threshold from the AC or move it to a non-gating perf-tracking job, and replace it with the subprocess-count assertion.

**AC #10 cache soundness (claude-p concern #3)**

The per-file content hash cache is narrower than the `cargo check --tests` invocation it gates. If file A is unchanged but file B has since introduced a compile error, a cache hit on A will short-circuit and miss B's breakage. The spec should either tighten the cache key (content hash of touched file plus no other `.rs` file or `Cargo.toml` in the crate has changed since the last successful gate run in this session) or explicitly accept the narrower per-file cache with a stated note that cross-file invalidation is deferred to the cache-miss path.

**`reserves-specs` is an undocumented frontmatter convention (claude-p concern #5)**

The `reserves-specs: ["0006"]` field has no precedent in `.speccraft/conventions.md` or the spec-format skill. It is a clean solution to the forward-reference problem, but without documentation, it risks being treated as a typo by future readers and tools. Either pre-register the field in the spec-format skill before merge, or add a one-line explanatory note in this spec.

**§What.7 deserves promotion to a named limitation (claude-p suggestion #6)**

The inline-tests-only-file resolution — no cross-file unlock from `src/foo_tests.rs` to `src/foo.rs`; the only cross-file unlock for Rust is `tests/<stem>.rs` → `src/<stem>.rs` — is the correct design decision but is currently buried in a sub-paragraph. Claude-p recommends promoting it to a named limitation note in the spec body for visibility, so it is not accidentally undone during implementation.

**Forward-compatibility language should be softened (claude-p discussion)**

The spec claims Go/Python can plug in "without changing the core." This claim has not been pressure-tested against Go's package-level discovery model (`go test ./...`) or Python's name-pattern model (`pytest -k`), which differ structurally from Rust's function-level inline test model. Claude-p recommends softening the language to "with the intent of supporting later adapters" rather than asserting compatibility as a fact.

---

### What is strong — preserve

Both reviewers agree that the round-2 blockers are convincingly cleared. The following elements should not be disturbed in any further revision:

- **Runner-primitive interface direction.** Both reviewers agree the `{test_name, status, scope}` normalized record and the language-adapter pattern are sound. The concern is only that `scope` is undefined, not that the shape is wrong.
- **Out-of-scope discipline.** The out-of-scope section grew from 4 to 7 items with explicit rationale. This is a model of scope discipline.
- **`reserves-specs` frontmatter field.** Despite being undocumented, this is a clean, testable solution to the AC #5 forward-reference problem. The concern is only documentation, not the approach.
- **AC #10 caching strategy.** Introducing a content-hash cache for the pre-edit gate is the right answer to the latency concern raised in round 2. The concerns about its shape (timing assertion, soundness, storage) are refinements, not rejections.
- **AC #9 CI/devcontainer provisioning.** Explicit CI toolchain requirements are good practice and address a round-2 gap.

---

### Recommended next actions

**Path A (recommended): fix the convergent concerns inline, then `/speccraft:spec:plan`**

Three targeted fixes will resolve the two highest-confidence ambiguity sources and address codex's primary concern, effectively turning codex's `changes-requested` into an approve at plan time:

1. **Define `scope` in §What.3.** One sentence: e.g., "scope is the test's containing module path (`crate::foo::tests` for inline tests, `tests::<file-stem>` for integration tests), used by AC #8 to compute set-difference against the baseline."

2. **Loosen AC #2's regex prose and add a multi-attribute fixture case.** Allow intervening attribute items between `#[cfg(test)]` and the `mod` item. Add one fixture: `#[cfg(test)] / #[allow(dead_code)] / mod tests { ... }` to the AC #2 test list.

3. **Define canonical Rust test ID format and apply it consistently.** Pick fully qualified libtest path as the canonical form. Require both the static discovery baseline (AC #8) and runner output records (AC #4) to use it. One paragraph in §What.3 and one sentence in AC #8 are sufficient.

Additionally recommended before plan (lower urgency but clean):

- Rewrite AC #10's timing assertion as a behavioral subprocess-count assertion (claude-p concern #1).
- Resolve runner selection: declare allowed values, default `cargo`, explicit opt-in for nextest, validation for unknown values (codex concern #7).
- Specify how nextest is made available or stub-able for AC #4's nextest tests (codex concern #6).
- Add a one-line note on `reserves-specs` in the spec or the spec-format skill (claude-p concern #5).
- Promote §What.7 to a named limitation note (claude-p suggestion).

**Path B: proceed to `/speccraft:spec:plan` now, carry concerns as plan TODOs**

Quorum is met and the spec is `status: reviewed`. The planner subagent can receive codex's concerns as explicit plan TODOs. The scope/normalization gaps are narrow enough that a careful planner can surface them as design decisions in the plan. Higher carry cost; lower up-front churn. Acceptable if the author prefers to work at plan granularity.

---

### Operational note

`opencode` remains a stub. If three-way quorum is desired going forward, install a real `opencode` binary or substitute another model in `.speccraft/agents.toml`. The current codex + claude-p pairing provides adequate cross-model coverage: two architecturally distinct models with independent review chains. The divergent verdicts in this round are a feature, not a failure — they distinguish between blocking and non-blocking concerns in a way that a single reviewer cannot.

**Action (Path A):** Fix `scope` definition, AC #2 multi-attribute regex, and canonical test ID format inline. Then run `/speccraft:spec:plan 0005`.

**Action (Path B):** Run `/speccraft:spec:plan 0005` now. Surface codex's round-3 concerns as plan-time design decisions.
