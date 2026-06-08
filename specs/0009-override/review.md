# Review: Spec 0009 — fix override no-op

## Verdict

**Overall: changes-requested** — quorum is met (claude-p approved with comments) but five mandatory fixes must land in `spec.md` and `commands/spec/override.md` before planning. None require redesigning the approach.

## Quorum

| Agent | Verdict |
|---|---|
| codex | changes-requested |
| claude-p | approve-with-comments |

Required: 1 approve or approve-with-comments → **quorum met**

## Resolved disputes

### Single-writer rule (codex concern #1)

Codex flagged a guardrail violation: ConsumeOverride called from speccraft-guard writes state.json "outside the speccraft-state binary."

**Resolved: no violation.** The guardrail prohibits *direct* edits from hooks/commands/tests. Routing through `state.go`'s `saveStateLocked` is the established pattern — `PostAcceptUpdateRustBaseline → AppendRustBaseline → saveStateLocked` already does this from speccraft-guard (main.go:247 + state.go:162). ConsumeOverride follows identical architecture. Codex misread the convention boundary.

However, codex is correct that `state_single_writer_test.go` must be updated — that test scans for `RustTestBaseline` and `RustGateFingerprint` by name; `OverridePending` needs the same coverage.

## Action items (must fix before plan)

1. **Bring `commands/spec/override.md` step 3 into scope.** The current markdown instructs the agent to "add a temporary entry to `.speccraft/state.json`" via a JSON snippet — it never names the CLI. An agent may use Write/Edit directly, bypassing the new wired path and reproducing the original bug. Fix: replace the JSON snippet with an explicit `speccraft-state set override_pending true` instruction. This is one line and converts a probabilistic fix into a deterministic one.

2. **Remove stale `post-tool-use.sh` note from `override.md`.** Step 3 claims "post-tool-use.sh clears it after the first production edit." That code does not exist, and this spec moves clearing into `ConsumeOverride`. The stale note misdescribes the design and will confuse future readers.

3. **Fix AC #3 output format — pick `"true"`/`"false"`.** The current wording "false (or empty, consistently with `active_spec` semantics)" is untestable: `doGet` in `speccraft-state/main.go` prints `null` for unset fields, not empty string. AC #3 should require `speccraft-state get override_pending` to print `"true"` when set and `"false"` when not. Both values should be machine-readable booleans.

4. **Pin ConsumeOverride placement in AC #4.** State explicitly: ConsumeOverride is called *after* the `ActiveSpec == ""` check and spec-status check, immediately before the sibling-test branch. Corollary for AC #5: a missing active-spec or wrong-status condition returns an error *without* consuming the flag (the flag is preserved for the next corrected attempt). This prevents silent flag burn-through on misuse.

5. **Add `state_single_writer_test.go` to in-scope work.** The new `Session.OverridePending` field assignment must be added to the test's grep patterns so the single-writer guardrail covers it. Add one bullet to the What section and a corresponding acceptance criterion (or fold into AC #6).

## Suggestions (optional)

- Add a `TestSetField_OverridePending` round-trip test explicitly — AC #6 names `TestConsumeOverride` and the guard test but not the `SetField`/`GetField` path. AC #1 implicitly depends on it; naming it avoids an implementation gap.
- With `omitempty` on the field, the key will be absent (not `false`) when unset. Clarify in AC #2 that "key omitted" is the expected on-disk form after consume, so implementers don't assert literal `"override_pending": false`.
- Note consume-on-error semantics once: with ConsumeOverride called inside the guard, the flag is consumed regardless of whether the tool call later succeeds downstream. This is the right trade-off (atomic + simple) but should be documented so future readers don't assume "one successful edit" semantics.

## Guardrail / convention status

- No guardrail violations in the final analysis.
- One convention obligation not yet reflected: `state_single_writer_test.go` allow-list update (action item #5).
