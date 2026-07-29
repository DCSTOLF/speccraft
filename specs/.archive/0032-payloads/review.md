---
spec: "0032"
reviewers: [codex, claude-p]
quorum: 1
verdict: approve
generated: 2026-07-25T00:00:00Z
round: 2
---

# Cross-model review — 0032-payloads

## Round 2 (revision 2) — RESOLVED

| Reviewer  | Round 1                | Round 2   |
|-----------|------------------------|-----------|
| codex     | changes-requested      | **approve** |
| claude-p  | approve-with-comments  | **approve** |
| **Overall** | **changes-requested** | **approve (quorum met)** |

Revision 2 applied all seven convergent must-fixes plus the strong suggestions.
Both reviewers re-audited their round-1 findings against revision 2 and confirmed
each resolved, with **no new blocking defects, guardrail violations, or
convention violations**:

- **AC1 contradiction** → fixed: `applyEdit("a c a", [{a→b},{c→d}]) == "b d a"`,
  exact oracle.
- **Edge cases** → AC3 pins empty `edits[]`→preContent, absent `old_string`→no-op,
  empty `OldString`→skipped (not prepended); AC4 pins NotebookEdit `""`→`""`.
- **Sequential dependency** → AC2 (`{a→b},{b→c}` on `"a"` == `"c"`).
- **AC13 build-vs-runtime trap** → promoted to a load-bearing WHAT constraint
  (envelope-boundary `json.Unmarshal` authoring) + AC7 requires the RED test to
  assert against an already-existing symbol; expected override-free.
- **Recurrence oracle** → AC9 exact phrases as a Go test (+ case-insensitive,
  whitespace-tolerant per round-2 nit) + unknown-tool (`"FutureEdit"`) fallback
  characterization.
- **Release completion** → AC10 restores the merge-time published+verified
  release obligation (auto-tag → release.yml → verify-release.sh), mirroring
  0031/0034.
- **NotebookEdit empty/absent** → resolved by switching on `ToolName` (not field
  presence); plain `string` deliberate; AC4 pins both cases.

Non-blocking round-2 nits carried into the plan/implementation: retain
release-workflow evidence when doing AC10 (codex); ensure `dispatchByLanguage`
sets `ToolName` before unmarshal-dependent logic so an injection-move regression
fails AC8 loudly (claude-p); AC9 grep is case-insensitive + whitespace-tolerant
(claude-p — folded into the spec).

**Round-2 recommendation:** quorum met → status `reviewed`; proceed to
`/speccraft:spec:plan`.

---

# Round 1 (revision 1) — history

# Cross-model review — 0032-payloads

## Verdict table

| Reviewer  | Verdict               |
|-----------|------------------------|
| codex     | changes-requested      |
| claude-p  | approve-with-comments  |
| **Overall** | **changes-requested** |

Per the review policy, any single `reject`/blocking-severity finding escalates
the overall verdict; here codex flagged AC1 as an internally-contradictory
BLOCKER, and both reviewers independently converged on several must-fix
items below, so the overall round-1 verdict is **changes-requested** despite
claude-p's more lenient standalone verdict.

## Convergent findings (must-fix)

Both reviewers independently identified these — treat as load-bearing.

1. **AC1 is broken/too weak.** codex: applying `a->b` and `c->d` to the literal
   input `"PRE"` yields `"PRE"` unchanged (neither substring occurs), so the AC's
   own "result other than PRE" requirement is unsatisfiable as written — a
   BLOCKER. claude-p: independently, the "not equal to PRE" shape is also too
   weak as an oracle even where satisfiable (e.g. an impl returning `"PRX"`
   would pass). **Fix:** replace the fixture with content that actually
   contains the target substrings (e.g. `"a c e"` with edits `{a->b, " c"->"d"}`)
   and assert the **exact** expected post-string, not a weak inequality.

2. **Edge cases are unspecified.** Both flag that the spec is silent on:
   empty `edits[]`, an absent `old_string`, an **empty** `old_string` (Go's
   `strings.Replace` prepends `new_string` when `old` is `""` — a real
   correctness trap), and an empty `NotebookEdit.new_source`. **Fix:** add
   explicit ACs pinning behavior for each case (e.g. empty `edits[]` →
   `preContent` unchanged; absent `old_string` → no-op vs. document as
   best-effort mismatch with the real MultiEdit tool's error behavior; empty
   `old_string` → explicitly reject/skip or document+test the prepend
   semantics; empty `new_source` → pin whether it's treated as
   present-and-empty or indistinguishable-from-absent).

3. **AC5 risks recreating the spec 0031 "build-failed-not-RED" trap** (spec
   0018 AC13). Both reviewers note that unit tests initializing the new
   `Edits`/`NewSource` fields directly cannot compile before those fields
   exist, so a driving RED authored that way would fail to *build* rather than
   fail at *runtime* — which doesn't count as a valid RED and may require an
   override. **Fix:** the plan must explicitly mandate authoring the driving
   RED at the `json.Unmarshal` envelope boundary (untyped/JSON-string
   construction, per the 0031 pattern), not via direct struct-literal
   construction of the new fields, and only add direct `applyEdit` unit tests
   once the fields exist.

4. **AC6's grep-based recurrence guard is under-specified.** Both reviewers
   want exact negative phrases pinned rather than a loose pattern (codex:
   "may be too broad or too weak"; claude-p: bare `grep -w` risks
   false-positives, and the check should run as a Go test — not a shell
   one-liner — so it executes under `go test`). **Fix:** enumerate the exact
   stale-phrase strings to guard against (e.g. `"reserved spec 0032"`,
   `"reserved for spec 0032"`, `"unmodeled"`) and implement the check as a Go
   test.

5. **AC7 omits the guardrail-mandated published-release verification.** Both
   reviewers note the version-bump/release AC doesn't include the
   published+verified GitHub release step, so the release isn't "done" under
   the project's release guardrail. **Fix:** add explicit release-completion
   criteria for the 1.9.0 bump (publish + verify).

6. **MultiEdit sequential-dependency case is untested but load-bearing.**
   Both reviewers call for a dedicated test where a later `edits[]` entry's
   `old_string` only exists in the content *after* an earlier entry has been
   applied (e.g. `{a->b}, {b->c}` on `"a"` must yield `"c"`), to pin that
   edits apply against the *running* (not original) content.

7. **NotebookEdit empty `new_source` vs. absent-field ambiguity.** Both note
   that in Go, an empty string and a zero-value (absent) field are
   indistinguishable on a plain `string` type. **Fix:** either accept and
   explicitly pin the ambiguity with a test, or use `*string` (+ optional
   companion bool) if the distinction needs to be observable.

## Suggestions (nice-to-have)

From codex:
- Add an explicit AC for the sequential-dependency case described above (also
  listed as convergent above, but codex frames it as a spec addition).
- Constrain AC5 to a failing assertion against an *existing* production
  symbol (a true runtime RED) or explicitly document the override path if a
  new-symbol RED is unavoidable.
- Add a test documenting that NotebookEdit red-candidate capture is scoped to
  the edited cell's `new_source` only, and does not pick up tests in other
  notebook cells (explicitly out of scope, but worth pinning with a test/note
  so it's not mistaken for an oversight).

From claude-p:
- Add an AC pinning `dispatchByLanguage`'s `ToolName` round-trip for
  MultiEdit/NotebookEdit, so a dispatch regression that silently routes to
  `default` doesn't pass downstream tests undetected.
- Name the inner MultiEdit entry type (`type MultiEditEntry struct{...}`)
  instead of an anonymous struct, for referenceability and easier test
  construction.
- Add a characterization test for a genuinely unknown `ToolName`
  (`"FutureEdit"`) asserting the `default` branch still returns `preContent`
  unchanged — re-establishing the "reserved slot" pattern for whatever tool
  comes next.
- Rename the existing 0031 reserved-slot tests (e.g. to
  `Test_MultiEditEnvelope_CapturesRedCandidate`) so the test *name* also acts
  as a recurrence guard, greppable independent of AC6's content check.
- Note in the spec that `hooks.json` already lists MultiEdit/NotebookEdit
  (context, not a gap).
- Consider a shared `applyMultiEdit(pre, edits)` helper so the sequential
  invariant lives in one greppable place rather than being reimplemented in
  the switch statement.

## Guardrail / convention notes

- **codex**: AC7 lacks the required published-release verification step —
  the version bump is not "done" under the release guardrail until that's
  added (also listed under must-fix #5 above, since claude-p converged on it
  independently).
- **codex**: flags a live risk of tripping the spec 0018 AC13
  build-failed-not-RED trap if REDs are authored via direct struct-literal
  construction of the new `Edits`/`NewSource` fields before those fields
  exist (see must-fix #3).
- **claude-p**: explicitly reports no guardrail violations, but independently
  raises the same AC13-trap risk as a spec-authoring-process concern rather
  than a violation per se — the plan needs to *mandate* envelope-boundary
  RED authoring, not merely hint at it.
- No disagreements between reviewers on guardrail matters — both point at the
  same two issues (AC13 trap risk, missing release-verification step) from
  slightly different angles.

## Synthesis

Both reviewers agree the overall direction and scope of spec 0032 are sound —
this is a narrow, well-motivated fix closing a reserved gap from spec 0031,
not a redesign. The disagreement in standalone verdicts (codex:
changes-requested vs. claude-p: approve-with-comments) is one of degree, not
substance: codex treats AC1's internal contradiction as a hard blocker while
claude-p treats the overlapping weak-oracle issue as a comment-level fix.
Because codex's finding is a genuine logical break in AC1 as currently
written (the stated fixture cannot produce the stated result), and because
both reviewers converge on the same substantive list of gaps (edge cases,
AC5's build-vs-runtime RED trap, AC6's oracle precision, AC7's release
completion, the MultiEdit sequential-dependency case, and NotebookEdit's
empty/absent ambiguity), the spec needs a text-hardening revision before
implementation should proceed. None of the required changes touch the
architectural approach (typed `Edits`/`NewSource` fields, explicit switch
cases, default-branch preservation) — they tighten the ACs' fixtures,
oracles, and edge-case coverage so implementation and tests can't drift into
false-pass states.

**Recommendation:** Apply the seven convergent must-fix items to `spec.md`
(revision 2): (1) fix the AC1 fixture + assert exact output; (2) add explicit
edge-case ACs for empty `edits[]`, absent/empty `old_string`, and empty
`new_source`; (3) mandate envelope-boundary RED authoring in the plan to
avoid the AC13 build-vs-runtime trap; (4) pin AC6's grep oracle to exact
phrases as a Go test; (5) add published-release verification criteria to
AC7; (6) add the MultiEdit sequential-dependency test; (7) pin the
NotebookEdit empty/absent `new_source` behavior. Then re-submit for round 2
review. The suggestions list (dispatch round-trip AC, named entry type,
unknown-ToolName characterization test, test renames, shared helper) is
optional polish and does not block a re-review pass.
