# Review — Spec 0039 Architect conductor: /speccraft:arch:orchestrate

Date: 2026-07-29 · Agents: codex, claude-p (quorum 1) · **Verdict: approve**

## Review loop

- **Self-check (spec-critic):** `needs-work` → **pass** over 2 rounds. Round 1
  caught 10 items — the two critical being the missing `spec:close` (so members
  never reached the `closed` status reconcile keys on) and a dispatch mapping with
  non-command tokens (`answer-questions`/`validate`). All resolved by folding
  `answer-questions` into `spec:new`, mapping `validate→spec:close`, and pinning six
  literal dispatch commands. Two cosmetic cleanups after.
- **Cross-model:** `claude-p` → **approve-with-comments**; `codex` →
  **changes-requested → (after amend) approve**. Both converged on the same
  substantive gaps; codex's re-review confirmed 4/5 fixed and caught one genuine
  new inconsistency (see below), now resolved.

## Key items caught & fixed (ranked)

1. **Scope honesty (codex's blocker).** Reframed from "final slice that completes
   Spec B" to the **orchestration MVP**: ships resume-at-pointer + `in_flight`
   visibility + blocked-set/clear, and **explicitly defers full crash-window
   idempotency to a follow-up (spec 0040)** — noting design 0001 itself lists
   crash-safety as mechanism spikes #1/#4, not a settled contract.
2. **`in_flight` clear-on-every-attempt (codex re-review).** `orch_apply_result`
   cleared `in_flight` only on success, leaving it set after a known-failed attempt
   (contradicting "non-empty `in_flight` = mid-execution"). Now cleared on **every**
   completed attempt; AC6 asserts it on the failure path.
3. **Seeding exactly-once `new`.** Pinned: seeding writes member *rows* only (no
   `spec:new`); the `new` phase dispatches `spec:new` once and captures the member's
   allocated ref — no double-dispatch.
4. **`orch_validate` exec contract.** Pinned `sh -c "$test_cmd"` with the
   trusted-config trust-boundary note; exit 0 → `pass`.
5. **Failure-isolation as behavior, not grep.** New `orch_apply_result` helper +
   a two-member behavioral bats (A fails→blocked, B advances, clean retry clears).
6. **Escalation restart** resets the revise iteration to 0; **decomposition**
   pins the indented-`#` comment rule + a **safe member-path charset**
   `^[A-Za-z0-9._/-]+$` (rejects whitespace/quotes/metacharacters); **`orch_dispatch`**
   single-quotes the member-path; **AC7** pins literal grep anchors + command
   frontmatter (`description`/`argument-hint`/`allowed-tools`) + `PLUGIN_ROOT` sourcing.

## Points of agreement (both models)

- **Phase-token model is internally consistent** across the tokens section,
  `orch_next_phase`, `orch_completed_token`, `orch_dispatch`, and AC6.
- The **`--straight-through` divergence** (suppresses only the after-plan checkpoint,
  never the escalation) is "the only coherent reading" of design 0001's tension.
- The **cwd-scoped-never-`--root` dispatch** is correctly scoped; deferring the
  runtime `FindRoot` resolution (spike #1) to the e2e tier is appropriate.
- **AC6's integration bats genuinely couples to 0039's phase machine** (a token drift
  0038's own suite wouldn't catch), not merely re-testing 0038's writer.
- **No guardrail/convention violations** (the two codex convention flags were
  AC-wording underspecification of pre-existing command conventions, now pinned in AC7).

## Aux-config nits (non-blocking; worth a follow-up)

`.speccraft/agents.toml`: (1) codex `cmd` `["codex","exec","--sandbox workspace-write"]`
errors on codex-cli — split into `"--sandbox","workspace-write"`. (2) claude-p
`input = "argv"` overflowed the single-argv exec ceiling on a ~132KB review payload
(`Argument list too long`); it works via **stdin** — set claude-p `input = "stdin"`.
Both surfaced across the 0038/0039 cross-model runs.
