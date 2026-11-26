---
id: "0055"
title: "What the live smoke found: a cwd-keyed job store, an archive-blind id allocator, and seven latent test and portability bugs"
status: draft
created: 2026-11-26
revision: 0
authors: [claude]
packages: ["commands/spec", "hooks", "tests/hooks", "specs/domains"]
related-specs: ["0025", "0051", "0052", "0054"]
domains: [external-tool-boundaries, spec-lifecycle, ci-and-e2e]
---

# Spec 0055 — What the live smoke found

## Why

Spec 0054 closed carrying ACs 26/26a, its manual credit-spending live smoke.
That smoke was run on a credentialed host on **2026-11-26**. It did what it was
written to do: it proved the `codex-plugin` dispatch path works live
(`task --background` → `status` → `result`, 12.4 s) and that a real cancel is
confirmed and the detached broker actually stops — the one thing no stub can
establish.

It also surfaced **nine defects that nothing else had caught**: not 1,093 green
bats, not a green Go suite, not nine spec-review rounds, not four cross-model
code-review rounds, and not five CI jobs across Linux and macOS. That is the
point worth recording. Each of these is invisible to the checks this repo
already runs, for a specific and different reason:

- Two are only reachable by **talking to a real external service**, whose
  behaviour the stub `node` does not model.
- Three are **in spec 0054's own close work** — written after the last review
  round and after the last CI run, so no reviewer and no job ever saw them.
- One is a **documentation claim** that is simply false, and prose is the one
  artifact no test asserts.
- One is **latent in a function's contract**: no current caller trips it, so
  every test passes while the parameter stays a trap.
- One is a **live collision hazard in `/speccraft:spec:new` itself**, created
  when spec 0025 began archiving closed specs and never noticed since, because
  allocating an id is a thing the command tells a model to do by hand.
- One was found by **this spec's own review round**, and is the sharpest
  argument in the list: spec 0054 added per-verdict `mode`/`model`/`vendor`
  reporting (**AC23**; AC23a is the separate `single_vendor_approval` flag), the round report emits them correctly — and the
  `cross-reviewer` **silently omitted the entire `## Reviewers` table** from the
  `review.md` it synthesized, on the first real use of those fields. The round
  report is ephemeral; `review.md` is the durable artifact a reader has weeks
  later. Nothing asserts the table exists, so AC23 reaches a human reader
  only by the synthesizer's goodwill.

Two of the nine were found by reviewers rather than by running anything, and
both were found by **cross-model review of this spec**, which is the process
working as designed and is recorded here because the alternative reading — that
the spec was right first time — would be false.

Two consequences make this urgent rather than tidy. **The live smoke is red
right now**, so the next engineer to run it sees two failures that have nothing
to do with the product and will reasonably conclude the `codex-plugin` mode is
broken. And **`/speccraft:spec:new` would today allocate `0047`**, colliding
with the archived `0047-done-means-contract` — this spec had to compute its own
id by hand to avoid it.

## What

Fix nine defects. Eight are small; the id allocator needs a helper, because the
current "allocator" is an instruction in markdown telling a model to run
`ls specs/`, and an instruction cannot be regression-tested.

1. **The live smoke's cwd.** `live_launch` in `tests/hooks/live-codex-smoke.bats`
   passes `$TEST_DIR` — a `mktemp` dir under `/tmp` — as the companion's
   `--cwd`. The Codex companion keys its job store by **git workspace root**
   (`state/<basename>-<hash>/jobs/`): every path inside a repo resolves to that
   repo's root, while a non-repo directory resolves to itself. So the job landed
   in `state/tmp.XXXX-*/` while `review_codex_job_status` and
   `review_codex_job_cancel` — which take no cwd and inherit bats' cwd, the
   repo — queried `state/speccraft-*/`. `status` never saw the job (300 s poll →
   124) and `cancel` could not confirm (`codex-cancel-unconfirmed`). The test
   was wrong on its own terms too: a reviewer running in an empty temp dir could
   never read the reference files it is required to attest.
2. **The dispatch-cwd trap.** `_review_codex_dispatch` accepts `<cwd>`, threads
   it into `review_codex_task_argv` only, and then calls
   `_review_codex_poll` / `review_codex_job_result` / `review_codex_job_cancel`
   without it and never `cd`s. Any caller passing a cwd whose workspace root
   differs from the process's gets a guaranteed timeout, an unconfirmed cancel
   and a quarantined round. No shipped caller trips it — all three dispatch
   sites pass three arguments, so the cwd defaults to `speccraft-state find-root`
   and both sides agree — but defect 1 is proof the trap can be stepped on.
3. **A comment contradicted eight lines later.**
   `tests/hooks/spec-review-payload.bats:1519` still claims "an unrelated
   spec:close cannot red this and neither can a new archive entry", directly
   above the spec-0054 amendment explaining that archiving 0054 did exactly
   that.
4. **The corpus arm's ambient-environment fragility.** Same test: the branch
   predicate compares `$tiered` against the compiled
   `REVIEW_MAX_ARGV_BYTES_DEFAULT`, then asserts on `review_budget_check`, which
   uses the **effective** limit. An exported `REVIEW_MAX_ARGV_BYTES` reds it
   spuriously. Spec 0051's T6 was this same class (an ambient `PATH`), and its
   lesson is already a convention.
5. **A false reproducibility claim.** `specs/domains/spec-lifecycle.md` states
   that `git diff HEAD` is "exactly reproducible from the recorded `HEAD`". It
   is not: that form reads the **working tree**, so two trees at one HEAD with
   different unstaged edits yield different diffs. Only the frozen artifact
   preserves the reviewed bytes. The claim is true for the
   `--base` / `<ref>...HEAD` form alone.
6. **Unquoted `${CLAUDE_PLUGIN_ROOT}` in every hook.** All five commands in
   `hooks/hooks.json` are bare `"${CLAUDE_PLUGIN_ROOT}/hooks/<name>.sh"`, which
   word-splits when the expanded path contains a space. The plugin installs
   under `$HOME`, so a macOS home directory such as `/Users/Daniel Stolf/`
   breaks **every hook in the plugin**. Found by `claude plugin validate`, which
   this repo has never run; it flags all five entries.
7. **Archive-blind spec id allocation.** `commands/spec/new.md` step 4 says to
   run `ls specs/` and take the highest prefix + 1. Closed specs are moved to
   `specs/.archive/` by consolidation (spec 0025), so that scan sees a maximum
   of `0046` while `0047`–`0054` sit archived. The next `/speccraft:spec:new`
   would allocate a **colliding** id. There is no allocation helper at all today.
8. **A test name that no longer describes its assertion.** The corpus arm at
   `spec-review-payload.bats:1504` is still named "composes under the argv
   limit" while its body now asserts the **payload** bound. At 0054's close this
   could not be fixed because T71's gate pinned all 120 names byte-identical;
   that gate was a one-time `done:` predicate in 0054's `tasks.md`, which is now
   archived and no longer runs, so the rename is finally free. The sibling
   static-corpus row at line 1488 still legitimately asserts the argv bound and
   must keep its name.
9. **`review.md` can lose the `## Reviewers` table silently.** The
   `cross-reviewer` template requires a per-reviewer table carrying
   `Mode | Model | Vendor` — spec 0054's **AC23** — and on this spec's own
   review round the agent omitted the whole section. The round report had the
   fields and was correct; the durable artifact simply did not carry them.
   Nothing in the suite asserts `review.md`'s structure, so this stays invisible
   until a reader opens a `review.md` and wonders which model answered.

**Two scope notes on the job-store cwd, from the review round.** Item 2's fix
must cover the *whole* job lifecycle, not just dispatch:
`review_round_quarantine_resolve` probes the per-block companion `root` it
recorded, but records **no job-store cwd** and calls
`review_codex_job_status` without one — so quarantine recovery queries the
ambient cwd's store and can retain a block forever. Existing quarantine blocks
carry no such field, so the fix needs a defined behaviour for them rather than a
format change that strands them. Separately,
`review_codex_job_cancel` returns success on **any** terminal status
(`completed | failed | cancelled`), so "confirmed cancellation" is weaker than
its name: a job that finished on its own a moment earlier reports as a confirmed
cancel. For the round's actual question — "is this reviewer still running?" —
terminal is the correct predicate, so the **product behaviour stands**; what must
change is the live smoke's **pass condition**, which must require that the job
was observed active *before* the cancel and `cancelled` *after*.

## Acceptance criteria

1. **`live_launch` launches at the workspace root.** It derives its cwd from
   `speccraft-state find-root` (or the plugin dir), not from `$TEST_DIR`, and a
   row asserts the launch argv's `--cwd` value equals that root. This row runs
   in CI with a stub `node`, ungated, so the fix is pinned on a host with no
   Codex plugin. **Negative:** reverting the cwd to a `/tmp` path fails the row.
2. **The gated live smoke passes on a credentialed host, and its cancellation
   row proves a cancellation rather than a coincidence.** With
   `SPECCRAFT_LIVE_CODEX_SMOKE=1`, both `AC26` and `AC26a` rows pass. The
   cancellation row's **pass condition** requires two observations, not one: the
   job reported a non-terminal status (`queued` or `running`) **before** the
   cancel, and `cancelled` specifically — not merely "some terminal status" —
   **after** it. This is required because `review_codex_job_cancel` succeeds on
   any terminal status, so a job that completed on its own a moment earlier
   would otherwise be recorded as a confirmed cancel. Not a CI criterion: it is
   verified by one manual run and recorded, as spec 0054's AC26 was.
3. **One cwd owns a job for its whole lifecycle, including quarantine
   recovery.** A stub `node` records argv per subcommand; a row asserts `task`,
   `status`, `result` and `cancel` all carry the **same** `--cwd`, equal to the
   cwd the dispatcher was given. **Negative:** dropping `--cwd` from any one of
   the three post-launch helpers fails the row — checked per helper, so fixing
   two of three cannot pass. A second row asserts a dispatch given an explicit
   cwd *outside* the repo still resolves its own job, which is exactly the
   scenario defect 1 hit.
3a. **Quarantine blocks record their job-store cwd, and recovery uses it.**
    `review_round_quarantine` writes a `cwd ` line beside the existing `root `
    line, and `review_round_quarantine_resolve` probes with that recorded cwd
    rather than the ambient one. A row proves recovery works when invoked from
    an **unrelated** cwd: the block is retained while its job is active and
    removed once that same job is terminal. **Legacy blocks:** a block with no
    `cwd ` line is **retained with a named diagnostic**, never probed against a
    guessed cwd and never silently dropped — a wrong guess would delete a live
    reviewer's output path, which fails silently and then reports
    `subagent-no-output` as the reviewer's fault. A row covers the legacy shape
    explicitly.
    **The diagnostic must reach the operator through the SWEEP, not only the
    resolver.** `review_round_sweep` discards resolver output and prints a
    generic retention message, so a direct resolver test can pass while an
    operator running the sweep cannot tell why a block survived or how to release
    it safely — which is precisely how spec 0054's round 9 defect hid, the
    sweep's `|| true` swallowing a refusal. So a row exercises the **sweep** over
    a **mixed** quarantine file holding one legacy Codex block (no `cwd `) and
    one new-format block, and asserts three things: the sweep surfaces the
    missing-cwd diagnostic naming the block, the legacy block is retained, and
    **only** the new-format block is cleared once its job is terminal.
    **Negative:** restoring the output suppression fails the row.
4. **No comment in `spec-review-payload.bats` claims an archive entry cannot red
   the corpus arm.** A grep-level row asserts the superseded sentence is absent,
   and that the surviving comment states what actually bounds the arm.
   **Negative:** restoring the superseded sentence fails the row — an absence
   assertion that has never been seen to fail is indistinguishable from a typo
   in its own pattern.
5. **The corpus arm's disposition is pinned at both override values, named
   explicitly.** "Same verdict" was ambiguous and is now spelled out: with the
   effective argv limit set **below** the live tiered size the predicate must
   yield `refuse:argv-limit` on argv and `ok` on stdin; with it set **above**
   that size it must yield `ok` on both. The row asserts each disposition by
   name, and the branch reads `review_effective_limit argv` rather than the
   compiled default. The fixture also controls the effective **payload** limit,
   because payload refusal takes precedence and would otherwise mask the argv
   disposition being tested. **Negative:** the pre-fix form, which compares
   against the compiled default, fails under an exported override —
   demonstrated by running it, not asserted in prose.
6. **`specs/domains/spec-lifecycle.md` no longer claims `git diff HEAD` is
   reproducible from `HEAD`.** The corrected bullet says three things: the
   **frozen artifact** is the reproducible record; a ref-based claim holds only
   for `<ref>...HEAD` **with both endpoints pinned to commits**, since a movable
   ref can change the merge base; and the artifact's **lifetime** is the round,
   because round cleanup removes it. A row asserts the false phrasing is absent.
   **Negative:** restoring the old phrasing fails the row.
7. **Every hook command is space-safe.** All five entries in `hooks/hooks.json`
   either quote the placeholder or use the exec form, and
   `claude plugin validate` reports **no** unquoted-placeholder warning. A row
   asserts the absence of a bare unquoted `${CLAUDE_PLUGIN_ROOT}` in a shell
   `command` field. **Negative:** re-introducing one in any single entry fails
   the row — the check is per entry, not "the file mentions a quote somewhere".
   A second row proves the hooks still execute from a path **containing a
   space**, which is the actual failure being prevented and the only thing a
   quoting grep cannot establish.
8. **Spec id allocation is archive-aware, honours reservations, and is a
   helper.** A new `spec_new_next_id <repo-root>` in `commands/spec/new.lib.sh`
   scans `specs/` **and** `specs/.archive/`, and also every spec's
   `reserves-specs:` frontmatter, returning the lowest four-digit id that is
   greater than the highest existing id **and not reserved**. The reservation
   rule is not optional decoration: `.speccraft/conventions.md:1197` defines
   `reserves-specs` and `:1212` states ids are never reused, and the mechanism is
   live — `0005` reserves `0006` (still unused) and `0031` reserved `0032`.
   It returns `0056` for this repo's current tree, `0001` for an empty fixture,
   `max+1` for a fixture whose ids exist **only** under `.archive/`, and skips a
   reserved id in a fixture where the reservation sits at `max+1`.
   **Negatives, each demonstrated by running it:** an allocator that scans only
   `specs/` returns a colliding id on the archived fixture; one that ignores
   `reserves-specs` returns the reserved id.
8a. **No two specs share an id, and that keeps being true.** A standing row
    collects every `NNNN` prefix across `specs/` and `specs/.archive/` and fails
    if any id appears more than once, naming the duplicates. This is deliberately
    separate from AC8: the allocator fix prevents future collisions, while this
    row addresses the damage the archive-blind allocator could already have done
    and then keeps watching. The current tree is clean — 53 ids, no duplicates,
    gaps at `0006` (a live reservation) and `0053` — so this row starts green and
    must be proven to bite. **Negative:** a fixture containing the same id in
    both `specs/` and `specs/.archive/` fails the row, proving it detects the
    exact shape the old allocator would have produced rather than only a
    duplicate within one directory.
8b. **The shipped command actually calls the helper, and the call is reachable.**
    Two separate problems, because a grep for the helper's name fixes neither.
    **(i) Ordering.** `commands/spec/new.md` currently sources
    `commands/spec/new.lib.sh` in **step 5** while allocating in **step 4**, so a
    `spec_new_next_id` call written into step 4 as-is would invoke an
    **unsourced function**. The bootstrap therefore moves ahead of allocation —
    one `source` before both — rather than the helper call being dropped into the
    existing step 4.
    **(ii) The pin executes the real thing.** A row asserting step 4 "mentions"
    the helper passes for a call that uses the wrong root, runs before the
    source, or discards the returned id. So the row **extracts the shipped step-4
    invocation and runs it against the real helper** on a fixture that has both
    archived ids and a `reserves-specs` reservation, then asserts the scaffold
    was created at the **returned** id. **Negatives, each run:** a call given the
    wrong repo root, and one whose return value is discarded, both fail — and the
    bare `ls specs/` allocation instruction is asserted absent, with restoring it
    failing the row.
9. **The corpus test name matches its assertion.** The row at line 1504 is
   renamed to say it composes under the **payload** limit; the static-corpus row
   keeps its argv wording. A row asserts no `@test` name in that file claims an
   argv bound while its body asserts `REVIEW_MAX_PAYLOAD_BYTES_DEFAULT`.
   **Negative:** restoring the old name fails the row.
9a. **The PRODUCTION path guarantees `review.md`'s `## Reviewers` table — a test
    over a fixture is not enough.** The per-reviewer `Mode | Model | Vendor`
    table is **AC23** of spec 0054 (`single_vendor_approval` is AC23a, a
    different thing — the distinction matters because only the latter is gated on
    quorum). The `cross-reviewer` template **already required** the table when
    the agent omitted it on this spec's own round 1, and it omitted it again
    nowhere else but the one place that counts. So a row asserting the table over
    a sample file would pass while a complete live round still persists an
    incomplete artifact — testing the thing that was never broken.
    The fix is therefore in the **write path**: `review.md` is either rendered
    from the round report's own fields, or **validated against it before being
    persisted**, with a named failure when the table is missing or malformed.
    The existing complete-round write gate and the quorum rules are preserved
    exactly — an inert round must still leave an existing `review.md`
    byte-unchanged, so validation must not become a new way to write one.
    **Rows:** the production path is exercised with a synthesis that omits the
    section entirely, one that has the heading but no `Vendor` column, and one
    that is well-formed; the first two must not persist a `review.md` that
    claims to describe reviewers it does not name. **Negative:** removing the
    validation lets the omitted-section case through, demonstrated by running it.
10. **Regression floor, including shell parity.** The whole bats suite and the
    Go suite green on Linux and macOS with `go test -C tools -count=1 ./...`;
    `tasks-verify --run` clean; drift scan clean; `bin/` not committed. The 0052
    floor's assertions are intact — a row count plus the names, now **119
    identical plus one deliberately renamed** by AC9, stated that way so the
    rename cannot be confused with an accidental edit. **And every helper this
    spec adds or changes in `commands/**/*.lib.sh` has its body EXECUTED under
    both bash and zsh**, not merely sourced: `spec_new_next_id` and the changed
    quarantine helpers go through `tests/hooks/spec-review-shell-parity.bats`.
    Naming operating systems is not enough and this repo has the scar to prove
    it — zsh does not word-split an unquoted expansion, and these libs are
    sourced into the caller's shell, which on macOS is zsh. `spec_new_next_id`
    iterates a list of ids, which is precisely the shape that failed before.

## Out of scope

- **The `actionlint` + shell-portability CI lint.** Its trigger condition is met
  three times over and it is owed its own spec; AC7 adds `claude plugin validate`
  as a finding, not as a CI job. Adding a new CI lint job belongs with that spec
  so the two are designed together rather than racing.
- **The `speccraft-state test-command` marker parser**, which returns `pytest -q`
  parsed out of a documentation example in `conventions.md`. Latent here and
  already recorded; its own spec.
- **`tests-portability-sweep.bats`'s blindness to a GNU-only form inside a
  one-line function body.** Pre-existing, deferred, its own spec.
- **AC26's `subagent` half.** It needs `speccraft:reviewer` registered, which
  needs 1.19.0 live on the host; that is an environment task, not a code change,
  and it is tracked against spec 0054.
- **Merging PR #4 / releasing.** Unchanged and still the operator's call.
- **Migrating existing host registries** to add the `subagent` / `codex-plugin`
  entries. This repo's own `.speccraft/agents.toml` is still the pre-0054
  registry; whether to update it is a separate decision, not a defect fix.
- **Concurrency control for `spec:new`.** The review round raised that two
  concurrent invocations could allocate the same id. Scoped out deliberately:
  `/speccraft:spec:new` is an interactive slash command driven by one session,
  and there is no path that invokes it concurrently — adding per-repo
  serialisation would be machinery for a scenario the product cannot reach.
  AC8a's standing duplicate check is the backstop if that ever stops being true,
  and it also covers a manually created or merge-introduced duplicate, which is
  the realistic version of this risk.
- **Defining behaviour when id `9999` is occupied.** Noted by the review round
  and left out: the allocator would need a four-digit overflow policy, which is
  a format decision about spec ids rather than a defect, and at 55 specs it is
  not reachable. Recorded so the omission is deliberate rather than overlooked.

## Open questions

None open. Both were ruled on by the operator on 2026-11-26, before planning,
and are recorded here rather than deleted so the reasoning survives:

1. **Should `claude plugin validate` run in CI as part of this spec?** **No —
   deferred to the owed `actionlint` + shell-portability lint spec**, so the two
   hermetic linters are designed as one job instead of racing each other into
   `ci.yml`. `claude plugin validate` does flag **all five** entries correctly,
   so this is purely a sequencing decision and not a doubt about the tool. AC7
   still pins the fix with a per-entry bats row plus a real
   space-containing-path execution, because a validator warning says the
   placeholder is unquoted while only an execution proves the hooks still run
   from such a path.
2. **Does anything check for an existing id collision?** **Yes — added as
   AC8a**, a standing uniqueness row rather than a one-off audit. The allocator
   fix prevents future collisions; nothing would otherwise detect a collision the
   archive-blind allocator may already have created.
