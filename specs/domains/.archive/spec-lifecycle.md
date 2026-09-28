# Domain requirement archive

Verbatim superseded requirement text demoted from a domain file by spec consolidation. Append-only.

## spec-lifecycle | spec 0052 | MODIFY
- `/speccraft:spec:review --diff` runs a diff-focused re-review: `speccraft-state review-snapshot write` freezes `spec.md`, and `review-diff [--promote]` emits a versioned JSON envelope (`snapshot`/`changed`/`changed_sections`/`diff`/`fingerprint`/`base_fingerprint`) from a section-anchored textual diff keyed by `##` heading + ordinal (byte-identical bodies never reported) (spec 0035)

## spec-lifecycle | spec 0052 | MODIFY
- `review.md` records the reviewed `spec.md` fingerprint (sha256 of raw bytes) as one `reviewed_sha256:` line via a single atomic temp-then-rename commit written only after the review workflow completes (verdict-independent; nothing written on any failure); `review-snapshot.md` persists under `specs/`, outside the `speccraft-drift` scan scope (spec 0035)

