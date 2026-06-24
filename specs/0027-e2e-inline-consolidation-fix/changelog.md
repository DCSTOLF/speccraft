---
spec: "0027"
closed: 2026-06-24
---

# Changelog — 0027 Restore e2e lifecycle green after inline-at-close consolidation

## What shipped vs spec

- A **test-harness-only** fix for a regression spec 0025 introduced. Spec 0025's
  inline, confirm-gated consolidation at `commands/spec/close.md` step 9 was, in the
  credit-gated e2e lifecycle, swept into the `[10/13]` "Approve all proposed memory
  updates" blanket approval. With the throwaway lifecycle spec
  `0001-add-farewell-function` carrying no conflicts, consolidation ran to completion
  and (by design) MOVED its directory to `specs/.archive/0001-add-farewell-function/`,
  so the pre-0025 assertion `run.sh:367` `exists "$SPEC_DIR/changelog.md"` failed —
  the changelog rode along to the archived path.
- **`tests/e2e/run.sh` `[10/13]`:** the close prompt now explicitly DECLINES / defers
  the spec-consolidation step (approve memory updates only; leave the closed dir in
  place under `specs/`). A new structural assertion
  `[ ! -d "specs/.archive/0001-add-farewell-function" ] || fail "..."` proves the
  decline held — turning a model slip into an immediate, named failure at `[10/13]`
  rather than the confusing downstream changelog-path failure. Legacy lines 367/368
  retained and now valid (the dir is not moved).
- **`tests/e2e/spec_consolidate.sh` `[cons 2/3]`:** documented that this CONFIRM leg
  is the inline-at-close-EQUIVALENT coverage — it drives `/speccraft:sync` but
  exercises the SAME `consolidate.lib.sh` route → `consolidate_apply_delta` →
  `consolidate_archive_dir_move` path that `close.md` step 9 drives inline.
  Cross-referenced that the close-command WIRING is pinned by
  `specs/0025-spec-consolidation-on-close/verify.sh` and the lib MECHANICS (incl. the
  wholesale `mv` that makes a changelog "ride along") by
  `tests/hooks/spec-consolidate.bats`. Positive move/merge/archive assertions retained.
- Net: the two close confirm-gates are now exercised on SEPARATE paths — `[10/13]`
  declines (dir stays, legacy assertions hold), `[10e/13]` confirms (dir moves +
  domain merge).

## Deviations

- None material. The spec-0025 feature code (`consolidate.lib.sh`, `close.md`,
  `sync.md`, `memory-keeper.md`, `SKILL.md`) is **byte-unchanged** (AC4 confirmed via
  `git diff --name-only 3fa2340..HEAD` — only the two `.sh` files appear).
- No `/speccraft:spec:override` needed (both files are `tests/e2e/*.sh`, not
  guard-gated). No Go, no bats, no new file.
- "Changelog rides along" needed no new e2e assertion — it is a logical consequence
  of the wholesale `mv` already proven by the bats
  `consolidate_archive_dir_move` test.

## Close-gate pending

- **AC3 (full lifecycle green through `[10e/13]`) is deferred to the in-flight
  `e2e-devcontainer` CI run 28066411890** — the credit-gated model tier is not
  locally runnable. Same deferral convention as spec 0025's model tier. The
  deterministic gate satisfied now: `bash -n tests/e2e/run.sh` +
  `bash -n tests/e2e/spec_consolidate.sh` clean, plus structural inspection that the
  changed assertions are structural. RED was the observed CI failure (run
  28057150956); GREEN is the two edits.

## Files touched

- `tests/e2e/run.sh`
- `tests/e2e/spec_consolidate.sh`

## Out of scope / follow-up

- RCA option (3): a distinct consolidation confirm-gate / opt-out so a generic
  "approve all" never silently relocates a spec dir — a real-user UX sharp edge, not
  just a test concern. Deferred as its own follow-up spec.
- A spec-0014/0020-style credit-free meta-test reading `run.sh`'s live `[10/13]`
  decline/non-move assertion was deliberately NOT taken (AC4 scopes the change to two
  files); flagged as possible future hardening.
