---
spec: "0047"
status: planned
strategy: tdd
---

# Plan — 0047 Per-task done-means contract and completion gate

## Ground truth established before planning

- **`run()` seam exists** at `tools/cmd/speccraft-state/main.go:20` with a flat
  `switch` over subcommands. Adding `tasks-verify` as a case, driven by
  `runCmd(t, root, "tasks-verify", …)` REDs, costs **override budget 0** (AC11).
- **An unknown subcommand already returns non-zero with empty stdout** — that is
  the RED state for T1, not a build failure.
- **A second tasks.md parser already exists**: `speccraft.TasksDonePct`
  ([state.go:400](tools/internal/speccraft/state.go#L400)) counts only column-0
  `- [` lines. Under the new grammar it therefore counts parents and ignores
  indented sub-checkboxes — correct by construction, but **not by intent**. T9
  pins that with a non-regression test rather than leaving it to luck. It is
  deliberately *not* refactored to share the new parser: that would mean an
  exported `internal/` symbol and would break AC11's zero-override budget.
- **Legacy corpus audited** (43 files): `specs/.archive/0016-…/tasks.md` carries
  `T1.1`–`T1.10` sub-checkboxes, a deeper `- [x] #1 …` prose level, `**bold**`
  task text, and both `id:` and `spec:` frontmatter keys; its `T5` is an unticked
  parent with unticked children. No `[x]`-parent/`[ ]`-child pair exists anywhere.
  This file is the single most valuable fixture in the repo for this spec and is
  used directly in T2 and T10.

## Test-first sequence

### Step 1 — RED: `tasks-verify` does not exist
- Add `tools/cmd/speccraft-state/tasks_verify_cmd_test.go`:
  - `Test_StateCmd_TasksVerify_CleanFile_ExitZero` — a minimal well-formed
    non-contract tasks.md exits 0 with empty stdout.
  - `Test_StateCmd_TasksVerify_MissingFile_ExitTwo` — absent path is malformed.
- Tests fail: `run()` has no `tasks-verify` case, so it returns non-zero with
  nothing on stdout. This is a genuine behavioral RED on the seam, not a compile
  error (per the spec-0018 "build failure is not RED" convention).

### Step 2 — RED: the parser contract, driven by the real archive
- Extend the same test file:
  - `Test_StateCmd_TasksVerify_ParentChild_TickedParentUntickedChild` — the AC1
    violation; asserts exit 1 and a finding naming the parent.
  - `Test_StateCmd_TasksVerify_ParentChild_HoldsWithoutContractKey` — AC1 fires on
    non-contract files too.
  - `Test_StateCmd_TasksVerify_Grammar_MultiDigitSuffix` — `T1.10` is a
    sub-checkbox (the alpha-only rule both reviewers proposed would fail here).
  - `Test_StateCmd_TasksVerify_Grammar_DeepBulletIsProse` — `- [x] #1 …` at depth
    2 is prose, not a malformed sub-checkbox.
  - `Test_StateCmd_TasksVerify_Grammar_BoldTaskText` / `_ExtraFrontmatterKeys` —
    spec 0016's shapes parse.
  - `Test_StateCmd_TasksVerify_Malformed_OrphanSubCheckbox` — a syntactically
    valid `T9.a` with no `T9` parent is exit 2 (**not** prose — this is the
    recognition/resolution split that resolved the round-2 contradiction).
  - `Test_StateCmd_TasksVerify_Malformed_DuplicateTaskID`,
    `_MissingFrontmatter`.
- Tests fail: no parser.

### Step 3 — GREEN: parser + structural checks
- Add `tools/cmd/speccraft-state/tasks_verify.go`: `parseTasksFile` (unexported,
  cmd package) implementing §Grammar exactly — syntactic recognition first, parent
  resolution second — plus the AC1 parent/child check. Frontmatter reading routes
  through the existing `parseFrontmatterBlock` (AC12); **no new frontmatter
  reader**.
- Wire `case "tasks-verify":` into `run()`.
- Steps 1–2 pass.

### Step 4 — RED: `done:` presence and shape under the contract
- `Test_StateCmd_TasksVerify_Contract_MissingDoneIsViolation` (AC2, any tick
  state), `_NoContractKey_MissingDoneIsNotReported`,
  `_EmptyDoneIsMalformed`, `_DuplicateDoneIsMalformed`,
  `_DoneBlockEndsAtNextTask` (block-boundary pin),
  `_DoneIndentIsTwoSpaces`.
- Tests fail: `done:` is not parsed.

### Step 5 — GREEN: `done:` parsing + AC2/AC8 classification
- Extend `parseTasksFile` and the checker. Steps 1–4 pass.

### Step 6 — RED: exit-code taxonomy and finding encoding
- `Test_StateCmd_TasksVerify_ExitCodes_ZeroOneTwo` — the three codes are distinct
  and a malformed file never reports as clean.
- `Test_StateCmd_TasksVerify_Findings_TSVEscaping` — a task description containing
  a literal tab and a newline round-trips as `\t`/`\n` without breaking field
  boundaries (AC7).
- Tests fail: encoding not implemented.

### Step 7 — GREEN: encoder + exit codes
- Emit `task-id\tkind\tdetail` with escaping and the 4 KiB `detail` cap. Steps 1–6
  pass.

### Step 8 — RED: predicate execution
- `Test_StateCmd_TasksVerify_Run_PredicatePasses` / `_PredicateFails` (AC4).
- `Test_StateCmd_TasksVerify_NoRun_DoesNotExecute` — a predicate that would fail
  is not reported without `--run` (AC4); assert via a predicate that writes a
  sentinel file, then assert the file is absent.
- `Test_StateCmd_TasksVerify_Run_SkipsUntickedTasks` (AC5).
- `Test_StateCmd_TasksVerify_Run_CWDIsRepoRoot` — predicate run from a subdir
  still sees the root.
- `Test_StateCmd_TasksVerify_Run_CapturesOutputIntoDetail` + `_TruncatesAt4KiB`.
- `Test_StateCmd_TasksVerify_Timeout_Matrix` — unset/empty/invalid/zero/negative
  → 30s; a valid value wins (mirrors `ledger_locktimeout_test.go`).
- `Test_StateCmd_TasksVerify_Timeout_KillsProcessGroup` — **the load-bearing one**:
  a predicate that forks a child which outlives its `sh` parent while holding the
  output pipe. Killing only the leader hangs forever; the test asserts the verifier
  returns within a short bounded timeout. Uses a small explicit timeout via the env
  var, no wall-clock sleeps in the assertion path.
- Tests fail: `--run` not implemented.

### Step 9 — GREEN: predicate runner
- `/bin/sh -c`, `Setpgid`, kill the negative pgid on timeout, combined capture,
  repo-root CWD, inherited env, stdin `/dev/null`. Timeout parsing follows the
  `parseLockTimeout` shape from spec 0045. Steps 1–8 pass.

### Step 10 — RED→GREEN: the archive fixture (AC3)
- Add `tests/hooks/tasks-verify.bats` asserting exit 0 over **every**
  `specs/**/tasks.md` and `specs/.archive/**/tasks.md`, with 0016 named explicitly
  so a future parser regression on multi-digit suffixes / deep prose bullets fails
  loudly rather than silently.

### Step 11 — RED: `tasks-done-pct` non-regression (AC-adjacent, see Ground truth)
- `Test_StateCmd_TasksDonePct_IgnoresSubCheckboxes` — a contract file with
  sub-checkboxes yields parent-level percentage, unchanged by indented children.
- Expected to pass on first run against existing code; it is a **pin**, not a
  behavior change. Recorded as such rather than dressed up as a RED.

### Step 12 — GREEN: wire the close gate
- Rewrite `commands/spec/close.md` step 2 to invoke `tasks-verify --run`, with the
  AC10 bypass protocol: literal `SKIP-TASKS-VERIFY`, exit 2 never bypassable,
  deterministic `## Skipped task verification` section appended to `changelog.md`.
- Gate sits before step 3 (diff) and step 4 (memory-keeper).

### Step 13 — GREEN: producers
- `agents/tdd-planner.md`: emit `contract: done-means-v1`, sub-checkboxes, `done:`
  lines, prefer executable predicates.
- `skills/spec-format/SKILL.md`: document the grammar with the worked example, and
  add the previously-undocumented `domains:` frontmatter key.

### Step 14 — Verification
- `go test ./tools/...`, `go vet`, full bats suite, `speccraft-drift`,
  `tasks-verify --run` against this spec's own `tasks.md`.

## Corrections

Recorded as implementation contradicts the plan. A plan is a hypothesis; this
section is where it gets falsified. (There is no first-class affordance for this
in speccraft today — that gap is itself a triaged follow-up.)

### C1 — `parseFrontmatterBlock` is unexported (Step 3 / T3.b)
- **Predicted**: `tasks_verify.go` calls `parseFrontmatterBlock` directly to read
  the `contract:` key, per AC12.
- **Observed**: `parseFrontmatterBlock` lives in `tools/internal/speccraft/` and is
  **unexported**, so the cmd package cannot reach it. Exporting it would add an
  exported `internal/` symbol and break AC11's zero-override budget.
- **Action**: call the already-exported `speccraft.ReadFrontmatterField(path, key)`
  ([workspace_topology.go:171](tools/internal/speccraft/workspace_topology.go#L171)),
  which itself routes through `parseFrontmatterBlock` — pinned by the existing
  `Test_ReadFrontmatterField_RoutesThroughSharedGrammar`. AC12's one-grammar
  intent is satisfied exactly; AC11 is untouched. No new symbol, no override.

### C2 — the TDD guard wedged, and it cost 5 overrides against a budget of 0
- **Predicted**: AC11, override budget **0**, via the `run()` seam.
- **Observed**: I wrote `tasks_verify.go` with a forward reference to a
  `runPredicates` symbol that did not exist yet. The build broke — and the guard's
  red-check then refused **every** subsequent Edit and Write, including the one
  that would have fixed the build. The only sanctioned escape is
  `/speccraft:spec:override`. Recovering (seam file → real implementation →
  missing import → invented `envOrEmpty` → rename) took **5 overrides**.
- **Action**: recorded, not hidden. Budget 0 → **actual 5**. The seam design of
  AC11 was never violated (no exported `internal/` symbol was added, and the
  subcommand does ride `run()`); every override was spent unwedging a
  self-inflicted build break.
- **Root cause is mine** (a forward reference), but the wedge is a real speccraft
  defect: the guard has no "this edit repairs the build" affordance, so one bad
  prod edit can make the guard demand a fix it simultaneously forbids. **Filed as
  a follow-up.**

### C3 — column-0 task ids may be dotted, and multi-dot (T2/T10)
- **Predicted**: §Grammar's "a sub-checkbox at column 0 is malformed", on the
  assumption that a dotted id implies a sub-checkbox.
- **Observed**: `specs/.archive/0001-speccraft-v1/tasks.md` uses `T0.1`, `T0.4`
  and `T0.5.1` **at column 0**. The first archive sweep failed on it — 1 of 44
  files. The spec's own audit had only checked *indented* checkboxes, so it
  missed this.
- **Action**: only **indentation** makes a sub-checkbox. A column-0 id may contain
  dots at any depth; an indented checkbox is a sub-checkbox iff its id is the
  enclosing task's id plus exactly one more segment. Verified across the corpus
  that every indented dotted id already matches its parent, so codex's round-2
  "unresolvable parent ⇒ exit 2" finding survives intact. Pinned by
  `Test_..._DottedTaskIDAtColumnZero` (a genuine RED) and by the bats fixture.

### C4 — the T4/T6/T8 tests are pins, not REDs
- **Predicted**: steps 4/6/8 are REDs preceding their GREENs.
- **Observed**: unwedging C2 forced the `done:` parser and the entire predicate
  runner to land **before** their tests. Those tests were written against
  existing code and passed on first run.
- **Action**: labelled as pins in the test file header rather than presented as
  REDs. The structural layer (`tasks_verify_cmd_test.go`) and the C3 fix were
  genuine REDs; T4/T6/T8 were not, and the changelog says so.

### C5 — a `done:` predicate can recurse
- **Predicted**: T14's predicate would run `tasks-verify --run` on its own file.
- **Observed**: that is unbounded self-recursion — the gate re-invoking itself,
  each level re-running every predicate, bounded only by the 30s timeout.
- **Action**: T14's predicate runs the **structural** check (no `--run`) on its
  own file. Worth a note in the planner guidance: a predicate must not invoke the
  verifier that runs it.

## Delegation

- None. Every step is small, local to one package, and the seam work needs the
  full spec context; a hand-off would cost more than it saves.

## Risk

- **Process-group kill is platform-sensitive** (`Setpgid` is unix-only, matching
  the existing `ledger_flock_unix.go` / `ledger_flock_other.go` build-tag split).
  → Mitigation: follow that precedent exactly; the shipped platforms are linux and
  macOS.
- **`/bin/sh` differs across platforms** → the spec constrains predicates to POSIX
  and says so in the tool's help; the repo's own predicates use only `grep`/`test`
  and `&&`.
- **A predicate could hang CI if the default timeout is too generous** → 30s
  default, and every predicate this repo writes is a grep or a scoped test.
- **AC3 could break on a future legacy file** → the bats fixture is the oracle and
  runs on every CI run, so a regression surfaces immediately.
