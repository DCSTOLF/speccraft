# Changelog — Spec 0009 — fix override no-op

## Shipped

- New `Session.OverridePending bool` field on `state.go` (JSON tag `override_pending,omitempty`), plumbed through `GetField` / `SetField` (`"true"`/`"false"` string round-trip).
- New `ConsumeOverride(root string) (bool, error)` API on `state.go`: atomic read-and-clear under a single `mu.Lock()` using `loadStateLocked` and `saveStateLocked`. Returns `(was, nil)`; on `true` the flag is cleared before unlock so a second call returns `false`.
- `goPythonProdGuard` in `cmd/speccraft-guard/main.go` now calls `ConsumeOverride` after the spec-status check and before `SiblingTestFiles` lookup. When the flag was set, the guard returns `nil` (allow) and the flag is consumed in the same call — making override single-shot by construction.
- Single-writer test (`state_single_writer_test.go`) extended: `OverridePending` is now part of the grep allow-list, so only `speccraft-state` may assign it.
- Test coverage added:
  - `state_test.go`: `TestConsumeOverride_FlagSet_ReturnsTrueAndClears`, `TestConsumeOverride_FlagUnset_ReturnsFalse`, `TestConsumeOverride_AbsentStateFile_ReturnsFalse`, `TestSetField_OverridePending_RoundTrip`, `TestGetField_OverridePending` (table-driven, 3 cases).
  - `cmd/speccraft-guard/main_test.go`: `TestGoPythonProdGuard_OverridePending_AllowsAndConsumes`, `TestGoPythonProdGuard_OverridePending_SecondEditRejected`, `TestGoPythonProdGuard_OverrideUnset_BehavesAsToday`, `TestGoPythonProdGuard_OverrideDoesNotConsumeOnPrecondFail`.

## Files touched

- `tools/internal/speccraft/state.go`
- `tools/internal/speccraft/state_test.go`
- `tools/internal/speccraft/state_single_writer_test.go`
- `tools/cmd/speccraft-guard/main.go`
- `tools/cmd/speccraft-guard/main_test.go`

## Deviations

- **AC #3 precision:** spec said `GetField("override_pending")` should return `"false" (or empty, consistently with active_spec semantics)`. Implementation returns `"false"` consistently (never empty). This is stricter than the spec allowed and aligns with the bool round-trip in `SetField`; no functional deviation.
- **Out-of-scope (known gap):** review action item #1 — updating `commands/spec/override.md` step 3 — was explicitly deferred during planning and is not addressed here. The command markdown still instructs adding a temporary entry to `.speccraft/state.json` directly rather than calling `speccraft-state set override_pending true`. Not a code defect (the guard honours the flag regardless of who set it), but the user-facing docs remain stale and should be tracked separately.

## Post-merge verification

All tests pass: `GOWORK=off go test ./...` green.
