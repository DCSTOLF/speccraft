---
id: "0055"
title: "What the live smoke found: a cwd-keyed job store, an archive-blind id allocator, and six latent test and portability bugs"
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

It also surfaced **eight defects that nothing else had caught**: not 1,093 green
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

Two consequences make this urgent rather than tidy. **The live smoke is red
right now**, so the next engineer to run it sees two failures that have nothing
to do with the product and will reasonably conclude the `codex-plugin` mode is
broken. And **`/speccraft:spec:new` would today allocate `0047`**, colliding
with the archived `0047-done-means-contract` — this spec had to compute its own
id by hand to avoid it.

## What

Fix eight defects. Seven are small; the id allocator needs a helper, because the
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

## Acceptance criteria

1. **`live_launch` launches at the workspace root.** It derives its cwd from
   `speccraft-state find-root` (or the plugin dir), not from `$TEST_DIR`, and a
   row asserts the launch argv's `--cwd` value equals that root. This row runs
   in CI with a stub `node`, ungated, so the fix is pinned on a host with no
   Codex plugin. **Negative:** reverting the cwd to a `/tmp` path fails the row.
2. **The gated live smoke passes on a credentialed host.** With
   `SPECCRAFT_LIVE_CODEX_SMOKE=1`, both `AC26` and `AC26a` rows pass, reporting
   a job id and a confirmed cancel. Not a CI criterion — it is verified by one
   manual run and recorded, exactly as spec 0054's AC26 was.
3. **`_review_codex_dispatch` uses one cwd for the whole job lifecycle.** A
   stub `node` records argv per subcommand; a row asserts that `task`,
   `status`, `result` and `cancel` all carry the **same** `--cwd` value, equal to
   the cwd the dispatcher was given. **Negative:** dropping `--cwd` from any one
   of the three post-launch helpers fails the row. A second row asserts a
   dispatch given an explicit cwd *outside* the repo still resolves its own job
   (the exact scenario defect 1 hit).
4. **No comment in `spec-review-payload.bats` claims an archive entry cannot red
   the corpus arm.** A grep-level row asserts the superseded sentence is absent,
   and that the surviving comment states what actually bounds the arm.
5. **The corpus arm is invariant under an exported budget override.** A row runs
   the arm's predicate with `REVIEW_MAX_ARGV_BYTES` exported to a value above
   and below the live composition and asserts the same verdict both times — the
   branch reads the **effective** limit (`review_effective_limit argv`), not the
   compiled default. **Negative:** the pre-fix form fails under the override,
   demonstrated rather than asserted.
6. **`specs/domains/spec-lifecycle.md` no longer claims `git diff HEAD` is
   reproducible from `HEAD`.** The bullet instead states that the frozen
   artifact is the reproducible record, and scopes any ref-reproducibility claim
   to the `<ref>...HEAD` form. A row asserts the false phrasing is absent.
7. **Every hook command is space-safe.** All five entries in `hooks/hooks.json`
   either quote the placeholder or use the exec form, and
   `claude plugin validate` reports **no** unquoted-placeholder warning. A row
   asserts the absence of a bare unquoted `${CLAUDE_PLUGIN_ROOT}` in a shell
   `command` field. **Negative:** re-introducing one in any single entry fails
   the row — the check is per entry, not "the file mentions a quote somewhere".
   A second row proves the hooks still execute from a path **containing a
   space**, which is the actual failure being prevented and the only thing a
   quoting grep cannot establish.
8. **Spec id allocation is archive-aware, and it is a helper.** A new
   `spec_new_next_id <repo-root>` in `commands/spec/new.lib.sh` scans
   `specs/` **and** `specs/.archive/` and returns the highest id + 1, zero-padded
   to four digits. It returns `0056` for this repo's current tree, `0001` for an
   empty fixture, and `max+1` for a fixture whose ids exist **only** under
   `.archive/`. **Negative:** an allocator that scans only `specs/` returns a
   colliding id on the archived fixture and fails the row. `commands/spec/new.md`
   step 4 calls the helper and no longer instructs `ls specs/`; a row asserts the
   command body does not contain the bare `ls specs/` allocation instruction.
8a. **No two specs share an id, and that keeps being true.** A standing row
    collects every `NNNN` prefix across `specs/` and `specs/.archive/` and fails
    if any id appears more than once, naming the duplicates. This is deliberately
    separate from AC8: the allocator fix prevents future collisions, while this
    row addresses the damage the archive-blind allocator could already have done
    and then keeps watching. **Negative:** a fixture containing the same id in
    both `specs/` and `specs/.archive/` fails the row — proving it detects the
    exact shape the old allocator would have produced, rather than only a
    duplicate within one directory.
9. **The corpus test name matches its assertion.** The row at line 1504 is
   renamed to say it composes under the **payload** limit; the static-corpus row
   keeps its argv wording. A row asserts no `@test` name in that file claims an
   argv bound while its body asserts `REVIEW_MAX_PAYLOAD_BYTES_DEFAULT`.
10. **Regression floor.** The whole bats suite and the Go suite green on Linux
    and macOS with `go test -C tools -count=1 ./...`; `tasks-verify --run`
    clean; drift scan clean; `bin/` not committed. The 0052 floor's assertions
    are intact — a row count plus the names, now **119 identical plus one
    deliberately renamed** by AC9, stated that way so the rename cannot be
    confused with an accidental edit.

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
