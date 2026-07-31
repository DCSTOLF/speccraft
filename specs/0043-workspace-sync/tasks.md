---
spec: "0043"
---

# Tasks

- [x] T1 — ledger-get Go oracle test: absent/empty, design filter, multi-design, in_flight/blocked, parse-corrupt (RED)
- [x] T2 — implement ledger-get subcommand via ParseLedger + run() seam (GREEN, AC2)
- [x] T3 — sync.lib.sh self-location + 0040 helper-contract defensive bats (RED)
- [x] T4 — create commands/sync.lib.sh scaffold: self-locate, source orchestrate/init libs, record emit + sync_error (GREEN)
- [x] T5 — status-ahead bats: closed-vs-planned/equal/behind/validated-pointer + 6-field awk assert (RED, AC3)
- [x] T6 — implement sync_status_ahead + status-ahead emit (GREEN, AC3)
- [x] T7 — stale-in-flight bats: stale/live/malformed-row-isolation + empty-value column (RED, AC4)
- [x] T8 — implement sync_stale_in_flight + malformed-row isolation (GREEN, AC4)
- [x] T9 — stale-blocked + dangling-spec bats (RED, AC5/AC6)
- [x] T10 — implement stale-blocked + dangling-spec branches (GREEN, AC5/AC6)
- [x] T11 — sync_membership_audit bats: stale/unlisted/orphan + clean-zero (RED, AC7)
- [x] T12 — implement sync_membership_audit (GREEN, AC7)
- [x] T13 — member-plan/conflict-guard bats: all-three-in-order + mutated-row conflict skip (RED, AC10)
- [x] T14 — implement sync_apply_member_plan (snapshot + one re-read + ordered argv apply) (GREEN, AC8/AC10)
- [x] T15 — sync.md source-scan bats: anchors + guard precedence + argv-not-eval + advisory-never-applied (RED, AC1/AC8)
- [x] T16 — wire commands/sync.md kind-branch + anchors + workspace runbook (GREEN, AC1/AC8)
- [x] T17 — Refactor: consolidate finding emit/parse + tidy usage (no behavior change)
- [x] T18 — hermetic e2e workspace_sync_cycle.sh + register in run.sh (AC9)
