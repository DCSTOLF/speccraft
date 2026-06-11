---
id: "0015"
title: "spec:revise command"
status: closed
created: 2026-06-10
authors: [claude]
packages: ["commands/spec", "agents"]
related-specs: ["0011", "0012", "0013", "0014"]
revision: 0
started_at_sha: "f2eaa5e00a945dff545fa0e830c418150c08b058"
---

# Spec 0015 — spec:revise command

## Why

During a real `/speccraft:spec:new` session on 2026-06-09, the user asked Claude
to "re-analyze that spec, cross-check against the code and re-run Socratic
interview questioning on key details and implementation decisions."
`commands/spec/new.md` has two paths — Path A (pre-provided answers, edit
placeholders directly) and Path B (spec-author Socratic interview from scratch)
— and neither fits "re-analyze an existing draft." The model improvised the
flow that session, which surfaced two other issues that became specs 0011
(codegraph routing) and 0012 (CI close-gate bugs). The "/spec:revise should be
its own command" thread has been carried forward unresolved across three
subsequent specs.

The gap matters because specs evolve mid-life: cross-model review surfaces
gaps, planning surfaces ambiguity in acceptance criteria, and code drifts
underneath in-flight specs. Today the only repair mechanisms are (a) hand-edit
the spec.md and re-run `/spec:review`, which leaves no audit trail of what
changed and why, and (b) the "mid-implementation amendment" convention from
spec 0013, which only applies to in-progress specs and is explicitly distinct
in scope. Pre-implementation revision deserves a first-class command with the
same Socratic rigor as `/spec:new`.

## What

Add `/speccraft:spec:revise` as a sibling command under `commands/spec/`. The
command operates on the active spec, validates the spec is in a revisable
status (`draft`, `reviewed`, or `planned`), optionally runs a textual code
cross-check against `packages[]`, drives a Socratic re-interview via a new
`spec-reviser` subagent, archives stale downstream artifacts on real change,
bumps a `revision: N` counter in spec.md frontmatter, and drops the spec back
to `draft` status (a no-op for `draft`-source revises).

Specifically:

- **Target:** active spec only. If `active_spec` is empty, error. Pattern
  matches `/spec:review`, `/spec:plan`, `/spec:close`.
- **Status gate:** allowed source statuses are `draft`, `reviewed`, `planned`.
  Rejected: `in-progress` (use mid-implementation amendment convention from
  spec 0013), `closed`, `archived`.
- **Mechanism:** a new subagent `agents/spec-reviser.md`, sibling to
  `spec-author`. Tools: `[Read, Write, Edit, Bash]`. Does **not** include the
  Agent tool — it does not spawn Explore or codegraph subagents (per spec 0011
  resolution: speccraft does not own code-intel routing).
- **spec-reviser purpose.** The subagent re-runs the Socratic interview
  against the existing spec.md content (not a blank template), surfacing
  ambiguity in acceptance criteria, scope creep, untestable assertions, and
  any drift items passed from the cross-check. It edits the spec body
  (sections `## Why`, `## What`, `## Acceptance criteria`, `## Out of scope`,
  `## Open questions`) and packages[] in frontmatter when scope changes
  warrant it. It **must not modify** `revision:`, `status:`, `id:`, or
  `created:` in the frontmatter — those are command-owned.
- **Code cross-check (optional):** if `packages[]` is non-empty, the command
  extracts identifier tokens from spec.md and runs grep against `packages[]`
  paths. Drift items are surfaced **inline** in the re-interview as
  `Q-DRIFT:`-prefixed questions (one per drift item) — see
  §Identifier-extraction rule and §spec-reviser output contract below. If
  `packages[]` is empty, the command prints
  `packages[] empty — skipping code cross-check` and proceeds with a pure
  Socratic re-interview.
- **packages[] field contract:** a YAML list of repo-relative paths. Each
  entry is either a directory (recursive grep) or a single file. Globs are
  not supported in v1. Empty list (`packages: []`) means no cross-check is
  performed and the command warns but proceeds.
- **Identifier-extraction rule:** the command scans `## What`, `## Acceptance
  criteria`, and `## Out of scope` in spec.md for tokens inside backtick spans
  (single-backtick or fenced code) that match the regex
  `[A-Za-z_][A-Za-z0-9_]{3,}` (at least 4 characters). Other prose words are
  ignored. This gives authors an explicit opt-in mechanism: a name appearing
  in backticks is checked; one appearing only in prose is not.
- **Cross-check execution:** for each extracted token, run a portable
  recursive grep over each entry in `packages[]`. For directory entries the
  canonical invocation is `find <pkg-path> -type f -print0 | xargs -0 grep -l
  <token>`; for single-file entries it is `grep -l <token> <pkg-path>`. Token
  matches are deduplicated across paths and across repeat tokens. Tokens with
  zero matches across all paths become drift items. The cross-check uses
  `grep` and `find` only (both available in the project's CI devcontainer and
  in standard Linux/macOS userlands); `ripgrep` is **not** used (not
  guaranteed in the host environment per existing conventions). The `-r` /
  `--include` flag combination from earlier drafts is not used because `-r`
  is a GNU extension and the `--include='*'` glob is a no-op against the
  default match set.
- **spec-reviser output contract:** for each drift item the command surfaces,
  the subagent must emit a line beginning with `Q-DRIFT:` (anchored at line
  start, no leading whitespace) when posing the drift question to the user.
  This is the structural anchor the e2e fixture greps for. Non-drift Socratic
  questions are unconstrained in shape.
- **Versioning:** `revision: N` in spec.md frontmatter. Pre-first-revise specs
  default to `revision: 0`. The field is required from this spec forward; if
  it is absent on a target spec, the **command** inserts `revision: 0`
  before the snapshot in step 3 of §Mechanism — never the spec-reviser
  subagent. Each successful revise call increments N by 1. The
  spec-reviser's prohibition on touching command-owned frontmatter
  (`revision:`, `status:`, `id:`, `created:`) is absolute; insertion of a
  missing `revision:` belongs to the command alone.
- **Mechanism (ordered steps).** The command executes in this order:
  1. Read `.speccraft/state.json` for `active_spec`. If empty, error.
  2. Read `specs/<active>/spec.md`. Validate `status:` is one of
     `draft|reviewed|planned`. Else error naming the offending status.
  2a. **Ensure `revision:` is present.** If the spec.md frontmatter has no
      `revision:` key, the command inserts `revision: 0` and writes spec.md
      back to disk before continuing. (The command, never the agent, owns
      this insertion.)
  3. **Snapshot.** Capture the full pre-revise content of spec.md (after the
     step-2a insertion if it happened) for the no-op diff in step 9.
  4. **Preflight archive paths.** Compute the source `revision` (treating
     missing as 0). Let `N_old = revision`. If source status is `reviewed`,
     check that `review-r<N_old>.md` does not exist. If source status is
     `planned`, additionally check `plan-r<N_old>.md` and
     `tasks-r<N_old>.md`. Any conflict → exit non-zero naming the conflicting
     archive path; modify nothing.
  5. **Preflight source artifacts.** If source status is `reviewed`, verify
     `review.md` exists. If source status is `planned`, verify all three
     (`review.md`, `plan.md`, `tasks.md`) exist. Any missing source → exit
     non-zero naming the missing file; modify nothing. (`draft` source has
     no source artifacts to check.)
  6. **Cross-check (optional).** If `packages: []` empty, print
     `packages[] empty — skipping code cross-check`. Else extract identifier
     tokens per the rule above and grep each across `packages[]`. Collect
     drift items.
  7. **Invoke spec-reviser** with: snapshot content, drift item list. Agent
     edits spec.md body (and packages[] if needed). Agent does not modify
     `revision:`, `status:`, `id:`, or `created:`.
  8. **Diff against snapshot.** Compare current spec.md content against the
     step-3 snapshot.
  9. **No-op branch.** If unchanged, print `no changes — spec unchanged` and
     exit zero without bumping revision, archiving artifacts, or changing
     status. A spec.md whose only delta is whitespace or terminal newline is
     also considered a no-op.
  10. **Real-change branch.** If changed:
      a. Set `revision: N_old + 1` in frontmatter.
      b. If source status was `reviewed`, rename `review.md` →
         `review-r<N_old>.md`. If source status was `planned`, additionally
         rename `plan.md` → `plan-r<N_old>.md` and `tasks.md` →
         `tasks-r<N_old>.md`.
      c. Set `status: draft` in frontmatter (no-op when source was already
         draft).
      d. Print next-step suggestion: `/speccraft:spec:review`.
- **`.speccraft/state.json` single-writer discipline preserved.** The revise
  command body does not directly write `.speccraft/state.json` — only the
  established single writer (`speccraft-state`, invoked from the
  PostToolUse hook) writes it. `active_spec` is **not modified** by revise.
  Session edit-tracking fields (`session.edited_*_files`) MAY change as a
  side effect of the spec-reviser agent invoking the Edit tool on spec.md
  — this is normal PostToolUse hook behaviour and is unrelated to revise's
  own contract. See the 2026-06-11 amendment below for the historical
  AC3/AC4 over-specification this clarifies.

## Acceptance criteria

1. Invoking `/speccraft:spec:revise` when the active spec's status is `closed`
   exits non-zero, prints an error naming the offending status, and modifies
   no files in `specs/<active>/`, `.speccraft/state.json`, or
   `.speccraft/index.md`. Same behavior for status `archived` and
   `in-progress` (each tested separately).
2. Invoking `/speccraft:spec:revise` when `active_spec` is empty in
   `.speccraft/state.json` exits non-zero, prints an error pointing to
   `/spec:new`, and modifies no files.
3. Running revise against a `draft` spec with `revision: 0` (or missing
   field), where the spec-reviser writes a real edit to spec.md body, results
   in: spec.md frontmatter `revision: 1` and `status: draft` (unchanged); no
   archive files created; no `review.md`/`plan.md`/`tasks.md` exist before
   or after; `.speccraft/state.json` `active_spec` field unchanged
   pre- and post-run (other session-tracking fields MAY change as a normal
   PostToolUse-hook side effect — see the 2026-06-11 amendment).
4. Running revise against a `reviewed` spec with `revision: 0` (or missing
   field), where the spec-reviser writes a real edit, results in: spec.md
   frontmatter `revision: 1` and `status: draft`; `review.md` renamed to
   `review-r0.md`; no `plan.md` or `tasks.md` archives created; index.md
   unchanged; `.speccraft/state.json` `active_spec` field unchanged
   pre- and post-run.
5. Running revise against a `planned` spec with `revision: 2`, where the
   spec-reviser writes a real edit, results in: spec.md frontmatter
   `revision: 3` and `status: draft`; `review.md` renamed to `review-r2.md`;
   `plan.md` renamed to `plan-r2.md`; `tasks.md` renamed to `tasks-r2.md`.
6. Running revise where the spec-reviser returns without modifying spec.md
   body (no-op) leaves frontmatter `revision` and `status` unchanged, leaves
   `review.md`/`plan.md`/`tasks.md` untouched, and prints
   `no changes — spec unchanged` to stdout. Verifiable by running revise
   twice in a row with no intervening edits.
7. Running revise on a spec with `packages: []` (empty array) prints
   `packages[] empty — skipping code cross-check` to stdout and still
   invokes the spec-reviser subagent for re-interview. Verifiable by
   capturing stdout and asserting both the warning text and that the
   subagent was invoked.
8. Running revise on a spec whose `## What` section contains the backtick
   span `` `NonexistentSymbolXYZ` ``, with `packages: ["commands/spec"]`,
   produces at least one stdout line matching the anchored regex
   `^Q-DRIFT:` in the spec-reviser's interview output. Verifiable via a
   fixture that seeds the spec body with a deliberately-absent identifier.
9. Running revise on a `reviewed` spec with `revision: 0` where
   `review-r0.md` already exists (e.g. from a prior partial run) exits
   non-zero, prints an error naming the conflicting archive path, modifies
   no files (spec.md, review.md, and `.speccraft/state.json` all
   byte-identical pre- and post-run), and does not invoke the spec-reviser.
10. Running revise on a `planned` spec where `tasks.md` is missing (but
    spec.md and review.md and plan.md exist) exits non-zero, prints an
    error naming the missing source file, modifies no files, and does not
    invoke the spec-reviser.
11. The file `agents/spec-reviser.md` exists with YAML frontmatter
    containing: `name: spec-reviser`, a non-empty `description:` string,
    `tools: [Read, Write, Edit, Bash]`, and a `model:` key. The tools list
    contains no `Agent` entry. (Tested by reading the file and asserting
    each frontmatter field's presence and shape — matches sibling
    `agents/spec-author.md` contract.)
12. The file `commands/spec/revise.md` exists with YAML frontmatter
    containing: a `description:` string, an `argument-hint:` string
    (revise takes no arguments — the hint is `""` or omitted, mirroring
    sibling `commands/spec/close.md`), and `allowed-tools:` declaring the
    tools the command body uses. This shape matches the de-facto contract
    of all eight existing files under `commands/spec/`; this spec
    consciously tightens conventions.md §"Markdown frontmatter" (which
    documents only `description:` as mandatory) to the sibling-observed
    triple. A follow-up amendment to conventions.md is in scope for the
    `/spec:close` memory-keeper pass on this spec.

## Out of scope

- Revising specs in status `closed` or `archived` (immutable rule preserved).
- Revising in-progress specs (the spec-0013 "mid-implementation amendment"
  convention covers this case and intentionally remains distinct).
- Auto-triggering revise from any signal (CI, drift detector, scheduled).
  v1 is strictly user-invoked.
- A `--undo` flag or any rollback mechanism beyond `git checkout`.
- Codegraph or LSP-backed semantic cross-check (per spec 0011: speccraft does
  not own code-intel routing). Cross-check is textual grep only.
- Spawning Explore or any code-search subagent from within spec-reviser.
- Cross-revision diff rendering in spec.md (no `## Revision history`
  section; archived files plus git are the audit trail).
- Revising a non-active spec by argument (e.g., `/spec:revise 0007`). User
  must re-set active_spec first to maintain consistency with sibling
  commands.
- Auto-running `/spec:review` after revise completes.
- Glob expansion in `packages[]` entries (directories and individual file
  paths only in v1).
- CamelCase or function-shaped identifier extraction from prose. Only tokens
  inside backtick spans are checked.
- Modifying `.speccraft/state.json`, `.speccraft/index.md`, or any
  `.speccraft/` memory file from within revise.
- Partial-failure rollback beyond preflight. Once step 10 begins, an
  interrupted run leaves the spec dir in whatever state the OS produced;
  `git checkout` is the recovery path.

## Open questions

_none_

## Amendment (2026-06-11) — AC3/AC4 state.json predicate corrected

**Trigger.** CI run [27314550595](https://github.com/DCSTOLF/speccraft/actions/runs/27314550595)'s
`e2e-devcontainer` job failed at `tests/e2e/run.sh` step `[5/13]
/speccraft:spec:revise`. The new assertion
`[ "$STATE_BEFORE" = "$STATE_AFTER" ]` (full-file byte-compare of
`.speccraft/state.json`) was tripped by the PostToolUse hook's normal
`speccraft-state track-edit` call when the spec-reviser agent issued
`Edit spec.md` during revise. The model log confirmed the revise contract
otherwise behaved correctly (status flipped, archive renamed, revision
bumped, next-step suggestion printed).

**Fix.** AC3 and AC4 originally asserted
"`.speccraft/state.json` byte-identical pre- and post-run." That predicate
was over-specified: the actual contract revise needs to preserve is
**single-writer discipline + active_spec stability**, not whole-file byte
equality. PostToolUse-hook session tracking is orthogonal and correct
behaviour. The amendment rewords AC3 and AC4 to assert that `active_spec`
is unchanged, and updates `tests/e2e/run.sh`'s assertion to a `jq`-based
compare of the `.active_spec` field only.

**Rationale for folding in vs spinning off.** All three mid-amendment
criteria from spec 0013 §"Mid-implementation amendment" hold: strictly
bounded edit (two AC rewordings + one assertion change in `run.sh`); main
CI is red until it lands (this spec's own close gate); theme overlap
(this IS spec 0015). The alternative — filing spec 0016 to fix spec
0015's own ACs — would carry red main CI through a second new+plan+impl
cycle for a one-line assertion change.

**Scope deltas.**
- spec.md §What state.json bullet rewritten.
- spec.md AC3 wording: byte-identical → `active_spec` field unchanged.
- spec.md AC4 wording: same.
- AC9 wording unchanged (preflight-collision path exits before any Edit
  call, so byte-identical there remains accurate).
- `tests/e2e/run.sh` step `[5/13]` assertion changed from full-file
  byte-compare to `jq -r '.active_spec'` compare.
- New tasks.md entry T18 captures the amendment.
- bats tests untouched — they exercise helper functions directly without
  the PostToolUse hook, so they never saw the false-positive shape.

**Convention precedent.** Spec 0013's T6 (CI workflow hooks: job fix
post-T1-T5 push) is the canonical example. This amendment matches that
shape — a bounded post-push fix folded into the active spec rather than
spun out.
