---
spec: "0014"
reviewers: [codex, claude-p]
quorum: 1
verdict: approve-with-comments
generated: 2026-06-10T00:00:00Z
note: "re-review pass — verdict flipped from changes-requested to approve-with-comments"
---

# Cross-model review — 0014 (re-review)

> **Note:** This is the second-pass review. The prior `changes-requested` verdict (same
> file, now overwritten) identified three blockers: AC1's self-contradictory grep oracle,
> the underspecified `## 20` match predicate, and AC2's unresolved helper shape and
> fixture location. All three blockers are resolved in the revised spec. Both reviewers
> flipped to `approve-with-comments`. Quorum (1) is met.

---

## codex

**Verdict:** approve-with-comments

Concerns: none blocking. All three prior blockers resolved.

Suggestions (non-blocking):
- Tighten AC2 sourcing: the fixture should either source only side-effect-free helpers
  from `run.sh`, or duplicate the definitions explicitly. Sourcing `run.sh` directly is
  only safe if `run.sh` is guarded (e.g. `[[ "${BASH_SOURCE[0]}" == "$0" ]]`) against
  executing the harness when sourced.
- Optionally extend the regex to match more of the ADR format — e.g. require at least
  the date + the ` — ` separator or `(spec NNNN)` suffix. The current anchored
  date-prefix is acceptable as-is.
- Soften the §What claim that the regex is "immune to any other in-body content of any
  ADR ever written" — a level-2 dated heading (`## 2026-06-10 …`) written inside an ADR
  body would still match in theory.

Guardrail violations: none

Convention violations: none

---

## claude-p

**Verdict:** approve-with-comments

Concerns:
- AC2's wording "sources from `run.sh` (or re-uses them via the same definitions)" leaves
  a load-bearing implementation choice to the planner. `tests/e2e/run.sh` executes at
  body level, so a naive `source run.sh` runs the entire harness. The three sub-options
  are: (a) extract `contains` / `contains_regex` to `tests/e2e/lib.sh` and have both
  `run.sh` and the fixture source it; (b) guard `run.sh` with a
  `[[ "${BASH_SOURCE[0]}" == "$0" ]]` sentinel; (c) duplicate the helper definitions in
  the fixture and accept the maintenance-drift risk. Given that the spec's own stated
  failure mode is fixture-and-production diverging silently, leaving the mechanism
  unresolved is a meaningful gap — close to a blocker on its own framing, though not
  strictly blocking given both options (a) and (b) are unambiguously safe.
- AC2 wires the helper test into `run_language_fixtures()`. That function name implies
  language-cycle fixtures; a shell-helper assertion test is not a language fixture. This
  works mechanically but the name no longer accurately describes what it runs.

Suggestions:
- Tighten the AC1 check for presence of the new assertion line: use `grep -nF` with
  the exact literal string rather than `grep -n` with escaped BRE specials
  (`\^`, `\[`, `\]`). The pattern is a fixed string at the call site; escaped BRE
  specials are brittle across `grep` implementations and on some hosts will fail to
  match at all.
- Decide in §What item 1 how helpers are shared with the fixture: prefer option (a),
  extracting `contains` and `contains_regex` into `tests/e2e/lib.sh` and having both
  `run.sh` and the fixture source it. This is the cleanest answer and a small change
  that eliminates the drift risk the spec itself flags.
- Consider renaming `run_language_fixtures()` or introducing a sibling
  `run_helper_unit_tests()` called from the same CI job. Optional — can be a follow-up
  via memory-keeper at close time rather than a blocker.
- AC4's GREEN log-line description ("whichever pass-line wording the post-edit
  `contains_regex` helper uses") could be pinned more precisely once AC2 pins the helper
  shape.

Guardrail violations: none

Convention violations: none

---

## Synthesis

### Where both reviewers agree (stronger signal)

**All three prior blockers are resolved.** The revised spec now carries the anchored
date-prefix regex `^## 20[0-9]{2}-[0-9]{2}-[0-9]{2}` throughout, AC1 is rewritten as
two scoped paired checks (presence of new line + absence of old line) that no longer
conflict with surviving `farewell` references in the `/spec:new` prompt text, AC2 is
pinned to `tests/e2e/contains_adr_assertion_test.sh` with explicit positive/negative
synthetic cases, a sibling `contains_regex` helper is mandated (option B, the cleaner
separation), and the RED-baseline oracle is now AC3. Both reviewers confirm no
guardrail or convention violations remain.

**AC2 sourcing mechanism is the strongest remaining concern.** Both reviewers
independently flag that "sources from `run.sh` (or re-uses them via the same
definitions)" is under-resolved given `run.sh` executes at body level on plain
`source`. Both identify the same three sub-options; both prefer option (a) — extract to
`tests/e2e/lib.sh` — as the cleanest answer. This is the only item both reviewers
raised, making it the strongest signal in this pass.

### Where reviewers diverge (weaker signal, one reviewer only)

- **claude-p only:** AC1's presence-check uses escaped BRE specials in `grep -n`; this
  should be `grep -nF` with the literal string. codex did not flag.
- **claude-p only:** `run_language_fixtures()` is a naming stretch when it runs a
  non-language helper test. codex did not flag.
- **claude-p only:** AC4's GREEN log-line wording could be pinned more precisely once
  the helper shape is final. codex did not flag.
- **codex only:** The regex could optionally be extended to require the ` — ` separator
  or `(spec NNNN)` suffix. claude-p did not flag.
- **codex only:** The §What prose claim of immunity to "any other in-body content of any
  ADR ever written" is slightly overstated. claude-p did not flag.

### No guardrail or convention violations remain

The prior `changes-requested` verdict included a codex-classified convention violation
(AC1 was mechanically unverifiable because its oracle conflicted with intentional
surviving content). That violation is resolved. Neither reviewer identifies any
guardrail or convention violation in the revised spec.

---

**Action (priority order):**

1. **Must-fix before `/spec:plan`** — Resolve the AC2 sourcing mechanism explicitly in
   the spec. The recommended path (agreed by both reviewers) is to extract `contains`
   and `contains_regex` into `tests/e2e/lib.sh` and have both `run.sh` and
   `contains_adr_assertion_test.sh` source that file. Document this choice in §What
   item 1 so the planner has a deterministic instruction and the fixture is guaranteed
   to exercise the identical predicate as the production harness.

2. **Should-fix** — Replace the `grep -n` with escaped BRE specials in AC1's
   presence-check with `grep -nF` and the exact literal string. Escaped BRE metacharacters
   (`\^`, `\[`, `\]`) are not portable across `grep` implementations and may silently
   fail to match on some hosts.

3. **Should-fix** — Rename `run_language_fixtures()` or introduce a sibling
   `run_helper_unit_tests()` so the function name accurately describes what it invokes.
   Can be a separate small edit or addressed in the plan step; document the intent here.

4. **Nice-to-have** — Pin AC4's GREEN log-line description once the helper shape is
   confirmed in item 1 above.

5. **Nice-to-have** — Optionally extend the regex to require the ` — ` separator or
   `(spec NNNN)` suffix for a tighter structural match, and soften the §What prose
   claim of full immunity to any in-body ADR content.

The spec is ready to advance to `reviewed` status and then to `/spec:plan` once item 1
is applied. Items 2 and 3 are small textual changes that can be made in the same edit.
