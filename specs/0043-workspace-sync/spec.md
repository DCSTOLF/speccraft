---
id: "0043"
title: "workspace sync: membership + ledger drift reconciliation"
status: closed
created: 2026-07-30
authors: [claude]
packages: ["commands", "tools/cmd/speccraft-state"]
related-specs: ["0037", "0038", "0039", "0040", "0042"]
informed-by: [design/0001-architect-lifecycle-orchestration]
---

# Spec 0043 — workspace sync: membership + ledger drift reconciliation

## Why

`/speccraft:sync` keeps a **repo**'s memory true against reality: it drift-scans
`enforce:` rules, runs a memory-keeper audit over recent diffs, and backfills closed
specs into domain files. But at a `kind = "workspace"` root there is no production
code and no `specs/` of its own — the memory that goes stale is the **ledger**
(`.speccraft/ledger.md`) and the **member manifest** (`workspace.yml`).

Today nothing reconciles those. The `/speccraft:arch:orchestrate` conductor keeps the
ledger current *while it runs* (spec 0040's `orch_reentry` adopts a phase that
succeeded-but-crashed on the next re-entry), but a developer who closes a member spec
by hand, runs `/speccraft:spec:implement` directly inside a member, deletes a member
directory, or adds a new child repo leaves the workspace's memory silently wrong until
the next orchestration happens to touch that member. There is no out-of-band "make the
workspace's belief match reality" pass — the workspace analog of `/speccraft:sync`.

This spec adds that pass as the workspace mode of `/speccraft:sync`: detect
**membership drift** (`workspace.yml` ⟷ filesystem) and **ledger drift** (ledger ⟷
member spec reality), present them as confirm-gated proposals, and apply the
tool-managed ledger corrections through the sanctioned writer. It is the reconciliation
counterpart to the conductor's forward drive — the same status↔token machinery, run
out-of-band across every member.

## What

Give `/speccraft:sync` a **kind-branch**. At a `kind = "repo"` root it runs the
existing repo flow unchanged; at a `kind = "workspace"` root it runs a **workspace
reconciliation** that reconciles the workspace's *own* memory (the ledger and the
manifest) against reality. The branch is auto-detected via the spec-0042
`speccraft-state config-kind` oracle — there is no flag, because you are either
standing in a workspace or a repo.

Scope is deliberately the **ledger-drift MVP (drift class B)** plus its cheap companion
**membership audit (class A)**; design-level consolidation/rollup (class C) and
`--recursive` per-member fan-out are explicit follow-ups (see Out of scope). The two
axes:

**Ledger drift (B) is out-of-band re-entry.** The core observation is that spec 0040's
`orch_reentry` already answers "does the member's actual status prove this phase
completed?" — the conductor asks it once, at re-entry, for the in-flight phase. Sync
asks the *same question* for **every** member of **every** design in the ledger,
comparing the member's live spec status (`speccraft-state get-status`) against the
stored ledger pointer. When the answer is `adopt`, the ledger is *behind reality* and
sync proposes the exact `ledger-set` the conductor's adopt-path would have written.
This reuses the tested token machine (`orch_reentry`, `orch_status_token`,
`orch_next_phase`) wholesale — sync adds almost no new comparison logic, only the
enumeration and the confirm-gated apply.

**Decomposition.** Deterministic mechanics live in a new sourceable
`commands/sync.lib.sh` (bats-tested under `tests/hooks/`), which sources the existing
`commands/arch/orchestrate.lib.sh` (token machine) and `commands/init.lib.sh`
(`ws_detect_members`). `commands/sync.md` gains the kind-branch and owns the
confirm-gated apply prompt. One new read-only Go oracle exposes the raw ledger.

- **`speccraft-state ledger-get [<design>]`** (new, `tools/cmd/speccraft-state/`) — the
  missing primitive. `reconcile` emits *computed* member status; nothing exposes the
  *stored* pointer fields sync must diff against. `ledger-get` prints one tab-delimited
  line per member — `<design>\t<member>\t<spec>\t<last_completed_phase>\t<in_flight>\t<blocked>`
  — in ledger order, reading raw `ParseLedger` fields (the readers are untouched; this
  is a new consumer of `ParseLedger`, like `reconcile`). An optional `<design>` filters.
  It rides the `run()` seam (a pre-implementation call is a runtime `unknown subcommand`
  error, not a build failure) → **override budget 0**.
- **`sync_ledger_drift`** — for one member row, emit a drift finding by driving
  `orch_reentry`. For readability the two `orch_reentry` uses (status-vs-pointer and
  in-flight-vs-status) are wrapped in named helpers (`sync_status_ahead`,
  `sync_stale_in_flight`) rather than calling `orch_reentry` inline with two different
  meanings. `stale-in-flight` / `status-ahead` findings carry a structured
  ledger-fix tuple (see below); `dangling-spec` is advisory (never auto-fixed).
- **`sync_membership_audit <root>`** — emit `stale-member` / `unlisted-member` /
  `orphan-ledger-row` **advisory** findings by composing `list-members`,
  `ws_detect_members`, and `ledger-get`. `workspace.yml` is never rewritten.

**Root & kind resolution.** `sync.md` resolves `ROOT="$(speccraft-state find-root)"`
(the nearest `.speccraft/` ancestor) and `KIND="$(speccraft-state config-kind "$ROOT")"`.
`workspace` → workspace reconciliation; `repo` → the existing repo flow. `config-kind`
is strict (spec 0042): a non-zero exit or any value other than `repo`/`workspace`
surfaces the error and stops — sync never guesses a kind.

**Finding schema is data, not a command.** Findings are structured records of exactly
six tab-separated fields — `<class>\t<design>\t<member>\t<field>\t<value>\t<detail>` —
where for the three auto-fixable ledger classes `<field>`/`<value>` name the exact
`ledger-set` target (e.g. `last_completed_phase`/`validated`, or `in_flight`/`` to
clear) and `<detail>` is human display text only; for advisory classes `<field>`/
`<value>` are empty and `<detail>` carries the reason. Apply passes `<field>`/`<value>`
**as argv** to `speccraft-state ledger-set` — sync never reconstructs or `eval`s a
command string from `<detail>`.

**Emitting and parsing the 6-field record.** No field ever contains a tab or newline:
the fixable-class `<field>`/`<value>` are fixed tokens; `<detail>` is single-line with
tabs stripped; a `<value>` cannot carry a tab because a successfully parsed spec-0038
ledger row is tab-free by grammar (constrained member charset, fixed phase tokens,
`phase=… iteration=…` in_flight, short blocked marker). Because meaningful **empty**
fields exist (a clear op has empty `<value>`; advisories have empty `<field>`/
`<value>`), the consumer MUST parse with a delimiter-preserving reader — `awk -F '\t'`
asserting `NF == 6` — **not** bash `IFS=$'\t' read` (tab is IFS-whitespace, so adjacent
tabs collapse and empty columns are lost). A line with `NF != 6` is a defensive
emit-bug signal, surfaced, never applied.

**`malformed-row` is a *semantic* (not parse) advisory.** Two distinct failure levels
are kept separate: (1) **parse-level ledger corruption** — `ParseLedger` cannot read
`ledger.md` at all — makes `ledger-get` exit non-zero with no stdout and **aborts the
whole audit** (AC2). (2) **row-level semantic malformation** — the row *parsed*
cleanly but a value fails the 0040 token machine (an `in_flight` `orch_in_flight_phase`
rejects, or an unknown `last_completed_phase` token) — is raised **downstream by
`sync_ledger_drift`**, not by `ledger-get`, as a `malformed-row` advisory for that one
member; the audit continues. `<detail>` names the offending value (e.g. `in_flight
failed to parse: <raw>` / `unknown last_completed_phase token: <raw>`).

**The tool-managed vs. curated line.** Sync applies (on confirm) only the ledger
corrections — the ledger is a tool-managed memory file whose only sanctioned writer is
`speccraft-state ledger-set` (the byte-safe upsert). Everything touching `workspace.yml`
(add/remove a member) or a spec ref (a dangling pointer) is **advisory** — reported for
a human edit, never auto-applied — because `workspace.yml` is curated and human-owned
(the spec-0042 `--force` preserve contract) and clearing a spec ref would break
conductor re-entry.

**Live-run safety — bounded, not absolute.** Sync takes no OS-level lock against a
running conductor. It reduces the risk two ways: an `in_flight` marker is proposed for
clearing **only** when `orch_reentry` returns `adopt` (the phase's completion is
already reflected in the member's status — crash residue), and every apply re-reads +
re-validates the member row immediately before mutating it (AC10). This is **not**
full concurrency-safety: a residual TOCTOU window remains between that re-read and the
`ledger-set` write. Sync is therefore safe to run **when no orchestration is
concurrently writing the ledger**; running it during a live `arch:orchestrate` is the
user's call, and a true atomic compare-and-set / file lock is a follow-up.

## Drift classes and findings

`sync_ledger_drift` and `sync_membership_audit` emit findings in the structured
`<class>\t<design>\t<member>\t<field>\t<value>\t<detail>` schema above, one per line,
so `sync.md` can render every finding and (for the fixable classes) apply the
`<field>`/`<value>` tuple. The classes:

| Class | Axis | Trigger | `field`/`value` (auto-fix) | Auto-fix? |
|---|---|---|---|---|
| `status-ahead` | ledger (B) | `sync_status_ahead` (`orch_reentry(next_action, status) == adopt` and the implied token ≠ stored `last_completed_phase`) | `last_completed_phase` / `<token>` | ✅ on confirm |
| `stale-in-flight` | ledger (B) | `sync_stale_in_flight` (non-empty `in_flight` and `orch_reentry(in_flight_phase, status) == adopt`) | `in_flight` / `` (clear) | ✅ on confirm |
| `stale-blocked` | ledger (B) | non-empty `blocked` and the member advanced past the pointer (`status-ahead` detected) | `blocked` / `` (clear) | ✅ on confirm |
| `dangling-spec` | ledger (B) | member `spec` set but `get-status` does not resolve it | — | ❌ advisory |
| `malformed-row` | ledger (B) | a *parsed* row whose `in_flight`/`last_completed_phase` fails the 0040 token machine (`orch_in_flight_phase`/`orch_next_phase` rejects the value) | — | ❌ advisory (row isolated) |
| `stale-member` | membership (A) | `list-members` reports a manifest member `missing` | — | ❌ advisory |
| `unlisted-member` | membership (A) | `ws_detect_members` finds a `kind = repo` child absent from the manifest | — | ❌ advisory |
| `orphan-ledger-row` | membership (A) | a ledger member path is not in the manifest | — | ❌ advisory |

A member already at the terminal pointer (`last_completed_phase = validated`, so
`orch_next_phase` yields `done`) has nothing ahead of it and yields no `status-ahead`
finding. A single member's malformed data (`malformed-row`) is isolated: it becomes an
advisory and the audit continues with the other members — one bad row never aborts the
run.

## Acceptance criteria

1. **Kind-branch, auto-detected, repo path unchanged.** `/speccraft:sync` resolves
   `ROOT="$(speccraft-state find-root)"` and `KIND="$(speccraft-state config-kind
   "$ROOT")"`. At `KIND = repo` it runs the existing repo flow (drift scan +
   memory-keeper audit + consolidation backfill) with no behavioral change — a
   repo-root invocation must not enter the workspace branch. At `KIND = workspace` it
   runs the workspace reconciliation instead. `config-kind` is strict (spec 0042): a
   non-zero exit or any other value surfaces the error and stops — sync never guesses a
   kind. No new flag is introduced. The regression fence uses explicit anchors: the two
   branch bodies in `commands/sync.md` are delimited by HTML-comment markers
   `<!-- speccraft:sync:repo -->` and `<!-- speccraft:sync:workspace -->`, and a
   source-scan asserts (a) the `config-kind`/`KIND` guard appears before either anchor,
   (b) the workspace-reconciliation helper calls (`sync_ledger_drift` /
   `sync_membership_audit`) appear only after the `:workspace` anchor, and (c) the
   existing repo-flow steps appear only after the `:repo` anchor — a trivially grep-able
   structural check (per conventions.md structural-over-content), not a whole-file
   parser. Behavioral repo-sync coverage is unchanged.

2. **`ledger-get` raw-dump oracle.** `speccraft-state ledger-get [<design>]` prints one
   tab-delimited line per member —
   `<design>\t<member>\t<spec>\t<last_completed_phase>\t<in_flight>\t<blocked>` — in
   ledger order, reading the raw stored fields from `ParseLedger` (NOT `reconcile`'s
   resolved status). With a `<design>` argument it emits only that design's members. A
   missing `ledger.md` yields zero lines and exit 0 (the spec-0038 lazy-ledger
   contract); a **parse-level** corrupt ledger (`ParseLedger` fails) exits non-zero with
   nothing on stdout (parity with `reconcile`) and aborts the audit. `ledger-get` only
   ever emits successfully-parsed, tab-free rows — row-level *semantic* malformation is a
   downstream `sync_ledger_drift` concern (`malformed-row`), not a `ledger-get` failure.
   It rides the `run()` seam (**override budget 0**) and is unit-tested in Go with
   hermetic fixtures (empty/absent, single-design filter, multi-design, a member carrying
   `in_flight`/`blocked`, and a parse-corrupt ledger → non-zero/empty).

3. **`status-ahead` drift reuses `orch_reentry`, never rewinds.** For a member row,
   `sync_ledger_drift` computes `next_action = orch_next_phase(<stored
   last_completed_phase>)` and consults `orch_reentry "$next_action" "$status"` where
   `$status` is the member's live `get-status`. On `adopt` with
   `orch_status_token("$status")` strictly ahead of the stored pointer it emits a
   `status-ahead` finding whose fix tuple is `last_completed_phase`/`<token>`; on
   `reattempt`, or when the implied token equals the stored pointer, it emits nothing.
   A member already at the terminal pointer (`last_completed_phase = validated`, so
   `orch_next_phase` yields `done`) yields no finding. Sync **never** proposes moving a
   pointer backward. bats-tested for: `closed` status vs stored `planned` (finding →
   `validated`), status equal to the pointer (no finding), a member whose status is
   *behind* the pointer (no finding), and a `validated`-pointer member (no finding).
   Because this AC depends on spec-0040 helper contracts that live in another lib, a
   defensive bats leg pins the two exact values sync relies on — `orch_next_phase
   validated` → `done` and `orch_status_token closed` → `validated` — so a future change
   to the token machine fails loudly here rather than silently mis-detecting drift.

4. **`stale-in-flight` clears only crash residue — conservative under concurrent
   writes.** When a member's
   `in_flight` is non-empty, `sync_ledger_drift` extracts its phase with
   `orch_in_flight_phase` and consults `orch_reentry`. `adopt` (the phase's completion
   is already reflected in the member's status) emits a `stale-in-flight` finding
   proposing to clear `in_flight` (alongside any `status-ahead` advance). `reattempt`
   (the phase is not yet reflected — possibly a live conductor run) emits **no** finding
   and leaves `in_flight` untouched. A malformed `in_flight` value
   (`orch_in_flight_phase` errors) does not abort: the row becomes a `malformed-row`
   advisory and the audit continues with the remaining members. bats-tested for the
   stale case (proposes clear), the live case (untouched), and the malformed case
   (advisory, run continues).

5. **`stale-blocked` clears only a resolved block.** When `blocked` is non-empty and the
   same member exhibits `status-ahead` (its live status advanced past the stored
   pointer, i.e. a clean re-attempt happened out of band), `sync_ledger_drift` emits a
   `stale-blocked` finding proposing to clear `blocked`. A member that is `blocked` with
   no forward progress emits no `stale-blocked` finding. bats-tested for both.

6. **`dangling-spec` is advisory, never auto-cleared.** When a ledger member's `spec`
   ref does not resolve via `get-status` in the member repo (dir/spec deleted or
   renamed), `sync_ledger_drift` emits a `dangling-spec` **advisory** finding — reported
   for human resolution and never auto-fixed (clearing a `spec` ref would break
   conductor re-entry, spec 0040). A member whose `spec` resolves emits no
   `dangling-spec` finding. bats-tested for both.

7. **Membership audit is advisory; `workspace.yml` never auto-edited.**
   `sync_membership_audit <root>` composes existing readers to emit three **advisory**
   classes: (a) a manifest member reported `missing` by `speccraft-state list-members`
   → `stale-member`; (b) a `kind = repo` child from `ws_detect_members "$root"` that is
   absent from the manifest → `unlisted-member`; (c) a `ledger-get` member path not
   present in the manifest → `orphan-ledger-row`. All three are advisory — sync never
   rewrites `workspace.yml` (curated/human-owned per spec 0042 AC6). bats-tested for
   each class, including a clean workspace (manifest, filesystem, and ledger agree)
   emitting zero membership findings.

8. **Apply is confirm-gated, ordered, argv-safe, and tool-managed-only.**
   `commands/sync.md`'s workspace branch presents every finding to the human and, on
   confirm, applies **only** the auto-fixable ledger classes through `speccraft-state
   ledger-set`, passing the finding's `<field>`/`<value>` **as argv** — never
   hand-editing `ledger.md` and never reconstructing or `eval`ing a command string from
   `<detail>`. Fixes are grouped **per member** into a *member plan* (AC10): a member's
   multiple fixable findings are applied in the fixed order `status-ahead` →
   `stale-in-flight` → `stale-blocked` (advance the pointer before clearing the residue
   it justifies, mirroring spec 0036's fixed apply order), each with the precondition it
   was *detected* under — the order-dependent preconditions are captured at detection,
   never re-derived from a partially-applied row. Confirmation is **per finding** —
   declining one applies nothing for it and does not suppress the others. Advisory
   findings (`dangling-spec`, `malformed-row`, `stale-member`, `unlisted-member`,
   `orphan-ledger-row`) are reported only, never applied. The deterministic detection
   (AC3–AC7) and the apply guard (AC10) carry the falsifiable coverage; the
   *interactive* prompt/branch wiring in `sync.md` is asserted by the AC1 anchored
   source-scan fence plus an apply-only-fixable / argv-not-eval / advisory-never-applied
   scan — the model-driven prompt itself is credit-gated, per the spec-0042 convention.

9. **Hermetic e2e detect→apply round-trip.** `tests/e2e/workspace_sync_cycle.sh`
   (registered in `tests/e2e/run.sh`) builds a hermetic workspace with a member whose
   spec was closed out of band while the ledger pointer was left at `planned` and
   `in_flight` non-empty, runs `ledger-get` + `sync_ledger_drift`, asserts a
   `status-ahead` (and `stale-in-flight`) finding, applies the proposed `ledger-set`
   calls, and then asserts the mutation **directly via `ledger-get`**:
   `last_completed_phase = validated` and `in_flight` cleared (not via `reconcile`,
   which derives status from the live spec and would pass even if the pointer never
   moved). It additionally asserts `speccraft-state reconcile` prints `done: true` for
   the design — proving the detect→apply loop end to end without model credits.

10. **Per-member plan with one conflict check (conflict-reducing, no lock).** Fixable
    findings are applied as an atomic-in-intent **member plan**, not finding-by-finding:
    detection captures, per member, (i) the member's full ledger row string as the
    *expected snapshot* and (ii) the ordered set of fixable findings with the
    preconditions they were detected under. At apply time sync re-reads the member's row
    **once** via `ledger-get`; only if that row is **byte-identical to the expected
    snapshot** does it apply the plan's confirmed findings in the fixed AC8 order via
    `ledger-set`, advancing its own notion of the expected row after each write (so the
    second and third fixes do not re-check against the pre-apply snapshot and do not
    re-derive their preconditions from the mutated row). If the re-read row differs from
    the expected snapshot (a conductor advanced/replaced it), sync applies **none** of
    that member's plan and reports a single `conflict` — never clearing a newer
    `in_flight`/`blocked`, never rewinding a pointer. This closes the detect→apply race
    pragmatically for the single-writer human workflow without an OS-level lock (a
    genuine atomic compare-and-set is a follow-up; see Out of scope). bats-tested: (a) a
    member with all three fixable findings, all valid at detection, applies pointer
    advance + `in_flight` clear + `blocked` clear in order **without self-conflict**;
    (b) a member whose row is mutated between detection and apply has its whole plan
    skipped with a `conflict` report and the ledger left byte-unchanged.

## Out of scope

- **Design-level consolidation / rollup (drift class C)** — folding a fully-`done`
  design into workspace `history.md` and archiving its ledger rows. This is the
  deliberate follow-up spec (the C-after-B sequencing agreed at design time, mirroring
  how 0040 followed 0039).
- **`--recursive` per-member fan-out** — running `/speccraft:sync` inside each member
  repo and aggregating. The default reconciles workspace-own memory only; recursion is
  deferred.
- **Auto-editing `workspace.yml`** — membership drift (class A) is advisory; adding an
  `unlisted-member` or removing a `stale-member` stays a human edit (spec-0042 curated
  manifest contract).
- **Auto-clearing a `dangling-spec` ref** — reported, never rewritten (would break
  conductor re-entry).
- **Any change to the ledger reader/writer or resolver** (`ParseLedger`,
  `SetLedgerField`, `Reconcile`, `resolveSpecStatus`) or to the 0040 token machine —
  this spec only *reads* via the new `ledger-get` oracle and *writes* via the existing
  `ledger-set`, and reuses `orch_reentry`/`orch_status_token`/`orch_next_phase`
  unchanged.
- **A true atomic compare-and-set / OS-level lock against a live orchestration** — sync
  is *conservative* by construction (AC4 never clears a not-yet-reflected `in_flight`)
  and additionally re-reads + re-validates each row immediately before mutating it
  (AC10), skipping with a `conflict` report if it changed — this *reduces* the race but
  is not concurrency-safety. A narrow TOCTOU window remains between that re-read and the
  `ledger-set` write, so sync is safe only under the no-concurrent-writer assumption;
  closing the window fully (a file lock or an atomic CAS `ledger-set --expect`) is a
  follow-up. Running sync concurrently with an active `arch:orchestrate` is the user's
  call.

## Open questions

_none_
