---
design: "0001-architect-lifecycle-orchestration"
title: "Architect orchestrates the full spec lifecycle across single- and multi-repo workspaces"
reviewers: [codex, claude-p]
quorum: 1
verdict: approved-with-required-fix
generated: 2026-07-28T00:00:00Z
---

# Cross-model review — 0001-architect-lifecycle-orchestration

## codex

**Verdict:** changes-requested

Concerns:
1. Status-source mismatch (confirmed against architecture.md): Components §4 has reconcile read child-spec status from member `state.json`, but `state.json` only holds active-spec/TDD session state — spec status lives in `spec.md` frontmatter via `speccraft-state set-status`. Also unaddressed: post-close consolidation (spec 0025) moves a closed spec's dir to `specs/.archive/NNNN-slug/`, so reconcile must resolve both live and archived locations.
2. Crash recovery not safely idempotent: if a delegated command succeeds but the ledger write fails, retrying from `last_completed_phase` could double-allocate a spec, repeat implementation, or re-run `spec:close` on an already-closed spec. Needs stable pre-dispatch identifiers plus authoritative-artifact inspection before retry, and per-phase idempotency rules.
3. Ledger schema underspecified: missing `blocked` flag + failure details, no schema/version, no markdown grammar, no atomic-write or concurrent-conductor policy.
4. `in_flight` boolean too lossy: review/revise is a multi-step retryable loop; the flag can't capture which op was interrupted, iteration count, or pending human-escalation state.
5. Unspecified interfaces: no machine-readable command outcomes / critic verdicts / unresolved-Q&A representation / validation results / checkpoint decisions / invocation+exit-code contract per phase.
6. `answer-questions`/`validate` phases lack concrete backing commands.
7. Workspace/decomposition schema gaps: member identity, canonical path rules, duplicate/overlapping paths, symlink escape, design-id uniqueness, decomposition syntax, membership validation.
8. Straight-through flag conflict: undefined behavior when an exhausted review loop (mandates human resolution) meets straight-through/unattended execution.
9. Multiple unresolved mechanism spikes materially determine implementation boundaries; a planner can't derive a reliable plan yet.

Guardrail violations: none (preserves red→green guard + `speccraft-state` single-writer rule).

Convention violations: state-file boundary — Components §4 reads status from `state.json` instead of `spec.md` frontmatter.

## claude-p

**Verdict:** approve-with-comments

Concerns:
1. Deferred staging decision (Open Questions §1) is load-bearing/hard-gate, not cosmetic.
2. Ledger/reconcile divergence when the pointer and real member status disagree (e.g. member archived out-of-band) is unspecified.
3. `ledger.md` format is asserted but no concrete schema/example is given.
4. `blocked` overlay flag storage/clearing mechanics are ambiguous.
5. `find-workspace-root` consumers are not enumerated, which affects the "no hot-path change" feasibility claim.
6. Spikes #2 (decomposition mapping) and #3 (AC-verification mechanism) are policy decisions, not just mechanism — resolving them could reshape Components §2/§3.
7. Monorepo re-scoping (single `repo`-kind member, no per-package roots) effect on existing installs is unstated.

Suggestions:
- Concrete 5-10 line `ledger.md` example (one design, two members, one blocked).
- Reconcile-divergence table (ledger pointer vs. real status, per case).
- Promote spikes #2/#3 to risk items with an explicit fallback.
- State which layers/commands call `find-workspace-root`.
- Decomposition: add a `decomposition:` block schema example.
- Clarify whether reconcile prunes archived rows from the ledger.
- Add a per-component test-surface bullet.

Guardrail/convention violations: none.

Free-form: feasibility is the strongest section; missing an explicit conductor entry command/invocation surface and how the two HITL checkpoints surface in UI; no reconcile perf NFR for large member counts; internal consistency is "impressively tight." Would reach a clean approve once the staging decision, ledger schema, and spike #2/#3 policy risk are addressed.

## Synthesis

Both reviewers independently converge on the same soft spots — ledger schema concreteness, `blocked`/`in_flight` state fidelity, and the open staging question — which is a strong signal these are real gaps rather than reviewer idiosyncrasy. Neither reviewer found a guardrail violation; both regard the overall direction (compose existing commands via a state machine + advisory ledger, never gate members) as sound and buildable.

Where they diverge in severity: claude-p treats the open items as polish-before-clean-approve; codex treats one of them as a confirmed factual defect. Cross-checking against the design text itself confirms codex is right: Components §4 states reconcile "read[s] each child spec's real status from that member's `state.json` via `speccraft-state`" — but spec status lives in `spec.md` frontmatter (set via `speccraft-state set-status`), not in `state.json`, and a closed spec's directory is relocated to `specs/.archive/NNNN-slug/` (spec 0025), which the current reconcile description does not account for. This is not a style nit — it is the authority mechanism for the design's core "advisory rollup, never gates" guarantee, so it must be corrected before this design is used to generate a plan.

Quorum (1 approve/approve-with-comments) is technically met by claude-p, and codex found no guardrail or convention violation beyond this one state-boundary error — so a full reject is not warranted. But shipping the design forward with a confirmed-wrong authority mechanism in a load-bearing component would mislead the planner. The honest framing is **approved-with-required-fix**: the design is directionally sound and cleared to proceed once the status-source defect is corrected in the doc; the remaining should-fix items are strong candidates to fold in now (cheap, and de-risk planning) but do not block moving to a fix-and-replan pass.

### Must-fix before planning
- **Status-source defect (Components §4, Data model).** Correct reconcile to read child-spec status from `spec.md` frontmatter (the `speccraft-state set-status` authority), not `state.json`. Explicitly handle both live (`specs/NNNN-slug/`) and post-close archived (`specs/.archive/NNNN-slug/`) locations when resolving a member's real status.

### Should-fix / fold into design
- Crash-recovery idempotency window: define stable pre-dispatch identifiers and an authoritative-artifact check before any retry from `last_completed_phase`, so a ledger-write failure after a successful delegated command can't double-allocate a spec, repeat implementation, or re-run `spec:close` on an already-closed spec.
- Enrich `in_flight` beyond a boolean (or add a companion field) to capture which sub-step of the review/revise loop was interrupted, iteration count, and pending human-escalation state; add the `blocked` flag with failure detail to the ledger schema explicitly (currently only described in prose, Components §5).
- Add a concrete `ledger.md` example (one design, two members, one blocked) so the markdown grammar is unambiguous before implementation.
- Specify a conductor entry command/invocation surface and how the two HITL checkpoints (exhausted review loop, post-plan pause) surface to the user.
- Enumerate which layers/commands call `find-workspace-root`, to substantiate the "no hot-path change" feasibility claim.

### Defer to plan/spike time
- Full ledger grammar + schema versioning.
- Concurrent-conductor locking / atomic-write policy for `ledger.md`.
- Typed phase envelopes / machine-readable outcomes for command results, critic verdicts, unresolved-Q&A state, validation results, and checkpoint decisions (spike per phase, per codex concern 5).
- Path canonicalization / symlink-escape / duplicate-member-path policy for `workspace.yml`.
- Reconcile performance NFR for large member counts.
- Monorepo re-scoping migration note for existing installs.
- Spikes #2 (decomposition mapping) and #3 (AC-verification mechanism) as tracked risk items with fallback, since they may reshape Components §2/§3 once resolved.

### Points of agreement
- No guardrail violations from either reviewer; the red→green guard and `speccraft-state` single-writer rule are preserved.
- Overall direction and feasibility (compose existing per-spec commands via a new state machine, never gate a member's own flow) is sound and buildable.
- The staging decision (Open Questions §1) is genuinely load-bearing and correctly marked as a hard gate before `spec:plan`.
- The ledger's markdown-file class and "advisory, never blocking" trade-off are well-motivated but need the concrete schema/example called out above before planning can rely on them.

**Action:** Revise `design.md` to fix the confirmed status-source defect in Components §4 (read from `spec.md` frontmatter, handle archived location) — this is required before any `spec:plan` derived from this design. While in there, fold in the should-fix items (idempotency window, richer `in_flight`/`blocked` schema, concrete `ledger.md` example, conductor entry-command surface, `find-workspace-root` consumer list) since they're cheap now and materially de-risk planning. Leave the defer-to-plan/spike items as tracked follow-ups. Then resolve the Open Questions §1 staging decision via `arch:review`/`arch:decide` as already flagged in the design, since it is a hard gate before `spec:plan` regardless of this review.
