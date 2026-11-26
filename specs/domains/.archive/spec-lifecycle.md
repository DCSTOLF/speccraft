# Domain requirement archive

Verbatim superseded requirement text demoted from a domain file by spec consolidation. Append-only.

## spec-lifecycle | spec 0052 | MODIFY
- `/speccraft:spec:review --diff` runs a diff-focused re-review: `speccraft-state review-snapshot write` freezes `spec.md`, and `review-diff [--promote]` emits a versioned JSON envelope (`snapshot`/`changed`/`changed_sections`/`diff`/`fingerprint`/`base_fingerprint`) from a section-anchored textual diff keyed by `##` heading + ordinal (byte-identical bodies never reported) (spec 0035)

## spec-lifecycle | spec 0052 | MODIFY
- `review.md` records the reviewed `spec.md` fingerprint (sha256 of raw bytes) as one `reviewed_sha256:` line via a single atomic temp-then-rename commit written only after the review workflow completes (verdict-independent; nothing written on any failure); `review-snapshot.md` persists under `specs/`, outside the `speccraft-drift` scan scope (spec 0035)

## spec-lifecycle | spec 0054 | MODIFY
- `review.md` records the reviewed `spec.md` fingerprint (sha256 of raw bytes) as one `reviewed_sha256:` line via a single atomic temp-then-rename commit, written only when `review_responses_complete` holds — every required reviewer returned a verdict — and then for ANY verdict including `changes-requested`; nothing is written on any failure, and an inert round leaves the prior `review.md` byte-identical. `review-snapshot.md` persists under `specs/`, outside the `speccraft-drift` scan scope (spec 0035, amended by spec 0052)

## spec-lifecycle | spec 0054 | MODIFY
- A review round has TWO separate predicates gating different things, because `review_quorum` counts AGREEING agents and conflating that with "did everyone answer" would forbid a legitimate `changes-requested` round from persisting its review: `review_responses_complete` (every required reviewer returned a verdict — a refusal, timeout, failure or failed attestation is not a verdict) gates synthesis, the `review.md` write and the `reviewed_sha256` commit for ANY verdict including `changes-requested`, while `review_approval_quorum_met` (agreeing verdicts >= quorum) ALONE gates `status: reviewed`. An unknown outcome token is an error rather than a silent non-verdict (spec 0052)

## spec-lifecycle | spec 0054 | MODIFY
- The review runbook is ordered source-lib -> compose -> materialize -> `review_budget_check` -> dispatch, pinned by a meta-test comparing FOUND MARKER INDICES rather than absolute line numbers: a budget check after dispatch would prevent nothing, since the payload has already reached the CLI. Each agent gets a DISTINCT artifact path inside the round temp dir and the outputs are hash-compared before verdicts are counted, because identical hashes across two agents are a dispatch bug rather than agreement (spec 0052)

## spec-lifecycle | spec 0054 | MODIFY
- The command classifies via a provenance gate on the prior `review.md`'s `reviewed_sha256` vs the envelope `base_fingerprint`: byte-identical → short-circuit (no reviewers); baseline-not-last-reviewed or first review → full review with a warning; else scoped re-review of the changed sections plus a regression sweep over previously-approved criteria (`templates/prompts/re-review.md`) (spec 0035)

