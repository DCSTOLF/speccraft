---
id: "0014"
title: "Tighten e2e history.md assertion to ADR structural match"
status: closed
created: 2026-06-10
authors: [claude]
packages: ["tests/e2e"]
related-specs: ["0008", "0012", "0013"]
---

# Spec 0014 — Tighten e2e history.md assertion to ADR structural match

## Why

CI run 27276707529 (commit `ed3fe24`) failed at step `[7/9]
/speccraft:spec:close` with:

```
FAIL: expected 'farewell' in .speccraft/history.md
```

The assertion at `tests/e2e/run.sh:278` is:

```bash
contains ".speccraft/history.md" "farewell"
```

It's checking that after the lifecycle's test spec ("Add farewell
function") closes, the throwaway repo's `.speccraft/history.md` was
updated. The mechanism is sound — `/speccraft:spec:close` invokes the
`memory-keeper` subagent, which proposes a history.md ADR; the
prompt's blanket "Approve all proposed memory updates" tells the
model to apply it.

The defect is in what the assertion looks for. It greps for the
literal word `farewell` — which is in the spec title — but
memory-keeper's ADR title is the model's free-text choice, not a
deterministic restatement of the spec title. On run 27276707529
attempts 2 and 3, the model produced an ADR titled *"Defer
stdout-capture testing for main()"* — a design-tradeoff title that
never mentions the feature. The model's own close-log spelled this
out:

> **`history.md`** — prepended ADR: *"Defer stdout-capture testing
> for main()"*.

The previous "green" run on `9c1330d` (27275588005) was effectively a
lucky outcome of the same flake — that attempt happened to produce a
feature-named title.

This is not a one-off. Three attempts on `ed3fe24` failed identically
(attempt 1 was `ENVIRONMENT_FAILURE: credit_exhausted` — environmental
per spec 0008's annotation; attempts 2 and 3 both produced
non-feature-named ADRs). The model is systematically biased toward
naming ADRs by their design rationale rather than by the feature.
Zero plugin code (`commands/`, `agents/`, `hooks/`, `tools/`,
`templates/`) changed between `9c1330d` and `ed3fe24`, so the
behavior is identical between the two commits — only the random seed
of the model's output differs.

Path 1 (re-run) is dice-rolling; path 3 (tighten memory-keeper's
prompt) is large and indirect; path 2 (tighten the assertion) is
the right fix. The e2e contract is verifying that memory-keeper's
output was applied to history.md — the deterministic signal for
that is structural (a dated ADR header), not content (a specific
word the model chose to include).

This spec is the bounded path-2 fix.

## What

Two coupled changes in `tests/e2e/run.sh`:

1. **New `contains_regex` helper, extracted to `tests/e2e/lib.sh`.**
   The existing `contains` helper is fixed-string (`grep -qF`-shaped)
   — it cannot express the anchored date-header pattern this spec
   needs. Add a sibling `contains_regex <file> <pattern>` helper that
   mirrors `contains`'s pass/fail shape but uses `grep -qE` so callers
   can pass an extended regex.

   **Both helpers move to a new `tests/e2e/lib.sh` file** that
   `run.sh` and the new fixture (AC2) source via
   `source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"`. The extraction is
   load-bearing: AC2's invariant is that the fixture exercises **the
   exact predicate** the production assertion uses, and naive
   `source tests/e2e/run.sh` from the fixture would execute the whole
   harness at body level. The two acceptable alternatives — guarding
   `run.sh` with a sentinel or duplicating helper definitions in the
   fixture with drift risk — both make the fixture/production
   divergence the spec exists to prevent more likely, not less. The
   `lib.sh` extraction picks the only option that keeps the predicate
   provably identical without restructuring `run.sh`.

   The two helpers (`contains` and `contains_regex`) are explicit at
   the call site; existing `contains` callers in `run.sh` are not
   touched in their semantics. This avoids overloading the
   fixed-string helper with a regex flag (which would change every
   existing call site's contract) and avoids inlining `grep -E`
   ad-hoc in `run.sh` (which would create asymmetry with the other
   `contains`-style assertions in the same block).

2. **Switch the brittle assertion at `tests/e2e/run.sh:278` to use
   the new helper with an anchored date-header regex:**

   ```bash
   # Current — couples to model's free-text choice of ADR title content:
   contains ".speccraft/history.md" "farewell"

   # New — matches memory-keeper's ADR header convention structurally:
   contains_regex ".speccraft/history.md" "^## 20[0-9]{2}-[0-9]{2}-[0-9]{2}"
   ```

   The pattern `^## 20[0-9]{2}-[0-9]{2}-[0-9]{2}` anchors at the start
   of a line and requires the full YYYY-MM-DD date shape. Memory-keeper's
   documented ADR format is `## YYYY-MM-DD — <title> (spec NNNN)`. This
   regex is sensitive to that header and immune to:
   - non-feature-keyword ADR titles (the failure on commit `ed3fe24`),
   - in-body lines like `## 20 things to consider` (no leading-line
     anchor and no real date shape),
   - any other in-body content of any ADR ever written.

   The throwaway repo's freshly-copied `history.md` template (from
   `templates/speccraft/history.md`) contains the header `# History`
   and an `Append-only. Newest first.` intro but no
   `^## 20[0-9]{2}-[0-9]{2}-[0-9]{2}`-matching line, so the assertion
   fails RED against the template and passes GREEN once memory-keeper
   prepends any well-formed ADR.

**Note for the planner.** This is a behavioral fix to a Bash test
harness. The RED→GREEN cycle is unusual: the bug is in the test (the
assertion is too tight), not in the system under test. RED = run the
new assertion against a synthetic history.md that has no `## 20XX-…`
header yet — the assertion fails. GREEN = same harness against a
history.md with any well-formed ADR prepended — passes. The
fixture-style test in AC2 codifies this. Plus the live signal: the
next post-spec-0014 CI run on `main` flips step `[7/9]` from `FAIL`
to `PASS` regardless of what feature-keyword the model uses in the
ADR title.

The fix is bounded to (a) the new helper and (b) the one assertion
site. Other assertions in the same `[7/9]` block (`exists
changelog.md`, `status_is closed`, `active_spec cleared`) are already
structural and stay unchanged. Other `contains "..." "farewell"`
occurrences elsewhere in `run.sh` (e.g. the `/spec:new` prompt text
that names the test spec) are unrelated to this assertion's bug and
stay.

## Acceptance criteria

1. After the change, the assertion site at the `[7/9]
   /speccraft:spec:close` block of `tests/e2e/run.sh` uses
   `contains_regex` (not `contains`) against
   `.speccraft/history.md` with the anchored date-header pattern
   `^## 20[0-9]{2}-[0-9]{2}-[0-9]{2}`. Verifiable by two paired
   fixed-string mechanical checks:
   - The new line is present:
     ```
     grep -nF 'contains_regex ".speccraft/history.md" "^## 20[0-9]{2}-[0-9]{2}-[0-9]{2}"' tests/e2e/run.sh
     ```
     returns exactly one match.
   - The old line is absent:
     ```
     grep -nF 'contains ".speccraft/history.md" "farewell"' tests/e2e/run.sh
     ```
     returns zero matches.

   Both checks use `grep -nF` (fixed-string) rather than escaped-BRE,
   so the oracles are portable across grep implementations.

   Other `farewell` mentions elsewhere in `run.sh` (e.g. the
   `/spec:new` prompt text at run.sh:174 that names the test spec)
   are intentional and unrelated to this fix — they are not part of
   either oracle.

2. A new shell-level fixture at
   `tests/e2e/contains_adr_assertion_test.sh` (executable,
   `#!/usr/bin/env bash` + `set -euo pipefail` per the general Bash
   convention) sources `tests/e2e/lib.sh` (the new helper module
   from §What item 1) and exercises **the exact `contains_regex`
   predicate the production assertion uses** —
   `^## 20[0-9]{2}-[0-9]{2}-[0-9]{2}` — against two synthetic
   histories built with `mktemp -d`:
   - **Positive case:** a history.md whose first non-header line is
     a well-formed ADR header
     `## 2026-06-10 — Sample (spec 0001)`. The fixture asserts
     `contains_regex` exits 0 (pass).
   - **Negative case:** a history.md containing only the template's
     `# History` + `Append-only. Newest first.` intro (no `## 20XX-…`
     ADR yet). The fixture asserts `contains_regex` exits non-zero
     (fail).

   Exit-code convention matches the existing E2E language-fixture
   pattern (`fail()` exits 2 for assertion failure). Because both
   `run.sh` and this fixture source the same `lib.sh`, the predicate
   is provably identical at runtime — there is no path by which
   fixture and production assertion can drift apart.

   The fixture is wired into a **new sibling**
   `run_helper_unit_tests()` function in `tests/e2e/run.sh` (not
   into the existing `run_language_fixtures()` — that function's
   name describes language-cycle fixtures specifically, and a
   shell-helper assertion test is not a language fixture).
   `run_helper_unit_tests` is called from the same dispatch points
   `run_language_fixtures` is, so the `e2e-language-only` CI job
   picks it up automatically. The step counter and progress prefix
   in `run.sh` are bumped accordingly in the same edit.

3. **RED-baseline oracle.** `grep -nE '^## 20[0-9]{2}-[0-9]{2}-[0-9]{2}'
   templates/speccraft/history.md` returns zero matches. This pins
   that the freshly-copied throwaway-repo history.md fails the new
   assertion before memory-keeper runs, so the GREEN flip after
   `/speccraft:spec:close` is a real positive signal and not a
   pre-existing template state. Verifiable mechanically; runs once
   in the new fixture's setup as a sanity precondition.

4. Next push to `main` after this spec lands produces a CI run where
   step `[7/9] /speccraft:spec:close` in `e2e-devcontainer` passes
   the history.md assertion regardless of the memory-keeper-chosen
   ADR title. Concretely the log line emitted by the post-edit
   harness (whichever pass-line wording the post-edit
   `contains_regex` helper uses) replaces the failing
   `FAIL: expected 'farewell' in .speccraft/history.md` line seen on
   run 27276707529. The run URL goes in this spec's `changelog.md`
   per the spec-0008 close-commit invariant.

## Out of scope

- The `TestGreeting` / `TestFarewell` host-fixture naming drift the
  model's close-log surfaced. Spec 0012's T8 already legitimized
  both `Test<UpperCamel>` and `Test_<Subject>_<Scenario>` as
  acceptable, so the "drift" is no longer a drift — it's a
  convention-conformant choice. Re-raising in `/speccraft:sync` is
  the right venue if the user wants to revisit; not part of this
  fix.
- Tightening memory-keeper's agent prompt to make ADR titles
  feature-deterministic. Larger, indirect, and changes
  memory-keeper's surface semantics for every spec — wrong layer
  to fix a single brittle assertion.
- Other assertions in `tests/e2e/run.sh` that may have similar
  content-vs-structure issues. This spec is strictly the
  `history.md: farewell` site at line 278. A sweep is a separate
  spec if needed.
- README + `speccraft-v1-spec.md` CodeGraphContext cleanup (still
  queued from spec 0011's §Out of scope).
- `/speccraft:spec:revise` command (still queued from spec 0011's
  §Out of scope).

## Open questions

_none — the `contains_regex` sibling-helper decision (vs extending
`contains` with a regex flag or inlining `grep -E`) is resolved in
§What item 1 and is the planner's input, not an open question._
