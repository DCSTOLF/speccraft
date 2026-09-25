---
id: "0047"
title: "Per-task done-means contract and completion gate"
status: closed
created: 2026-08-06
authors: [claude]
packages: ["tools/cmd/speccraft-state", "commands/spec", "agents", "skills/spec-format", "tests/hooks"]
related-specs: ["0035", "0036", "0045"]
domains: [spec-lifecycle]
---

# Spec 0047 — Per-task done-means contract and completion gate

## Why

Field feedback from an agent that ran a full speccraft lifecycle under load: every
one of its four real misses was **a multi-part task ticked when its most visible
part was finished**.

- One task was "declare the error + add the ceiling + add the task field + thread
  the knob through the discovery seam" — four sub-items, one checkbox. Three were
  done, the box was ticked, and a config knob shipped **unwired** (declared, never
  read).
- Two other tasks were "implement the seam + write six live tests" as one
  checkbox; both were ticked with the code written and zero tests.

The cross-model review loop — speccraft's strongest feature — cannot catch this
class. Review finds *design* errors; it does not find *"you marked it done and it
wasn't."* Nothing else in the lifecycle looks at task completion either:
`/speccraft:spec:close` step 2 only asks whether every top-level box is `[x]`,
which is exactly the assertion that was false.

The deeper pattern: speccraft's durable wins are all **mechanical** (the TDD
PreToolUse gate, `set-status` refusing closed specs, the `state.json` write ban).
Its failures are all in the **instruction layer** — markdown a model is merely
asked to follow. `tasks.md` today has no sub-structure and no per-task definition
of done: `skills/spec-format/SKILL.md` codifies the line format as
`- [x] TN — <description>`, and `agents/tdd-planner.md` emits exactly one flat
checkbox per plan step. A task's completion criterion lives only in the planner's
head at plan time and nowhere at implement time.

This spec moves that check down a layer. Everything it adds is mechanical; it
deliberately adds **no** new prose instruction that a model is merely asked to
obey (see §Design note on the removed backstop).

## What

Give `tasks.md` a **decomposition contract** and enforce the mechanically
checkable part of it at close time.

1. **Grammar** — sub-checkboxes and a per-task `done:` line. Pinned in §Grammar.
2. **Opt-in marker** — `contract: done-means-v1` in `tasks.md` frontmatter. Files
   carrying it are held to the full contract; files without it (every spec through
   0046, and the archive) are held only to the checks that are unambiguous for
   legacy shapes. No date logic, no migration of existing specs. The `-v1` suffix
   is deliberate: grammar evolution gets a new value rather than silently
   redefining an existing one.
3. **Oracle** — a read-only op `speccraft-state tasks-verify <tasks.md>` that
   parses the file and reports violations. `--run` additionally executes
   `$`-prefixed predicates.
4. **Gate** — `/speccraft:spec:close` runs `tasks-verify --run` **in place of**
   its current step-2 eyeball check, i.e. before the diff and before
   `memory-keeper`, so a doomed close costs nothing.
5. **Producers** — `tdd-planner` emits the new shape and `spec-format` documents
   it, so new plans are born decomposed.

### Grammar

```markdown
---
spec: "0047"
contract: done-means-v1
---

# Tasks

- [x] T1 — RED: parent/child consistency violations are detected
  done: $ go test ./tools/... -run Test_TasksVerify_ParentChild
- [x] T2 — GREEN: tasks-verify parses and reports
  - [x] T2.a — parser: frontmatter, tasks, sub-checkboxes, done: lines
  - [x] T2.b — parent/child + done-presence checks
  - [x] T2.c — wired as a `run()` case in speccraft-state
  done: $ speccraft-state tasks-verify specs/0047-done-means-contract/tasks.md
- [ ] T3 — thread the timeout knob end to end
  - [ ] T3.a — declare SPECCRAFT_TASKS_VERIFY_TIMEOUT + its parser
  - [ ] T3.b — read it at the predicate call site
  done: $ grep -q SPECCRAFT_TASKS_VERIFY_TIMEOUT tools/cmd/speccraft-state/tasks_verify.go && grep -rq 'tasksVerifyTimeout(' tools/cmd/speccraft-state/
- [x] T4 — document the grammar for humans
  done: spec-format SKILL.md shows the worked example
```

Rules — recognition is **syntactic**, and resolution happens afterward. This split
matters: it is what keeps "unmatched parent" (an error) distinct from "an indented
bullet that was never a sub-checkbox" (prose).

- A **task line** is `- [ ]` / `- [x]` at column 0, followed by `T<digits>`, then
  ` — <text>`. Surrounding `**bold**` on the text is tolerated (spec 0016 uses it).
- A **sub-checkbox** is recognized *syntactically*: an indented `- [ ]` / `- [x]`
  followed by `T<digits>.<suffix>` where `<suffix>` matches `[A-Za-z0-9]+`. Both
  `T2.a` and `T1.10` are legal — spec 0016 already uses multi-digit numeric
  suffixes in the wild, so an alpha-only suffix rule would break AC3.
- Resolution runs after recognition: a syntactically valid sub-checkbox whose
  `T<digits>` prefix names no enclosing task is **malformed** (exit 2), not prose.
- An indented bullet that does **not** match the sub-checkbox shape is **prose and
  is ignored**, at any indent depth. Spec 0016's second-level `- [x] #1 …` bullets
  are the live example; this rule is what keeps the archive clean (AC3).
- **Nesting is out of scope.** Only one level of sub-checkbox is recognized;
  anything deeper is prose per the rule above.
- A **`done:` line** is `done:` indented exactly **2 spaces** from column 0,
  belonging to the nearest preceding task line. Its block runs to the next
  column-0 task line, the next markdown heading, or EOF. Each task must carry
  **exactly one** `done:` line with a **non-empty** value — zero is an AC2
  violation under the contract, and duplicate or empty `done:` lines are malformed
  (exit 2). It may appear with or without sub-checkboxes and applies to the parent
  task only; sub-checkboxes carry no `done:` of their own.
- A `done:` value beginning with `$` is an **executable predicate**; the remainder
  (after stripping the `$` and surrounding whitespace) is the command. Any other
  value is prose.
- T3 above is the field report's unwired-knob case expressed mechanically: the
  predicate fails until the knob has both a declaration *and* a reader. This
  example is load-bearing — it is the whole substitute for the removed backstop —
  so the plan carries it (or an equivalent two-site predicate) as a real fixture.

The frontmatter parser must tolerate keys beyond `spec:` and `contract:`; spec
0016's `tasks.md` carries both `id:` and `spec:`.

### Predicate execution

Mirrors the spec-0045 `SPECCRAFT_LEDGER_LOCK_TIMEOUT` / `parseLockTimeout`
precedent:

- **Shell**: `/bin/sh -c <command>`, invoked by absolute path. POSIX shell, not
  bash. `/bin/sh` is dash on some platforms and bash-in-POSIX-mode on others, so a
  predicate relying on a bashism can pass locally and fail in CI; §Boundary puts
  predicate authors on notice.
- **CWD**: the repo root, as resolved by the same logic backing
  `speccraft-state find-root` — never the tasks.md directory and never the
  caller's CWD, so a predicate behaves identically whether close is invoked from
  the root or a subdirectory.
- **Environment**: inherited unmodified from the `speccraft-state` process.
- **Streams**: stdin `/dev/null`; stdout and stderr captured (not echoed live),
  combined, and truncated to **4 KiB** with a literal `…[truncated]` marker before
  landing in the failing finding's `detail` field.
- **Timeout**: `SPECCRAFT_TASKS_VERIFY_TIMEOUT`, a Go duration, default `30s`.
  Unset, empty, invalid, zero, or negative all fall back to the default.
- **Termination**: the predicate runs in its own process group, and the timeout
  kills the **whole group**, not just the `sh` leader. Killing only the leader
  leaves grandchildren holding the captured output pipes open, which would hang
  the verifier on exactly the runaway predicate the timeout exists to bound.

### Design note — why there is no memory-keeper backstop

An earlier draft added a prose instruction to `memory-keeper` ("for each new
identifier in the diff, name its reader"). Both reviewers independently flagged
that this re-introduces the exact instruction-layer mechanism §Why identifies as
speccraft's chronic weakness — the spec would have argued against prose-you-hope-
the-model-follows and then added some. It is removed. The unwired-knob class is
covered mechanically by the T3-shaped executable predicate above. A *mechanical*
definition-without-reader check is worth building and is deferred to its own spec.

### Boundary — what "verify" honestly means

`tasks-verify` checks **structure always, and executable truth where a predicate
is offered**. It cannot evaluate prose. A prose `done:` line forces articulation
at plan time (its real value: the planner must decompose before it can write one)
but carries no teeth at close time. This limit is stated in the tool's own help
text so the gate is not mistaken for stronger than it is.

Separately: `tasks-verify`'s **own logic** is read-only, but a predicate is
arbitrary shell and may have side effects (`$ npm test` can write caches). The
tool makes no claim about what predicates do. Predicates run at the developer's
own trust level with their full ambient environment — the same trust speccraft
already extends to the detected test command — and under `/bin/sh`, so a bashism
that works locally may not work elsewhere.

## Acceptance criteria

1. **Parent/child consistency is always enforced.** `tasks-verify` reports a
   violation naming the offending task when any `[x]` parent has a `[ ]`
   sub-checkbox — for files with *and* without `contract: done-means-v1`. This is
   the check that would have caught all three of the field report's premature
   ticks.

2. **`done:` presence is enforced only under the contract, for every task.** For a
   file with `contract: done-means-v1`, **any** task lacking a `done:` line is a
   violation regardless of tick state, so an omission surfaces at plan time rather
   than after completion. An empty or duplicated `done:` is malformed (AC8), not a
   satisfied one. For a file without the contract key, a missing `done:` is not a
   violation and is not reported as one.

3. **Legacy files stay clean.** A `tests/hooks/tasks-verify.bats` fixture asserts
   exit 0 for every existing `specs/**/tasks.md` and `specs/.archive/**/tasks.md`.
   The corpus was audited while writing this spec and already contains the two
   shapes that could break the parser, so the fixture is a real test rather than a
   vacuous one:
   - `specs/.archive/0016-.../tasks.md` uses `T1.1`–`T1.10` sub-checkboxes
     (multi-digit numeric suffixes) **and** a deeper `- [x] #1 …` level, which
     §Grammar classifies as prose;
   - the same file's `T5` is an unticked parent with unticked children, and four
     other archived files carry unticked tasks — none is an `[x]`-parent /
     `[ ]`-child pair, so AC1 does not fire on the archive.

   If a future audit surfaces a genuine `[x]`/`[ ]` legacy pair, the escape is to
   grandfather that exact file — not to weaken AC1.

4. **Executable predicates are executed under `--run`.** For a task whose `done:`
   value begins with `$`, `--run` executes the remainder per §Predicate execution;
   a non-zero exit is a violation naming the task, the command, and captured
   output. Without `--run`, no predicate is executed and a false predicate is not
   reported.

5. **Unticked tasks are not executed.** `--run` skips predicates for `[ ]` tasks —
   a plan whose later steps legitimately fail today must not fail verification.
   (Their `done:` lines are still presence-checked per AC2.)

6. **Predicates are bounded.** A predicate that does not terminate is killed at
   `SPECCRAFT_TASKS_VERIFY_TIMEOUT` and reported as a violation rather than
   hanging the close. Unset, empty, invalid, zero, and negative values each fall
   back to the documented `30s` default; a valid value wins. The kill targets the
   predicate's whole process group, proven by a predicate that forks a child which
   outlives its `sh` parent while holding the output pipe — the case where killing
   only the leader hangs the verifier forever.

7. **Findings are structured and delimiter-safe.** Violations are emitted one per
   line as tab-separated `task-id`, `kind`, `detail`. Any tab, newline, or
   carriage return inside a field is escaped (`\t`, `\n`, `\r`) so field
   boundaries survive a task description or captured predicate output containing
   them, and `detail` is capped at 4 KiB with a visible truncation marker.

8. **Malformed input fails loud, with a distinct exit code.** Exit codes are `0`
   clean, `1` violations found, `2` malformed input. Malformed means: missing
   frontmatter; a syntactically valid sub-checkbox whose `T<digits>` prefix names
   no enclosing task; duplicate task ids; an empty `done:` value; or two `done:`
   lines in one task block. A malformed file is never silently treated as clean.
   The distinction matters to the runbook: `2` is a bug to hand-fix, `1` is a
   decision.

9. **The close gate is wired at step 2.** `/speccraft:spec:close` invokes
   `tasks-verify --run` as its step-2 completion check — before the diff (step 3)
   and before `memory-keeper` (step 4), so a blocked close performs no downstream
   work. A clean run proceeds silently.

10. **Blanket approval does not silently bypass the gate.** close.md step 2 today
    reads: *"If the user's message contains 'approve all' or the spec was created
    in a non-interactive context, proceed with closure regardless."* That path
    does **not** satisfy the new gate — it is exactly the mode the field agent ran
    in, and leaving it would defeat the gate on arrival. Specifically:
    - bypass requires the literal token `SKIP-TASKS-VERIFY`, distinct from
      `approve all` and from any other blanket-approval phrasing;
    - exit `2` (malformed) is **never** bypassable — a file the parser cannot read
      is a bug to fix, not a decision to wave through;
    - a bypass writes a `## Skipped task verification` section into the spec's
      `changelog.md` listing every skipped finding verbatim. The record is written
      deterministically by the runbook, not left to `memory-keeper` prose.

11. **Bootstrap costs override budget 0.** `tasks-verify` is added as a case on the
    existing `run()` seam in `tools/cmd/speccraft-state/` and driven test-first via
    `run([]string{"tasks-verify", …})` REDs. No exported symbol is added to
    `tools/internal/speccraft/`. Budget: **0 overrides**. Consequence, accepted
    deliberately: the out-of-scope implement-time gate would want these same
    shell-out and timeout helpers and will have to re-pay an override to promote
    them to `internal/`. Premature reuse is not worth an override now.

12. **One frontmatter parser.** Reading the new `contract:` key routes through the
    existing shared `parseFrontmatterBlock` (spec 0036), not a second reader
    accreted inside `tasks-verify`. The source-scan invariant that pins this —
    the `strings.Count` assertion over `func parseFrontmatterBlock(` — still
    counts exactly one definition after this spec; adding a caller does not move
    it.

13. **Producers emit the contract.** `tdd-planner`'s output template and the
    `spec-format` skill both specify the sub-checkbox grammar, the `done:` line,
    the `$` executable form, and the `contract: done-means-v1` key; the planner
    emits the key by default on new plans and uses an executable predicate whenever
    completion is command-observable. While editing `spec-format`, its frontmatter
    reference also gains the `domains:` key, which `consolidate.lib.sh` already
    reads but which the skill has never documented.

14. **`tasks-verify` is read-only and says what it is.** The op writes no file and
    mutates no state; its help text states both boundaries from §Boundary — the
    prose-vs-executable limit, and that predicates themselves may have side
    effects.

## Out of scope

- Retrofitting `done:` lines onto specs 0001–0046.
- Any change to the TDD red→green PreToolUse guard, `speccraft-guard`, or the
  override path. This spec adds a close-time gate only.
- Blocking `/speccraft:spec:implement` on per-task verification. Implement-time
  enforcement is a plausible follow-up but multiplies the blast radius; close is
  the single choke point this spec touches.
- Sandboxing executable predicates. They run with the developer's own privileges
  from the developer's own plan file — the same trust level speccraft already
  extends to the detected test command.
- A mechanical definition-without-reader check (the removed backstop) — its own
  spec.
- Fixing the aux-delegator temp-file collision that produced a false quorum in
  this spec's own round-1 review — its own spec, filed from `review.md`.
- The four other items triaged from the same field report (plan corrections as a
  first-class artifact, `index.md` per-entry byte cap, consolidation routing seed
  and skip marker, review-round stopping rule).

## Open questions

_none_
