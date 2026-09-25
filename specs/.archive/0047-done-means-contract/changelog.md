---
spec: "0047"
closed: 2026-08-07
---

# Changelog — 0047 Per-task done-means contract and completion gate

## What shipped vs spec

- **`speccraft-state tasks-verify <tasks.md> [--run|--help]`** — a read-only
  oracle over tasks.md, added as a `case` on the existing `run()` seam. Exit `0`
  clean / `1` violations / `2` malformed; findings emitted one per line as escaped
  TSV `task-id`, `kind`, `detail`.
- **Grammar** as specified, recognition syntactic and parent resolution second:
  multi-digit suffixes (`T1.10`), `**bold**` task text, extra frontmatter keys,
  one level of sub-checkbox, and any non-matching indented bullet treated as prose
  at any depth.
- **AC1 (parent/child) fires on every tasks.md**, contract key or not. **AC2**
  (`done:` present, non-empty, exactly one, every task regardless of tick state)
  fires only under `contract: done-means-v1`. Empty/duplicate `done:`, a bare
  `done: $` with no command, an orphan sub-checkbox, a duplicate task id and
  missing frontmatter are all exit 2.
- **Predicate runner** (`tasks_predicate.go`, `//go:build unix`): `/bin/sh -c`,
  CWD = repo root via `FindRoot`, inherited env, stdin `/dev/null`, combined
  capture capped at 4 KiB with `…[truncated]`, `SPECCRAFT_TASKS_VERIFY_TIMEOUT`
  (default 30s; unset/empty/invalid/zero/negative → default), and a
  **process-group** kill proven by a predicate whose forked child outlives its
  `sh` parent holding the output pipe. Non-unix half (`tasks_predicate_other.go`)
  fails loud rather than silently reporting clean.
- **Close gate**: `commands/spec/close.md` step 2 runs `tasks-verify --run` before
  the diff (step 3) and before `memory-keeper` (step 4).
- **Producers**: `agents/tdd-planner.md` emits the contract by default (eight
  rules, incl. the knob-must-prove-its-**reader** predicate shape, the
  no-self-recursion rule, and the bare-`$` rule); `skills/spec-format/SKILL.md`
  documents the grammar and the previously undocumented `domains:` key;
  `docs/commands.md` documents the gate and the bypass token.
- **Tests**: `tests/hooks/tasks-verify.bats` (5) pins AC3 across all 44 live and
  archived `tasks.md`; `tests/hooks/close-gate.bats` (7) pins the AC9/AC10 gate
  contract durably; 27 Go tests in the cmd package.
- Verification: `go test ./...` + `go vet` green, **294 bats** green, drift clean,
  `GOOS=windows go build ./...` green, and `tasks-verify --run` exits 0 against
  this spec's own tasks.md — the gate passes on itself.

## Deviations

1. **Override budget: stated 0, actual 5.** AC11's *design* constraint held —
   `tools/internal/speccraft/` is byte-unchanged and the subcommand rides `run()`
   — but the *budget prediction* did not. A forward reference to `runPredicates`
   broke the build, and the guard's red-check then refused every Edit and Write
   **including the repair**; 5 overrides were spent unwedging (seam file →
   implementation → missing `os` import → invented `envOrEmpty` → rename). Root
   cause was mine; the absent "this edit repairs the build" affordance is a real
   speccraft defect, filed as a follow-up. See plan.md C2 and tasks.md §Bypasses.

2. **T4/T6/T8 are pins, not REDs** (plan C4). Unwedging (1) forced the `done:`
   parser and the whole predicate runner to land ahead of their tests, which then
   passed on first run. The tasks are retitled `PIN (not RED)` so the archived
   tasks.md does not misrepresent them. Genuine REDs: the structural layer
   (`tasks_verify_cmd_test.go`), the two C3 column-0 tests, and all five T15
   close-pass tests.

3. **C3 — column-0 task ids may be dotted, and multi-dot.** §Grammar assumed a
   dotted id implied a sub-checkbox; `specs/.archive/0001-speccraft-v1/tasks.md`
   uses `T0.1`/`T0.5.1` at column 0 and failed the first archive sweep (1 of 44).
   Only **indentation** makes a sub-checkbox. The spec's own audit missed this
   because it examined indented checkboxes only.

4. **C1 — `parseFrontmatterBlock` is unexported.** AC12 is satisfied through the
   exported `speccraft.ReadFrontmatterField`, which routes through it. A
   fence-only detector (`hasFrontmatterFence`) was added in the cmd package
   because `ReadFrontmatterField` cannot distinguish "no block" from "key absent".
   The `strings.Count("func parseFrontmatterBlock(") == 1` invariant still holds,
   but it scans `internal/` only and therefore cannot see this second fence
   reader — latent drift, not a current violation.

5. **C5 — predicate recursion.** T14's predicate runs the structural check on its
   own file; `--run` there would recurse unboundedly. Now also encoded as rule 7
   in `tdd-planner.md`.

## Found by memory-keeper's adversarial close pass, fixed before closing

The close-time verification of the summary against the diff caught six real
defects. All were fixed in T15 rather than shipped; each is now a test.

1. **AC9/AC10 had no durable coverage.** The bypass protocol existed only as
   close.md prose, and the sole check was a `grep` in this spec's own `done:`
   predicate — which runs once, at this close, and never again (the archive sweep
   runs without `--run`). Deleting `SKIP-TASKS-VERIFY` tomorrow would have broken
   nothing. → `tests/hooks/close-gate.bats`, 7 assertions on the contract
   (invocation, gate-before-diff ordering, the token, the blanket-approval
   carve-out, exit-2-unbypassable, the changelog record).
2. **A bare `done: $` was silently waived.** Non-empty to the parser, so not
   malformed, but `predicateCommand` reclassified it as *prose* — a ticked task
   that looked executable, never run, never reported. **This spec's own failure
   mode, reproduced inside its own tool.** → now exit 2, with a test.
3. **`GOOS=windows go build ./...` was broken.** `tasks_predicate.go` shipped
   `//go:build unix` with no counterpart, though plan.md §Risk promised to mirror
   `ledger_flock_unix.go`/`ledger_flock_other.go` "exactly". → counterpart
   shipped, pinned by `Test_StateCmd_CrossCompilesForNonUnix_GOOSWindows`.
4. **AC7's escaping was unpinned.** The original test never placed a tab in an
   emitted field, because no finding `detail` carries the task description. →
   re-driven through predicate *output*, which does reach `detail`.
5. **`tasks-verify --help` never printed the AC14 boundary text** (it was treated
   as a filename), and an extra positional argument was silently ignored, so a
   typo'd invocation reported clean. → both fixed; usage is now a single shared
   `tasksVerifyUsage` so the boundary cannot drift between paths.
6. **`spec-format`'s worked example was itself an AC1 violation** — a `[x] T2`
   over a `[ ] T2.c`, three lines above the text explaining that the tool rejects
   exactly that. → corrected, with the reason called out.

Also corrected: the test header cited plan correction C2 where it meant C4.

## Known limitations (not fixed, deliberate)

- `malformedErr` discriminates nothing today — `tasksVerify` checks `err != nil`
  and `parseTasksFile` returns no other error kind. Harmless, but it is a
  declaration whose stated purpose has no reader.
- A prose `done:` line still carries no teeth at close time. That is the §Boundary
  contract, stated in the tool's own help text, not an oversight.

## Files touched

- `tools/cmd/speccraft-state/main.go` (`case "tasks-verify":`, arg parsing)
- `tools/cmd/speccraft-state/tasks_verify.go` (new)
- `tools/cmd/speccraft-state/tasks_predicate.go` (new, `//go:build unix`)
- `tools/cmd/speccraft-state/tasks_predicate_other.go` (new, `//go:build !unix`)
- `tools/cmd/speccraft-state/tasks_verify_cmd_test.go` (new)
- `tools/cmd/speccraft-state/tasks_verify_done_test.go` (new, `//go:build unix`)
- `tests/hooks/tasks-verify.bats` (new)
- `tests/hooks/close-gate.bats` (new)
- `commands/spec/close.md`, `agents/tdd-planner.md`,
  `skills/spec-format/SKILL.md`, `docs/commands.md`
- `.speccraft/index.md` (active-spec pointer)
- `specs/0047-done-means-contract/{spec,plan,tasks,review,changelog}.md` (new)

## Overrides used (guardrails.md record)

5 × `/speccraft:spec:override`, all 2026-08-06, all spent recovering from one
self-inflicted build break (forward reference to `runPredicates`) that the guard's
red-check then made unrepairable: (1) seam file, (2) full implementation,
(3) missing `os` import, (4) `envOrEmpty` → `os.Getenv`, (5) `execPredicates` →
`runPredicates` rename. Stated budget 0; actual 5.

## No release

Ships unbumped at 1.16.0, in the 0037–0040 style (bundle into a later release
spec). A user-visible subcommand and a changed close gate are therefore
implemented but unreleased.

## Follow-ups filed

- **aux-delegator temp-file collision → false quorum** (highest priority). Round 1
  of this spec's review returned byte-identical output from both reviewers: both
  `aux-delegator` invocations wrote `/tmp/0047-review-output.txt`, so the second
  reported the first's bytes as its own verdict. Caught by md5-comparing the two
  bodies; claude-p was re-run with an isolated path and the recorded verdicts are
  from that corrected run. Needs per-agent output namespacing plus a caller-side
  identical-output detector. Cross-model review is the plugin's headline feature
  and a false quorum is its worst failure mode.
- **Guard has no "this edit repairs the build" affordance** — a broken build makes
  the red-check forbid the very edit that fixes it (deviation 1).
- **Guard's `red_candidates` are clobbered by a subsequent edit** that adds no test
  function: an import-only edit reset the file's registered candidates to `[]`,
  blocking a legitimately-RED production edit until a test function was renamed so
  its `func` line counted as added.
- **Mechanical definition-without-reader check** (the deliberately removed prose
  backstop).
- Plan corrections as a first-class artifact; `index.md` per-entry byte cap;
  consolidation routing seed + skip marker; review-round stopping rule.
