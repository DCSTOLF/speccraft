---
spec: "0027"
---

# Tasks

- [x] T1 — RED: confirm the current `[10/13]` lifecycle failure at `run.sh:367` (`exists "$SPEC_DIR/changelog.md"`) caused by the consolidation dir-move; credit-gated, not locally runnable, evidenced by the reported CI log (AC1, AC3)
- [x] T2 — GREEN: edit `tests/e2e/run.sh` `[10/13]` — change the prompt to decline/defer consolidation (approve memory updates only) and add the `[ ! -d specs/.archive/0001-add-farewell-function ]` non-move assertion; keep lines 367/368; `bash -n` clean (AC1, AC4)
- [x] T3 — GREEN: extend `tests/e2e/spec_consolidate.sh` `[cons 2/3]` — add the inline-at-close lib-path equivalence comment (wiring pinned by 0025 verify.sh, mechanics by spec-consolidate.bats) and retain/tighten the positive move/merge/archive assertions; `bash -n` clean (AC2, AC4)
- [x] T4 — VERIFY: `bash -n` both files; structural inspection that AC1/AC2/AC4 hold (decline+non-move present, equivalence+outcome asserts present, only the two `.sh` files changed); full credit-gated lifecycle green deferred to the next `e2e-devcontainer` CI run (AC1, AC2, AC3 deferred, AC4)
