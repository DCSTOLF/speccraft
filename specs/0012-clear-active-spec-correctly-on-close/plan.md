---
spec: "0012"
status: planned
strategy: tdd
---

# Plan — 0012 Clear active_spec correctly on close

## Open questions resolved

- **Implementation shape for clear (spec §Open questions).** Special-case
  `null`/`""` argv inside `SetField` (option a in spec). Reasoning:
  - `commands/spec/close.md:45` already calls
    `speccraft-state set active_spec null` — special-casing keeps that
    call site unchanged.
  - The new `speccraft-state init` subcommand (Path A in the compat
    pre-check, §Step 5 below) is a separate, well-bounded surface;
    adding `clear` on top would be one new subcommand too many for
    the bug at hand.
  - Symmetry: init writes `"active_spec": null`; clear must converge
    to the same shape. Both go through `SetField` naturally when
    `null`/`""` argv is special-cased.

- **Hook path-matching policy.** `filepath.Clean` on the incoming
  `file_path` plus comparison against the canonical
  `<root>/.speccraft/state.json` derived from `speccraft-state find-root`.
  Do **not** call `filepath.EvalSymlinks` — codex flagged it as a minor
  concern only, no current path uses a symlinked `.speccraft/`, and
  `EvalSymlinks` adds an `os.Stat` round-trip on every Edit/Write tool
  call. Document this in the hook source as a comment.

- **Test-environment for AC1 jq round-trip.** Pure-Go null-default
  semantics (replicate `// "null"` in Go) with a comment linking back
  to `tests/e2e/run.sh:281-282`. `jq` is present in the devcontainer
  (`/usr/bin/jq`, 1.6) and in the language-only CI image, but the
  Go unit-test layer must not depend on a `jq` binary being on
  `$PATH` — that would couple `go test ./tools/...` to a non-Go tool.

- **Compatibility pre-check result (from planner context).**
  `commands/init.md:53-56` writes `.speccraft/state.json` directly
  via a literal JSON snippet. **Resolution: migrate init.md to a new
  `speccraft-state init` subcommand** (Path A from the planner-context
  block). This is bundled into the spec per §What item 3's explicit
  direction. `hooks/session-start.sh:36` is only a comment stub, no
  active write. e2e fixtures (`tests/e2e/<lang>_cycle.sh`) use shell
  `cat > state.json` heredocs — those are process-level shell writes,
  not Claude Code tool calls, and are not affected by the new hook.

- **`speccraft-state init` semantics.** Idempotent: if
  `.speccraft/state.json` already exists, succeed silently without
  overwriting (preserves any session state already on disk). If
  absent, write the canonical empty shape:
  `{"version":1,"active_spec":null,"session":{"id":"","edited_test_files":[],"edited_prod_files":[]}}`.
  This matches the literal currently in `commands/init.md:53-56`.

- **Sequencing constraint.** The hook test (Step 3 RED) must be
  written before `commands/init.md` is migrated (Step 6 GREEN),
  otherwise the migration is a no-op RED. The `init` subcommand
  (Step 5 RED + Step 6a GREEN) must land before the hook is enabled
  in production (Step 4 GREEN), otherwise the next `/speccraft:init`
  is broken. Sequence below respects both constraints.

## Test-first sequence

### Step 1 — RED: Go test for `SetField` clear semantics on `active_spec`

- Add `tools/internal/speccraft/state_clear_test.go`:
  - `Test_SetField_ActiveSpec_NullArg_ClearsToJSONNull` — seed
    state with `active_spec = "0011-code-intel"`, call
    `speccraft.SetField(root, "active_spec", "null")`, then read
    `.speccraft/state.json` raw bytes and assert via the pure-Go
    jq-null-default equivalence helper that
    `.active_spec // "null"` yields the string `"null"`. Include a
    file-level comment linking back to `tests/e2e/run.sh:281-282`
    so the next reader can see why this round-trip shape matters.
  - `Test_SetField_ActiveSpec_EmptyStringArg_ClearsToJSONNull` —
    same setup, call `SetField(root, "active_spec", "")` with an
    empty-string Go argument directly (no shell layer, per claude-p
    R2 R7), assert the same shape. Distinct test function so the
    failure message names which argv form regressed.
  - `Test_SetField_ActiveSpec_RealSpecId_RoundTrips` — regression
    guard: `SetField(root, "active_spec", "0001-foo")` then
    `GetField` returns `"0001-foo"`. Pins that the special-case did
    not accidentally swallow legitimate spec ids.
- Tests fail because `state.go:127-128` treats `value` as opaque and
  writes the literal string `"null"` (Bug A from §Why).
- Satisfies: AC1, AC2.

### Step 2 — GREEN: implement clear semantics in `SetField`

- Edit `tools/internal/speccraft/state.go`:
  - In the `case "active_spec":` arm of `SetField`, treat `value ==
    "null"` and `value == ""` as a clear: set `s.ActiveSpec = ""`.
    The Go zero value plus the existing
    `ActiveSpec string \`json:"active_spec"\`` tag with no
    `omitempty` writes `"active_spec":""` to disk — which is what
    the e2e assertion **does not** want.
  - Therefore change the struct tag on `ActiveSpec` to include
    `,omitempty` and the field type to remain `string`. With
    `omitempty` + empty string, the JSON encoder omits the key
    entirely. `jq -r '.active_spec // "null"' state.json` returns
    the literal `null` string per AC1.
  - Alternative considered and rejected: change `ActiveSpec` to
    `*string` to distinguish nil from `""`. Rejected — it cascades
    through every reader (`GetField`, `TasksDonePct`, `state_test.go`)
    and is a strictly larger diff than the omitempty path.
- All Step 1 tests pass. Existing tests in
  `tools/internal/speccraft/state_test.go` (`TestStateRoundTrip`,
  `TestResetSession`) and
  `tools/cmd/speccraft-state/main_test.go` continue to pass — they
  only assert real-spec-id round-trips, which are unchanged.
- Satisfies: AC1, AC2 (RED → GREEN).

### Step 3 — RED: bats test for PreToolUse hook state.json guardrail

- Add `tests/hooks/pre-tool-use-state-guard.bats`, modeled on the
  existing `tests/hooks/session-start.bats` scaffold:
  - `setup()` creates a temp repo with `.speccraft/`, builds (or
    re-uses) the `speccraft-state` and `speccraft-guard` binaries in
    `bin/`, exports `CLAUDE_PLUGIN_ROOT` to the repo root.
  - Test cases (each pipes a hook envelope on stdin to
    `hooks/pre-tool-use.sh`):
    - `@test "rejects Edit on absolute path .speccraft/state.json"`
      — envelope `{"tool_name":"Edit","tool_input":{"file_path":"$TEST_REPO/.speccraft/state.json"},"cwd":"$TEST_REPO"}`,
      expects non-zero exit and stderr contains the literal string
      `speccraft-state`.
    - `@test "rejects Edit on relative path .speccraft/state.json"`
      — `file_path: ".speccraft/state.json"`, `cwd` set to repo
      root, expects non-zero exit + `speccraft-state` in stderr.
    - `@test "rejects Write on .speccraft/state.json"` — same shape
      with `tool_name: "Write"`. Covers the §What item 3
      enumeration extending beyond `Edit`.
    - `@test "rejects MultiEdit on .speccraft/state.json"` — same
      shape with `tool_name: "MultiEdit"`. Pins that
      `MultiEdit` is not a trivial bypass (claude-p R3 must-fix).
    - `@test "rejects NotebookEdit on .speccraft/state.json"` —
      same shape with `tool_name: "NotebookEdit"`. Completes the
      enumeration claude-p R3 asked for.
    - `@test "allows Edit on sibling memory file conventions.md"`
      — `file_path: ".speccraft/conventions.md"`. Expects exit 0
      (or whatever existing exit code `pre-tool-use.sh` emits for
      non-blocked calls — pin from current behavior in a no-active-
      spec setup so the assertion is stable). Catches the regression
      where a regex matches on directory prefix and silently locks
      down the whole memory directory (AC4 third-case must-fix).
- Tests fail because `hooks/pre-tool-use.sh` currently delegates
  unconditionally to `speccraft-guard pre-tool-use` and does not
  short-circuit on `state.json` writes from any tool name.
- Satisfies: AC4.

### Step 4 — GREEN: implement the PreToolUse state.json guardrail

- Edit `hooks/pre-tool-use.sh`:
  - Before the existing `exec speccraft-guard pre-tool-use` line,
    insert a single-pass guard:
    1. Capture stdin once into a variable (`INPUT="$(cat)"`).
    2. Parse `tool_name` and `tool_input.file_path` using `jq`
       (already available in the plugin's runtime; the binary path
       is `/usr/bin/jq` in the devcontainer).
    3. Enumerate the gated tool names in **one** shell variable:
       `GATED_TOOLS="Edit Write MultiEdit NotebookEdit"`. Adding a
       future tool name is a one-line change.
    4. If `tool_name` is in `GATED_TOOLS` AND the cleaned absolute
       file path equals `<root>/.speccraft/state.json` (root from
       `speccraft-state find-root`, path cleaned via Bash parameter
       expansion + `realpath -m` for the absolute form, with a
       fallback when `realpath` is absent — verify against the
       devcontainer image; otherwise pure-bash normalization),
       emit a stderr message naming `speccraft-state` as the
       sanctioned writer and exit 2 (matching the hook-protocol
       convention `set -euo pipefail; exit non-zero on guardrail
       violation` from `.speccraft/guardrails.md:24`).
    5. Otherwise replay `INPUT` on stdin to
       `speccraft-guard pre-tool-use` via a here-string and
       `exec` (preserving the existing delegation contract).
  - Update the file header comment to document the guardrail and
    point at the spec.
- All Step 3 bats tests pass.
- Update `hooks/hooks.json` matcher from `"Edit|Write"` to
  `"Edit|Write|MultiEdit|NotebookEdit"` so the new tool names
  actually reach the hook in the first place. (Without this change,
  Claude Code never invokes `pre-tool-use.sh` for `MultiEdit`/
  `NotebookEdit` and the guardrail is unreachable.)
- Satisfies: AC4 (RED → GREEN).

### Step 5 — RED: Go test for new `speccraft-state init` subcommand

- Add to `tools/cmd/speccraft-state/main_test.go`:
  - `TestStateCmd_Init_CreatesCanonicalEmptyShape` — call
    `run([]string{"init"}, …)` in a repo with an empty `.speccraft/`
    directory but no `state.json`. Assert exit 0, then read
    `.speccraft/state.json` and assert the canonical shape
    matches: `version: 1`, `active_spec` absent (or JSON null —
    confirm against Step 2's omitempty choice), `session.id: ""`,
    `session.edited_test_files: []`, `session.edited_prod_files: []`.
  - `TestStateCmd_Init_Idempotent_PreservesExistingState` — seed
    `.speccraft/state.json` with `active_spec: "0099-foo"` and a
    non-empty `edited_test_files`. Call `run([]string{"init"}, …)`.
    Assert exit 0 and the existing state is untouched. Pins the
    idempotency contract so re-running `/speccraft:init` cannot
    silently nuke session state.
- Tests fail because the `init` case does not exist in the `switch`
  in `tools/cmd/speccraft-state/main.go:26`.
- Satisfies: prerequisite for Step 6 (`init.md` migration), which is
  itself the §What item 3 compatibility fix.

### Step 6a — GREEN: implement `speccraft-state init`

- Edit `tools/cmd/speccraft-state/main.go`:
  - Add `case "init":` to the `switch args[0]` block. Resolve repo
    root via `speccraft.FindRoot("")` (mirroring the other
    subcommands). Check whether `.speccraft/state.json` exists; if
    so, return 0 silently (idempotent). Otherwise call a new
    `speccraft.InitState(root)` helper that writes the canonical
    empty `State` via the existing atomic `saveStateLocked` path.
  - Update the `usage()` text to list the new subcommand.
- Edit `tools/internal/speccraft/state.go`:
  - Add `InitState(root string) error`. Body: take `mu.Lock()`,
    call `saveStateLocked(root, State{Version: 1})`. The empty
    `Session` zero-value + the JSON tags from `Session` already
    produce the canonical
    `"session":{"id":"","edited_test_files":null,"edited_prod_files":null}`
    on Go's default `MarshalIndent`. If the empty-array shape
    `[]` is required (not `null`) to match the pre-existing
    literal in `commands/init.md`, initialize the slices explicitly
    in the helper: `s.Session.EditedTestFiles = []string{}` etc.
    Pin the choice in the test from Step 5 so this is unambiguous.
- All Step 5 tests pass.

### Step 6b — GREEN: migrate `commands/init.md` to use the binary

- Edit `commands/init.md`:
  - Replace step 8 (lines 53-56) with:
    ```bash
    "$CLAUDE_PLUGIN_ROOT/bin/speccraft-state" init
    ```
    matching the invocation style already used at
    `commands/spec/close.md:45`.
  - Adjust the surrounding prose (step 8 lead-in) so the model
    invokes the binary instead of issuing a `Write` tool call. This
    is what makes the Step 4 hook safe to land: by the time `init`
    runs the new hook, no path in this repo writes `state.json`
    via `Edit`/`Write`/`MultiEdit`/`NotebookEdit`.
- No new test required for this edit — the Step 5 init test is the
  oracle for the binary's behavior, and the Step 3 hook tests are
  the oracle for the runtime guardrail. The change in `init.md` is
  observable end-to-end via the unchanged
  `e2e-devcontainer` job's first `/speccraft:init` step.
- Satisfies: AC4 compatibility precondition (§What item 3
  pre-check). Order matters: 6a builds the subcommand, 6b switches
  the call site, then the hook in Step 4 is safe in production.

### Step 7 — GREEN: tighten `commands/spec/close.md`

- Edit `commands/spec/close.md`:
  - Step 6 (the `speccraft-state set active_spec null` call at
    line 45) stays as written — Step 2 made that invocation
    correct.
  - Add one immediately-following sentence (still inside step 6
    or as a new step 6a) that reads, approximately: "Do not edit
    `.speccraft/state.json` directly under any circumstance — even
    to 'fix' a value the binary just produced. The only sanctioned
    writer is `speccraft-state`." The text must satisfy the AC3
    grep oracle: `grep -niE 'do not.*edit|never.*edit'` returns
    this line, and `grep -n 'speccraft-state' commands/spec/close.md`
    returns both the binary call and the new prohibition.
- No new test required: AC3 is verified by the two grep
  invocations called out in the spec. (Optional: add a one-line
  shell check in this spec's directory as a `verify.sh`-style
  oracle. Not required — this is a behavioral spec and the bats /
  Go tests cover the load-bearing axes.)
- Satisfies: AC3.

### Step 8 — GREEN: document the test-naming convention in `conventions.md`

- Edit `.speccraft/conventions.md` under the "Go (`tools/`)" section
  (around line 10, alongside the existing enforce-regex):
  - Append a short paragraph documenting both `Test<UpperCamel>` and
    `Test_<Subject>_<Scenario>` as acceptable, with the underscore
    form preferred for scenario-specific tests (input → expected
    output). State explicitly that the existing
    `^func Test[A-Z]` enforce-regex stays as is.
  - Resolves the AC6 decision direction that was open in cross-model
    review (claude-p R4, codex AC6 single-reviewer).
- No new test required: AC5 is a "reads cleanly" assertion verified
  by reading the section.
- Satisfies: AC5.

### Step 9 — REFACTOR (optional)

- Run `go test ./tools/...` and `bats tests/hooks/` end-to-end.
- Scan `commands/init.md` for any residual `Write` tool prose that
  could still trip the new hook on a fresh repo (`/speccraft:init`
  also creates `specs/.gitkeep` and may append to `.gitignore` —
  neither targets `state.json`, but a quick re-read confirms).
- Re-read `hooks/pre-tool-use.sh` for shell-portability: the
  `realpath -m` call must degrade gracefully if the binary is
  absent on a minimal image. Add a fallback or document the
  dependency in the script header.
- All tests still pass.

## Delegation

- Step 4 (PreToolUse hook implementation) → could delegate to
  `aux-delegator` for `codex` review of the shell path-normalization
  edge cases (symlinks, `..` traversal, CRLF in JSON). Not strictly
  required; the bats test cases in Step 3 already enumerate the
  load-bearing positive and negative path shapes. Default: keep
  in-thread.
- Step 6a (Go `InitState` helper + subcommand wiring) → no
  delegation. Pattern-match against the existing `ResetSession`
  helper in the same file.

## Risk

- **Risk: `omitempty` on `ActiveSpec` regresses readers that
  distinguished `""` from "unset".** Mitigation: grep for
  `\.ActiveSpec\s*==` across `tools/` before Step 2; current
  readers (`TasksDonePct` at `state.go:287`) check
  `s.ActiveSpec == "" || s.ActiveSpec == "null"` — the special-case
  for `"null"` becomes dead code after Step 2 but is harmless;
  remove it as part of Step 2 to keep the diff honest.
- **Risk: `jq` not on the runtime path for the new hook block.**
  Mitigation: `jq` is already an implicit dependency of
  `tests/e2e/run.sh:281` (the very assertion §Why quotes), and the
  devcontainer ships it (verified `/usr/bin/jq` 1.6 on host).
  Document the dependency in the hook header. If portability to a
  minimal image becomes a concern in a future spec, switch to a
  small Go helper (`speccraft-state hook-check-state-write`?) —
  out of scope here.
- **Risk: bats tests need the `speccraft-state` and
  `speccraft-guard` binaries built into `bin/`.** Mitigation: the
  Step 3 `setup()` block calls
  `"$PLUGIN_DIR/scripts/install-binaries.sh"` (mirroring
  `tests/hooks/session-start.bats:9-10`). The CI image has the Go
  toolchain available; the binaries get built into
  `$PLUGIN_DIR/bin/`. No new infra.
- **Risk: hook starts blocking `MultiEdit` / `NotebookEdit` in
  contexts where the host repo's host project legitimately uses
  those tools on its own files.** Mitigation: the guard rejects
  **only** when the `file_path` resolves to
  `<root>/.speccraft/state.json`. Every other `MultiEdit` /
  `NotebookEdit` invocation falls through to
  `speccraft-guard pre-tool-use` unchanged. Pin this in the
  "allow sibling memory file" bats case (Step 3) and in a follow-on
  case using an unrelated production file path inside the test
  repo.
- **Risk: Step 6b's `init.md` edit lands without the binary
  built.** Mitigation: Step 6a creates `speccraft-state init`
  before Step 6b changes the call site. Step 6a's tests fail
  until the subcommand exists, so the sequencing is enforced by
  the RED→GREEN gate.

## Out of scope (carried from spec)

- Schema changes to `state.json` (no new fields, no version bump).
- Single-writer enforcement for non-`active_spec` fields beyond
  what the hook covers as a side effect.
- Renaming existing camelCase host-repo test fixtures.
- Replacing the `jq` trick in `tests/e2e/run.sh:281`.

## Post-merge close gate

Per spec §Post-merge verification: not a planner gate. The
`e2e-devcontainer` job's step `[7/9] /speccraft:spec:close` must
emit `PASS: active_spec cleared` on the close-commit push; the run
URL goes in `changelog.md` per the spec-0008 close-commit
convention. Planner exits when ACs 1–5 are green locally.
