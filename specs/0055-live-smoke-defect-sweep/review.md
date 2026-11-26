---
spec: "0055"
reviewers: [codex-plugin]
quorum: 1
verdict: changes-requested
generated: 2026-11-26T00:00:00Z
---

# Cross-model review — 0055 (round 3, scoped --diff re-review)

This round supersedes round 2.

## Reviewers

| Agent | Verdict | Mode | Model | Vendor |
|-------|---------|------|-------|--------|
| codex-plugin | changes-requested | codex-plugin | inherit | openai |

## codex-plugin

**Verdict:** changes-requested

Confirmed landed from round 2:
- AC3a now tests the operator-facing sweep with mixed quarantine blocks. It requires the diagnostic to identify the legacy block, preserves that block, and clears only the new-format block once its job is terminal.
- AC8b moves sourcing ahead of allocation and tests that the shipped invocation uses the real helper's returned ID for scaffolding.
- The prose counts nine defects.
- AC23 reviewer metadata is distinguished from AC23a's quorum-gated flag.

Concerns:
- AC9a leaves finalization undefined when a complete round meets approval quorum but the synthesis fails table validation. The runbook writes `review.md` before finalizing and then reads the quorum result to promote status. Rejecting the candidate without stopping that sequence can advance the snapshot, stamp the prior `review.md`, or mark the spec reviewed without a valid artifact for this round.

Suggestions:
- Require AC9a to stage the synthesis and validate or render the table before publishing `review.md`. If validation fails, preserve the previous `review.md` and snapshot byte-for-byte and skip fingerprint stamping and status promotion.
- Exercise that path with a complete, quorum-met round and a malformed synthesis, starting from an existing review and snapshot. Keep the quorum calculation unchanged.

Guardrail violations: none.

Convention violations: none.

Reviewer's closing note: no other regression found in the revised sections, the previously approved criteria, or the unchanged scope decisions.

## Synthesis

The findings have clearly diminished across the three rounds. Round 1 produced four concerns and four convention violations. Round 2 produced three concerns and one convention violation. Round 3 produced one concern and no convention or guardrail violations. This is the signal that the spec has stabilised.

The reviewer explicitly confirmed that the round-2 revisions landed. AC3a exercises the operator-facing sweep with mixed quarantine blocks. AC8b sources before allocating and pins the shipped invocation against the real helper. The prose counts nine defects. AC23 is distinguished from AC23a.

The single remaining concern is accepted in full, and it is the one thing left to specify. AC9a put the Reviewers-table check in the production write path but did not define the failure branch. The runbook writes `review.md` before `review_finalize_round`. Finalize promotes the snapshot, stamps the fingerprint and can set status to `reviewed`. If a failed validation does not halt that sequence, a complete quorum-met round with an invalid synthesis could advance the snapshot, stamp the prior `review.md`, or mark the spec reviewed with no valid artifact for the round. This is the same class of defect spec 0052 already fixed once. There, promoting before a verdict existed re-baselined the anchor that an inert round must leave untouched.

Required behaviour: stage the synthesis and validate or render the table before publishing. On failure, preserve the previous `review.md` and `review-snapshot.md` byte-for-byte, skip fingerprint stamping and status promotion, and leave the quorum calculation unchanged.

**Action:** Revise AC9a to define the failure branch. Stage the synthesis and validate or render the Reviewers table before publishing. On rejection, keep the previous `review.md` and `review-snapshot.md` byte-for-byte, skip fingerprint stamping and status promotion, and do not change the quorum calculation. Add a test that starts from an existing review and snapshot, feeds a complete quorum-met round with a malformed synthesis, and asserts both files are unchanged, no fingerprint is stamped and status is not promoted. Then run a final scoped re-review.
reviewed_sha256: 2e8f5149164124f8e337e7cacd7ce2eb528c7fb154a0bc65335cbe0174df82c2
