---
id: "0040"
title: "Crash-safe conductor re-entry"
status: closed
created: 2026-07-29
authors: [claude]
packages: []
related-specs: []
informed-by: [design/0001-architect-lifecycle-orchestration]
design: 0001-architect-lifecycle-orchestration
---

# Spec 0040 — Crash-safe conductor re-entry

## Why

Spec 0039 shipped the conductor as an MVP with **resume-at-pointer + `in_flight`
visibility + blocked-clear**, and explicitly deferred *full crash-window
idempotency* — the case design 0001 §Data-model calls out: a phase whose delegated
command **succeeded but crashed before the ledger advanced**. On a naive re-run the
conductor would blindly re-dispatch that `in_flight` phase, risking a
**double-allocated spec** (re-running `new`) or a **re-close of an already-`closed`
spec** (re-running `validate` — which `SetStatus` rejects).

This spec closes that window: on resume, before re-dispatching an `in_flight`
member the conductor **inspects the member's real `spec.md` status** and either
**adopts** the already-done result — jumping the ledger pointer to the artifact's
true position — or **re-attempts**. It never double-allocates and never re-closes,
and it is robust to a member advanced **out-of-band** (status changed outside the
conductor), not just to a single-phase crash.

## Divergence from design 0001 (honest scope)

Design 0001 §Data-model lists two crash-safety mechanisms: (a) *"spec-id allocated
and written to the ledger **before** the phase that creates the spec,"* and (b)
each phase *re-entrant against its authoritative artifact*. **(a) is infeasible
without changing `spec:new`'s allocation contract** — `/speccraft:spec:new` is what
*allocates* the member's `NNNN` (member repos number independently), so the conductor
cannot know the id before dispatch. (The window this closes is specifically
"delegated command succeeded, ledger advance did not.")
0040 delivers **(b) in full** and **supersedes (a)** with post-hoc adoption: after
a crash, `orch_find_member_spec` finds the design-linked spec `spec:new` created and
adopts its ref (no double-allocate); the runbook writes the ref to the ledger **as
soon as it is known**. This spec closes the crash window; it does not deliver literal
id-before-dispatch (which the allocating `spec:new` precludes).

## Nature of this slice (extends 0039 — shell + markdown, not Go)

Additive helpers in `commands/arch/orchestrate.lib.sh` (bats-tested in
`tests/hooks/arch-orchestrate.bats`) + a runbook update to
`commands/arch/orchestrate.md` + crash-safety legs in the hermetic e2e
`tests/e2e/arch_orchestrate_cycle.sh`. It reuses the shipped 0037/0038 primitives
(`get-status`/`get-frontmatter`/`ledger-set`/`reconcile`) unchanged and the 0039
lib. **No Go exported symbols ⇒ no `/speccraft:spec:override`;** bats + the e2e are
the RED oracle.

## The re-entry model

Ordering the member-spec status vocabulary (spec 0037 — `SetStatus` also accepts
`blocked` out-of-band), and mapping each real status to the ledger token it implies:

| status | ordinal | ledger token (`orch_status_token`) |
|---|---|---|
| `""` (get-status resolved nothing) | -1 | — (never adopted) |
| `blocked` | -1 | — (never adopted; a parked spec re-attempts) |
| `draft` | 0 | `new` |
| `reviewed` | 1 | `reviewed` |
| `planned` | 2 | `planned` |
| `in-progress` | 3 | `implemented` |
| `closed` / `archived` | 4 | `validated` |

The status that **proves** each phase completed:

| in_flight phase | completion status | ordinal |
|---|---|---|
| new | draft (a spec exists) | 0 |
| review | reviewed | 1 |
| plan | planned | 2 |
| implement | in-progress | 3 |
| validate | closed | 4 |

**Re-entry rule (`orch_reentry`):** `adopt` iff `orch_status_ordinal(member_status)`
≥ the in_flight phase's completion ordinal, else `reattempt`. On **adopt** the
pointer jumps to `orch_status_token(member_status)` — the artifact's true position
(so an out-of-band multi-phase jump is reconciled, not partially replayed) — and
`in_flight`/`blocked` clear, **without re-dispatching**. On **reattempt**, clear
`in_flight` and re-run the phase. `validate`+`closed`→adopt (no re-close) and
`new`+`""`→reattempt (no spec yet) are the load-bearing cases.

## What — `commands/arch/orchestrate.lib.sh` additions (bats-tested)

- **`orch_status_ordinal <status>`** — echoes the ordinal above: empty `""` → `-1`,
  `blocked` → `-1`; `draft/reviewed/planned/in-progress` → `0/1/2/3`;
  `closed/archived` → `4`. Any **non-empty** status outside the vocabulary →
  `orchestrate_error` (stderr) + non-zero.
- **`orch_status_token <status>`** — echoes the ledger token a *real completion*
  status implies (`draft→new`, `reviewed→reviewed`, `planned→planned`,
  `in-progress→implemented`, `closed→validated`, `archived→validated`); `""`/`blocked`
  /unknown → error (only called on the adopt path, where status is a completion).
- **`orch_phase_completion_status <phase>`** — `new→draft`, `review→reviewed`,
  `plan→planned`, `implement→in-progress`, `validate→closed`; unknown → error.
- **`orch_reentry <in_flight_phase> <member_status>`** — `adopt` when
  `orch_status_ordinal(member_status)` ≥ the phase's completion ordinal, else
  `reattempt`. An unresolved (`""`) or `blocked` member never adopts.
- **`orch_find_member_spec <member-root> <design-id>`** — echoes the `NNNN-slug` of
  the member spec that back-references the design. The key is the
  **`informed-by: [design/<design-id>]`** frontmatter `/speccraft:spec:new --from
  design/<design-id>` actually writes (verified: `spec_new_scaffold` records
  `informed-by`, **not** a bare `design:` field). A candidate matches when its
  `speccraft-state get-frontmatter <spec.md> informed-by` output contains the exact
  substring `design/<design-id>` (full `NNNN-slug`; a `0001` vs `0001-slug`
  mismatch is a defined miss). Scans `specs/*` then `specs/.archive/*`.
  **Zero matches → empty output, exit 0**; **≥2 matches → `orchestrate_error`
  (non-zero)** (an ambiguous adoption key is the very double-allocate this spec
  prevents — surfaced, never silently first-wins); a `get-frontmatter` **read
  failure** on any candidate → `orchestrate_error` (non-zero), so an inconclusive
  scan is never collapsed into a false "zero matches" that would trigger a spurious
  `spec:new`.
- **`orch_in_flight_phase <in_flight_value>`** — extracts the phase:
  - a value with **no `=`** is a bare phase token → echo it verbatim (0039
    compatibility);
  - a value with a **`phase=<p>`** token → echo `<p>` (`phase` may appear in **any
    position** among space-separated `key=value` pairs; on a duplicate `phase=`,
    **first wins**);
  - a value that has `=` tokens but **no `phase=`**, or an empty value → is
    malformed: `orchestrate_error` (stderr) + non-zero (never silently coerced to an
    action). Validating the *phase name* is `orch_reentry`/`orch_completed_token`'s
    job, not this parser's.

## What — `commands/arch/orchestrate.md` runbook update

**Idempotent seeding (restart-safe).** The seed step must be **create-if-absent**:
seed a member row (with empty `spec`) **only when the member is not already in the
ledger for this design**. A re-run must **never re-`ledger-set … spec ""`** on an
existing row — that would erase a `spec` ref captured before the restart and break
re-entry for every later phase.

Before dispatching for a member, **resolve re-entry** from its ledger row. Let
`phase = orch_in_flight_phase "$in_flight"` (empty if idle) and
`status = speccraft-state get-status`. Precedence is **`new`-first**, because the
`new` phase's re-entry key is the artifact's *existence*, not just its status, and
the ledger `spec` ref must be captured:

- **The `new` phase** (resuming an `in_flight=new` **or** starting a member at the
  empty pointer): first `ref="$(orch_find_member_spec "$member_root" "$DESIGN")"`.
  - non-empty → **adopt**: `ledger-set … spec "$ref"` **then**
    `ledger-set … last_completed_phase new`, clear `in_flight`/`blocked` — **no
    `spec:new` dispatch** (this captures the very ref a crash-after-`spec:new`
    dropped, so the ledger `spec` is never left empty).
  - empty → **reattempt**: clear `in_flight`, dispatch `spec:new` **once**, then
    write the returned ref via `ledger-set … spec <ref>` **as soon as it is known**.
- **Any other phase** with non-empty `in_flight`: branch on
  `orch_reentry "$phase" "$status"` — **adopt** → `ledger-set … last_completed_phase
  "$(orch_status_token "$status")"`, clear `in_flight`/`blocked`, **no re-dispatch**;
  **reattempt** → clear `in_flight`, re-run the phase.

For the `review→revise` loop, write `in_flight` in the **structured form**
`phase=review iteration=<n>` so an escalation resumes with its iteration count.

## Acceptance criteria

1. **Status ordinal + phase completion (direct).** `orch_status_ordinal` maps
   `""→-1`, `blocked→-1`, `draft→0`, `reviewed→1`, `planned→2`, `in-progress→3`,
   `closed→4`, `archived→4`; any **non-empty** status outside the vocabulary errors to
   **stderr** + non-zero. `orch_phase_completion_status` is **directly** table-tested
   (`new→draft`, `review→reviewed`, `plan→planned`, `implement→in-progress`,
   `validate→closed`; unknown phase → error) and `orch_status_token` directly
   (`draft→new` … `closed/archived→validated`; `""`/`blocked`/unknown → error) — not
   only exercised transitively through `orch_reentry`. bats tables (incl. `blocked`/`""`).
2. **Re-entry decision + adopt target.** `orch_reentry` echoes `adopt` iff the member
   ordinal ≥ the in_flight phase's completion ordinal, else `reattempt` — pinned over
   every phase and the load-bearing rows **`validate`+`closed`→adopt**,
   **`new`+`""`→reattempt**, `review`+`draft`→reattempt, `implement`+`in-progress`→adopt,
   and the out-of-band **`review`+`closed`→adopt**. `orch_status_token` maps each
   completion status to its token (`in-progress→implemented`, `closed→validated`, …)
   so an adopt after `review`+`closed` yields pointer `validated`, not `reviewed`.
   bats tables.
3. **Crash-safe `new` adoption.** `orch_find_member_spec` returns the `NNNN-slug` of a
   member spec whose frontmatter **`informed-by`** contains `design/<design-id>` (what
   `spec:new --from design/<id>` writes; found in `specs/` **and** in `specs/.archive/`);
   empty (exit 0) when none back-reference it; **errors (non-zero) on ≥2 matches**; and
   **errors (non-zero) on a `get-frontmatter` read failure** (never a false zero-match).
   bats fixtures for all cases, plus a `0001` vs `0001-slug` form mismatch asserted as a
   (defined) miss.
4. **`in_flight` parse (structured + bare, order-tolerant, malformed).**
   `orch_in_flight_phase` extracts `review` from `phase=review iteration=2
   awaiting_human=1`, from `iteration=2 phase=review` (phase not first), from a
   duplicate `phase=review phase=plan` (first wins), and from the bare `review` (0039
   compat); a value with `=` tokens but **no `phase=`** and an **empty** value each
   error (stderr, non-zero). bats.
5. **Runbook re-entry contract.** A structure-grep bats asserts `orchestrate.md`
   documents: **idempotent create-if-absent seeding** (never re-`spec ""` on an
   existing row); reading `in_flight` on resume; `orch_reentry` adopt-vs-reattempt with
   the adopt pointer set via `orch_status_token`; `orch_find_member_spec` adoption for
   `new`; writing the spec-ref to the ledger as soon as known; and writing the
   structured `in_flight` (`phase=… iteration=…`) for the review loop.
6. **Crash-safety e2e (behavioral, direct).** `arch_orchestrate_cycle.sh` gains:
   - a **no-re-close** leg: a member left `in_flight=validate` with its `spec.md`
     already `closed` → the re-entry branch (`orch_reentry`→`adopt`) advances
     `last_completed_phase` to `validated` and `reconcile` shows `done: true`, while a
     **dispatch sentinel** (a counter the validate mock bumps) asserts the validate
     mock was **never invoked** — proving no re-dispatch *structurally*, not only via
     `SetStatus`'s closed-refusal side effect.
   - a **no-double-allocate `in_flight=new`** leg: a design-linked member spec already
     exists on disk (the `new` mock stamps **`informed-by: [design/<DESIGN>]`** — what
     real `spec:new` writes) with the member left `in_flight=new` and the ledger `spec`
     **empty** → the `new`-first re-entry runs `orch_find_member_spec`, adopts the
     existing ref, and asserts: **the ledger `spec` ends non-empty** (== that ref),
     **no second `specs/` directory is created** (dir count), **and** a **`new`-dispatch
     sentinel** (a counter the `new` mock bumps) is **zero** — symmetric to the
     no-re-close leg, proving `spec:new` was not re-dispatched (a dir-count alone can't
     catch a mock that overwrites the same ref).
   Each leg runs in its **own fresh `mktemp` workspace** (scenario isolation — no shared
   ledger/artifacts/counters), and one leg asserts that **an idempotent re-seed does not
   erase a captured `spec` ref** (restart safety).
   The e2e's `drive_member`/`mock_phase` gain the re-entry branch + the `informed-by`
   stamp + the validate/`new` sentinels to run these legs.

## Clarifications & invariants (from cross-model review)

- **`review`+`reviewed`→adopt is correct, not lossy.** `/speccraft:spec:review` sets
  `status: reviewed` **only** on a quorum pass; a changes-requested round leaves the
  spec `draft` (being revised). So `status == reviewed` genuinely proves review
  passed → adopt is right; a mid-loop crash with a pending revise has status `draft`
  → `orch_reentry(review, draft)` → reattempt.
- **`revise` is never a bare `in_flight` phase.** The review loop's `in_flight` is
  always the structured `phase=review iteration=<n>`; `orch_in_flight_phase` of it
  yields `review`. So `orch_reentry`/the completion table never see `revise` (which
  has no completion status by design). A stray legacy `in_flight=revise` is treated
  as malformed by the downstream phase validation, not silently mis-adopted.
- **Crash-resume iteration vs escalation reset.** 0039's "iteration resets to 0 on an
  escalation restart" (a human-driven restart after summarize) is a *different* event
  from a **crash resume**: a crash resume preserves the iteration carried in the
  structured `in_flight`. 0040 does not overturn the 0039 escalation-reset rule.
- **`closed`/`archived` is authoritative proof of all prior obligations.** Adopt
  treats a `closed` artifact as proof every preceding phase completed (the status
  machine only reaches `closed` through the lifecycle), so the pointer jumps straight
  to `validated`.
- **zsh-safety.** The six new helpers return via stdout/exit and never assign a
  zsh/bats-reserved name (`status`), consistent with the 0039 lib and pinned by the
  existing lib-zsh-safety check.

## Out of scope

- Changing any 0037/0038/0039 Go primitive or the 0039 lib helpers' contracts —
  additive only.
- Literal spec-id-**before**-dispatch (infeasible with the allocating `spec:new`;
  superseded by `orch_find_member_spec` adoption — see Divergence).
- The interactive review-loop *content* / real subagent dispatch (the e2e mocks the
  phase effect, as in 0039).
- Concurrent-conductor locking; multi-member-path canonicalization beyond spec 0037;
  version bump / release mechanics.

## Open questions

_none — the re-entry model is a deterministic artifact-ordinal comparison; the
interactive parts stay runbook-documented._
