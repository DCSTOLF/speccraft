---
spec: "0049"
status: planned
strategy: tdd
---

# Plan — 0049 Command-lib portability and sanctioned PM/Architect status writers

## Stack & commands

Polyglot repo; `speccraft-state detect-stack` returns `unknown`, so the two test
surfaces are named explicitly here rather than resolved from detection:

- **Go** — module `github.com/dcstolf/speccraft/tools`. Suite: `cd tools && go test ./...`
  (9.5s cold). Tests colocated as `*_test.go`; names `Test<UpperCamel>` or
  `Test_<Subject>_<Scenario>` (conventions.md §Go).
- **bats** — `tests/hooks/*.bats` (20 files, 294 tests, 12s). Run as
  `PATH="$PWD/bin:$PATH" bats tests/hooks/`.

**The `PATH="$PWD/bin:$PATH"` prefix is load-bearing, not decoration.** In this
devcontainer `command -v speccraft-state` resolves to the cached plugin build
`~/.claude/plugins/cache/dcstolf-tools/speccraft/1.11.0/bin/speccraft-state`,
which has no `--kind` flag. From T8 onward the arch/pm helpers shell out to the
binary, so a bats run against the stale cache fails for the wrong reason. Every
bats `done:` predicate in `tasks.md` carries the prefix, and Appendix C records
the resolution order the helpers implement.

## Sequencing hazards (read before touching anything)

1. **AC4 gates AC1.** `validStatuses` (`tools/internal/speccraft/revision.go:183`)
   holds `draft/reviewed/planned/in-progress/blocked/closed` — neither `decided`
   nor `prioritized`. The shell reroute in T8 *cannot* work until the kind-scoped
   enum exists. Phase 1 (T2–T6, Go) therefore precedes Phase 2 (T7–T8, shell).
2. **AC9's permitted fixture and AC8's fix are ONE task (T12).** The portability
   guard scans `commands/` live. Land the guard first and it flags the very
   `tac` it is meant to outlaw; land the fix first and the guard's PERMITTED set
   does not yet contain the replacement reversal form. T12 lands the reversal,
   the scanner, and the PERMITTED fixture for that exact reversal string in a
   single task/commit. **Do not split T12.**
3. **AC7's guard widening must follow T8.** `frontmatter-writer-guard.bats`'s
   third test scans the live `commands/` tree. Widen the path filter to
   `design.md`/`brief.md` while `decide.lib.sh:25` and `prioritize.lib.sh:25`
   still hold their `sed -i`, and the live-clean test fails on the un-fixed
   production code — a RED for the wrong reason. T9/T10 come after T8.
4. **T3 breaks the whole `tools/` build for the duration of one edit.** See
   §Override budget.

## Override budget: 3 (expected spend 1)

Stating 0 would repeat spec 0047's error (it declared 0 and spent 5 on exactly
this hazard, which spec 0048 — now `blocked` — documents as the guard-wedge
class: a broken build makes the guard forbid its own repair, because a build
failure is not an observable runtime RED per guardrails.md / spec-0018 AC13).

- **1 planned, at T3.** `ArtifactKind`, `KindSpec/KindDesign/KindBrief`, and the
  three-arg `SetStatus` are brand-new exported symbols in
  `tools/internal/speccraft`; T2's RED cannot compile until they exist. Per
  conventions.md §"Place fault-injectable logic in the cmd package…"
  (Budget discipline), **all** from-scratch exported bootstrapping is
  concentrated into this single edit — constants, `kindStatuses`, the signature
  change, and all nine call-site updates land together, leaving the package
  buildable at the end of the edit.
- **2 contingency.** If T3's mega-edit misses a call site, the package stays
  unbuildable and the guard will block the repair (the 0048 wedge). Appendix A
  pre-enumerates every call site precisely so this does not happen; the two
  reserved overrides are the honest cost if it does.
- **Structurally 0 elsewhere.** The CLI `--kind` parsing (T5) lands in the
  **cmd** package and rides the compile-stable `run()` seam — an unknown-flag
  RED is a runtime failure, never a build error. Shell (`commands/**.lib.sh`,
  `scripts/*.sh`), bats, and YAML are not gated by `speccraft-guard` at all
  (conventions.md §Bash), so T7–T19 cost nothing.
- **No new Go imports anywhere.** Per conventions.md §"Avoid a NEW import…",
  T3 reuses the existing `revErr` string-error type; nothing in this spec needs
  `fmt`, `errors`, or `strconv` added to a file that carries a standing RED.

## Test-first sequence

### Phase 0 — enumerate before you break things

#### Step 1 — Inventory and sweep methodology (no code)

Pure recording step, discharged by Appendices A/B/C of this file. It exists
because both carried review items 7 and 8 are about *not discovering* facts
mid-implementation:

- Appendix A pre-enumerates all nine `SetStatus` call sites (review item 7), so
  T3 is one atomic edit rather than a build-error discovery loop.
- Appendix B records the grep pattern and the non-executed-match exclusion list
  behind "exactly one file, seven mutations" (review item 8), and T13 turns that
  methodology into an executable meta-test.
- Appendix C records the binary-resolution decision that lets AC1's four
  pre-existing tests pass **unmodified**.

### Phase 1 — kind-scoped enum in Go (AC4, AC5, AC6, AC2 Go layer)

#### Step 2 — Kind-scoped status enum (RED)

- Extend `tools/internal/speccraft/revision_test.go`:
  - `Test_SetStatus_KindDesign_AcceptsDecided_RejectsPrioritized` — table-driven
    over the `design` enum.
  - `Test_SetStatus_KindBrief_AcceptsPrioritized_RejectsDecided` — the mirror,
    proving the two new values are not pooled.
  - `Test_SetStatus_KindSpec_RejectsDecidedAndPrioritized` — the no-regression
    half: today's spec enum is unchanged and neither new value leaks into it.
  - `Test_SetStatus_EmptyKind_Errors` — `SetStatus(p, ArtifactKind(""), "draft")`
    errors *before* status validation. Pins AC4's "no meaningful zero value".
  - `Test_SetStatus_ClosedArtifact_Immutable_AllKinds` — AC5, table over all
    three kinds: non-zero, and the file byte-identical afterwards.
- **Tests fail:** `ArtifactKind`, `KindSpec/KindDesign/KindBrief` do not exist
  and `SetStatus` takes two arguments — this is a *compile* failure, which per
  spec-0018 AC13 the guard cannot observe as a RED. This is the one budgeted
  override, spent on step 3.

#### Step 3 — Kind-scoped enum + typed `ArtifactKind` (GREEN) — THE ONE BUDGETED OVERRIDE

- `tools/internal/speccraft/revision.go`:
  - `type ArtifactKind string` + `KindSpec ArtifactKind = "spec"`,
    `KindDesign = "design"`, `KindBrief = "brief"`.
  - Replace the flat `validStatuses` map with
    `kindStatuses map[ArtifactKind]map[string]bool` — `spec` keeps today's six;
    `design` = today's six minus `reviewed`/`planned`/`in-progress` plus
    `decided` (decide the exact design/brief sets in this step and pin them by
    the step-2 table); `brief` likewise with `prioritized`.
  - `func SetStatus(specMd string, kind ArtifactKind, status string) error`:
    reject unknown/empty kind first (`revErr`), then the per-kind enum, then
    closed-immutability (kind-independent), then `setFrontmatterField`.
  - **No compatibility wrapper** (AC4 is explicit: a kind-defaulting wrapper is
    the silent-default surface this spec removes).
- Update all nine call sites from Appendix A in the same edit —
  `tools/cmd/speccraft-state/main.go:302` → `speccraft.KindSpec`, and the eight
  test call sites in `revision_test.go` / `frontmatter_writer_test.go`.
- `cd tools && go build ./...` must be clean at the end of this single edit.
- All step-2 tests pass.

#### Step 4 — `set-status --kind` CLI shape (RED)

- Extend `tools/cmd/speccraft-state/set_status_cmd_test.go`:
  - `Test_StateCmd_SetStatus_KindFlag_SpaceAndEqualsForms` — table: both
    `--kind design` and `--kind=design` accepted, flag before the positionals.
  - `Test_StateCmd_SetStatus_KindFlag_AfterPositionals_IsUsageError` — a flag
    after the positionals is a **usage error**, never a silent ignore.
  - `Test_StateCmd_SetStatus_NoKindFlag_DefaultsToSpecEnum` — no flag ⇒ exactly
    today's behavior; `decided` and `prioritized` both rejected.
  - `Test_StateCmd_SetStatus_KindValidatesEnumOnly_NotPathShape` — `--kind design`
    against a `brief.md` **succeeds**. AC4 requires this be recorded as
    deliberate, not discovered later as a bug.
  - `Test_StateCmd_SetStatus_UnknownKind_IsUsageError`.
  - `Test_StateCmd_SetStatus_EveryNonZeroPath_WritesStderr` — AC2 at the binary
    layer: invalid-status, closed-artifact, unknown-kind, missing-file and
    usage all produce non-empty stderr. A silent `return 1` is a defect.
- **Tests fail at runtime, not build time:** the current `case "set-status"`
  reads `args[1]`/`args[2]` positionally, so `--kind` is taken as the path and
  the assertions on exit code/stderr text do not hold. Rides the `run()` seam ⇒
  zero override.

#### Step 5 — `--kind` flag parsing at the CLI boundary (GREEN)

- New `tools/cmd/speccraft-state/set_status_cmd.go` (cmd package, per the
  conventions' `run()`-seam pattern) with `setStatusCmd(args, stdout, stderr) int`:
  parse `--kind X` / `--kind=X` **before** the positionals, map "absent" to
  `speccraft.KindSpec` **here and only here**, reject a post-positional flag as
  usage, and print every error to stderr.
- `main.go`'s `case "set-status":` becomes a one-line delegation.
- All step-4 tests pass.

#### Step 6 — Byte-safety and the Go write-failure seam (PIN, not RED)

Labeled PIN following the spec-0047 precedent: both behaviors are already
correct by construction once step 3 lands (`setFrontmatterField` is
kind-agnostic; `AtomicWriteFile` already removes its temp on a failed rename),
so there is no honest RED to write and **no GREEN follows**. They are pinned
because AC2/AC6 require them asserted for design/brief specifically.

- `tools/internal/speccraft/frontmatter_writer_test.go`:
  - `Test_SetStatus_Design_BomCrlfNoEofNewline_OnlyStatusLineChanges` — fixture
    with a UTF-8 BOM, CRLF terminators and no EOF newline; asserts every byte
    outside the first `status:` line is preserved (AC6).
- `tools/internal/speccraft/revision_test.go`:
  - `Test_SetStatus_RenameFailure_LeavesFileByteIdentical_NoTempLeftover` —
    injects at the existing `atomicRename` seam (`review.go:26`, pattern already
    used by `review_commit_test.go:98`); asserts error non-nil, target
    byte-identical, and no `<file>.tmp` sibling (AC2 Go layer).

### Phase 2 — route the shell through the sanctioned writer (AC1, AC2, AC3)

#### Step 7 — The full exit-path contract for both helpers (RED)

Coverage is **split by layer**, per carried review item 6: the helper handles two
of the five non-zero paths itself, before the binary is ever invoked.

- Extend `tests/hooks/arch-decide.bats` (do **not** touch the two existing
  `@test`s — AC1 requires them unmodified):
  - `@test "arch_set_status: lib has no in-place rewrite and invokes set-status"`
    — source-scan: no `sed`/`perl -i` in the lib; `set-status --kind design` present.
  - `@test "arch_set_status: successful transition leaves no stray sibling"` —
    directory listing identical before/after apart from `design.md`; no
    `design.md-E`, `.bak`, or `.tmp` (AC3).
  - *Shell-layer pre-checks (binary never invoked):*
    `@test "arch_set_status: missing file -> non-zero + non-empty stderr"`,
    `@test "arch_set_status: non-draft source -> non-zero + non-empty stderr + file unchanged"`.
  - *Binary-layer, real binary:*
    `@test "arch_set_status: invalid status for kind -> non-zero + non-empty stderr + file unchanged"`
    (`arch_set_status <design.md> prioritized`),
    `@test "arch_set_status: closed artifact -> non-zero + non-empty stderr + file unchanged"`.
  - *Binary-layer, PATH shim (AC2's deterministic, uid-independent seam):*
    `@test "arch_set_status: binary failure via PATH shim -> non-zero, stderr, byte-identical target, no temp remnant"`
    — prepends a temp dir holding an executable `speccraft-state` that writes to
    stderr and exits 3.
- Mirror all six in `tests/hooks/pm-prioritize.bats` as
  `pm_set_status: …` (`--kind brief`, `decided` as the invalid value).
- **Tests fail:** the libs still hand-roll `sed -i -E "0,/^status:/…"`, so the
  source-scan test fails outright; the PATH-shim test fails because the helper
  never invokes the binary; and the stray-sibling test is exactly the
  `design.md-E` bug under BSD sed (on Linux it passes for the wrong reason,
  which is why AC10's macOS leg exists).

#### Step 8 — Delegate both writes to `speccraft-state set-status` (GREEN)

- `commands/arch/decide.lib.sh` — delete line 25; keep the `-f` and
  `status == draft` gates verbatim (AC1); append
  `"$bin" set-status --kind design "$file" "$new" || { echo "arch_set_status: set-status failed via $bin" >&2; return 1; }`.
- `commands/pm/prioritize.lib.sh` — same shape with `--kind brief`.
- Resolver (Appendix C), shared shape in both libs: `$SPECCRAFT_STATE_BIN` if
  executable → `command -v speccraft-state` → `$(dirname "${BASH_SOURCE[0]}")/../../bin/speccraft-state`.
  PATH must rank above the plugin-local fallback so AC2's shim intercepts; the
  fallback is what makes AC1's four unmodified tests resolve a *fresh* binary in
  CI. The diagnostic names the resolved path, so a version-skewed binary
  self-reports instead of confusing the author.
- `.github/workflows/ci.yml`, `hooks` job: after "Build helper binaries", add
  `echo "$PWD/bin" >> "$GITHUB_PATH"` so every bats file (including the two that
  do not export PATH themselves) sees the just-built binary.
- All step-7 tests pass, and the four pre-existing AC1 tests pass unmodified.

### Phase 3 — widen the frontmatter-writer meta-guard (AC7)

> Ordering: must follow step 8 (hazard 3).

#### Step 9 — Design/brief/variable-target fixtures (RED)

- `tests/hooks/frontmatter-writer-guard.bats`, extending the `setup()` fixture sets:
  - FORBIDDEN `f5`–`f9`: `sed -i` on a literal `design.md`; on a literal
    `brief.md`; on `"$DESIGN"`; on `"$BRIEF"`; and **`f9` = the pre-fix
    `arch_set_status` line carried verbatim**, so the guard is pinned against the
    bug that actually escaped.
  - PERMITTED `p6`–`p7`: read-only `awk -F': ' '/^status:/{print $2; exit}' design.md`
    (the helper's own surviving read) and `grep -E '^status:' "$BRIEF"`.
  - `@test "meta-guard FLAGS design/brief/variable-target frontmatter writes"`
  - `@test "meta-guard PASSES read-only awk/grep on a design and a brief"`
  - `@test "meta-guard scan root is commands/ only and excludes specs/"` — asserts
    the archive-safety invariant stated in spec §What item 3 (a `sed -i` line
    planted under a fixture `specs/` tree is not seen).
- **Tests fail:** `scan_offenders()`'s third filter
  (`grep -E 'spec\.md|SPEC_MD|spec_md'`, line 37) never sees a `design.md` /
  `brief.md` / `$DESIGN` target — the exact blind spot that let this bug ship.

#### Step 10 — Widen the path-shape filter (GREEN)

- `scan_offenders()` filter (a) becomes
  `grep -E 'spec\.md|SPEC_MD|spec_md|design\.md|DESIGN|design_md|brief\.md|BRIEF|brief_md|\$file|\$FILE'`;
  filter (b) gains the design/brief redirect shapes. Scope-conservatively-IN is
  preserved: a non-literal target is treated as in-scope and flagged.
- Scan root stays `"$PLUGIN_DIR/commands"`. Add a header comment recording *why*
  widening to `specs/**` is forbidden (this spec's own archived copy quotes the
  forbidden line verbatim).
- All step-9 tests pass, and the live `commands/` tree scans clean.

### Phase 4 — the `tac` fix and the portability guard, together (AC8, AC9)

#### Step 11 — Reversal ordering and the portability-guard fixtures (RED)

- `tests/hooks/spec-consolidate.bats`:
  - `@test "consolidate_backfill_order: history-chronological then history-less, with tac absent from PATH"`
    — runs the helper with a PATH stripped of `tac` (or a shim dir shadowing it
    as non-executable). The fixture carries **both halves** (AC8): two
    candidates with parseable `## YYYY-MM-DD` history entries and two with none,
    asserting the full expected order oldest-first-then-`created:`-ordered. A
    history-only fixture would green a fix that still drops the history-less half.
- New `tests/hooks/portability-guard.bats`:
  - `@test "portability guard FLAGS every forbidden GNU-only fixture"` — one
    fixture per enumerated form: bare `sed -i`, the `0,/re/` address, `tac`,
    `readlink -f`, `grep -P`, `stat -c`, `date -d`, `base64 -w`, plus the
    commented, fenced, quoted and line-continuation variants (all FLAGGED —
    "scope conservatively IN, never silently skip").
  - `@test "portability guard PASSES every portable counterpart"` — `sed -i.bak`,
    `sed -i ''`, `sed -i ""`, `sed -n '/re/p'`, `stat -f`, a
    `speccraft-state`-subcommand redirect, and **the exact awk reversal string
    step 12 introduces**.
  - `@test "portability guard finds the LIVE shipped surfaces clean"` — `hooks/`,
    `commands/`, `tools/`, `templates/`, `agents/`, `skills/`.
  - `@test "portability guard scan root excludes tests/ and tools/**/*_test.go"`
    — the carried review item 5 decision, made explicit below.
- **Tests fail:** `commands/spec/consolidate.lib.sh:409` still pipes through
  `tac`, so on a `tac`-less PATH the process substitution yields empty input,
  the `while` body never runs, `set -euo pipefail` does not fire, and the
  history-chronological half vanishes; and `portability-guard.bats` does not exist.

**Review item 5 — decided: `tools/**/*_test.go` is TEST-SIDE and excluded.**
Same rationale as `tests/**`: a Go test file is never compiled into a shipped
binary and never installed into a user's environment, so a GNU-form *string*
there is not a shipped defect. And the complementary runner already exists —
`unit-macos` runs `go test ./...` on `macos-14` today, so a Go test that actually
*executes* a GNU-only form fails there, exactly mirroring the guard/runner split
AC10 sets up for bats. Pinned both ways: a PERMITTED fixture
`tools/internal/speccraft/x_test.go` carrying `sed -i`, and a FORBIDDEN fixture
`tools/internal/speccraft/x.go` carrying the same string. Cost today is zero —
the sweep in Appendix B finds no GNU form anywhere under `tools/`.

#### Step 12 — Replace `tac` and land the guard in ONE task (GREEN)

> **Hazard 2. Do not split this step.** The scanner's live pass over `commands/`
> would flag the `tac`; the PERMITTED set must already contain the replacement.

- `commands/spec/consolidate.lib.sh:409` →
  `done < <(history_parse_entries "$H" | awk '{l[NR]=$0} END{for(i=NR;i>0;i--) print l[i]}')`.
  Verified entry-reversal-safe: `history_parse_entries` emits only matching
  `^## YYYY-MM-DD` header lines — one line per entry — so line reversal *is*
  entry reversal (review round 1, considered-and-rejected).
- Land the scanner in `portability-guard.bats` with that exact awk string as a
  PERMITTED fixture.
- Matching semantics, two-stage so the forbidden forms are not prefixes of the
  permitted ones (verified against a seven-line fixture: flags the bare and the
  `-i -E` forms and the commented form; passes `-i.bak`, `-i ''`, `-i ""`, `sed -n`):
  `grep -nE "sed +-i([^.a-zA-Z0-9]|$)" | grep -vE "sed +-i +(''|\"\")( |$)"`.
- Header comment states the `tests/**` + `tools/**/*_test.go` exclusion and its
  rationale, and states that there is **no escape hatch** — documentation under a
  scanned surface that must name a forbidden form moves to `.speccraft/` or
  `specs/`, because an `allow-gnu-form` annotation would make the guard evadable
  by annotation.
- All step-11 tests pass.

### Phase 5 — the macOS bats leg (AC10)

#### Step 13 — Executable sweep over `tests/hooks/` (RED)

- New `tests/hooks/tests-portability-sweep.bats`:
  - `@test "no tests/hooks file EXECUTES a GNU-only form"` — runs Appendix B's
    grep across `tests/hooks/`, subtracting the explicit mention-only exclusion
    list (`frontmatter-writer-guard.bats`, `spec-revise-selfheal.bats`,
    `portability-guard.bats`, `tests-portability-sweep.bats`). This is carried
    review item 8 made executable: the "one file, seven mutations" claim becomes
    a standing assertion instead of a one-off sweep.
  - `@test "the mention-only exclusion list is exactly the four guard/fixture files"`
    — so the list cannot silently grow, which is the failure mode an exclusion
    list always has.
- **Test fails:** `tests/hooks/spec-revise-preflight.bats` executes seven
  GNU-only `sed -i` mutations (lines 695, 707, 719, 731, 744, 781, 793).

#### Step 14 — Port the seven mutations (GREEN)

- `tests/hooks/spec-revise-preflight.bats:695–793` — each
  `sed -i 's/X/Y/' "$spec_dir/spec.md"` becomes
  `sed 's/X/Y/' "$spec_dir/spec.md" > "$spec_dir/.tmp" && mv "$spec_dir/.tmp" "$spec_dir/spec.md"`.
  Ported, not excluded — an exclusion list needs maintaining and silently grows.
  `sed -i.bak` is deliberately *not* used here: it drops a sibling into a
  fixture directory some of these very tests assert the shape of.
- All step-13 tests pass; `spec-revise-preflight.bats` stays green (53 tests).

#### Step 15 — No-GNU-userland assertion and the CI contract (RED)

- New `tests/hooks/no-gnu-userland.bats` — tests the **script's logic** against
  synthetic fixture PATHs, so it runs correctly on Linux:
  - `@test "assert-no-gnu-userland PASSES a synthetic BSD-only fixture PATH"`
  - `@test "assert-no-gnu-userland FLAGS a gnubin-shadowed sed"`
  - `@test "assert-no-gnu-userland FLAGS a coreutils/libexec-shadowed stat"`
  - `@test "assert-no-gnu-userland FLAGS a resolvable gsed"`
  - `@test "assert-no-gnu-userland FLAGS a resolvable tac"`
  - `@test "assert-no-gnu-userland FLAGS a GNU sed reached through an unusual symlink"`
    — **carried review item 2**: the `*/gnubin/*` path check alone misses this;
    the behavioral probe (GNU `sed --version` exits 0, BSD `sed` does not) catches
    it. The two oracles are complementary, and the fixture is a shim that accepts
    `--version` from a directory matching neither excluded path pattern.
  - `@test "the live no-GNU assertion is a ci.yml step, not a bats test"` —
    **carried review item 1, pinned mechanically**: asserts no file under
    `tests/hooks/` invokes the script against the *live* PATH. On Linux `tac`
    resolves, so a live assertion loaded by the `hooks` job would invert and fail.
  - `@test "the bats interpreter is Bash 5 or newer"` — `BASH_VERSINFO[0] -ge 5`
    (AC10 condition 2; green on Linux CI, and the thing that makes a silently-3.2
    macOS job fail loudly instead of passing for the wrong reason).
  - `@test "ci.yml defines hooks-macos on macos-14 running the full tests/hooks suite"`
  - `@test "ci.yml hooks-macos invokes the no-GNU assertion BEFORE bats"` —
    ordinal comparison of the two step positions within the job block.
  - `@test "ci.yml installs no GNU userland and prepends no gnubin"` — no
    `coreutils` / `gnu-sed` / `gsed` brew install anywhere, no `gnubin` string.
    AC10 calls condition 3 load-bearing; prose in a workflow file is enforced by
    nothing, so it is asserted.
- **Tests fail:** `scripts/assert-no-gnu-userland.sh` does not exist and
  `.github/workflows/ci.yml` has no `hooks-macos` job.

**Decision recorded (review item 1): the live no-GNU assertion runs as a
workflow step, not as a bats test, and not under `$RUNNER_OS` scoping.** A
workflow step fails *before* any bats runs, so a GNU-greened job cannot mask a
single test; `$RUNNER_OS` scoping instead pushes CI-environment branching into
the suite and makes the assertion a silent no-op everywhere else. The script's
logic stays cross-platform-testable because it reads the PATH it is *given*.

#### Step 16 — `scripts/assert-no-gnu-userland.sh` + the `hooks-macos` job (GREEN)

- New `scripts/assert-no-gnu-userland.sh` — `#!/usr/bin/env bash`, `set -euo pipefail`,
  absolute paths from `${BASH_SOURCE[0]}`. For each of `sed stat date readlink base64 tac`:
  either it does not resolve at all (`tac` must not), or it resolves outside
  `*/gnubin/*` and `*/coreutils/libexec/*` **and** fails the behavioral
  `--version` probe. Then `! command -v gsed`. Probes the PATH in
  `$SPECCRAFT_PROBE_PATH` when set, else the live `PATH`, which is what makes
  step 15's fixtures possible.
- `.github/workflows/ci.yml` — new `hooks-macos` job on `macos-14`, mirroring
  `hooks`: checkout, `setup-go`, `brew install bash bats-core` (**and nothing
  else**), build the helper binaries, `echo "$PWD/bin" >> "$GITHUB_PATH"`, run
  `bash scripts/assert-no-gnu-userland.sh`, then run the full suite through the
  Homebrew Bash 5 (`"$(brew --prefix)/bin/bash" "$(command -v bats)" tests/hooks/`),
  not `/bin/bash`. Unconditional on push and PR per resolved decision 2; the
  documented fallback (gate to `push` on `main`) is a workflow-only edit.
- All step-15 tests pass.

### Phase 6 — the AC11 coverage-topology oracle

#### Step 17 — `verify-linux-pins.sh` contract (RED)

- New `tests/hooks/verify-linux-pins.bats`:
  - `@test "verify-linux-pins --list names exactly the three production pins"` —
    `decide.lib.sh`, `prioritize.lib.sh`, `consolidate.lib.sh`.
  - `@test "verify-linux-pins fingerprints the caller tree BEFORE creating the worktree"`
    — **carried review item 3**: source-scan asserting the fingerprint call's
    offset precedes the `git worktree add` offset, so the script's own setup
    cannot mutate the checkout unnoticed.
  - `@test "verify-linux-pins uses git worktree add --detach, not a temp clone"`
    — **carried review item 4**: same isolation, faster, and it cannot inherit an
    unclean index.
  - `@test "verify-linux-pins removes its worktree on exit, including on failure"`
  - `@test "verify-linux-pins restarts each mutation from the same clean baseline"`
    — asserts the reverts are not layered.
  - `@test "caller checkout is byte-identical after a run whose pin check FAILS"` —
    driven through a `$SPECCRAFT_VLP_TEST_CMD` seam set to an always-exit-0 stub,
    which makes "reverting the fix produced no bats failure" — i.e. the pin is
    *not* held on Linux — so the script exits non-zero; then compares the
    pre-run fingerprint. This is the sharp one: a helper whose job is reverting
    production fixes is one bug away from destroying uncommitted work.
- **Tests fail:** `scripts/verify-linux-pins.sh` does not exist.

#### Step 18 — `scripts/verify-linux-pins.sh` (GREEN)

- New script: fingerprint the caller's tree first (`git status --porcelain` +
  `git rev-parse HEAD` + a content hash over the three target files), then
  `git worktree add --detach "$TMP" HEAD`, `trap 'git worktree remove --force' EXIT`,
  and for each of the three pins independently: restore the worktree to the clean
  baseline, revert that one fix, run `$SPECCRAFT_VLP_TEST_CMD` (default
  `bats tests/hooks/`) inside the worktree, and require a **non-zero** result.
  Final self-check re-fingerprints the caller's tree and fails loudly on any
  drift. Non-CI-gating by design; prints `verify-linux-pins.sh: 3/3 pins confirmed`
  on success.
- All step-17 tests pass.

#### Step 19 — Author evidence run (AC11)

- Run `bash scripts/verify-linux-pins.sh` for real and paste its final line into
  `specs/0049-command-lib-portability/changelog.md`. Script-existing-and-passing
  *is* the acceptance evidence; the predicate checks the recorded line rather
  than re-running three full suites inside the close gate's 30s predicate budget.

### Phase 7 — refactor and close-out

#### Step 20 — Confirm no version bump (Resolved decision 1)

- 0049 carries no release. Assert the six version locations still read `1.16.0`,
  so the bump cannot be made accidentally here — and so that if 0049 is *later*
  chosen to carry the release, the decision is a deliberate reopening before
  `spec:close` (closed-spec immutability makes it unfixable afterward).

#### Step 21 — Refactor: one shared writer envelope (optional but recommended)

- Steps 8's two helpers are near-identical (resolver + gate + delegate +
  diagnostic). Factor the resolver and the error envelope into a single sourced
  helper that both libs use — conventions.md already sanctions a command lib
  sourcing another's pure helpers. Keep `arch_set_status` / `pm_set_status` as
  the public names so AC1's four unmodified tests still bind.
- All tests still pass; do **not** attempt this before step 12 is green, so a
  refactor failure is never confused with a portability failure.

#### Step 22 — Full green on Linux

- `cd tools && go test ./...` (9.5s) and `PATH="$PWD/bin:$PATH" bats tests/hooks/`
  (12s, now 21 files) both clean, plus `go vet ./...`.

## Delegation

- **Steps 2–22 → in-session.** This repo ships no implementer subagent
  (`agents/` holds spec/arch/pm authoring, critics, `cross-reviewer`,
  `memory-keeper`, `aux-delegator`), so there is no strength-matched delegate for
  a RED→GREEN edit. Delegating them would add a handoff without adding capability.
- **Step 11's live sweep + step 13's exclusion list → `aux-delegator`
  (optional).** A second, independent grep sweep over the six shipped surfaces is
  cheap, mechanical, and benefits from an independent generation — this is
  precisely the "did we ship a GNU-ism?" question, and a missed form is a silent
  false negative. If used, treat the aux output as evidence, never as
  authoritative sign-off (the known aux-delegator false-quorum hazard).
- **Close-out ADR + changelog → `memory-keeper`, via `/speccraft:spec:close`
  step 4.** Three conventions earn recording: the kind-scoped enum + typed
  `ArtifactKind` with the default living only at the CLI boundary; the portability
  meta-guard's two-stage prefix-safe matching; and the guard-versus-runner split
  ("did we ship it?" vs "does our suite run on BSD?").

## Risk

- **T3 wedges the build and the guard forbids its own repair** (spec 0048,
  `blocked`; spec 0047 spent 5 overrides on exactly this) → mitigation:
  Appendix A pre-enumerates all nine call sites so the edit is atomic and ends
  buildable; no new imports anywhere (conventions.md §"Avoid a NEW import");
  budget states 3 with 2 explicitly reserved for this, not 0.
- **AC1's four unmodified tests break because the resolved binary is the stale
  1.11.0 plugin cache** (verified: that is what `command -v speccraft-state`
  returns in this devcontainer) → mitigation: Appendix C's resolver ranks the
  plugin-local `bin/` after PATH but ahead of nothing, step 8 adds
  `$GITHUB_PATH` in both bats jobs, every bats predicate in `tasks.md` carries
  `PATH="$PWD/bin:$PATH"`, and the diagnostic names the resolved binary path so a
  skewed build self-reports. A stale binary receiving `--kind` also fails loudly
  (it reads `--kind` as the path, `design` as the status → non-zero + stderr),
  which satisfies AC2 rather than reintroducing silent success.
- **AC10's no-GNU assertion inverts on Linux** (`tac` resolves there) →
  mitigation: it is a `hooks-macos` workflow step, never a bats test, and step 15
  asserts that placement mechanically so a future contributor cannot "helpfully"
  move it into the suite.
- **T12 split by a well-meaning reviewer into "fix" + "guard"** → mitigation:
  hazard 2 is stated in this plan, in AC9's own text, in T12's `tasks.md` entry,
  and in the guard file's header comment.
- **The macOS job greened by installing GNU tools**, masking the defect class it
  exists to catch → mitigation: asserted from three directions — the ci.yml
  contract test (no `coreutils`/`gsed`/`gnubin`), the pre-bats runtime step, and
  the behavioral `--version` probe that catches a symlink-smuggled GNU binary.
- **A guard false positive on prose.** The portability guard deliberately flags
  commented, fenced and quoted occurrences and has no escape hatch. Cost accepted
  and pre-paid: `.speccraft/` and `specs/` are outside the scan root, so this
  spec's own quoted `sed -i` evidence is safe, and any future doc under a scanned
  surface relocates or rewords rather than annotating.
- **`verify-linux-pins.sh` destroys uncommitted work** → mitigation: fingerprint
  before worktree creation, `git worktree add --detach`, `trap` cleanup on every
  exit path, per-pin restart from one clean baseline, and a bats test that asserts
  byte-identity after a *failing* run (the contaminating case).
- **A `done:` predicate exceeds the 30s `tasks-verify --run` budget at close** →
  mitigation: measured — the full bats suite is 12s and `go test ./...` is 9.5s;
  the only long-running deliverable (step 19's triple-suite run) is recorded as a
  changelog line rather than re-executed by its predicate.

## Appendix A — SetStatus call-site inventory

Derived from `grep -rn 'SetStatus(' --include='*.go' tools/` at plan time. Nine
occurrences; T3 updates every one in a single edit.

Production (1):

| File | Line | Current | After T3 |
|---|---|---|---|
| `tools/cmd/speccraft-state/main.go` | 302 | `speccraft.SetStatus(args[1], args[2])` | routed through `setStatusCmd`, kind from the flag layer, default `speccraft.KindSpec` |

Definition (1): `tools/internal/speccraft/revision.go:291`.

Tests (8):

| File | Lines |
|---|---|
| `tools/internal/speccraft/revision_test.go` | 135 (`"reviewed"`), 143 (`"bogus"`), 173 (`"draft"` on closed) |
| `tools/internal/speccraft/frontmatter_writer_test.go` | 29, 41, 53, 71, 109 |

No other package references `SetStatus`; `SetRevision` is untouched (spec §Out of
scope — `revision:` is a `uint64` with identical semantics for every kind).

## Appendix B — GNU-form sweep methodology

Reproducible commands behind AC10's "exactly one file, seven mutations" claim and
AC9's "the live shipped surfaces are clean".

Enumerated-form pattern (word-boundary-guarded so `sed -i.bak` and identifiers
containing `tac` do not match):

```
(sed -i|(^|[^[:alnum:]_.-])(tac|readlink -f|grep -P|stat -c|date -d|base64 -w)([^[:alnum:]_-]|$)|0,/)
```

Shipped surfaces — `grep -rnE <pattern> hooks/ commands/ tools/ templates/ agents/ skills/`
yields exactly three hits, which are the three production defects this spec fixes:

- `commands/arch/decide.lib.sh:25` — `sed -i -E` + the `0,/re/` address
- `commands/pm/prioritize.lib.sh:25` — byte-identical in the substantive part
- `commands/spec/consolidate.lib.sh:409` — `| tac`

Nothing under `tools/`, `templates/`, `agents/`, `skills/`, or `hooks/` matches,
which is why step 11's decision to exclude `tools/**/*_test.go` costs nothing today.

Test surfaces — `grep -rlE <pattern> tests/` yields four files. **The
discriminator is "executed", not "mentioned":**

| File | Matches | Executed? | Disposition |
|---|---|---|---|
| `tests/hooks/spec-revise-preflight.bats` | 7 × `sed -i 's/…/'` at lines 695, 707, 719, 731, 744, 781, 793 | **yes** | ported in step 14 |
| `tests/hooks/frontmatter-writer-guard.bats` | lines 14, 15, 24 (fixture strings written to disk), 33/35/50 (grep patterns and a comment) | no | mention-only exclusion |
| `tests/hooks/spec-revise-selfheal.bats` | line 69, inside a `grep -qE` pattern | no | mention-only exclusion |
| `tests/e2e/assertions/test_session_env_writable.sh` | `stat -c` at lines 37, 41, 60 | yes | out of scope — `e2e-devcontainer` is Linux-only and never runs on `macos-14` |

Step 13 encodes this table as a standing bats assertion, including the
exclusion-list-is-exactly-these-files check, so the claim stays true rather than
being a plan-time snapshot.

## Appendix C — speccraft-state resolution and the stale-cache hazard

AC1 requires the four pre-existing arch/pm tests pass **unmodified**, and neither
`arch-decide.bats` nor `pm-prioritize.bats` exports `PATH`. AC2 requires a PATH
shim to intercept the binary. Both are satisfied by one ordered resolver, used
identically in both libs:

1. `$SPECCRAFT_STATE_BIN`, when set and executable — explicit operator override.
2. `command -v speccraft-state` — **this is what makes AC2's PATH shim work**, and
   in a real installation it resolves the plugin's own `bin/`, i.e. the matching
   version.
3. `$(dirname "${BASH_SOURCE[0]}")/../../bin/speccraft-state` — the plugin-local
   fallback, absolute-from-`BASH_SOURCE` per conventions.md §Bash. This is what
   makes the four unmodified tests pass in CI, where no ambient
   `speccraft-state` exists.

Measured hazard: in this devcontainer `command -v speccraft-state` returns
`~/.claude/plugins/cache/dcstolf-tools/speccraft/1.11.0/bin/speccraft-state`,
which predates `--kind`. Rule 2 therefore resolves a *stale* binary unless the
fresh build is prepended. Three mitigations, no test-file edits:

- Run bats as `PATH="$PWD/bin:$PATH" bats tests/hooks/` (every `done:` predicate
  in `tasks.md` does this; `./bin/speccraft-state` is the freshly built binary,
  never the cached plugin copy).
- `.github/workflows/ci.yml` prepends `$PWD/bin` to `$GITHUB_PATH` in both the
  `hooks` and `hooks-macos` jobs, after the build step.
- The helpers' failure diagnostic names the resolved binary path, so a
  version-skewed binary self-reports instead of looking like a logic bug.

Version skew fails loudly, not silently: a pre-0049 binary given
`set-status --kind design <file> decided` reads `--kind` as the path and `design`
as the status, rejects the status, and exits non-zero with stderr — which is
AC2-conformant behavior, not a regression to silent success.
