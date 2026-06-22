---
spec: "0022"
title: "Optional PM and Architect workflows upstream of specs"
reviewers: [codex, claude-p]
quorum: 1
quorum-status: "MET (2/2 approve-with-comments)"
verdict: approve-with-comments
generated: 2026-06-21T00:00:00Z
round: 3
status-transition: "reviewed (held)"
---

# Cross-model review — 0022 (Round 3)

## codex

**Verdict:** approve-with-comments (UPGRADED from round-2 changes-requested)

Concerns:
- AC3 is over-broad: "Writing files under product/ or design/ is exempt" reads as a directory-prefix TDD bypass that would accidentally allow source files placed under those trees. The intended behavior is narrower: markdown PM/Architect artifacts are already non-source and allowed via the existing doc-zone rule. Rewording must pin existing behavior without granting a blanket product/design source-file exemption.
- AC4 and AC5 still partially depend on model-generated content outcomes where structural predicates are required (convention from specs 0014, 0017, 0020).
- pm-critic and arch-critic are acceptable provided they remain thin mirrors of spec-critic — cheap self-checkers invoked before *:review, not a second review quorum. Acceptance must be narrow: frontmatter contract, agent presence, invocation-before-review, stage-specific checklist output.

Suggestions:
- Reword AC3 as a regression pin scoped to markdown: add a files_test.go row asserting IsAlwaysAllowed("product/<id>/brief.md")==true and the design/ equivalent. Do not add a broad directory-wide source bypass.
- Convert AC4 to structural predicates in the plan: memory-keeper invoked (verifiable via call log or stub), ADR header/section shape present in history.md (reuse the contains_adr assertion pattern from spec 0014), diff proposed-not-applied verifiable via file-unchanged-until-confirm, no write on decline.
- Convert AC5 to structural predicates in the plan: informed-by frontmatter key present and non-empty in the generated spec, generated spec file exists, active_spec set, plain spec:new byte-identical with no informed-by key.

Guardrail violations:
- AC3 — must not introduce a broad source-file bypass under product/ or design/; non-source markdown already allowed is fine, but the current wording is wider than intended.

Convention violations:
- AC4 and AC5: structural-over-content convention (specs 0014, 0017, 0020) not yet met at the predicate-binding layer.

---

## claude-p

**Verdict:** approve-with-comments (held from round 2)

Concerns:
- IMMUTABILITY OVERCLAIM (new this round, highest priority): the Lifecycle section states a closed brief or design is "immutable like a closed spec", but AC3's doc-zone exemption makes everything under product/ and design/ always-allowed via IsAlwaysAllowed. Closed-spec immutability is enforced by a TARGETED guard predicate, not the general doc-zone gate. As written, closed-artifact immutability is advisory-only while the spec claims parity with an enforced property. The plan must pick one path: (i) soften the language to "immutable by convention" and remove the "like a closed spec" comparison, OR (ii) extend the closed-immutability guard predicate to cover product/ and design/ and add an AC pinning it. This is the single most important plan-phase decision introduced in round 3.
- Scope has grown, not split: 8 commands, 4 agents, 2 directory trees, 2 state keys, memory routing, and --from. The carry-forward "phased implementation" recommendation from prior rounds is now MANDATORY at plan stage, not optional.
- pm:prioritize and arch:decide, and the draft->prioritized and draft->decided transitions named in the Lifecycle section, have no acceptance criterion — 2 of 8 commands and 2 status transitions are unpinned.

Suggestions:
- Resolve the immutability overclaim before or during planning: soften the spec language OR add a targeted guard + AC; do not leave the contradiction between the Lifecycle prose and the actual enforcement mechanism.
- Reframe AC3 as a regression pin: files_test.go row asserting IsAlwaysAllowed("product/<id>/brief.md")==true and the design/ equivalent; do not grant a directory-wide source bypass.
- Bind AC4 and AC5 to structural predicates in the plan (memory-keeper diff/ADR-append call shape; informed-by frontmatter key present and non-empty; plain spec:new byte-identical); do not grep model prose.
- Add explicit empty-tree base case for ID allocation: first pm:new with no product/ directory present yields 0001; AC2 implies but does not state this.
- Clarify or defer roadmap.md: it is scaffolded as "optional" yet roadmap management is out of scope; state what writes or consumes it in the initial phase or defer it explicitly.

Convention violations:
- recent-specs-are-single-concern: one spec carries 8 commands, 4 agents, 2 trees, 2 state keys, memory routing, and --from. Not a blocker given prior round history, but phased implementation is mandatory.

---

## Synthesis

### Resolved this round

**Lifecycle gap closed (codex round-2 blocking item).** The new Lifecycle section provides close semantics, per-lane state clearing, closed-artifact immutability claims, --from on closed artifacts, and dangling informed-by handling. This is explicit enough to implement and test structurally. codex upgrades from changes-requested to approve-with-comments on this basis.

**AC8 pins the informed-by advisory guarantee.** The new AC8 asserts that --from accepts a closed brief and that a missing or deleted referent never blocks spec:new. This is the strongest addition in round 3 and was specifically called out by claude-p as the best new AC.

**OQ3 settled — critic pair accepted by both agents.** pm-critic and arch-critic are accepted on parity grounds: they mirror the existing spec-critic pattern (cheap self-checkers before *:review) and do not constitute a second review quorum. Both agents withdraw prior objections on this basis.

### New this round — must address in the plan

**IMMUTABILITY OVERCLAIM (claude-p, highest priority).** The Lifecycle section claims a closed brief or design is "immutable like a closed spec." Closed-spec immutability is backed by a targeted guard predicate. The doc-zone exemption (IsAlwaysAllowed on product/ and design/) does not enforce immutability — it does the opposite. As written, the immutability claim is advisory only, while the spec implies it is enforced. The plan must resolve this before implementation begins. Two valid paths:

- (i) Soften the Lifecycle language to "immutable by convention" and remove the "like a closed spec" comparison, acknowledging there is no enforcement predicate for upstream artifacts.
- (ii) Extend the closed-immutability guard predicate to product/ and design/ paths, and add an AC pinning that a write to a closed brief or closed design is rejected by the guard.

Neither path is obviously wrong; the author must choose deliberately. This is the single most important decision introduced by round 3.

### Carry-forward — now binding on the plan

The following items were raised in prior rounds and remain unresolved. They are no longer advisory; the plan must address each one.

**AC3: regression pin, not a broad exemption (both agents, guardrail flag from codex).**
The current wording "Writing files under product/ or design/ is exempt" is a directory-prefix bypass that would accidentally permit source files placed in those trees. The correct artifact is a files_test.go table row: `IsAlwaysAllowed("product/<id>/brief.md") == true` and the design/ equivalent. The plan must not add a directory-wide source bypass; the markdown doc-zone allowance already holds via the *.md rule and requires only a regression pin.

**AC4 and AC5: structural predicates required (both agents, convention violation).**
Both agents flagged these in round 1. They carried forward through round 2. The plan must commit to structural-predicate bindings:

- AC4: memory-keeper invoked (verifiable via call log or stub); ADR header/section shape present in history.md (reuse the contains_adr assertion pattern from spec 0014); diff proposed-not-applied verifiable via file-unchanged-until-confirm; no write on decline.
- AC5: informed-by frontmatter key present and non-empty in the generated spec; generated spec file exists; active_spec set; plain spec:new with no --from produces output byte-identical to current behavior with no informed-by key.

Do not grep model-generated prose at the assertion layer.

**Phased implementation is mandatory (both agents).**
The spec's surface is: 8 commands, 4 agents, 2 directory trees, 2 state keys, memory routing, and --from. Phasing is no longer a recommendation; it is required for the plan to be credible. Suggested phasing for the tdd-planner:

- P1: Go struct changes, getter/setter cases, single-writer allow-list extension, directory-tree scaffolding, doc-zone regression pin (AC1, AC3, AC6, AC7 assertions). First independently verifiable slice.
- P2: Authoring commands (pm:new, pm:revise, pm:close, arch:new, arch:revise, arch:close), pm-critic and arch-critic agents, review integration.
- P3: --from/informed-by linkage (spec:new --from, AC5, AC8), memory-bridge routing (AC4).

**Missing ACs: pm:prioritize, arch:decide, and the associated status transitions (claude-p).**
The Lifecycle section names draft->prioritized and draft->decided as valid status transitions, but pm:prioritize and arch:decide have no acceptance criterion. Two of 8 commands and 2 status transitions are entirely unpinned. The plan must add ACs for these before the task list is finalized.

**Scope of pm-critic and arch-critic acceptance must remain narrow (codex).**
These agents must be scoped to: frontmatter contract validation, agent-presence assertion, invocation-before-review check, and stage-specific checklist output. They must not function as a second review quorum.

**Minor: empty-tree ID base case (claude-p).**
AC2 implies but does not state the behavior when product/ does not yet exist. State explicitly: first pm:new with no product/ directory yields 0001. Add to AC2 or the Lifecycle text.

**Minor: roadmap.md ambiguity (claude-p).**
roadmap.md is scaffolded as "optional" but roadmap management is out of scope. The plan must either state what writes or consumes it in the initial phase, or defer it explicitly to a named future spec.

---

## Recommended next step

Proceed to `/speccraft:spec:plan` for spec 0022. The status is already "reviewed", so the author may optionally tighten the spec text first (resolving the immutability overclaim wording and adding pm:prioritize/arch:decide ACs) before invoking the planner. Either way, the planner is REQUIRED to address the following before the task list is final:

(a) Resolve the immutability overclaim: choose softened language ("by convention") OR extend the closed-immutability guard predicate to product/design and add an AC pinning it. This is the single most important plan-phase decision from round 3.

(b) Make AC3 a markdown-scoped regression pin: files_test.go row asserting IsAlwaysAllowed for product/<id>/brief.md and design/ equivalents; no directory-wide source bypass.

(c) Give AC4 and AC5 structural predicates as specified above: ADR header shape in history.md via contains_adr pattern; informed-by key present and non-empty; file-unchanged-until-confirm; plain spec:new byte-identical; no prose grep.

(d) Add acceptance criteria for pm:prioritize and arch:decide, and assert the draft->prioritized and draft->decided status transitions.

(e) Produce the explicit P1/P2/P3 phasing in the task list; phasing is mandatory given scope.

(f) Add the empty-tree ID base case to AC2 or Lifecycle text: first pm:new with no product/ directory yields 0001.

(g) Resolve roadmap.md: state what writes or consumes it in P1, or defer explicitly to a named future spec.

---

## Prior rounds (superseded)

- **R1**: changes-requested (codex) / changes-requested (claude-p). Quorum not met. Blockers: OQ1 (core vs opt-in architecture fork) and OQ2 (state shape vs byte-compatibility contradiction).
- **R2**: changes-requested (codex) / approve-with-comments (claude-p). Quorum met (1/1 approve-with-comments threshold). OQ1 and OQ2 resolved; lifecycle contract and OQ3 (critic pair) carried forward as open items. Full text preserved in git history.
- **R3**: This document. Both agents approve-with-comments. Lifecycle gap closed; AC8 added; OQ3 settled. New: immutability overclaim (must resolve in plan). Carry-forward items from R2 are now binding on the plan.
