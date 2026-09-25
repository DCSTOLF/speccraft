---
id: "0049"
title: "Command-lib portability and sanctioned PM/Architect status writers"
status: draft
created: 2026-09-15
authors: [claude]
packages: ["commands/arch", "commands/pm", "commands/spec", "tools/cmd/speccraft-state", "tools/internal/speccraft", "tests/hooks"]
related-specs: ["0022", "0025", "0029", "0030", "0036"]
domains: [cross-env-portability]
---

# Spec 0049 — Command-lib portability and sanctioned PM/Architect status writers

## Why

A field report against installed plugin 1.6.1: `/speccraft:arch:decide` reported
success but left the design at `status: draft`, and dropped a stray
`design.md-E` sibling (byte-identical, 125672 bytes) next to it. The user was
told the transition had happened. It had not.

The cause is one line — `commands/arch/decide.lib.sh:25`, unchanged at HEAD:

```sh
sed -i -E "0,/^status:/s/^status: .*/status: $new/" "$file"
```

Two independent GNU-isms in one invocation. Under BSD sed, `-i` takes the backup
suffix as its next argument, so `-E` is consumed as the suffix (hence the `-E`
sibling); and the `0,/re/` address form is unsupported. No substitution is
applied, and because the function's last command *is* the `sed`, its exit status
is the function's — 0. The caller sees success. **The silent-success half is the
real defect**: a loud failure would have been a nuisance, whereas this one
advanced the workflow on a lie.

Three further findings from the sweep this report prompted, all load-bearing:

### The identical line exists in a second command

`commands/pm/prioritize.lib.sh:25` is byte-identical in the substantive part.
`/speccraft:pm:prioritize` has the same silent no-op on macOS. The report
correctly predicted this ("worth a sweep").

### The same failure class exists in a third, unrelated command

`commands/spec/consolidate.lib.sh:409` reverses history entries with `tac`,
which does not exist on macOS:

```sh
done < <(history_parse_entries "$H" | tac)
```

A missing command inside a process substitution yields empty input; the `while`
body never executes; `set -euo pipefail` does **not** fire (a process
substitution's exit status is never checked). Verified locally: the construct
survives with exit 0 and zero iterations. So on macOS
`consolidate_backfill_order` silently discards the entire history-chronological
replay ordering and emits only the history-less fallback set, in `created:`
order. Spec 0025's AC11 ordering contract is void on macOS, silently.

### Two existing guards should have caught this and did not

- **The frontmatter-writer meta-guard.** `.speccraft/conventions.md:201-207`
  already states that `status:`/`revision:` are mutated ONLY through
  `speccraft-state set-status`, and that "command libs never hand-roll a
  `sed -i` frontmatter edit." But `tests/hooks/frontmatter-writer-guard.bats:37`
  scopes its third filter to `spec\.md|SPEC_MD|spec_md`. These two libs target a
  `design.md` / `brief.md` through `"$file"`, so the scan never sees them. The
  PM/Architect artifacts (spec 0022) were never brought under the spec-0036
  guardrail — the rule was written for spec.md and the second and third artifact
  kinds arrived outside it.
- **CI.** `.github/workflows/ci.yml:48-59` has a `macos-14` job, but it runs
  `go test ./...` only; the bats suite is Linux-only. `tests/hooks/arch-decide.bats`
  **already** contains `@test "arch_set_status: draft -> decided"`, which asserts
  the exact transition that silently fails. No new test was needed to catch this
  bug — only a runner. That gap is why an entire class of shell-portability
  defects reaches users.

macOS is a primary platform for Claude Code, so every one of these is a
first-class correctness bug, not a theoretical portability nit.

## What

Eliminate the three defective invocations, close both guard gaps that let them
ship, and add the CI leg that makes this class self-catching.

**1. Route PM/Architect status transitions through the sanctioned writer.** Do
not portability-patch the `sed`. A hand-rolled frontmatter write is precisely
what the spec-0036 guardrail forbids, so a portable `awk`-to-temp rewrite would
merely re-earn the violation under the widened guard of item 3. `arch_set_status`
and `pm_set_status` keep their existing source-status gate (only `draft` may be
transitioned) and delegate the write to `speccraft-state set-status`, inheriting
the byte-safe `setFrontmatterField` (field order, BOM, per-line LF/CRLF, EOF
newline), the enum validation, closed-artifact immutability, and — the point — a
real non-zero exit status.

**2. Make the status enum artifact-kind-scoped.** `validStatuses`
(`tools/internal/speccraft/revision.go:183`) is the spec state machine and
contains neither `decided` nor `prioritized`, so item 1 cannot land without it.
Replace the flat map with a kind-scoped one (`spec` / `design` / `brief`) behind
`set-status [--kind spec|design|brief]`, defaulting to `spec`. A flat map
widened with the two new values is explicitly rejected: it would let a `spec.md`
be set to `decided` and dissolve three distinct state machines into one.
Closed-artifact immutability is kind-independent and applies to all three.

**3. Widen the frontmatter-writer meta-guard to all three artifact kinds.**
Extend the path-shape filter to the `design.md` / `brief.md` forms, keeping the
fixture-first, both-polarity, scope-conservatively-IN regime of
`.speccraft/conventions.md:162-184`. The pre-fix `arch_set_status` line is added
verbatim as a FORBIDDEN fixture, so the guard is pinned against the bug that
actually escaped rather than against a reconstruction of it.

**The guard's scan root stays `commands/` and must never widen to `specs/`.**
`tests/hooks/frontmatter-writer-guard.bats:56` scans `"$PLUGIN_DIR/commands"`
only. This is load-bearing once this spec closes: spec 0025's consolidation will
move this very spec to `specs/.archive/0049-command-lib-portability/spec.md`,
carrying the forbidden `sed -i` line quoted verbatim in the Why section above. A
scan root widened to `specs/**` would flag the spec's own historical evidence
and wedge the guard on its own archive. The invariant is stated here so a future
contributor reads it as a deliberate boundary rather than an oversight to
"improve", and a test asserts `specs/` is outside the scan root.

**4. Fix `tac`, and add a portability meta-guard.** Replace `tac` with a POSIX
reversal. Then a new fixture-first guard over the **shipped** surfaces
(`hooks/`, `commands/`, `tools/`, `templates/`, `agents/`, `skills/`) forbidding
the enumerated GNU-only forms. `tests/**` is outside the **guard's scan root** —
the suites are never installed into a user's environment, so a GNU-only form
there is not a shipped defect; the exclusion and its rationale are stated in the
guard's header comment so the scope is not later mistaken for an oversight.

**This is a scope boundary on the guard, not a portability exemption for the
tests, and the two must not be conflated.** Item 5 runs the bats suite *on
macOS*, so any GNU-only form a test actually executes will fail there regardless
of what the guard scans. Those are different mechanisms with different jobs: the
guard answers "did we ship a GNU-ism to a user?", the macOS runner answers "does
our own suite run on BSD userland?". Exactly one test file executes a GNU-only
form today (`spec-revise-preflight.bats`), and item 5 ports it rather than
exempting it — so after this spec there is no file that is both outside the
guard and failing on macOS. The remaining `tests/**` matches are non-executed
fixture strings, which is why the guard's exclusion costs nothing.

**5. Run the bats suite on macOS in CI.** A `hooks-macos` job mirroring `hooks`
on `macos-14`, running the full suite with Bash 5 + bats-core from Homebrew and
**no GNU userland on PATH**, after porting the seven GNU-only `sed -i` fixture
mutations in `spec-revise-preflight.bats`. This is the only one of the five that
catches *semantic* GNU-isms — an enumerated-form guard would never have flagged
the `0,/re/` address, only the `sed -i`. The guard is the cheap net; the runner
is the real one. Its value depends entirely on not installing GNU tools to make
it pass, which is why AC10 makes that a stated condition rather than a
convention.

## Acceptance criteria

1. Neither `commands/arch/decide.lib.sh` nor `commands/pm/prioritize.lib.sh`
   contains `sed`, `perl -i`, or any in-place rewrite; each performs its write by
   invoking `speccraft-state set-status`. The four pre-existing tests in
   `tests/hooks/arch-decide.bats` and `tests/hooks/pm-prioritize.bats`
   (`draft -> decided`, `draft -> prioritized`, and both `rejects non-draft
   source` cases) pass unmodified.
2. **No silent success, and no silent failure either.** *Every* non-zero exit
   path of `arch_set_status` and `pm_set_status` — missing file, non-`draft`
   source status, invalid status for the kind, closed artifact, and underlying
   write failure — returns non-zero **and** emits a non-empty diagnostic to
   stderr. A `return 1` with empty stderr is a defect under this AC: a silent
   non-zero is only half a fix for a bug whose essence was the caller being
   unable to tell what happened.
   The write-failure case is pinned by a **deterministic, uid-independent
   seam at each layer** — never by file permissions. A read-only *target file*
   does not work at all: `setFrontmatterField` routes through `AtomicWriteFile`
   (same-directory temp + `os.Rename`), and `rename(2)` succeeds into a writable
   parent regardless of the target's mode. A read-only *parent directory* does
   block a non-root user, but it is rejected too: it silently degrades to a
   no-op under root, so the test would pass for the wrong reason in any
   privileged environment, and permission-dependent fixtures are exactly the
   class of environment-sensitive test this spec exists to remove.
   - **Shell layer** (`arch_set_status` / `pm_set_status`): the bats test shims
     `speccraft-state` on `PATH` with a stub that exits non-zero and writes to
     stderr. This is the correct layer — the helpers invoke the binary as a
     subprocess, so no Go-internal seam is reachable from bats — and it is fully
     deterministic regardless of uid.
   - **Go layer**: the write failure is injected at spec 0035's `atomicRename`
     seam, which is already built for exactly this.
   Each test asserts all four of: non-zero exit, non-empty stderr, a
   byte-identical target file, and no leftover temp file in the artifact's
   directory.
3. Both helpers leave **no stray sibling file** in the artifact's directory. A
   test asserts the directory listing before and after a successful transition is
   identical except for the artifact's own content — in particular no
   `<file>-E`, `<file>.bak`, or temp remnant.
4. `speccraft-state set-status --kind design <design.md> decided` succeeds;
   `--kind design … prioritized` exits non-zero with an invalid-status error.
   `--kind brief <brief.md> prioritized` succeeds; `--kind brief … decided` exits
   non-zero. With no `--kind` flag the behavior is exactly today's `spec` enum:
   `reviewed`/`planned`/`in-progress`/`blocked`/`closed`/`draft` accepted, and
   both `decided` and `prioritized` rejected.
   Two shape questions are pinned by table-driven tests rather than left to
   discovery: (a) both `--kind design` and `--kind=design` are accepted, and the
   flag is accepted before the positionals (a flag after the positionals is a
   usage error, not a silent ignore); (b) `--kind` validates **only the status
   enum**, not that the target path actually is an artifact of that kind — a
   path-sniffing check would be a second, weaker authority over artifact
   identity, and the caller already knows the kind. An explicit test documents
   that `--kind design <brief.md> decided` therefore succeeds, so the choice is
   recorded as deliberate rather than discovered later as a bug.
   The Go API takes the kind as a typed parameter — `SetStatus(path string, kind
   ArtifactKind, status string)` with a string-backed `ArtifactKind` — replacing
   the current two-arg `SetStatus`. Every existing call site is updated in the
   same change; no compatibility wrapper is kept, because a wrapper that defaults
   the kind is exactly the silent-default surface this AC is trying to avoid.
   **`ArtifactKind` has no meaningful zero value, and the empty kind is an
   error, not a synonym for `spec`.** The three kinds are explicit non-empty
   constants (`KindSpec ArtifactKind = "spec"`, `KindDesign = "design"`,
   `KindBrief = "brief"`), and `SetStatus` rejects an empty or unrecognized
   `ArtifactKind` with a non-zero error before it validates the status. The
   no-`--kind` CLI default maps to `KindSpec` in the **flag-parsing layer only**,
   so the convenience default lives at the CLI boundary where it is visible and
   documented, and an uninitialized `ArtifactKind` reaching the Go API from any
   caller is a loud failure rather than a silent reinterpretation as `spec`. A
   test pins that `SetStatus(path, ArtifactKind(""), "draft")` errors.
5. Closed-artifact immutability holds for every kind: `set-status --kind design`
   against a design whose `status:` is `closed` exits non-zero and does not
   modify the file. Same for `--kind brief` and for the default kind.
6. A successful `set-status` on a design/brief changes **only** the first
   `status:` line: a test with a fixture carrying a BOM, CRLF terminators, and no
   EOF newline asserts every other byte is preserved.
7. The frontmatter-writer meta-guard FLAGS an in-place `status:` rewrite whose
   target is a `design.md`-shaped path, a `brief.md`-shaped path, or a
   non-literal variable target (`"$file"`, `$DESIGN`, `$BRIEF`) — including the
   pre-fix `arch_set_status` line carried verbatim as a fixture — and PASSES the
   existing permitted fixtures plus a read-only `awk -F': ' '/^status:/…'` on a
   design/brief. The live `commands/` tree scans clean.
8. `consolidate_backfill_order` contains no `tac` and returns the
   history-chronological (oldest-first) order followed by the history-less
   candidates. Pinned by a test that runs the function with `tac` **absent from
   `PATH`** and asserts the full expected order — a test that fails against the
   current implementation on any platform.
   The fixture must carry **both halves**: candidates that have parseable
   history entries *and* candidates that have none. An ordering assertion over a
   history-only fixture would go green against a fix that still drops the
   history-less half, which is the half the original `tac` bug did not touch —
   so a one-sided fixture would leave the composition untested precisely where
   the regression risk moved.
9. A new portability meta-guard is fixture-first and FLAGS each of: `sed -i`
   without a backup suffix, the `0,/re/` address form, `tac`, `readlink -f`,
   `grep -P`, `stat -c`, `date -d`, and `base64 -w`; PASSES the portable
   counterpart of each (`sed -i.bak`, `sed -n '/re/p'`, the reversal form from
   AC8, `stat -f` or a `speccraft-state` subcommand, …). It scans `hooks/`,
   `commands/`, `tools/`, `templates/`, `agents/`, `skills/` clean, and a test
   asserts `tests/` is outside its scan root.
   **Matching semantics are stated, because the forbidden forms are string
   prefixes of the permitted ones.** `sed -i` must not match `sed -i.bak` or
   `sed -i ''`; the guard matches `sed -i` only when followed by whitespace and
   a non-suffix token, and both permitted spellings ship as PASSES fixtures.
   The guard is a bounded lexical scanner over lines, not a shell parser, and it
   deliberately ignores nothing: a commented-out or fenced occurrence is FLAGGED
   rather than skipped, matching the spec-0036 "scope conservatively IN, never
   silently skip" rule — a guard that parsed comments would be evadable by
   moving code into a heredoc. Fixtures cover the commented, fenced, quoted, and
   line-continuation forms so the conservative behavior is pinned as intended
   rather than tolerated as an artifact.
   **There is deliberately no escape hatch, and the cost of that is accepted
   explicitly.** Any documentation under a scanned surface that needs to name a
   forbidden form must be relocated to `.speccraft/` or `specs/` — both outside
   the scan root — or reworded to avoid the literal string. A
   `# speccraft-guard: allow-gnu-form` style marker is rejected: an annotation
   that suppresses the guard makes the guard evadable by annotation, which is
   precisely the property it exists to deny, and the spec-0036 precedent already
   chose "scope conservatively IN" over a suppression mechanism. The cost is
   stated here so a future contributor hitting it reads a decision rather than a
   bug.
   **The permitted-fixture set for AC8's reversal form and the AC8 fix land in
   the same commit.** In the other order the guard rejects the very change that
   satisfies AC8, wedging the work behind its own enforcement.
   The guard's permitted counterpart for `stat -c` is NOT fixed to `stat -f`:
   a redirect into a Go helper is equally acceptable and is the option
   consistent with this repo's precedent of pushing platform-specific work into
   `speccraft-state` rather than choosing a shell polyfill.
10. `.github/workflows/ci.yml` runs the **full** `tests/hooks/` bats suite (all
    20 files) on `macos-14` with the helper binaries built, and that job is
    green. Four conditions make "full" achievable rather than aspirational:
    - **The one genuinely GNU-dependent test file is ported, not excluded.**
      A sweep of `tests/hooks/` found exactly one file that *executes* a
      GNU-only form: `spec-revise-preflight.bats:695-793`, seven
      `sed -i 's/…/'` fixture mutations. These are test-internal edits to a
      scratch spec.md, so porting them is a seven-line change. Porting beats an
      exclusion list, which would need maintaining and would silently grow.
      (`frontmatter-writer-guard.bats` also matches a naive grep, but its hits
      are fixture *strings* written to disk and never executed — it is portable
      as-is. The sweep's discriminator is "executed", not "mentioned".)
    - **Bash 5 is installed and is the interpreter actually used.** macOS ships
      Bash 3.2; this repo requires Bash 5+. The job installs bash and bats-core
      via Homebrew and invokes the suite through the installed Bash 5 — not the
      system `/bin/bash`. A test asserts the running `BASH_VERSINFO[0]` is >= 5
      so a silently-3.2 job fails loudly instead of passing for the wrong
      reason.
    - **No GNU userland on PATH ahead of BSD.** The job must not install
      `coreutils` or `gsed`, and must not prepend a `gnubin` directory. This is
      the load-bearing condition: a job made green by installing GNU tools
      would mask exactly the defects it exists to catch, and would have passed
      against all three bugs in this spec.
    - **The no-GNU condition is mechanically asserted, not merely stated.**
      Condition 3 is the load-bearing one, and a prose rule in a workflow file
      is enforced by nothing: a future contributor who adds `brew install
      coreutils` to green a flake trips no alarm and the suite silently starts
      passing against the wrong invariant. Condition 2 gets a runtime assertion
      for exactly this reason, so condition 3 gets one too. A test in the
      `macos-14` job asserts that each of `sed`, `stat`, `date`, `readlink`,
      `base64`, and `tac` either does not resolve at all (`tac` should not) or
      resolves outside `*/gnubin/*` and `*/coreutils/libexec/*`, and that
      `command -v gsed` returns non-zero. A silently GNU-greened job then fails
      loudly instead of masking the defect class this leg exists to catch.
    - **zsh needs no special handling** — macOS ships it as the default shell,
      so `lib-zsh-safety.bats` and `spec-consolidate.bats` gain coverage rather
      than needing an install step.
11. No fix in this spec is pinned *only* by the macOS job: reverting any one of
    the three production fixes (the two `sed -i` lines and the `tac`) makes at
    least one test fail **on Linux**. Because this is a claim about the test
    suite's coverage topology rather than a single assertion, it is
    operationalized as `scripts/verify-linux-pins.sh` — a documented,
    non-CI-gating helper that reverts each of the three fixes in turn and
    asserts a bats failure for each. The script existing and passing is the
    acceptance evidence; it is run by the author before the spec closes, and
    referenced from `tasks.md`.
    **The script must never mutate the caller's checkout.** A helper whose job
    is to revert production fixes is one bug away from destroying uncommitted
    work, and a revert left in place would contaminate every later check in the
    same run. So: it operates on a disposable copy (a temporary clone or
    `git worktree`, removed on exit including on failure), it restarts each of
    the three mutations from the same clean baseline rather than layering them,
    and it leaves the caller's working tree byte-for-byte unchanged. A test —
    or the script's own final self-check — asserts the checkout is unmodified
    after a full run, including after a run in which a pin check fails.

## Out of scope

- **Cleaning up stray `<file>-E` / `<file>.bak` siblings already on users'
  disks.** A defensive sweep that deletes files matching a pattern speccraft did
  not create is a worse bug than the one it tidies. Recovery is documented
  instead: delete the stray file and re-run the command (the artifact is still
  `status: draft`, so the gate accepts it). A **non-destructive** variant —
  `/speccraft:sync` *reporting* (never deleting) `<file>-E` / `<file>-[A-Z]`
  siblings with a recovery hint — is a reasonable follow-up spec and a better
  discovery surface for users who do not read changelogs, but it is a new
  feature on a different command and stays out of 0049.
- **`stat -c` under `tests/e2e/`.** The e2e suite runs only in the Linux
  devcontainer (`e2e-devcontainer`), never on the macOS runner, so its GNU-isms
  are not reachable by AC10 and are not shipped to users. Note this is now the
  *only* remaining test-side exclusion: AC10 ports the `tests/hooks/` GNU-isms
  rather than exempting them, so "tests are Linux-only" is no longer a blanket
  claim and must not be cited as one.
- **Windows / MSYS / busybox portability.** The target is BSD/macOS userland
  alongside GNU. Widening further needs its own spec and its own CI leg.
- **Auditing the Go binaries for platform assumptions.** `go test ./...` already
  runs on `macos-14`; this spec is about the shell surfaces that do not.
- **A shellcheck or actionlint CI lint.** Adjacent and already tracked
  separately; the guards here are targeted greps, not a general linter adoption.
- **Retrofitting `--kind` onto `set-revision`.** Only `status:` has divergent
  per-kind enums; `revision:` is a `uint64` with identical semantics everywhere.

## Resolved decisions

These were open questions at first review; both are now decided, so nothing
blocks `spec:plan`.

1. **Release sequencing — 0049 does NOT carry a version bump.** Decided by
   precedent: spec 0046 (`Release 1.16.0 — ledger write-locking`) was a
   dedicated release-only spec that carried the bump for the feature spec
   before it, and 0047 likewise shipped unbumped at 1.16.0 on the expectation
   of a later release spec. A separate release spec will carry 0047, 0048, and
   0049 together. **0049 therefore touches none of the six version locations**,
   and `spec:close` on 0049 is not blocked by the `feedback_bump_before_close`
   constraint, because that constraint binds only the release-carrying spec.
   This is the reversible half of the decision: if 0049 is later chosen to carry
   the release, the bump must be added *before* its `spec:close`, since
   closed-spec immutability makes it unfixable afterward. Recorded here rather
   than left implicit precisely so that choice is made deliberately.
2. **macOS runner cost — the job runs unconditionally.** AC10 specifies a job on
   every push and PR. If the 10x private-repo billing multiplier turns out to
   apply and the cost is unwelcome, the documented fallback is to gate it to
   `push` on `main` (as `e2e-devcontainer:97` already is), accepting that PRs
   lose macOS bats coverage. That fallback is a workflow-file edit with no
   effect on any other AC, so it does not need to be settled before planning.

## Open questions

_none_
