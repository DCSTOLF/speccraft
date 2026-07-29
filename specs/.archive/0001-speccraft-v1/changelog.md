# Changelog — Spec 0001 speccraft v1

Closed 2026-07-29 (**retrospective**). The project-genesis spec: it bootstrapped
the whole plugin — the gating hooks, the three Go binaries
(`speccraft-{state,guard,drift}`), the slash commands, subagents, `.speccraft/`
memory templates, and the e2e harness. 58/69 tasks completed; the 11 that stayed
open were all manual-verification / "needs a live Claude session" / early-phase-e2e
placeholders (T0.4, T0.5.8, T1.5, T2.7, T3.8, T4.7, T4.10, T5.8, T8.4–T8.6).

## Why closed now (retrospective)

v1 shipped long ago and has been in continuous use; its implementation was subsumed
and hardened by the **40 specs that followed (through 0040)**. It sat at
`in-progress` only because its tail of open tasks gated on a "final user
verification" that never got a formal sign-off (`active_spec` was already null).
Closing to reflect reality. The open tasks are superseded:

- Manual/early-e2e placeholders (T2.7, T3.8, T4.7, T8.4) → covered by the hermetic
  `tests/e2e/run.sh` harness + language cycles shipping today.
- Clean-machine / platform install (T0.4, T0.5.8, T4.10) → covered by the
  devcontainer + the release packaging/verify pipeline (spec 0021).
- Live-agent testing (T5.8) → covered by the mock-agent e2e.
- README / CHANGELOG polish (T8.5, T8.6) → evolved continuously with the project.

## What v1 delivered (still current in spirit)

The three execution surfaces (Edit/Write-gating hooks, user slash commands,
dispatched subagents), the `speccraft-{state,guard,drift}` binaries, always-injected
`.speccraft/` memory, and the spec-first TDD workflow this repo dogfoods to this day.
No code change accompanies this close — it is a status reconciliation only.
