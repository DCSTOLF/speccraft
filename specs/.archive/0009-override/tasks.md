---
id: "0009"
title: "fix override no-op"
spec: "0009"
---

# Tasks

- [x] T1 (RED, Step 1) — Add `TestSetField_OverridePending_RoundTrip` and `TestGetField_OverridePending` to `tools/internal/speccraft/state_test.go`
- [x] T2 (GREEN, Step 2) — Add `Session.OverridePending` field and `override_pending` arms to `SetField`/`GetField` in `tools/internal/speccraft/state.go`
- [x] T3 (RED, Step 3) — Add `TestConsumeOverride_FlagSet_ReturnsTrueAndClears`, `TestConsumeOverride_FlagUnset_ReturnsFalse`, `TestConsumeOverride_AbsentStateFile` to `tools/internal/speccraft/state_test.go`
- [x] T4 (GREEN, Step 4) — Implement `ConsumeOverride(root)` in `tools/internal/speccraft/state.go` using single-lock `loadStateLocked`+`saveStateLocked`
- [x] T5 (Step 5) — Append `\.OverridePending\s*=[^=]` regex to `patterns` in `tools/internal/speccraft/state_single_writer_test.go`
- [x] T6 (RED, Step 6) — Add four guard tests (`TestGoPythonProdGuard_OverridePending_AllowsAndConsumes`, `TestGoPythonProdGuard_OverridePending_SecondEditRejected`, `TestGoPythonProdGuard_OverrideUnset_BehavesAsToday`, `TestGoPythonProdGuard_OverrideDoesNotConsumeOnPrecondFail`) to `tools/cmd/speccraft-guard/main_test.go`
- [x] T7 (GREEN, Step 7) — Insert `ConsumeOverride` call in `goPythonProdGuard` after spec-status check, before sibling lookup, in `tools/cmd/speccraft-guard/main.go`
- [x] T8 (REFACTOR, Step 8) — Verify `Session` field ordering and confirm `GOWORK=off go test ./...` green
