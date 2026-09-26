# Changelog — Spec 0051 (Release 1.17.0)

Closed 2026-09-26. `1.16.0 → 1.17.0`, carrying four specs that closed without a bump.

## What shipped

A version-string change and nothing else, across eight locations: 3 Go `const version`,
4 version oracles (renamed to encode `1170` so the bump registers a fresh red-candidate
under the TDD guard), and 2 JSON manifests. `bin/` rebuilt and `.binary-version`
re-stamped to `1.17.0`.

Carried: **0047** (per-task `done-means-v1` contract + `tasks-verify`), **0048**
(build-repair mode + first-touch red-candidate baseline + `build-repair-log`), **0049**
(command-lib portability + kind-scoped status writers + the `hooks-macos` job), **0050**
(writer-side state-key normalization, the release-binary clobber closed in three
consumers, the no-GNU probe corrected, `realpath -m` and the GNU checksum tool ported
out of shipped shell, `design-fingerprint`).

Minor rather than patch: four new subcommands, a new guard behaviour, three new
`state.json` session keys, no existing caller contract changed.

## Verification (AC6, AC7 — both post-push by necessity)

| Gate | Result |
|---|---|
| Tag | `v1.17.0` at the bump commit `bdefb29`, pushed by `auto-tag` via `RELEASE_TAG_PAT` |
| `Release` workflow | run 19, success |
| Assets | 4 platform tarballs + `checksums.txt` |
| `scripts/verify-release.sh 1.17.0` | **OK** — every tarball downloaded, SHA-256 recomputed, all matched (strong form) |
| Published binaries | all three report `1.17.0` |
| New subcommands in the published artifact | `tasks-verify` and `design-fingerprint` both dispatch |
| CI on the bump commit | run **#92**, all seven jobs green |

Pre-push: 350 bats, full Go suite, `go vet`, `drift scan-all`.

**The behavioural check on the published artifact is not ceremony.** The defect that cost
eight red runs was an installed plugin downloading a release whose binaries lacked
`tasks-verify`. Verifying that the v1.17.0 bytes actually answer the new subcommands
closes that loop at the distribution end, not merely in CI configuration — hash
verification alone would have passed on a correctly-packaged wrong build.

## Deviations

- **The bump and the close are separate commits.** The close-commit invariant requires
  `changelog.md` and the `status:` flip in ONE commit; it does not require the bump to
  join them. Splitting let this changelog record what CI and the release pipeline
  ACTUALLY reported about the tagged commit, instead of an intention. Closing alongside
  the bump would have meant asserting AC6 and AC7 before either could be observed —
  precisely the "a version bump is not done when the consts are edited" failure spec 0021
  exists to prevent.
- **Two predicates were wrong on first writing, in the same way.** T1 and AC3 asserted the
  ABSENCE of `1.16.0` from files whose stale-version negative checks must contain it —
  that is those checks' entire function — and from `ci.yml`/`tests/e2e/run.sh` comments
  that legitimately name the v1.16.0 release when explaining spec 0050's clobber. For a
  version bump the invariant is **polarity**: the positive expectation names the new
  version, the negative check names the old. AC3 was rewritten to say so; the alternative
  was padding the predicate with exclusions until it asserted nothing. This was the third
  occurrence of that shape in the same session.
- **A `done:` predicate that depends on ambient `PATH` is not an oracle.** T6 ran
  `bats tests/hooks/` bare and failed at close time, while the identical check had passed
  during implementation — the only difference being that I had prefixed
  `PATH="$PWD/bin:$PATH"` on the earlier invocation by hand. Without it, the cached
  installed plugin's `speccraft-state` (1.11.0, no `--kind`) shadows the repo's and four
  spec-0049 tests fail for an environmental reason. T6 now sets `PATH` itself. **Spec
  0050's T7, T12 and T15 carry the same latent flaw** and passed only by the same
  accident; they are closed and immutable, so this is recorded rather than fixed, and the
  general rule is now in `conventions.md`.
- **`memory-keeper` was not invoked**, as with spec 0050: this session runs under a
  standing instruction not to spawn subagents unbidden, so the changelog and ADR were
  written directly.

## Process observation worth acting on

Four consecutive specs deferred their bump, which is what `bump-before-close` exists to
prevent. Each deferral was individually defensible — 0047 shipped mid-arc, 0048 and 0049
explicitly deferred to "a later release spec carrying them together", 0050 was emergency
CI repair — and they compounded regardless. Two candidate responses, neither taken here:
give the convention teeth (a close-time check that a feature spec either bumped or names
the release spec that will), or accept release-carrying as a routine standalone spec and
stop treating the deferral as exceptional.

## Out of scope

- Any behaviour change.
- Follow-ups the four carried specs left open: probers for Python/JS/TS (the 0048 wedge is
  live there); `TrackEdit`'s unnormalized state keys, which make spec 0048 AC15's "every
  state key this package writes" not literally true; the aux-delegator false-quorum
  hazard; whether a source-built `bin/` should ever be overwritten by a release of the
  same version.
- History compaction (13 entries / 115KB), explicitly deferred by the developer.
