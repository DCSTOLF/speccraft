---
id: "0050"
title: "CI green again: unnormalized red-candidate keys, a release-binary clobber, and a GNU-compatible BSD grep"
status: closed
created: 2026-09-25
authors: [claude]
packages: ["tools/internal/speccraft", "tools/cmd/speccraft-guard", "scripts", ".github/workflows", "tests/hooks"]
related-specs: ["0018", "0047", "0048", "0049"]
domains: [tdd-guard, cross-env-portability]
---

# Spec 0050 — CI green again

## Why

Every CI run since spec 0047's work landed has failed — eight consecutive runs
(#79 through #86) on `main`. The last green run was #78, on 2026-08-04. Three
independent defects are involved, and each one had been green locally, which is
the fact that matters: the local suite is not a proxy for CI, and two of the
three are only observable on a platform or in a filesystem layout the local
devcontainer never presents.

### Defect A — a state key written by one spelling and read by another

Spec 0048 introduced `NormalizeStateKey` and its AC15 called it "the single
canonical path normalizer for every state key this package writes".
`SetRedCandidates` does not apply it. It stores `s.Session.RedCandidates[file]`
verbatim, trusting every caller to have normalized first, while
`siblingRedCheck` reads that map through `redCand[NormalizeStateKey(sib)]`.

A caller passing a merely-absolute path therefore writes a key the reader can
never find, and the guard reports **"No test was added this session"** for a
session that added one — the exact user-visible failure that spec 0048 existed to
remove, reintroduced through a different door.

This is invisible on Linux and fires on macOS, because `t.TempDir()` there hands
back `/var/folders/…`, a symlink to `/private/var/folders/…`. 25 tests in
`speccraft-guard` fail on the macOS runner and pass on the Linux one. The
divergence is not about macOS: it is about whether any ancestor of the path is a
symlink, which is equally true of a checkout under a symlinked home directory on
Linux. Pointing `TMPDIR` at a symlink reproduces all 25 failures on Linux, and
that is how they were diagnosed.

The writer is the right place to fix it. `CaptureRedCandidates` already
normalizes; `SetRedCandidates` is the sibling that does not, and a per-call-site
fix leaves the trap armed for the next caller.

### Defect B — the SessionStart hook installs release binaries over freshly built ones

`tests/hooks/session-start.bats` runs the real `hooks/session-start.sh` with
`CLAUDE_PLUGIN_ROOT` pointed at the real repository. That hook calls
`scripts/install-binaries.sh`, which — finding no `.binary-version` stamp, since
it is gitignored and absent on a fresh checkout — **downloads the v1.16.0 release
tarball and untars it over `bin/`**, replacing the binaries CI had just built
from HEAD.

`session-start.bats` sorts before `tasks-verify.bats`, so by the time the latter
runs, `bin/speccraft-state` is the last *released* build. `tasks-verify` shipped
in spec 0047 and is unreleased, so four tests fail with `unknown subcommand:
tasks-verify`.

The clobber is not new — it has happened on every CI run for as long as the test
has existed. It was harmless only while no test needed a subcommand newer than
the last release, so the first unreleased subcommand turned a long-standing
latent fault into a red main. The same mechanism is a live hazard for a developer:
build HEAD, start a session, and every hook silently runs released code.

### Defect C — macOS `grep` reports "GNU compatible", and the assertion read that as GNU

`scripts/assert-no-gnu-userland.sh` (spec 0049 AC10) probes each required tool
behaviourally: if it accepts `--version` and the output contains `GNU`, it is a
GNU build and the runner is rejected. On macos-14, `/usr/bin/grep` accepts
`--version` and prints:

```
grep (BSD grep, GNU compatible) 2.6.0-FreeBSD
```

That is BSD grep truthfully advertising GNU *compatibility*. The substring check
matched, so the assertion failed the job **before bats ran at all** — the macOS
suite has never once executed. A job that cannot start is worse than the GNU-
greened job AC10 was written to prevent, because it produces no signal in either
direction.

The bats fixture missed it by modelling BSD tools as *rejecting* `--version`,
which real macOS `grep`, `awk`, and `date` do not.

## What

Fix all three, and pin each against the environment that exposed it rather than
against the environment that hid it.

1. `SetRedCandidates` keys through `NormalizeStateKey`, like
   `CaptureRedCandidates` already does.
2. The guard's tests compute the read key the way production writes it, instead
   of with a bare `filepath.Abs`.
3. Both bats CI jobs stamp `.binary-version` after building, so
   `install-binaries.sh` takes its fast path and cannot reach the network;
   `session-start.bats` additionally points `SPECCRAFT_RELEASE_BASE` at an
   unreachable base so the test cannot install a release build over a
   developer's `bin/` either.
4. The GNU probe distinguishes a GNU *implementation* from a BSD tool declaring
   GNU compatibility, and the fixture models the real macOS strings.

## Acceptance criteria

1. `SetRedCandidates(root, file, ids)` stores its entry under
   `NormalizeStateKey(file)`. Asserted asymmetrically through a symlinked
   ancestor: the expected key is built from the resolved path with no call to the
   normalizer, so a regression making the normalizer a no-op cannot satisfy it.
2. One file reached by two spellings (symlinked and resolved) occupies exactly
   one entry in `red_candidates`.
3. `CaptureRedCandidates` is pinned to the same invariant, so the fix cannot
   regress on the capture side while passing on the set side.
4. `go test ./...` passes with `TMPDIR` pointed at a symlinked directory. This is
   the mechanical stand-in for the macOS runner and the pin that would have
   caught defect A on Linux; all 25 currently-failing guard tests pass under it.
5. No production caller of `SetRedCandidates` regresses: the guard's write path
   continues to normalize explicitly at its own touchpoint, so spec 0048 AC15's
   both-touchpoints scan still holds.
6. `scripts/assert-no-gnu-userland.sh` PASSES a tool whose `--version` output is
   `grep (BSD grep, GNU compatible) 2.6.0-FreeBSD`, and still FAILS a real GNU
   build (`grep (GNU grep) 3.11`, `sed (GNU sed) 4.9`, `date (GNU coreutils) 9.4`,
   and `GNU Awk 5.1.0` — which carries no parenthesis and would escape a
   paren-anchored pattern alone).
7. The bats fixture models BSD tools that ACCEPT `--version`, not only ones that
   reject it. The previous fixture's rejecting stubs are kept as a second shape,
   since both exist in the wild.
8. Running `hooks/session-start.sh` from the bats suite cannot replace
   `bin/speccraft-state` with a downloaded release build. Pinned by asserting
   `session-start.bats` constrains `SPECCRAFT_RELEASE_BASE`, and separately that
   both bats jobs in `ci.yml` write the version stamp after their build step.
9. The whole bats suite and `go test ./...` pass on Linux, unchanged in count
   except for the tests this spec adds.

### Found by fixing AC6 — the first-ever run of the macOS bats suite

Fixing defect C let `hooks-macos` reach bats for the first time. It ran 339
tests and failed 11, in two clusters, both production defects of exactly the
class spec 0049 was written to catch. They are in scope here because they are
the same pipeline failure and were only observable once C was fixed.

10. `hooks/pre-tool-use.sh` must not depend on `realpath -m`. macOS ships
    `realpath` without `-m`, so on BSD userland the invocation fails under
    `set -e` and the hook exits before reaching `speccraft-guard` — which means
    **both** the `state.json` single-writer guard and the entire TDD invariant
    delegation are inert on macOS, and the operator sees `realpath: illegal
    option -- m` instead of either guard's message. Replaced with the portable
    `cd "$(dirname …)" && pwd -P` idiom the repo already uses. Correctness
    argument for dropping `-m`: only the *directory* need exist, and when it does
    not, the target cannot be `<root>/.speccraft/state.json`, whose directory
    always exists — so exact-match behaviour is preserved.
11. `commands/sync.lib.sh`'s `sync_design_fingerprint` must not shell out to
    `sha256sum` (GNU coreutils only; macOS ships `shasum`). It delegates to a new
    `speccraft-state design-fingerprint <design>`, which exposes the
    `designFingerprint` Go helper that ALREADY computes this exact value for
    `ledger-archive --expect`. Delegation rather than a `command -v` fallback:
    the shell copy was a second implementation of a value Go already produces, so
    porting it in place would have kept two things that can drift.
12. Both portability meta-guards gain `sha256sum` and `realpath -m`, fixture-first
    (each forbidden form and its portable counterpart), and the live-tree scan is
    observed FAILING on the two real sites before they are ported. The guards
    passed over both defects, so extending them is not optional bookkeeping —
    a guard that missed the forms that took the job down would miss them again.
13. The bats suite's own `sha256sum` use (`tests/hooks/sync-workspace.bats`) is
    made portable while KEEPING an independent shell computation, so the test
    still checks the binary's fingerprint against a separately computed sha256
    rather than comparing the binary to itself.

### The E2E devcontainer job — the SAME clobber, one layer down

`E2E (devcontainer)` failed on runs #87 and #88 for a cause that is defect B again,
reaching a different consumer. It passed on #86 only because the failure depends on
a non-deterministic agent judgement.

14. `tests/e2e/run.sh` must build the plugin's binaries from source (and stamp the
    version, so the SessionStart hook's fast path skips the download) BEFORE the
    claude lifecycle. `--plugin-dir` loads HEAD's commands, hooks and skills, but the
    binaries they shell out to were being DOWNLOADED from the last release by the
    SessionStart hook — so the suite validated HEAD's markdown against release Go.
    `/speccraft:spec:close` step 2 calls `tasks-verify` (spec 0047, unreleased); the
    agent reported it "not present in the installed binary", ran each `done:`
    predicate by hand, and the run failed at `exists changelog.md` — a symptom three
    steps from its cause. The step asserts the built binary answers `tasks-verify`
    (exit ≠ 1) so a silent fallback to release behaviour is impossible.
15. The `[10/13]` close prompt must say what to do when the task-completion gate
    reports violations. Without that, the run's outcome depended on whether the
    `done:` predicates the agent authored at `[8/13]` still matched the code it wrote
    at `[9/13]`; twice they did not (a test renamed by a refactor; a
    `grep -v '^\./main.go$'` filter defeated by a path printed without `./`) and the
    agent correctly refused to proceed. The prompt instructs it to reconcile a stale
    LOCATOR and re-run — close.md's own option (a) — and deliberately does NOT supply
    `SKIP-TASKS-VERIFY`, because bypassing would stop exercising the gate altogether.
    Weakening a predicate remains forbidden: the work must still be done AND provable.

## Out of scope

- `TrackEdit` writes `edited_test_files` / `edited_prod_files` with a bare
  `filepath.Abs`, which makes spec 0048 AC15's "every state key this package
  writes" literally false. Nothing currently reads those lists through the
  normalizer, so there is no defect to fix today — recorded as a follow-up rather
  than widened into this spec.
- Build probers for Python, JS/TS and Rust (the spec-0048 wedge is still live
  there).
- The release spec carrying 0047 + 0048 + 0049 + this one. This spec must land
  before it, since a red main cannot be released.
- Changing `install-binaries.sh`'s download-first policy. The stamp and the
  fixture base close the CI and test-hermeticity holes; whether a source-built
  `bin/` should ever be overwritten by a release of the same version is a
  separate design question.

## Open questions

_none_
