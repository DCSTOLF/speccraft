---
spec: "0040"
---

# Tasks

- [x] T1 — bats RED: orch_status_ordinal table + unknown-errors (AC1)
- [x] T2 — lib GREEN: implement orch_status_ordinal (AC1)
- [x] T3 — bats RED: orch_status_token table + ""/blocked/unknown-errors (AC1, direct)
- [x] T4 — lib GREEN: implement orch_status_token (AC1)
- [x] T5 — bats RED: orch_phase_completion_status table + unknown-errors (AC1, direct)
- [x] T6 — lib GREEN: implement orch_phase_completion_status (AC1)
- [x] T7 — bats RED: orch_reentry matrix + load-bearing rows + never-adopt(""/blocked) (AC2)
- [x] T8 — lib GREEN: implement orch_reentry via ordinal comparison (AC2)
- [x] T9 — bats RED: orch_in_flight_phase bare/positional/first-wins/malformed (AC4)
- [x] T10 — lib GREEN: implement orch_in_flight_phase (AC4)
- [x] T11 — bats RED: orch_find_member_spec fixtures — match/archive/zero/dup/read-fail/form-miss (AC3)
- [x] T12 — lib GREEN: implement orch_find_member_spec (exit-code-vs-empty read-fail detection) (AC3)
- [x] T13 — bats RED: orchestrate.md re-entry contract greps (AC5)
- [x] T14 — runbook GREEN: idempotent seeding + resume + new-first adoption + orch_reentry + structured in_flight (AC5)
- [x] T15 — e2e RED: mock_phase informed-by stamp + validate/new sentinels + 3 crash legs in fresh mktemp workspaces (AC6)
- [x] T16 — e2e GREEN: drive_member re-entry branch (create-if-absent seed, new-first, orch_reentry) — legs pass (AC6)
- [x] T17 — Refactor (optional): extract _orch_phase_completion_ordinal; full bats + e2e still green
