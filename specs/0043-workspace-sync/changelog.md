# Changelog — 0043 workspace sync: membership + ledger drift reconciliation

**Status:** closed · **Shipped in:** 1.14.0 · **Date:** 2026-07-31

## What shipped

The **workspace mode of `/speccraft:sync`** — the out-of-band reconciliation pass
that makes a workspace root's own memory (the ledger + the member manifest) match
reality, the workspace analog of the repo drift/memory audit. `/speccraft:sync` now
auto-detects `kind` via `speccraft-state config-kind` and branches: `repo` runs the
unchanged repo flow; `workspace` reconciles **ledger drift (class B)** and **membership
drift (class A)**. Design-level consolidation (class C) and `--recursive` fan-out are
the deliberate follow-ups.

The core leverage: **ledger drift is out-of-band re-entry.** Spec 0040's `orch_reentry`
already answers "does the member's live status prove this phase completed?"; sync asks
it for every member of every design, and an `adopt` verdict means the ledger is behind
reality. So the MVP reuses the tested token machine wholesale and adds only enumeration,
the finding record, membership diffing, and a conflict-safe apply.

### Surfaces

- **`speccraft-state ledger-get [<design>]`** (`tools/cmd/speccraft-state/`) — new
  read-only oracle. `reconcile` emits *computed* status; nothing exposed the *stored*
  pointer fields sync must diff against. Dumps
  `<design>\t<member>\t<spec>\t<last_completed_phase>\t<in_flight>\t<blocked>` in ledger
  order (raw `ParseLedger`; readers untouched). Missing ledger → 0 lines/exit 0;
  parse-corrupt → non-zero/empty (parity with `reconcile`). Rides the `run()` seam →
  **override budget 0**.
- **`commands/sync.lib.sh`** (new) — pure helpers sourcing `arch/orchestrate.lib.sh`
  (token machine) + `init.lib.sh` (`ws_detect_members`): `sync_status_ahead` /
  `sync_stale_in_flight` (readability wrappers over `orch_reentry`), `sync_ledger_drift`
  (status-ahead / stale-in-flight / stale-blocked / dangling-spec / malformed-row in a
  6-field record), `sync_membership_audit` (stale-member / unlisted-member /
  orphan-ledger-row, advisory), and `sync_apply_member_plan` (the conflict-safe
  per-member plan).
- **`commands/sync.md`** — kind-branch guarded by `config-kind`, with
  `<!-- speccraft:sync:repo -->` / `<!-- speccraft:sync:workspace -->` anchors; the repo
  flow is textually unchanged. Confirm-gated apply passes `<field>`/`<value>` as argv to
  `ledger-set` (never `eval`).

### Contracts

- **Tool-managed vs. curated line.** Only the three ledger classes are auto-fixable (via
  the sanctioned `ledger-set`). `workspace.yml` (membership) and dangling spec refs are
  **advisory** — reported, never auto-written.
- **Live-run-conservative, not concurrency-safe.** A stale `in_flight` is cleared only
  when `orch_reentry` returns `adopt`; a not-yet-reflected marker (possibly a live
  conductor) is left untouched. Apply re-reads + byte-compares the row once
  (`sync_apply_member_plan`); a row changed since detection → `conflict`, no write. A
  residual TOCTOU window remains (true CAS/lock deferred).
- **Structured findings.** Exactly six tab fields; consumers parse with `awk -F '\t'`
  (`NF==6`), never `IFS=$'\t' read` (which collapses the meaningful empty columns).
- **Parse vs. semantic.** `ledger-get` fails globally only on parse-level corruption;
  a *parsed* row with a bad token-machine value is a per-member `malformed-row` advisory
  (`sync_ledger_drift`), row isolated, audit continues.

### Tests

- `tests/hooks/sync-workspace.bats` — 29 bats (helpers + `sync.md` anchored
  source-scan). `ledger_get_cmd_test.go` (Go oracle). `tests/e2e/workspace_sync_cycle.sh`
  — hermetic detect→apply round-trip asserting the mutation **directly via `ledger-get`**
  (pointer=validated, in_flight/blocked cleared) + `reconcile done: true`. Registered in
  `run.sh`.
- Full suite: `go test ./...` + `go vet` green, **270 bats** green, drift clean, both
  workspace e2e pass. **Override budget: 0.**

## Spec vs shipped — deviations

- **One new `speccraft-state` subcommand (`ledger-get`)** beyond the existing readers —
  anticipated in the spec's What (raw-dump oracle; `reconcile` couldn't expose stored
  pointers). Readers (`ParseLedger`/`Reconcile`) untouched.
- **The interactive apply prompt in `sync.md`** is source-scan-fenced (anchors, guard
  precedence, argv-not-eval, advisory-never-applied) and credit-gated — not executed in
  tests. The detect→apply *mechanism* is proven deterministically by the e2e (per the
  spec-0042 convention).

## Cross-model review — three rounds

codex opened *changes-requested* and drove real hardening (both models converged on the
top issues): the detect→apply race → the AC10 per-member-plan conflict guard;
findings-as-commands → a structured argv-safe 6-field record; the AC8+AC10 self-conflict
→ captured-snapshot batch apply with no precondition re-derivation; TSV empty-field
parsing → pinned `awk -F '\t'`; parse-vs-semantic malformation split; bounded live-run
claim. claude-p approved-with-comments throughout. Full trail in `review.md`.

## Follow-ups / not done

- **Class C — design-level consolidation/rollup** (fold a fully-`done` design into
  workspace `history.md` + archive its ledger rows): the next spec.
- **`--recursive` per-member fan-out**: deferred.
- **True atomic CAS / file lock** (`ledger-set --expect`): closes the residual TOCTOU
  window; deferred.
- **Inline domain consolidation** (close step 9): deferred — 0043 stays a live silo
  under `specs/` for a later `/speccraft:sync` backfill (candidate domain:
  `state-and-config` or `workspace-orchestration`).
