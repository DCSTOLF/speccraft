# speccraft

A Claude Code plugin that enforces spec-first TDD via hooks, slash commands, subagents, and cross-model review.

## Stack

- Bash 5+ hooks (`hooks/`) wired through `hooks/hooks.json`
- Go helper binaries under `tools/cmd/speccraft-{state,guard,drift}` sharing `tools/internal/{speccraft,delegate}` (module `github.com/dcstolf/speccraft/tools`; `go.mod` declares Go 1.22, CI runs Go 1.26.3)
- Markdown slash commands (`commands/`) and subagents (`agents/`)
- Markdown skills (`skills/<name>/SKILL.md`)
- Stack-agnostic memory templates (`templates/speccraft/`) copied into a host repo by `/speccraft:init`
- Devcontainer-based end-to-end test (`tests/e2e/run.sh`) driven by GitHub Actions (`.github/workflows/ci.yml`)

## Architecture in one paragraph

speccraft is packaged as a Claude Code plugin (`.claude-plugin/plugin.json`, marketplace `dcstolf-tools`) and ships three execution surfaces: shell hooks that gate Edit/Write tool calls, slash commands the user invokes (`/speccraft:init`, `/speccraft:spec:*`, `/speccraft:sync`), and subagents the orchestrator dispatches (planner, critic, reviewer, delegator, memory-keeper). Hooks and commands call small Go binaries — `speccraft-state` (session/spec state in `.speccraft/state.json`), `speccraft-guard` (TDD red→green invariant), and `speccraft-drift` (regex scan of `enforce:` rules in memory files) — whose shared logic lives in `tools/internal/speccraft`. The repo dogfoods its own plugin: `.speccraft/` here is real project memory for this very codebase, not a fixture.

## Hard rules (see guardrails.md)

- Never commit built binaries from `bin/` or `tools/bin/`.
- Never bypass the TDD red→green invariant without `/speccraft:spec:override` with a recorded reason.
- Plugin templates under `templates/speccraft/` must stay stack-agnostic (no Go-, Python-, or HTTP-specific assumptions).

## Where to look

- Hooks: `hooks/` (entry: `hooks/hooks.json`)
- Slash commands: `commands/` (top-level + `commands/spec/`)
- Subagents: `agents/`
- Skills: `skills/<name>/SKILL.md`
- Go helper binaries: `tools/cmd/speccraft-*/main.go`
- Shared Go logic: `tools/internal/speccraft/`, `tools/internal/delegate/`
- Architect conductor & workspace topology: `commands/arch/orchestrate.{md,lib.sh}`, `tools/internal/speccraft/ledger.go` (`ParseLedger`/`SetLedgerField`/`Reconcile`), `FindWorkspaceRoot`/`ParseWorkspaceMembers`; the workspace ledger is `<workspace>/.speccraft/ledger.md` (a history.md-class memory file, never `state.json`)
- User-facing memory templates: `templates/speccraft/`
- E2E test harness: `tests/e2e/run.sh`
- Specs: `specs/NNNN-<slug>/`

## Active spec

specs/0052-review-prompt-size-budget/

## Recent decisions (last 3)

- 2026-09-26 — Release 1.17.0: the four-spec bump backlog, and why it could not ship until CI was green (spec 0051, closed; **released as v1.17.0**): carries 0047 + 0048 + 0049 + 0050. MINOR — four new subcommands (`tasks-verify`, `build-repair-log`, `design-fingerprint`, `set-status --kind`), build-repair mode, three new `state.json` session keys, no caller contract changed. `bump-before-close` exists to stop a backlog and four deferrals compounded anyway, but **the binding constraint was CI**: `auto-tag` → `release.yml` fires on push to `main`, so a bump pushed during runs #79-#86 would have tagged and published from a tree failing on three jobs — the gate was correctly closed, not ignored. Eight locations: 3 Go consts, 4 oracles whose function names ENCODE the version (so the bump renames them and registers a real red-candidate, which a bare const edit cannot) each with a NEGATIVE check advanced to reject the outgoing version, 2 manifests; `bin/` rebuilt and `.binary-version` re-stamped in the same task, since skipping that makes this repo's hooks chase a release that does not exist yet. **Bump and close are SEPARATE commits** — the close-commit invariant binds changelog+status, not the bump, and splitting let the changelog record what the pipeline ACTUALLY reported rather than an intention. Verified: `v1.17.0` at `bdefb29`, Release run 19 success, 4 tarballs + `checksums.txt`, `verify-release.sh` OK strong-form, CI **#92** green on all seven jobs, and the PUBLISHED binaries extracted and run — all report 1.17.0 and the new subcommands dispatch, which hash-only verification could not prove. Divergence, all predicates: T1/AC3 asserted the ABSENCE of `1.16.0` from files whose stale-version checks must contain it (**third time this session**; the invariant is POLARITY, not absence), and T6 depended on ambient `PATH`, failing at close having passed during implementation — spec 0050's T7/T12/T15 share that latent flaw and passed by the same accident. Both rules now in conventions.md.

- 2026-09-26 — CI green again: six defects behind eight red runs, three of them ONE root cause (spec 0050, closed; unreleased at 1.16.0): `main` was red for runs #79-#86 (last green #78, 2026-08-04); run **#89** is green on all seven jobs. **A:** `SetRedCandidates` stored `red_candidates[file]` verbatim while `siblingRedCheck` reads via `NormalizeStateKey`, so a registered candidate became unfindable and the guard said "No test was added this session" — spec 0048's own refusal, back through another door. Only visible where an ancestor is a symlink (every macOS `t.TempDir()`); fixed at the WRITER, and `TMPDIR`-at-a-symlink reproduces all 25 macOS failures on Linux. **B, which hit THREE consumers as three unrelated-looking symptoms:** `install-binaries.sh` finds no gitignored `.binary-version` stamp and DOWNLOADS the last release over freshly built binaries — breaking the Linux bats job, the macOS one, and the E2E job, where `--plugin-dir` loaded HEAD's commands but RELEASE Go. As old as those tests; harmless only until one needed an unreleased subcommand. **C:** macOS `grep (BSD grep, GNU compatible)` read as a GNU build, failing `hooks-macos` BEFORE bats — so the macOS suite had **never once executed**; a job that cannot start yields no signal in either direction, which is worse than the vacuous green AC10 was written to prevent. Fixing C let it run and it found **D:** `hooks/pre-tool-use.sh` used `realpath -m` (absent on macOS), so the hook aborted under `set -e` before delegating — **the state.json guard AND the whole TDD invariant were inert on macOS** — and **E:** a GNU-only checksum tool in `sync_design_fingerprint`, now delegating to a new `speccraft-state design-fingerprint` (one producer of a value Go already computed). **F:** with the gate hand-run by an agent, the E2E's outcome depended on whether step-8 predicates still matched step-9 code; the agent correctly STOPPED, twice, and the suite blamed close for a stale locator upstream. Extending the meta-guard revealed the new clause was **mis-scoped** — it flagged a pre-existing, correct Go comment — so it excludes `*.go`, pinned by fixture. A usage/dispatch parity test found **three more** undocumented subcommands and **corrected my own diagnosis**: the truncated usage dump was not evidence of a stale binary, since a CURRENT binary produced it too. 9 ACs at open, 15 at close. Override budget 0 stated / **2 actual**, both because the INSTALLED 1.11.0 plugin predates this repo's fixes and hit spec 0048's defects A and B in turn — 0048's bugs re-demonstrated live by the session fixing their successor. Verified: **350 bats** on Linux, **343/343 on real BSD userland** (macOS job's first green ever), Go suite plain and under a symlinked `TMPDIR`, vet, drift.

- 2026-09-25 — Build-repair mode: a broken build no longer forbids its own repair, and red candidates survive a no-new-test edit (spec 0048, closed; unreleased at 1.16.0): `OutcomeBuildFailed` blocked the edit, so a break in PRODUCTION code blocked the very edit that would repair it — spec 0047 stated an override budget of 0 and spent 5 on one forward reference. Now a `go test -overlay` probe of the POST-edit content decides: clean ⇒ allow silently and close repair mode; still broken ⇒ allow but RECORD FIRST, bounded at `buildRepairMaxEdits` = 10 per session enforced INSIDE the atomic record op (the only race-free placement) and derived solely from the log's length, so a clean probe never refunds spent budget; probe cannot answer ⇒ BLOCK naming both errors; non-Go ⇒ byte-identical to today. Defect B: `added = postIDs − preIDs` meant any test-file edit adding no new `func Test…` overwrote that file's candidates with `[]` and re-blocked a legitimately-RED production edit — now recomputed from a FIRST-TOUCH-ONLY per-file `red_baseline`, so a no-new-test edit recomputes the same set while a deletion still shrinks it, and a failed capture now BLOCKS the test-file edit (PreToolUse, so disk is byte-unchanged and the retry recovers). The probe is ONE command, which **corrected the plan's own correction C1**: `go build -o <dir> ./...` fails with "no main packages to build" on a library-only module, while `go test -run '^$'` compiles test files too and links into GOCACHE, so it is both safer and more thorough. Guardrails names this as the SECOND bypass class beside `/speccraft:spec:override`, with the bound pinned bidirectionally to the compiled constant. 3 review rounds, six hash-distinct outputs, no false quorum. Override budget 1 stated / **3 actual** — none where the plan expected: T2's bootstrap landed at zero via a compile-stable literal-JSON RED, and two of the three spent were **this spec's own defects biting their own fix**.

