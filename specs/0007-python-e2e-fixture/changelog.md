---
spec: "0007"
closed: 2026-05-29
---

# Changelog — 0007 Python e2e fixture

## Shipped

Pure test-infrastructure work; no Go or hook code changed. Landed in commit `383c928`.

- **AC #1 (script skeleton).** `tests/e2e/python_cycle.sh` (~149 lines) — `#!/usr/bin/env bash`, `set -euo pipefail`, `REPO_ROOT` derived from `${BASH_SOURCE[0]}`, `WORK=$(mktemp -d -t python-cycle.XXXXXX)`, `trap cleanup EXIT` honoring `KEEP_E2E=1`, `fail()` exiting 2, `note()` for progress. Marked executable.
- **Build block.** Both `speccraft-guard` and `speccraft-state` built from `tools/cmd/` into `$WORK`. No cargo shim (Python's guard path is pure file-classification + session-state lookup).
- **Fixture layout (T3).**
  - `src/foo.py` + `src/test_foo.py` — sibling pair (AC #2).
  - `src/pkg/bar.py` + `tests/test_bar.py` — separate-tree pair (AC #3).
  - `src/loners/orphan.py` — no-test-anywhere (AC #4).
  - `.speccraft/state.json` seeded with `active_spec: "0007-python-e2e-fixture"` and empty edited-file lists.
  - `specs/0007-python-e2e-fixture/spec.md` seeded with `status: in-progress` so the guard's status check passes.
- **Helpers.**
  - `reset_state()` rewrites a fresh `state.json` so each AC scenario is independent of the others.
  - `hook_input(path)` emits the Claude Code PreToolUse JSON envelope (`tool_name=Edit`, `tool_input.file_path`, `cwd=$PROJ`).
- **AC #2 (tier-1 sibling).** Reject-then-accept block: hook on `src/foo.py` exits non-zero and stderr names `test_foo.py`; after `speccraft-state track-edit src/test_foo.py` (invoked from inside `$PROJ`), the same hook exits 0.
- **AC #3 (tier-2 separate tree).** `.speccraft/speccraft.toml` written with `[tdd] test_roots = ["tests"]`. After `reset_state`, hook on `src/pkg/bar.py` is rejected and cites `test_bar.py`; after track-edit on `tests/test_bar.py`, the hook accepts.
- **AC #4 (no-test-anywhere).** After `reset_state`, hook on `src/loners/orphan.py` is rejected and stderr contains the literal `(none found)` (matches `goPythonProdGuard` in `tools/cmd/speccraft-guard/main.go`).
- **AC #5 (test-file always allowed).** After `reset_state`, hook on `src/test_foo.py` (the test file itself) exits 0 with no prior `track-edit`. Confirmed against `dispatchByLanguage`'s `IsTestFile` short-circuit.
- **AC #6 (wiring).** `tests/e2e/run.sh` counter bumped from `[N/8]` to `[N/9]` across all eight prior steps; new step `[9/9] Python dispatch (spec 0007)` invokes `python_cycle.sh` in a hermetic subshell using the same `RUST_E2E_DIR` already defined for the spec-0005 step, with `fail`/`pass` wrapping.
- **AC #7 (exit-2 convention).** Provided by the `fail()` helper from T1; documented inline in the script's header.

## Deviations from spec body

- **AC #3 fixture-layout fix (discovered at T4).** The spec originally placed `bar.py` at `src/bar.py` alongside the AC #2 fixture (`src/foo.py`, `src/test_foo.py`). Tier 1 of `SiblingTestFiles` is a directory glob (`test_*.py` / `*_test.py` in the same dir), not a stem match — so it would have matched `src/test_foo.py` and tier 2 (separate-tree walk) would never have fired, masking the behavior AC #3 was meant to verify. Implementation moved `bar.py` to `src/pkg/` and `orphan.py` to `src/loners/`, each in a directory with no `test_*.py` neighbors. The Go behavior is correct; the spec's fixture layout was the bug. Documented in inline script comments.
- **`reset_state()` helper not required by the spec.** Spec implies independence between AC scenarios but doesn't mandate a helper. Adding it was a planner correctness fix — without it, residue from `EditedTestFiles` would have leaked from AC #2 into AC #3/#4/#5 and accept-by-default-masked the rejection assertions. Kept as a small inline helper rather than the more elaborate `assert_reject` / `assert_accept` pair the optional T11 refactor would have introduced.
- **Planning skipped cross-model review.** Plan was generated with `/speccraft:spec:plan --skip-review` against a `status: draft` spec; the spec+plan should be treated as a paired artifact in PR review.

## Deferred

- **T10 — CI green.** Not verified; pre-existing CI infrastructure failures unrelated to spec 0007 prevent the `[9/9]` step from ever being reached:
  - Older CI runs failed at `[N] /speccraft:spec:review` with `EACCES` on `/home/vscode/.claude/session-env` (devcontainer permission issue).
  - Recent runs (`079ed25`, `383c928`) failed at `[5/N] /speccraft:spec:plan` with `"Credit balance is too low"` (Anthropic API quota).
  - Step `[9/9] Python dispatch` has not been reached in any CI run.
  - The script passes locally in the devcontainer; the failure mode is upstream of the new step.
- **T11 — optional refactor.** Deliberately skipped. Duplication exists (five reject/accept blocks share a small structure) but the linear form is more self-documenting than a ~30%-shorter helper extraction would be. If a fourth scenario is ever added, revisit.

## Follow-up tracked

- **Spec 0008 (CI hardening) — to be filed immediately after this closure.** Will address:
  - Devcontainer permissions on `/home/vscode/.claude/session-env` to fix the `EACCES` on `/speccraft:spec:review`.
  - Credit-balance handling so the e2e workflow does not hard-fail on transient API quota errors at `/speccraft:spec:plan`.
  - Retroactive verification of AC #8 / T10 for this spec once the upstream failures are fixed.
- Spec 0008 is **not yet on disk** at the time of writing this changelog; it will be filed via `/speccraft:spec:new` as the next step.

## Test coverage summary

| AC  | Behavior                                  | Assertion block in `python_cycle.sh`             |
|-----|-------------------------------------------|--------------------------------------------------|
| 1   | Script skeleton, executable, hermetic     | Header + `trap cleanup EXIT` + `fail`/`note`     |
| 2a  | Tier-1 sibling: reject without track-edit | `==> AC #2 ...` — first reject block             |
| 2b  | Tier-1 sibling: accept after track-edit   | `==> AC #2 ...` — second accept block            |
| 3a  | Tier-2 separate tree: reject              | `==> AC #3 ...` — first reject block             |
| 3b  | Tier-2 separate tree: accept              | `==> AC #3 ...` — second accept block            |
| 4   | No-test-anywhere: `(none found)`          | `==> AC #4 ...`                                  |
| 5   | Test-file edits always allowed            | `==> AC #5 ...`                                  |
| 6   | Wiring as `[9/9]` in `run.sh`             | `tests/e2e/run.sh` step `[9/9] Python dispatch`  |
| 7   | Exit 2 on assertion failure               | `fail()` helper (T1)                             |
| 8   | CI green                                  | **Deferred — see "Deferred" above.**             |
