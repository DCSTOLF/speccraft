---
spec: "0011"
reviewers: [codex, claude-p]
quorum: 1
verdict: approve-with-comments
generated: 2026-06-09T00:00:00Z
---

# Cross-model review — 0011

## codex (gpt-5.5)

**Verdict:** approve-with-comments

Concerns:
- AC1 is only partly testable as written: `grep -nE 'prefer|fall back'` across
  the whole skill file may produce false positives on unrelated prose; the
  intended constraint is tool-routing context only.
- The spec allows one CodeGraphContext example in commands/init.md, but the
  rationale says naming one tool by brand creates drift risk. The distinction
  (examples allowed only in install-suggestion prose, not routing guidance) is
  reasonable but is not stated explicitly enough to survive misreading.

Suggestions:
- Tighten AC1: assert absence of codegraph/cgc references specifically inside
  the "Codebase-wide structural queries" section, not the whole skill file. Add
  a positive assertion that explicit deferral wording is present.
- Add a planner note clarifying that all three changes are
  documentation/template-only; verification is grep-based regression, not a
  behavioral test. This prevents the planner from generating e2e fixture
  scaffolding that is not needed.

Guardrail violations: none
Convention violations: none

---

## claude-p (Claude)

**Verdict:** approve-with-comments

Concerns:
- README.md is not in scope but contains CodeGraphContext references, including
  at least one line that will become factually false after this change. The
  spec's rationale applies word-for-word to the README. Excluding it leaves a
  known-stale claim on the most-read surface in the repo.
- AC1's grep test ends in a manual judgment call ("returning no matches against
  tool-routing context") — not a binary pass/fail. A fully objective form would
  pair `grep -i 'codegraph' skills/` returning nothing with a positive assertion
  that neutral deferral language is present.
- AC2 says "at most one match in commands/init.md" — this bound passes even if
  the install-suggestion is removed entirely (zero is at most one), contradicting
  §What's instruction to keep the conditional behavior. Should be "exactly one
  match" paired with a positive assertion that the suggestion still exists.

Suggestions:
- Either pull README.md into scope with its own AC, or explicitly exclude it in
  §Out of scope with a brief rationale (e.g., README is human-facing prose, not
  model-loaded routing, so drift there is lower-severity and can be a follow-on).
- Tighten AC2 to: "exactly one match in commands/init.md (the install-suggestion
  line), and the line frames CodeGraphContext as an example ('such as
  CodeGraphContext'), not as the recommended tool." This is verifiable with a
  literal phrase count.
- Add an AC sub-bullet for SKILL.md confirming the replacement text actually
  exists and is non-trivial — e.g., "the section retains an acknowledgment that
  structural queries are a real need." Without this, deleting the entire section
  would satisfy all three ACs while losing useful guidance.
- Note that this is a documentation-only change so the tdd-planner can adapt:
  "red" = a grep-based assertion script that fails today, "green" = same script
  passes after edits.

Guardrail violations: none
Convention violations: none

---

## Synthesis

Both reviewers agree: the core rationale is sound, the three-file scope is
appropriate, the frontmatter is correct, and no guardrail or convention
violations were found. Both converge on approve-with-comments with two
overlapping findings.

**Where both reviewers agree (stronger signal):**

1. AC1 has a testability gap. The grep command targets the whole SKILL.md file
   and produces a judgment call on context, not a binary result. Both reviewers
   independently asked for a scoped, objective form.

2. The planner needs a documentation-only signal. Without it a tdd-planner may
   attempt behavioral test scaffolding. Both reviewers flag this.

**Where only one reviewer flagged an issue:**

3. (claude-p only, must-fix) AC2's "at most one" bound is logically weak:
   zero matches also satisfies it, so deleting the install-suggestion entirely
   would pass AC2 while contradicting §What. This is a clear spec defect.

4. (claude-p only, should-fix) README.md is not in scope but contains
   CodeGraphContext references the spec's own rationale argues against. The
   spec should either pull it in or explicitly exclude it with reasoning so the
   planner does not have to decide.

5. (codex only, nice-to-have) The example-vs-recommendation distinction for
   the remaining commands/init.md match is implicit. Making it explicit in §What
   or AC2 removes ambiguity for whoever writes the prose change.

**Priority order for the spec author:**

Must-fix before the planner runs:
- Rewrite AC1 as a scoped, binary check: assert `grep -i 'codegraph\|cgc'
  skills/speccraft-context/SKILL.md` returns nothing inside the structural-
  queries section, AND assert that neutral deferral language is present (e.g.,
  a phrase check for "defer").
- Rewrite AC2 bound from "at most one" to "exactly one," and add a positive
  assertion that the surviving line frames CodeGraphContext as an example, not
  the recommended tool.
- Add a planner note (one sentence) stating this is a documentation/template-
  only change; regression verification is via grep, no behavioral fixtures
  required.

Should-fix:
- Address README.md: add it to scope with its own AC, or add a one-line §Out
  of scope entry explaining why it is explicitly excluded.
- Add an AC sub-bullet for SKILL.md confirming the replacement block is
  non-empty and contains an acknowledgment that structural queries are a
  legitimate need.

Nice-to-have:
- State the example-vs-recommendation distinction explicitly in §What item 2
  (already implied, but making it a named rule prevents ambiguity).

**Action:** The spec author should revise AC1, AC2, and add the planner note
before handing off to the tdd-planner. The README disposition (in-scope or
explicitly out-of-scope) should be decided in the same pass. No architectural
changes are needed; all required edits are to §Acceptance criteria and §Out of
scope.
