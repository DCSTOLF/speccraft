---
spec: "0040"
status: planned
strategy: tdd
---

# Plan — 0040 Crash-safe conductor re-entry

Additive shell + markdown, extending spec 0039 (no Go, no `/speccraft:spec:override` —
`.sh`/`.md` are not gated by the TDD guard). **bats + the hermetic e2e are the RED
oracle: write the failing assertion FIRST, then implement.** Every step APPENDS to the
existing files — never recreates them:

- lib   → `commands/arch/orchestrate.lib.sh`
- bats  → `tests/hooks/arch-orchestrate.bats`
- runbook → `commands/arch/orchestrate.md`
- e2e   → `tests/e2e/arch_orchestrate_cycle.sh`

Six new pure helpers: `orch_status_ordinal`, `orch_status_token`,
`orch_phase_completion_status`, `orch_reentry`, `orch_in_flight_phase`,
`orch_find_member_spec`. All return via stdout/exit; NONE assigns a
zsh/bats-reserved `status` var. Errors route through the existing `orchestrate_error()`.

Grounding verified: `speccraft-state get-frontmatter` exits **1** on a read/open
failure but exits **0 with empty stdout** when the key is merely absent — this is the
exit-code-vs-empty discrimination `orch_find_member_spec` must make to avoid a false
zero-match. `mock_phase`'s `new` currently writes only `id`/`status` frontmatter, so
the e2e must add the `informed-by: [design/<DESIGN>]` stamp.

## Test-first sequence

### Step 1/2 — `orch_status_ordinal` (RED→GREEN) — AC1
- RED: table `""→-1`, `blocked→-1`, `draft→0`, `reviewed→1`, `planned→2`,
  `in-progress→3`, `closed→4`, `archived→4`; non-empty-unknown → stderr + non-zero.
- GREEN: `case` echoing ordinals; `""`/`blocked`→-1; other non-empty → `orchestrate_error`.

### Step 3/4 — `orch_status_token` (RED→GREEN, direct) — AC1
- RED: `draft→new`, `reviewed→reviewed`, `planned→planned`, `in-progress→implemented`,
  `closed/archived→validated`; `""`/`blocked`/unknown → non-zero.
- GREEN: `case` per table; `""`/`blocked`/unknown → error.

### Step 5/6 — `orch_phase_completion_status` (RED→GREEN, direct) — AC1
- RED: `new→draft`, `review→reviewed`, `plan→planned`, `implement→in-progress`,
  `validate→closed`; unknown → non-zero.
- GREEN: `case` per table; unknown → error.

### Step 7/8 — `orch_reentry` (RED→GREEN) — AC2
- RED: sweep phase×status → adopt/reattempt; load-bearing rows `validate closed→adopt`,
  `new ""→reattempt`, `review draft→reattempt`, `implement in-progress→adopt`,
  out-of-band `review closed→adopt`; `""`/`blocked` never adopt (any phase).
- GREEN: `member_ord=orch_status_ordinal(status)`,
  `comp_ord=orch_status_ordinal(orch_phase_completion_status(phase))` (both propagate
  error); `adopt` iff `member_ord -ge comp_ord`, else `reattempt`. `-1` never adopts.

### Step 9/10 — `orch_in_flight_phase` (RED→GREEN) — AC4
- RED: bare `review→review`; `phase=review iteration=2 awaiting_human=1→review`;
  `iteration=2 phase=review→review`; `phase=review phase=plan→review` (first-wins);
  `=` tokens without `phase=` → error; empty → error.
- GREEN: empty → error; no `=` → echo verbatim; else first `phase=<p>` token → `<p>`;
  `=` present but no `phase=` → error. No phase-name validation here.

### Step 11/12 — `orch_find_member_spec` (RED→GREEN) — AC3
- RED (disk fixtures; a `mk_member_spec <root> <ref> <informed-by-value>` helper):
  match in `specs/`; match in `specs/.archive/`; zero → empty exit 0; **two matches →
  error**; a **`get-frontmatter` read failure** (candidate `spec.md` `chmod 000`,
  guarded to skip as root) → error (no false zero); `0001` vs `0001-slug` form mismatch
  → miss.
- GREEN: scan `specs/*/spec.md` then `specs/.archive/*/spec.md`; per candidate capture
  `speccraft-state get-frontmatter <spec.md> informed-by` **output AND exit code
  separately** — non-zero exit → `orchestrate_error`; on exit 0, match iff output
  contains substring `design/<design-id>`. 0 → empty exit 0; 1 → echo `NNNN-slug`;
  ≥2 → `orchestrate_error`.

### Step 13/14 — runbook re-entry contract (RED→GREEN grep) — AC5
- RED grep bats over `orchestrate.md`: idempotent create-if-absent seeding (never
  re-`spec ""` on an existing row); resume reads `in_flight`/`orch_in_flight_phase`;
  branches on `orch_reentry` with adopt pointer via `orch_status_token`; new-first
  `orch_find_member_spec` adoption + write-ref-asap; structured `phase=review iteration=`.
- GREEN: extend `orchestrate.md` (append/edit, don't recreate): §seeding → create-if-absent;
  add a resume/re-entry subsection with new-first precedence (find→adopt ref+pointer,
  no `spec:new`; else reattempt+write ref asap) and other-phase `orch_reentry`
  (adopt→`orch_status_token`, reattempt→re-run); write `phase=review iteration=<n>`.

### Step 15/16 — e2e crash legs (RED→GREEN) — AC6
- RED: extend `mock_phase` — `new` stamps `informed-by: [design/<DESIGN>]`; add
  `VALIDATE_DISPATCHES`/`NEW_DISPATCHES` sentinel counters bumped when each mock is
  invoked. Add 3 legs, EACH in its own fresh `mktemp -d` workspace (isolation):
  1. no-re-close: `in_flight=validate` + spec `closed` → final `last_completed_phase:
     validated`, `reconcile done: true`, `VALIDATE_DISPATCHES == 0`.
  2. no-double-allocate `in_flight=new`: design-linked spec exists + ledger `spec` empty
     → ledger `spec` non-empty (== ref), member `specs/` dir count unchanged,
     `NEW_DISPATCHES == 0`.
  3. restart-safety: an idempotent re-seed does not erase a captured `spec` ref.
  (RED: `drive_member` still blindly re-dispatches / re-seeds → sentinels non-zero.)
- GREEN: extend `drive_member` to mirror the runbook — create-if-absent seed; pre-dispatch
  read `in_flight`+status and resolve re-entry (new-first `orch_find_member_spec` adopt;
  other phases `orch_reentry` adopt via `orch_status_token`, else reattempt). All legs
  pass; the 0039 happy-path/failure-isolation legs stay green.

### Step 17 — Refactor (optional)
- If Steps 8/16 duplicate the phase-completion-ordinal expression, extract
  `_orch_phase_completion_ordinal`. Full bats + e2e stay green.

## Delegation
- All steps → in-house shell/bats/e2e (the `commands/**/*.lib.sh` + `tests/hooks/*.bats`
  + `tests/e2e/*.sh` pattern). No Go, no `/speccraft:spec:override`.

## Risk
- **get-frontmatter read-failure vs empty** → capture exit code separately from stdout;
  non-zero = error (surfaced), exit-0-empty = miss. Step-11 unreadable-candidate test
  (skip as root, where `chmod 000` still reads).
- **informed-by over-match (`0001` vs `0001-slug`)** → match full `design/<NNNN-slug>`;
  Step-11 asserts the mismatch is a defined miss.
- **e2e scenario isolation** → each leg in its own `mktemp -d`, sentinels re-zeroed per leg.
- **new-first vs orch_reentry precedence for `in_flight=new`** → runbook + `drive_member`
  branch `new` through `orch_find_member_spec` FIRST (never `orch_reentry`).
- **zsh `status` shadow** → helpers use `member_ord`/`fm`/`phase`; never assign `status`.
