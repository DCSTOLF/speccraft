---
spec: "0033"
title: "Post-0030/0031 CI regression hardening"
reviewers: [codex]
quorum: 1
verdict: approve-with-comments
generated: 2026-07-24T00:00:00Z
---

# Cross-model review — 0033 Post-0030/0031 CI regression hardening

## Reviewer availability

**Single-reviewer review.** The `claude-p` leg terminated early on an API session
limit (resets 11pm UTC) and returned no verdict. Only `codex` completed. Quorum
(1 approve/approve-with-comments) is met by codex's `approve-with-comments`; the
usual codex-vs-claude-p cross-check was not available this round. Worth a
second-model pass after the limit resets if any comment turns out contentious —
none did.

## codex — approve-with-comments

No guardrail or convention violations. Concerns (all actionable refinements, no
blockers):

1. **AC1 must be ASYMMETRIC.** Normalize only the expected fixture root
   (`want = filepath.EvalSymlinks(root)`) and compare `got` to it directly — do
   NOT normalize `got`. Normalizing both sides would let a resolver that *skipped*
   `EvalSymlinks` pass, masking the exact regression AC1 exists to catch.
2. **AC3 needs a defined unit of association.** "Write payload carrying
   `new_string`" must be pinned to the *same constructed envelope/block*, not a
   repo-wide proximity grep (false positives from comments / unrelated payloads).
   Forbid `new_string` **unconditionally** for a `Write` payload (even if
   `content` is also present) for the cleanest invariant. Pick the guard *layer*
   in the spec (a Go test that structurally scans `tests/e2e/*.sh` is preferable)
   and name the CI entry point.
3. **AC4 needs a credit-free oracle.** "Imperative / separates" is not a
   deterministic check. Add a credit-free meta-test that reads the LIVE decline
   prompt and pins terminal-action phrases (write the marker; do not move the
   directory; do not wait for confirmation), keeping the credit-gated
   marker-exists/dir-unmoved post-condition as the behavioral check.
4. **Frame item (3) as an independent CI-unblock item**, not a 0030/0031
   regression — the spec is already transparent; make it explicit so causal
   cohesion isn't overstated.
5. **AC5 defined negatively.** State the permitted file classes positively
   (the test, the e2e fixtures, the new guard) rather than "no non-test/-fixture/
   -prompt code."
6. **State the no-version-bump decision positively:** no shipped binary,
   manifest, command, hook, or user-facing prompt changes → the behavior/API
   trigger of §Version bumps does not apply. Note the changed prompt is
   test-driver input inside `tests/e2e/`, not a user-facing command/agent prompt.
7. **Allocation note:** record that 0032 remains reserved by spec 0031 and 0033
   intentionally skips it; do NOT add `reserves-specs:["0032"]` to 0033 (a
   reservation cannot be lower than the reserving spec's own ID).

## Synthesis & resolution

Quorum met; verdict `approve-with-comments`; no blockers. All seven comments are
correct and cheaply actionable, and several materially improve testability (AC1
asymmetry, AC3 precision + layer decision, AC4 credit-free oracle). Folding them
into the spec before planning:

- AC1 → rewritten to mandate the asymmetric assertion (normalize `want` only;
  the test must still fail if the resolver stops calling `EvalSymlinks`).
- AC3 → pinned to same-envelope/block association, `new_string`-forbidden-
  unconditionally-for-Write, and the **Go-test layer** chosen (resolving the open
  question); open question removed.
- AC4 → adds the credit-free prompt meta-test alongside the credit-gated
  post-condition.
- AC5 → restated as a positive permitted-file-class list.
- Version decision → restated positively in Out of scope, noting the prompt is
  test-driver input.
- §Why/§What → item (3) explicitly labelled an independent CI-unblock/
  stabilization item.
- Added an allocation note (0033 skips reserved 0032; no self-reservation).

**Action:** fold the above into spec.md (draft → edit-in-place), then advance to
`/speccraft:spec:plan`.
