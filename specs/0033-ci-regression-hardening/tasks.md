---
spec: "0033"
---

# Tasks

- [x] T1 — RED: new `tools/internal/speccraft/e2e_fixture_shape_test.go` — `Test_E2EFixtures_NoWritePayloadUsesNewString` (fails on rust_integration_cycle.sh) + `Test_ConsolidateDeclineLeg_ImperativePrompt` (fails on current [cons 1/3] prompt) — AC3, AC4
- [x] T2 — GREEN: fix `tests/e2e/rust_integration_cycle.sh` Step-2 payload → `content` (drop old_string/new_string); guard test green; `bash rust_integration_cycle.sh` reaches OK — AC2, AC3
- [x] T3 — GREEN: make `tests/e2e/spec_consolidate.sh` [cons 1/3] decline prompt imperative (write consolidation-skip, don't move, don't ask; keep memory-audit separate); meta-test green — AC4
- [x] T4 — FIX: asymmetric assertion in `Test_ResolvePluginRoot_SymlinkedExe_ResolvesRealInstall` (`want = filepath.EvalSymlinks(root)`, `got` untouched); Linux stays green — AC1
- [x] T5 — VERIFY: `go test ./...` green, `bash rust_integration_cycle.sh` OK, `rust_inline_cycle.sh` OK, `bats tests/hooks/*.bats` 0-fail, only the 4 files changed, no version bump — AC5
