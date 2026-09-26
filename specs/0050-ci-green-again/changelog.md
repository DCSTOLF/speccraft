# Changelog — Spec 0050 (CI green again)

Closed 2026-09-26. Run **#89** is green on all seven jobs — the first successful CI
run since **#78 on 2026-08-04**, eight red runs earlier.

## What shipped

Six defects, against the four stated at the outset. Two were found by fixing a
third, and one by fixing a fourth.

| # | Defect | Surface | Fix |
|---|--------|---------|-----|
| A | `SetRedCandidates` wrote `red_candidates[file]` verbatim; `siblingRedCheck` reads via `NormalizeStateKey` | `tools/internal/speccraft/state.go` | normalize in the writer |
| B | `install-binaries.sh` downloaded the last release over freshly built binaries | `ci.yml`, `session-start.bats` | stamp `.binary-version`; pin the release base in the suite |
| C | macOS `grep (BSD grep, GNU compatible)` read as a GNU build | `scripts/assert-no-gnu-userland.sh` | probe whether the tool NAMES ITSELF GNU |
| D | `realpath -m` unsupported on macOS | `hooks/pre-tool-use.sh` | pure-shell `canon_path` |
| E | GNU-only checksum tool in the fingerprint helper | `commands/sync.lib.sh` | delegate to `speccraft-state design-fingerprint` |
| F | E2E loaded HEAD's commands but RELEASE binaries | `tests/e2e/run.sh` | build + stamp before the lifecycle; assert `tasks-verify` answers |

## Deviations from the spec as written

- **ACs 10–15 were added mid-spec, not planned.** The spec opened with 9 ACs covering
  A–C. Fixing C let `hooks-macos` reach bats **for the first time in the project's
  history**; it ran 339 tests and failed 11, exposing D and E. Fixing B's sibling case
  exposed F. Each was the same pipeline failure and only observable once its
  predecessor was fixed, so they were folded in rather than deferred.
- **B, D and F share one root cause.** A gitignored version stamp lets the SessionStart
  hook replace locally built binaries with the last release. It hit the Linux bats job,
  then the macOS one, then the E2E — three consumers, one bug. Worth stating plainly
  because the three symptoms looked unrelated.
- **The `sha256sum` guard clause was mis-scoped on first writing.** It flagged a
  *pre-existing, correct* Go comment in `ledger_archive_cmd.go`. Go cannot execute a
  shell form, and the argv shape is already outside the guard by its own stated limit,
  so the clause excludes `*.go` — pinned by fixture `q14.go` rather than left implicit.
  A guard that fires on prose about a defect trains readers to weaken guards.
- **Delegation over a portability shim for E.** A `command -v` fallback would have
  fixed the portability alone. `designFingerprint` in Go already computed that exact
  value for `ledger-archive --expect`, so the shell copy was a second implementation of
  one number; two producers of a fingerprint can drift, which defeats its purpose.
- **A usage/dispatch parity test was added unplanned, and found three MORE undocumented
  subcommands** (`tasks-verify`, `review-commit`, `build-repair-log`). This corrected my
  own reasoning: I had read the truncated usage dump in the bats log as evidence of a
  stale binary, but a CURRENT binary produced the same dump. The clobber was real; that
  particular evidence was not. It was established instead by running the installer
  unpinned and watching `tasks-verify` disappear.
- **`memory-keeper` was not invoked** (close.md step 4). This session operates under a
  standing instruction not to spawn subagents unbidden, so the changelog and the ADR
  entry were written directly. Noted as a process deviation, not a silent one.

## Out of scope, recorded as follow-ups

- `TrackEdit` writes `edited_test_files` / `edited_prod_files` with a bare
  `filepath.Abs`, which makes spec 0048 AC15's "every state key this package writes"
  literally false. Nothing reads those lists through the normalizer today, so there is
  no defect — but the claim should be either honoured or narrowed.
- Build probers for Python, JS/TS and Rust: the spec-0048 wedge is still live there.
- Whether a source-built `bin/` should ever be overwritten by a release of the same
  version. The stamp closes the CI and test paths; the policy question is untouched.
- The release spec carrying 0047 + 0048 + 0049 + 0050 at 1.16.0.

## Override budget

Stated 0; **2 actual**. Both were caused by the INSTALLED plugin
(`~/.claude/plugins/cache/dcstolf-tools/speccraft/1.11.0`) being older than the fixes
in this repository:

1. It probes the PRE-edit build, so the transiently non-compiling half of a two-part
   rename made it refuse the edit that repairs the build — **spec 0048 defect A,
   verbatim, from a stale cache rather than from the code.**
2. A comment-only edit to a test file cleared that file's red candidates — **spec 0048
   defect B.** The failing test was present and failing on demand; the installed guard
   could no longer see it.

Neither bypassed a real RED. HEAD's guard would have allowed both edits: (1) silently,
via its `-overlay` probe of post-edit content, and (2) because candidates now derive
from a first-touch-only `red_baseline`. The most useful reading is that spec 0048's two
defects were re-demonstrated live, by the very session fixing their successor.

## Verification

- **343 → 350 bats** on Linux, and **343/343 on real BSD userland** (Bash 5.3.15,
  darwin23 arm64) with the no-GNU assertion confirming no shims — the macOS job's
  first green ever.
- Full Go suite, plain **and under a symlinked `TMPDIR`** (AC4), which is the
  mechanical stand-in for the macOS runner and reproduces defect A's 25 failures on
  Linux.
- `go vet`, `speccraft-drift scan-all`, and the locally runnable e2e cycles.
- Every negative assertion proven to bite by temporarily reintroducing what it forbids:
  the GNU pattern, the canonicalisation, and the e2e bypass-token check.
