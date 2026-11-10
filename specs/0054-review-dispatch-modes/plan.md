---
spec: "0054"
status: planned
strategy: tdd
---

# Plan — 0054 Review dispatch modes: `codex-plugin` and `subagent`

## Ratified plan decisions

Four shapes the spec does not fix, settled here before step 1. The first was a
user ruling; the other three are forced by the spec plus the 0052 regression
floor (each is the only design that keeps 0052's suites byte-unedited).

1. **The shared runbook lives at `skills/review-round/SKILL.md`.** Every `.md`
   under `commands/` registers as a slash command — verified: all 21 are
   commands, and shared logic there uses `.lib.sh` — so the runbook cannot go
   there without creating a stray `/speccraft:spec:review-round` users should
   never invoke. `skills/` is already a shipped surface in the
   portability-guard scan roots and already carries `aux-agents/SKILL.md`.
   **Eleven grep assertions hardcode this path**; changing it means editing
   steps 40, 41 and AC17a/19/20's tests together.
2. **AC4's parity fixture is a DIRECTORY, not one file.** `LoadConfig` fails
   the whole file on the first bad entry while `review_agent_mode` is
   per-agent, so a single `parity.toml` carrying reject rows cannot be driven
   by both readers. The corpus is
   `tests/hooks/fixtures/review-dispatch/registries/`: `accept-all.toml`, one
   `reject/<reason>.toml` per reject reason, and `expected.txt` holding
   `<file> accept|reject <reason-token>`. A third assertion pins that
   `expected.txt` covers every reject-reason token, so neither reader can pass
   against a half-empty corpus. This still satisfies the spec's "AC4's fixture
   is the single source for both readers' validation rows" — one corpus, two
   readers.
3. **`review_compose_payload` gains `--label <text>`**, defaulting to today's
   literal heading. The arch/pm/review-code branches need their own "under
   review" heading; a defaulted option keeps 0052's composer tests
   byte-identical where a new positional would not.
4. **`review_finalize_round` gains an optional 4th arg `<kind>`**, defaulting
   to `spec`. `arch`/`pm` need the durable write without the snapshot-promote
   and fingerprint arms, and `review-code` needs neither. Defaulting preserves
   0052's 3-arg call sites.

**Corrections made while implementing (the plan's mechanism was wrong):**

- **Step 3 — `toml.MetaData.IsDefined` cannot address array-of-table elements.**
  `md.IsDefined("agents", "mode")` reports false even when an element defines
  `mode`. `md.Keys()` does carry it (a bare `agents` key introduces each
  element), so `agentKeySets` segments on that instead.
- **Step 7 — `md.Undecoded()` has the same limitation.** It reports
  `agents.install_hint` with no element index, so it cannot say WHICH entry
  carried the key. Replaced by `agentKeySets` + `knownAgentKeys`.
- **Step 9 — `review_agent_mode` cannot be built "over `review_agent_field`".**
  That helper's awk prints a value only `if (val != "")`, so `mode = ""` and an
  absent `mode` are both the empty string — and AC1 needs them distinguished
  (absent ⇒ `cli`, explicit-empty ⇒ named error). Added `review_agent_keys`,
  the shell analogue of `agentKeySets`, which reads key PRESENCE. Step 11 needs
  it too: a forbidden or unknown KEY is forbidden whatever its value.
- **Every `done:` predicate ran `go test ./tools/...` from the repo root**,
  where there is no `go.mod` (the module is rooted at `tools/`). All nine
  corrected to `go test -C tools ./...`.
- **T1 — spec.md §Output describes the FOREGROUND shape, but §Command mandates
  the BACKGROUND path.** The fifth instance of the same failure, and the first
  found by reading the companion rather than by review. §Output says `--json`
  emits a flat `{status, threadId, rawOutput, …}` and that
  `review_parse_codex_task_output` "extracts `rawOutput`". That is true of
  foreground `task --json` (`codex-companion.mjs:511-517`). On the mandated
  background path, `handleResult` (`:910-925`) emits `{job, storedJob}` with
  the flat payload nested at `storedJob.result` (`tracked-jobs.mjs:166`), so
  the real paths are **`.storedJob.result.rawOutput`** and
  **`.storedJob.result.status`**. A parser written against §Output literally
  would read `undefined` on every live run. Worse, there are two fields named
  `status` at different depths — the outer job status is a STRING whose success
  value is exactly `"completed"`, which is the value spec.md:189 warns "is
  never" emitted (true only of the inner, numeric one). ACs 6/9/10 need
  restating; fixtures and `INTERFACE-1.0.6.md` pin the verified shapes.
- **T1 — an executed stub may not live under `fixtures/`.** `stub-node.sh` is
  dropped on PATH as `node`, and `tests-portability-sweep.bats:61-62` states
  the boundary outright: a fixture that must be executed has to move out of
  `fixtures/`, or the GNU-form sweep stops seeing it. Moved to
  `tests/hooks/stubs/`; proven load-bearing by planting `readlink -f` in it and
  watching the sweep name the file, which it could not do before the move.
- **Four `done:` predicates asserted TRANSIENT state.** Three RED steps used
  `grep -q FAIL`, which stops holding the moment the GREEN lands, and T8's used
  `! grep -q 'review_agent_mode' …` — an assertion that the helper is ABSENT,
  which T9 permanently falsifies. All now assert durable evidence (the required
  test functions or test names exist). Two more pinned exact test COUNTS, so
  adding a test broke them; they now name the required functions.

**Deferred to a follow-up spec, not fixed here:**
`speccraft-state test-command` returns `pytest -q` in this repo, parsed out of
a *documentation example* inside `.speccraft/conventions.md`'s own description
of the marker grammar (line 521) — the parser matches the marker anywhere in
the file, including inside its own docs, and this repo has no pytest. No step
in this plan depends on it (every `done:` predicate names its command
literally and sets `PATH` itself), so it is latent here. Out of scope for
0054; worth its own spec after this one closes.

## Shape of the work

Nine phases. Phase A is Go; phases B-H are shell + markdown and are therefore
**ungated by `speccraft-guard`** (`.speccraft/conventions.md` §Bash: the TDD gate
classifies only Go/Python/Rust/JS-TS as production code), so the RED→GREEN
discipline below is author-enforced via sibling bats suites. Expected override
budget: **0**. Expected build-repair admissions: **0-2** (Phase A struct-field
additions ride an existing sibling RED in the same package directory).

New test files (all new; the spec-0052 suites `spec-review-payload.bats` and
`spec-review-diff.bats` are the regression floor and are **not edited**):

- `tests/hooks/spec-review-dispatch.bats`        — modes, transport, router
- `tests/hooks/spec-review-codex.bats`           — the codex-plugin adapter
- `tests/hooks/spec-review-payload-boundary.bats`— AC8
- `tests/hooks/spec-review-round-dir.bats`       — round dir, lease, sweep, quarantine
- `tests/hooks/spec-review-tree-snapshot.bats`   — AC17b/17c
- `tests/hooks/spec-review-round-runbook.bats`   — the shared runbook + 4 command files
- `tests/hooks/spec-review-attestation.bats`     — AC16/16a
- `tests/hooks/spec-review-code.bats`            — AC22/22a
- `tests/hooks/spec-review-subagent.bats`        — AC18b/20a/20b/17a/17d
- `tests/hooks/spec-review-vendor.bats`          — AC23/23a
- `tests/hooks/review-only-mode-refusal.bats`    — AC23b
- `tests/hooks/review-subagent-agent.bats`       — AC18/18a
- `tests/hooks/review-dispatch-docs.bats`        — AC24/25
- `tests/hooks/spec-review-round-lifecycle.bats` — AC15/14d
- `tests/hooks/live-codex-smoke.bats`            — AC26/26a, env-gated, NON-CI
- `tools/internal/delegate/mode_test.go`         — AC1/2/3
- `tools/internal/delegate/parity_test.go`       — AC4 (Go half)
- `tools/internal/delegate/template_test.go`     — AC25 (Go half)

Test command, stated literally because `speccraft-state test-command` is
**unreliable in this repo** — it returns `pytest -q`, parsed out of the prose
example marker on `.speccraft/conventions.md:521`:

- shell: `PATH="$PWD/bin:$PATH" bats tests/hooks/`
- Go: `go test ./...` (plus `GOOS=windows go build ./...`)

## Test-first sequence

### Phase 0 — Re-verify the companion facts (the spec's own first instruction)

#### Step 1 — Pin the installed 1.0.6 companion's real interface (PREP)
Writes **test fixtures only**, no production code, so the RED-before-GREEN rule
is not engaged. Spec §Notes: "The plan's first task should re-verify them
against the installed plugin before coding the adapter, since two of round 2's
three P1s were exactly this class of error."
- Re-read, against an installed 1.0.6 tree: numeric `status` from
  `buildResultStatus` (`scripts/lib/codex.mjs:754`); `printUsage` omitting
  `--prompt-file`/`--cwd`/`--json` (line 82); the detached+`unref`'d broker;
  `cancel` as the only path to `interruptAppServerTurn`; `setup --json`
  exposing `ready`; `runAppServerTurn` sending `options.prompt?.trim()`
  (`codex.mjs:1127`).
- Capture into `tests/hooks/fixtures/review-dispatch/codex/`:
  - `printusage-1.0.6.txt` — the verbatim help text (AC5a's pin)
  - `task-success-1.0.6.json` — verbatim successful `task --json` output (AC9's
    "one row is verbatim captured 1.0.6 output")
  - `installed_plugins/{local-match,user-only,absent,both-scopes}.json`
  - `manifests/{v106,v105,unparseable,absent}/.claude-plugin/plugin.json`
  - `stub-node.sh` — records argv to a file, answers `setup`/`task`/`status`/
    `result`/`cancel` from a per-test canned-response directory, and counts
    calls per subcommand and per resolved root (AC5c/15b need per-root counts)
- **The codex plugin is NOT installed in this devcontainer** (only
  `speccraft@dcstolf-tools` and `gopls-lsp@claude-plugins-official` are in
  `~/.claude/plugins/installed_plugins.json`). Do this on a host that has it,
  or against a vendored 1.0.6 source copy, and record which in the changelog.

### Phase A — The Go registry loader (ACs 1, 2, 3)

#### Step 2 — Mode enum, normalization and case-rejection (RED)
- Add `tools/internal/delegate/mode_test.go` (package `delegate`):
  - `Test_LoadConfig_Mode_AcceptsFourModes` — table over `cli`, `acp`,
    `codex-plugin`, `subagent`; each loads and `Agent.Mode` equals the input
  - `Test_LoadConfig_Mode_OmittedNormalizesToCLI`
  - `Test_LoadConfig_Mode_ExplicitEmptyIsNamedError` — error names the agent
    and all four valid values
  - `Test_LoadConfig_Mode_CaseVariantsRejected` — `Subagent`, `CLI`
- Assertions touch only `LoadConfig` and `Agent.Mode`, both of which already
  exist, so every failure is a **runtime assertion failure, not a build error**
  — no `/speccraft:spec:override` and no build-repair admission.
- Tests fail: `LoadConfig` does no mode validation at all today
  (`toml.Decode` is permissive), so the empty and case-variant rows load
  silently and the omitted-mode row yields `""`, not `cli`.

#### Step 3 — Mode validation + the new `Agent` fields (GREEN)
- Implement in `tools/internal/delegate/toml.go`: a `validateAgent` pass after
  decode that normalizes `""`→`cli` **only when the key is absent** and errors
  on an explicitly-empty or unrecognised value, naming the agent and the four
  modes. Distinguish absent from explicit-empty via `toml.MetaData.IsDefined`.
- In the **same edit** (so the next RED compiles): add the fields the spec says
  the struct gains — `ReferenceRead *bool`, `Model`, `Effort`, `PluginRoot`,
  `SubagentType` — plus `func (a Agent) IsReferenceRead() bool` (nil ⇒ true,
  the opt-out convention).
- All step-2 tests pass.

#### Step 4 — Strict keys, per-mode enums, field defaults (RED)
- Extend `tools/internal/delegate/mode_test.go`:
  - `Test_LoadConfig_StrictKeys_RejectedOnNewModes` — one table row each:
    `cmd`, `input`, `acp_agent` on `codex-plugin`; same three on `subagent`;
    `subagent_type` on `codex-plugin`; `effort` on `subagent`; `plugin_root`
    on `subagent`
  - `Test_LoadConfig_Effort_OutsideSixValues_IsNamedError`
  - `Test_LoadConfig_SubagentModel_OutsideFiveValues_IsNamedError` — accepts
    `opus|sonnet|haiku|fable|inherit`, rejects e.g. `gpt-5`
  - `Test_LoadConfig_NewModeFields_DecodeAndDefault` — `subagent_type` absent
    ⇒ `speccraft:reviewer`; `model` absent ⇒ `inherit`; `reference_read`
    absent ⇒ `IsReferenceRead() == true`; `reference_read = false` ⇒ false
- Compiles because step 3 added the fields. Fails: no strict-key or enum
  checking exists and no defaults are applied.

#### Step 5 — `validateAgent` strict-field and enum arms (GREEN)
- `tools/internal/delegate/toml.go`: per-mode strict-field rejection and the
  two enum checks, each error naming the agent, the offending key and the
  permitted values. Defaults applied after validation.
- All step-4 tests pass.

#### Step 6 — Unknown keys on new modes; the AC3 regression floor (RED)
- Extend `tools/internal/delegate/mode_test.go`:
  - `Test_LoadConfig_UnknownKey_OnNewMode_IsNamedError` — `install_hint` on a
    `subagent` entry errors (**the RED**)
  - `Test_LoadConfig_UnknownKey_OnCLIEntry_StillLoads` — `install_hint` on a
    `cli` entry is ignored (green on arrival; the regression floor)
  - `Test_LoadConfig_RealRegistries_LoadUnchanged` — walks and loads
    `.speccraft/agents.toml`, `templates/speccraft/agents.toml`, and **every**
    `agents.toml` found under `tests/`; fails on any error. This is the test
    that will catch Phase G's template edit if it breaks.
- Fails on the first row: `toml.Decode` ignores unknown keys for every mode.

#### Step 7 — Per-entry unknown-key scoping via `md.Undecoded()` (GREEN)
- `tools/internal/delegate/toml.go`: capture `toml.MetaData` from
  `toml.Decode`, map each `Undecoded()` key path back to its `agents[i]`
  index, and error **only** when that entry's mode is `codex-plugin` or
  `subagent`. `cli`/`acp` keep today's permissive decode (the host-owned-config
  opt-out convention).
- All step-6 tests pass. Verify the negative bites: temporarily flip the mode
  guard off and watch `..._OnCLIEntry_StillLoads` go red.

### Phase B — The shell mode reader, parity, transport (ACs 4, 12)

#### Step 8 — `review_agent_mode` (RED)
- Add `tests/hooks/spec-review-dispatch.bats` (setup() mirrors
  `spec-review-payload.bats`: `PLUGIN_DIR` from `BATS_TEST_FILENAME`,
  `./bin` FIRST on `PATH`, all derived paths assigned **in `setup()`**, plus
  that file's `assert_named_failure` helper):
  - `@test "review_agent_mode returns each of the four valid modes"`
  - `@test "review_agent_mode normalizes an omitted mode to cli"`
  - `@test "review_agent_mode names an error for an explicitly empty mode"`
  - `@test "review_agent_mode names an error for the case variants Subagent and CLI"`
  - `@test "the error names the agent and all four valid modes"`
- Tests fail: `review_agent_mode` does not exist in
  `commands/spec/review.lib.sh` (`command not found`).

#### Step 9 — `review_agent_mode` (GREEN)
- `commands/spec/review.lib.sh`: `review_agent_mode <toml> <agent>` over
  `review_agent_field`, absent⇒`cli`, explicit-empty/unknown ⇒ named error on
  stderr + non-zero. No new awk; reuse the existing per-agent scalar reader.
- All step-8 tests pass, and `assert_named_failure` now distinguishes the
  helper's own diagnostic from a typo.

#### Step 10 — The shared parity corpus, driven by both readers (RED)
- Add `tests/hooks/fixtures/review-dispatch/registries/` per decision 2:
  `accept-all.toml`, `reject/{empty-mode,case-variant,cmd-on-subagent,
  input-on-codex-plugin,acp-agent-on-subagent,subagent-type-on-codex-plugin,
  effort-on-subagent,plugin-root-on-subagent,bad-effort,bad-subagent-model,
  unknown-key-on-new-mode}.toml`, `expected.txt`.
- Add `tools/internal/delegate/parity_test.go`:
  - `Test_LoadConfig_ParityCorpus_AcceptsAcceptAll`
  - `Test_LoadConfig_ParityCorpus_RejectsEachRejectFixture`
  - `Test_ParityCorpus_CoversEveryRejectReason` — `expected.txt` names every
    token in a hardcoded reason list, so a half-empty corpus fails
- Extend `tests/hooks/spec-review-dispatch.bats`:
  - `@test "review_agent_mode accepts every entry of the parity accept fixture"`
  - `@test "review_agent_mode rejects every parity reject fixture with a named error"`
  - `@test "the parity corpus covers the same reject-reason set the Go loader pins"`
- The Go half passes on arrival (Phase A). The bats half is the RED: the shell
  reader validates the mode token only, not strict keys or the two enums.

#### Step 11 — The shell reader's strict-key and enum arms (GREEN)
- `commands/spec/review.lib.sh`: `_review_agent_mode_strict <toml> <agent> <mode>`
  called from `review_agent_mode`, reproducing step 5 + step 7's rules with
  byte-identical reason tokens.
- All step-10 tests pass on both sides.

#### Step 12 — `review_agent_transport` (RED)
- Extend `tests/hooks/spec-review-dispatch.bats`:
  - `@test "review_agent_transport returns file for codex-plugin"`
  - `@test "review_agent_transport returns file for subagent"`
  - `@test "review_agent_transport returns the registry input for cli and acp"`
  - `@test "an 80 KB payload is ok for codex-plugin and for subagent"`
  - `@test "the same 80 KB payload is refuse:argv-limit for cli plus argv"`
  - `@test "review_budget_check and review_dispatch_payload keep their signatures"`
    (asserts the two helpers still accept exactly their 0052 argument counts)
- Fails: `review_agent_transport` does not exist.

#### Step 13 — `review_agent_transport` (GREEN)
- `commands/spec/review.lib.sh`: maps mode ⇒ the input-mode token
  `review_budget_check` takes; new modes ⇒ `file`. Touches neither
  `review_budget_check` nor `review_dispatch_payload`.
- All step-12 tests pass; the spec-0052 budget/dispatch suite passes unedited.

### Phase C — The `codex-plugin` adapter (ACs 5, 5a-5d, 6, 6a, 6b, 7, 9, 9a, 10, 11, 13)

#### Step 14 — `review_with_deadline` (RED)
- Add `tests/hooks/spec-review-codex.bats`:
  - `@test "review_with_deadline 1 on a 30 s sleeper returns 124"`
  - `@test "it returns within 5 s"` (wall-clock bound only on the harness, not
    on acquisition order)
  - `@test "it leaves no child process alive"` (pgid probe, no `pkill -f`)
  - `@test "it returns the command's own status when the command finishes first"`
  - `@test "it uses no timeout(1)"` — `run grep -nE` + `[ "$status" -ne 0 ]`,
    since macOS has none. Prove it bites by temporarily adding `timeout `.
- Fails: `review_with_deadline` does not exist.

#### Step 15 — `review_with_deadline` (GREEN)
- `commands/spec/review.lib.sh`: background the command, background a sleeper,
  `wait -n`, kill the loser's process group, exit 124 on expiry. Portable:
  no `timeout(1)`, no `date -d`.
- All step-14 tests pass. This is a prerequisite for steps 17 and 19.

#### Step 16 — `review_codex_plugin_root` resolution, every row (RED)
- Extend `tests/hooks/spec-review-codex.bats`, all under a fake `HOME` and a
  stub `node` on `PATH` (never the real plugin):
  - `@test "an explicit plugin_root wins over installed_plugins.json"`
  - `@test "the local-scope entry whose projectPath equals the repo root wins"`
  - `@test "otherwise the user-scope entry's installPath is used"`
  - `@test "a root without scripts/codex-companion.mjs is companion-missing"`
  - `@test "no codex@openai-codex entry at all is not-installed"`
  - `@test "a version below 1.0.6 is unsupported-companion <version>"`
  - `@test "an absent version is unknown-version"`
  - `@test "an unparseable version is unknown-version"`
  - `@test "the reason token is exactly one of the four, never concatenated"`
    — a fixture satisfying two failure conditions at once emits exactly one
    token; prove it bites by temporarily concatenating
  - `@test "an explicit plugin_root absent from installed_plugins.json reads
     .claude-plugin/plugin.json and succeeds at 1.0.6"`  (**AC5d's load-bearing
     row** — fails if the version is sourced only from
     `installed_plugins.json`)
  - `@test "a root present in both sources reads installed_plugins.json"`
  - `@test "a root present in neither is unknown-version"`
  - `@test "a manifest present but unparseable is unknown-version"`
  - `@test "a companion whose help output omits --prompt-file --cwd and --json
     still resolves at 1.0.6"` (**AC5a**, driven by step 1's verbatim
     `printusage-1.0.6.txt`)
  - `@test "resolution invokes no help or --help subcommand"` — the stub's argv
    log contains no help invocation; prove it bites by adding one
  - `@test "1.0.6 and above resolve, forward-compatibly"` (e.g. 1.7.0)
- Fails: `review_codex_plugin_root` does not exist.

#### Step 17 — `review_codex_plugin_root` + per-path version discovery (GREEN)
- `commands/spec/review.lib.sh`: `review_codex_plugin_root <toml> <agent>`,
  `_review_codex_version_for_root <root> <source>`, `_review_version_ge
  <a> <b>`. Version source is decided **by how the root was resolved** — the
  `installed_plugins.json` entry, else `<root>/.claude-plugin/plugin.json`.
  No help-text probe anywhere.
- Portability: no `realpath -m`, no `readlink -f`; canonicalize with
  `cd "$d" && pwd -P`. JSON read via `jq` (already a repo dependency).
- All step-16 tests pass.

#### Step 18 — `review_codex_preflight` and its memoization (RED)
- Extend `tests/hooks/spec-review-codex.bats`:
  - `@test "{\"ready\":true} from setup --json returns zero"`
  - `@test "{\"ready\":false,...} returns non-zero with not-ready <reason>"`
  - `@test "a ready-false setup surfaces as codex-plugin-unavailable"`
  - `@test "a ready-false setup is never codex-output-unparseable"` (negative;
    prove it bites)
  - `@test "two codex-plugin agents sharing one plugin_root call setup exactly once"`
  - `@test "two agents with different plugin_root values call setup once each"`
  - `@test "two path strings resolving through a symlink to one root call setup once"`
    (**the row that fails if the memo key is the input string** — AC5c)
  - `@test "with one root ready and the other not, the first dispatches and the
     second records codex-plugin-unavailable not-ready"`
- Fails: `review_codex_preflight` does not exist.

#### Step 19 — `review_codex_preflight` (GREEN)
- `commands/spec/review.lib.sh`: canonicalize the root **before** forming the
  memo key, then memoize in an associative array keyed on that canonical path.
  The `setup --json` call runs under `review_with_deadline`.
- All step-18 tests pass.

#### Step 20 — `review_codex_task_argv` and the inode proof (RED)
- Extend `tests/hooks/spec-review-codex.bats`:
  - `@test "review_codex_task_argv emits exactly the background launch argv"`
    — NUL-separated, compared via `tr '\\0' '\\n'`, asserting the exact word
    sequence `node <root>/scripts/codex-companion.mjs task --background
    --fresh --json --prompt-file <payload> --cwd <cwd>`
  - `@test "--model appears only when the registry sets it"`
  - `@test "--effort appears only when the registry sets it"`
  - `@test "--write never appears in the argv"` (negative; prove it bites)
  - `@test "--resume never appears in the argv"` (negative; prove it bites)
  - `@test "--resume-last never appears in the argv"` (negative; prove it bites)
  - `@test "the dispatched --prompt-file is the round artifact itself, not a copy"`
    — the stub node asserts `[ "$f" -ef "$ART" ]`. **`test -ef`, never
    `stat -c`**, which `tests-portability-sweep.bats` flags.
- Fails: `review_codex_task_argv` does not exist.

#### Step 21 — `review_codex_task_argv` (GREEN)
- `commands/spec/review.lib.sh`: emits NUL-separated argv; `--model`/`--effort`
  conditional; never emits the three forbidden flags.
- All step-20 tests pass.

#### Step 22 — `review_parse_codex_task_output`, total over the table (RED)
- Extend `tests/hooks/spec-review-codex.bats`, exercising the **public
  two-argument** signature:
  - `@test "a one-argument call is a named usage error"` (AC9's explicit
    requirement that the status is a parameter, not ambient)
  - `@test "status 0, non-empty rawOutput, zero exit yields the response"`
  - `@test "the verbatim captured 1.0.6 success output yields its rawOutput"`
    (step 1's fixture)
  - `@test "numeric status 1 is failed codex-output-unparseable"`
  - `@test "status 0 with an empty rawOutput is failed codex-output-unparseable"`
  - `@test "status 0 with an absent rawOutput is failed codex-output-unparseable"`
  - `@test "invalid JSON with a zero exit is failed codex-output-unparseable"`
  - `@test "non-zero exit with non-JSON stdout is failed codex-task-error"`
  - `@test "valid success-shaped JSON with a non-zero exit is failed
     codex-task-error"` (**the quadrant** — neither accepting the verdict nor
     filing it as unparseable passes)
  - `@test "non-empty touchedFiles is failed codex-wrote-files even with a
     valid verdict in rawOutput"`
  - `@test "a string status of \"completed\" is not treated as success"`
    (**AC9a**; prove it bites by adding string matching)
  - `@test "the parser never reads stderr"` — a stderr file exists beside the
    stdout file and its content never appears in the parser's output; prove it
    bites by making the parser read it
- Fails: `review_parse_codex_task_output` does not exist.

#### Step 23 — `review_parse_codex_task_output` (GREEN)
- `commands/spec/review.lib.sh`: `<file> <exit-status>`; `touchedFiles` wins
  over every other row; numeric-only status comparison; classifies and nothing
  else. The **caller** captures stderr and attaches the excerpt on a
  `codex-task-error`.
- All step-22 tests pass.

#### Step 24 — The job lifecycle, cancel and confirmation (RED)
- Extend `tests/hooks/spec-review-codex.bats`:
  - `@test "review_codex_job_id extracts the job id from the launch output"`
  - `@test "review_codex_job_status polls at 5 s until the stub reports terminal"`
  - `@test "review_codex_job_result supplies the output the parser then parses"`
  - `@test "a never-terminating stub at review_timeout_s=2 calls cancel exactly once"`
  - `@test "the deadline path makes exactly one confirming status call after cancel"`
  - `@test "a confirmed cancellation records <agent> timeout"`
  - `@test "a cancel whose following status still reports the job active records
     failed codex-cancel-unconfirmed <job-id>, not timeout"` (**AC6b**)
  - `@test "the job id appears in the codex-cancel-unconfirmed message"`
  - `@test "the codex-plugin timeout path never kills a process group"`
    (**AC10's second half**; negative, prove it bites)
- Fails: none of the four job helpers exists.

#### Step 25 — The job helpers and the polling driver (GREEN)
- `commands/spec/review.lib.sh`: `review_codex_job_id`,
  `review_codex_job_status`, `review_codex_job_result`,
  `review_codex_job_cancel` (zero **only** on confirmed cancellation), and
  `_review_codex_poll <root> <job-id> <timeout-s>`. Every companion invocation
  runs under `review_with_deadline`.
- All step-24 tests pass.

#### Step 26 — The unavailable round and the mode router (RED)
- Extend `tests/hooks/spec-review-codex.bats`:
  - `@test "a [codex-plugin, stub-cli] round with no plugin installed records
     failed codex-plugin-unavailable not-installed"`
  - `@test "the stub-cli agent in that round still dispatches"`
  - `@test "the message names /codex:setup"`
  - `@test "no codex binary is executed"` — a stub `codex` first on `PATH`
    writes a marker; assert the marker is absent. Prove it bites by invoking it.
  - `@test "no fallback to codex exec appears in the adapter"` (negative grep;
    prove it bites)
- Extend `tests/hooks/spec-review-dispatch.bats`:
  - `@test "review_dispatch_agent routes a cli entry through
     review_dispatch_payload by its input mode"`
  - `@test "review_dispatch_agent routes codex-plugin through the AC6 argv"`
  - `@test "review_dispatch_agent returns non-zero for subagent with the
     orchestrating-session error"`
  - `@test "the subagent branch writes nothing to stdout"`
- Fails: `review_dispatch_agent` and `review_codex_unavailable_message` do not
  exist.

#### Step 27 — `review_dispatch_agent` + the unavailable message (GREEN)
- `commands/spec/review.lib.sh`: the mode router and the `/codex:setup`
  diagnostic. Never a `codex exec` fallback.
- All step-26 tests pass.

#### Step 28 — Extract the codex adapter (REFACTOR)
- Move the step 15-27 helpers into `commands/spec/review-codex.lib.sh`,
  sourced by `review.lib.sh` via the sanctioned cross-lib pattern:
  `source "$_REVIEW_LIB_DIR/review-codex.lib.sh"` with `_REVIEW_LIB_DIR` from
  `"$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"` — never a bare
  `${BASH_SOURCE[0]}` (the zsh guard in `spec-consolidate.bats` flags it).
- `tests/hooks/lib-zsh-safety.bats` globs `commands/**/*.lib.sh`, so the new
  lib is covered with no test edit.
- All tests still pass; `review.lib.sh` stops growing past ~1,600 lines.

### Phase D — The payload byte boundary (AC8, spec branches)

#### Step 29 — Payload ends (RED)
- Add `tests/hooks/spec-review-payload-boundary.bats` (new file — do **not**
  edit `spec-review-payload.bats`, the 0052 floor):
  - `@test "the full-round payload begins with a non-whitespace byte"`
  - `@test "the full-round payload ends with exactly one newline"`
  - `@test "the scoped --diff payload begins with a non-whitespace byte"`
  - `@test "the scoped --diff payload ends with exactly one newline"`
  - `@test "an input ending with no newline still yields exactly one trailing newline"`
  - `@test "an input ending with several newlines is collapsed to exactly one"`
  - `@test "a template whose first line is blank leaks no leading newline"`
- Measured on the **file**, never on a command substitution
  (`.speccraft/conventions.md` §"A byte-exactness contract measures a FILE").
- Fails: the composer normalizes neither end; a reference-less round returns
  early (line 841) and a trailing-newline-free spec source passes through.

#### Step 30 — Normalize both payload ends (GREEN)
- `commands/spec/review.lib.sh`: a leading-whitespace guard and a single
  trailing-newline normalizer applied to the composed stream on **every**
  branch, including the early `(none)` return. The budget keeps measuring the
  untrimmed artifact (an upper bound on what the companion's trim sends).
- All step-29 tests pass; the 0052 composer tests pass unedited.

### Phase E — The persistent round directory (ACs 14, 14a, 14b, 14c, 14e, 15a, 15b, 17b, 17c)

#### Step 31 — Create, publish, ignore, clean up (RED)
- Add `tests/hooks/spec-review-round-dir.bats`:
  - `@test "review_round_dir_create makes a 0700 dir under .speccraft/.review-rounds/"`
  - `@test "the round dir survives the creating shell"` (verified from a second shell)
  - `@test "review_round_cleanup removes a round dir"`
  - `@test "review_round_cleanup refuses a path outside .review-rounds/"`
  - `@test "review_round_cleanup refuses a symlink"`
  - `@test "review_round_cleanup refuses /"`
  - `@test "review_round_cleanup refuses an escaping .."`
  - `@test "each refusal deletes nothing"` (asserted per row, not once)
  - `@test "cleanup resolves symlinks on both sides under a symlinked TMPDIR"`
  - `@test "cleanup resolves a symlinked ancestor of the repo root"`
  - `@test "review_round_dir_create writes .speccraft/.review-rounds/.gitignore containing *"`
  - `@test "the .gitignore write is idempotent across two rounds"`
  - `@test "git check-ignore reports the round dir and its payload ignored in this repo"`
  - `@test "a repo freshly initialized from the template ignores the round dir"`
  - `@test "a pre-0054 installed-base fixture repo ignores the round dir with no re-init"`
    — against the **checked-in** fixture
    `tests/hooks/fixtures/review-dispatch/legacy-repo/gitignore.pre0054`, a
    byte-copy of the template's `.gitignore` as it shipped before this spec
    (AC14a is explicit that the test must not construct this shape itself)
  - `@test "git add -A in that legacy repo stages nothing from the round dir"`
  - `@test "two different <timeout-s> values yield two different lease expiries,
     each timeout plus 300"` (**AC14e**)
  - `@test "the .building-<expiry>-<rand> temp name the helper chose is recorded
     by its instrumentation"` — AC14e explicitly requires interleaving **or**
    instrumentation; use instrumentation (`$REVIEW_ROUND_BUILD_NAME`), since a
    successful create renames the name away
- Fails: none of `review_round_dir_create`, `review_round_lease_write`,
  `review_round_cleanup` exists.

#### Step 32 — Round dir create, lease, cleanup (GREEN)
- `commands/spec/review.lib.sh`: `review_round_dir_create <kind> <id>
  <timeout-s>` — build under `.building-<expiry-unix-ts>-<rand>` **inside**
  `.review-rounds/` with the absolute expiry (`now + timeout + 300`) fixed at
  `mkdir` time **before any fallible setup**, write the `lease` into it, then
  `mv` to the final name; write `.review-rounds/.gitignore` containing `*`
  idempotently via same-dir temp + rename. Plus `review_round_lease_write`,
  `review_round_lease_expired`, `review_round_cleanup` (resolve both sides
  before comparing — spec 0050 defect A).
- Portability: `date +%s` + shell arithmetic, **never `date -d`**.
- All step-31 tests pass.

#### Step 33 — Lease-based sweeping (RED)
- Extend `tests/hooks/spec-review-round-dir.bats`:
  - `@test "review_round_sweep removes only the dir whose lease has expired"`
    (both mtimes faked far in the past with `touch -t`)
  - `@test "the old-but-active round's payload is intact after the sweep"`
  - `@test "a dir with a missing lease is removed"`
  - `@test "a dir with an unparseable lease is removed"`
  - `@test "review_round_sweep takes no age or max-age argument"` — passing one
    is a usage error, **and** a grep of the lib finds no such option; prove the
    grep bites
  - `@test "a created round survives a sweep looped against a creator looped"`
    (**AC14c**, the publish race)
  - `@test "a fresh .building-* dir survives a concurrent sweep"`
  - `@test "a .building-* dir whose encoded expiry has passed is reclaimed"`
  - `@test "the sweep reads the expiry off the name and never recomputes it"`
    — two `.building-*` dirs with different encoded expiries are judged on
    their own thresholds
  - `@test "a published round dir is never matched by the .building rule"`
- Fails: `review_round_sweep` does not exist.

#### Step 34 — `review_round_sweep` (GREEN)
- `commands/spec/review.lib.sh`: no argument, no config read. Lease-expired OR
  lease-missing OR lease-unparseable ⇒ delete; `.building-*` ⇒ delete once the
  **name's** expiry has passed; never on age.
- All step-33 tests pass.

#### Step 35 — Quarantine (RED)
- Extend `tests/hooks/spec-review-round-dir.bats`:
  - `@test "review_round_quarantine records the id, outcome, time and mode"`
  - `@test "a codex-plugin quarantine records the canonical resolved companion root"`
  - `@test "a codex-plugin quarantine without a root is a named error"`
  - `@test "a subagent quarantine omits the root"`
  - `@test "review_round_quarantined returns zero for a quarantined dir"`
  - `@test "review_round_cleanup refuses a quarantined dir and deletes nothing"`
  - `@test "review_round_sweep reports and does not delete a quarantined dir
     whose lease expired"`
  - `@test "the sweep report line is grep-able as <dir>: quarantined <outcome>
     <id> lease-expired <iso-ts>"`
  - `@test "removing the quarantine file lets the same sweep reclaim the dir"`
  - `@test "a quarantined dir outlives its own expired lease"`
  - `@test "a quarantined codex-plugin round is reclaimed after a stub status
     reports the job inactive"` (**AC15b**)
  - `@test "the status probe goes to the root recorded in the quarantine file,
     not a re-resolved one"` — the recorded root **differs** from what
    re-resolution would now produce (the install was removed /
    `plugin_root` dropped). **This is the only row that proves the field is
    used rather than merely written**; it is required.
  - `@test "two installations with one quarantined job each are probed with
     their own companion"` (per-root call counts from step 1's stub)
  - `@test "a quarantined subagent round is reclaimed by no probe"`
  - `@test "no Agent-tool termination query is attempted for a quarantined
     subagent round"` (negative over the lib **and** the runbook; prove it bites)
  - `@test "no exit path both quarantines and deletes"` (**AC15a**)
- Fails: no quarantine helper exists.

#### Step 36 — Quarantine helpers + sweep integration (GREEN)
- `commands/spec/review.lib.sh`: `review_round_quarantine <dir> <id> <outcome>
  <mode> [<companion-root>]`, `review_round_quarantined <dir>`,
  `review_round_quarantine_resolve <dir>` (codex-plugin only), plus the
  cleanup refusal and the sweep's report-not-delete branch.
- All step-35 tests pass.

#### Step 37 — The content-aware tree snapshot (RED)
- Add `tests/hooks/spec-review-tree-snapshot.bats`:
  - `@test "review_tree_snapshot hashes every tracked file outside the round dir"`
  - `@test "it hashes every untracked regular file"`
  - `@test "two files under one untracked directory both appear in the snapshot"`
    (**the row that fails if `--directory` is ever used**)
  - `@test "it records path and type for untracked non-regular entries without hashing them"`
  - `@test "modifying an already-dirty tracked file changes the snapshot"` (required)
  - `@test "adding a file beneath an already-untracked directory changes the snapshot"` (required)
  - `@test "editing the bytes of an existing untracked file changes the snapshot"` (required)
  - `@test "writing bin/probe changes the snapshot"` (required — the hard-guardrail row)
  - `@test "writing tools/bin/probe changes the snapshot"` (required)
  - `@test "the enumeration passes no --exclude-standard"` (negative; prove it bites)
  - `@test "the enumeration passes no --directory"` (negative; prove it bites)
  - `@test "the implementation never compares git status --porcelain text"` (negative; prove it bites)
  - `@test "the implementation relies on no path-only untracked inventory"` (negative)
  - `@test "a mid-round write to .claude/settings.local.json leaves the check passing"`
  - `@test "a mid-round write to .speccraft/state.json leaves the check passing"`
  - `@test "a mid-round write to tests/e2e/.logs/ leaves the check passing"`
  - `@test "a mid-round write to .speccraft/.review-rounds/.gitignore leaves the check passing"`
  - `@test "a write to any other ignored path fails the check"`
  - `@test "the exclusion list contains exactly four entries"` (**the closed set**)
  - `@test "the pre-round snapshot is taken after review_round_dir_create"`
    (**AC17c**, sequence asserted)
  - `@test "a full round in a repo with no .review-rounds/.gitignore records no
     subagent-wrote-files"` (AC17c, installed-base first round)
  - `@test "the check passes with a pre-existing dirty tree and a pre-existing
     untracked file and nothing else changed"` (AC17c's sensitivity-without-noise row)
- Fails: `review_tree_snapshot` does not exist.

#### Step 38 — `review_tree_snapshot` (GREEN)
- `commands/spec/review.lib.sh`: sha256 of every tracked file plus every
  untracked **regular** file outside the round dir, enumerated with
  `git ls-files --others -z` per file; path+type for non-regular entries; the
  four-entry closed exclusion list in one named array.
- **Digest via `_review_digest_cmd`, never a literal `sha256sum`** — both
  `portability-guard.bats` (shipped surfaces) and
  `tests-portability-sweep.bats` (tests/hooks) flag that token.
- All step-37 tests pass.

#### Step 39 — Extract the round-directory lib (REFACTOR)
- Move steps 32-38's helpers into `commands/spec/review-round.lib.sh`, sourced
  from `review.lib.sh` with the same `${BASH_SOURCE[0]:-$0}` idiom.
- All tests still pass; zsh-safety and portability sweeps pick it up by glob.

### Phase F — One shared round for all four commands (ACs 8-rest, 16, 16a, 17, 19, 20, 21, 22, 22a)

#### Step 40 — The shared runbook and the four command files (RED) — **pure markdown**
- Add `tests/hooks/spec-review-round-runbook.bats`:
  - `@test "the shared runbook file exists at skills/review-round/SKILL.md"`
  - `@test "it names all four modes"`
  - `@test "it states that subagent reviewers are dispatched by the
     orchestrating session, not by aux-delegator"`
  - `@test "its Agent dispatch instruction carries model: opus for a registry
     model of opus"` (**AC19**)
  - `@test "it carries no model when the registry says inherit or omits it"` (AC19)
  - `@test "it states that the no-model case relies on reviewer.md's model: inherit"` (AC19)
  - `@test "it records requested: inherit (per <agent> definition) for a custom
     subagent_type with no model"` (AC19)
  - `@test "it contains no instruction to transcribe the Agent result into .out"`
    (**AC17a**, negative; prove it bites)
  - `@test "it spells out the seven-step subagent timeout and cancellation protocol"`
  - `@test "it prints the round dir path for the runbook to carry across tool calls"`
  - `@test "each of the four review command files references the shared runbook"` (AC20)
  - `@test "each of the four lists Agent in allowed-tools"` (AC20)
  - `@test "each of the four lists TaskStop in allowed-tools"` (AC20, asserted
    in all four — the timeout protocol cannot stop a reviewer without it)
  - `@test "each of the four lists Bash(shasum:*) and Bash(sha256sum:*)"` (AC20)
  - `@test "review-code additionally lists Write"` (AC20)
  - `@test "each of the four names all four modes"` (AC20)
  - `@test "arch:review names design.md and design/<id>/review.md"` (AC20)
  - `@test "pm:review names brief.md and product/<id>/review.md"` (AC20)
  - `@test "no review command still calls the backend unchanged"` (AC20,
    negative; prove it bites — `arch/review.md:3` and `pm/review.md:3` both say
    exactly that today)
- Fails: the runbook file does not exist, and none of the four command files
  lists `Agent`/`TaskStop`.

#### Step 41 — Write the runbook, point all four at it (GREEN) — **pure markdown**
- New `skills/review-round/SKILL.md`: compose → budget-check → dispatch →
  outcome-record → attestation, mode-aware, parameterized by document(s) under
  review / inline set / reference set / template, with the seven-step subagent
  timeout protocol and the per-mode quarantine-resolution rule.
- Edit `commands/spec/review.md`, `commands/arch/review.md`,
  `commands/pm/review.md`, `commands/spec/review-code.md`: `allowed-tools`
  gains `Agent`, `TaskStop`, `Bash(shasum:*)`, `Bash(sha256sum:*)` (and `Write`
  for review-code), bodies reference the runbook, the "unchanged" prose goes.
- **Verify the tool names `Agent` and `TaskStop` against the live Claude Code
  tool surface before writing them** — the spec asserts both and the plan has
  no independent confirmation.
- All step-40 tests pass. External-tool-boundaries check: the runbook describes
  adapters, and uses no "prefer"/"recommended" phrasing about either tool.

#### Step 42 — The attestation extension and every template's schema (RED)
- Add `tests/hooks/spec-review-attestation.bats`:
  - `@test "a subagent response missing payload_sha256 is attestation-failed
     missing-payload-digest"`
  - `@test "a wrong payload_sha256 is attestation-failed payload-digest-mismatch"`
  - `@test "permission_denied: Bash maps to failed subagent-permission-denied"`
  - `@test "it is not reported as a generic attestation-failed"` (negative)
  - `@test "a correct payload digest plus correct reference digests is valid"`
  - `@test "a cli response is unaffected by the payload-digest rule"`
  - `@test "every dispatchable template's documented reference_access block
     round-trips through _review_parse_reference_access"` — table over
    `templates/prompts/{review,re-review,review-code,arch-review,pm-review}.md`;
    extract the block, fill the placeholders, assert it pairs into
    `ACCESS-PATH`/`ACCESS-SHA` (**AC16a**)
  - `@test "every dispatchable template documents payload_sha256 in its attested block"`
  - `@test "the YAML-map shape <path>: <digest> is rejected, per template"`
    (the round-3 regression, re-pinned across all five)
  - `@test "the one-line - path: X, sha256: Y shape is rejected, per template"`
  - `@test "a template documenting no reference_access block fails the round trip"`
    (so a sixth template added later cannot pass vacuously)
- Note: `templates/prompts/re-review.md`'s `reference_access` schema and three
  of these assertions **already landed on this branch** in
  `tests/hooks/spec-review-diff.bats` — do not duplicate those three; the new
  file generalizes them to all five templates and adds `payload_sha256`.
- Fails: three templates do not exist, none documents `payload_sha256`, and
  the validator has no subagent arm.

#### Step 43 — The validator's subagent arm and the five templates (GREEN)
- `commands/spec/review.lib.sh`: `_review_parse_reference_access` gains
  `PAYLOAD-SHA` and `PERMISSION-DENIED` tokens;
  `review_validate_reference_access` gains a `subagent`-mode arm checking
  `payload_sha256` against the payload file's digest and mapping
  `permission_denied: <tool>` to `failed subagent-permission-denied`.
- New `templates/prompts/review-code.md` (challenge framing),
  `templates/prompts/arch-review.md`, `templates/prompts/pm-review.md`; add
  `payload_sha256` to all five templates' attested blocks.
- All step-42 tests pass; the spec-0052 `cli` attestation tests pass unedited.

#### Step 44 — review-code freezes ONE diff (RED)
- Add `tests/hooks/spec-review-code.bats`:
  - `@test "the diff is computed exactly once into the round dir"`
  - `@test "with a staged edit reversed in the working tree every reviewer's
     payload contains the same git diff HEAD bytes"`
  - `@test "with --base the frozen diff is git diff <ref>...HEAD"`
  - `@test "an untracked file is absent from the frozen diff"`
  - `@test "with no active spec the round still runs"`
  - `@test "with no active spec the payload states that no spec is active"`
  - `@test "the composed payload names the untracked-file exclusion in prose"` (**AC22a**)
  - `@test "the round's stdout repeats the untracked-file exclusion"` (AC22a)
  - `@test "the code-review template keeps a challenge framing"`
  - `@test "no --include-untracked option exists"` (negative, out of scope)
- Fails: `review_freeze_diff` does not exist and `review-code.md` recomputes
  the diff per agent.

#### Step 45 — `review_freeze_diff` + the review-code body (GREEN)
- `commands/spec/review.lib.sh`: `review_freeze_diff <round-dir> [<base>]`,
  writing one artifact and refusing a second materialization (the 0052
  single-creation seam).
- `commands/spec/review-code.md`: freeze once, compose per agent from the
  frozen diff, record outcomes (hence the new `Write` permission), repeat the
  exclusion on stdout.
- All step-44 tests pass.

#### Step 46 — AC8 over the new branches, and AC17's distinct artifacts (RED)
- Extend `tests/hooks/spec-review-payload-boundary.bats`:
  - `@test "the arch payload begins with a non-whitespace byte and ends with one newline"`
  - `@test "the pm payload begins with a non-whitespace byte and ends with one newline"`
  - `@test "the review-code payload begins with a non-whitespace byte and ends with one newline"`
- Extend `tests/hooks/spec-review-round-runbook.bats`:
  - `@test "two byte-identical <agent>.out artifacts in one round are reported
     as a dispatch failure, not two verdicts"` (**AC17**)
  - `@test "two byte-identical subagent .out artifacts are reported the same way"`
  - `@test "neither verdict is counted when the hashes match"`
- Fails: the composer has no arch/pm/review-code branch and there is no
  hash-compare helper (0052 left it as runbook prose).

#### Step 47 — Composer `--label` + `review_hash_compare_outputs` (GREEN)
- `commands/spec/review.lib.sh`: `review_compose_payload` gains `--label <text>`
  (default byte-identical to today's literal, per decision 3);
  `review_hash_compare_outputs <round-dir>` returns non-zero naming the two
  agents on any duplicate digest.
- All step-46 tests pass; 0052's composer tests pass unedited.

#### Step 48 — arch/pm write `review.md` only on a complete round (RED)
- Extend `tests/hooks/spec-review-round-runbook.bats`:
  - `@test "arch:review writes design/<id>/review.md on a complete round"`
  - `@test "an inert arch round leaves an existing review.md byte-unchanged"` (`cmp -s`)
  - `@test "an inert arch round creates no review.md where none existed"`
  - `@test "pm:review writes product/<id>/review.md on a complete round"`
  - `@test "an inert pm round leaves an existing review.md byte-unchanged"`
  - `@test "an inert pm round creates no review.md where none existed"`
  - `@test "neither kind promotes a snapshot or stamps a fingerprint"` (negative)
- Fails: `review_finalize_round` is spec-only — it writes
  `<dir>/review.md` plus the snapshot and fingerprint unconditionally.

#### Step 49 — `review_finalize_round` gains `<kind>` (GREEN)
- `commands/spec/review.lib.sh`: optional 4th arg `<kind>` defaulting to
  `spec` (decision 4). `design`/`brief` write `review.md` with no snapshot and
  no fingerprint; `code` writes nothing durable.
- All step-48 tests pass; 0052's finalize tests pass unedited.

### Phase G — The subagent reviewer, vendor, refusals, docs (ACs 17d, 18, 18a, 18b, 20a, 20b, 23, 23a, 23b, 24, 25)

#### Step 50 — `agents/reviewer.md` shape and the naming contrast (RED) — **pure markdown**
- Add `tests/hooks/review-subagent-agent.bats`:
  - `@test "agents/reviewer.md frontmatter name is reviewer"`
  - `@test "its tools are exactly Read, Grep, Glob, Bash(shasum:*), Bash(sha256sum:*), Write"`
  - `@test "its model is inherit"`
  - `@test "it declares no Edit"` (negative; prove it bites)
  - `@test "it declares no bare Bash"` (negative; prove it bites — mechanical
    scoping is the point)
  - `@test "its body instructs reading the payload by path, never pasted content"`
  - `@test "its body instructs reporting payload_sha256"`
  - `@test "its body instructs reporting permission_denied: <tool>"`
  - `@test "its body names the speccraft verdict vocabulary"`
  - `@test "its body confines Write to <round-dir>/<agent>.out"`
  - `@test "its body forbids writing any other path"`
  - `@test "agents/reviewer.md states the reviewer-vs-synthesizer contrast in its first lines"` (AC18a)
  - `@test "agents/cross-reviewer.md states the contrast in its first lines"` (AC18a)
  - `@test "neither file describes itself with the other's role"` (negative; prove it bites)
  - `@test "skills/aux-agents/SKILL.md documents both names"` (AC18a)
- Fails: `agents/reviewer.md` does not exist.

#### Step 51 — Write `agents/reviewer.md`, amend the siblings (GREEN) — **pure markdown**
- New `agents/reviewer.md`; edit `agents/cross-reviewer.md`'s opening lines;
  extend `skills/aux-agents/SKILL.md` with both names.
- All step-50 tests pass.

#### Step 52 — Custom `subagent_type` preflight (RED)
- Add `tests/hooks/spec-review-subagent.bats`:
  - `@test "a custom subagent_type lacking Write is failed subagent-launch
     missing-write-tool"`
  - `@test "that refusal happens before any Agent launch"` (a marker-writing
    stub proves nothing launched; prove it bites)
  - `@test "a custom subagent_type declaring Edit produces a review-time warning"`
  - `@test "it still dispatches"`
  - `@test "an unknown subagent_type is failed subagent-launch <reason>"`
  - `@test "every failure leaves the prior durable review.md byte-unchanged"` (`cmp -s`)
- Fails: `review_subagent_preflight` does not exist.

#### Step 53 — `review_subagent_preflight` (GREEN)
- `commands/spec/review.lib.sh`: reads `<agents-dir>/<type>.md`'s frontmatter
  `tools`, refuses on absent `Write`, warns on `Edit`, names an unknown type.
  Wire it into the runbook's dispatch step.
- All step-52 tests pass.

#### Step 54 — The subagent timeout, late completion and no-output (RED)
- Extend `tests/hooks/spec-review-subagent.bats`:
  - `@test "the agent id and an absolute deadline are recorded in the round dir"`
  - `@test "a never-completing stub at review_timeout_s=2 is stopped via TaskStop"`
  - `@test "it is recorded <agent> timeout"`
  - `@test "the round still finalizes after a subagent timeout"`
  - `@test "a TaskStop that errors records failed subagent-stop-failed <agent-id>"`
  - `@test "the agent id appears in the stop-failed message"`
  - `@test "a reviewer completing after its deadline is recorded <agent> timeout late-completion"`
  - `@test "a late verdict is not counted toward quorum"`
  - `@test "the already-finalized review.md is byte-unchanged after a late completion"` (`cmp -s`)
  - `@test "the round reads <round-dir>/<agent>.out from disk"` (AC17a)
  - `@test "a missing <agent>.out after the agent returns is failed subagent-no-output"`
  - `@test "an empty <agent>.out is failed subagent-no-output, never an empty verdict"`
  - `@test "partial output is never a verdict"`
- Fails: no subagent record/collect helper exists.

#### Step 55 — Subagent record / collect / deadline helpers (GREEN)
- `commands/spec/review.lib.sh`: `review_subagent_record <dir> <agent>
  <agent-id> <deadline>`, `review_subagent_collect <dir> <agent>`,
  `review_subagent_deadline_expired <dir> <agent>`, and the stop-failed ⇒
  `review_round_quarantine` wiring. Runbook gains the executable form of the
  seven-step protocol.
- All step-54 tests pass.

#### Step 56 — Attribution with concurrent subagents (RED)
- Extend `tests/hooks/spec-review-subagent.bats`:
  - `@test "two concurrent subagents with one writing out of bounds both record
     failed subagent-wrote-files <unattributed>"`
  - `@test "that round's responses_complete is false"`
  - `@test "quorum cannot be met by the innocent reviewer's approval"`
  - `@test "with exactly one subagent active the outcome names that agent"`
  - `@test "that single-agent outcome carries no <unattributed> marker"` (negative; prove it bites)
  - `@test "two concurrent subagents with no out-of-bounds write record neither failure"`
    (**so the rule is not merely fail-everything-when-two-run**)
  - `@test "a codex-plugin reviewer running alongside a writing subagent is not failed"`
  - `@test "activity is defined over the snapshot interval, not an instant"`
    — a subagent live at any point between the pre- and post-snapshot counts
- Fails: no attribution helper exists.
- **Determinism note:** record each subagent's activity interval in the round
  dir at launch/return and read it back; never infer "active" from timing
  (`.speccraft/conventions.md` §Ledger write-lock: "contention tests use the
  seam, never wall-clock timing").

#### Step 57 — `review_attribute_tree_writes` (GREEN)
- `commands/spec/review.lib.sh`: compares pre/post `review_tree_snapshot`;
  one active subagent ⇒ name it; more than one ⇒ `<unattributed>` on **every**
  such subagent; `codex-plugin` reviewers are never swept in (their
  `touchedFiles` is per-job, self-attested and trusted).
- All step-56 tests pass.

#### Step 58 — Vendor, quorum and the single-vendor flag (RED)
- Add `tests/hooks/spec-review-vendor.bats`:
  - `@test "review_agent_vendor resolves claude to anthropic"`
  - `@test "/usr/local/bin/claude resolves to anthropic by basename"`
  - `@test "claude -p --allowedTools ... resolves to anthropic on argv[0] only"`
  - `@test "claude-p resolves to unknown"`
  - `@test "claude_wrapper.sh resolves to unknown"`
  - `@test "codex resolves to openai"`
  - `@test "/opt/wrappers/opus resolves to unknown"`
  - `@test "subagent mode resolves to anthropic by construction"`
  - `@test "codex-plugin mode resolves to openai by construction"`
  - `@test "no substring matching: claudex resolves to unknown"` (negative)
  - `@test "no first-token-prefix matching: claude-code resolves to unknown"` (negative)
  - `@test "one subagent approve plus one cli changes-requested at quorum 1 is
     responses_complete true and approval_quorum_met true"` (AC23)
  - `@test "a subagent attestation-failed makes responses_complete false"` (AC23)
  - `@test "the synthesized review.md lists each verdict's mode"` (AC23)
  - `@test "... its requested model"` (AC23)
  - `@test "... its vendor"` (AC23)
  - `@test "a round whose only approval is anthropic on a spec authored by
     claude writes single_vendor_approval: true"` (AC23a)
  - `@test "that round still meets quorum"` (**the flag is a record, not a gate**)
  - `@test "one anthropic plus one openai approval writes single_vendor_approval: false"`
  - `@test "quorum arithmetic is byte-identical with and without the flag"`
    (so 0052's quorum tests are unaffected)
- Fails: `review_agent_vendor` does not exist and `review_finalize_round`
  records no per-verdict mode/model/vendor.

#### Step 59 — `review_agent_vendor` + the recorded flag (GREEN)
- `commands/spec/review.lib.sh`: `review_agent_vendor <toml> <agent>` by exact
  basename match on argv[0] of `cmd`, mode-derived for the two new modes;
  `review_single_vendor_approval <toml> <outcomes> <authors>`;
  `review_finalize_round` records per-verdict `mode`/`model`/`vendor` and the
  round-level `single_vendor_approval`.
- `agents/cross-reviewer.md`'s `review.md` template gains those columns and
  the round flag.
- All step-58 tests pass.

#### Step 60 — Review-only modes refused by non-review consumers (RED)
- Add `tests/hooks/review-only-mode-refusal.bats`:
  - `@test "the refusal names the mode and the four review commands"`
  - `@test "the refusal names cli and acp as what spec:delegate supports"`
  - `@test "spec:delegate refuses a codex-plugin entry"`
  - `@test "spec:delegate refuses a subagent entry"`
  - `@test "aux-delegator refuses both the same way"`
  - `@test "the refusal is a precondition check before any dispatch"` — a stub
    recording invocation proves nothing ran; prove it bites
  - `@test "aux-delegator's documentation states the restriction"`
  - `@test "the error text promises no future support"` (negative — "guardrail,
    not a roadmap")
  - `@test "cli delegation through both consumers is unchanged"`
  - `@test "acp delegation through both consumers is unchanged"`
- Fails: `review_refuse_review_only_mode` does not exist and neither consumer
  mentions the new modes.

#### Step 61 — The shared refusal helper + two doc edits (GREEN) — **part markdown**
- `commands/spec/review.lib.sh`: `review_refuse_review_only_mode <mode>`
  emitting the one message both consumers use (one text, not two copies).
- Edit `commands/spec/delegate.md` and `agents/aux-delegator.md` to call it as
  a precondition.
- All step-60 tests pass; the existing delegate tests pass unedited.

#### Step 62 — Template, convention, skill (RED) — **pure markdown/TOML**
- Add `tests/hooks/review-dispatch-docs.bats`:
  - `@test "conventions.md External-tool boundaries contains the
     user-configured review-adapter clarification"` (AC24)
  - `@test "skills/aux-agents/SKILL.md documents what the codex-plugin adapter invokes"`
  - `@test "... its guarantees"`
  - `@test "... what the subagent adapter invokes and its guarantees"`
  - `@test "... /codex:setup as the remedy"`
  - `@test "... the speccraft:reviewer / speccraft:cross-reviewer distinction"`
  - `@test "SKILL.md uses no prefer or recommended phrasing about either tool"`
    (negative; prove it bites)
  - `@test "the template has exactly one enabled subagent entry"` (AC25,
    **parsed per entry**, never a whole-file grep)
  - `@test "that subagent entry sets model = opus"`
  - `@test "the template has one codex-plugin entry with enabled = false"`
  - `@test "every template entry carries an explicit reference_read"` (per entry)
  - `@test "the template comments the same-vendor-default trade-off"`
  - `@test "the template names /codex:setup as the route to a cross-vendor round"`
  - `@test "the template uses no prefer or recommended phrasing"` (negative)
- Add `tools/internal/delegate/template_test.go`:
  - `Test_ShippedTemplate_LoadsWithNewModes` — `templates/speccraft/agents.toml`
    loads via `LoadConfig` and yields one enabled `subagent` with
    `Model == "opus"` and one disabled `codex-plugin`
- Fails: the template has neither new entry; conventions.md has no
  clarification; SKILL.md documents neither mode.

#### Step 63 — Write the template, convention and skill (GREEN) — **pure markdown/TOML**
- `templates/speccraft/agents.toml`: the two entries plus the trade-off
  comment. **Template purity holds** — no language-specific content.
- `.speccraft/conventions.md` §External-tool boundaries: the
  user-configured-adapter clarification (AC24).
- `skills/aux-agents/SKILL.md`: both adapters as documentation, not a
  recommendation.
- All step-62 tests pass, and step 6's `Test_LoadConfig_RealRegistries_
  LoadUnchanged` still passes against the amended template.

### Phase H — Lifecycle integration (ACs 14d, 15, 27)

#### Step 64 — Cleanup on every exit path (RED)
- Add `tests/hooks/spec-review-round-lifecycle.bats`:
  - `@test "a complete round ends with the round dir removed"`
  - `@test "an inert round ends with the round dir removed"`
  - `@test "a dispatch-error round ends with the round dir removed"`
  - `@test "a timed-out-reviewer round ends with the round dir removed once that
     reviewer is proven terminal"`
  - `@test "cleanup is never invoked while a recorded reviewer is still pending"`
    — a pending-reviewer marker; prove it bites
  - `@test "a quarantined round is the one exit path that retains the dir"`
- Fails: no "proven terminal" predicate exists, so cleanup is either
  unconditional or absent.

#### Step 65 — `review_round_all_terminal` + runbook gating (GREEN)
- `commands/spec/review-round.lib.sh`: `review_round_all_terminal <dir>` over
  the recorded reviewer set; runbook's cleanup step gates on it.
- All step-64 tests pass.

#### Step 66 — The lease is never renewed, and every bounded path survives (RED)
- Extend `tests/hooks/spec-review-round-lifecycle.bats`:
  - `@test "a lease file's expiry is byte-identical before and after a full round"`
    (**the load-bearing assertion** — catches a re-stamp under any name,
    including `_touch`/`_bump` or inlined `date` arithmetic)
  - `@test "a codex-plugin round polling to the review_timeout_s deadline
     survives a concurrent sweep"`
  - `@test "its cancel plus one confirming status survives a concurrent sweep"`
  - `@test "a subagent round to its deadline and TaskStop survives a concurrent sweep"`
  - `@test "a cli-only round under review_with_deadline survives a concurrent sweep"`
  - `@test "a quarantined dir outlives its own expired lease"`
  - `@test "review_round_lease_renew is absent from the review libs"` — marked
    **in the test's own comment** as a convention nudge only, not the guard
  - This step is last on purpose: all three dispatch paths must exist, or the
    survival rows pass vacuously.
- Fails on whichever margin or re-stamp the implementation got wrong.

#### Step 67 — Lease margin arithmetic (GREEN)
- Whatever step 66 surfaces, in `commands/spec/review-round.lib.sh`. Expected
  to be small: `+300 s` margin and the no-re-stamp invariant.
- All step-66 tests pass.

#### Step 68 — One outcome-token vocabulary (REFACTOR)
- The eleven new outcome tokens accrete across phases C, E and G. Consolidate
  them into one named table in `review.lib.sh` that `_review_outcome_kind`
  reads, and assert the table is the sole definition (the
  §"One shared parser entrypoint, pinned by a source-scan assertion" pattern).
- All tests still pass.

### Phase I — The gated live smoke, and the CI gate (ACs 26, 26a, 27)

#### Step 69 — The gated skip harness (RED) — **NON-CI**
- Add `tests/hooks/live-codex-smoke.bats`:
  - `@test "AC26 live codex-plugin plus subagent round (SPECCRAFT_LIVE_CODEX_SMOKE)"`
  - `@test "AC26a live cancellation smoke (SPECCRAFT_LIVE_CODEX_SMOKE)"`
  - `@test "each gated test skips with a message naming itself and the knob"`
- Both gated tests `skip "AC26 ... skipped: SPECCRAFT_LIVE_CODEX_SMOKE is not 1"`
  unless the knob is `1` — **they never pass silently**.
- Fails: the file does not exist.

#### Step 70 — Wire the gate (GREEN) — **NON-CI**
- Implement the two gated bodies (the live round and the live cancel) plus the
  self-naming skip. The bodies run only on a host with the Codex plugin
  installed and authenticated.
- All step-69 tests pass (as skips in CI, by design).

#### Step 71 — The close gate (AC27)
- `PATH="$PWD/bin:$PATH" bats tests/hooks/` green on Linux **and** macOS.
- `go test ./...` green; `GOOS=windows go build ./...` green (the
  build-tag-split rule).
- `git status --porcelain bin/ tools/bin/` empty — **never commit either**.
- `git diff --stat` shows **no change** to `tests/hooks/spec-review-payload.bats`
  and no change to `spec-review-diff.bats` beyond this branch's existing three
  tests (the 0052 regression floor).
- The two gated skips appear in the CI log **by name**, so "green" never
  implies the live smoke ran.
- **Then, manually, on a host with the Codex plugin:** run AC26 and AC26a with
  `SPECCRAFT_LIVE_CODEX_SMOKE=1` and record in `changelog.md` the companion
  version, the resolved job ids, that the round went through
  `task --background` + `status` + `result`, and that `/codex:status` shows the
  cancelled turn no longer active.

## Which steps are pure markdown/doc (cheap, batchable)

Steps **40, 41, 50, 51, 62, 63** are entirely markdown/TOML plus grep
assertions, and the doc halves of **61** and **42/43**'s template work are too.
They cost no overrides (markdown is ungated), run in milliseconds, and can be
batched into one commit per phase. Everything else is real logic with real
fixtures. Steps **16-27, 31-38, 54-59, 66-67** are the expensive, genuinely
behavioural work.

## Delegation

- Step 1 (companion fact re-verification + fixture capture) → do **in-session
  on a host with the plugin**; `codex` cannot be trusted to re-verify a claim
  about its own plugin's source without the tree present.
- Steps 2-7 (Go table tests + loader) → delegate to `codex` (registry
  strengths `refactoring, review`; table-driven Go tests are its best fit).
- Steps 22-23 (the total output-classification table) → delegate to `codex`:
  exhaustive-case enumeration over a stated truth table, and the quadrant row
  is exactly the kind a second model is good at keeping honest.
- Steps 37-38 (tree snapshot) → delegate to `codex`, then **review in-session**:
  this guarantee took four iterations in review and the four negative rows are
  the ones most likely to be written inert.
- Steps 40-41, 50-51, 62-63 (markdown) → keep in-session: the
  external-tool-boundaries phrase rule (no "prefer"/"recommended") needs
  judgement a delegate will not apply.
- Every phase boundary → `/speccraft:spec:review-code` with `codex` +
  `claude-p`, per this repo's own cross-model habit.

## Risk

- **`speccraft-state test-command` returns `pytest -q` in this repo**, parsed
  out of the prose example marker at `.speccraft/conventions.md:521`. Every
  `done:` predicate must therefore name its command literally and set `PATH`
  itself (`done: $ PATH="$PWD/bin:$PATH" bats tests/hooks/<file>.bats && …`) —
  a predicate that trusts ambient `PATH` picks up the cached 1.11.0 plugin
  binary. → mitigation: no `done:` line in this plan's `tasks.md` calls
  `test-command`, and every one sets `PATH`. Also worth a separate follow-up
  spec: the marker parser is matching documentation.
- **GNU-only forms.** `sha256sum`, `stat -c`, `readlink -f`, `date -d`, `tac`,
  `grep -P`, `base64 -w`, `realpath -m` and GNU `sed -i` are flagged by
  `portability-guard.bats` on shipped surfaces **and** by
  `tests-portability-sweep.bats` inside `tests/hooks`. This spec's natural
  reaches for all four of the first ones. → mitigation: `_review_digest_cmd`
  for digests, `test -ef` for the AC7 inode proof, `cd && pwd -P` for
  canonicalization, `date +%s` + shell arithmetic for lease expiry, `touch -t`
  for faked mtimes.
- **Inert negative assertions.** This plan contains ~30 negative assertions,
  and `! grep -q` on its own line in a bats `@test` **cannot fail**. →
  mitigation: every one uses `run grep -nE …` + `[ "$status" -ne 0 ] || { …;
  false; }`, and each is verified by temporarily reintroducing what it forbids
  and watching it go red. Budget one minute per negative assertion for this.
- **`review.lib.sh` roughly doubles** (1,206 lines today). → mitigation: the
  two REFACTOR extractions (steps 28, 39) land mid-stream, not at the end;
  `lib-zsh-safety.bats` and the portability guard pick new libs up by glob, and
  each new lib self-locates with `${BASH_SOURCE[0]:-$0}`.
- **Race-shaped ACs (14c, 17d).** "Sweep in a loop against a creator in a loop"
  and "two concurrent subagents" are the shapes this repo has previously made
  pass by luck. → mitigation: a fault-injection pause seam in
  `review_round_dir_create` (env-settable) for 14c, and recorded activity
  intervals in the round dir for 17d. Never sleep-and-hope.
- **The Codex plugin is absent from this devcontainer.** Step 1's
  re-verification and ACs 26/26a cannot be done here. → mitigation: step 1 runs
  on a host that has it (or against a vendored 1.0.6 tree) and the checked-in
  fixtures (AC5a, AC9) then make any drift a test failure, which is exactly why
  the spec asked for them.
- **`Agent` and `TaskStop` tool names are asserted by the spec but unverified
  by this plan.** A wrong name makes AC20 pass a grep and fail in the field. →
  mitigation: confirm both against the live tool surface at step 41, before
  writing them into four `allowed-tools` lists.
- **The shared-runbook location is a plan decision, not a spec decision**
  (every `.md` under `commands/` registers as a slash command). → mitigation:
  ratify `skills/review-round/SKILL.md` before step 40; eleven grep assertions
  hardcode that path.
- **The 0052 suite is the regression floor and must pass unedited.** Five new
  helpers extend 0052 surfaces (`review_compose_payload`,
  `review_validate_reference_access`, `review_finalize_round`,
  `_review_parse_reference_access`, `review_budget_check`'s caller). →
  mitigation: every extension is an **optional, defaulted** parameter or a new
  mode arm, and step 71 asserts `git diff --stat` shows no edit to
  `spec-review-payload.bats`.
- **Override budget: 0 expected.** Shell and markdown are ungated
  (conventions §Bash); the only Go work edits an existing function in a package
  that already has sibling tests, so step 2's RED is a runtime failure, not a
  build error. If step 3's struct-field addition does trip the build probe it
  costs build-repair admissions, not an override — budget 2 of 10.
