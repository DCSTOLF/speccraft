---
spec: "0007"
status: planned
strategy: tdd
---

# Plan — 0007 Python e2e fixture

## Preamble

This plan was produced with **review skipped** at user request (planner
invoked with `--skip-review` against a `status: draft` spec). The
cross-model review step that normally precedes planning has been
bypassed; reviewers should treat the spec and this plan as a paired
artifact and apply extra scrutiny in PR review.

**TDD note.** The implementation is a single Bash fixture script
(`tests/e2e/python_cycle.sh`) plus a one-line edit to `tests/e2e/run.sh`.
Strict unit-test-style RED→GREEN cycles don't apply cleanly to a
self-asserting Bash script — the script *is* the test. The plan instead
sequences each acceptance criterion as a RED step (add an assertion
block that fails because the script doesn't yet exist, isn't yet wired
in, or the assertion block hasn't been written) followed by a GREEN
step that adds the minimum fixture/script logic to satisfy it. Each
GREEN step is verified by `bash tests/e2e/python_cycle.sh` exiting 0,
and the final wiring step is verified by `bash tests/e2e/run.sh`
showing `[9/9]` and exiting 0.

**Structural template.** `tests/e2e/rust_inline_cycle.sh` is the
explicit structural template. The Python script reuses its skeleton —
`mktemp -d` work dir, `trap cleanup EXIT`, `fail`/`note` helpers, two
binaries built from `tools/cmd/`, hook JSON on stdin — and differs only
in: (a) no cargo shim (the Python guard path is pure file-classification
+ session-state lookup; no external runner is invoked), (b) no
`PATH` manipulation, (c) Python fixture content instead of a Cargo
crate, (d) assertions on `goPythonProdGuard` rejection messages instead
of runner-outcome messages.

## Test-first sequence

### Step 1 — Skeleton + AC #1: script exists, executable, hermetic shell (RED→GREEN)

- Create `tests/e2e/python_cycle.sh` with:
  - `#!/usr/bin/env bash` shebang.
  - `set -euo pipefail`.
  - `REPO_ROOT` derived from `${BASH_SOURCE[0]}`.
  - `WORK="$(mktemp -d -t python-cycle.XXXXXX)"`.
  - `cleanup()` honoring `KEEP_E2E=1` and a `trap cleanup EXIT`.
  - `fail()` (exits 2) and `note()` helpers, matching `rust_inline_cycle.sh`.
  - Final `echo "OK: python_cycle e2e passed"`.
- `chmod +x tests/e2e/python_cycle.sh`.
- Verification: `bash tests/e2e/python_cycle.sh` exits 0; `test -x tests/e2e/python_cycle.sh` passes; `head -2` shows shebang + `set -euo pipefail`. **Satisfies AC #1.**
- RED rationale: before this step the file does not exist, so any later step's assertion harness has nothing to run.

### Step 2 — Build both binaries (GREEN extension)

- Add a build block to `python_cycle.sh`:
  ```
  GUARD_BIN="$WORK/speccraft-guard"
  STATE_BIN="$WORK/speccraft-state"
  ( cd "$REPO_ROOT/tools" && go build -o "$GUARD_BIN" ./cmd/speccraft-guard )
  ( cd "$REPO_ROOT/tools" && go build -o "$STATE_BIN" ./cmd/speccraft-state )
  ```
- Verification: script still exits 0; `$GUARD_BIN` and `$STATE_BIN` are executable inside `$WORK` during the run (proven implicitly by later steps invoking them).
- No cargo shim needed — Python's guard path never shells out to a runner.

### Step 3 — Shared Python project fixture (GREEN extension)

- Add a fixture-setup block:
  ```
  PROJ="$WORK/proj"
  mkdir -p "$PROJ/src" "$PROJ/tests" "$PROJ/.speccraft" \
           "$PROJ/specs/0007-python-e2e-fixture"
  ```
- Seed prod + test files used by all later assertions:
  - `src/foo.py`, `src/test_foo.py` (sibling pair — AC #2)
  - `src/bar.py`, `tests/test_bar.py` (separate-tree pair — AC #3)
  - `src/orphan.py` (no test anywhere — AC #4)
- Seed `.speccraft/state.json` with `active_spec: "0007-python-e2e-fixture"` and empty `edited_test_files`/`edited_prod_files`.
- Seed `specs/0007-python-e2e-fixture/spec.md` with `status: in-progress` frontmatter (so the guard's status check in `goPythonProdGuard` passes).
- Define a `hook_input()` helper that emits the Claude Code hook JSON envelope (`tool_name`, `tool_input.file_path`, `cwd`) given a path argument — keeps the assertion blocks short.
- Verification: script still exits 0; later assertions can reference these files.

### Step 4 — AC #2 tier-1 sibling: rejection then acceptance (RED→GREEN)

- Add assertion block 2a (rejection): pipe `hook_input "$PROJ/src/foo.py"` into `$GUARD_BIN pre-tool-use`. Expect non-zero exit and stderr containing `src/test_foo.py` (or `test_foo.py`) and the word `sibling` / `TDD invariant`. `fail` otherwise.
- Add assertion block 2b (acceptance after track-edit):
  - `( cd "$PROJ" && "$STATE_BIN" track-edit src/test_foo.py )`
  - Re-issue the same hook JSON; expect exit 0. `fail` otherwise.
- RED rationale: before the assertion block exists, AC #2 is not exercised. The block fails on first author until both the fixture (Step 3) and the guard wiring (already in `tools/cmd/speccraft-guard`) line up.
- Verification: `bash tests/e2e/python_cycle.sh` exits 0; manually breaking the guard's sibling lookup would cause this block to fail with exit 2.

### Step 5 — AC #3 tier-2 separate `tests/` tree: rejection then acceptance (RED→GREEN)

- Before the tier-2 block, write `$PROJ/.speccraft/speccraft.toml` with:
  ```
  [tdd]
  test_roots = ["tests"]
  ```
- Reset session state by writing a fresh `state.json` with empty `edited_test_files` (or call `speccraft-state` reset if available; otherwise just rewrite the JSON literal) — this keeps the AC #3 scenario independent of AC #2's mutations.
- Add assertion block 3a (rejection): hook JSON for `$PROJ/src/bar.py`. Expect non-zero exit and stderr naming `tests/test_bar.py` (or `test_bar.py`).
- Add assertion block 3b (acceptance): `( cd "$PROJ" && "$STATE_BIN" track-edit tests/test_bar.py )`, then re-issue hook JSON; expect exit 0.
- Verification: script exits 0; `[tdd] test_roots = ["tests"]` is the only mechanism that makes `tests/test_bar.py` reachable from `src/bar.py` via `SiblingTestFiles`.

### Step 6 — AC #4 no-test-anywhere with `(none found)` (RED→GREEN)

- Reset session state to empty `edited_test_files` again.
- Add assertion block: hook JSON for `$PROJ/src/orphan.py`. Expect non-zero exit and stderr containing the literal `(none found)`.
- Verification: matches `goPythonProdGuard`'s exact rejection message when `len(siblings) == 0`.

### Step 7 — AC #5 test-file edits always allowed regardless of session state (RED→GREEN)

- Reset session state to empty `edited_test_files`.
- Add assertion block: hook JSON for `$PROJ/src/test_foo.py` (the **test file itself**, not the prod sibling). Expect exit 0. **Do not** call `track-edit` first.
- Verification confirmed against code: `dispatchByLanguage` in `tools/cmd/speccraft-guard/main.go:134-136` short-circuits via `IsTestFile(absPath)` and returns `nil` *before* `goPythonProdGuard` is consulted. AC #5's "regardless of session state" claim is accurate — no session inspection happens on the test-file path.

### Step 8 — Wire into `run.sh` as `[9/9]` (RED→GREEN)

- Edit `tests/e2e/run.sh`:
  - Replace each occurrence of `[N/8]` with `[N/9]` for `N` in `1..8`.
  - After the existing `pass "rust_integration_cycle.sh"` line, add:
    ```
    echo "==> [9/9] Python dispatch (spec 0007)"
    ( bash "$RUST_E2E_DIR/python_cycle.sh" ) || fail "python_cycle.sh failed"
    pass "python_cycle.sh"
    ```
  - (`RUST_E2E_DIR` is already defined at step `[8/8]` and is just the e2e dir; reuse it. Rename optional but out of scope.)
- **Satisfies AC #6.** Verification: `grep -c '\[9/9\]' tests/e2e/run.sh` is ≥ 1; `grep -c '\[./8\]' tests/e2e/run.sh` is 0.

### Step 9 — AC #7 exit-2 convention verification (RED→GREEN)

- Confirmed already by Step 1's `fail()` helper (`exit 2`). No extra code needed.
- Verification: induce a failure locally (e.g., temporarily change an expected stderr substring) and observe `echo $?` reports `2`. Document the verification command in a code comment near `fail()` for future maintainers.

### Step 10 — AC #8 CI green (verification only)

- Push the branch; observe the e2e workflow on push to `main` (or on PR) shows the `[9/9] Python dispatch` step running and passing inside the devcontainer.
- Verification: no script change. If CI fails because `python3` is somehow missing from the image, file a follow-up — the spec explicitly notes Python 3 is part of the base image.

### Step 11 — Refactor (optional)

- If multiple assertion blocks repeat the "reset session state" JSON literal, hoist into a `reset_session()` helper inside the script.
- If the `hook_input()` helper accumulates more than one call site per scenario, factor a `assert_reject` / `assert_accept` pair that takes a file path and an expected-stderr-substring.
- All assertions still pass after refactor.

## Delegation

- All steps → keep with the implementing agent (Claude Code main thread). Reasons:
  - The work is a single self-contained Bash file plus a 4-line edit to `run.sh`. No multi-package coordination, no Go code, no cross-model review.
  - No step benefits from `opencode` (no large refactor) or `codex` (no algorithm-heavy logic). Aux-agent delegation overhead would dominate execution time.

## Risk

- **`speccraft-state track-edit` path semantics.** `goPythonProdGuard` compares `filepath.Abs(sibling)` against `state.Session.EditedTestFiles`; if `track-edit` stores the literal CLI argument (`src/test_foo.py`) but the guard compares against an abs path, the AC #2 acceptance step would silently still reject. Mitigation: invoke `track-edit` from inside `$PROJ` (`cd "$PROJ" && ...`) so relative paths resolve against the project root, matching the resolution the guard does for `absPath`. If a mismatch is observed during script authoring, fall back to passing absolute paths to `track-edit`.
- **`speccraft.toml` location.** `SiblingTestFiles` reads `[tdd] test_roots` from `.speccraft/speccraft.toml` (per spec 0003). If a stale `.speccraft/state.json` from AC #2 still references the project root before AC #3's config is written, no harm — the toml is read fresh on each guard invocation. But state-reset between scenarios is still required to avoid the prior `EditedTestFiles` carrying into AC #3/#4/#5.
- **`active_spec` reservation.** The fixture writes `specs/0007-python-e2e-fixture/spec.md` under `$PROJ` (not under `$REPO_ROOT`); this is correct because the guard resolves the spec path against the project root it computes from the hook's `cwd`. Risk only if a future guard change starts resolving against the repo root — out of scope here.
- **AC #4 message brittleness.** The spec says "`(none found)` (or equivalent)". The current `goPythonProdGuard` emits the literal string `(none found)`, so the assertion uses an exact substring match; if a future spec rewords this message, the assertion will need to follow. Documented inline in the script via a comment pointing at `main.go` line 358.
- **Python availability.** Spec AC #8 says "Python 3 is already present in the base image — `python3 --version` is sufficient." The script does not actually invoke `python3` (no test execution happens), so this is informational only; no preamble needed.

