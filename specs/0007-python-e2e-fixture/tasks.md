---
spec: "0007"
---

# Tasks

- [x] T1 — Create `tests/e2e/python_cycle.sh` skeleton (shebang, `set -euo pipefail`, `mktemp -d`, cleanup trap, `fail`/`note` helpers, chmod +x)
- [x] T2 — Add binary build block (`speccraft-guard` + `speccraft-state` into `$WORK`)
- [x] T3 — Add shared Python fixture (src/foo.py + src/test_foo.py, src/pkg/bar.py + tests/test_bar.py, src/loners/orphan.py, .speccraft/state.json with active spec, in-progress spec.md, `hook_input()` helper)
- [x] T4 — AC #2 tier-1 sibling: assert rejection without track-edit, then acceptance after `speccraft-state track-edit src/test_foo.py`
- [x] T5 — AC #3 tier-2 separate tree: write `.speccraft/speccraft.toml` with `[tdd] test_roots = ["tests"]`, reset session, assert rejection then acceptance after track-edit on `tests/test_bar.py`
- [x] T6 — AC #4 no-test-anywhere: reset session, assert rejection of `src/loners/orphan.py` with `(none found)` in stderr
- [x] T7 — AC #5 test-file always-allowed: reset session (empty edited list), assert hook on `src/test_foo.py` exits 0 with no prior track-edit
- [x] T8 — Wire into `tests/e2e/run.sh`: bump `[N/8]` → `[N/9]` and add `[9/9] Python dispatch` subshell after the Rust integration step (AC #6)
- [x] T9 — Verify exit-2 convention by inducing a controlled failure locally and observing `$? == 2` (AC #7)
- [ ] T10 — Push and verify CI green for the Python step in the e2e workflow (AC #8)
- [ ] T11 — Optional refactor: factor `reset_session()` and `assert_reject` / `assert_accept` helpers if call-site duplication exceeds two repetitions
