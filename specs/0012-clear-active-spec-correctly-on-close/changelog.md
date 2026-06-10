---
spec: "0012"
closed: 2026-06-10
---

# Changelog — 0012 Clear active_spec correctly on close

## What shipped vs spec

All five §What items shipped as planned. AC1–AC5 verified locally:

- **Bug A fix.** `SetField` in `tools/internal/speccraft/state.go`
  special-cases the literal arg `"null"` (mapping to `""`); combined with
  the new `,omitempty` tag on `State.ActiveSpec`, the disk shape becomes
  "key absent." `jq -r '.active_spec // "null"' state.json` now returns
  the literal string `null` per AC1/AC2. Pure-Go pinning in
  `tools/internal/speccraft/state_clear_test.go` covers both the
  `"null"` and `""` argv forms plus a real-spec-id round-trip.
- **Runtime single-writer guardrail.** `hooks/pre-tool-use.sh` captures
  the envelope once, enumerates the gated tools in
  `GATED_TOOLS="Edit Write MultiEdit NotebookEdit"`, canonicalises the
  incoming `file_path` via `realpath -m`, compares against
  `<root>/.speccraft/state.json`, and exits 2 with a stderr message
  naming `speccraft-state` as the sanctioned writer when they match.
  `hooks/hooks.json` matchers extended in lockstep on **both**
  PreToolUse and PostToolUse blocks. Six bats cases in
  `tests/hooks/pre-tool-use-state-guard.bats` (5 reject, 1 allow on a
  sibling memory file).
- **`speccraft-state init` subcommand.** New idempotent creation path
  in `tools/cmd/speccraft-state/main.go` + `InitState(root)` helper in
  `tools/internal/speccraft/state.go`. `commands/init.md` step 8
  migrated from a literal-JSON Write to a binary invocation — without
  this, the new hook would block fresh `/speccraft:init` runs.
- **`commands/spec/close.md` tightening.** Added the
  "do not edit `.speccraft/state.json` directly under any circumstance"
  prohibition pointing at `speccraft-state` as the only sanctioned
  writer.
- **Test-naming convention.** Both `Test<UpperCamel>` and
  `Test_<Subject>_<Scenario>` documented as acceptable in
  `.speccraft/conventions.md` under the Go section. Existing
  `^func Test[A-Z]` enforce-regex unchanged.

## Deviations

- **Carried-forward micro-cleanup, deliberate.** Two dead-code defensive
  checks reading `ActiveSpec == "null"` remain in the tree after the
  `,omitempty` change made them unreachable:
  - `tools/cmd/speccraft-guard/main.go:353` — `state.ActiveSpec == "null"`
  - `tools/internal/speccraft/root.go:45` — `activeSpec == "null"`
    (the plan §Risk section called out the `guard/main.go` site but
    not this second one)

  Both are intentionally left in place. The TDD hook correctly blocked
  removing them mid-spec without a fresh sibling test (verified: I
  tried, was blocked, and respected the gate). They are not in the
  plan's explicit scope. Removing them is a one-line follow-up spec;
  flagged here so the next reviewer knows it is deliberate, not an
  oversight.

## Files touched

- `tools/internal/speccraft/state.go` — `,omitempty` on `ActiveSpec`;
  `SetField` clear semantics; new `InitState` helper.
- `tools/internal/speccraft/state_clear_test.go` (new) — AC1/AC2.
- `tools/cmd/speccraft-state/main.go` — `init` subcommand wiring;
  usage text.
- `tools/cmd/speccraft-state/main_test.go` — `init` shape +
  idempotency tests.
- `hooks/pre-tool-use.sh` — runtime single-writer guard.
- `hooks/hooks.json` — extend PreToolUse and PostToolUse matchers
  to `Edit|Write|MultiEdit|NotebookEdit`.
- `tests/hooks/pre-tool-use-state-guard.bats` (new) — AC4 (6 cases).
- `commands/init.md` — migrate step 8 to `speccraft-state init`.
- `commands/spec/close.md` — no-direct-edit prohibition.
- `.speccraft/conventions.md` — test-naming clarification (AC5).
- `.speccraft/index.md` — active-spec pointer flipped.

## Out-of-scope follow-ups still queued

- README.md + speccraft-v1-spec.md CodeGraphContext cleanup
  (carried from spec 0011's §Out of scope).
- `/speccraft:spec:revise` (carried from spec 0011's §Out of scope).
- Remove the two dead-code `ActiveSpec == "null"` checks at
  `tools/cmd/speccraft-guard/main.go:353` and
  `tools/internal/speccraft/root.go:45`. One-line each plus a sibling
  test apiece.

## Close gate (AC5 / §Post-merge verification)

`e2e-devcontainer` run URL goes here once the close commit lands on
`main` and the next CI run is green. <!-- TODO: <github-actions-run-url> -->
