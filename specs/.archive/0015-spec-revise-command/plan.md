---
spec: "0015"
status: planned
strategy: tdd
---

# Plan — 0015 spec:revise command

## Overview and helper-extraction decision

Spec 0015 declares `packages: ["commands/spec", "agents"]` — two pure-Markdown
directories with zero `*_test.go` siblings. The AC set spans three distinct
test layers:

- **AC11, AC12** (file-presence + frontmatter shape) — natural fit for a
  spec-local `verify.sh` grep-assertion oracle (conventions §"Grep-assertion
  oracle for doc-only specs"). Cheap, RED-friendly, no CI wiring needed.
- **AC1, AC2, AC9, AC10** (preflight error paths: status gate, missing
  active spec, archive-collision preflight, missing-source preflight) — these
  are pure-Bash decisions with no model in the loop. The cheapest oracle that
  satisfies the RED→GREEN rule is a `bats` suite that sources the preflight
  helpers as shell functions.
- **AC3, AC4, AC5, AC6, AC7, AC8, AC13** (real revise flow, including
  spec-reviser agent edits and Q-DRIFT emission) — depend on `claude -p`
  driving the subagent. Belong in `tests/e2e/run.sh` (credit-gated
  `e2e-devcontainer` job).

The bats layer is only viable if the preflight Bash logic is extracted into
a sourceable helper file. The plan picks **option (a) from the planner
brief**: a new file `commands/spec/revise.lib.sh` colocated with the command
Markdown body, sourced both by `commands/spec/revise.md` at command runtime
and by `tests/hooks/spec-revise-preflight.bats` at test time.

**Rationale for (a) over (b) and (c):**

- **(b) extend `tests/e2e/lib.sh`.** That file is documented (spec 0014,
  conventions §"Shared assertion helpers") as the **assertion-helper**
  location for the e2e harness. Putting command-runtime preflight logic
  there would be a layering violation — the command body would source a
  test-tree file, inverting the dependency direction. Future readers
  inspecting `tests/e2e/lib.sh` to understand its scope would see two
  unrelated concerns.
- **(c) no extraction; rely on `tests/e2e/run.sh` only.** Pushes every
  preflight path to the credit-gated lifecycle job. Spec 0011's e2e budget
  concern (cited in review.md) directly argues against this. AC1's status
  gate has three sub-cases (`closed`, `archived`, `in-progress`), AC9
  needs a pre-seeded archive collision, AC10 needs a missing-source
  scenario — each is one bats test costing zero credits versus one
  lifecycle pass costing real budget.
- **(a) new `commands/spec/revise.lib.sh`.** Colocates the helper with its
  one runtime caller, keeps the test-tree concern out of the source tree,
  and follows the precedent of "one binary per subdirectory" by analogy
  (one library per command that needs testable shell). The shape is novel
  for this repo (`commands/spec/*` has only been Markdown until now), so
  a §Conventions note at close is required — see T17.

The §Mechanism evolves: the `commands/spec/revise.md` body becomes a thin
shell driver that sources `revise.lib.sh` and calls named functions
(`preflight_status_gate`, `preflight_archive_collisions`,
`preflight_source_artifacts`, `ensure_revision_field`, `extract_identifiers`,
`run_cross_check`, `frontmatter_integrity_check`, `compute_archive_renames`,
`bump_revision`). Each function is independently testable from bats. This
satisfies "every GREEN preceded by RED" — bats tests for each helper fail
before the function exists.

## Test-first sequence

### Step 1 — verify.sh oracle for spec-reviser.md and revise.md frontmatter (RED)

- Add `specs/0015-spec-revise-command/verify.sh` (executable, `set -euo
  pipefail`, resolves repo root from `${BASH_SOURCE[0]}`):
  - **AC11 checks** for `agents/spec-reviser.md`:
    - Labelled `grep` invocation: file must exist.
    - Frontmatter must contain `^name: spec-reviser$`.
    - Frontmatter must contain `^description:` followed by a non-empty
      string (regex: `^description: .+`).
    - Frontmatter must contain `^tools:.*\[.*Read.*,.*Write.*,.*Edit.*,.*Bash.*\]`
      (or equivalent multi-line shape — both single-line and YAML-list
      shapes are accepted; see T2 for the canonical written form).
    - Tools list must NOT contain `Agent` (regex: `tools:.*Agent` must
      return zero matches).
    - Frontmatter must contain `^model: ` followed by a non-empty token.
  - **AC12 checks** for `commands/spec/revise.md`:
    - File must exist.
    - Frontmatter must contain `^description: .+`.
    - Frontmatter must contain `^argument-hint:` (value may be `""` or
      omitted — match `^argument-hint:` OR explicitly accept its absence
      per spec text "the hint is `""` or omitted, mirroring sibling
      `commands/spec/close.md`"; the verify.sh shape is "present-and-empty
      OR absent" — implemented as: if `argument-hint` is present its
      value must match `""` or be empty after the colon).
    - Frontmatter must contain `^allowed-tools:` with `Read`, `Write`,
      `Edit`, and `Bash`.
  - Paired-absence-and-presence per the conventions §grep oracle
    pattern: e.g. "spec-reviser.md must not list Agent" is paired with
    "spec-reviser.md must list at least one tool" so the absence isn't
    satisfied by an empty tools list.
- Tests fail: `agents/spec-reviser.md` does not exist; `commands/spec/revise.md`
  does not exist. Every grep against those files fails (file not found),
  every fails-counter increment fires.

### Step 2 — Write agents/spec-reviser.md (GREEN for AC11)

- Implement `agents/spec-reviser.md` with YAML frontmatter:
  ```yaml
  ---
  name: spec-reviser
  description: "Re-runs Socratic interview against an existing spec.md. Use during /speccraft:spec:revise."
  tools: [Read, Write, Edit, Bash]
  model: opus
  ---
  ```
- Body sections (load-bearing for downstream ACs):
  - **Purpose** — paraphrase §spec-reviser purpose from spec.md: re-run the
    Socratic interview against existing spec content, surface ambiguity in
    ACs, scope creep, untestable assertions, and drift items.
  - **Forbidden edits** — explicit prose: "you must NEVER modify the
    following frontmatter keys: `revision:`, `status:`, `id:`, `created:`.
    These are command-owned. The command will reject your output if these
    keys change."
  - **Output format / Q-DRIFT contract** — explicit required-token
    instruction (per review.md "Q-DRIFT structural anchor must be pinned in
    the prompt body"): "When posing a drift question surfaced by the
    command's cross-check, your line MUST begin with the literal token
    `Q-DRIFT:` anchored at column 0, no leading whitespace. The command's
    e2e fixture greps for `^Q-DRIFT:` as a structural anchor and will fail
    if you reword the prefix."
  - **Interview sequence** — mirror `agents/spec-author.md`'s sequence
    but oriented around editing the existing spec, not drafting fresh.
- `bash specs/0015-spec-revise-command/verify.sh` AC11 checks pass.

### Step 3 — Bats RED for preflight helpers (RED)

- Add `tests/hooks/spec-revise-preflight.bats`:
  - `setup()`: create `$TEST_REPO` with `.speccraft/state.json` (empty
    `active_spec`), `specs/0099-fixture/spec.md` (configurable shape),
    `export REVISE_LIB="$PLUGIN_DIR/commands/spec/revise.lib.sh"`.
  - `@test "preflight_status_gate rejects closed"` — seeds a spec.md with
    `status: closed`, sources `$REVISE_LIB`, calls `preflight_status_gate
    specs/0099-fixture/spec.md`, asserts exit non-zero and stderr names
    "closed".
  - `@test "preflight_status_gate rejects archived"` — same shape, status
    `archived`.
  - `@test "preflight_status_gate rejects in-progress"` — same shape,
    status `in-progress`.
  - `@test "preflight_status_gate accepts draft"` — status `draft`,
    expects exit zero.
  - `@test "preflight_status_gate accepts reviewed"` — exit zero.
  - `@test "preflight_status_gate accepts planned"` — exit zero.
  - `@test "preflight_active_spec_set errors on empty active_spec"` —
    state.json has empty `active_spec`, expects exit non-zero with
    stderr mentioning `/spec:new`.
  - `@test "ensure_revision_field inserts revision: 0 when missing"` —
    seeds spec.md without `revision:`, asserts function rewrites file
    inserting `revision: 0`.
  - `@test "ensure_revision_field is idempotent when revision present"` —
    seeds spec.md with `revision: 2`, asserts file byte-identical
    pre/post.
  - `@test "preflight_archive_collisions reviewed-r0 conflict"` — seeds
    `review-r0.md` alongside a `reviewed`/`revision: 0` spec, asserts
    non-zero exit naming the conflicting path.
  - `@test "preflight_archive_collisions planned-r2 plan-conflict"` —
    seeds `plan-r2.md` alongside a `planned`/`revision: 2` spec (review
    archive absent), asserts non-zero exit naming `plan-r2.md`.
  - `@test "preflight_archive_collisions clean reviewed exits zero"` —
    no archives present, exit zero.
  - `@test "preflight_source_artifacts reviewed missing review.md"` —
    seeds `reviewed` spec with no `review.md`, exits non-zero naming
    `review.md`.
  - `@test "preflight_source_artifacts planned missing tasks.md"` —
    seeds `planned` spec with `review.md` + `plan.md` but no
    `tasks.md`, exits non-zero naming `tasks.md`.
  - `@test "preflight_source_artifacts draft requires nothing"` — draft
    source with no artifacts, exit zero.
- Tests fail: `commands/spec/revise.lib.sh` does not exist, every
  `source "$REVISE_LIB"` call fails with "file not found", every assertion
  evaluates against an unset function and bats marks the test failed.

### Step 4 — Implement preflight helpers in revise.lib.sh (GREEN for step 3)

- Implement `commands/spec/revise.lib.sh`:
  - `#!/usr/bin/env bash` + `set -euo pipefail` per conventions §Bash.
  - `preflight_status_gate <spec.md path>` — greps the spec frontmatter
    for `^status:`, validates the value is in
    `{draft, reviewed, planned}`, errors with stderr naming the offending
    status otherwise.
  - `preflight_active_spec_set <state.json path>` — `jq -r
    '.active_spec // ""'`, errors if empty with stderr "no active spec —
    run /speccraft:spec:new first" (verbatim per spec §Mechanism step 1).
  - `ensure_revision_field <spec.md path>` — checks for `^revision:` in
    frontmatter; if absent, inserts `revision: 0` immediately after the
    `created:` line (or before the closing `---` if `created:` absent)
    using `awk` for portability. Idempotent.
  - `preflight_archive_collisions <spec dir> <source status> <N_old>` —
    computes the candidate archive set per spec §Mechanism step 4 and
    errors on any conflict.
  - `preflight_source_artifacts <spec dir> <source status>` — checks
    `review.md`/`plan.md`/`tasks.md` per spec §Mechanism step 5.
- All step-3 bats tests pass when run via `bats tests/hooks/`.

### Step 5 — Bats RED for cross-check helpers (RED)

- Extend `tests/hooks/spec-revise-preflight.bats`:
  - `@test "extract_identifiers picks single-backtick tokens >=4 chars"` —
    seeds spec.md with `` `Foo` `` (3 chars, ignored), `` `FooBar`,
    `` `MyToken`, `` `xy` ``, asserts function emits `FooBar` and
    `MyToken` on stdout, nothing else.
  - `@test "extract_identifiers dedups repeated tokens"` — seeds spec.md
    with the same token in 5 backtick spans, asserts function emits one
    line.
  - `@test "extract_identifiers scope limited to What / AC / OOS sections"` —
    seeds a token in `## Why` (must be ignored) and another in `## What`
    (must be picked).
  - `@test "extract_identifiers excludes fenced code blocks"` — seeds a
    token only inside a triple-backtick fenced block; asserts ignored.
    (Per review.md §Plan-time refinements "Fenced-code-block extraction
    scope": fenced blocks are EXCLUDED in v1 because they commonly hold
    example identifiers the author never meant to assert.)
  - `@test "validate_packages rejects glob entries"` — seeds spec.md
    `packages: ["foo/*.go"]`, expects non-zero exit naming "glob".
  - `@test "validate_packages rejects escape-path entries"` — seeds
    `packages: ["../etc/passwd"]`, expects non-zero exit naming
    "escape" or "outside repo".
  - `@test "validate_packages rejects non-string entries"` — seeds
    `packages: [{"path": "foo"}]`, expects non-zero exit naming "non-string".
  - `@test "validate_packages rejects nonexistent paths"` — seeds
    `packages: ["does/not/exist"]`, expects non-zero naming the path.
  - `@test "validate_packages accepts clean dirs and files"` — seeds
    `packages: ["commands/spec", "agents/spec-author.md"]`, expects
    zero exit.
  - `@test "run_cross_check warns and skips when packages empty"` —
    spec.md has `packages: []`, asserts stdout contains
    `packages[] empty — skipping code cross-check`.
  - `@test "run_cross_check reports missing tokens as drift items"` —
    seeds spec.md with `` `NonexistentSymbolXYZ` `` token and
    `packages: ["commands/spec"]`, asserts stdout contains one line
    naming `NonexistentSymbolXYZ`.
  - `@test "run_cross_check omits tokens that match in at least one path"` —
    seeds spec.md with `` `description` `` token (which exists in
    `commands/spec/new.md`) and `packages: ["commands/spec"]`, asserts
    `description` is NOT emitted as drift.
- Tests fail: `extract_identifiers`, `validate_packages`, `run_cross_check`
  functions are not yet defined in revise.lib.sh.

### Step 6 — Implement extraction / packages-validation / cross-check helpers (GREEN for step 5)

- Extend `commands/spec/revise.lib.sh`:
  - `extract_identifiers <spec.md path>` — uses `awk` to walk the file,
    tracks current `## Heading`, only emits inside sections
    `## What`, `## Acceptance criteria`, `## Out of scope`. Strips
    fenced-code-block content (toggle on `^```` lines). Extracts tokens
    matching `[A-Za-z_][A-Za-z0-9_]{3,}` inside single-backtick spans
    (`` `...` `` pairs on the same line). Pipes through `sort -u` for
    dedup.
  - `validate_packages <spec.md path>` — uses `yq` (already available in
    devcontainer) to parse the YAML list; rejects entries containing
    glob chars (`*`, `?`, `[`, `]`), entries with `..`, entries that
    are not strings, and entries that don't resolve to existing files
    or directories under the repo root.
  - `run_cross_check <spec.md path>` — orchestrates: if `packages: []`,
    print the skip warning and return zero. Else call
    `validate_packages`, then `extract_identifiers`, then for each
    token run a portable `grep`: for directory entries,
    `find <pkg> -type f -print0 | xargs -0 grep -l "$token"`; for
    file entries, `grep -l "$token" <pkg>`. Tokens with zero matches
    across all paths emit on stdout.
- All step-5 bats tests pass.

### Step 7 — Bats RED for frontmatter integrity and snapshot/diff helpers (RED)

- Extend `tests/hooks/spec-revise-preflight.bats`:
  - `@test "frontmatter_integrity_check fails when revision changed"` —
    snapshots a spec.md, then edits its frontmatter to bump revision,
    asserts function exits non-zero naming `revision`.
  - `@test "frontmatter_integrity_check fails when status changed"` —
    same shape, status changed by agent.
  - `@test "frontmatter_integrity_check fails when id changed"` — same
    shape.
  - `@test "frontmatter_integrity_check fails when created changed"` —
    same shape.
  - `@test "frontmatter_integrity_check passes when only body changed"` —
    snapshots, edits body only, asserts exit zero.
  - `@test "diff_against_snapshot detects byte-identical as no-op"` —
    snapshots a spec.md, no edits, asserts function returns "no-op"
    signal (exit zero with stdout `no-op` or equivalent named return).
  - `@test "diff_against_snapshot treats trailing newline diff as no-op"` —
    snapshots, post-state differs only in terminal newline, asserts
    no-op.
  - `@test "diff_against_snapshot treats trailing-horizontal-whitespace
     diff as no-op"` — snapshots, post-state has trailing spaces on a
     line, asserts no-op. (Per review.md: implementation uses `diff -B`
     plus an explicit trailing-whitespace strip; the bats test pins the
     exact predicate.)
  - `@test "diff_against_snapshot reports real-change for body edit"` —
    snapshots, post-state has a real word change, asserts function
    returns "changed" signal (non-zero or stdout `changed`).
- Tests fail: `frontmatter_integrity_check`, `diff_against_snapshot`
  functions don't exist yet.

### Step 8 — Implement frontmatter integrity and diff helpers (GREEN for step 7)

- Extend `commands/spec/revise.lib.sh`:
  - `snapshot_spec <spec.md path> <snapshot dir>` — copies the spec.md
    to `$snapshot_dir/spec.md.pre` and extracts the four command-owned
    frontmatter fields into `$snapshot_dir/frontmatter.pre` as a sorted
    `key=value` text file.
  - `frontmatter_integrity_check <spec.md path> <snapshot dir>` —
    re-extracts the four fields from the current spec.md, compares
    against `$snapshot_dir/frontmatter.pre`, exits non-zero naming the
    changed key on any delta.
  - `diff_against_snapshot <spec.md path> <snapshot dir>` —
    normalisation algorithm: strip trailing horizontal whitespace
    (`sed 's/[[:space:]]*$//'`) and trailing newlines from both
    `spec.md.pre` and current `spec.md`; `cmp -s` the results; emit
    `no-op` on match, `changed` on differ. Returns exit zero in both
    cases; the dispatch in the command body branches on the stdout
    value. (Picked over `diff -wB` because `diff -w` would also collapse
    inner-line whitespace differences that genuinely indicate intentional
    edits like changing `revision: 0` to `revision: 10`.)
- All step-7 bats tests pass.

### Step 9 — Bats RED for archive-rename and revision-bump helpers (RED)

- Extend `tests/hooks/spec-revise-preflight.bats`:
  - `@test "bump_revision increments N to N+1"` — seeds spec.md with
    `revision: 5`, calls function, asserts file now has `revision: 6`.
  - `@test "bump_revision sets status: draft on reviewed source"` —
    seeds spec.md with `status: reviewed`, asserts result has
    `status: draft`.
  - `@test "bump_revision sets status: draft on planned source"` — same.
  - `@test "bump_revision leaves status: draft on draft source"` —
    no-op for status field.
  - `@test "archive_rename reviewed renames review.md only"` — seeds
    spec dir with `review.md`/`plan.md`/`tasks.md`, source status
    `reviewed`, `N_old=0`, asserts only `review.md` was renamed to
    `review-r0.md`; `plan.md`/`tasks.md` untouched.
  - `@test "archive_rename planned renames all three"` — same seed,
    source `planned`, `N_old=2`, asserts all three renamed with the
    `-r2` suffix.
  - `@test "archive_rename draft renames nothing"` — same seed, source
    `draft`, asserts no renames.
- Tests fail: `bump_revision`, `archive_rename` don't exist.

### Step 10 — Implement archive-rename and revision-bump helpers (GREEN for step 9)

- Extend `commands/spec/revise.lib.sh`:
  - `bump_revision <spec.md path> <source status>` — increments
    `^revision: N` in-place using `sed` / `awk`. If source status is
    `reviewed` or `planned`, additionally sets `^status:` to `draft`.
  - `archive_rename <spec dir> <source status> <N_old>` — performs the
    `git mv`-equivalent renames per spec §Mechanism step 10b. Uses `mv`
    (the command doesn't assume git state). Returns zero on success,
    non-zero on any rename failure.
- All step-9 bats tests pass.

### Step 11 — Write commands/spec/revise.md command body (GREEN for AC12 + integrate helpers)

- Implement `commands/spec/revise.md` with:
  - YAML frontmatter matching the sibling contract observed in
    `commands/spec/close.md`:
    ```yaml
    ---
    description: "Re-run Socratic interview on the active spec; archive stale artifacts, bump revision, return to draft."
    argument-hint: ""
    allowed-tools: ["Read", "Write", "Edit", "Bash"]
    ---
    ```
  - Body that walks Claude through the §Mechanism ordered steps,
    sourcing the helper:
    ```bash
    source "$CLAUDE_PLUGIN_ROOT/commands/spec/revise.lib.sh"
    ```
    Each step in §Mechanism becomes one named function call. Step 7
    (the spec-reviser invocation) is rendered as instructions for
    Claude to invoke the subagent and pass the snapshot content + drift
    list; Claude's tool use is bounded by the frontmatter-integrity
    re-check (`frontmatter_integrity_check`) immediately after.
  - Final step prints the next-step suggestion exactly as
    `/speccraft:spec:review` (per spec §Mechanism step 10d, for AC13
    coverage in step 13 below).
- `bash specs/0015-spec-revise-command/verify.sh` AC12 checks now pass.

### Step 12 — Refactor: extract bats setup helper (optional but recommended)

- The bats file accumulated ~30+ tests by step 11. Many share the same
  spec.md seed template (frontmatter + `## What` + `## Acceptance
  criteria` sections). Extract a `seed_spec()` helper at the top of
  `tests/hooks/spec-revise-preflight.bats` taking
  `(id, status, revision, packages_yaml, what_body)` and producing a
  canonical spec dir. Each `@test` becomes a 2-line setup + 1-line
  assertion. All existing bats tests still pass.

### Step 13 — E2E RED for revise lifecycle integration (RED)

- Edit `tests/e2e/run.sh` step counter: existing flow has 11 numbered
  steps; the revise step inserts between `[7/11] /speccraft:spec:close`
  and `[8/11] Helper unit tests`. Renumber to `[N/12]`. The natural
  position is AFTER the original close — but the revise command operates
  on the active spec, and closing clears active_spec. Place the revise
  exercise BEFORE close instead: insert the new step between
  `[5/9] /speccraft:spec:plan` and `[6/9] TDD invariant`, renumbering
  downstream. New step number: `[6/12] /speccraft:spec:revise`. (The
  comment block in `run.sh` currently says `[N/9]` despite the help text
  saying 11 steps; honor the actual on-disk numbering as part of this
  edit.)
- New step body:
  - Invoke `run_claude "/speccraft:spec:revise. Edit the spec.md What
    section to add a deliberately-absent identifier in backticks:
    \`NonexistentSymbolXYZ\`. Also tighten AC1 wording." 06-revise.log`.
  - Assertions covering AC3/AC4/AC5/AC6/AC7/AC8/AC13:
    - `status_is "$SPEC_DIR/spec.md" "draft"` (AC4: planned → draft).
    - `contains_regex "$SPEC_DIR/spec.md" "^revision: 1"` (AC4: bump).
    - `exists "$SPEC_DIR/review-r0.md"` (AC4: review.md archived).
    - `exists "$SPEC_DIR/plan-r0.md"` (AC5-shaped: plan.md archived
      because source was `planned`).
    - `exists "$SPEC_DIR/tasks-r0.md"` (AC5-shaped).
    - `contains_regex "$LOG_DIR/06-revise.log" "^Q-DRIFT:"` (AC8).
    - `contains "$LOG_DIR/06-revise.log" "/speccraft:spec:review"`
      (AC13).
    - `ACTIVE_AFTER="$(jq -r '.active_spec' .speccraft/state.json)";
       [ "$ACTIVE_AFTER" = "$ACTIVE_BEFORE" ]` where `ACTIVE_BEFORE`
       was captured pre-revise (AC3/AC4: state.json byte-identical).
  - Add a SECOND `run_claude` call invoking revise again with prompt
    "make no semantic changes" to exercise AC6 no-op: assert
    `contains "$LOG_DIR/06b-revise-noop.log" "no changes — spec
    unchanged"`, assert `contains_regex "$SPEC_DIR/spec.md" "^revision:
    1"` (still 1, not bumped).
  - After the revise exercise the spec is back at `status: draft`. To
    let the existing `[7/11] /speccraft:spec:close` step succeed
    without re-running plan, add a re-review + re-plan via two extra
    `run_claude` calls inserted before the original close step. (This
    keeps the lifecycle linear and preserves close's status-gate
    requirements.)
- Tests fail: `commands/spec/revise.md` does not exist as an installed
  command; `claude -p` would respond with an unknown-command error;
  every assertion fails.

### Step 14 — Verify e2e GREEN (no new code, only verification)

- With the implementation from steps 2, 4, 6, 8, 10, 11 in place, the
  `run.sh` modifications from step 13 execute the full lifecycle
  including revise. Run locally:
  ```bash
  bash tests/e2e/run.sh
  ```
  and confirm all 12 steps green. (This step is verification-only; it
  contains no new file writes. It's listed as a task so the tracker
  reflects that the e2e gate is intentionally walked.)
- Note for the reviewer: AC1, AC2, AC9, AC10 are covered structurally by
  the bats suite (steps 3, 4) and don't need re-exercising via `claude
  -p`. The e2e step focuses on the agent-dependent ACs.

### Step 15 — Refactor: dedupe error-message format strings (optional)

- After step 11, several helpers emit "ERROR: <thing> at <path>"-shape
  messages. Extract `revise_error()` at the top of `revise.lib.sh`
  taking `(category, detail)` and emitting a uniform shape. Update
  all helpers to use it. All bats tests still pass (the bats
  assertions name the offending file/status by substring, not by
  whole-line format).

### Step 16 — Wire bats coverage into hook-test CI job

- `.github/workflows/ci.yml` already runs `bats tests/hooks/` in the
  `Hook tests (bats)` job (line 50). Verify the new
  `spec-revise-preflight.bats` is picked up automatically (glob
  expansion on `bats tests/hooks/`). No workflow edits required.
- If CI Bash environment differs from the devcontainer (e.g. `yq` is
  not installed), add `yq` install step. Confirm by reading the
  `Hook tests (bats)` job env setup at planning time.

### Step 17 — Convention amendment at close (deferred to /spec:close memory-keeper pass)

- The §Mechanism in spec 0015 introduces `commands/spec/revise.lib.sh`
  — the first sourceable Bash helper under `commands/spec/`. This is
  a new repo convention.
- At `/speccraft:spec:close` time, the memory-keeper pass must propose
  a §Conventions / Bash subsection entry documenting:
  - Naming convention: `commands/<group>/<name>.lib.sh` colocated with
    the `.md` body that sources it.
  - Sourcing pattern: `source "$CLAUDE_PLUGIN_ROOT/commands/<group>/<name>.lib.sh"`.
  - Testability requirement: helpers in a `.lib.sh` MUST be pure
    shell functions (no top-level side effects) so bats can source
    them.
- Also at close, memory-keeper must propose the conventions.md
  §"Markdown frontmatter" tightening that AC12 commits to: subagent
  frontmatter contract becomes `name/description/tools/model`; slash
  command frontmatter contract becomes `description/argument-hint/
  allowed-tools`.
- No file written here; this is the tasks.md placeholder for the
  close pass.

## Delegation

- Steps 2, 11 (writing `agents/spec-reviser.md`, `commands/spec/revise.md`)
  → keep with the **planner / implementer** thread, no sub-agent
  delegation. These are Markdown bodies with load-bearing prose
  constraints (Q-DRIFT pinning, forbidden-edits list, source-pattern)
  that benefit from direct authorial control.
- Steps 3, 5, 7, 9 (bats test authoring) → no delegation; the test names
  encode AC mapping and need to be reviewable against spec.md line-by-line.
- Steps 4, 6, 8, 10 (helper implementation in `revise.lib.sh`) → keep
  with the implementer. Bash portability is a recurring trip-hazard
  (POSIX vs GNU grep flagged in review.md); single-author keeps the
  shell-portability discipline consistent.
- Step 13 (e2e integration) → keep with the implementer. The renumbering
  is a mechanical edit and the existing run.sh has spec-0008 / spec-0014
  scaffolding (`run_claude`, `contains_regex`) that must be reused
  verbatim.
- Step 17 (close-time convention amendments) → delegate to
  **memory-keeper** at `/speccraft:spec:close`, per the agent's standing
  role. The tasks.md entry exists so the planner remembers to surface it.

## Risk

- **Bash portability between devcontainer and CI.** `yq` is used in
  step 6 for `validate_packages`. If absent on the CI Bash runner used
  by the `Hook tests (bats)` job, the bats tests will fail at
  helper-source time. Mitigation: in step 16, confirm the CI job
  installs `yq` (or fall back to a small awk-based YAML-list parser
  that accepts the narrow shape `packages: [...]` only).
- **Q-DRIFT pinning depends on model adherence.** AC8's structural
  anchor is the `^Q-DRIFT:` prefix. Even with step 2's prompt-body
  pinning, a model that paraphrases the prefix (e.g. "Q-DRIFT —" or
  "## Q-DRIFT") will produce a green model run with a red AC8
  assertion. Mitigation: the verify.sh oracle (step 1) statically
  asserts that the LITERAL token `Q-DRIFT:` appears in
  `agents/spec-reviser.md` body — that's a structural compile-time
  check on the prompt, complementing the runtime e2e check.
- **`diff_against_snapshot` normalisation is a known ambiguity.** The
  spec calls out "whitespace or terminal newline" without pinning the
  algorithm. Step 8 picks "strip trailing horizontal whitespace +
  trailing newlines + cmp -s". If a future spec author adds a no-op
  case the helper misses (e.g. tab/space normalisation in the middle
  of a line), they'd see a false "changed" report. Mitigation:
  document the chosen predicate at the top of the helper function and
  reference the bats test names so the contract is discoverable.
- **e2e step renumbering is high-traffic.** `tests/e2e/run.sh` has
  step-counter prose that's been touched by specs 0005, 0007, 0008,
  0010, 0014. The step-13 edit must keep all existing numbered
  comments in lockstep. Mitigation: do the renumber in a single
  commit with `git diff --check`-verified whitespace and a manual
  read of every `\[[0-9]+/[0-9]+\]` line in the file.
- **Active-spec lifecycle interaction.** The e2e step exercises revise
  on a `planned` spec; the existing `/speccraft:spec:close` later in
  the same run requires the spec to be back at `planned` (close gate
  reads tasks.md). Step 13 plans re-review + re-plan after revise to
  re-enter `planned`. Risk: this extends the credit-gated lifecycle
  by two extra `claude -p` invocations. Acceptable in exchange for
  exercising the full revise contract end-to-end.
