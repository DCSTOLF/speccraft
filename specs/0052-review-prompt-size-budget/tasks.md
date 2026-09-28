---
spec: "0052"
---

# Tasks

- [x] T0 — Capture the 12 historical reviewer responses from /tmp into `tests/hooks/fixtures/spec-review-payload/responses/historical/` (CHORE — done during planning; they existed only in /tmp)
- [x] T1 — RED: tier classification, heading/fence grammar fixtures, awk-interval guard fixtures
- [x] T2 — GREEN: `review_context_tier`, `review_heading_index`, portability-guard clause (f)
- [x] T3 — RED: round predicates, inert all-refused round, promote deferral at the speccraft-state seam
- [x] T4 — GREEN: `review_responses_complete` / `review_approval_quorum_met` / `review_finalize_round`; `review.md` drops `--promote` and gates steps 5-7
- [x] T5 — RED: digest primitive on both polarities, FIFO single-scan proof, sweep exact-set update
- [x] T6 — GREEN: `_review_digest_cmd` / `review_digest` / `_review_scan_reference`; land the sweep update in the same commit
- [x] T7 — RED: composer envelope (tier mismatch, order, no body, no digest, missing vs empty reference set, digest-out, scoped substitution, spec-src indirection, locale determinism)
- [x] T8 — GREEN: `review_compose_payload`
- [x] T9 — RED: budget mode matrix, boundary triples, reason enum, refusal-message arms, override validation
- [x] T10 — GREEN: the three constants with derivation + raise-me comments, `review_effective_limit`, `review_budget_check`, `review_refusal_message`
- [x] T11 — RED: materialize-once, measured==dispatched, trap on clean and interrupted exit, NUL/UTF-8 refusal, byte-preserving argv, aux-delegator pure dispatch
- [x] T12 — GREEN: `review_round_tmpdir` / `review_materialize_payload` / `review_payload_representable` / `review_dispatch_bytes`; aux-delegator precomposed-payload path
- [x] T13 — RED: `reference_access` validator arms, historical-corpus parse, `reference_read` capability, prompt template and agents.toml pins
- [x] T14 — GREEN: `review_validate_reference_access`, `review_agent_reference_read`, `templates/prompts/review.md`, `templates/speccraft/agents.toml`
- [x] T15 — RED: static-corpus and live-corpus ratio assertions, largest-archived-spec selection, stated skip
- [x] T16 — GREEN: `review_full_paste_bytes` + the static corpus fixtures
- [ ] T17 — RED: runbook marker order, no-full-paste, and the remaining AC29 bite proof (fb04); fb01/fb02 landed in T7, fb03 in T11, fb05 in T3
- [ ] T18 — GREEN: rewrite `commands/spec/review.md` step 3 with the compose → budget-check → dispatch markers
- [ ] T19 — REFACTOR: retire `review_build_payload`, re-point `spec-review-diff.bats`, factor shared bats helpers
- [ ] T20 — Verify: `bats tests/hooks/` and `go test ./...` green, portability gates green

## AC coverage

| AC | Task |
|---|---|
| AC1 tier classification | T1/T2 |
| AC2 tier-mismatch rejection | T7/T8 |
| AC3 heading fixtures | T1/T2 |
| AC4 fence grammar | T1/T2 |
| AC5 interval scan + behavioural arm | T1/T2 |
| AC6 payload order / no body / no digest | T7/T8, incl. the fb01/fb02 bite proofs |
| AC7 missing vs empty reference set | T7/T8 |
| AC8 single scan (FIFO) | T5/T6 |
| AC9 digest primitive both polarities | T5/T6 |
| AC10 materialize once, measured==dispatched | T11/T12 |
| AC11 named-seam single creation | T11/T12 (fixture fb03 asserted in T11) |
| AC12 trap on abnormal exit | T11/T12 |
| AC13 NUL / invalid UTF-8 / locale | locale arm T7/T8; NUL + UTF-8 arms T11/T12 |
| AC13b byte-preserving file→argv | T11/T12 |
| AC14 aux-delegator pure dispatcher | T11/T12 |
| AC15 single composer, scoped round | T7/T8 |
| AC16 snapshot source + budget on both branches | composer half T7/T8; budget half T9/T10 |
| AC17 live-corpus ratio | T15/T16 |
| AC18 static-corpus ratio | T15/T16 |
| AC19 budget mode matrix | T9/T10 |
| AC20 refusal message | T9/T10 |
| AC21 override validation | T9/T10 |
| AC22 two predicates | T3/T4 |
| AC23 inert round | T3/T4 |
| AC24 deferred promote | T3/T4 |
| AC25 digest attestation + historical corpus | T13/T14 (fixtures from T0) |
| AC26 capability, both halves | T13/T14 |
| AC27 runbook + prompt pins | T17/T18 |
| AC28 shipped agents.toml | T13/T14 |
| AC29 bite proofs | fb01/fb02 in T7, fb03 in T11, fb04 in T17/T18, fb05 in T3 |
