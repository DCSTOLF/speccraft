---
spec: "0039"
status: planned
strategy: tdd
---

# Plan — 0039 Architect conductor: /speccraft:arch:orchestrate

This slice is **shell + markdown, not Go**. A pure `commands/arch/orchestrate.lib.sh`
of deterministic helpers (bats-tested) plus a `commands/arch/orchestrate.md` runbook.

**No `/speccraft:spec:override` anywhere.** The TDD guard's red-check gates only
Go/Python/JS/TS production files; `.sh` and `.md` are not gated. So there is no
build-failure-is-not-RED trap and no override budget. **bats is the RED oracle**: for
each helper we write the failing bats case FIRST (the function is undefined → bats
fails), then add the helper to the lib (GREEN). Every helper emits errors to **stderr**
via a central `orchestrate_error()`; stdout is reserved for structured output (the
`arch_set_status:` / `ledger.md:` precedent).

Test file: `tests/hooks/arch-orchestrate.bats`, mirroring `arch-decide.bats` — `setup()`
computes `PLUGIN_DIR` from `$BATS_TEST_FILENAME`, points `ORCH_LIB` at the lib, `mktemp
-d` a `TEST_REPO`; `teardown` `rm -rf`. Run with `bats tests/hooks/arch-orchestrate.bats`.
zsh-reserved-name discipline: the lib must never assign a parameter named `status`
(bats binds `$status`) — return via stdout/exit code.

## Test-first sequence

### Step 1 — bats scaffold + phase machine (RED) — AC1
- Add `tests/hooks/arch-orchestrate.bats` (`setup`/`teardown` mirror `arch-decide.bats`):
  - `orch_next_phase` table: `""→new`, `new→review`, `reviewed→plan`,
    `planned→implement` (mid-sequence resume), `implemented→validate`, `validated→done`.
  - `orch_next_phase` unknown token → non-zero + `orchestrate:` on **stderr**.
  - `orch_completed_token` inverse: `new→new`, `review→reviewed`, `plan→planned`,
    `implement→implemented`, `validate→validated`.
  - `orch_completed_token revise` → non-zero/empty (revise does not advance).
- Fails: lib does not exist.

### Step 2 — lib skeleton: error envelope + phase machine (GREEN) — AC1
- Create `commands/arch/orchestrate.lib.sh` (`#!/usr/bin/env bash`, `set -euo pipefail`,
  pure functions): `orchestrate_error()` (`echo "orchestrate: $*" >&2; return 1`),
  `orch_next_phase`, `orch_completed_token`. Step-1 green.

### Step 3/4 — checkpoint predicate (RED→GREEN) — AC2
- RED: `orch_should_pause` table — `implement 0→pause`, `implement ""→pause`,
  `implement 1→go`, `new 0→go`, `plan 0→go`, `validate 0→go`.
- GREEN: `orch_should_pause <next_action> <straight_through>` — `pause` iff
  `next_action==implement && straight_through!=1`, else `go`.

### Step 5/6 — review→revise control (RED→GREEN) — AC3
- RED: `orch_review_verdict` — `pass` on `pass`; `revise` when not-pass & iter<max;
  `escalate` at iter==max and iter>max.
- GREEN: `orch_review_verdict <iteration> <max> <critic_verdict>`.

### Step 7/8 — decomposition parse (RED→GREEN) — AC4
- RED fixtures (heredocs into `$TEST_REPO`), both polarities:
  - valid: leading blank, full-line `#`, **tab-indented `#`** and **space-indented `#`**
    (ignored), first-tab split w/ interior tabs kept in brief, trim both fields.
  - errors (stderr `orchestrate:`-prefixed, non-zero): no tab; empty member; empty brief;
    duplicate member; member-path with whitespace; member-path with a shell metachar;
    **member-path with a literal single-quote `'`** (load-bearing — charset `^[A-Za-z0-9._/-]+$`).
- GREEN: `orch_parse_decomposition <file>` — skip blanks + first-non-whitespace-`#`;
  first-tab split; trim; error on the above.

### Step 9/10 — dispatch (quoted, never --root) + validate (RED→GREEN) — AC5
- RED: `orch_dispatch` per action emits `(cd '<m>' && <cmd>)` — `new→/speccraft:spec:new`,
  `review→…:review`, `revise→…:revise`, `plan→…:plan`, `implement→…:implement`,
  `validate→/speccraft:spec:close`; assert `cd '<m>'` present and `--root` absent;
  unknown action → non-zero. `orch_validate true→pass`, `orch_validate false→fail`.
- GREEN: `orch_dispatch <member-path> <action>` (single-quoted path, pinned commands,
  never `--root`); `orch_validate <test_cmd>` (`sh -c "$test_cmd"`; exit 0→pass else fail).

### Step 11/12 — failure isolation + phase-walk (behavioral, RED→GREEN) — AC6
- Prereq in `setup()`: build `./bin/speccraft-state` if absent
  (`(cd "$PLUGIN_DIR/tools" && go build -o ../bin/speccraft-state ./cmd/speccraft-state)`)
  and `PATH="$PLUGIN_DIR/bin:$PATH"`. Fixtures: `TEST_REPO/.speccraft/speccraft.toml`
  = `kind = "workspace"`; member `<member>/specs/<ref>/spec.md` for reconcile.
- RED:
  - two-member: seed rows `./a`,`./b`; `orch_apply_result <ws> D ./a implement 1` →
    `./a` blocked + `in_flight` empty; `orch_apply_result <ws> D ./b implement 0` → `./b`
    advanced; sibling isolation; then `orch_apply_result <ws> D ./a implement 0` clears
    blocked + advances.
  - phase-walk: drive pointer from the lib (`orch_next_phase`→set `in_flight`→
    `orch_apply_result` success), asserting the pointer walks
    `new→reviewed→planned→implemented→validated` and `in_flight` set-then-cleared.
- GREEN: `orch_apply_result <ledger> <design> <member> <action> <exit_code>` via
  `speccraft-state ledger-set`: on 0 → advance + clear blocked + clear in_flight; on
  non-zero → set blocked + clear in_flight, pointer unchanged. Never touches siblings.

### Step 13/14 — orchestrate.md runbook + structure-grep (RED→GREEN) — AC7
- RED: grep bats over `commands/arch/orchestrate.md` — exists; frontmatter
  `description`/`argument-hint`/`allowed-tools`; `speccraft-state plugin-root` + sources
  the lib; token order `new → reviewed → planned → implemented → validated`; both
  checkpoint labels + `--straight-through`; `spec:close`; `resume`/`in_flight`;
  `blocked`; `list-members`/`ledger-set`/`reconcile`.
- GREEN: author `commands/arch/orchestrate.md` (mirror `decide.md` frontmatter +
  bootstrap): confirm decomposition; **seed member rows only** (no `spec:new` at
  seeding); per member resume via `orch_next_phase`, set `in_flight`, `orch_dispatch`
  cwd-scoped, `orch_apply_result` after; review loop under `orch_review_verdict`;
  `validate` gates on `orch_validate` then `spec:close`; finish `reconcile`. Include
  every literal anchor.

### Step 15 — Refactor (optional)
- Dedupe case-map scaffolding; confirm all error paths route through
  `orchestrate_error`; no lib assignment shadows zsh-reserved `status`.

## Delegation
- All steps → in-house (pure-function shell + bats + `.md` runbook, the repo's
  established `arch:*` pattern; no Go). No `/speccraft:spec:override` (shell + markdown
  are ungated).

## Risk
- **No guard-disarm risk, no override needed** → bats is the RED oracle; run the bats
  after each RED (expect fail) and GREEN (expect pass); never batch a GREEN ahead of RED.
- **Step 11 needs the built `./bin/speccraft-state` + `kind=workspace` fixture** →
  `setup()` builds/patches PATH; fixtures write `kind = "workspace"` + member specs.
- **Member-path charset must reject a literal `'`** → explicit `'`-case RED so
  `orch_dispatch`'s single-quoting can never be broken out of (eval-injection).
- **stdout/stderr contract** → assert non-empty `orchestrate:`-prefixed **stderr** on
  errors; use bats `run --separate-stderr` (or `2>` capture) where stderr is asserted.
- **zsh-reserved `status`** → the lib returns via stdout/exit; never assigns `status`.
