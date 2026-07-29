---
spec: "0039"
---

# Tasks

- [x] T1 — RED: bats scaffold + orch_next_phase/orch_completed_token phase-machine cases (AC1)
- [x] T2 — GREEN: orchestrate.lib.sh skeleton — orchestrate_error, orch_next_phase, orch_completed_token (AC1)
- [x] T3 — RED: orch_should_pause checkpoint-predicate table (AC2)
- [x] T4 — GREEN: orch_should_pause (AC2)
- [x] T5 — RED: orch_review_verdict pass/revise/escalate table incl. iteration==max boundary (AC3)
- [x] T6 — GREEN: orch_review_verdict (AC3)
- [x] T7 — RED: orch_parse_decomposition fixtures both polarities (indented-# comments, first-tab split, charset incl. literal ') (AC4)
- [x] T8 — GREEN: orch_parse_decomposition (AC4)
- [x] T9 — RED: orch_dispatch six actions (quoted, never --root) + orch_validate true/false stubs (AC5)
- [x] T10 — GREEN: orch_dispatch + orch_validate (AC5)
- [x] T11 — RED: two-member failure-isolation + blocked-clear + phase-walk behavioral bats (built speccraft-state, kind=workspace) (AC6)
- [x] T12 — GREEN: orch_apply_result via ledger-set (advance/clear on success, blocked+clear-in_flight on failure) (AC6)
- [x] T13 — RED: orchestrate.md structure-grep bats (frontmatter, plugin-root sourcing, token order, checkpoints, spec:close, resume/in_flight/blocked, list-members/ledger-set/reconcile) (AC7)
- [x] T14 — GREEN: author commands/arch/orchestrate.md runbook (AC7)
- [x] T15 — REFACTOR (optional): dedupe case maps, confirm error routing + no zsh status shadow
