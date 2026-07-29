# Changelog — Spec 0039 Architect conductor: /speccraft:arch:orchestrate

Closed 2026-07-29. The orchestration surface of design 0001's conductor (Spec B).
Shell + markdown (not Go): a pure `commands/arch/orchestrate.lib.sh` + a
`commands/arch/orchestrate.md` runbook. **28 new bats tests** in
`tests/hooks/arch-orchestrate.bats`; full `tests/hooks/` suite (192) green,
`go test ./...` green. **Zero `/speccraft:spec:override`** — shell/markdown are
ungated; bats supplied RED-before-GREEN.

## What shipped (vs spec)

- **AC1 — phase machine.** `orch_next_phase` (`""→new … validated→done`, resume from
  the pointer) + inverse `orch_completed_token` (`revise` has no token).
- **AC2 — checkpoint.** `orch_should_pause` — pause iff next==`implement` and not
  `--straight-through`.
- **AC3 — review→revise.** `orch_review_verdict` — pass / revise (<max) / escalate
  (≥max), iteration = completed revise cycles.
- **AC4 — decomposition.** `orch_parse_decomposition` — first-tab split, end-trim,
  full-line (incl. indented) `#` comments, and rejects tab-less/empty/duplicate/
  unsafe-charset members (incl. a literal `'`).
- **AC5 — dispatch + validate.** `orch_dispatch` emits `(cd '<m>' && /speccraft:spec:<...>)`
  — single-quoted member-path, six pinned commands (`validate→spec:close`), never
  `--root`. `orch_validate` runs `sh -c "$test_cmd"` → pass/fail.
- **AC6 — failure isolation + ledger (behavioral).** `orch_apply_result` via 0038's
  `ledger-set`: on success advance + clear `blocked` + clear `in_flight`; on failure
  set `blocked` + clear `in_flight`, pointer put. A two-member bats proves A
  fails→blocked (in_flight cleared) while sibling B advances, and a clean retry
  clears; a phase-walk bats drives the pointer `new→…→validated` from the lib with
  `in_flight` set-then-cleared.
- **AC7 — runbook.** `orchestrate.md` with frontmatter, `plugin-root`/`find-root`
  bootstrap, sources the lib, seeds member rows only (no double-`new`), resumes,
  dispatches cwd-scoped, gates validate→`spec:close`, reconciles; structure-grep bats.

## Notable during review/implementation

- Cross-model review (codex changes-requested→approve, claude-p approve-with-comments)
  drove the **scope-honesty reframe** — this is the orchestration **MVP** (resume +
  `in_flight` + blocked-clear); **full crash-window idempotency is deferred to a
  follow-up (0040)**, since design 0001 itself lists it as mechanism spikes #1/#4.
  It also pinned exactly-once `new` seeding, the `orch_validate` `sh -c` trust
  boundary, the behavioral (not grep-only) failure-isolation test, and — on
  re-review — that `in_flight` must clear on **every** completed attempt (not just
  success).
- The self-check's two critical catches were the missing `spec:close` (so members
  never reached the `closed` status reconcile keys on) and non-command dispatch
  tokens — both fixed by folding `answer-questions` into `spec:new` and mapping
  `validate→spec:close`.

## Deviations / deferrals

- **Full crash-safety → follow-up spec 0040** (allocate-id-before-dispatch,
  authoritative-artifact inspection before re-attempt; richer `in_flight` schema).
- Real-subagent end-to-end run (mock-agent harness) + design spike #1's runtime
  `FindRoot` resolution → a follow-up e2e.
- Consolidation → `/speccraft:sync`; no version bump here — with Spec B's
  orchestration surface now in place, a release/version step can bundle 0037–0039.

## Aux-config nits (logged in review.md)

`.speccraft/agents.toml`: codex `cmd` should split `--sandbox workspace-write` into
two tokens; claude-p `input` should be `stdin` (argv overflowed on large payloads).
