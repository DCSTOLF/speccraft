---
description: "Reconcile .speccraft/ memory with reality. Detect drift. Kind-aware (repo | workspace)."
allowed-tools: ["Read", "Write", "Edit", "Bash"]
---

Reconcile `.speccraft/` memory with reality. This command is **kind-aware**: at a
`kind = repo` root it runs the repo drift/memory audit; at a `kind = workspace` root
it reconciles the workspace's own memory (ledger + member manifest) against reality
(spec 0043).

**IMPORTANT**: Execute ALL steps below using your tools before responding. Do not
describe steps — carry them out. The deterministic workspace logic lives in
`commands/sync.lib.sh` (bats-tested via `tests/hooks/sync-workspace.bats`); source it
before use.

## 0. Resolve root & kind, then branch

```bash
PLUGIN_ROOT="$(speccraft-state plugin-root)"
ROOT="$(speccraft-state find-root)"
KIND="$(speccraft-state config-kind "$ROOT")" || { echo "sync: cannot determine config kind of $ROOT" >&2; exit 1; }
```

`config-kind` is strict (spec 0042): if it exits non-zero or prints anything other
than `repo`/`workspace`, surface the error and stop — never guess a kind. Then dispatch
on `$KIND`: `repo` → the repo flow below; `workspace` → the workspace reconciliation.

<!-- speccraft:sync:repo -->
## Repo mode (`KIND = repo`)

Run a drift scan and a memory-keeper audit pass.

1. Run `speccraft-drift scan-all` over `enforce:`-tagged conventions and
   guardrails. Report violations with file:line references.

2. Invoke the `memory-keeper` subagent in audit mode with:
   - The drift report from step 1
   - `git log --since=<last sync>` (or full log if first sync) for context
   - A sampled list of changed files since last sync

   Propose:
   - New conventions implied by repeated patterns visible in recent diffs
   - Architecture updates implied by new top-level packages
   - Stale entries in conventions.md / architecture.md

3. Present proposals for approval. Apply approved ones.

4. **Retroactive spec-consolidation backfill (confirm-gated, per spec).** Fold any
   closed spec that never went through inline-at-close consolidation into its
   domain file(s). This is the same routing → delta → merge → archive flow that
   `/speccraft:spec:close` runs inline, applied retroactively. Source the helper:

   ```bash
   REPO_ROOT="$(speccraft-state find-root)"
   source "$PLUGIN_ROOT/commands/spec/consolidate.lib.sh"
   CANDIDATES="$(consolidate_backfill_candidates "$REPO_ROOT" | tr '\n' ' ')"
   ORDER="$(consolidate_backfill_order "$REPO_ROOT" "$CANDIDATES")"
   ```

   - **Candidate predicate (location-based, clock-free).**
     `consolidate_backfill_candidates` returns every spec dir still under `specs/`
     with `status: closed` and no `consolidation-skip` marker — subsuming both
     pre-feature specs and specs whose consolidation was declined at close.
   - **Replay order.** `consolidate_backfill_order` orders candidates by
     `.speccraft/history.md` chronology (oldest-first, reusing spec 0024's history
     parser). A candidate whose history entry was compacted out by spec 0024 (no
     parseable `## YYYY-MM-DD … (spec NNNN)` line) falls to a `created:`-then-ID
     bucket ordered LAST — presentation ordering only, not guaranteed closure order.
     PRESENT the full computed `ORDER` to the developer for confirmation before
     running.
   - **Per spec, confirm-gated.** For each candidate in order, propose the same
     routing → delta → merge → archive flow (reusing `memory-keeper` Mode:
     consolidate). On accept, apply and move the dir to `specs/.archive/`. On
     **decline**, write a `consolidation-skip` marker (`touch
     "$REPO_ROOT/specs/<id>/consolidation-skip"`) so the spec is excluded from every
     future run. Each eligible spec is proposed at most once per run; an
     already-archived spec is skipped.

<!-- speccraft:sync:workspace -->
## Workspace mode (`KIND = workspace`)

Reconcile the workspace's own memory — the ledger (`.speccraft/ledger.md`) and the
member manifest (`workspace.yml`) — against reality (spec 0043, drift classes A + B).
Design-level consolidation (class C) and `--recursive` per-member fan-out are NOT part
of this pass. Source the lib:

```bash
source "$PLUGIN_ROOT/commands/sync.lib.sh"   # also sources orchestrate.lib.sh + init.lib.sh
```

### W1. Ledger drift (class B) — detect per member

For every ledger row, compare the stored pointer against the member's live spec
status and emit findings. Capture each member's full `ledger-get` row as its
**expected snapshot** for the conflict-safe apply (W3).

```bash
speccraft-state ledger-get | while IFS= read -r row; do
  design="$(awk -F '\t' '{print $1}' <<<"$row")"
  member="$(awk -F '\t' '{print $2}' <<<"$row")"
  spec="$(awk -F '\t' '{print $3}' <<<"$row")"
  lcp="$(awk -F '\t' '{print $4}' <<<"$row")"
  inflight="$(awk -F '\t' '{print $5}' <<<"$row")"
  blocked="$(awk -F '\t' '{print $6}' <<<"$row")"
  # Resolve the member's live status; resolved=1 iff get-status succeeds.
  if status="$( ( cd "$ROOT/$member" && speccraft-state get-status "$spec" ) 2>/dev/null )"; then
    resolved=1
  else
    status=""; resolved=0
  fi
  sync_ledger_drift "$design" "$member" "$spec" "$lcp" "$inflight" "$blocked" "$status" "$resolved"
done
```

Parse the emitted 6-field records with `awk -F '\t'` asserting `NF == 6` — **never**
`IFS=$'\t' read` (it collapses the empty columns that clear-ops and advisories rely
on). The classes:

- **Auto-fixable (ledger, tool-managed):** `status-ahead`, `stale-in-flight`,
  `stale-blocked` — their `<field>`/`<value>` are the exact `ledger-set` target.
- **Advisory (reported only, never auto-applied):** `dangling-spec`, `malformed-row`
  (semantic, row isolated — the audit continues).

### W2. Membership audit (class A) — advisory only

```bash
sync_membership_audit "$ROOT"
```

Emits `stale-member` / `unlisted-member` / `orphan-ledger-row` — all **advisory**.
`workspace.yml` is curated/human-owned (spec 0042 AC6) and is **never** rewritten by
sync; report these for the developer to edit by hand.

### W3. Present & apply — confirm-gated, tool-managed-only

Present every finding to the developer. On confirm, apply **only** the fixable ledger
classes, grouped per member into an ordered plan and guarded against a concurrent
conductor write:

```bash
# Fixes for one member, in the fixed order last_completed_phase → in_flight → blocked,
# passed as argv (never eval'd). expected_row is the snapshot captured in W1.
sync_apply_member_plan "$ROOT" "$design" "$member" "$expected_row" \
  last_completed_phase=validated in_flight= blocked=
```

`sync_apply_member_plan` re-reads the member's row once and applies the plan only if
it is byte-identical to `expected_row`; if a conductor advanced the row since
detection it emits a `conflict` and applies nothing (never rewinding a pointer or
clearing a newer marker). Advisory findings are reported only. Declining a finding
applies nothing.

> **Live-run note.** Sync re-validates before each write but takes no lock; a narrow
> TOCTOU window remains. Run workspace sync when no `arch:orchestrate` is concurrently
> writing the ledger.

### W4. Design consolidation (class C) — bound the ledger, confirm-gated

After W1–W3 have reconciled the ledger (the ordering is load-bearing — W3's `ledger-set`
fixes must land before W4 decides a design is done), fold every fully-`done` design out of
the live ledger into a durable rollup record, keeping `.speccraft/ledger.md` bounded as
designs accumulate.

```bash
sync_done_live_designs "$ROOT" | while IFS= read -r design; do
  [ -z "$design" ] && continue
  # Present the proposed rollup + the rows that would be archived; apply ONLY on confirm.
  sync_consolidate_design "$ROOT" "$design"
done
```

- `sync_done_live_designs` lists design ids that are both live in the ledger and
  `reconcile`-`done`. Present each to the developer with its proposed
  `design/<id>-<slug>/outcome.md` rollup (via `sync_design_rollup_body`) and the rows to be
  archived; **apply `sync_consolidate_design` only on confirm** — declining leaves
  `ledger.md`, `.speccraft/ledger.archive.md`, and `design/` byte-identical.
- `sync_consolidate_design` writes the fingerprinted `outcome.md` **before** archival and
  archives through `speccraft-state ledger-archive <design> --expect <fp>` — the atomic
  read-verify-splice that appends to `.speccraft/ledger.archive.md` first, then removes the
  rows from `ledger.md`. A conductor that changed the design mid-consolidation makes
  `ledger-archive` return a `conflict` (surfaced, nothing written); the idempotent outcome
  file is corrected on the next run.
- Archival is **one-directional** and confirm-gated; a no-longer-`done` design is never
  proposed. `workspace.yml` and the 0043 passes are untouched.
