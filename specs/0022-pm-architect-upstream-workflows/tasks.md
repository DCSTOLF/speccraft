---
id: "0022"
spec: "0022"
---

# Tasks

## Phase P1 — State lanes, tree scaffolding, doc-zone pin, regression proof

- [x] T1 — P1.0 Capture green regression baseline (go test, bats, e2e adr assertion); pins AC1/AC7 start state
- [x] T2 — P1.1 (RED) Add state_lanes_test.go: ActiveProduct/ActiveDesign round-trip + null/empty clear tests [AC2, AC7]
- [x] T3 — P1.2 (GREEN) Add ActiveProduct/ActiveDesign struct fields + GetField/SetField cases mirroring active_spec clear semantics [AC2, AC6, AC7] — used one-shot /speccraft:spec:override (Write-created sibling test isn't modeled by guard's applyEdit, so red_candidates was empty)
- [x] T4 — P1.3 (RED/lock) Extend state_single_writer_test.go patterns with \.ActiveProduct/\.ActiveDesign; state.go remains sole writer [AC7]
- [x] T5 — P1.4 (RED/pin) Add files_test.go TestIsAlwaysAllowed rows: product/design *.md == true, source .go under those trees == false; NO files.go prefix change [AC3]
- [x] T6 — P1.5 (RED) Add commands/pm/new.lib.sh + tests/hooks/pm-new-preflight.bats: empty-tree 0001, max+1, scaffold brief status:draft [AC2]
- [x] T7 — P1.6 (RED) Add commands/arch/new.lib.sh + tests/hooks/arch-new-preflight.bats: empty-tree 0001, max+1, scaffold design status:draft [AC2]
- [x] T8 — P1.7 (GREEN) Implement pm/arch next-id + scaffold helpers (pure, set -euo pipefail) [AC2]
- [x] T9 — P1.8 (RED→GREEN) Add state_lane_independence_test.go: clear-one-preserves-other-two (spec/product/design) [AC6]
- [~] T10 — P1.R (REFACTOR, optional) SKIPPED — pm/arch next_id duplication (~15 lines) is acceptable; not extracted

## Phase P2 — Authoring + critic agents + review wiring

- [x] T11 — P2.1 (RED) Add specs/0022-.../verify.sh grep-oracle: agent+command frontmatter, critic narrowness, invoked-before-review, cross-reviewer/memory-keeper reuse-unchanged [AC4-support]
- [x] T12 — P2.2 (GREEN) Add agents/pm-author.md, arch-author.md (mirror spec-author), pm-critic.md, arch-critic.md (mirror spec-critic)
- [x] T13 — P2.3 (GREEN) Add commands/pm/{new,review,prioritize,close}.md + commands/arch/{new,review,decide,close}.md with required frontmatter; wire lib helpers, critic-before-cross-reviewer, lane set/clear [AC2]
- [x] T14 — P2.4 (RED) Add pm/prioritize.lib.sh + arch/decide.lib.sh + bats: draft->prioritized, draft->decided, reject non-draft source [pm:prioritize AC, arch:decide AC]
- [x] T15 — P2.5 (GREEN) Implement pm_set_status / arch_set_status status-transition helpers; wire into prioritize.md / decide.md [pm:prioritize AC, arch:decide AC]
- [~] T16 — P2.R (REFACTOR, optional) SKIPPED — pm_set_status/arch_set_status share logic but stay in separate libs for independent sourcing; not extracted

## Phase P3 — --from / informed-by linkage + arch:close memory routing

- [x] T17 — P3.1 (RED) Add commands/spec/new.lib.sh + tests/hooks/spec-new-from.bats: --from sets non-empty informed-by, plain new has no key, accepts closed brief, dangling referent non-fatal [AC5, AC8]
- [x] T18 — P3.2 (GREEN) Implement --from product/<id>|design/<id> bridge: pull Why/What, write informed-by; plain path no key; dangling/closed non-fatal; wire into spec/new.md [AC5, AC8]
- [x] T19 — P3.3 (RED) Add tests/e2e/pm_to_spec_bridge.sh + register in run.sh: spec exists, informed-by key present+non-empty, Why/What non-empty, active_spec set; plain branch no informed-by key (structural, no prose grep) [AC5] — SOURCED-fixture (shares run_claude); bash -n clean + section_nonempty unit-checked; full run credit-gated (pending user e2e)
- [x] T20 — P3.4 (RED) Add tests/e2e/arch_close_memory.sh + register in run.sh: memory-keeper invoked, diff proposed-not-applied (architecture.md unchanged pre-confirm), ADR header SHAPE in history.md via contains_adr, no write on decline, clears active_design only [AC4] — bash -n clean; full run credit-gated (pending user e2e)
- [x] T21 — P3.5 (GREEN) Wire commands/arch/close.md memory-keeper routing (propose→confirm→apply) + clear active_design [AC4, AC6] — already wired in T13 (commands/arch/close.md); verified propose→confirm→apply + clears active_design only
- [x] T22 — P3.R (REFACTOR/verify) Re-run unmodified existing suite: go test ./... green, bats 77/77 green, verify.sh oracle green, run.sh source integrity (--help) clean; P3 added no Go/state/fixture edits so AC1/AC7 byte-shape holds. run.sh close-gate jq active_spec + preflight_active_spec_set lifecycle re-run is credit-gated (pending user e2e) [AC1, AC7]

## Bypasses
- 2026-06-21 — override: adding additive state lanes ActiveProduct/ActiveDesign to state.go (T3/P1.2). Sibling RED tests (state_lanes_test.go round-trip) are observed failing, but the guard did not register them as this session's red-candidates for the package; one-shot bypass per plan.md TDD-gate note.
