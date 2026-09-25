---
spec: "0049"
closed: 2026-09-25
---

# Changelog — 0049 Command-lib portability and sanctioned PM/Architect status writers

**Status:** closed · **Ships in:** unreleased at 1.16.0 (see Resolved decision 1) · **Date:** 2026-09-25

## What shipped

A field report said `/speccraft:arch:decide` reported success and left the design
at `status: draft`, dropping a stray `design.md-E` sibling. One line was
responsible, and the sweep it prompted found the same failure class twice more.

### The three production fixes

1. **`commands/arch/decide.lib.sh`** — the GNU-only in-place stream edit is gone.
   `arch_set_status` keeps its `draft`-only source gate and delegates the write
   to `speccraft-state set-status --kind design`.
2. **`commands/pm/prioritize.lib.sh`** — carried a byte-identical copy of the
   same line, so `/speccraft:pm:prioritize` had the same silent no-op on macOS.
   Now delegates with `--kind brief`.
3. **`commands/spec/consolidate.lib.sh:409`** — `tac` (GNU-only, absent on
   macOS) replaced by a POSIX `awk` reversal. This one was the worst-behaved: a
   missing command inside a process substitution yields empty input, the `while`
   body never runs, and `set -euo pipefail` never fires, so
   `consolidate_backfill_order` silently dropped its entire
   history-chronological half and spec 0025's AC11 ordering contract was void on
   macOS with no error.

Both delegating helpers resolve the binary explicitly — `$SPECCRAFT_STATE_BIN` → `PATH`
→ plugin-local `bin/` (from the lib's own `${BASH_SOURCE[0]:-$0}` location) — and name the
resolved path in the failure diagnostic. Because PATH wins over the plugin-local copy, the
Linux `hooks` job now prepends the freshly built `bin/` to `$GITHUB_PATH`; without it a
stale ambient `speccraft-state` with no `--kind` flag is picked up and the suite fails for
the wrong reason. This bit live in the devcontainer, where `command -v speccraft-state`
resolves to a cached 1.11.0 build.

### Kind-scoped status enum

`tools/internal/speccraft/revision.go` gains `type ArtifactKind string` with
`KindSpec`/`KindDesign`/`KindBrief`, and the flat `validStatuses` map becomes
`kindStatuses` — spec keeps its six statuses, design gets
`draft/decided/closed`, brief gets `draft/prioritized/closed`. `SetStatus` is
now `SetStatus(path, kind, status)`; there is **no compatibility wrapper**,
because a kind-defaulting wrapper is the silent-default surface this spec
removes. `ArtifactKind` has no meaningful zero value: the empty kind is an
error, checked before status validation. The no-`--kind` CLI default maps to
`KindSpec` in `tools/cmd/speccraft-state/set_status_cmd.go` — the flag-parsing
layer — and nowhere else.

### Both guard gaps closed

- **`tests/hooks/frontmatter-writer-guard.bats`** — the path-shape filter covered
  only `spec.md`-shaped targets, which is exactly how spec 0022's design and
  brief writers sat outside spec 0036's guardrail. Widened to all three artifact
  kinds and to non-literal targets, with the escaped line carried verbatim as a
  FORBIDDEN fixture. The scan root stays `commands/` and a test pins that it
  excludes `specs/` — load-bearing, since this spec's own archived copy will
  quote the forbidden line.
- **`tests/hooks/portability-guard.bats`** (new) — fixture-first guard over the
  shipped surfaces for eight GNU-only forms, 13 forbidden and 10 permitted
  fixtures. Matching is prefix-safe (`sed -i` must not match `sed -i.bak` or
  `sed -i ''`) and there is no escape hatch.

### The runner that makes the class self-catching

`ci.yml` gains **`hooks-macos`** (macos-14, full bats suite via Homebrew Bash 5).
The bug was **already covered** by `tests/hooks/arch-decide.bats`, which fails on
BSD sed — no new test was needed to catch it, only a runner.
`scripts/assert-no-gnu-userland.sh` runs before bats and fails loudly if the
runner is not BSD-userland-on-Bash-5, because a job greened by
`brew install coreutils` would have passed against all three defects here.

## Files touched

Recorded explicitly because 0049 shipped alongside unreleased work from 0047 in
the same working tree: `git diff` at close time does not separate them, and
`started_at_sha` was never set, so nothing had been committed since 1.16.0.

Production / shipped surfaces:

- `commands/arch/decide.lib.sh` — GNU-only in-place edit removed; `_arch_state_bin`
  resolver + delegation to `set-status --kind design`
- `commands/pm/prioritize.lib.sh` — same, `--kind brief`
- `commands/spec/consolidate.lib.sh` — `tac` → POSIX `awk` reversal
- `tools/internal/speccraft/revision.go` — `ArtifactKind`, `kindStatuses`, 3-arg `SetStatus`
- `tools/cmd/speccraft-state/set_status_cmd.go` (new) — the `set-status` flag layer
- `tools/cmd/speccraft-state/main.go` — `case "set-status":` now
  `return setStatusCmd(args[1:], stderr)`. The `case "tasks-verify":` hunk in the
  same file is spec 0047's, not 0049's.
- `.github/workflows/ci.yml` — new `hooks-macos` job; `$GITHUB_PATH` step added to `hooks`
- `scripts/assert-no-gnu-userland.sh` (new), `scripts/verify-linux-pins.sh` (new)

Tests:

- `tests/hooks/portability-guard.bats`, `no-gnu-userland.bats`,
  `tests-portability-sweep.bats`, `verify-linux-pins.bats` (all new)
- `tests/hooks/arch-decide.bats`, `pm-prioritize.bats` — per-layer non-zero-path coverage
- `tests/hooks/frontmatter-writer-guard.bats` — widened filter + archive-safety test
- `tests/hooks/spec-consolidate.bats` — `tac`-absent ordering over a both-halves fixture
- `tests/hooks/spec-revise-preflight.bats`, `init-workspace.bats` — GNU-only executions ported
- `tools/internal/speccraft/revision_test.go`, `frontmatter_writer_test.go`,
  `tools/cmd/speccraft-state/set_status_cmd_test.go`

## AC11 evidence

`scripts/verify-linux-pins.sh` reverts each production fix in a detached
worktree and requires the suite to notice, then asserts the caller's checkout is
byte-identical:

```
verify-linux-pins.sh: 3/3 pins confirmed
```

No fix in this spec is pinned only by the macOS runner.

## Corrections made during implementation

- **Three false-pass assertions, all "an assertion that cannot fail."** (1) A bare
  `! grep -q …` on its own line in a bats `@test` is inert — POSIX `set -e` ignores a
  `!`-negated failure, so the `@test` passed on its last line while the lib still
  contained the forbidden token. (2) A `;` mid-chain in a `done:` predicate discards
  everything before it. (3) `|| true` mid-chain did the same, and neutralised the single
  most important check in the spec — that the GNU-only `sed` was gone from both libs.
  All three were found by making each negative assertion prove it bites (reintroduce the
  forbidden thing, watch it go red, revert) and by refusing to "fix" a `done:` predicate
  that disagreed with a test until it was clear which one was lying. This is the spec's
  own bug class reproduced in the tests for the fix, and it is why a convention was
  codified.
- **AC10's "exactly one file, seven mutations" was wrong.** T13's mechanised
  sweep — required by carried review item 8 precisely so the claim would be
  reproducible — disproved it: the original hand sweep searched `grep -P ` with
  a trailing space and missed `grep -qP`. The true set is **two files, nine
  sites**: seven `sed -i` in `spec-revise-preflight.bats` plus two `grep -qP` in
  `init-workspace.bats:139-140`. Both ported; AC10 amended in place.
- **Override budget: 3 of 3 spent, against a plan estimate of 1.** The estimate
  missed that `ConsumeOverride` is per-EDIT, not per-task: T3 touched
  `revision.go` in two non-adjacent regions plus `main.go`. Spanning both
  `revision.go` regions in one edit would have cost 2.
- **Spec 0048's `red_candidates` clobber fired live.** Two tightening edits to a
  test file added no `func Test` line, so the guard reset that file's registered
  candidates and blocked T5. Worked around per the documented recipe; it is a
  real, still-open defect in the blocked spec.

## Follow-ups not in scope

- `commands/arch/close.md:36` and `commands/pm/close.md:24` still instruct a
  model to hand-edit `status:` → `closed` — the instruction-layer cousin of this
  bug. `--kind design|brief closed` now exists to fix it properly. No AC covered
  it, so it was deliberately left alone.
- A non-destructive `/speccraft:sync` pass that REPORTS stray `<file>-E`
  siblings with a recovery hint (claude-p, review round 1).
