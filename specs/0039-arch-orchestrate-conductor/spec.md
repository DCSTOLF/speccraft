---
id: "0039"
title: "Architect conductor: /speccraft:arch:orchestrate"
status: closed
created: 2026-07-28
authors: [claude]
packages: []
related-specs: []
informed-by: [design/0001-architect-lifecycle-orchestration]
design: 0001-architect-lifecycle-orchestration
---

# Spec 0039 — Architect conductor: /speccraft:arch:orchestrate

## Why

The **orchestration surface** of design 0001's conductor (Spec B). Specs 0037
(topology primitives) and 0038 (ledger + reconcile) shipped the Go/testable
substrate; this spec ships the `/speccraft:arch:orchestrate` command that drives
the per-member lifecycle across a workspace's member repos, tracking progress in
`ledger.md` and rolling up with `reconcile`.

Consistent with design 0001, orchestration is **advisory and failure-isolated**:
it *sequences* the existing per-spec commands (never bypasses them or the TDD
guard), dispatches each phase into the member repo with **cwd scoped to that
member** (the member's own `FindRoot` resolves — never an explicit `--root`),
**resumes from the ledger pointer** (writing `in_flight` before a dispatch and
clearing it after, so an interrupted member is visible), records a failed member
as `blocked` (cleared on a clean re-attempt) and **continues with its siblings**.

### Scope honesty — this is the orchestration MVP, not full crash-safety

Design 0001's Data-model/NFRs describe a *fully idempotent, crash-safe* conductor
(allocate spec-id strictly before dispatch, inspect the authoritative artifact
before re-attempt) — which design 0001 itself lists as **mechanism spike #1/#4**,
not a settled contract. This spec delivers the deterministic orchestration core +
**resume-at-pointer + `in_flight` visibility + blocked-set/clear**, and
**explicitly defers full crash-window idempotency** (a phase that succeeds but
crashes before the ledger advances) to a tracked follow-up (see Out of scope). It
does **not** claim to close Spec B's crash-safety story.

## Nature of this slice (shell + markdown, not Go)

Following the `arch:*` pattern, the conductor is a `commands/arch/orchestrate.md`
runbook the orchestrator executes, backed by a pure `commands/arch/orchestrate.lib.sh`
of deterministic helpers (bats-tested in `tests/hooks/arch-orchestrate.bats`). The
**testable core is the lib**; the interactive/model-driven parts (the Socratic
interview, decomposition *drafting*, real subagent dispatch) live in the runbook and
are covered by structure/grep assertions + behavioral ledger integration tests. No
new Go exported symbols ⇒ **no `/speccraft:spec:override`**; bats supplies
RED-before-GREEN. The lib routes all errors to **stderr** via a central
`orchestrate_error()` (stdout reserved for structured output, per the
`arch_set_status:`/`ledger.md:` precedent).

## Behavior divergences from design 0001 (on purpose)

- **`answer-questions` is folded into `spec:new`.** The design's separate
  `answer-questions` phase is the Socratic interview, which `/speccraft:spec:new`
  already runs. So the ledger token sequence is `new → reviewed → planned →
  implemented → validated` (five, not six) — the design's `questioned` token is
  subsumed by `new`.
- **`validate` culminates in `/speccraft:spec:close`.** The validate phase runs the
  deterministic tests gate and then closes the member spec via `spec:close`, which
  sets `status: closed` — the status that spec-0038 `reconcile` keys its `Done` on
  (design §4). AC-satisfaction is a *separate* model-judged advisory note, never a
  gate.
- **`--straight-through` covers only the after-plan checkpoint.** Design
  Resolved-decision **4** says "run straight through both"; the escalation
  checkpoint mandates human resolution (Resolved-decision **2** forbids
  force-passing), so suppressing it has no sane semantics. The flag suppresses only
  checkpoint (a).

## Lifecycle, tokens & checkpoints

Ledger `last_completed_phase` tokens: `new → reviewed → planned → implemented →
validated`. The conductor advances a member one token at a time via
`speccraft-state ledger-set`, **resuming** from the current pointer. `revise` loops
**within** the `review` phase and does **not** advance the pointer. Two mandatory
human-in-the-loop checkpoints: **(a)** after `planned`, before implement (suppressed
by `--straight-through`); **(b)** when the `review → revise` loop exhausts `max`
iterations without a critic `pass` (escalate — summarize for the human; on restart
after input the revise iteration count **resets to 0**).

## What — `commands/arch/orchestrate.lib.sh` helpers (bats-tested)

- **`orch_next_phase <last_completed>`** → next **action**: `""→new`, `new→review`,
  `reviewed→plan`, `planned→implement`, `implemented→validate`, `validated→done`.
  Unknown token → `orchestrate_error` (stderr) + non-zero. (This is how the runbook
  resumes: read the pointer, call `orch_next_phase`.)
- **`orch_completed_token <action>`** → the ledger token written back after success:
  `new→new`, `review→reviewed`, `plan→planned`, `implement→implemented`,
  `validate→validated`. (`revise` has no entry — it does not advance the pointer.)
- **`orch_should_pause <next_action> <straight_through>`** → `pause` iff
  `next_action == implement` and `straight_through != 1`; `go` otherwise.
- **`orch_review_verdict <iteration> <max> <critic_verdict>`** → `pass` when
  `critic_verdict == pass`; else `revise` when `iteration < max`; else `escalate`.
  `iteration` = count of **completed** revise cycles (0 at the first review; reset
  to 0 after an escalation restart).
- **`orch_parse_decomposition <file>`** → normalized `<member-path>\t<brief>` lines.
  Grammar: a line whose **first non-whitespace char is `#`** (spaces or tabs before
  it) is a full-line comment; blank lines ignored. Otherwise split on the **first
  tab**: `member-path` = text before it, `brief` = remainder (verbatim, interior
  tabs kept); both trimmed of leading/trailing spaces. Errors (→ `orchestrate_error`
  on stderr, `orchestrate:`-prefixed, non-zero): no tab; empty member-path; empty
  brief; **duplicate member-path**; a member-path not matching the **safe
  relative-path charset `^[A-Za-z0-9._/-]+$`** (rejecting whitespace, quotes — incl.
  `'` — and shell metacharacters so dispatch never eval-injects; consistent with
  0037's bare-path discipline).
- **`orch_dispatch <member-path> <action>`** → the **cwd-scoped** invocation
  `(cd '<member-path>' && <cmd>)` (the member-path is **single-quoted**), mapping the
  action to a real command: `new→/speccraft:spec:new`, `review→/speccraft:spec:review`,
  `revise→/speccraft:spec:revise`, `plan→/speccraft:spec:plan`,
  `implement→/speccraft:spec:implement`, `validate→/speccraft:spec:close`. The output
  **contains `cd '<member-path>'`** and **never** contains `--root`. (Whether the
  *spawned* agent's own `FindRoot` then resolves — design spike #1 — is confirmed at
  the e2e/mock-agent tier, not by this string assertion.)
- **`orch_validate <test_cmd>`** → runs the member's configured test command via
  `sh -c "$test_cmd"` (the command is trusted repo config — the same trust boundary
  the guard's runner uses — not user input), echoing `pass` on exit 0 else `fail`.
  The deterministic gate that precedes `spec:close`.
- **`orch_apply_result <ledger> <design> <member> <action> <exit_code>`** → the
  advisory, failure-isolated ledger transition, written through 0038's `SetLedgerField`
  surface. **`in_flight` is cleared on every completed attempt** (design 0001: a
  non-empty `in_flight` denotes mid-execution, and a finished attempt is not
  mid-execution): on `exit_code == 0`, set `last_completed_phase =
  orch_completed_token <action>`, clear `blocked`, clear `in_flight`; on non-zero,
  set `blocked = "<action> failed"`, clear `in_flight`, leave the pointer where it
  was. Never touches sibling rows.

## What — `commands/arch/orchestrate.md` runbook

Standard command frontmatter (`description`, `argument-hint`, `allowed-tools`);
resolves `PLUGIN_ROOT="$(speccraft-state plugin-root)"` and the workspace root
(`FindWorkspaceRoot`) before sourcing `orchestrate.lib.sh`. Confirms the decomposition
(model-drafted, human-confirmed → `orch_parse_decomposition`) and **seeds member
rows only** — one `ledger-set … <member> spec ""`-style row per confirmed member
(the member-path recorded; **no `spec:new` dispatched at seeding**, so `new` is never
double-dispatched). Then, per member, **resume** via `orch_next_phase(pointer)`: set
`in_flight=<action>`, dispatch cwd-scoped (`orch_dispatch`); the `new` action runs
`spec:new` **once**, capturing the member-allocated `NNNN-slug` ref which is written
via `ledger-set … spec <ref>`; each action's result is applied via `orch_apply_result`
(advance + clear `in_flight`/`blocked` on success, set `blocked` on failure — siblings
continue). The `review` phase loops under `orch_review_verdict`; `validate` gates on
`orch_validate` then dispatches `spec:close`. Honors both checkpoints. Finishes with
`speccraft-state reconcile <design>`.

## Acceptance criteria

1. **Phase machine + resume.** A bats table asserts `orch_next_phase` maps every
   token to the correct next action (`""→new` … `validated→done`), incl. resuming
   from a mid-sequence token (`planned→implement`), and errors to **stderr** +
   non-zero on an unknown token. `orch_completed_token` asserted as its inverse (and
   that `revise` has no token).
2. **Checkpoint predicate.** `orch_should_pause` echoes `pause` **iff**
   `next_action == implement` and `straight_through != 1`; `go` otherwise (incl.
   `implement` under `--straight-through`). bats table.
3. **Review→revise control.** `orch_review_verdict` → `pass` on `pass`; `revise`
   when not-pass and `iteration < max`; `escalate` when not-pass and `iteration >=
   max` (incl. the `iteration == max` boundary). bats table.
4. **Decomposition parse.** `orch_parse_decomposition` echoes normalized member/brief
   lines for valid input (ignoring blanks + full-line `#`, incl. a **tab/space-indented
   `#`**; first-tab split; trim), and errors to **stderr** (`orchestrate:`-prefixed)
   for: a tab-less line, empty member-path, empty brief, duplicate member-path, and a
   **member-path with whitespace or a shell metacharacter**. bats fixtures, both
   polarities.
5. **Dispatch cwd-scoped + quoted, never --root; validate gate.** `orch_dispatch <m>
   <action>` over all six actions emits `(cd '<m>' && <cmd>)` with the pinned literal
   command per action (incl. `validate→/speccraft:spec:close`), the member-path
   **single-quoted**, and **never** `--root`. `orch_validate` echoes `pass`/`fail` from
   `sh -c` stubs (`true`/`false`). bats.
6. **Failure isolation, blocked-clear & ledger contract (behavioral).**
   - A **two-member behavioral bats** (built `speccraft-state`, real `kind =
     workspace`) drives `orch_apply_result`: member A's action fails (exit 1) → A is
     `blocked`, member B's action succeeds → B advances and reconcile shows A blocked
     / B progressing (siblings isolated); A's `in_flight` is **cleared on the failed
     attempt too** (a non-executing member never shows `in_flight`); a **clean
     re-attempt of A (exit 0)** clears `blocked` and advances A. This pins
     failure-isolation + blocked-clear as *behavior*, not prose.
   - A **phase-walk integration bats** drives the pointer **from the lib** — iterate
     `orch_next_phase`→`orch_completed_token`→`ledger-set … last_completed_phase` — and
     asserts the pointer walks `new→reviewed→planned→implemented→validated` exactly as
     the phase machine dictates, with `in_flight` set-then-cleared around a step.
7. **Command contract (structure).** A grep bats asserts `orchestrate.md` exists,
   carries the frontmatter keys `description`/`argument-hint`/`allowed-tools`, resolves
   `PLUGIN_ROOT` via `speccraft-state plugin-root` and sources `orchestrate.lib.sh`,
   and contains the **literal anchors**: the token order `new → reviewed → planned →
   implemented → validated`; both checkpoint labels + `--straight-through`;
   `spec:close`; `resume`/`in_flight`; `blocked`; and the driven subcommands
   `list-members`, `ledger-set`, `reconcile`.

## Out of scope

- Changing any 0037/0038 Go primitive — reused as-is.
- The Socratic interview's *content* and the decomposition *drafting* heuristic
  (model-driven; the lib only parses the human-confirmed artifact).
- **Full crash-window idempotency** — allocate-spec-id-strictly-before-dispatch and
  authoritative-artifact inspection before re-attempt (design 0001 mechanism spikes
  #1/#4). 0039 ships resume-at-pointer + `in_flight` visibility + blocked-clear; a
  **follow-up spec (0040)** owns crash-safe re-entry and the richer `in_flight`
  sub-state schema. This spec does not complete Spec B's crash-safety story.
- A fully-automated, real-subagent end-to-end run across live repos (mock-agent
  harness — a follow-up e2e; also where design spike #1's runtime `FindRoot`
  resolution is discharged).
- Concurrent-conductor locking; version bump / release mechanics.

## Open questions

_none — the interactive parts are runbook-documented; the deterministic core is the
bats-tested lib, and full crash-safety is explicitly deferred to 0040._
