# Review — 0043 workspace sync: membership + ledger drift reconciliation

**Outcome:** reviewed (quorum met). Cross-model review over three rounds
(codex `gpt-5.6-sol` + `claude -p`). All substantive concerns resolved; the
spec is cleared for planning.

## Reviewers & verdicts

| Round | codex | claude -p |
|---|---|---|
| 1 | changes-requested | approve-with-comments |
| 2 | changes-requested | approve-with-comments |
| 3 (codex confirmation) | changes-requested → nits only | — |

Quorum default (1 approve/approve-with-comments) met by `claude -p`. codex's
round-1/2 concerns were substantive and were all addressed; its round-3 residue
was two wording-consistency nits (now fixed), not scope or design.

## Round 1 — what changed

codex (changes-requested) and claude-p (approve-with-comments) raised:

1. **Detect→apply race / no-lock overclaim** (codex). → Added **AC10**: re-read +
   re-validate each row immediately before `ledger-set`; skip with a `conflict`
   report if it changed. Bounded the safety claim honestly.
2. **Findings-as-rendered-commands** unsafe machine interface (codex). → Redefined
   findings as a structured 6-field record `<class>\t<design>\t<member>\t<field>\t<value>\t<detail>`;
   apply passes `<field>`/`<value>` **as argv**, never `eval`s `<detail>`.
3. **AC9 `reconcile` doesn't prove the mutation** (codex). → AC9 now asserts the
   mutation **directly via `ledger-get`** (`last_completed_phase=validated`,
   `in_flight` cleared) in addition to `reconcile done: true`.
4. **Terminal/invalid states** (codex). → `validated` pointer → `orch_next_phase
   done` → no finding; malformed `in_flight`/token → `malformed-row` advisory,
   row isolated, run continues.
5. **AC8/AC9 integration overclaim** (codex). → AC8 no longer claims the
   interactive path is executed by AC9; deterministic detection (AC3–AC7) + apply
   guard (AC10) carry falsifiable coverage; the model-driven prompt is a
   source-scan fence, credit-gated (spec-0042 convention).
6. **`$ROOT` undefined** (claude-p). → AC1 pins `ROOT="$(speccraft-state
   find-root)"`, `KIND="$(speccraft-state config-kind "$ROOT")"`; strict, no guess.
7. **Apply ordering + decline granularity** (claude-p). → AC8 pins order
   `status-ahead → stale-in-flight → stale-blocked`, per-finding confirmation.
8. **`orch_reentry` dual-use readability** (claude-p). → wrapped as
   `sync_status_ahead` / `sync_stale_in_flight`.

## Round 2 — convergence (both models flagged the same top issues)

1. **AC8 + AC10 self-conflict** (both, #1): applying `status-ahead` mutates the
   row, breaking the byte-identical check for later fixes, and re-deriving drift
   falsifies `stale-blocked`'s precondition. → Rewrote AC10 as a **per-member
   plan**: capture the full-row *expected snapshot* + the ordered findings with the
   preconditions they were detected under; apply as an ordered batch behind **one**
   snapshot check, advancing the expected row after each write (no precondition
   re-derivation from a mutated row). Added a bats case: one member with all three
   fixable findings applies in order without self-conflict.
2. **TSV empty-field parsing** (both): bash `IFS=$'\t' read` collapses adjacent
   tabs, losing meaningful empty fields (clear ops, advisory blanks). → Pinned the
   consumer to `awk -F '\t'` with `NF == 6`; `NF != 6` is a surfaced emit-bug.
3. **`malformed-row` vs `ledger-get` global-fail** (codex): split cleanly.
   Parse-level corruption (`ParseLedger` fails) → `ledger-get` non-zero/no-stdout,
   aborts (AC2). Row-level *semantic* malformation → downstream `sync_ledger_drift`
   `malformed-row` advisory; `ledger-get` only emits parsed, tab-free rows.
4. **Bounded lock claim** (codex): reworded away from "does not need a lock".
5. **AC1 grep-fence brittleness** (claude-p): pinned explicit anchors
   `<!-- speccraft:sync:repo -->` / `<!-- speccraft:sync:workspace -->`.
6. **0040 helper-contract rot** (claude-p): added a defensive bats leg pinning
   `orch_next_phase validated → done` and `orch_status_token closed → validated`.

## Round 3 — codex confirmation

codex confirmed the apply-order, TSV, and parse-vs-semantic fixes resolved.
Two residual **wording** nits (both fixed post-review, not affecting design):

- Unqualified "-safe" labels (`AC4` heading, `AC10` "conflict-safe", Out-of-scope
  "live-run-safe by construction") contradicted the bounded prose → retitled to
  "conservative under concurrent writes" / "conflict-reducing" / "conservative by
  construction … not concurrency-safety".
- `malformed-row` trigger still listed "embedded tab/newline", impossible given
  AC2's tab-free `ledger-get` guarantee → narrowed to token-machine rejection only.

## Guardrail / convention violations

None flagged by either reviewer in any round.

## Recommendation

Proceed to `/speccraft:spec:plan`. The design leans hard on tested primitives
(`orch_reentry`/`orch_status_token`/`orch_next_phase`, `list-members`,
`ws_detect_members`, `ledger-set`, `config-kind`) and adds one read-only oracle
(`ledger-get`, override budget 0 via the `run()` seam) plus a pure `sync.lib.sh`
and a kind-branch in `sync.md` — high leverage per unit of new code.
reviewed_sha256: e412463459de0834ba29b65ed2ff68cbaa41bee4a4d95eb2131e26fd4de057a7
