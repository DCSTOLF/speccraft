---
spec: "0013"
reviewers: [codex, claude-p]
quorum: 1
verdict: approve-with-comments
generated: 2026-06-10T00:00:00Z
---

# Cross-model review — 0013

## codex (gpt-5.5)

**Verdict:** approve-with-comments

Concerns:
- AC2 marks the `ActiveSpecDir(root, "null")` behavior pin as optional even though §What frames it as the intentional behavior change the spec is making; this leaves the planner discretion on the most important semantic assertion.
- AC2 and AC3 do not specify the working directory for their `go test` invocations; AC4 is explicit (`go test ./...` from `tools/`), but the earlier ACs use relative paths like `./internal/speccraft/` that are only unambiguous if the reader already knows the cwd.

Suggestions:
- Promote the optional `ActiveSpecDir(root, "null")` bullet in AC2 to a hard requirement; it is the pin that makes the behavior change verifiable, not merely plausible.
- Keep scope strictly bounded to the two named sites; folding in unrelated defensive cleanup would dilute the bounded-cleanup purpose and weaken the TDD story.
- Name the new test functions explicitly in the spec (e.g., `TestActiveSpecDir_TreatsEmptyAsUnset` and `Test_ProdGuardPrologue_MissingActiveSpecBlocks`) so the planner has concrete RED-phase targets.

Guardrail violations: none
Convention violations: none

---

## claude-p

**Verdict:** approve-with-comments

Concerns:
- AC2's third bullet (pinning that `ActiveSpecDir` treats `"null"` as a literal id) is marked Optional, but it represents the entire intentional behavior change the spec describes. Leaving it optional risks the pin being silently dropped — at which point the test only proves the dead-clause removal did not affect the empty-string case, which the old code already handled. The behavior-change pin and the dead-clause removal must land together or the change is under-tested.
- AC3 does not specify how the test fixture constructs the omitempty-cleared state shape. Convention says only `speccraft-state` writes `state.json` at runtime, but a unit test has two plausible setups (literal JSON via `os.WriteFile`, or shell out to `speccraft-state set active_spec null`), and the spec is silent on which to use. This is a planner-determinism gap.
- AC1's grep covers `tools/` which is correct, but the spec does not say what to do with spec 0012's changelog entry that documents these sites as carry-forwards. One-line note would forestall the question.

Suggestions:
- Promote AC2's optional third bullet to a required assertion: `ActiveSpecDir(root, "null")` returns `filepath.Join(root, "specs", "null")`, not `""`.
- Add one sentence to AC3 specifying the fixture setup, e.g. literal JSON write to `<tmpdir>/.speccraft/state.json` with no `active_spec` key (the omitempty-cleared shape).
- Add a sentence to §What noting the behavioral nuance: after the removal, a `"null"` `ActiveSpec` fed to `prodGuardPrologue` no longer hard-blocks at the "No active spec" gate — it passes through to the sibling-test check and fails there harmlessly. This is correct behavior but worth one sentence so a future reader does not treat it as a regression.
- Optional fourth AC: post-removal `goimports`/`gofmt` diff on the two files is exactly the deleted clause (no incidental formatting changes).

Guardrail violations: none
Convention violations: none

---

## Synthesis

Both reviewers reach the same verdict and share no guardrail or convention violations. The convergence is strong on every substantive point.

**Load-bearing finding (must fix before plan):**

The single most important gap, identified independently by both reviewers, is that AC2's third bullet — `ActiveSpecDir(root, "null")` returns a real path rather than `""` — is marked Optional. This is the pin for the entire intentional behavior change the spec describes. If it remains optional, a planner may legitimately omit it, leaving the dead-clause removal tested only against cases the old code already handled correctly. The fix is one word: change "Optionally pins" to a hard assertion, and reword as a direct statement rather than a conditional.

**Planner-determinism gap (should fix before plan):**

Raised by claude-p only: AC3 does not say how the test fixture builds the missing-`active_spec` state shape. Both `os.WriteFile` with a hand-crafted JSON blob and a shell invocation of `speccraft-state set active_spec null` are defensible, but they have different coupling properties. The spec should name one. The minimal answer is one sentence: use `os.WriteFile` to write a `state.json` with no `active_spec` key into a temp directory.

**Working-directory ambiguity (should fix):**

Raised by codex only: AC2 and AC3 reference `./internal/speccraft/` and `./cmd/speccraft-guard/` without stating the working directory. AC4 says "from `tools/`", but the earlier ACs do not. Appending "from `tools/`" to each `go test` command in AC2 and AC3 resolves this.

**Nice-to-have (no blocking force):**

- Name the new test functions in the spec so the planner has concrete RED-step targets (both reviewers).
- Add one sentence to §What about the `prodGuardPrologue` fall-through behavior after the removal (claude-p only — genuinely useful context, not a blocking gap).
- Optional fourth AC pinning gofmt clean diff (claude-p only — minor).
- Cosmetic cross-reference to 0012 changelog in AC1 (claude-p only — one line).

**Overall assessment.** This is a well-scoped bounded-cleanup spec and is plannable with two targeted edits. The "must fix" change is small: one bullet in AC2 changes from optional to required. The "should fix" changes are each one sentence. Nothing requires restructuring the spec.

**Action:** Return the spec to the author with the following changes before opening a plan session:

1. **Must fix.** In AC2, change the third bullet from Optional to required. Replace the conditional framing ("Optionally pins: `ActiveSpecDir(root, "null")` is not specially handled") with a hard assertion: "`ActiveSpecDir(root, "null")` returns `filepath.Join(root, "specs", "null")`, not `""`."

2. **Should fix.** In AC3, add one sentence specifying the fixture setup: use `os.WriteFile` to write a `state.json` with no `active_spec` key (e.g., `{}`) into `<tmpdir>/.speccraft/state.json`.

3. **Should fix.** Append "from `tools/`" to the `go test` invocations in AC2 and AC3 so the working directory matches AC4.

4. **Nice-to-have.** Name the new test functions (e.g., `TestActiveSpecDir_TreatsEmptyAsUnset`, `Test_ProdGuardPrologue_MissingActiveSpecBlocks`) so the planner has concrete RED targets.

5. **Nice-to-have.** Add one sentence to §What noting that after removal, a literal `"null"` id fed to `prodGuardPrologue` falls through to the sibling-test check rather than hard-blocking at "No active spec" — this is correct behavior, not a regression.
