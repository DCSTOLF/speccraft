---
spec: "0047"
reviewers: [codex, claude-p]
quorum: 1
verdict: approve-with-comments
generated: 2026-08-06T20:45:00Z
rounds: 2
---

# Review — 0047 Per-task done-means contract and completion gate

## Verdicts

| reviewer | verdict |
| --- | --- |
| codex | changes-requested |
| claude-p | approve-with-comments |

Quorum (1 approve-or-approve-with-comments) is met, but codex's
`changes-requested` and the convergence below justify one revision + re-review
round before planning.

## Process note — false quorum in round 1 (dispatch defect, not a spec finding)

The first dispatch returned **byte-identical** output from both reviewers. Cause:
both `aux-delegator` invocations wrote to the same unqualified temp path
(`/tmp/0047-review-output.txt`); only one such file exists on disk, with a single
mtime. The second delegator reported the first's bytes as its own verdict. This
was caught by md5-comparing the two returned bodies, and claude-p was re-run
directly with an isolated output path — the verdicts above are from that
corrected run and are genuinely independent.

This is a defect in speccraft itself, not in this spec: parallel aux review has
no per-agent temp-file namespacing, so a collision silently manufactures a fake
second opinion. Cross-model review is the plugin's headline feature, and a false
quorum is its worst possible failure mode. **Filed as a follow-up spec** — see
§Follow-ups.

## Convergent findings (both reviewers, independently)

1. **AC9 self-contradicts on gate ordering.** §What #4 puts the gate at close.md
   step 2 (before the diff); AC9 says it "does not fire before the diff is
   computed". An implementer must guess. → RESOLVED: gate fires at step 2, before
   the diff and before `memory-keeper`.

2. **Executable-predicate runtime is wholly unspecified** — shell (`sh -c` vs
   `bash -c`), CWD, inherited environment, stdout/stderr capture, and the timeout
   env var *name* and default. AC6 has the fallback matrix but not the identifier.
   Both cite `SPECCRAFT_LEDGER_LOCK_TIMEOUT` / `parseLockTimeout` (spec 0045) as
   the precedent to mirror. → RESOLVED: new §Predicate execution.

3. **AC11 contradicts the spec's own thesis.** It adds a prose instruction to
   `memory-keeper` — the exact instruction-layer mechanism §Why identifies as
   speccraft's chronic weakness. → RESOLVED: AC11 **removed** from this spec. The
   unwired-knob case is handled by an executable predicate instead
   (`$ grep -q KNOB definer && grep -q KNOB reader`), which is mechanical. A
   sharpened mechanical version is deferred to its own spec.

4. **Override budget / `run()` seam not named** (convention, spec 0035/0036).
   A new `speccraft-state` subcommand must ride the `run()` seam in
   `tools/cmd/speccraft-state/` to keep budget 0; an exported
   `tools/internal/speccraft` symbol would cost one. → RESOLVED: stated as AC,
   budget 0.

5. **New `contract:` frontmatter key must route through the existing shared
   parser** (`parseFrontmatterBlock`, spec 0036 one-parser invariant) rather than
   accreting a second frontmatter reader. → RESOLVED: stated as AC.

6. **Grammar underspecified.** codex: placement/indent of `done:`, coexistence
   with sub-checkboxes, parent-vs-child precedence. claude-p sharpens it into a
   concrete AC3 conflict: a legacy `tasks.md` containing an indented plain bullet
   would be read as a malformed sub-checkbox and fail the "legacy files stay
   clean" criterion. → RESOLVED: new §Grammar pins the sub-checkbox regex; a
   bullet whose `TN.x` prefix does not match its parent is prose, not a
   sub-checkbox.

## Single-reviewer findings adopted

- **codex** — version the marker as `contract: done-means-v1` from day one, so
  grammar evolution never silently changes the semantics of an existing key.
- **codex** — pin AC3 to a real `tests/hooks/tasks-verify.bats` fixture asserting
  clean exit over every `specs/**/tasks.md` and `specs/.archive/**/tasks.md`.
- **codex (stderr secondary pass)** — *the strongest finding in the round*: close.md
  step 2's blanket-approval path ("approve all" / non-interactive) would let the
  new gate be bypassed silently, reproducing exactly the failure mode the spec
  exists to prevent — in exactly the mode the field agent was running in. →
  RESOLVED: a dedicated AC requires a distinct explicit token to bypass, and the
  bypass is recorded.
- **codex (stderr secondary pass)** — require `done:` on **every** task in a
  contracted file, not only `[x]` ones, so omission is caught at plan time rather
  than after completion. → ADOPTED into AC2.
- **claude-p** — exit-code taxonomy: `0` clean, `1` violations, `2` malformed, so
  the runbook can branch (malformed is a bug to fix; a violation is a decision).
- **claude-p** — AC12's "read-only" over-promises: `tasks-verify`'s own logic is
  read-only, but a predicate is arbitrary shell and may have side effects. State
  the split.
- **claude-p** — add `related-specs: 0035, 0036, 0045`.

## Not adopted

- **codex** — a source-scan meta-test pinning the producer prose in
  `tdd-planner.md` / `spec-format/SKILL.md`. Reasonable, but it pins *wording*
  rather than behavior and would fire on benign rewording. AC10 keeps the
  requirement without the brittle assertion.

---

# Round 2 — scoped re-review of the deltas

| reviewer | verdict |
| --- | --- |
| codex | changes-requested |
| claude-p | approve-with-comments |

Dispatched directly with isolated output paths after the round-1 collision;
distinct md5s confirm independence. claude-p's regression sweep found every
round-1 finding resolved and no regressions against the settled criteria.

## Round-2 findings, all adopted

1. **§Grammar contradicted AC8** (codex; claude-p's suffix concern is the same
   seam). §Grammar said an indented checkbox not matching a parent is prose; AC8
   said a sub-checkbox with a nonexistent parent is malformed. → Split recognition
   from resolution: a syntactically valid `T<digits>.<suffix>` bullet **is** a
   sub-checkbox, and an unresolvable parent is exit 2; anything not matching the
   shape is prose at any depth.
2. **Empty and duplicate `done:` lines were permitted** (codex) — an empty one
   would satisfy AC2 while articulating nothing. → Exactly one non-empty `done:`
   per task block; block boundary pinned (next column-0 task, next heading, EOF);
   empty/duplicate is exit 2.
3. **Timeout killed only the `sh` leader** (codex). Grandchildren holding the
   captured pipes would hang the verifier on exactly the runaway predicate the
   timeout exists to bound. → Process-group kill, with a forking-child test.
4. **AC10 bypass was unspecified** (codex + claude-p). → Literal token
   `SKIP-TASKS-VERIFY`; exit 2 never bypassable; deterministic
   `## Skipped task verification` section in `changelog.md`. close.md's existing
   blanket-approval sentence is now quoted verbatim in the AC.
5. **Unbounded `detail`** (both). → 4 KiB cap with a visible truncation marker.
6. **Suffix charset / nesting** (claude-p). → `[A-Za-z0-9]+`, one level only.
   claude-p proposed `[a-z]+`; **that would have been wrong** — see the audit.
7. **`done:` indent ambiguous without sub-checkboxes** (claude-p). → Pinned at
   exactly 2 spaces.
8. **`/bin/sh` drift and the predicate trust model** (claude-p). → Absolute path,
   POSIX-only constraint, and a trust-level sentence in §Boundary.
9. **AC11's deferred-reuse cost** (claude-p) and **AC12's vague "invariant holds"**
   (claude-p). → Both stated concretely.
10. **`domains:` undocumented in spec-format** (claude-p). → Folded into AC13,
    since that skill is being edited anyway.

## Empirical audit (settles claude-p's AC1×AC3 concern)

claude-p flagged that AC1 fires unconditionally and could collide with AC3's
"legacy files stay clean". Audited all 43 existing `tasks.md` files rather than
deferring it to RED time:

- `specs/.archive/0016-.../tasks.md` **already uses** `T1.1`–`T1.10` sub-checkboxes
  and a deeper `- [x] #1 …` level, and carries both `id:` and `spec:` frontmatter
  keys.
- Its `T5` is an unticked parent with unticked children; four other archived files
  carry unticked tasks. **No `[x]`-parent / `[ ]`-child pair exists anywhere**, so
  AC1 does not fire and AC3 holds.
- The multi-digit `T1.10` is why the suffix charset is `[A-Za-z0-9]+`; codex's and
  claude-p's alpha-only suggestion would have failed AC3 on a real file.

This audit is recorded in AC3 so the fixture is demonstrably non-vacuous.

## Stopping decision — 2 rounds

Round 1 produced six convergent design findings; round 2 produced one real
contradiction plus a set of pin-a-constant refinements, all folded above. Nothing
remaining is a design question — the residue is exactly the "fold at plan time
rather than spend another round" case the field report identified. **Stopping at
round 2** and proceeding to plan.

## Follow-ups (separate specs)

- **aux-delegator temp-file collision → false quorum.** Per-agent output path
  namespacing for parallel review dispatch, plus a caller-side identical-output
  detector. Highest priority of the three; this round demonstrates the failure.
- **Mechanical definition-without-reader check** (the dropped AC11), e.g. new
  top-level identifiers under the spec's declared `packages:` with no reference
  outside their declaring file.
- The four other items triaged from the same field report (plan corrections,
  index.md byte cap, consolidation routing seed + skip marker, review stopping
  rule).
