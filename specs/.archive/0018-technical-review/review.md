---
spec: "0018"
title: "technical-review"
reviewers: [codex, claude-p]
quorum: 1
verdict: approve-with-comments
generated: 2026-06-12T00:00:00Z
---

# Cross-model review — 0018 (technical-review)

## Round 2 (re-review) — 2026-06-12

Both reviewers returned `approve-with-comments`. Quorum is met (1 of 1 required). All round-2 precision comments were addressed by the author in the same review cycle before advancing. Status advanced: **draft → reviewed**.

---

## codex

**Verdict:** approve-with-comments

Concerns:

- AC3 should require that the failed record's test id be in the session's just-added set; as drafted it did not constrain which tests must fail.
- AC9 left the timeout source and default duration unspecified, making the bounded-invocation requirement ambiguous for implementers.

Suggestions:

- Tighten AC3 to cross-reference AC7 and explicitly scope the failure check to the just-added set.
- Clarify that JS and TS share one adapter and one resolution path; per-language config keys select the command, not a second adapter.

Guardrail violations: none

Convention violations: none

---

## claude-p

**Verdict:** approve-with-comments

Concerns:

- D1 overclaimed a "pure Rust mirror" — the cited range main.go:199-246 includes `if len(justAdded)==0 { return nil }`, which allows on empty. The new languages must deliberately diverge: empty just-added set must BLOCK (no rust_test_baseline), otherwise P0-1 reopens via a blank-line touch. The divergence was not explicitly noted.
- AC9 was only half-specified: the Outcome enum has no timeout value and gate.go:50 uses `context.Background()`, so a genuine hang remained unbounded. The spec needed to mandate `context.WithTimeout` and clarify that a deadline overrun surfaces as a Go error from `adapter.Run`, not a new Outcome value.

Suggestions:

- Add an explicit "Deliberate divergence on the empty just-added set" sub-bullet under D1 so implementers cannot inadvertently copy Rust's allow-on-empty branch.
- Bound the real adapter invocation with `context.WithTimeout(d)`; state that `d` is deferred to planning.
- Scrub both architecture.md non-goal sites (lines 14 and 42, not just one) in the documentation ACs.
- Confirm that guardrails.md carries the touch-only wording, or narrow AC11 to a no-regression check if the invariant text is already generic.

Guardrail violations: none

Convention violations: none

---

## Round-1 blocker disposition

All five round-1 blockers were resolved before round-2 re-review was submitted.

| # | Round-1 blocker | Resolution |
|---|-----------------|------------|
| 1 | Runner-absent policy (OQ#2) left open; "fall back to legacy touch-check" reopened P0-1 silently | Resolved — spec body closes OQ#2 as fail-closed; AC8 added: runner absent or unresolvable → BLOCK, no fallback |
| 2 | architecture.md absent from documentation ACs; spec 0005 non-goal sentence left contradicting shipped reality | Resolved — AC11 added architecture.md to the documentation list; supersession of the spec 0005 non-goal recorded in the Why section and frontmatter supersedes note |
| 3 | AC1 conflated two observably distinct states (OutcomeAllPassed vs. no sibling test found) | Resolved — AC1 split into AC1 (green blocks) and AC2 (no-target blocks), each with its own fixture and expected message |
| 4 | OQ#1 (sibling-file vs. just-added tests) left open; "parity with Rust" not actionable without stating Rust semantics | Resolved — D1 resolves the selector to the just-added model; Rust semantics stated explicitly |
| 5 | No timeout/hang contract; synchronous runner call with no deadline could block indefinitely | Resolved — AC9 added: runner invocation must be bounded; deadline overrun is non-RED and blocks |

---

## Round-2 comments (all addressed in-cycle)

The following precision comments were raised during round 2. The author applied each fix to the spec before the status was advanced, so no further author action is required on these items.

**D1 divergence (claude-p):** The original D1 note did not call out that the new languages must diverge from Rust's allow-on-empty branch. Without an explicit note, an implementer could copy `if len(justAdded)==0 { return nil }` from main.go:199-246 and silently re-open P0-1 via a blank-line touch.
Applied fix: added an explicit "Deliberate divergence on the empty just-added set" sub-bullet under D1 — empty just-added BLOCKS for Go/Python/JS-TS (no rust_test_baseline equivalent); implementer must not copy Rust's allow-on-empty branch.

**AC3 scope (codex + claude-p):** AC3 did not constrain which tests must fail; it could be satisfied by a failure in a pre-existing test unrelated to the just-added change.
Applied fix: AC3 now requires that the failed record's test id be in the session's just-added set (cross-referencing AC7). A failure outside that set does not satisfy AC3.

**AC9 timeout specification (codex + claude-p):** AC9 mandated a bounded invocation but did not name the mechanism or state how a timeout surfaces. The Outcome enum has no timeout value; gate.go:50 uses `context.Background()` so without an explicit mandate the real invocation remained unbounded.
Applied fix: AC9 now mandates `context.WithTimeout(d)` on the real adapter invocation. A deadline overrun surfaces as a Go error from `adapter.Run` (not a new Outcome value). Default `d` is deferred to planning.

**AC11 architecture.md sites (claude-p):** AC11 named only one architecture.md non-goal site; the document contains the superseded statement at two locations (lines 14 and 42).
Applied fix: AC11 now names both architecture.md sites explicitly. The guardrails.md check is narrowed to a no-regression check (its invariant text is already generic, so no rewrite is needed — only confirm the existing wording still holds).

**JS/TS single-adapter note (codex):** The spec was ambiguous about whether JS and TS require separate adapters or share one.
Applied fix: added a note that JS and TS share one adapter and one resolution path; the per-language config keys (e.g., `runners.javascript.command`, `runners.typescript.command`) select the command, not a second adapter instance.

---

## Synthesis

Round 2 found no new blockers. The five round-1 blockers were correctly and completely resolved. The round-2 comments were all precision issues — two reviewers converged on the same D1 divergence gap and the same AC9 half-specification; codex independently raised the AC3 scope gap and the JS/TS adapter ambiguity; claude-p independently raised the two-site architecture.md gap and the guardrails.md narrowing. None of these required structural changes to the spec; all were addressed by targeted sentence additions or tightenings. No guardrail or convention violations were found in round 2.

The spec is ready for planning.

---

## Quorum

Quorum MET. Two reviewers returned `approve-with-comments`; 1 of 1 required. Status advanced: **draft → reviewed**.

## Recommended next step

Run `/speccraft:spec:plan` against spec 0018 to produce the implementation task breakdown.
