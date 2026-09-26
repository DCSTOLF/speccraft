---
id: "0050"
title: "CI green again: unnormalized red-candidate keys, a release-binary clobber, and a GNU-compatible BSD grep"
status: in-progress
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
