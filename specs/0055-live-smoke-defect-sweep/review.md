---
spec: "0055"
reviewers: [codex-plugin]
quorum: 1
verdict: changes-requested
generated: 2026-11-26T00:00:00Z
---

# Cross-model review — 0055 (round 2, scoped --diff re-review)

## Reviewers

| Agent | Verdict | Mode | Model | Vendor |
|-------|---------|------|-------|--------|
| codex-plugin | changes-requested | codex-plugin | inherit | openai |

## codex-plugin

**Verdict:** changes-requested

Concerns:
- AC9a specifies a structural test but leaves the production write path unchanged. The cross-reviewer template already required the table when the agent omitted it. A test against a sample review.md can pass while a complete live round still persists an incomplete artifact.
- AC8b checks that step 4 mentions the helper, but can pass if the call uses the wrong root, runs before new.lib.sh is sourced, or discards the returned ID. The current runbook sources the library in step 5.
- AC3a requires a diagnostic for legacy blocks, but the existing sweep suppresses resolver output and prints a generic quarantine message. The criterion can pass in a direct resolver test while an operator running the sweep cannot tell why the block remains or how to release it safely.

Suggestions:
- Have the production review path render the table from the round report or validate it before persisting review.md. Exercise that path with omitted and malformed tables, and preserve the existing complete-round write gate and quorum rules.
- Execute the shipped step 4 call against the real helper with an archive-and-reservation fixture. Assert that scaffolding uses the returned ID, and demonstrate failure with an incorrect root or a discarded return value.
- Exercise the sweep with a mixed quarantine file containing a legacy Codex block and a new-format Codex block. Assert that the sweep exposes the missing-cwd diagnostic, retains the legacy block, and clears only the new block after its job becomes terminal.
- Change the What introduction to nine defects and distinguish AC23's reviewer metadata requirement from AC23a's same-vendor approval flag.

Guardrail violations: none.

Convention violations:
- "A behavioral contract added to a command runbook gets a bats pin against the real function." Location: Acceptance criteria, AC8b.

Reviewer's closing note: The revision addresses the prior findings on active-before-cancel evidence, explicit budget outcomes, diff reproducibility, reserved IDs, and Bash and Zsh execution. I found no contradiction in the unchanged Open questions. The new legacy-quarantine rule safely retains blocks with an unknown job-store cwd. Its remaining gap is operator visibility through the sweep. The new reviewer-table criterion needs a production guarantee that survives another synthesis omission.

## Synthesis

This was round 2, a scoped `--diff` re-review by a single reviewer (quorum 1, not met). The reviewer explicitly confirmed that round 1's findings were addressed: active-before-cancel evidence, explicit budget outcomes, diff reproducibility, reserved ids, and bash/zsh execution. The remaining findings are new, all in the revision's added criteria.

**Convention violation (surfaced regardless of quorum):** AC8b lacks a bats pin against the real function, as the conventions require for behavioral contracts added to a command runbook.

Orchestrator-verified facts:
1. The AC8b concern is correct and concrete. `commands/spec/new.md` sources `new.lib.sh` at step 5 but allocates the id at step 4. A `spec_new_next_id` call placed in step 4 would invoke an unsourced function. A mention-only check would pass anyway. The author must reorder the sourcing, or place the call after it, and pin the shipped call against the real helper with an archive-and-reservation fixture. That fixture must show failure for a wrong root or a discarded return value.
2. The What introduction still reads "Fix eight defects. Seven are small", while the Why section says nine. The inconsistency is present and must be fixed. AC23 (reviewer metadata) should also be distinguished from AC23a (the same-vendor approval flag).

Accepted: the AC9a concern. A structural test over a fixture cannot prevent a live round from persisting an incomplete artifact, which is the very failure round 1 exhibited. The fix must be in the production write path. That means rendering the Reviewers table from the round report, or validating it before review.md is persisted. The existing complete-round write gate and quorum rules must be preserved, and the tests must cover omitted and malformed tables.

AC3a also needs work. The sweep suppresses resolver output and prints only a generic quarantine message, so an operator cannot see why a legacy block remains. The test should use a mixed quarantine file. The sweep must show the missing-cwd diagnostic, retain the legacy block, and clear only the new-format block once its job is terminal.

**Action:** Revise the spec with these four changes.
1. Make AC9a a production-path guarantee (render or validate the Reviewers table before persisting review.md).
2. Rework AC8b so the step 4 call is made after `new.lib.sh` is sourced, and pin it with a bats test against the real helper.
3. Make AC3a require the sweep itself to surface the legacy-block diagnostic, and test it with a mixed quarantine file.
4. Fix the What introduction to say nine defects, and separate AC23 from AC23a.

Then run another scoped re-review.
reviewed_sha256: 37a84180af500ff9e1db63a342fea0f81ec953b40e42090366e5c18491af50a0
