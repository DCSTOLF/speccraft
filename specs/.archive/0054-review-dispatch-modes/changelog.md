---
spec: "0054"
closed: 2026-11-26
---

# Changelog — 0054 Review dispatch modes: `codex-plugin` and `subagent`

## What shipped vs spec

Fifty-two of the spec's fifty-four acceptance criteria (ACs 1–27 with letter
suffixes) across 92 tasks and 45 commits, `c96b97f` → `e10ea23`. **ACs 26 and
26a are carried, not done** — see §Carried below. The design shipped as
reviewed: the four-mode enum, the `companion task --background` lifecycle with
confirmed cancellation, the persistent lease-governed round directory, the
payload-digest attestation, the content-aware tree check, and the explicit
rejections (help-text probing, foreground `task`, lease renewal, a `/codex:*`
slash command as the dispatch target) all landed unchanged.

- **Two new registry modes (ACs 1–4, 12).** `mode` accepts `cli | acp |
  codex-plugin | subagent`; an omitted key normalizes to `cli`; an explicitly
  empty value and case variants (`Subagent`, `CLI`) are named errors in **both**
  readers. Strict keys apply to the new modes only — `cli`/`acp` keep today's
  permissive decoding, so no host registry stops loading. Both readers are driven
  from one fixture corpus
  (`tests/hooks/fixtures/review-dispatch/registries/`, 11 reject files +
  `expected.txt`), because `LoadConfig` fails the whole file on the first bad
  entry while `review_agent_mode` is per-agent and a single `parity.toml` could
  not be driven by both.
- **The `codex-plugin` adapter (ACs 5–7, 9–11, 13).** `commands/spec/review-codex.lib.sh`,
  958 lines: root resolution (`plugin_root` → local-scope entry whose
  `projectPath` is the repo root → user-scope entry), per-resolution-path version
  discovery, `setup --json` readiness memoized on the **symlink-resolved** root,
  the exact background launch argv, the four-helper job lifecycle (`job_id` /
  `status` / `result` / `cancel`), and a parser total over
  (exit status × JSON validity × field contents) against the **nested**
  `.storedJob.result.*` shape.
- **The persistent round directory (ACs 14, 14a–14e, 15, 15a–15b, 17b–17c).**
  `commands/spec/review-round.lib.sh`, 1,251 lines: `0700` dir under
  `.speccraft/.review-rounds/`, published atomically from
  `.building-<expiry-unix-ts>-<rand>`, a `*` `.gitignore` written atomically
  beside it, lease-based (never age-based) reclamation at
  `review_timeout_s + 300 s`, quarantine records that beat cleanup and are
  resolved per block against their own recorded companion root, and
  `review_tree_snapshot` — content digests of every tracked **and** untracked
  file outside the round dir, no `--exclude-standard`, no `--directory`.
- **One shared round for four commands (ACs 8, 16, 16a, 19–22a).**
  `skills/review-round/SKILL.md` (481 lines) is the single runbook;
  `commands/spec/review.md`, `commands/arch/review.md`, `commands/pm/review.md`
  and `commands/spec/review-code.md` all reference it and all list `Agent`,
  `TaskStop`, `Bash(shasum:*)`, `Bash(sha256sum:*)`. `review_compose_payload`
  gained `--label` and normalizes both payload ends on every branch;
  `review_finalize_round` gained an optional `<kind>` so `design`/`brief` write
  `review.md` with no snapshot promote and no fingerprint, and `code` writes
  nothing durable. Both extensions are defaulted, which is what kept spec 0052's
  suites from needing edits.
- **The subagent reviewer (ACs 17a, 17d, 18, 18a, 18b, 20a, 20b, 23).**
  `agents/reviewer.md` (126 lines): tools exactly
  `Read, Grep, Glob, Bash(shasum:*), Bash(sha256sum:*), Write`, `model: inherit`,
  no `Edit`, no bare `Bash`. Preflight refuses a custom `subagent_type` lacking
  `Write` before any Agent launch and warns on one declaring `Edit`; the timeout
  protocol is the spec's seven steps with a recorded agent id and an **absolute**
  deadline; lateness is judged against a completion stamp written when the
  notification arrives, never against the clock at collection time.
- **Attestation extended (ACs 16, 16a).** Subagent responses carry
  `payload_sha256`; all five dispatchable templates
  (`review.md`, `re-review.md`, `review-code.md`, `arch-review.md`,
  `pm-review.md`) now document a `reference_access:` block that is extracted from
  the template, filled, and round-tripped through the real parser by test.
- **Vendor record (ACs 23a).** `review_agent_vendor` resolves
  `anthropic|openai|unknown` by exact basename match on argv[0] — no substring,
  no prefix — with `subagent` ⇒ `anthropic` and `codex-plugin` ⇒ `openai` by
  construction; `review.md` records `mode`, requested `model` and `vendor` per
  verdict, and `single_vendor_approval` per round.
- **Review-only modes refused elsewhere (AC23b).** `spec:delegate` and
  `aux-delegator` fail with the contracted string
  `unsupported-mode: <mode> is a review-only dispatch mode`, before composing a
  prompt.
- **Docs and template (ACs 24, 25).** A new `.speccraft/conventions.md`
  §"A user-configured review adapter is not routing"; `skills/aux-agents/SKILL.md`
  documents both adapters as mechanism, enforced by a phrase guard with a premise
  row; `templates/speccraft/agents.toml` rewritten (94 lines changed).
- **Version 1.19.0**, bumped inside the spec before close as its own commit
  (`6514df2`), per spec 0051's split.

### Deviations

1. **ACs 26/26a are carried, not satisfied.** See §Carried.
2. **The spec-0052 regression floor moved by two BODY lines, and T71's gate
   changed shape.** `tests/hooks/spec-review-payload.bats` had a row skipping
   `mode == "acp"` when checking that every shipped-template entry yields a
   runnable command — `acp` being the complete set of command-less modes when
   0052 wrote it. AC25 mandates an **enabled** `subagent` entry and the loader
   REFUSES a `cmd` on it, so that row and AC25 could not both hold. The skip was
   narrowed to `!= "cli"`, which is what the row's own comment already meant.
   Separately, the file's single-use-source helper **deadlocked**: the writer's
   three extra `: > "$fifo"` opens do not block while a reader is attached, so all
   three could be consumed inside the first read's window and the second read
   blocked in `open()` forever (observed with `grep` parked in the kernel's
   `wait_for_partner`, hanging roughly half the local runs). The second pass is
   now bounded by `timeout 10`, which reaches the same conclusion the test
   asserts, deterministically. **All 120 `@test` names remain byte-identical to
   `19317e5`**, and T71's predicate is now that equality plus the row count,
   rather than whole-file byte equality — byte equality cannot express "0052's
   assertions are intact" once the mode set grows.
3. **Scoped amendments, recorded in-repo rather than worked around.** AC14a
   gained its fixture provenance (the pre-0054 `.gitignore` is a checked-in
   fixture, not a shape the test constructs); AC14e gained the statement that the
   transient `.building-*` names are observed by interleaving or instrumentation,
   because a successful create renames them away; AC17b's volatile set was
   widened from `.claude/settings.local.json` to the whole `.claude/` tree, to
   match §Contracts, and its wording corrected; and
   `failed subagent-launch unsupported-subagent-plugin <type>` is a **contract
   addition** that §3/§Contracts do not name, recorded in plan.md §"Scoped
   amendment" after round 9 flagged it as an unrecorded deviation.
4. **`aux-delegator`'s `mode` parameter was renamed `task_mode`.** Two different
   things were called "mode" — the task kind and the registry's dispatch mode —
   and passing one where the other belonged was a live defect in
   `/speccraft:spec:review` (T45.8). The agent file now states the distinction
   explicitly; the 0052 golden
   `tests/hooks/fixtures/spec-review-payload/golden/aux-delegator-nonreview.golden`
   was updated to match.
5. **Two phases shipped text that was known-wrong and said so.** Phase F.6
   deferred the runbook's §4 timeout protocol and §7 attribution rule to their
   owning tasks and recorded both as landed-but-wrong rather than letting them
   read as done; both deferrals are closed in plan.md at steps 55 and 57.
6. **Three REFACTORs un-pointed static guards, twice.** The T28 and T39
   extractions each left guards grepping `review.lib.sh` for forms that had just
   moved out of it — **seven** went vacuous at T39, demonstrated by planting all
   seven forbidden forms in the extracted lib and watching every guard pass. All
   now scan `commands/spec/review*.lib.sh` by glob, and the re-planted forms red
   six of them (the seventh is behavioural, not a static grep).
7. **44 files of an unrelated project were swept into `ac6ed4a`, and have been
   removed by a history rewrite.** `evidences/0014-masking-injectivity-gate-and-
   output-version-fence/` — another repo's closed spec, plan, review and ~12,600
   lines of evidence logs (`packages: [engine, integration/masking, …,
   cdcbridgetest]`) — was committed by a blind `git add -A` inside the T39
   extraction commit, which added exactly ONE legitimate file and 44 foreign
   ones. It then survived 25 further commits, nine verification passes, four
   cross-model review rounds and four CI runs, and reached draft PR #4; a
   close-time `memory-keeper` pass found it.

   Resolved on the operator's ruling (2026-11-25): the branch history was
   rewritten with `filter-branch --index-filter` across all 45 commits so the
   files were never added, verified by `git diff --name-status <old> <new>`
   showing **exactly 44 deletions and nothing else** and all 45 commit subjects
   byte-identical, then force-pushed with a lease. The files remain on disk —
   they are evidence the operator shares for debugging — and are ignored via
   `.git/info/exclude` rather than `.gitignore`, so no ignore rule for them
   ships to the repo. `git add -A --dry-run` now stages none of them. A local
   `backup/pre-evidences-rewrite` branch holds the pre-rewrite tip, unpushed.

   Recorded as a lesson rather than a footnote: every check run during this spec
   was scoped to what was being worked on, and none asked whether anything
   tracked in the repo did not belong to it.

8. **Override budget 0 planned, 0 actual. Build-repair admissions: 0.**
   `speccraft-state build-repair-log` reports "no build-repair edits recorded
   this session" at close. The plan's reasoning held: Phases B–I are shell and
   markdown, which `speccraft-guard` does not classify as production code, and
   Phase A's RED was a runtime failure in a package that already had sibling
   tests, so the struct-field additions never tripped the pre-edit build probe.

## Review

**Nine spec-review rounds** (recorded in `review.md`, `review-snapshot.md`):
codex `changes-requested` ×8 then `approve` with `concerns: []`; claude-p
`attestation-failed` → `changes-requested` → `approve-with-comments` ×7. Round 9
is the first cross-vendor approval in nine rounds — rounds 3–8 each met quorum on
a lone `anthropic` approval, so `single_vendor_approval` was `true` for six
consecutive rounds and is `false` here.

**Round 1 was INERT, and that is why the `subagent` mode exists.** `claude -p`
in a non-interactive permission context refused every hashing command, so its
spec-0052 reference digests were never computed and its verdict came back
`attestation-failed`. This repo's own `.speccraft/agents.toml` now passes
`--allowedTools Read Grep Glob Bash(shasum:*) Bash(sha256sum:*)` for that entry.

**Four cross-model code-review rounds of the DIFF (6, 7, 8, 9), ~55 defects
reproduced.** Every finding was reproduced before being accepted; two claims did
not hold and were dropped.

- **Round 6 (the three shell libs, 142 KB) — the macOS-fatal class nine spec
  rounds and 752 green tests had missed.** zsh does not word-split an unquoted
  parameter expansion, and these libs are `source`d into the caller's shell.
  `tests/hooks/lib-zsh-safety.bats` proved every lib *sources* under zsh; nothing
  had ever *executed* a function body there. Four were fatal: `$digest "$p"`
  holding `shasum -a 256` execed a command name with spaces, so the whole
  attestation chain and the tree snapshot failed; `for x in $LIST` iterates once
  with the whole list as one element, so the tier table, the outcome tokens, the
  mode enum, the effort/model enums and the volatile set all answered "no" to
  everything; round dirs named `$$-$RANDOM` collided because zsh hands a
  command-substitution subshell the parent's `$RANDOM`, so `mv` nested one round
  inside the other, returned 0, and one round's cleanup deleted the other's
  payload; and `review_dispatch_agent` read `cmd` through `review_agent_field`,
  which returns raw TOML array text, so every array-form registry — this repo's
  included — execed the word `["codex",`.
- **Round 7 (four command bodies, the runbook, five templates, 58 KB) — the
  runbook's text IS the implementation, and nothing had checked its calls.** §2
  passed a PATH to `review_budget_check`, which takes a byte count, so the shared
  round's first gate errored for every reviewer in all four commands; §2 composed
  one `payload.md` while §6 validated `<agent>.payload`, a path nothing wrote;
  `spec:review` read the transport where the dispatch mode belonged, so the
  subagent-only digest check never ran; and it still used the ephemeral
  `review_round_tmpdir` with an `EXIT` trap, which made running a subagent
  **structurally impossible** — the reviewer is dispatched in a later tool call
  and would find its payload deleted.
- **Round 8 (split 8a libs / 8b docs, four reviewers) — eleven defects, every one
  in the SEAM between two individually correct helpers.** Two were fatal to any
  real round: `review_subagent_collect` emits `ok`, a *proceed* token, and the
  runbook **recorded** it as an outcome, so the unknown-token arm aborted every
  successful subagent round with exit 2; and **ACs 23/23a shipped DEAD** — the
  vendor record switches on only with a 5th and 6th argument to
  `review_finalize_round` and not one of the nine call sites passed them (both
  reviewers found this independently). Then: a disqualified approval still met
  quorum, because the attribution was appended beside the reviewer's own
  `approve` instead of replacing it; lateness was judged at collection time, so
  one slow reviewer discarded every other verdict in the round; a YAML
  block-list `tools:` read as absent, so a `Write`-less agent took the
  inherits-everything branch and passed preflight; any `plugin:` qualifier was
  stripped, so `otherplugin:reviewer` was vetted against *speccraft's*
  `agents/reviewer.md`; and the refusal text was a paraphrase that its own test
  agreed with while both disagreed with §Contracts.
- **Round 9 reviewed round 8's FIXES and found eleven more — six newly introduced
  by those fixes.** The T65 proven-terminal gate was placed inside
  `review_round_cleanup`, which the **sweep** also calls, so an abandoned round
  could never be reclaimed and silently, because the sweep's `|| true` swallowed
  the refusal; AC15a's documented operator action ("remove `quarantine` and the
  sweep reclaims it") therefore stopped working; the per-block quarantine record
  was undone by its own consumer, which read only the first block and `rm -f`'d
  the whole file; `review_finalize_round` resolved the vendor flag **after** its
  durable writes, so a failure left a partially committed round reading as a
  failed one; the runbook's `|| true` swallowed the tree check's exit 2; and the
  frontmatter parser had three defects, all from the previous phase — it required
  block-list items to be indented, it stripped whitespace from the key so a
  nested `meta:` block's `tools:` shadowed the real one, and it printed the value
  twice because in POSIX awk `exit` inside a main rule still runs `END`.

**Two operator rulings, 2026-11-24, both recorded in plan.md and implemented at
T70.5/T70.6.** (1) `single_vendor_approval` **is gated on a met quorum** — this
overruled my recommendation, and the reviewers' reasoning is the better one: the
line describes an approval the round ACTED ON, so printing it on a round that
never reached quorum invites "approved, by one vendor" where the round was not
approved at all. Resolution is skipped with the reporting, so a below-quorum
round is not failed over a value nobody reads; with quorum met an unresolvable
vendor is still fatal and still leaves the spec dir untouched. The per-verdict
`mode=`/`model=`/`vendor=` fields are **not** gated. (2) The shipped
`templates/speccraft/agents.toml` now enables **exactly one** reviewer — the
`subagent`, the only one that needs nothing installed — with the three `cli`
entries `enabled = false` **explicitly** and the reason written beside them.
`enabled` is opt-OUT, which is exactly how those three came to be enabled: an
absent key means true and nobody ever wrote one. An enabled reviewer whose binary
is absent does not degrade gracefully — its dispatch fails, the round is
incomplete, and **no `review.md` is written at all, even if another reviewer
approved**. This changes `/speccraft:init` for new repos; existing registries are
not migrated.

## CI: four runs, and the first three were not product bugs

PR #4 is the first CI this branch ever had — `ci.yml` fires only on push to
`main` and pull_request to `main`, so **41 commits ran nothing**.

1. **Run 1, Linux bats:** two CI-only defects in my own tests. (a) An `awk` range
   whose END pattern is an interval — `awk '/[Tt]imeout .*protocol/,/^#{2,3} /'`.
   mawk, this devcontainer's awk and Debian's default, does not implement
   intervals, so the end pattern matched nothing, the range ran to EOF, and the
   count happened to come out right; CI's awk does implement them, and there the
   range closed on its own **start** line, because the section header matches
   `^#{2,3} ` too. One line yielded "the whole file" on one platform and "one
   line" on the other, and neither was the section meant. Replaced with
   `sed -n '/…/,/^## [0-9]/p'` — sed's range never closes on the start line and
   an alternation needs no interval — plus a non-empty check. (b) A nested-bats
   helper cleared every `BATS_*` variable to stop a child inheriting the parent's
   filter, which also removed `BATS_ROOT`/`BATS_LIBEXEC`; this container's bats
   resolves its internals from argv0 and did not care, CI's install does, and the
   child died on `validator.bash: No such file or directory`.
2. **Runs 1 and 2, both macOS jobs: cancelled in under a second, with no runner
   and zero steps.** `ci.yml` pinned `runs-on: macos-14`, which GitHub had
   retired. The only visible diagnosis was a check-run annotation reading
   `The configuration 'macos-14-arm64-us-default' is not supported` — the **job**
   said only `cancelled`, which reads like a human cancelled the run. macOS last
   ran green here on **2026-09-30**, and nothing surfaced the breakage for
   ~8 weeks. Both jobs are now `macos-latest`, with the reason in a comment: what
   they are for is BSD userland and darwin/arm64 Go, neither of which is tied to a
   macOS version.
3. **Run 3, macOS allocated for the first time: exactly one failure, and it was a
   REAL product defect.** `_review_codex_root_from_registry` canonicalized the
   repo root and then handed it to jq to compare against a **raw**
   `.projectPath`. jq cannot resolve a symlink, so that was a string comparison
   between two spellings of one directory; on macOS `$TMPDIR` is under
   `/var/folders/…` and `/var` is a symlink to `/private/var`. **A local-scope
   plugin entry could therefore never be selected on macOS**, and resolution fell
   through to the USER-scope companion silently — the round went to a different
   installation than the operator configured. The sibling check three lines above
   already canonicalized both sides. Fixed by matching in shell, one entry at a
   time, both sides canonicalized (which also made array order explicit, so that
   has its own row), and pinned **on Linux** by reaching a fixture repo through a
   symlink — this repo's recorded technique for the class, from spec 0050.
4. **Run 4 green. `45481446627`, conclusion `success`:** Go Linux, Go macOS, bats
   Linux, bats macOS, language-only e2e. `Auto-tag` and `E2E (devcontainer)` are
   `skipped` by their own `if:` (both gated on push to `main`, which a draft PR is
   not). The two gated ACs appear in the macOS log **by name**, which is the half
   of AC27 that stops a green suite from implying the live smoke ran.

One failure in 1,093 tests, missed by nine spec-review rounds, four cross-model
code-review rounds and dozens of green local runs — because every one of those
ran against a non-symlinked temp dir. That is the whole argument for the macOS
job.

## Files touched

Libraries and runbook:
- `commands/spec/review.lib.sh` (+1,474 → 2,594)
- `commands/spec/review-codex.lib.sh` (new, 958)
- `commands/spec/review-round.lib.sh` (new, 1,251)
- `skills/review-round/SKILL.md` (new, 481)
- `agents/reviewer.md` (new, 126)

Commands, agents, templates:
- `commands/spec/review.md`, `commands/arch/review.md`, `commands/pm/review.md`,
  `commands/spec/review-code.md`, `commands/spec/delegate.md`
- `agents/aux-delegator.md` (`mode` → `task_mode`), `agents/cross-reviewer.md`
- `skills/aux-agents/SKILL.md`
- `templates/speccraft/agents.toml`
- `templates/prompts/{review,re-review,review-code,arch-review,pm-review}.md`
  (the last two new)

Go:
- `tools/internal/delegate/toml.go` (+216: mode enum, `agentKeySets`,
  `knownAgentKeys`, the new `Agent` fields)
- `tools/internal/delegate/{mode,parity,template}_test.go` (new)
- the six version-bump files + `manifest_version_test.go` +
  `.claude-plugin/{plugin,marketplace}.json`

Tests (15 new bats files, ~11,500 lines):
`spec-review-dispatch`, `spec-review-codex`, `spec-review-payload-boundary`,
`spec-review-round-dir`, `spec-review-tree-snapshot`, `spec-review-round-runbook`,
`spec-review-attestation`, `spec-review-code`, `spec-review-subagent`,
`spec-review-vendor`, `spec-review-shell-parity`, `spec-review-round-lifecycle`,
`review-only-mode-refusal`, `review-subagent-agent`, `review-dispatch-docs`,
plus `live-codex-smoke.bats` (env-gated, NON-CI) and `tests/hooks/stubs/stub-node.sh`.
Edited: `portability-guard.bats`, `tests-portability-sweep.bats`,
`spec-review-payload.bats` (2 body lines), `spec-review-diff.bats`.

Fixtures: `tests/hooks/fixtures/review-dispatch/{codex,legacy-repo,registries}/`
— the verbatim 1.0.6 `printUsage` capture, `INTERFACE-1.0.6.md`, the derived
`task-success-1.0.6.json`, the pre-0054 `.gitignore` with its `PROVENANCE.md`,
and the 12-file parity corpus.

Repo config: `.github/workflows/ci.yml` (macOS runners unpinned),
`.speccraft/agents.toml` (claude-p `--allowedTools`), `.speccraft/conventions.md`
(AC24), `.speccraft/index.md`.

Not 0054's work, tracked at HEAD, needs a decision:
`evidences/0014-masking-injectivity-gate-and-output-version-fence/` (44 files).

## Verification

- **1,093 bats locally, 2 named skips** (AC26, AC26a), 86 s with
  `PATH="$PWD/bin:$PATH"`.
- `go test -C tools -count=1 ./...`, `go vet`, `GOOS=windows go build -C tools ./...`
  all clean. `-count=1` is load-bearing: `template_test.go` reads a file that is
  not a Go source input, so a cached pass survives a template change (verified by
  shipping the subagent entry disabled and watching the package stay green).
- `tasks-verify --run` clean at **92/92**.
- **CI run `45481446627` on draft PR #4, conclusion `success`** — five executing
  jobs green on Linux and macOS. This is AC27.
- Every negative assertion was proven to bite by reintroducing what it forbids;
  round 8 recorded 14 such mutations and round 9 recorded 13, in both cases with
  a few written only after noticing the fix had been verified by hand without a
  row.
- Override budget **0 stated / 0 actual**; build-repair log empty.

## Carried (ACs 26/26a), not hidden

The manual live smoke is **not done**. The harness exists and is complete
(`tests/hooks/live-codex-smoke.bats`, T69/T70): both bodies are written, gated on
`SPECCRAFT_LIVE_CODEX_SMOKE=1`, and they **skip by name** rather than passing
silently — the CI log shows both skips, and AC27 is worded to exclude them so a
green suite can never be read as having run them. They need a host with the Codex
plugin installed and authenticated and they spend real Codex credits, so on
2026-11-24 the operator chose to close and carry them. When run, the changelog
takes the companion version, the resolved job ids, evidence the round went
through `task --background` + `status` + `result`, and `/codex:status` showing the
cancelled turn no longer active.

Honest about the ceiling: **AC26's `subagent` half is unprovable from bats at
all** — no shell can launch a subagent, so that reviewer's live behaviour can
only be exercised by an orchestrating session, not by any suite.

## Known gaps, carried not hidden

- The live smoke above.
- **`templates/speccraft/agents.toml` ships `opencode` with `input = "stdin"`
  while `opencode run <message>` may take its prompt positionally.** Unverifiable
  here: `/usr/local/bin/opencode` is this repo's own e2e mock, not the real CLI.
  Recorded as an open question in the template itself; if stdin is not accepted
  that entry needs `argv`, and the byte budget then refuses an oversized payload
  by name — the right failure, where an empty prompt returning a confident verdict
  is the worst one.
- **A `/speccraft:init` on a host with no aux CLI now yields a single-vendor
  round by design.** One enabled reviewer, `anthropic`, so
  `single_vendor_approval: true` on every approval until the operator enables a
  second vendor. The record is the mitigation; `/codex:setup` plus the disabled
  `codex-plugin` entry is the documented route out.
- `speccraft-state test-command` returns `pytest -q` in this repo, parsed out of
  a documentation example inside `.speccraft/conventions.md`'s own description of
  the marker grammar (line 521). Latent here — no `done:` predicate in this spec
  calls it and every one sets `PATH` itself — and deferred to its own spec.
- `tests-portability-sweep.bats` still cannot see a GNU-only form inside a
  one-line function body (`f() { cmd; }`); pre-existing, unchanged by this spec.

## Follow-ups filed

1. **Run ACs 26/26a** on a credentialed host and append the evidence here.
2. ~~Decide on `evidences/0014-…`~~ — **done at close.** Removed by history
   rewrite; kept on disk, ignored via `.git/info/exclude`. See deviation 7.
3. **Release.** 1.19.0 is in the tree, so the merge to `main` trips `auto-tag` →
   `release.yml` → `verify-release.sh`. Per spec 0051, hash verification alone
   cannot catch a correctly-packaged wrong build: extract the published tarballs
   and run the three binaries.
4. **Spec the `test-command` marker parser** (it matches its own documentation).
5. **Consider a CI trigger on spec branches.** 41 commits with no CI, and an
   8-week-old runner-label outage that surfaced only at the close gate, are both
   consequences of firing on push/PR to `main` alone.
6. **`review-code`'s untracked-file exclusion** stays as stated prose; widening
   the command to untracked files remains out of scope.
