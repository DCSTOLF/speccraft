---
spec: "0027"
status: planned
strategy: tdd
---

# Plan — 0027 Restore e2e lifecycle green after inline-at-close consolidation

## Context

This is a **test-harness-only** fix for a regression spec 0025 introduced. Spec 0025
added an inline, confirm-gated consolidation step to `commands/spec/close.md` (step 9).
In the credit-gated e2e lifecycle, the `[10/13] /speccraft:spec:close` step is driven
with *"Approve all proposed memory updates"*; `claude -p` swept the consolidation
confirm-gate into that blanket approval. With the throwaway lifecycle spec
`0001-add-farewell-function` carrying no `domains:` frontmatter and hitting zero
conflicts, consolidation ran to completion and — by design — **moved** the dir
`specs/0001-add-farewell-function/` → `specs/.archive/0001-add-farewell-function/`.
The pre-0025 assertion at `tests/e2e/run.sh:367` (`exists "$SPEC_DIR/changelog.md"`,
where `SPEC_DIR=specs/0001-add-farewell-function`) then fails: the changelog rode
along to the archived path via the wholesale `mv`.

The feature behaved exactly as specified; the break is a pre-0025 lifecycle assertion
never updated for the dir-relocating close. The fix touches only two test files:
`tests/e2e/run.sh` and `tests/e2e/spec_consolidate.sh`.

This is a **credit-gated model-tier change with no locally-runnable test** (the
lifecycle needs claude credits). The deterministic gate available now is
`bash -n` on both files plus structural inspection; full green is confirmed by the
next `e2e-devcontainer` CI run (AC3, same deferral as spec 0025's model tier).

## Test-first sequence

### Step 1 — Confirm the current lifecycle RED at run.sh:367 (RED)
- This step has no new local test to author: the RED is the **currently-observed CI
  failure** the user reported. The `[10/13] /speccraft:spec:close` step is driven
  with the blanket-approval prompt at `tests/e2e/run.sh:366`; `claude -p` folds the
  consolidation confirm-gate into that approval, consolidation moves the spec dir to
  `specs/.archive/0001-add-farewell-function/`, and `tests/e2e/run.sh:367`
  `exists "$SPEC_DIR/changelog.md"` (with `SPEC_DIR` resolved at line 279 to
  `specs/0001-add-farewell-function`) fails because the changelog rode along to the
  archived path.
- **Why it fails before the fix:** the prompt does not distinguish the memory-keeper
  confirm-gate from the consolidation confirm-gate, so the zero-conflict dir-move
  relocates the dir out from under the legacy path assertion.
- **Not locally runnable** — credit-gated; evidence is the reported `e2e-devcontainer`
  pipeline log. Honest RED in the spec-0025 deferral pattern.
- Covers: AC1, AC3 (the failure these GREEN steps must clear).

### Step 2 — run.sh [10/13]: decline consolidation + assert non-move (GREEN)
- Edit `tests/e2e/run.sh` at the `[10/13] /speccraft:spec:close` step (lines 365-368):
  - **Line 366:** change the `run_claude` prompt so the blanket approval covers ONLY
    the memory-keeper updates and **explicitly declines / defers the
    spec-consolidation step**, leaving the closed dir in place under `specs/`.
    (e.g. "…Approve all proposed memory updates, but DECLINE / defer the spec
    consolidation step — leave the closed spec directory in place under specs/.")
  - **Add a structural non-move assertion** immediately after the existing line-367
    check, using the inline negative-exists idiom the fixtures already use (lib.sh
    has no negative-exists helper):
    `[ ! -d "specs/.archive/0001-add-farewell-function" ] || fail "[10/13] consolidation moved the closed spec dir to .archive despite decline"`
  - **Keep lines 367 and 368 unchanged** — they remain valid because the dir is not
    moved.
- After this edit the legacy post-close assertions hold and the decline is verified,
  not assumed. `bash -n tests/e2e/run.sh` is clean.
- Covers: AC1, AC4.

### Step 3 — spec_consolidate.sh [cons 2/3]: document inline-at-close equivalence + retain positive move/merge asserts (GREEN)
- Edit `tests/e2e/spec_consolidate.sh`, the `[cons 2/3]` CONFIRM leg (lines 98-111):
  - **Relabel / comment** the leg to state explicitly that this CONFIRM path
    exercises the **same** `consolidate.lib.sh` move → merge → archive flow that
    `close.md` step 9 drives **inline-at-close**, and that:
    - the close-command inline **wiring** (close.md sources `consolidate.lib.sh` and
      calls the confirm-gated consolidate helper) is already pinned deterministically
      and credit-free by `specs/0025-spec-consolidation-on-close/verify.sh`; and
    - the lib **mechanics** — `apply_delta`, the wholesale `mv` of `archive_dir_move`
      preserving ALL dir contents incl. a `changelog.md` ("changelog rides along"),
      and conflict record/clear — are already pinned by the bats tests in
      `tests/hooks/spec-consolidate.bats`.
    - Therefore **declining** consolidation at `[10/13]` does NOT leave the
      inline-at-close path unverified: this CONFIRM leg is its sanctioned outcome
      coverage (the spec's "document the lib-path equivalence explicitly" branch of
      AC2).
  - **Keep / tighten the existing positive structural assertions** as the
    inline-at-close OUTCOME coverage (already present at lines 103-110):
    - domain file carries `(spec 0089)` and matches the `$PROV_SUFFIX_RE`
      provenance-suffix regex,
    - archive-B (`specs/domains/.archive/state.md`) exists and is non-empty,
    - `specs/.archive/0089-demo-consolidation/spec.md` exists (moved dir retains
      its contents) and `specs/0089-demo-consolidation` is gone from `specs/`.
- Do NOT add a second full credit-heavy `/speccraft:spec:close` drive (spec's
  open-question resolution prefers extending the existing fixture). Structural
  predicates only — never grep model prose. `bash -n tests/e2e/spec_consolidate.sh`
  is clean.
- Covers: AC2, AC4.

### Step 4 — Deterministic verification + deferred credit-gated confirm (VERIFY)
- Run `bash -n tests/e2e/run.sh` and `bash -n tests/e2e/spec_consolidate.sh` — both
  must parse clean.
- Structural inspection that the contract holds:
  - AC1: `[10/13]` prompt declines consolidation; the new
    `[ ! -d specs/.archive/0001-add-farewell-function ]` non-move assertion is present;
    lines 367/368 retained.
  - AC2: `[cons 2/3]` carries the inline-at-close equivalence comment and the positive
    move/merge/archive structural assertions.
  - AC4: only `tests/e2e/run.sh` and `tests/e2e/spec_consolidate.sh` changed; the
    spec-0025 feature files (`commands/spec/consolidate.lib.sh`,
    `commands/spec/close.md`, `commands/sync.md`, `agents/memory-keeper.md`,
    `skills/speccraft-context/SKILL.md`) are byte-unchanged
    (confirm via `git diff --name-only`).
- AC3 (full lifecycle reaches green through `[10e/13]`) is **deferred to the next
  `e2e-devcontainer` CI run** — credit-gated, same deferral as spec 0025's model
  tier. Not locally runnable.
- Covers: AC1, AC2, AC3 (deferred), AC4.

## Delegation

- None. This is a two-file shell-fixture edit best done directly; no agent has a
  stronger match than direct editing for `bash -n`-gated harness changes.

## Override needs: NONE

The changed files are `tests/e2e/*.sh` (not guard-gated production/Go code). No
`/speccraft:spec:override` is required. No Go change, no bats change, no new file.

## Risk

- **The decline at `[10/13]` depends on the model honoring "decline consolidation."**
  `claude -p` previously swept the gate into the blanket approval; an explicit decline
  may still be missed. *Mitigation:* the added
  `[ ! -d specs/.archive/0001-add-farewell-function ]` non-move assertion turns a
  model slip into an **immediate, named failure** at `[10/13]` rather than the
  confusing downstream line-367 `changelog.md` failure.
- **Green is confirmed only by the next credit-gated `e2e-devcontainer` CI run.**
  The model-tier lifecycle is not locally runnable; the deterministic gate now is
  `bash -n` + structural inspection. *Mitigation:* mirror spec 0025's accepted
  deferral and treat the next CI lifecycle run as the AC3 confirmation gate.
- **A credit-free meta-test alternative was deliberately not taken.** A
  spec-0014/0020-style meta-test that reads `run.sh`'s live `[10/13]` assertion text
  could pin the decline+non-move contract deterministically, but AC4 scopes this
  hotfix to exactly two files and such a meta-test would itself need a follow-up.
  *Mitigation:* flag it as possible future hardening; out of scope here.
