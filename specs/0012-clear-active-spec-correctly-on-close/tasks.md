---
spec: "0012"
---

# Tasks

- [x] T1 — RED: Go test for SetField clear semantics on active_spec (`tools/internal/speccraft/state_clear_test.go`)
- [x] T2 — GREEN: implement clear semantics in SetField + `omitempty` on `ActiveSpec` (`tools/internal/speccraft/state.go`)
- [x] T3 — RED: bats test for PreToolUse hook state.json guardrail (`tests/hooks/pre-tool-use-state-guard.bats`)
- [x] T4 — GREEN: implement PreToolUse state.json guardrail + extend hook matcher (`hooks/pre-tool-use.sh`, `hooks/hooks.json`)
- [x] T5 — RED: Go test for `speccraft-state init` subcommand (`tools/cmd/speccraft-state/main_test.go`)
- [x] T6a — GREEN: implement `speccraft-state init` + `InitState` helper (`tools/cmd/speccraft-state/main.go`, `tools/internal/speccraft/state.go`)
- [x] T6b — GREEN: migrate `commands/init.md` step 8 to call `speccraft-state init` (`commands/init.md`)
- [x] T7 — GREEN: tighten `commands/spec/close.md` with no-direct-edit prohibition (`commands/spec/close.md`)
- [x] T8 — GREEN: document `Test<UpperCamel>` + `Test_<Subject>_<Scenario>` as acceptable (`.speccraft/conventions.md`)
- [x] T9 — REFACTOR (optional): full `go test ./tools/...` + `bats tests/hooks/`; portability scan of `pre-tool-use.sh`
