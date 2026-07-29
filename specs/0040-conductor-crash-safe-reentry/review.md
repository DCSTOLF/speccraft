# Review — Spec 0040 Crash-safe conductor re-entry

Date: 2026-07-29 · Agents: codex, claude-p (quorum 1) · **Verdict: approve**

## Review loop

- **Self-check (spec-critic):** `needs-work` → **pass** over 3 rounds — 8 issues,
  then 1 new gap (the `in_flight=new` adopt path dropped the ledger `spec` ref),
  all resolved. The load-bearing fix: `adopt` jumps the pointer to the *artifact's*
  token (`orch_status_token`) so an out-of-band multi-phase-ahead spec is reconciled,
  not partially replayed.
- **Cross-model:** `claude-p` → **approve-with-comments**; `codex` →
  **changes-requested**. (Both invoked cleanly after the `agents.toml` fix — no
  delegator workarounds.) Strongly convergent; both endorsed the ordinal/token model,
  the adopt-jumps-to-token composition, the ≥2-match hard-error key, and the honest
  design divergence.

## Key items caught & fixed (ranked)

1. **The back-reference key was wrong (both).** `orch_find_member_spec` keyed on a
   `design:` field, but `/speccraft:spec:new --from design/<id>` writes
   **`informed-by: [design/<id>]`** (verified against `spec_new_scaffold`; the
   `design:` lines on 0037–0040 were added by the close-flow, not `spec:new`). Rekeyed
   on `informed-by` — otherwise crash-safe-`new` adoption would miss in production.
   Also: a `get-frontmatter` read failure now errors (never a false zero-match).
2. **Unconditional seeding clobbered the captured ref on restart (codex).** Pinned
   **create-if-absent** seeding — a re-run never re-`spec ""` on an existing row.
3. **Asymmetric e2e rigor (both).** Added a `new`-dispatch sentinel (symmetric to the
   validate sentinel) so the no-double-allocate leg proves no re-dispatch structurally,
   plus scenario isolation (fresh `mktemp` per leg) and a seeding-preserves-ref assertion.
4. **Untested helpers / grammar (codex).** `orch_phase_completion_status` and
   `orch_status_token` now have **direct** bats ACs; `orch_in_flight_phase` pins
   malformed input (no `phase=`→error, empty→error, duplicate→first-wins).
5. **Clarifications (claude-p).** `review`+`reviewed`→adopt is correct (`spec:review`
   sets `reviewed` only on quorum pass); `revise` is never a bare `in_flight`;
   crash-resume-iteration ≠ 0039's escalation-reset; zsh-safety restated.
6. **Divergence narrowed** to "infeasible *without changing `spec:new`'s allocation
   contract*"; window scoped to "delegated command succeeded, ledger advance did not."

## Points of agreement (both models)

- The status→ordinal/token and phase→completion tables are complete and correct
  against 0037's vocabulary and 0039's token machine (no off-by-ones); folding
  `answer-questions` into `new` needs no `questioned` entry.
- The **adopt-jumps-to-token** move (token derived from status, not phase) is "the key
  move" — `review`+`closed`→adopt→`validated`→`done` composes correctly.
- The **≥2-match hard error** in `orch_find_member_spec` is correct (first-wins would
  reproduce the exact double-allocate being fixed).
- The **design divergence** (id-before-dispatch infeasible → post-hoc adoption) is sound.
- No guardrail/convention violations. No Go, no `/speccraft:spec:override`.

## Cosmetic note

Spec 0040's own frontmatter carries both `informed-by` and a `design:` line; the
prose keys adoption on `informed-by` (what `spec:new` auto-writes). The `design:`
field is the close-flow back-reference (consistent with 0037–0039), not the adoption
key — left for cross-spec consistency.
