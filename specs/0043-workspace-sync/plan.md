---
spec: "0043"
---

# Plan — 0043 workspace sync: membership + ledger drift reconciliation

Test-first (RED→GREEN→REFACTOR). **Override budget: 0.** The only Go surface
(`ledger-get`) rides the `run()` seam — a pre-implementation call is a runtime
`unknown subcommand` error (not a build failure), so its RED is a passing test file
asserting non-zero+message. All shell (`commands/sync.lib.sh`) and markdown
(`commands/sync.md`) are ungated by the TDD guard; `bats` is their RED oracle. No
production edit requires an override.

## Surfaces

- **Go:** `speccraft-state ledger-get [<design>]` — new read-only oracle in
  `tools/cmd/speccraft-state/` (dispatch in `main.go` + a `ledger_get_cmd.go` using
  `speccraft.ParseLedger`; readers untouched). Unit-tested in
  `ledger_get_cmd_test.go`.
- **Shell:** `commands/sync.lib.sh` (new) — pure helpers, sourcing
  `commands/arch/orchestrate.lib.sh` (token machine) and `commands/init.lib.sh`
  (`ws_detect_members`). Bats: `tests/hooks/sync-workspace.bats`.
  - `sync_status_ahead` / `sync_stale_in_flight` — readability wrappers over
    `orch_reentry`.
  - `sync_ledger_drift` — per-member finding emitter (status-ahead / stale-in-flight /
    stale-blocked / dangling-spec / malformed-row) in the 6-field record.
  - `sync_membership_audit <root>` — stale-member / unlisted-member / orphan-ledger-row.
  - `sync_apply_member_plan` — the AC10 per-member plan with one conflict check.
- **Markdown:** `commands/sync.md` — kind-branch (`config-kind`) with
  `<!-- speccraft:sync:repo -->` / `<!-- speccraft:sync:workspace -->` anchors +
  confirm-gated apply. Source-scan tested in the bats suite.
- **E2E:** `tests/e2e/workspace_sync_cycle.sh` registered in `tests/e2e/run.sh`.

## Reuse (no new logic)

`orch_reentry`, `orch_status_token`, `orch_next_phase`, `orch_in_flight_phase`
(0040 token machine); `list-members`, `get-status`, `config-kind`, `find-root`,
`ledger-set` (state CLI); `ws_detect_members` (init.lib.sh). The status↔token
comparison is expressed entirely through `orch_reentry` — sync adds enumeration,
the finding record, membership diffing, and the confirm-gated apply.

## Steps

1. **RED** (T1) `ledger_get_cmd_test.go`: `ledger-get` on absent/empty ledger → 0
   lines, exit 0; single-design filter; multi-design (design column); a member with
   `in_flight`/`blocked` populated; a parse-corrupt ledger → non-zero + empty stdout.
2. **GREEN** (T2) implement `ledger-get` (dispatch + `ledgerGetCmd` via `ParseLedger`,
   `<design>\t<member>\t<spec>\t<last_completed_phase>\t<in_flight>\t<blocked>`), usage
   line, bump nothing. (AC2)
3. **RED** (T3) `sync-workspace.bats`: self-location (`sync.lib.sh` sources cleanly and
   locates its siblings, per spec 0029) + defensive 0040-contract legs
   (`orch_next_phase validated`→`done`, `orch_status_token closed`→`validated`).
4. **GREEN** (T4) create `commands/sync.lib.sh` scaffold: robust self-location, source
   `orchestrate.lib.sh` + `init.lib.sh`, define a `sync_error` + the 6-field record
   emit helper. (supports AC3)
5. **RED** (T5) status-ahead legs (AC3): `closed` vs stored `planned` → one
   `status-ahead` finding with fix tuple `last_completed_phase`/`validated`; status ==
   pointer → none; status behind pointer → none; `validated` pointer → none. Assert the
   emitted line has exactly 6 tab fields via `awk -F '\t' 'NF==6'`.
6. **GREEN** (T6) implement `sync_status_ahead` + status-ahead emission in
   `sync_ledger_drift`. (AC3)
7. **RED** (T7) stale-in-flight legs (AC4): stale (`in_flight` completion reflected in
   status) → `stale-in-flight` clear finding (empty `<value>` column preserved under
   `awk -F '\t'`); live (`in_flight` not yet reflected) → untouched/none; malformed
   `in_flight` → `malformed-row` advisory and the audit continues to the next member.
8. **GREEN** (T8) implement `sync_stale_in_flight` + `malformed-row` isolation. (AC4)
9. **RED** (T9) stale-blocked + dangling-spec legs (AC5/AC6): `blocked` + status-ahead →
   `stale-blocked` clear; `blocked` + no progress → none; unresolvable `spec` ref →
   `dangling-spec` advisory; resolvable ref → none.
10. **GREEN** (T10) implement stale-blocked + dangling-spec branches in
    `sync_ledger_drift`. (AC5/AC6)
11. **RED** (T11) `sync_membership_audit` legs (AC7): manifest member `missing` →
    `stale-member`; `ws_detect_members` child absent from manifest → `unlisted-member`;
    `ledger-get` path not in manifest → `orphan-ledger-row`; clean workspace → zero
    findings.
12. **GREEN** (T12) implement `sync_membership_audit` composing `list-members` +
    `ws_detect_members` + `ledger-get`. (AC7)
13. **RED** (T13) member-plan / conflict-guard legs (AC10): one member with all three
    fixable findings valid at detection → `sync_apply_member_plan` emits `ledger-set`
    calls in fixed order `status-ahead → stale-in-flight → stale-blocked` with no
    self-conflict; a member whose row is mutated between detection and apply → whole
    plan skipped with a `conflict` report and the ledger byte-unchanged.
14. **GREEN** (T14) implement `sync_apply_member_plan`: capture expected-snapshot +
    ordered findings at detection, one re-read/byte-compare at apply, ordered
    `ledger-set` via argv, advancing the expected row per write. (AC8/AC10)
15. **RED** (T15) `sync.md` source-scan legs (AC1/AC8): `config-kind`/`KIND` guard
    precedes both anchors; `sync_ledger_drift`/`sync_membership_audit` appear only after
    `<!-- speccraft:sync:workspace -->`; repo-flow steps only after
    `<!-- speccraft:sync:repo -->`; apply is argv-to-`ledger-set` (no `eval`); advisory
    classes never passed to `ledger-set`.
16. **GREEN** (T16) wire `commands/sync.md`: add the kind-branch + anchors + workspace
    reconciliation runbook + confirm-gated apply; leave the repo flow textually intact
    under `<!-- speccraft:sync:repo -->`. (AC1/AC8)
17. **REFACTOR** (T17) fold any duplicated finding-emit/awk-parse into one helper; tidy
    `sync_error`/usage; no behavior change (suites stay green).
18. **E2E** (T18) `tests/e2e/workspace_sync_cycle.sh`: hermetic workspace, a member spec
    `closed` out of band with the ledger left at `planned` + non-empty `in_flight`; run
    `ledger-get` + `sync_ledger_drift`; assert `status-ahead` + `stale-in-flight`; apply
    the plan; assert **via `ledger-get`** `last_completed_phase=validated` + `in_flight`
    cleared, and `reconcile` → `done: true`. Register in `run.sh`. (AC9)

## Falsifiable coverage map

- AC1 → T15/T16 (anchored source-scan) · AC2 → T1/T2 (Go) · AC3 → T5/T6 (+T3 defensive)
- AC4 → T7/T8 · AC5,AC6 → T9/T10 · AC7 → T11/T12 · AC8 → T13/T14/T15
- AC9 → T18 (e2e) · AC10 → T13/T14
- The model-driven interactive prompt in `sync.md` is credit-gated (source-scan fence
  only), per the spec-0042 convention.
