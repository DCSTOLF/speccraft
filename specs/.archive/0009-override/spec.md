---
id: "0009"
title: "fix override no-op"
status: closed
created: 2026-06-08
authors: [claude]
packages: ["tools/internal/speccraft", "tools/cmd/speccraft-guard"]
related-specs: []
---

# Spec 0009 — fix override no-op

## Why

The `/speccraft:spec:override` slash command is advertised as the escape hatch for editing Go production code without a sibling test edit in the same change. Today it is fully broken: invoking it runs to completion but has no observable effect — the Go/Python production guard still fires on the next edit.

Root cause analysis identified three concrete gaps:

1. **State schema gap.** `State.Session` (`tools/internal/speccraft/state.go`) has no `OverridePending` field. Go's `encoding/json` silently drops unknown keys, so any attempt to persist `"override_pending": true` into `state.json` is lost on the next `LoadState` call.
2. **State CLI gap.** `SetField` / `GetField` in `state.go` only know about `active_spec`. A call to `speccraft-state set override_pending true` falls through to the `default:` arm and is a no-op.
3. **Guard gap.** `goPythonProdGuard` in `tools/cmd/speccraft-guard/main.go` only inspects `state.ActiveSpec` and `hasSiblingTestEdited`. There is no code path that honours an override flag, so the invariant fires unconditionally.

The net effect is that the documented override workflow does not work, which both undermines user trust in the guardrail system and blocks legitimate edits (e.g. refactors, dependency bumps) that have no natural sibling test.

## What

Wire `override_pending` end-to-end through the state schema, the state CLI, and the Go/Python production guard so that setting the flag once allows exactly one subsequent guarded edit and is then automatically cleared.

In scope:

- Add `Session.OverridePending bool` (json tag `override_pending,omitempty`) to `state.go`.
- Add `ConsumeOverride(root string) (bool, error)` to `state.go` — atomic read-and-clear: returns `true` exactly once if the flag was set, and persists `false` immediately.
- Extend `GetField` / `SetField` to recognise the `override_pending` key with string values `"true"` / `"false"`.
- Modify `goPythonProdGuard` in `tools/cmd/speccraft-guard/main.go` to call `ConsumeOverride` before the sibling-test check; on `true`, allow the edit and return `nil`.
- Add unit tests covering `ConsumeOverride` semantics and the guard short-circuit behaviour.

## Acceptance criteria

1. **State round-trip persists the flag.** Given a `state.json` written via `SetField("override_pending", "true")`, a subsequent `LoadState` returns a `Session` whose `OverridePending` field is `true` (i.e. the value survives JSON serialisation and deserialisation).
2. **`ConsumeOverride` clears on read.** Given `OverridePending == true` on disk, the first call to `ConsumeOverride(root)` returns `(true, nil)`, and a second immediate call returns `(false, nil)`. After the first call, `state.json` on disk reflects `override_pending: false` (or the key omitted).
3. **`GetField` reports the current value.** `speccraft-state get override_pending` prints `"true"` when the flag is set and `"false"` (or empty, consistently with `active_spec` semantics) when it is not. Unknown keys continue to behave as before.
4. **Guard short-circuits with override.** Given `OverridePending == true` and an edit to a Go production file with no sibling test edited, `goPythonProdGuard` returns `nil` (edit allowed) and consumes the flag — a follow-up identical edit with no override set is rejected with the existing sibling-test error.
5. **Guard behaviour unchanged without override.** Given `OverridePending == false` (or unset), `goPythonProdGuard` behaves exactly as it does today: edits with a sibling test in the same batch are allowed; edits without one are rejected with the existing error message. No new code paths execute for non-Go/Python files.
6. **Unit tests cover the contract.** `TestConsumeOverride` asserts the set → consume `true` → consume `false` sequence against a temp `state.json`. A guard-level test asserts that with `override_pending=true` and no sibling test, the guard returns `nil` and the flag is cleared after the call.

## Out of scope

- The Rust dispatch path (`rustDispatch` in `speccraft-guard`) — override is not wired through Rust in this spec.
- Changes to the `/speccraft:spec:override` slash-command markdown or its argument parsing; this spec assumes the command already invokes `speccraft-state set override_pending true` correctly.
- Multi-edit / multi-spec override semantics (e.g. "override the next N edits"). Override remains single-shot.
- Audit logging or telemetry for override usage.
- UX changes to the guard error message when override is absent.

## Open questions

_none_
