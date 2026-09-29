# FORBIDDEN FIXTURE — do not copy this into commands/spec/review.md

Spec 0052 AC24/AC29. This file is the bite proof for the promote-deferral
check in tests/hooks/spec-review-payload.bats: `runbook_promote_free` is run
against the real runbook (must pass) and against this file (must reject). A
bare `! grep -q '--promote'` against the runbook alone would pass just as
happily if the `review-diff` call were deleted entirely, so the negative is
pinned against a committed artifact rather than against author discipline.

This is the pre-0052 shape, verbatim from `commands/spec/review.md:32`:

```bash
# ONE read/diff/write: freeze the snapshot from spec.md, capture the envelope.
ENV="$(speccraft-state review-diff "$SPEC_DIR" --promote)"
```

It writes `review-snapshot.md` at the START of the round, before any verdict
exists — mutating the very anchor AC23 requires byte-unchanged on an inert
round, and silently re-baselining a round in which every reviewer refused.
