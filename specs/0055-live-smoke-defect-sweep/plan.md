---
spec: "0055"
status: planned
strategy: tdd
---

# Plan — 0055 What the live smoke found

Nine defects, twenty-five implementation steps, RED before every GREEN. Steps
1–4 come first because the gated live smoke is **red right now** and the next
engineer to run it reads two test defects as a broken `codex-plugin` mode.

**Surface note.** Nothing in this spec touches Go. `speccraft-guard` does not
classify `.sh` / `.md` / `.json` / `.bats` as production code (conventions
§Bash), so no step needs `/speccraft:spec:override` and the override budget is
**0 planned**. The RED→GREEN discipline here is author-enforced, not
guard-enforced — which is exactly why every negative row below must be *run*
against a restored defect rather than asserted in prose.

**Two hard constraints that shaped test placement:**

- `tests/hooks/spec-review-payload.bats` is the spec-0052 floor and AC10 pins it
  at **119 identical names plus exactly one rename** (120 total, baseline commit
  `19317e5` — verified today as `diffcount=0 total=120`). Adding a row there
  would break AC10. So ACs 4/5/9's assertion rows live in a **new sibling**,
  `tests/hooks/spec-review-payload-floor.bats`, following the existing
  `spec-review-payload-boundary.bats` precedent. Only the arm's **body** and its
  one **name** change in the floor file itself.
- A `done:` predicate may not `source` a command lib under `/bin/sh`: every lib
  sets `-o pipefail`, which dash rejects. Predicates that need a helper use
  `bash -c '. ./commands/... && <fn>'`.

**Why predicates never read the ambient stack.** `speccraft-state detect-stack`
returns `language: unknown` with no test patterns in this repo (the Go module is
rooted at `tools/`, and there is no root `go.mod`), and `test-command` wrongly
returns `pytest -q` — a doc example parsed out of `conventions.md`, deferred to
its own spec. So **every `done:` predicate below names its command literally and
sets `PATH="$PWD/bin:$PATH"` itself.** Spec 0051's T6 failed by depending on
ambient state in exactly this shape.

## Test-first sequence

### Step 1 — the live smoke's launch cwd and cancellation pass condition (RED)

Add to `tests/hooks/live-codex-smoke.bats` (ungated, runs in CI with a stub
`node`):

- `@test "live_launch derives its cwd from the workspace root, not a temp dir"`
  — a stub `node` records its argv and prints `{"jobId":"probe-1"}`; call
  `live_launch` and assert the recorded `--cwd` equals `speccraft-state find-root`.
- `@test "the launch-cwd row rejects a /tmp cwd, so it is not vacuous"` — drive
  the **pre-fix body**, kept verbatim as a file-local `live_launch_tmpcwd`,
  through the *same* `assert_launch_cwd` predicate and require a non-zero result.
- `@test "the AC26a body requires a non-terminal status before the cancel and cancelled after"`
  — a source-scan row over this file's own gated AC26a body (the existing
  arity-guard pattern): it must read a status *before* the cancel, accept only
  `queued`/`running` there, and require exactly `cancelled` after.

Fails because `live_launch` passes `$TEST_DIR` as `review_codex_task_argv`'s 5th
argument, so the recorded `--cwd` is the temp dir; and today's AC26a body asserts
only that `review_codex_job_cancel` returned 0, with no pre-cancel observation
and no `cancelled` equality.

### Step 2 — launch at the workspace root; make the cancel row prove a cancel (GREEN)

- `live_launch` derives
  `cwd="$(speccraft-state find-root 2>/dev/null || printf '%s\n' "$PLUGIN_DIR")"`
  and passes `$cwd`; the payload stays an absolute path under `$TEST_DIR`.
- The `AC26a` body captures `pre="$(review_codex_job_status …)"`, fails with a
  named message if `pre` is already terminal ("this run proves nothing about
  cancellation"), and after the cancel requires `st = cancelled` **exactly** —
  not merely terminal, because `review_codex_job_cancel` succeeds on any terminal
  status.
- The two gated rows still skip (`# skip` count stays 2) and the arity guard
  stays green.

### Step 3 — one cwd owns the whole job lifecycle (RED)

Add to `tests/hooks/spec-review-codex.bats`:

- `@test "task status result and cancel all carry the dispatcher's cwd"` — a stub
  `node` records argv per subcommand; drive `_review_codex_dispatch` with a short
  timeout so the poll expires and the cancel path runs, then assert all four
  recorded `--cwd` values equal the cwd the dispatcher was given.
- `@test "a dispatch given a cwd outside the repo still resolves its own job"` —
  the stub models a **cwd-keyed job store**, answering `status`/`result` only when
  the `--cwd` matches the launch's. Dispatch with a cwd outside the repo must
  still collect the response instead of timing out. This is defect 1's exact
  scenario.
- `@test "dropping the cwd from any one post-launch codex helper fails the lifecycle row"`
  — loop over `review_codex_job_status`, `_result`, `_cancel`: for each, source a
  copy of the lib with that one helper's `--cwd` removed and re-run the assertion,
  requiring failure. **Per helper**, so fixing two of three cannot pass.

### Step 4 — thread the cwd through the post-launch helpers (GREEN)

`commands/spec/review-codex.lib.sh`:

- `review_codex_job_status <root> <job-id> <cwd>`,
  `review_codex_job_result <root> <job-id> <out-file> <cwd>`,
  `review_codex_job_cancel <root> <job-id> <cwd>`,
  `_review_codex_poll <root> <job-id> <timeout-s> <cwd>` — the cwd is
  **required, never defaulted**: a default is precisely the trap this spec closes.
- Update each `# <fn> <args…>` doc header in lockstep — the live smoke's arity
  guard reads them and fails otherwise.
- `_review_codex_dispatch` passes its own `$cwd` to poll / result / cancel.
- `review_codex_preflight` is deliberately unchanged: it asks about the install,
  not the job store.

Then update the ~12 two-argument call sites in `spec-review-codex.bats` and the
four in `live-codex-smoke.bats`.

### Step 5 — quarantine records its cwd, and the sweep says why a block survived (RED)

Add to `tests/hooks/spec-review-round-lifecycle.bats`:

- `@test "a codex-plugin quarantine records the job-store cwd beside the root"`
- `@test "quarantine recovery probes the recorded cwd from an unrelated cwd"`
- `@test "a legacy quarantine block with no cwd line is retained with a named diagnostic"`
- `@test "the sweep reports the missing-cwd block by name and clears only the new-format one"`
  — a **mixed** quarantine file (one legacy Codex block with no `cwd `, one
  new-format block).
- `@test "the sweep's missing-cwd report fails when the resolver output is suppressed"`
  — restore `>/dev/null 2>&1` on the sweep's resolve call in a lib copy and
  require the row above to go red.

Fails because `review_round_quarantine` writes no `cwd ` line, the resolver calls
`review_codex_job_status` with no cwd, and `review_round_sweep` discards the
resolver's output at `review-round.lib.sh:386` behind `>/dev/null 2>&1`, printing
only a generic retention line.

### Step 6 — record it, probe with it, surface it (GREEN)

`commands/spec/review-round.lib.sh`:

- `review_round_quarantine <dir> <id> <outcome> <mode> [<root>] [<cwd>]` writes
  `cwd <canonical>` beside `root <canonical>`; required for `codex-plugin`,
  refused for `subagent` — the same shape the root already has.
- The resolver reads the block's `cwd` and probes
  `review_codex_job_status "$root" "$q_id" "$cwd"`. A block with a root but **no**
  `cwd` is retained with the named diagnostic `quarantine-missing-cwd <id>` plus
  the operator's safe release path. A guessed cwd would delete a live reviewer's
  output dir and then report `subagent-no-output` as the reviewer's fault.
- `review_round_sweep` stops discarding the resolver's stderr: it captures it and
  prints each diagnostic prefixed with the entry, so an operator learns *which*
  block survived and *why*. Exit-status semantics unchanged.

The only shipped caller (`subagent-stop-failed`) is unaffected: the new parameter
is positional after the optional root, and subagent blocks carry neither.

### Step 7 — the 0052 corpus arm's three defects, pinned from a sibling file (RED)

Add `tests/hooks/spec-review-payload-floor.bats` (new file — the floor itself
cannot grow a row without breaking AC10):

- `@test "no comment in the 0052 corpus arm claims an archive entry cannot red it"`
  — bracket-escaped patterns, per the self-scanning rule.
- `@test "the superseded-claim row bites when the sentence is restored"`
- `@test "the surviving comment states what actually bounds the arm"`
- `@test "the corpus arm branches on the effective argv limit, not the compiled default"`
- `@test "the pre-fix corpus-arm branch misclassifies under an exported REVIEW_MAX_ARGV_BYTES"`
  — reproduce the pre-fix predicate inline and **run** it with an override above
  the live tiered size, showing the wrong disposition, then show
  `review_effective_limit argv` yields the right one.
- `@test "no @test name in the 0052 floor claims an argv bound while its body asserts the payload limit"`
- `@test "the test-name row bites when the old argv name is restored"`
- `@test "the 0052 floor is 119 identical names plus exactly one rename"`

### Step 8 — correct the comment (GREEN)

`tests/hooks/spec-review-payload.bats`: delete the superseded sentence
("…and neither can a new archive entry") and state what actually bounds the arm —
"a new archive entry CAN push the tiered size over the argv limit, and the arm
below pins that case rather than denying it." No `@test` name changes.

### Step 9 — pin the arm's disposition at both override values (GREEN)

The arm's **body only**: the branch reads `review_effective_limit argv`, and the
arm runs two sub-cases over the live corpus — effective argv limit **below** the
tiered size ⇒ `refuse:argv-limit` on argv **by name** and `ok` on stdin;
**above** it ⇒ `ok` on both. The fixture exports `REVIEW_MAX_PAYLOAD_BYTES` high
in both cases, because payload refusal takes precedence and would otherwise mask
the argv disposition under test.

### Step 10 — rename the row to match its assertion (GREEN)

`spec-review-payload.bats:1504` becomes
`@test "the live .speccraft plus the largest archived spec composes under the payload limit while a full paste exceeds the argv limit by more than 2x"`.
The sibling static-corpus row at :1488 keeps its argv wording. Exactly one name
then differs from `19317e5`; total stays 120.

### Step 11 — the false reproducibility claim (RED)

Add to `tests/hooks/spec-review-code.bats` (which already owns the frozen-diff
prose rows):

- `@test "spec-lifecycle.md no longer claims git diff HEAD is reproducible from HEAD"`
- `@test "the reproducibility-claim row bites when the old phrasing is restored"`
- `@test "the corrected bullet names the frozen artifact, pinned endpoints and the round lifetime"`

### Step 12 — correct the bullet (GREEN)

`specs/domains/spec-lifecycle.md`: replace the clause with one saying three
things — **the frozen artifact is the reproducible record**; a ref-based claim
holds only for `<ref>...HEAD` with **both endpoints pinned to commits** (a
movable ref can change the merge base); and the artifact lives **for the lifetime
of the round**, because round cleanup removes it. `specs/**` is excluded from the
drift scan, so this edit cannot trip it.

### Step 13 — every hook command must be space-safe (RED)

Add `tests/hooks/hooks-json-quoting.bats`:

- `@test "no hook command field carries a bare unquoted CLAUDE_PLUGIN_ROOT"` —
  asserts it saw **five** command entries, so it cannot pass vacuously.
- `@test "the quoting row bites on any single re-introduced bare placeholder"` —
  five mutants, one per entry.
- `@test "all five hooks execute from a plugin root containing a space"` — a
  `$TEST_DIR/plugin dir with space/hooks/<name>.sh` marker stub per hook; run each
  entry's `command` string through `sh -c` with `CLAUDE_PLUGIN_ROOT` set to that
  spaced path, and require every marker.
- `@test "the spaced-path row fails on the pre-fix unquoted command"` — the thing
  a quoting grep cannot establish.

### Step 14 — quote the placeholder in all five entries (GREEN)

`hooks/hooks.json`: each command becomes
`"\"${CLAUDE_PLUGIN_ROOT}/hooks/<name>.sh\""`. File stays valid JSON.
`claude plugin validate` is run by hand under the manual task; adding it to CI is
out of scope, owed to the `actionlint` spec.

### Step 15 — archive-aware, reservation-honouring id allocation (RED)

Add `tests/hooks/spec-new-id-allocation.bats`:

- `@test "spec_new_next_id returns 0056 for this repo's live tree"`
- `@test "spec_new_next_id returns 0001 for an empty fixture"`
- `@test "spec_new_next_id returns max+1 when every id lives only under .archive"`
- `@test "spec_new_next_id skips an id reserved by reserves-specs at max+1"`
- `@test "reserves-specs is read from frontmatter only, never from prose"` —
  0005's own spec.md names the field in body text in backticks, so a loose grep
  would read prose as a reservation.
- `@test "an allocator that scans only specs slash returns a colliding id on the archived fixture"`
  — a test-local `naive_next_id` reproducing the shipped `ls specs/` rule, **run**
  and asserted to return the colliding id.
- `@test "an allocator that ignores reserves-specs returns the reserved id"` —
  likewise run.

### Step 16 — add `spec_new_next_id` (GREEN)

`commands/spec/new.lib.sh`: scan `specs/*/` **and** `specs/.archive/*/` for
four-digit prefixes, collect column-0 `^reserves-specs:` values from every spec.md
in both trees, and return the lowest four-digit id greater than the highest
existing id and not reserved; `0001` for an empty tree. Pure, zero-padded,
newline-delimited iteration via `while IFS= read -r` — **never** `for x in $list`,
which iterates once under zsh.

### Step 17 — no two specs may share an id (RED)

- `@test "no spec id appears twice across specs and specs archive"`
- `@test "the duplicate-id row fails on a fixture holding one id in specs and the same id archived"`
  — the exact shape the archive-blind allocator would have produced, not merely a
  duplicate within one directory.

### Step 18 — the standing uniqueness collector (GREEN)

Add the test-side `spec_ids_for <root>` collector (test-side on purpose: it
selects a corpus and ships nothing). The live-tree row starts green — 53 ids,
gaps at `0006` (a live reservation) and `0053` — and the fixture row proves it
bites.

### Step 19 — the shipped command must call the helper, reachably (RED)

- `@test "new.md sources the lib before it allocates an id"` — the `source` line's
  number must be lower than the `spec_new_next_id` line's.
- `@test "the shipped step-4 invocation, extracted and run, allocates on a fixture with archived ids and a reservation"`
- `@test "the extracted invocation fails when given the wrong repo root"`
- `@test "the extracted invocation fails when its return value is discarded"`
- `@test "new.md no longer tells the model to run ls specs"`
- `@test "the ls-specs absence row bites when the instruction is restored"`

Fails because `new.md` step 4 says to run `ls specs/`, and the `source` of
`new.lib.sh` sits in step **5** — after allocation — so a `spec_new_next_id` call
written into step 4 as-is would invoke an unsourced function.

### Step 20 — bootstrap before allocation, and call the helper (GREEN)

`commands/spec/new.md`: move the bootstrap block (`plugin-root`, `find-root`, one
`source`) **ahead** of allocation; make step 4
`NEXT_ID="$(spec_new_next_id "$REPO_ROOT")"`; delete the `ls specs/` instruction;
downstream steps use `$NEXT_ID`.

### Step 21 — a rejected synthesis must stop the whole publish sequence (RED)

Add to `tests/hooks/spec-review-round-runbook.bats`:

- `@test "a staged synthesis with no Reviewers section is refused and nothing is published"`
- `@test "a staged synthesis whose Reviewers table has no Vendor column is refused"`
- `@test "a well-formed staged synthesis is published"`
- `@test "a refused synthesis leaves review.md and review-snapshot.md byte-identical"`
- `@test "a refused synthesis stamps no fingerprint and does not promote status"`
- `@test "a refused synthesis reports the same quorum result as a well-formed one"`
- `@test "removing the table validation lets the omitted-section case through"`
- `@test "restoring the publish-then-finalize order lets the snapshot advance"`
- `@test "an inert round with a staged synthesis still leaves review.md byte-unchanged"`
- `@test "the runbook stages the synthesis and hands it to review_finalize_round"`
- `@test "each of the four review commands passes a staged synthesis rather than writing review.md directly"`

### Step 22 — stage, validate, then publish (GREEN)

- `review_reviewers_table_valid <candidate> <outcomes>` emits `ok` or one named
  reason (`reviewers-table-missing`, `reviewers-table-no-vendor-column`,
  `reviewers-table-missing-agent <agent>`) as **data**. `ok` is a proceed token
  the caller branches on and never records.
- `review_finalize_round` gains a 7th **optional** positional `<staged-review>`,
  so every 3-/4-/6-argument caller stays byte-identical. When given: validate
  **before any durable write**, and on failure emit `synthesis: refused <reason>`
  with `responses_complete:` / `approval_quorum_met:` **unchanged**, perform no
  install, no snapshot promote, no fingerprint stamp, no status promotion, and
  return 1. On success install the candidate via a same-dir temp + rename, then
  promote/stamp for the `spec` lane. `code` plus a staged candidate is exit 2 by
  name, never a silent ignore.
- The quorum calculation is untouched: a malformed artifact is a publishing fault
  and must not retroactively un-approve a round.
- `skills/review-round/SKILL.md` writes the synthesis to
  `$ROUND_DIR/review.candidate.md` and hands it to `review_finalize_round`; the
  runbook no longer writes `review.md` itself. Same change in
  `commands/spec/review.md`, `commands/spec/review-code.md`,
  `commands/arch/review.md`, `commands/pm/review.md`.

### Step 23 — every changed helper body runs under bash AND zsh (RED)

Extend `tests/hooks/spec-review-shell-parity.bats` with
`parity_lib <lib> <what> <script>` so a lib other than `review.lib.sh` can be
sourced, plus:

- `@test "the parity harness detects a difference in an extra lib too"` — without
  this self-check the new arm can pass vacuously, which is the defect this file
  exists to end.
- `@test "spec_new_next_id agrees across shells"` — it iterates a list of ids,
  precisely the shape that failed before.
- `@test "review_round_quarantine agrees across shells"`
- `@test "review_round_quarantine_resolve agrees across shells on a legacy block"`
- `@test "the sweep's missing-cwd diagnostic agrees across shells"`

### Step 24 — fix whatever zsh exposes (GREEN)

Whatever the parity rows surface in `new.lib.sh` and `review-round.lib.sh` —
expect unquoted-expansion iteration and command-substitution `$RANDOM` reuse, the
two recorded classes. zsh is required, never silent-skipped.

### Step 25 — Refactor (optional)

Steps 1, 3 and 5 each build a cwd-recording stub `node`. Fold them into one
helper under `tests/hooks/stubs/` so the stub that models the companion's
cwd-keyed job store exists once.

## Delegation

- Steps 1–24 → **keep in session.** Every step is shell/markdown/JSON, so the TDD
  guard does not gate them and there is no override budget to protect; the work is
  a chain of per-file RED→GREEN pairs where the cost of handing off context exceeds
  the work itself.
- After step 22 → delegate a **code review of the diff** via
  `/speccraft:spec:review-code`, scoped at the `review.lib.sh` + `SKILL.md` +
  four-command-body diff. Reason: the publish path is the one place this spec
  changes a durable-write ordering, and this repo's record is that diff review
  catches what spec review cannot — nine spec rounds plus 752 green tests once
  missed a macOS-fatal class.
- T27 (the live smoke) → **operator only.** It spends credits on a credentialed
  host; no agent can be given that authority.

## Risk

- **`result` and `cancel` may not accept `--cwd`.** `status` is proven to —
  `.speccraft/history.md` records the same job id returning `No job found` without
  it and `"status": "completed"` with it — and the other two share the companion's
  arg parser. Mitigation: T27's manual run is the oracle. If one rejects the flag,
  the fallback is a subshell `cd "$cwd"` around that invocation, which satisfies
  AC3's intent but **not** its wording, so it would need a spec revision rather
  than a quiet substitution.
- **A required cwd parameter churns 16 existing call sites.** Required
  deliberately — an optional default is the trap — and the live smoke's arity
  guard cross-checks every call against the doc headers, so a missed site fails
  loudly rather than defaulting.
- **Adding a row to `spec-review-payload.bats` would break AC10.** The name pin
  (`19317e5`, exactly one differing name, 120 total) is both a bats row and a
  `done:` predicate, so the mistake fails at close time.
- **New bats files are in `tests-portability-sweep.bats`'s scan scope.** No
  `sed -i`, `tac`, `readlink -f`, `grep -P`, `stat -c`, `date -d`, `base64 -w`,
  `0,/re/`, and no awk range whose end pattern is an interval. Mutation fixtures
  are built with `printf`, never a heredoc containing a column-0 `@test` — bats
  counts those as real tests.
- **The close gate exceeds the 30 s predicate budget.** Measured: full
  `tests/hooks/` 89 s, `go test -C tools -count=1 ./...` 16 s. Run it as
  `SPECCRAFT_TASKS_VERIFY_TIMEOUT=300 speccraft-state tasks-verify
  specs/0055-live-smoke-defect-sweep/tasks.md --run`, as spec 0054's T71 required.
  T26's own predicate deliberately calls `tasks-verify` **without** `--run`:
  a `--run` inside a predicate is unbounded self-recursion.
- **The `-ge` row floors are slack**, set at current count plus planned rows.
  Tighten them to exact post-implementation counts before close, or they will not
  bite on a deleted file.
- **AC2 cannot be a CI predicate.** The *code* half (the two-observation pass
  condition) is pinned by an ungated source-scan row in step 1; the *run* half is
  a recorded manual task whose predicate proves the observations were
  **transcribed**, not that they occurred. That residue is irreducible and is the
  same contract spec 0054's AC26 shipped under.

## AC coverage

| AC | Tasks | Mechanical? |
|---|---|---|
| 1 | T1, T2 | Yes — ungated CI row with a stub `node` |
| 2 | T1 (code half), T27 (run half) | **Partly** — the run needs credits; the predicate proves a record exists, not that it is true |
| 3 | T3, T4 | Yes |
| 3a | T5, T6 | Yes |
| 4 | T7, T8 | Yes |
| 5 | T7, T9 | Yes |
| 6 | T11, T12 | **Partly** — absence and the three required claims are greppable; prose quality is not |
| 7 | T13, T14, T27.b | **Partly** — quoting and spaced-path execution are mechanical; `claude plugin validate` needs the CLI, so it rides T27 |
| 8 | T15, T16 | Yes |
| 8a | T17, T18 | Yes |
| 8b | T19, T20 | Yes |
| 9 | T7, T10 | Yes |
| 9a | T21, T22 | Yes |
| 9b | T21, T22 | Yes |
| 10 | T23, T24, T26, T27.c | **Partly** — Linux bats, Go, drift, `bin/`, the 119+1 pin and bash/zsh parity are predicates; "green on macOS" is the CI job, recorded under T27.c |
