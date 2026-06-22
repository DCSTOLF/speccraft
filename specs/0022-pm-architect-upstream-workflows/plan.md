---
id: "0022"
spec: "0022"
status: planned
strategy: tdd
---

# Plan — 0022 Optional PM and Architect workflows upstream of specs

## Plan-phase decisions (resolved per review carry-forwards)

- **Immutability overclaim (round-3 highest priority): RESOLVED via path (i) — "by
  convention".** Closed brief/design immutability is advisory only. NO status-aware
  PreToolUse guard is added (explicitly out of scope, spec §Out of scope). The plan
  adds NO closed-artifact-immutability guard predicate and NO AC pinning a rejected
  write to a closed artifact. Spec Lifecycle already softened to "immutable by
  convention" with the parity-comparison removed.
- **AC3 = markdown-scoped regression pin, NOT a directory prefix.** We rely on the
  existing `ext == ".md"` rule in `files.go::IsAlwaysAllowed` and add table rows that
  PIN it for `product/` and `design/` markdown, PLUS negative rows pinning that a
  SOURCE file under those trees stays gated. We do NOT add `product/`/`design/`
  entries to the `prefix()` chain — adding them would flip the negative source rows
  and reintroduce the broad bypass codex flagged as a guardrail violation.
- **roadmap.md: DEFERRED.** Not scaffolded, written, or consumed in this spec.
  Roadmap MANAGEMENT is out of scope (spec §Out of scope). `pm:new` scaffolds only
  `brief.md`; `pm:review` writes `review.md`. A future spec owns roadmap.md if ever.
- **pm-critic / arch-critic acceptance stays NARROW:** frontmatter contract
  (name/description/tools/model), agent-file presence, invoked-before-`*:review`,
  stage-specific checklist output. NOT a second review quorum.
- **Test-layer assignment (cheapest layer per AC):**
  - Deterministic Go mechanics → `tools/internal/speccraft/*_test.go`:
    AC2 (state lane set), AC3 (IsAlwaysAllowed), AC6 (lane independence), AC7
    (active_spec byte-shape + sibling-key serialization).
  - Pure-shell command helpers (id allocation, frontmatter scaffold, preflight) →
    `commands/{pm,arch}/*.lib.sh` + `tests/hooks/*.bats`: AC2 (id allocation +
    empty-tree base case), prioritize/decide status-transition helpers.
  - Doc-only frontmatter contracts (agents + commands) → `specs/0022-.../verify.sh`
    grep-oracle: pm-critic/arch-critic/pm-author/arch-author frontmatter, command
    frontmatter, invoked-before-review wording.
  - Credit-gated agent integration → `tests/e2e/*.sh` via `run.sh`: AC4
    (memory-keeper diff/ADR-append), AC5/AC8 (`spec:new --from` prefill, dangling
    informed-by non-fatal). Deterministic structural predicates only — never grep
    model prose.

## TDD-gate note

The `speccraft-guard` PreToolUse gate covers only Go/Python/Rust/JS-TS. All `.md`
command bodies, `.md` agent files, `*.lib.sh`, `*.bats`, `tests/e2e/*.sh`, and
`verify.sh` are ungated — they need no RED/GREEN guard dance (their RED is a
failing bats/verify/e2e run, sequenced below). Only the Go edits in `state.go`,
`files.go`, and their `_test.go` siblings hit the guard.

**OVERRIDE CALL-OUT (Step P1.2):** Adding the `ActiveProduct` / `ActiveDesign`
struct fields is a brand-new Go symbol whose just-added test cannot compile until
the field exists (build-failure ≠ observed RED; conventions / spec 0018 known
limitation). The Step P1.2 GREEN edit to `state.go` therefore requires a one-shot
`/speccraft:spec:override` immediately before it. Subsequent Go edits in this spec
add no new symbols and follow normal RED→GREEN.

---

## PHASE P1 — State lanes + tree scaffolding + doc-zone pin + regression proof
_(Independently landable: ships the additive state lanes, the two trees' id/scaffold
helpers, the AC3 markdown pin, and proves AC1/AC6/AC7 regression-clean.)_

### Step P1.0 — Regression baseline proof (RED-as-guard) (RED)
- Run the existing suite UNMODIFIED to capture green baseline:
  `go test ./...`, `bats tests/hooks`, `bash tests/e2e/contains_adr_assertion_test.sh`.
- This pins AC1/AC7 starting state: `tests/e2e/run.sh` close-gate
  `jq -r '.active_spec // "null"'` (run.sh:359-360) and `revise.lib.sh::
  preflight_active_spec_set` currently green; any later step that reddens them fails.
- No new files. Purely the "before" snapshot.

### Step P1.1 — State lanes round-trip + clear (RED)
- Add `tools/internal/speccraft/state_lanes_test.go`:
  - `Test_SetField_ActiveProduct_RoundTrips` — `SetField(active_product,"0001-x")`
    then `GetField` returns `"0001-x"`; disk `jq`-shape (reuse `jqStringNullDefault`
    helper from `state_clear_test.go`) returns the literal value.
  - `Test_SetField_ActiveDesign_RoundTrips` — same for `active_design`.
  - `Test_SetField_ActiveProduct_NullArg_ClearsToOmitempty` — set then
    `SetField(active_product,"null")`; key absent on disk (mirror
    `activeSpecOnDiskIsCleared` shape assertion for the new key).
  - `Test_SetField_ActiveDesign_EmptyStringArg_ClearsToOmitempty` — same via `""`.
- Tests fail: `ActiveProduct` / `ActiveDesign` fields and the `GetField`/`SetField`
  `case` arms do not exist yet (compile failure = the known-limitation RED).

### Step P1.2 — State lanes implementation (GREEN, override-gated)
- **Run `/speccraft:spec:override` first** (new-symbol build-failure exception).
- Edit `tools/internal/speccraft/state.go`:
  - Add to `State` struct: `ActiveProduct string \`json:"active_product,omitempty"\``
    and `ActiveDesign string \`json:"active_design,omitempty"\`` as siblings of
    `ActiveSpec` (NOT nested; `active_spec` line stays byte-identical).
  - `GetField` switch: add `case "active_product": return s.ActiveProduct, nil` and
    `case "active_design": return s.ActiveDesign, nil`.
  - `SetField` switch: add `case "active_product":` and `case "active_design":` each
    mirroring `active_spec`'s `if value == "null" { value = "" }` clear semantics then
    assigning the field.
- All P1.1 tests pass. `speccraft-state get/set` CLI (`tools/cmd/speccraft-state/
  main.go`) already dispatches generically through GetField/SetField (main.go:163,197)
  — no CLI edit needed; confirmed by inspection.

### Step P1.3 — Single-writer allow-list extension (RED)
- Edit `tools/internal/speccraft/state_single_writer_test.go`
  `TestRustState_NoExternalWriters_Grep`: append to the `patterns` slice
  `regexp.MustCompile(\`\.ActiveProduct\s*=[^=]\`)` and
  `regexp.MustCompile(\`\.ActiveDesign\s*=[^=]\`)`.
- Test still GREEN if and only if `state.go` is the sole writer. (This is a
  protective regression assertion, not a failing RED for new prod code — it locks
  the new lanes to the single-writer rule. If any non-allowed `.go` later assigns
  the field it reddens.) No prod change required; `allowedFiles` already contains
  `state.go`.

### Step P1.4 — AC3 doc-zone markdown regression pin (RED)
- Edit `tools/internal/speccraft/files_test.go` `TestIsAlwaysAllowed` table; add rows:
  - `{"/repo/product/0001-x/brief.md", true}` — PM markdown allowed via `*.md` rule.
  - `{"/repo/design/0001-x/design.md", true}` — Architect markdown allowed.
  - `{"/repo/product/0001-x/review.md", true}` — review artifacts allowed.
  - `{"/repo/design/0001-x/sample.go", false}` — SOURCE under design/ stays gated.
  - `{"/repo/product/0001-x/sample.go", false}` — SOURCE under product/ stays gated.
- Tests PASS immediately against current `files.go` (the `ext==".md"` rule already
  yields true; no `product/`/`design/` prefix means source stays gated). This is a
  REGRESSION PIN — it locks AC3's narrow scope. To prove it is load-bearing, the
  same step temporarily flips the negative-source expectation locally to confirm the
  table actually exercises the predicate, then reverts.
- No `files.go` change (deliberate — adding prefixes would break the negative rows).

### Step P1.5 — product/ id-allocation + scaffold helper (RED)
- Add `commands/pm/new.lib.sh` consumed by a new bats suite (helper does not exist
  yet → sourcing fails = RED).
- Add `tests/hooks/pm-new-preflight.bats` (mirror `spec-revise-preflight.bats` setup):
  - `@test "pm_next_id: empty tree yields 0001"` — no `product/` dir → `0001`
    (AC2 empty-tree base case).
  - `@test "pm_next_id: highest NNNN + 1"` — seed `product/0001-a`, `product/0003-b`
    → `0004` (never-reused gaps not reclaimed).
  - `@test "pm_scaffold_brief: writes brief.md with status draft frontmatter"` —
    asserts `status: draft`, `id:` zero-padded, Why/What section headers present.
- Tests fail: `commands/pm/new.lib.sh` and its functions absent.

### Step P1.6 — design/ id-allocation + scaffold helper (RED)
- Add `commands/arch/new.lib.sh`; add `tests/hooks/arch-new-preflight.bats`:
  - `@test "arch_next_id: empty tree yields 0001"` (AC2 empty-tree base, design lane).
  - `@test "arch_next_id: highest NNNN + 1"` — seed under `design/`.
  - `@test "arch_scaffold_design: writes design.md status draft"` — frontmatter +
    section-header structural assertions.
- Tests fail: `commands/arch/new.lib.sh` absent.

### Step P1.7 — id/scaffold helpers implementation (GREEN)
- Implement `commands/pm/new.lib.sh` and `commands/arch/new.lib.sh`:
  pure functions, `#!/usr/bin/env bash` + `set -euo pipefail`, no top-level side
  effects. `<pm|arch>_next_id <tree-root>` (scan `NNNN-*` dirs, max+1, zero-pad 4,
  default 0001 when dir absent), `<pm|arch>_scaffold_<brief|design> <path> <title>`
  (emit frontmatter `id/title/status: draft/created` + Why/What | feasibility
  section skeleton).
- All P1.5/P1.6 bats pass.

### Step P1.8 — AC6 lane-independence assertion (RED)
- Add `tools/internal/speccraft/state_lane_independence_test.go`:
  - `Test_LaneIndependence_ClearSpec_PreservesProductAndDesign` — set all three
    lanes; `SetField(active_spec,"null")`; assert `active_product`/`active_design`
    unchanged via `GetField`.
  - `Test_LaneIndependence_ClearProduct_PreservesSpecAndDesign` — symmetric.
  - `Test_LaneIndependence_ClearDesign_PreservesSpecAndProduct` — symmetric.
- Tests fail until P1.2 lanes exist (sequenced after P1.2, so they GREEN once run).
  Placed last in P1 so AC6 is asserted against the full lane set.

### Step P1.R — Refactor (optional)
- If `pm/new.lib.sh` and `arch/new.lib.sh` next-id/zero-pad logic duplicates,
  extract a shared `commands/lib/id-alloc.lib.sh` sourced by both. All bats stay green.

---

## PHASE P2 — PM/Arch authoring + critic agents + *:review wiring
_(Independently landable: the eight command bodies, four agents, and review wiring,
verified at the doc-frontmatter + bats layer. No --from / memory routing yet.)_

### Step P2.1 — Agent + command frontmatter contract oracle (RED)
- Add `specs/0022-pm-architect-upstream-workflows/verify.sh` (executable, resolves
  repo root from `BASH_SOURCE`, paired presence+absence greps, `fails` counter
  pattern from `specs/0011-code-intel/verify.sh`). Checks:
  - **Agent presence + frontmatter:** `agents/pm-author.md`, `agents/arch-author.md`,
    `agents/pm-critic.md`, `agents/arch-critic.md` each exist and carry `name:`,
    `description:`, `tools:`, `model:` (mirror `agents/spec-critic.md`).
  - **Reuse-unchanged pin:** `agents/cross-reviewer.md` and `agents/memory-keeper.md`
    present and NOT modified by this spec (presence assertion only; their content is
    out of this spec's edit set).
  - **Command frontmatter:** `commands/pm/{new,review,prioritize,close}.md` and
    `commands/arch/{new,review,decide,close}.md` each carry `description:`,
    `argument-hint:`, `allowed-tools:`.
  - **Critic narrowness pin:** `pm-critic.md`/`arch-critic.md` contain
    stage-specific checklist wording and do NOT contain quorum/reviewers language
    (absence grep) — keeps them out of the review-quorum role.
  - **Invoked-before-review pin:** `commands/pm/review.md` references `pm-critic`
    self-check before `cross-reviewer`; `commands/arch/review.md` references
    `arch-critic` before `cross-reviewer`.
- `verify.sh` fails: none of the agent/command files exist yet.

### Step P2.2 — Author + critic agents (GREEN, doc-only)
- Add `agents/pm-author.md`, `agents/arch-author.md` (mirror `spec-author.md` with
  PM/Architect interview scripts), `agents/pm-critic.md`, `agents/arch-critic.md`
  (mirror `spec-critic.md`: single-model self-check, stage-specific checklist).
- The presence+frontmatter+narrowness checks in `verify.sh` pass.

### Step P2.3 — pm:* / arch:* command bodies (GREEN, doc-only)
- Add `commands/pm/{new,review,prioritize,close}.md` and
  `commands/arch/{new,review,decide,close}.md` with required frontmatter. Bodies
  invoke the P1.7 lib helpers for id/scaffold, invoke `pm-critic`/`arch-critic`
  before `cross-reviewer` in `*:review`, and set/clear the lane via `speccraft-state`
  (pm:new→`set active_product`, pm:close→`set active_product null`; arch symmetric).
- All `verify.sh` command checks pass.

### Step P2.4 — prioritize / decide status-transition helpers (RED)
- Add `commands/pm/prioritize.lib.sh` + `tests/hooks/pm-prioritize.bats`:
  - `@test "pm_set_status: draft -> prioritized"` — seed brief `status: draft`, run
    helper, assert frontmatter now `status: prioritized` (structural).
  - `@test "pm_set_status: rejects non-draft source"` — reviewed/closed source errors.
- Add `commands/arch/decide.lib.sh` + `tests/hooks/arch-decide.bats`:
  - `@test "arch_set_status: draft -> decided"` — `status: draft` → `status: decided`.
  - `@test "arch_set_status: rejects non-draft source"`.
- Tests fail: the lib files / `<pm|arch>_set_status` functions absent.
  **(Covers the previously-unpinned pm:prioritize / arch:decide ACs and the
  draft→prioritized / draft→decided transitions — review carry-forward item 3.)**

### Step P2.5 — prioritize / decide helpers implementation (GREEN)
- Implement `pm_set_status` / `arch_set_status` (sed/awk frontmatter flip, source-
  status gate mirroring `revise.lib.sh::preflight_status_gate`). Wire into the
  `prioritize.md` / `decide.md` bodies (these `.md` already added in P2.3, or added
  here if deferred). All P2.4 bats pass.

### Step P2.R — Refactor (optional)
- Fold `pm_set_status` / `arch_set_status` frontmatter-field rewrite into a shared
  `commands/lib/frontmatter.lib.sh` if it duplicates the scaffold helper's writer.
  All bats stay green.

---

## PHASE P3 — --from / informed-by linkage + arch:close memory-keeper routing
_(Independently landable: the cross-stage bridge and the memory routing, verified by
deterministic structural e2e predicates.)_

### Step P3.1 — informed-by frontmatter scaffold helper (RED)
- Add `commands/spec/new.lib.sh` (or extend an existing spec helper) +
  `tests/hooks/spec-new-from.bats`:
  - `@test "spec_from_emits_informed_by: --from product/<id> sets non-empty key"` —
    assert generated spec frontmatter has `informed-by:` key, non-empty, containing
    the referent (structural key-present + non-empty; NOT prose).
  - `@test "spec_plain_new_has_no_informed_by_key"` — plain `spec:new` output has NO
    `informed-by:` key (absence grep) — byte-shape parity with today (AC5).
  - `@test "spec_from_accepts_closed_brief"` — referent brief `status: closed` is
    accepted (no error) (AC8).
  - `@test "spec_from_dangling_referent_is_nonfatal"` — `--from product/9999-missing`
    exits 0 with a non-fatal note on stderr, spec still generated (AC8).
- Tests fail: helper / `spec_from_*` functions absent.

### Step P3.2 — informed-by / --from helper implementation (GREEN)
- Implement the `--from product/<id>|design/<id>` bridge helper: pull referent
  Why/What into the new spec's sections, write `informed-by: [...]` key; plain path
  writes NO key. Dangling/closed referents → non-fatal note, proceed. Wire into
  `commands/spec/new.md` body. All P3.1 bats pass.

### Step P3.3 — AC5/AC8 e2e structural predicates (RED)
- Add `tests/e2e/pm_to_spec_bridge.sh` (sources `tests/e2e/lib.sh`; exit 0/2 pattern):
  - After `pm:new` + `spec:new --from product/<id>`: assert generated `spec.md` file
    exists, `informed-by:` key present + non-empty (`contains_regex` for the key
    shape), Why/What sections non-empty (section-header + non-blank-body structural
    check), and `active_spec` set in state.json.
  - Plain `spec:new` branch: assert generated spec has NO `informed-by:` key
    (inverted `contains_regex` via subshell, per `contains_adr_assertion_test.sh`).
  - Never grep model prose.
- Register the fixture in `tests/e2e/run.sh`. Fails until P3.2 lands + the bridge is
  wired (credit-gated; run in the e2e harness).

### Step P3.4 — AC4 arch:close memory-keeper routing e2e (RED)
- Add `tests/e2e/arch_close_memory.sh` (sources `lib.sh`, reuses the `contains_adr`
  regex `^## 20[0-9]{2}-[0-9]{2}-[0-9]{2}` from `contains_adr_assertion_test.sh`):
  - Assert `arch:close` routes through `memory-keeper` (invocation evidence:
    proposed diff artifact present) and proposes — does NOT apply — until confirm:
    `.speccraft/architecture.md` byte-unchanged before confirmation.
  - On confirm: `history.md` gains an ADR entry matching the dated-ADR header SHAPE
    (`contains_regex`), and `architecture.md` changed.
  - On DECLINE: no write to `architecture.md` or `history.md` (file-unchanged assert).
  - Clears `active_design` only (assert `active_spec`/`active_product` untouched).
  - Structural predicates only.
- Register in `tests/e2e/run.sh`. Fails until arch:close memory routing is wired.

### Step P3.5 — arch:close memory routing wiring (GREEN)
- Edit `commands/arch/close.md` (and any `arch/close.lib.sh` preflight) to route the
  ADR/architecture update through `memory-keeper` (propose-diff → confirm → apply),
  clear `active_design` via `speccraft-state set active_design null`. All P3.3/P3.4
  e2e predicates pass.

### Step P3.R — AC1/AC7 final regression re-proof (REFACTOR/verify)
- Re-run the full unmodified existing suite: `go test ./...`, `bats tests/hooks`,
  `tests/e2e/run.sh` close-gate (`jq -r '.active_spec // "null"'` still `null` after
  `spec:close`, run.sh:359-360), `revise.lib.sh::preflight_active_spec_set` still
  reads `active_spec`. Confirms the four e2e fixture `state.json` literals keep
  `active_spec` byte-identical (AC1/AC7). All green.

---

## Delegation

- Go state/files edits (P1.1-P1.4, P1.8) → keep in tdd-implement (guard-gated; P1.2
  needs the override call-out above).
- Agent authoring (P2.2: pm-author/arch-author/pm-critic/arch-critic) → delegate to
  `spec-author`-style authoring (reason: these mirror spec-author/spec-critic, the
  agent-authoring strength match), but the tdd-planner/implementer owns the
  frontmatter-contract verify.sh oracle.
- arch:close memory routing (P3.4/P3.5) → `memory-keeper` is the reused backend
  (UNCHANGED); the command body wiring stays in tdd-implement.
- cross-reviewer / memory-keeper agents → reused UNCHANGED; no delegation to edit them.

## Risk

- **R1: P1.2 override slips and the new-symbol edit is attempted under the guard.**
  → Mitigation: the override is an explicit task (T3) ordered immediately before the
  state.go edit; the plan flags it as the only override in the spec.
- **R2: AC3 reviewer regression — someone "helpfully" adds product/design prefixes.**
  → Mitigation: the negative-source rows in P1.4 (`sample.go == false`) fail loudly
  if prefixes are added; the plan documents the decision NOT to add them.
- **R3: AC4/AC5 drift back to prose-grep under e2e time pressure.** → Mitigation:
  P3.3/P3.4 specify structural predicates only (key-present, file-unchanged,
  contains_adr SHAPE) and reuse the proven contains_adr/subshell-inversion patterns;
  "never grep model prose" is restated per fixture.
- **R4: active_spec serialization drifts (breaks AC1/AC7).** → Mitigation: P1.2 adds
  fields as siblings only; P3.R re-runs the unmodified close-gate + four-fixture
  proof; single-writer test (P1.3) locks the writer.
- **R5: lane independence regression.** → Mitigation: P1.8 asserts all three
  clear-one-preserves-others directions at the Go layer.
