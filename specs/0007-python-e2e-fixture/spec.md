---
id: "0007"
title: "Python e2e fixture"
status: in-progress
created: 2026-05-29
authors: [claude]
packages: ["tests/e2e"]
related-specs: ["0002", "0003"]
---

# Spec 0007 — Python e2e fixture

## Why

speccraft ships Python TDD support via specs 0002 (sibling-test resolution) and 0003 (separate `tests/` tree resolution). Both have solid unit-test coverage in `tools/internal/speccraft/files_test.go` (sibling discovery, two-tier lookup). They have **no end-to-end coverage** — no test that drives `speccraft-guard` against a real Python project layout through the full PreToolUse hook flow.

The Rust spec 0005 set the pattern: standalone Bash e2e fixtures invoked from `tests/e2e/run.sh` as a numbered step. Go has e2e via the existing throwaway Go module in `run.sh` step 1. Adding the Python equivalent closes the symmetric-coverage gap: every supported language gets a real fixture that exercises the guard, the active-spec check, and the TDD invariant.

The gap was surfaced during CI hardening for spec 0005 — when wiring Rust e2e into `run.sh`, the Python omission became visible. This spec is the smallest possible follow-up that restores parity.

## What

Scope of this change:

1. **One new Bash fixture script** at `tests/e2e/python_cycle.sh` modeled on `rust_inline_cycle.sh`. The script must:
   - Build the `speccraft-guard` binary from source.
   - Create a temp Python project layout covering both sibling and separate-tree scenarios (one directory tree per scenario, or a unified tree exercising both).
   - Seed `.speccraft/state.json` with an active spec in `in-progress` status.
   - Drive `speccraft-guard` via the Claude Code hook JSON protocol on stdin (same approach the Rust scripts use).
   - Assert: (a) editing a prod `.py` file without a prior test edit in the session is rejected; (b) editing a prod file AFTER a sibling test edit is allowed; (c) editing a prod file when the matching test lives under a configured `[tdd] test_roots` directory is allowed; (d) the rejection message names the expected test-file location.

2. **Wire the script into `tests/e2e/run.sh`** as step `[9/9]` (after the Rust step from spec 0005). Update the existing `[8/8]` counters to `[9/9]`. Follow the same hermetic-subshell pattern: `( bash "$RUST_E2E_DIR/python_cycle.sh" ) || fail "python_cycle.sh failed"`.

3. **No new Go code.** The behaviors under test are already implemented in `tools/internal/speccraft/files.go` (specs 0002/0003); this spec adds e2e coverage only.

## Acceptance criteria

1. `tests/e2e/python_cycle.sh` exists, is executable (`chmod +x`), starts with `#!/usr/bin/env bash` and `set -euo pipefail`, and uses `mktemp -d` for an isolated work directory with a `trap` for cleanup.

2. **Tier-1 (sibling) scenario.** A test asserts that for a project containing `src/foo.py` and `src/test_foo.py`:
   - A hook invocation targeting `src/foo.py` with NO prior `track-edit` on `src/test_foo.py` in the session exits non-zero, and stderr names `src/test_foo.py` as the expected sibling.
   - After invoking `speccraft-state track-edit src/test_foo.py`, a subsequent hook invocation targeting `src/foo.py` exits 0.

3. **Tier-2 (separate `tests/` tree) scenario.** A test asserts that for a project containing `src/bar.py` and `tests/test_bar.py` with `.speccraft/speccraft.toml` declaring `[tdd] test_roots = ["tests"]`:
   - A hook invocation targeting `src/bar.py` with NO prior `track-edit` on `tests/test_bar.py` exits non-zero.
   - After `speccraft-state track-edit tests/test_bar.py`, the hook accepts the edit.

4. **No-test-anywhere scenario.** A test asserts that for `src/orphan.py` with no `test_orphan.py` and no `*_test.py` anywhere in `test_roots`, the hook exits non-zero with a stderr message listing `(none found)` (or equivalent — match the existing Go/Python behavior in `goPythonProdGuard`).

5. **Test-file edits always allowed.** A test asserts that a direct hook invocation targeting `src/test_foo.py` (the test file itself) exits 0 regardless of session state.

6. The script is invoked from `tests/e2e/run.sh` as step `[9/9]` after the Rust step; an existing `[8/8]` counter is updated to `[9/9]`. The new step uses the same hermetic-subshell + `fail` + `pass` pattern as the Rust step.

7. The script exits 0 when all assertions pass and exits 2 (matching the Rust scripts' convention) on any assertion failure.

8. CI green: a push to `main` triggers the e2e workflow and the Python step passes inside the devcontainer with no additional toolchain dependencies (Python 3 is already present in the base image — `python3 --version` is sufficient; the script does NOT need `pytest` to be installed because the assertions are about the *guard*'s recognition of test files, not about running tests).

## Out of scope

- Rewriting the Go (`speccraft-guard`) implementation. Specs 0002 and 0003 own the behavior; this spec exercises it.
- New Go unit tests. Existing coverage in `files_test.go` is sufficient.
- Running real pytest invocations. The Python e2e tests the *guard* (which is a file-classification + state-tracking flow), not Python's test runner.
- Cross-platform Python detection (Windows paths, etc.). The fixture targets Linux only, matching the rest of the e2e suite.
- Adding Python to the cargo-preamble model. The e2e cargo preamble (spec 0005 AC #9) stays — it gates Rust availability, not Python. Python uses the always-present `python3` from the base devcontainer image and does not need a preamble.
- Inline-tests-style discovery for Python (none of speccraft's Python support recognizes anything Rust-style; mentioned only to be explicit that Python's sibling/two-tier model is the only contract).

## Open questions

_none_
