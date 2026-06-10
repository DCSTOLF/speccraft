---
id: "0012"
title: "Clear active_spec correctly on close"
status: in-progress
created: 2026-06-09
authors: [claude]
packages: ["tools/cmd/speccraft-state", "tools/internal/speccraft", "commands/spec", "hooks"]
related-specs: ["0008", "0009", "0011"]
---

# Spec 0012 — Clear active_spec correctly on close

## Why

On 2026-06-09 the `e2e-devcontainer` CI job (run 27178536892) failed
at step `[7/9] /speccraft:spec:close`. The assertion at
`tests/e2e/run.sh:281-282` —

```bash
ACTIVE="$(jq -r '.active_spec // "null"' .speccraft/state.json)"
[ "$ACTIVE" = "null" ] || fail "active_spec not cleared after close: $ACTIVE"
```

— rejected the post-close state. The literal failure line was
`FAIL: active_spec not cleared after close:` (trailing empty value),
meaning `state.json` carried `active_spec: ""` rather than JSON `null`
or a missing field.

Two bugs compound to produce that outcome:

**Bug A — `speccraft-state set active_spec null` writes the literal
string `"null"`.** `commands/spec/close.md:45` instructs the model to
run `speccraft-state set active_spec null` to clear the field.
`tools/internal/speccraft/state.go:127-128` treats the value as opaque:

```go
case "active_spec":
    s.ActiveSpec = value
```

No special-casing of `null` or `""`. Result on disk:
`"active_spec": "null"` — a non-empty string. The same bug surfaced
live during the spec 0010 close in parallel with this session
(observed `state.json` post-close), and again at the close of spec
0011 itself in this very session (`speccraft-state set active_spec null`
run during `/speccraft:spec:close` step 6 wrote the literal `"null"`
to disk).

**Bug B — model workaround pattern.** When the close model in CI saw
the literal-`"null"` artifact it had just produced, it tried to clean
it up. Its own log:

> 2. **Tooling bug:** `speccraft-state set active_spec null` wrote the
>    literal string `"null"` instead of JSON `null`/empty. A formatter
>    hook normalized it to `""`, so state is correct now — but the
>    binary's null handling is worth a look.

There is no such formatter hook. The model almost certainly edited
`state.json` directly, violating the single-writer rule documented in
`conventions.md:118-119`:

> **Single-writer rule for `Session` state fields.** All fields on
> `Session` in `.speccraft/state.json` are written **only** by
> `tools/cmd/speccraft-state/main.go` and the helpers in
> `tools/internal/speccraft/state.go`.

That rule is enforced today only at the Go-test layer by
`state_single_writer_test.go` — a grep against source files. A `claude -p`
lifecycle session can do a direct Edit on `state.json` at runtime and
pass that test. The end-state was `active_spec: ""`, which `jq`'s `//`
default does not treat as null, so the e2e assertion fails.

**Why this matters now.**

- `main` CI is red until this lands. Every push triggers
  `e2e-devcontainer` and fails the same way.
- Spec 0011 (just closed) is unaffected directly — its changes are
  doc-only and don't touch the failing path — but the failure blocks
  any future merge story that relies on green CI.
- The bug is reproducible without CI: `speccraft-state set active_spec
  null` in any worktree produces the same artifact. Easy to fix once
  scoped.

## What

Three closely coupled fixes plus one minor cleanup. The "Bug A" /
"Bug B" / guardrail split is intentional — A is the root cause, B is
the model behavior that A induced, the guardrail prevents B from
re-emerging if any future A-class bug appears.

1. **Bug A — `speccraft-state` clear semantics for `active_spec`.**
   `SetField` (or a dedicated subcommand) must treat the literal
   argument `null` or `""` as "clear the field." On disk this means
   either `"active_spec": null` (JSON null) or omission of the field —
   whichever is cleaner given the `State` struct's tags. The test
   `jq -r '.active_spec // "null"' state.json` must output the literal
   string `null` after a clear. Existing call sites that pass a real
   spec id (e.g. `speccraft-state set active_spec 0011-foo`) are
   unchanged.

   Open question — implementation shape: (a) special-case `null`/`""`
   inside `SetField`, vs. (b) add a new `speccraft-state clear <field>`
   subcommand and route close.md through it. Both are acceptable; (a)
   is the smaller patch and keeps `commands/spec/close.md:45` unchanged.
   Resolved in plan.

2. **`commands/spec/close.md` instruction tightening.** Whatever shape
   is chosen for (1), the close.md step must clear the field via the
   sanctioned binary call, and must include a one-line note that the
   model is **not** to direct-edit `.speccraft/state.json` under any
   circumstance — even to "fix" a value the binary just produced. The
   model's CI workaround was a single-writer-rule violation triggered
   by the tooling bug; documenting the rule at the close-command level
   reduces the chance of recurrence even if a different state-binary
   bug appears later.

3. **Runtime single-writer guardrail.** Add a PreToolUse hook check
   (`hooks/pre-tool-use.sh` or a new helper invoked from it) that
   rejects write tool calls whose `file_path` resolves to
   `.speccraft/state.json` (relative or absolute). The rejection
   message must name `speccraft-state` as the sanctioned writer and
   point at the appropriate subcommand. This makes the single-writer
   rule enforced at runtime, not just at unit-test grep level. The
   existing `state_single_writer_test.go` grep stays — it covers
   compiled-in source-level violations, which the hook can't see.

   **Write-tool coverage.** The hook must gate on the full set of
   Claude Code write tools: `Edit`, `Write`, `MultiEdit`,
   `NotebookEdit`. Enumerate them in one place in the hook source
   so adding a new write-tool name in the future is a one-line
   change. Gating on `Edit` and `Write` only would leave `MultiEdit`
   as a trivial bypass.

   **Compatibility pre-check (planner gate).** Before the hook
   lands, the planner must verify empirically that no current path
   in this repo writes `.speccraft/state.json` via a write tool —
   grep `commands/`, `hooks/`, `tests/e2e/`, `tests/hooks/`, and
   the devcontainer setup scripts. If any path does (e.g. an
   `/speccraft:init` bootstrap that creates the file directly
   rather than letting `speccraft-state` create it on first call),
   the plan must either migrate that path to a `speccraft-state`
   call **before** the hook lands, or carve an explicit, narrowly
   scoped exception (e.g. allow `Write` when the file does not yet
   exist) and document it in the hook source.

4. **Test-naming convention drift (minor cleanup).** The same CI run
   surfaced that the lifecycle e2e produces `TestFarewell` while spec
   0001's plan (the long-since-closed v1 spec) named the same test
   `Test_Farewell_ReturnsGoodbye`. The current convention enforce-line
   in `conventions.md:10` —

   ```
   <!-- enforce: regex pattern="^func Test[A-Z]" ... -->
   ```

   — accepts `TestFarewell`. So the regex isn't actually being violated;
   the plan-document naming style is just optional.

   **Decision (pinned for the planner).** Document both
   `Test<UpperCamel>` and `Test_<Subject>_<Scenario>` as acceptable
   under the Go conventions section, with the underscore form
   preferred for tests that name a specific scenario (input → expected
   output). The existing enforce-regex stays as is. Tightening would
   force a rename of every camelCase `TestX` in the host repo plus
   the lifecycle e2e prompt, which is out of scope. Loosening is
   already the de facto state — this just makes it explicit so the
   next reviewer doesn't re-raise the question.

**Note for the planner.** This is a code spec, not a doc-only one — Go
production code in `tools/internal/speccraft/state.go` and/or
`tools/cmd/speccraft-state/main.go` plus a new test file, a new hook
behavior plus a hook-unit test (`tests/hooks/`), and small Markdown
edits in `commands/spec/close.md` and `.speccraft/conventions.md`.
The RED state is a failing Go test that round-trips
`set active_spec null` through `jq` and asserts `null`-string output;
the failure mode on `main` is what the CI run currently shows.

## Acceptance criteria

1. After running `speccraft-state set active_spec null` against a
   `state.json` whose `active_spec` is a non-empty spec id (e.g.
   `"0011-code-intel"`), the resulting file satisfies the e2e
   assertion shape: `jq -r '.active_spec // "null"' state.json`
   outputs the literal string `null`. Verifiable by a new Go test
   under `tools/cmd/speccraft-state/` (or `tools/internal/speccraft/`)
   that performs the round-trip with `jq` in a subprocess (or
   replicates jq's null-default semantics in pure Go, with a comment
   linking back to `tests/e2e/run.sh:281`).

2. The same shape holds for `speccraft-state set active_spec ""` —
   empty-string argument also clears the field. Same Go test covers
   both invocations. Verifiable by reading the test and confirming
   both cases are asserted.

3. `commands/spec/close.md` clears the field via the sanctioned
   binary call (no instruction to direct-edit `state.json`), and
   contains a one-line note forbidding direct edits with a pointer to
   `speccraft-state`. Verifiable by `grep -n 'speccraft-state' commands/spec/close.md`
   returning the clear call, and `grep -niE 'do not.*edit|never.*edit' commands/spec/close.md`
   returning the prohibition line.

4. An attempt to invoke a write tool call targeting
   `.speccraft/state.json` is rejected at runtime by the PreToolUse
   hook. Verifiable by a hook unit test under `tests/hooks/` covering
   three cases:

   - **Reject (absolute path).** Hook envelope
     `{"tool_name":"Edit","tool_input":{"file_path":"/abs/path/to/.speccraft/state.json"},"cwd":"..."}`
     must produce non-zero exit and a stderr message containing the
     string `speccraft-state`.
   - **Reject (relative path).** Same shape with
     `file_path: ".speccraft/state.json"` — must also reject.
   - **Allow (sibling memory file).** Hook envelope with
     `file_path` resolving to `.speccraft/conventions.md` (or any
     other non-state.json file under `.speccraft/`) must NOT be
     rejected. Catches the regression where a regex matches on
     directory prefix rather than the full path and silently locks
     down the whole memory directory.

   The test must cover at least one tool name beyond `Edit` (e.g.
   `Write` or `MultiEdit`) to confirm the enumeration in §What
   item 3 is wired through. The existing
   `tools/internal/speccraft/state_single_writer_test.go` grep
   stays green; the new hook test covers the runtime axis.

5. `conventions.md` documents the test-naming question explicitly:
   both `Test<UpperCamel>` and `Test_<Subject>_<Scenario>` are
   documented as acceptable under the Go conventions section, with
   the underscore form noted as preferred for scenario-specific
   tests. The existing enforce-regex (`^func Test[A-Z]`) stays.
   Verifiable by reading the relevant section of `conventions.md`
   and confirming no ambiguity remains.

## Out of scope

- **Schema changes to `state.json`.** No new fields, no renames, no
  version bump. Only the serialization semantics for the
  `active_spec` field's cleared state.
- **The single-writer rule for non-`active_spec` fields** (e.g.
  `rust_test_baseline`, `override_pending`, `edited_test_files`).
  Those already route through `speccraft-state` exclusively and the
  hook guardrail will protect them automatically as a side effect,
  but no behavioral change is in scope for those fields here.
- **Migrating existing `TestGreeting` / `TestFarewell` host-repo
  fixtures to the underscore form.** The convention decision in AC6
  is documentation-only; renaming live test fixtures across the
  speccraft repo and any downstream uses is out of scope.
- **Replacing the `jq` trick in `tests/e2e/run.sh:281`.** The
  assertion shape is correct given AC1; fixing the producer is the
  right fix, not weakening the assertion.
- **README.md and `speccraft-v1-spec.md` CodeGraphContext cleanup.**
  Still queued from spec 0011's §Out of scope. Orthogonal.
- **Adding `/speccraft:spec:revise`.** Still queued from spec 0011's
  §Out of scope. Orthogonal.

## Post-merge verification

After this spec lands on `main`, the next push triggers a green
`e2e-devcontainer` run. Specifically the step `[7/9] /speccraft:spec:close`
must emit both `PASS: status=closed in ...` and `PASS: active_spec cleared`,
and the job overall must succeed. This is the close gate per the spec
0008 close-commit convention (`.speccraft/conventions.md:103-112`):
the GitHub Actions run URL is recorded in this spec's `changelog.md` as
part of the same commit that flips status to `closed`.

This is post-merge evidence, not an implementation AC — the planner
satisfies the spec when ACs 1-5 are green locally; the close-gate
condition above gates the close commit itself.

## Open questions

- Implementation shape for clear: special-case `null`/`""` inside
  `SetField`, or new `speccraft-state clear <field>` subcommand?
  Both satisfy AC1/AC2. Resolved in plan based on diff size and
  call-site touch cost. *Resolution expected during /spec:plan.*
