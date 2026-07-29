---
id: "0009"
title: "fix override no-op"
spec: "0009"
status: planned
strategy: tdd
---

# Plan — 0009 fix override no-op

## Test-first sequence

### Step 1 — Schema + SetField/GetField round-trip (RED)

Add to `tools/internal/speccraft/state_test.go`:

- `TestSetField_OverridePending_RoundTrip` — calls `speccraft.SetField(root, "override_pending", "true")`, then `speccraft.LoadState(root)` and asserts `s.Session.OverridePending == true`; then `SetField(..., "false")` and asserts `false`. Drives both the schema field and the `SetField` switch arm.
- `TestGetField_OverridePending` — table-driven over `{set:"true", want:"true"}`, `{set:"false", want:"false"}`, `{unset, want:"false"}`. Drives the `GetField` switch arm.

Tests fail because `Session.OverridePending` does not exist (compile error); after schema compiles, `SetField`/`GetField` return wrong value.

### Step 2 — Schema + SetField/GetField implementation (GREEN)

Edit `tools/internal/speccraft/state.go`:

- Add `OverridePending bool \`json:"override_pending,omitempty"\`` to `Session`.
- Add `case "override_pending": s.Session.OverridePending = (value == "true")` to `SetField`.
- Add `case "override_pending":` to `GetField` returning `"true"` / `"false"` based on `s.Session.OverridePending`.

`omitempty` keeps disk format byte-identical when unset; no behaviour change elsewhere.

### Step 3 — ConsumeOverride atomic read-and-clear (RED)

Extend `tools/internal/speccraft/state_test.go`:

- `TestConsumeOverride_FlagSet_ReturnsTrueAndClears` — `SetField(..., "true")`, call `ConsumeOverride(root)` → `(true, nil)`; second call → `(false, nil)`; read raw `state.json` bytes and assert `override_pending` key is absent (`omitempty` when false).
- `TestConsumeOverride_FlagUnset_ReturnsFalse` — fresh state, `ConsumeOverride` → `(false, nil)`, no error.
- `TestConsumeOverride_AbsentStateFile` — root with `.speccraft/` dir but no `state.json`, `ConsumeOverride` → `(false, nil)` (mirrors `loadStateLocked` no-file behaviour).

Tests fail: `ConsumeOverride` is undefined.

### Step 4 — ConsumeOverride implementation (GREEN)

Edit `tools/internal/speccraft/state.go`:

Add `ConsumeOverride(root string) (bool, error)`:
- Acquire single `mu.Lock()` (do NOT call `LoadState`/`SaveState` — that would race with `TrackEdit`).
- `loadStateLocked` → capture `was := s.Session.OverridePending`.
- If `was`, set `s.Session.OverridePending = false` and `saveStateLocked`.
- If not `was`, skip the save.
- Return `was, nil`. Wrap save errors with `fmt.Errorf("consume override: %w", err)`.

### Step 5 — Single-writer grep pattern (GREEN immediately)

Extend `tools/internal/speccraft/state_single_writer_test.go`:

Append `regexp.MustCompile(`\.OverridePending\s*=[^=]`)` to the `patterns` slice alongside the existing Rust field patterns.

Since `OverridePending` is only assigned inside `state.go` (the allowed file), this test passes immediately after the pattern is added. Acts as a regression guard against future accidental external writers.

### Step 6 — Guard honours OverridePending (RED)

Extend `tools/cmd/speccraft-guard/main_test.go`:

- `TestGoPythonProdGuard_OverridePending_AllowsAndConsumes` — tmp root, `active_spec="0009"`, `session.override_pending=true`; `specs/0009/spec.md` with `status: in-progress`; Go prod file; no sibling edited. `goPythonProdGuard` → `nil`. Re-load state → `Session.OverridePending == false`.
- `TestGoPythonProdGuard_OverridePending_SecondEditRejected` — same setup; first call `nil`; second call returns TDD-invariant error (flag single-use).
- `TestGoPythonProdGuard_OverrideUnset_BehavesAsToday` — no override set, no sibling edited → TDD-invariant error (existing behaviour).
- `TestGoPythonProdGuard_OverrideDoesNotConsumeOnPrecondFail` — `active_spec=""` AND `override_pending=true` → "No active spec" error AND flag remains `true` on disk (consume only after pre-conditions pass).

Tests fail: `goPythonProdGuard` never calls `ConsumeOverride`.

### Step 7 — Guard implementation (GREEN)

Edit `tools/cmd/speccraft-guard/main.go`, inside `goPythonProdGuard`, after the spec-status check and BEFORE `siblings, _ := speccraft.SiblingTestFiles(...)`:

```go
if ok, err := speccraft.ConsumeOverride(root); err == nil && ok {
    return nil
}
```

Error is silently swallowed to match the existing `LoadState` error-swallow policy; the sibling check runs as safety net if ConsumeOverride fails.

### Step 8 — Refactor sweep (REFACTOR, optional)

- Verify `Session` field ordering: `OverridePending` placed near the top with `ID`/Edited slices (per-session lifecycle), not mixed into Rust-specific fields.
- Confirm full `GOWORK=off go test ./...` green under `tools/`.
