---
spec: "0013"
closed: 2026-06-10
---

# Changelog — 0013 Remove dead `ActiveSpec == "null"` checks

## What shipped vs spec

Bounded post-0012 cleanup. Six tasks landed in
T1 → T2 → T3 → T4 → T6 → T5 order (T6 was a mid-implementation
amendment, see below). Two production one-line removals plus
three pieces of supporting test work, plus one CI workflow fix:

- **T1.** New `tools/internal/speccraft/root_test.go` with three
  test functions. The load-bearing
  `TestActiveSpecDir_LiteralNullReturnsJoinedPath` RED-failed
  against pre-removal `main` (the dead clause short-circuited
  `"null"` to `""`).
- **T2.** Removed `|| activeSpec == "null"` from
  `tools/internal/speccraft/root.go:45` (`ActiveSpecDir`). All
  three T1 tests went GREEN.
- **T3.** Extended `tools/cmd/speccraft-guard/main_test.go` with
  `Test_ProdGuardPrologue_MissingActiveSpecKeyBlocks`. Fixture
  uses `os.WriteFile` of the AC3-pinned omitempty-cleared shape
  (`{"version":1,"session":{...}}` with no `active_spec` key) —
  distinct from `makeTestRepo`'s `"active_spec":null` shape. This
  is an assertion-pinning refactor: the test passes both BEFORE
  and AFTER T4.
- **T4.** Removed `|| state.ActiveSpec == "null"` from
  `tools/cmd/speccraft-guard/main.go:353` (`prodGuardPrologue`).
  T3 stayed green; all existing tests stayed green.
- **T6 (amendment).** Extended `.github/workflows/ci.yml` `hooks:`
  job: added `actions/setup-go@v5` and a `go build` step
  producing `bin/speccraft-state` + `bin/speccraft-guard` from
  `tools/` before `Run hook tests`. Without this, the
  `pre-tool-use-state-guard.bats` reject cases from spec 0012
  silently passed because `speccraft-state find-root` was not on
  `$PATH` in CI — the hook's first line short-circuits to
  `exit 0` when `find-root` returns empty.
- **T5.** Verification gate: `go test ./...` from `tools/` green;
  `bats tests/hooks/` from repo root green; AC1 grep oracle zero
  matches; `bin/speccraft-guard` rebuilt locally; new test names
  confirmed via `go test -list`.

### Deviation: mid-implementation amendment (T6)

T6 was not in the original T1–T5 plan. After pushing T1–T5
(commit 23d81e3), CI run 27274882006 surfaced a spec-0012 CI
miss: the `Hook tests (bats)` job at
`.github/workflows/ci.yml:49-62` ran `bats tests/hooks/` without
first building the helper binaries. Spec 0012's new
`pre-tool-use-state-guard.bats` reject cases silently passed
because the hook's `ROOT="$(speccraft-state find-root ...)"`
returned empty (binary not on PATH) and the
`[ -z "$ROOT" ] && exit 0` short-circuit no-op'd the hook before
any guard could fire. Locally the tests passed because T5 had
rebuilt `bin/` from source — the failure was CI-only.

Per user direction, the fix was folded into 0013 as T6 + a new
AC5 + a dated `## Amendment (2026-06-10)` section in `spec.md`,
rather than spun off as spec 0014. Rationale: the edit is a
strictly bounded one-file workflow change, main CI stays red
until it lands, and it shares the "post-0012 cleanup" theme.
This pattern is codified as a new convention in this close
batch — see the §"Conventions proposed" entry below.

## CI close-gate evidence (AC5)

CI run **27275588005** on commit 9c1330d reports green across all
five jobs, including `Hook tests (bats)` (9/9 OK:
`pre-tool-use-state-guard.bats` 6/6 + `session-start.bats` 3/3)
and `e2e-devcontainer`. Run URL:
https://github.com/DCSTOLF/speccraft/actions/runs/27275588005

This run satisfies both spec 0013's new AC5 close gate **and**
the still-open spec 0012 AC5 close gate (which was pending at
0012's close — the `e2e-devcontainer` job was the verification
target).

### Cross-reference to spec 0012's AC5

Spec 0012's `changelog.md` carries an explicit
`<!-- TODO: <github-actions-run-url> -->` marker at the
post-merge verification line. Per the
`conventions.md` → "Close-commit invariant" → "No post-close
edits" rule, closed specs are immutable. The convention is
upheld: 0012's TODO marker is intentionally left in place as a
historical record of the deviation (close-gate pending at
close time). Run 27275588005 is recorded here in 0013's
changelog as the canonical evidence; future readers tracing
0012's close gate should find this cross-reference via
`history.md` (which lists 0013 immediately after 0012).

This cross-reference pattern — record the gate URL in the
closing-since spec, leave the predecessor's TODO marker intact
— is the canonical workaround for the close-gate-pending case.
A post-close changelog backfill exception was evaluated during
this close batch and explicitly rejected in favor of strict
immutability.

## Files touched

- `tools/internal/speccraft/root.go` (1-line removal)
- `tools/internal/speccraft/root_test.go` (new)
- `tools/cmd/speccraft-guard/main.go` (1-line removal)
- `tools/cmd/speccraft-guard/main_test.go` (extended)
- `.github/workflows/ci.yml` (T6 amendment: setup-go + build step)
- `specs/0013-remove-dead-active-spec-null-checks/` (spec + plan
  + tasks + review + this changelog)

## Conventions proposed

- `conventions.md` § Spec lifecycle → new "Mid-implementation
  amendment" subsection codifying the T6-style fold-in pattern
  with three conditions (bounded edit, CI-blocking, theme
  overlap).
- Post-close changelog backfill exception was evaluated and
  rejected to keep strict immutability of closed specs.

## Out-of-scope follow-ups still queued

- README + `speccraft-v1-spec.md` CodeGraphContext copy cleanup
  (carried forward from spec 0011's §Out of scope; spec 0011
  scrubbed the skill / init.md / templates / architecture.md
  but not the top-level README or v1 spec).
- `/speccraft:spec:revise` command (carried forward from spec
  0011's §Out of scope).
- Spec 0001's CodeGraphContext mention is closed-spec immutable
  and accepted as historical record per spec 0011's history.md
  entry.
