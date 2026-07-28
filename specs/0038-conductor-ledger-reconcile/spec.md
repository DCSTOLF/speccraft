---
id: "0038"
title: "Conductor primitives: ledger.md + reconcile rollup"
status: closed
created: 2026-07-28
authors: [claude]
packages: []
related-specs: []
informed-by: [design/0001-architect-lifecycle-orchestration]
design: 0001-architect-lifecycle-orchestration
---

# Spec 0038 — Conductor primitives: ledger.md + reconcile rollup

## Why

Design 0001's conductor (the `/speccraft:arch:orchestrate` command — Spec 0039)
must durably track per-member lifecycle progress and compute a design's rollup
status across member repos. This spec ships the two Go/testable **primitives**
that command will stand on — the `ledger.md` reader/writer and the `reconcile`
rollup — before any orchestration exists, exactly as Spec 0037 shipped the
topology primitives before this.

Everything here is advisory and non-blocking (design 0001): the ledger is a
`history.md`-class markdown memory file written directly by the conductor
(deliberately **outside** the `state.json` single-writer rule), and reconcile is
read-only — it never mutates a member or gates a spec.

## Context carried from the design decisions (this session)

- **Sliced delivery.** 0038 = these primitives; **0039** = the
  `/speccraft:arch:orchestrate` command + subagent dispatch + the lifecycle state
  machine. Decomposition is **model-drafted / human-confirmed at orchestrate-time**
  (0039), so there is *no* static decomposition parser here.
- **Validation policy (for 0039):** the validate phase's gate is the member's
  test command passing (deterministic); AC-satisfaction is a model-judged
  **advisory** note, never a blocking gate. Built in 0039.
- **Grammar divergence, on purpose.** Design 0001's Data-model shows an
  illustrative markdown *table* with a bare `spec | 0007`. This spec pins a
  parse-friendlier `### <member>` block form and a **full `NNNN-slug` spec-ref**
  (matching Spec 0037's `get-status` contract) — the design explicitly deferred
  "full `ledger.md` grammar" to plan time.

## Layering & conventions (applies to every AC)

- **Pure logic in `tools/internal/speccraft`** returns typed values and `error`s
  and **never prints**; all stdout/stderr/exit contracts are owned by the
  `speccraft-state` cmd layer.
- **`ledger.md` write path:** the canonical writer serializes to
  `<workspace-root>/.speccraft/ledger.md` through the shared **`AtomicWriteFile`**
  seam — **never** `state.json`, so the spec-0012 single-writer rule is untouched.
- **Reconcile keys on `spec.md` frontmatter for STATUS, never `last_completed_phase`.**
  It *does* read the ledger's `blocked` overlay to surface blocked members (design
  §5 failure-isolation) — the prohibition is specifically on treating the ledger's
  `last_completed_phase` pointer as a status. Reconcile takes an **injected status
  resolver** `func(memberRoot, specRef string) (status string, found bool)` so its
  aggregation is pure and table-testable; the cmd layer wires the real dual
  live/`.archive` resolver.
- **Clock seam.** `SetLedgerField` stamps `updated` via an unexported package var
  `ledgerNow` (default `time.Now`), which tests override and restore with
  `t.Cleanup` — the established fault-injection seam shape. It is **not** a
  parameter of the exported `SetLedgerField` signature.
- **Override budget (spec-0018-AC13).** The complete inventory of new *exported*
  `tools/internal/speccraft` symbols — `Ledger`/`LedgerDesign`/`LedgerMember`,
  `ParseLedger`, `SetLedgerField`, `Reconcile`, `Rollup`/`MemberStatus` — lands in
  **one consolidated bootstrap edit** costing a **single** `/speccraft:spec:override`.
  Everything else is **zero** override: the `ledger-set`/`reconcile` subcommands
  ride the `run()` seam; the cmd-side extraction of a shared `resolveSpecStatus`
  (which `get-status` is refactored to call) is a same-package edit justified by
  the just-added *failing* `reconcile`/`ledger-set` cmd tests. **Plan-time
  obligation:** the reconcile/ledger-set cmd RED must be authored and standing
  *before* the `get-status` refactor edit, else that pure refactor has no failing
  sibling and the guard blocks it — the plan sequences this explicitly.

## What

- **`ledger.md` grammar** (the entire accepted subset; a line is read after
  trimming a trailing `\r` and a leading UTF-8 BOM, mirroring `parseFrontmatterBlock`):
  - An optional leading `# `-heading preamble (e.g. `# Ledger`) **before the first
    `## design`** is ignored. Blank lines are ignored everywhere. Any other content
    before the first `## design` is a parse error.
  - `## design <design-id>` at column 0 opens a design section; the id is the
    non-empty remainder after `## design ` (an **empty id** is a parse error). A
    **duplicate `## design`** for one id is a parse error.
  - `### <member-path>` at column 0 opens a member block; the path is the non-empty
    remainder after `### ` (an **empty path** is a parse error). A `###` before any
    `## design`, and a **duplicate `### <member-path>`** within one design, are
    parse errors. Any **non-blank, non-heading content directly under a `## design`
    and before its first `### <member-path>`** (a bare line that is neither a
    `### member` heading nor blank) is a parse error.
  - Any **other heading** (a `##`/`###`/`####…` that is not the two forms above,
    e.g. `## foo`) is a parse error.
  - Inside a member block, a field line is `<key>:<value>` **split on the first
    `:`**; the value is the remainder with **one optional leading space stripped**
    (so `spec: 0007-x`, `spec:0007-x` both yield `0007-x`; an interior `: ` as in
    `in_flight: {phase: plan}` is preserved verbatim after the single-space strip).
    `<key>:` with nothing after is the **empty value** — this is the intentional
    field-**clear** mechanism (0039 clears `blocked` this way). `key ∈ {spec,
    last_completed_phase, in_flight, blocked, updated}` (fixed parsed set; the
    conductor's richer in-flight state is encoded *within* the `in_flight` value).
    **`updated` is conductor-managed** — auto-stamped by `SetLedgerField`, never a
    settable `field`. **First-wins** on a duplicate key. A `<key>:` line **before
    the first `### member`**, an **unknown key**, and any non-blank/non-heading/
    non-`key:` **junk line** inside a block are parse errors.
  - The **`spec:` value is stored verbatim** (a full `NNNN-slug` spec-ref by
    convention); it is **not** shape-validated at parse/set time — an unresolvable
    ref simply classifies **Blocked** at reconcile.
  - Every `ParseLedger` error message carries a stable **`ledger.md: `** prefix +
    a class token, so cmd/consumer assertions can match reliably.
- **`ParseLedger(path) (Ledger, error)`** — reads the grammar into ordered
  `Ledger{Designs []LedgerDesign}`, `LedgerDesign{ID string; Members []LedgerMember}`,
  `LedgerMember{Path, Spec, LastCompletedPhase, InFlight, Blocked, Updated string}`
  (order preserved, unset fields `""`). A **missing file ⇒ empty `Ledger`, nil error**.
- **Canonical writer** (used by `SetLedgerField`): emits, deterministically, an
  `# Ledger\n\n` header, then each design as `## design <id>\n\n`, then each member
  as `### <path>\n` followed by **all five fields in the fixed order** `spec,
  last_completed_phase, in_flight, blocked, updated` (each as `<key>: <value>`, or
  `<key>:` when empty), then one blank line; the file ends in a single `\n`. An
  arbitrary pre-existing preamble is **not** preserved (the writer emits its own
  canonical `# Ledger` header) — documented, since the file is machine-owned.
- **`SetLedgerField(path, designID, memberPath, field, value) error`** — idempotent
  upsert: creates file/design/member as needed and sets exactly `field`
  (validated against the **settable set `{spec, last_completed_phase, in_flight,
  blocked}`** — `updated` and any other value error and write nothing), stamping
  `updated` via `ledgerNow`. If the field **already equals `value`** it is a
  **no-op** (file byte-identical, `updated` unchanged).
- **`Reconcile(ws Ledger, designID string, resolve func(memberRoot, specRef string) (string, bool)) Rollup`**
  — pure aggregation. `Rollup{DesignID string; Members []MemberStatus; Total,
  Closed, Blocked, InProgress int; Done bool}`; `MemberStatus{Member, Spec string;
  Class string /* "closed"|"blocked"|"in-progress" */; Status string /* resolved
  frontmatter status, "" if unresolved */}`.
- **cmd layer:** `resolveSpecStatus(root, ref)` — the real dual `specs/<ref>` →
  `specs/.archive/<ref>` resolver (via `ReadFrontmatterField`), distinguishing
  *resolved* / *not-found* / *no-status-field* so `get-status`'s two messages are
  preserved; `get-status` is refactored to call it (no behavior change). The
  **`reconcile` cmd** resolves the workspace root with **`FindWorkspaceRoot`** from
  the invocation dir, reads `<root>/.speccraft/ledger.md`, and for each member
  calls `resolveSpecStatus(filepath.Join(root, member.Path), member.Spec)`, mapping
  **both** *not-found* and *no-status-field* (and any read error) to `found ==
  false`. `ledger-set` likewise resolves the root and writes `<root>/.speccraft/ledger.md`.

## Acceptance criteria

1. **Ledger parse (fixture table).** `ParseLedger` reads a multi-design,
   multi-member `ledger.md` into the ordered structs (order preserved, unset
   fields `""`), ignoring a leading `# Ledger` preamble and blank lines, tolerating
   a trailing `\r`/leading BOM. A value with an interior `: `
   (`in_flight: {phase: plan}`) and a spaceless `spec:0007-x` both parse correctly.
   **Missing file ⇒ empty `Ledger`, nil error.** **Parse errors** (each a fixture
   row, message carrying the `ledger.md: ` prefix): `###` before any `## design`;
   an unknown `<key>:`; a `<key>:` before the first `### member`; a junk line in a
   block; a duplicate `## design <id>`; a duplicate `### <member>`; an empty design
   id; an empty member path; a non-`design` `##` heading; non-blank content before
   the first `## design`; a bare junk line between a `## design` heading and its
   first `### member`. First-wins on a duplicate key.
2. **Ledger upsert + canonical layout.** `SetLedgerField` creates file/design/member
   as needed, sets exactly `field`, stamps `updated` (fixed via `ledgerNow`); other
   fields/members/designs survive parse→set→parse, including an interior-`: ` value.
   A **golden-output test** pins the canonical serialization of a fresh
   single-member write (header, fixed field order, empty-field `key:` form, final
   newline). **parse→write→parse→write is byte-stable** (canonical-layout
   invariant), and **re-setting a field to its current value is a byte-identical
   no-op** (`updated` unchanged). An **invalid `field`** — outside the settable set,
   **including `updated`** — returns an error and leaves the file **unchanged (or
   uncreated if absent)**, asserted by bytes/existence.
3. **Ledger is not `state.json`.** A test asserts `SetLedgerField` writes only
   `<root>/.speccraft/ledger.md`, never `state.json`; a source-scan (sibling to
   `state_single_writer_test.go`) asserts no ledger write path references
   `state.json`.
4. **Reconcile keys on the resolver, not the pointer.** With a **fake resolver**, a
   `Reconcile` over a ledger whose member `last_completed_phase` disagrees with the
   resolver's returned status reports the **resolver's** value. A **source-scan**
   test additionally asserts the `Reconcile` implementation contains no
   `LastCompletedPhase`/`last_completed_phase` reference (belt-and-suspenders).
5. **Rollup classification + precedence.** `Reconcile` returns a `Rollup` (ordered
   `MemberStatus` + counts) where:
   - a member is **Blocked** if its ledger `blocked` is non-empty **OR** the
     resolver returns `found == false` (not-found / no-status / read error). A
     non-empty `blocked` overlay **wins over** a resolved-`closed` (stale flag keeps
     it Blocked).
   - a non-Blocked member is **Closed** if the resolver status is `closed`/`archived`,
     else **InProgress**. `MemberStatus.Status` carries the resolved frontmatter
     status (`""` when unresolved).
   - classification is mutually exclusive (Blocked→Closed→InProgress), so
     `Done == true` **iff every member classifies Closed** (equivalently zero
     Blocked and zero InProgress).
   - Reconcile **never errors** on a single member and returns a Rollup for an empty
     design (zero members ⇒ `Done`).
6. **Cmd surfaces (run() seam) + get-status regression.**
   - `speccraft-state ledger-set <design-id> <member-path> <field> <value>` resolves
     the workspace root (`FindWorkspaceRoot`), upserts `<root>/.speccraft/ledger.md`,
     exit 0; an invalid `field` (including `updated`) ⇒ non-zero + stderr, nothing
     written.
   - `speccraft-state reconcile <design-id>` prints `done: true|false` then, in
     **ledger order**, one `<status>\t<member>\t<spec-ref>` line per member where
     `<status>` is `MemberStatus.Status` (`draft`…`closed`/`archived`) or the
     literal `blocked` for a Blocked member; exit 0. An empty/absent design ⇒
     `done: true`, zero member lines. A **malformed ledger** ⇒ non-zero + stderr
     (the `ledger.md: `-prefixed `ParseLedger` error) with **nothing on stdout**.
   - `get-status` behaves **identically** after the `resolveSpecStatus` extraction —
     its `not found` and `no status field` messages both preserved (0037's
     regression table stays green).

## Out of scope

- The `/speccraft:arch:orchestrate` command, the lifecycle state machine, subagent
  dispatch with member-scoped cwd, the review→revise loop, human-in-the-loop
  checkpoints — **all Spec 0039**.
- **Decomposition** (design → member briefs): model-drafted/human-confirmed at
  orchestrate-time — 0039. No decomposition parser here.
- **The validate phase** and its tests-green/AC-advisory policy — 0039.
- **Semantic** transitions (which phase advances `last_completed_phase`/`in_flight`,
  when `blocked` is set/cleared) — 0039; 0038 ships only durable field read/write
  (the empty-value clear mechanism is provided, but *when* to clear is 0039's call).
- Spec-ref *shape* validation (stored verbatim; unresolved ⇒ Blocked);
  concurrent-conductor locking; member-path canonicalization beyond spec 0037 —
  0039 / deferred.

## Open questions

_none — the scope is the two primitives; orchestration semantics are 0039._
