---
id: "0001"
title: "Architect orchestrates the full spec lifecycle across single- and multi-repo workspaces"
status: closed
created: 2026-07-27
authors: [claude]
---

# Design 0001 — Architect orchestrates the full spec lifecycle across single- and multi-repo workspaces

Architect graduates from an advisory design-writer into a **conductor** that
drives the entire spec lifecycle end-to-end:

```
new → answer-questions → (review → revise)* → plan → implement → validate
```

…for one spec in a single repo, or fanned out across N member repos of a
workspace. It never *bypasses* the existing per-spec commands or the TDD
red→green guard — it **sequences** them, one member repo at a time, and tracks
the result in a ledger.

## Feasibility

Buildable, and mostly by composition rather than new primitives.

- **Root resolution needs no change.** `FindRoot` already returns the nearest
  `.speccraft/` ([root.go:9](../../tools/internal/speccraft/root.go#L9)); that
  boundary owns spec numbering, `state.json`, and memory. Members keep their own
  `.speccraft/`; the guard resolves each edit to its owning member. We add one
  resolver, `find-workspace-root`, layered *above* `FindRoot` — no change to the
  hot path.
- **Dispatch already has a pattern.** `aux-delegator` shells out today; the
  conductor spawns `spec-author`/`tdd-planner`/etc. with **cwd scoped to the
  member repo**, so each member's own `FindRoot` lands artifacts in its own
  `.speccraft/`. Nothing threads an explicit `--root` through every command.
- **The lifecycle is existing commands in sequence.** `spec:new`, `spec:review`,
  `spec:revise`, `spec:plan`, `spec:implement` already exist and are individually
  tested. The new work is the *state machine* that sequences them, decides loop
  exit, and records progress — not re-implementing any step.

Key unknowns / spikes (the Q&A, loop-exit, and validation *policies* are settled
under "Resolved decisions"; these are the remaining *mechanism* unknowns):

1. **cwd-scoped dispatch — confirm.** The `aux-delegator` precedent proves we can
   shell out, but not that `spec-author`/`tdd-planner` spawned with an arbitrary
   member cwd resolve `FindRoot` to that member. Cheap one-shot spike before
   building the conductor.
2. **Decomposition mapping (design → members).** How a workspace design maps to
   per-member briefs is the hardest orchestration unknown. Proposed surface: a
   `decomposition:` block the architect drafts in `design.md` and the human
   confirms (member-path → brief); the conductor consumes it. Spike: whether the
   mapping is model-drafted, fully human-authored, or derived from `workspace.yml`
   scopes. Until resolved, treat decomposition input as human-confirmed data.
3. **"plan ACs checked" mechanism.** *What* counts as validated is decided (tests
   green + plan ACs checked); *how* AC-satisfaction is verified is not — "tests
   green" has a machine surface, "plan ACs checked" is model-driven. Spike the
   check surface (or downgrade AC-checking to advisory if it can't be made
   reliable).
4. **Q&A resume granularity.** A live Socratic interview can be interrupted
   mid-way. Spike whether partial answers persist (resume re-asks only the
   unresolved) or the `answer-questions` phase re-runs whole.

## Components

1. **Workspace topology (Go, table-testable).**
   - `.speccraft/` gains `kind: repo | workspace`. A plain repo or monorepo is
     `kind: repo` — **unchanged from today** (one spec stream, architect
     co-located). Per this design's scoping decision, a monorepo is a single
     `repo`-kind member with one repo-wide spec stream, **not** per-package
     `.speccraft/` roots.
   - A *workspace* is a parent dir over ≥2 repos: `kind: workspace`, holding a
     `members:` manifest, the `design/` tree, and the ledger — but **no specs of
     its own**.
   - New resolver `find-workspace-root`: nearest `kind: workspace` ancestor, else
     fall back to repo-root (a lone repo is "a workspace of one", so architect
     works with zero manifest ceremony). **Consumers: the `arch:*` commands and
     the conductor only.** Hooks and the guard continue to call `FindRoot`
     exclusively — nothing on the Edit/Write hot path calls the new resolver, so
     the "no change to the hot path" claim holds by construction.

2. **The conductor (lifecycle state machine).** Entry surface: a new
   `/speccraft:arch:orchestrate` command (peer of `arch:decide`/`arch:close`),
   with the two mandatory human-in-the-loop checkpoints surfaced as interactive
   prompts and a `--straight-through` flag to run past them. Drives, per member
   spec:
   `new → answer-questions → (review → revise)* → plan → implement → validate`.
   Each phase invokes the existing command/subagent with member-scoped cwd, then
   advances the member's **`last_completed_phase` pointer** in the ledger (single
   pointer + an `in_flight` boolean, not a per-verb enum — see Data model for the
   verb→pointer table). Resumable and idempotent per member: on re-run the
   conductor resumes *at* the phase after `last_completed_phase`; an `in_flight`
   member re-attempts the interrupted phase from scratch (Q&A resume granularity
   is spike #4). Stops at the configured human-in-the-loop checkpoints.

3. **Decomposition + dispatch.** The architect drafts a `decomposition:` mapping
   (member-path → brief) that the **human confirms** before fan-out; the conductor
   consumes it, seeding one member spec per brief stamped `design: <design-id>`.
   Dispatch = spawn the phase's subagent with cwd = member path. The *authoring*
   heuristic for the mapping is spike #2; the conductor treats the confirmed
   mapping as its input.

4. **Ledger + reconcile.** The ledger is a **markdown file** at workspace
   `.speccraft/ledger.md` (memory-file class, like `history.md` — *outside* the
   `speccraft-state` single-writer rule for `state.json`), holding only
   conductor-owned fields: `design-id → [{ member-path, spec-id,
   last_completed_phase, in_flight, updated }]`. It does **not** cache spec
   `status`. `arch:close`/`sync` are the sole authority for the **design rollup**
   status (read-only; member status is written only by the member's own
   `spec:close`): they walk members and read each child spec's real status from
   its **`spec.md` frontmatter** — *not* from `state.json`, which per
   [architecture.md](../../.speccraft/architecture.md) holds only the active-spec
   pointer and TDD session state. Status is written solely by
   `speccraft-state set-status <spec.md>`; reconcile needs the read counterpart,
   so this design **requires a new read-only `speccraft-state get-status
   <spec.md>` subcommand** (there is currently only a writer + the internal
   `currentStatusClosed`). **Dual-location resolution (spec 0025):** a closed spec
   is consolidated by *moving its directory* to `specs/.archive/NNNN-slug/` with
   `status` still `closed`, so reconcile must resolve each child at
   `specs/NNNN-slug/spec.md` **or** `specs/.archive/NNNN-slug/spec.md`. A design
   is *done* when every child spec's frontmatter status is **`closed`** (or
   `archived` — arrives out-of-band, never emitted by the conductor), from the
   existing `draft | reviewed | planned | in-progress | closed | archived`
   vocabulary. Because status is read from the authoritative artifact each time,
   a member closed/archived out-of-band is observed correctly with no ledger
   divergence. The conductor's `validate` phase is **not** a
   member-spec status: on success it culminates in `/speccraft:spec:close`, which
   is what moves the member spec to `closed`. Thus the ledger's
   `last_completed_phase: validated` (conductor's view) and the member's `closed`
   (authority's view) never conflict — reconcile reads only the member's `spec.md`
   frontmatter, never the ledger pointer. Advisory — never gates a member.

5. **Failure isolation + retry.** `blocked` is an **overlay flag** on a member
   (not a lifecycle phase): set when a phase fails (e.g. implement leaves RED) or
   a listed member path is missing. Siblings proceed; the conductor surfaces
   blocked members but does not abort the fan-out. On re-run the conductor
   **re-attempts the failed phase** for a blocked member (it does not skip it the
   way it skips completed phases); a clean attempt clears the flag.

## Data model

- **`.speccraft/` frontmatter** (both kinds): add `kind: repo | workspace`
  (default `repo` when absent → full backward compatibility).
- **`workspace.yml`** (workspace root only) — **the authoritative membership
  list.** Filesystem ancestry only resolves *which* workspace root you are under;
  it never defines membership. A repo physically under the workspace dir but
  absent from `members:` is ignored; a listed `path:` that is missing/moved is a
  `blocked` overlay in the ledger, not a hard error.
  ```yaml
  members:
    - path: ./api      # each has its own .speccraft/ (kind: repo)
    - path: ./web
  ```
- **Ledger** (`ledger.md`, markdown memory file — not `state.json`, so outside
  the single-writer rule). Per-member row fields (conductor-owned only, no cached
  `status` — derived live at reconcile):
  - `member-path`, `spec-id` — stable identity, allocated **before** first
    dispatch (see crash-safety below).
  - `last_completed_phase` — single pointer (table below), not a state enum.
  - `in_flight` — the phase currently executing plus enough to resume it: for the
    `review→revise` loop it carries `{ phase, iteration, awaiting_human }` (a bare
    boolean is too lossy — the loop is multi-step and can pause for escalation);
    empty when idle.
  - `blocked` — overlay: `{ reason, phase }` when a phase failed or a listed
    member path is missing; cleared by a clean re-attempt. Explicitly part of the
    schema.

  Concrete shape (one design, two members, one blocked):
  ```markdown
  ## design 0001-architect-lifecycle-orchestration
  | member       | spec | last_completed_phase | in_flight                          | blocked                    | updated    |
  |--------------|------|----------------------|------------------------------------|----------------------------|------------|
  | ./api        | 0007 | reviewed             | {phase: plan}                      |                            | 2026-07-28 |
  | ./web        | 0012 | implemented          |                                    | {reason: RED, phase: validate} | 2026-07-28 |
  ```

  **Crash safety (idempotency window).** `spec-id` is allocated and written to the
  ledger *before* the phase that creates the spec, and each phase is re-entrant
  against its authoritative artifact: on re-run the conductor inspects the real
  artifact (spec.md existence/status, plan.md, test state) *before* re-attempting,
  rather than blindly replaying `last_completed_phase+1`. This closes the
  "delegated command succeeded but ledger write failed" window (no double-allocate,
  no re-close of an already-`closed` spec).

  `last_completed_phase` is a **single pointer**, not a state enum, drawn from the
  ordered lifecycle:

  | verb (§ lifecycle) | `last_completed_phase` value after it succeeds |
  |---|---|
  | new                | `new` (intentionally the noun; the phase, not a participle) |
  | answer-questions   | `questioned` |
  | review→revise loop | `reviewed`   |
  | plan               | `planned`    |
  | implement          | `implemented`|
  | validate (→ `spec:close`) | `validated` — conductor pointer only; the member spec's real status becomes `closed` |

  A non-empty `in_flight` means the phase *after* the pointer is mid-execution
  (its `phase` field names it). The pointer is the conductor's private progress
  marker; it is **never** read as a spec status (reconcile keys on member
  `spec.md` frontmatter — see Components §4).
- **Member spec frontmatter**: gains `design: <design-id>` back-reference.
- **Workspace `state.json`**: `active_design` (and nothing the conductor writes
  ad hoc) — written **only** through `speccraft-state set`, honoring the
  single-writer guardrail. The ledger, being markdown, is written directly by the
  conductor. Member `state.json` unchanged (`active_spec` stays per member).

## NFRs & trade-offs

- **Advisory, never blocking.** Consistent with today's architect: the conductor
  sequences and tracks but never gates a member's spec flow or the TDD guard.
  Chosen over a "design blocks until children close" model to preserve member
  autonomy and keep single-repo behavior untouched.
- **Idempotent / resumable.** Ledger-driven so a re-run continues from the last
  phase; safe against interruption mid-fan-out.
- **Failure isolation over all-or-nothing.** One blocked member never stalls
  siblings; visibility via ledger rollup.
- **Backward compatible.** Absent `kind:` ⇒ `repo`; absent workspace ⇒ architect
  behaves exactly as it does now. No migration for existing repos.
- **Alternatives weighed:** (a) *Hub repo pointing at siblings* — rejected:
  asymmetric, pollutes one repo's memory, monorepo/multi-repo diverge.
  (b) *Advisory-only linking convention, no orchestration* — rejected as the
  end state (drops the requested lifecycle orchestration) but retained as the
  forward-compatible **stage 1** to de-risk the topology work.

## Deferred to plan / spike time

Surfaced by cross-model review, intentionally *not* designed here (they belong to
implementation planning, and over-specifying them now is premature):

- Full `ledger.md` grammar + a `schema-version` and its parser tests.
- Concurrent-conductor policy (locking / single-run enforcement on one workspace).
- Typed input/output envelopes for phase dispatch (cwd, identifiers, success
  classification, critic verdict, unresolved-Q&A payload, AC evidence,
  retryable-vs-terminal failure).
- Member-path canonicalization: duplicate/overlapping paths, symlink-escape,
  design-id uniqueness.
- Reconcile performance NFR at large member counts (e.g. walking 20+ members on
  every `arch:close`/`sync`).
- Monorepo re-scoping migration note for existing single-repo installs (absent
  `kind:` ⇒ `repo`, so no action required — but state it in release notes).

## Resolved decisions

1. **Interactive Q&A routing — hybrid.** The conductor pre-seeds interview
   answers from the design and surfaces only the unresolved questions per member
   for live Socratic Q&A. Neither fully unattended nor fully manual.
2. **`review → revise` exit — critic `pass`, else escalate.** The loop exits on a
   critic `pass` verdict. When the max-iterations cap is reached *without*
   consensus, the conductor **summarizes the sticking points for human review and
   restarts the loop after the human's input** (rather than force-passing or
   aborting).
3. **"Validated" default — tests green + plan ACs checked; cross-model code
   review optional.** `spec:review-code` is an opt-in extra, not part of the
   default validation gate.
4. **Human-in-the-loop checkpoints.** Two mandatory pauses by default:
   (a) when max `review → revise` iterations are exhausted without consensus
   (the escalation in #2), and (b) **after `plan`, before `implement`** — with an
   optional flag to run straight through both.
5. **Staging — stage-1 (topology) first, conductor second.** This design ships as
   **two specs**, not one arc:
   - **Spec A — workspace topology (foundation):** `.speccraft/ kind:` field,
     `workspace.yml` parsing, `find-workspace-root` resolver, the read-only
     `speccraft-state get-status` reader, and the `design:` linking convention.
     All Go/table-testable, fully backward-compatible (absent `kind:` ⇒ `repo`),
     ships and validates *before* any orchestration exists.
   - **Spec B — the conductor:** lifecycle state machine, `ledger.md`,
     decomposition/dispatch, reconcile, `/speccraft:arch:orchestrate`. Built on
     Spec A's foundation.

## Open questions

_None blocking. Remaining mechanism unknowns are tracked as the numbered spikes
under Feasibility and are resolved during Spec B planning._
