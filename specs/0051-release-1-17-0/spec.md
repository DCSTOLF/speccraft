---
id: "0051"
title: "Release 1.17.0 — done-means contract, build-repair mode, portability, CI green"
status: in-progress
created: 2026-09-26
authors: [claude]
packages: ["tools/cmd/speccraft-state", "tools/cmd/speccraft-guard", "tools/cmd/speccraft-drift"]
related-specs: ["0047", "0048", "0049", "0050"]
domains: [release-pipeline]
---

# Spec 0051 — Release 1.17.0

## Why

**Four** specs have closed since 1.16.0 without a version bump — 0047, 0048, 0049 and
0050. Each closed after its own `spec:close` flipped it to `closed`, and closed-spec
immutability (spec 0036) rules out bumping under any of their umbrellas, so this is the
release step that carries all four.

Backlog of four is itself worth naming: the convention (see `.speccraft/conventions.md`
§Version bumps, and the `bump-before-close` rule) is that a release-carrying feature spec
does its bump BEFORE close. Four consecutive specs did not, and the reason is visible in
the history: 0047 shipped mid-arc, 0048 and 0049 deliberately deferred to "a later
release spec carrying them together", and 0050 was an emergency CI repair. The deferral
was defensible each time and compounded anyway.

**Releasing was blocked until now, and that is the load-bearing fact.** CI was red for
eight consecutive runs (#79–#86); the `auto-tag` → `release.yml` → `verify-release.sh`
pipeline runs on push to `main`, so a bump pushed during that window would have tagged
and published from a tree whose own suite was failing on three jobs. Run **#89** is the
first green run since #78 (2026-08-04), which is what makes this releasable.

## What the release carries

- **0047 — per-task `done-means-v1` contract.** `tasks.md` gains sub-checkboxes and a
  per-task `done:` predicate; `speccraft-state tasks-verify <tasks.md> [--run]` exits
  0/1/2 and is `/speccraft:spec:close` step 2. Bypass needs the literal
  `SKIP-TASKS-VERIFY`.
- **0048 — build-repair mode.** A broken Go build no longer forbids its own repair: a
  `go test -overlay` probe of post-edit content decides, bounded at 10 recorded edits per
  session. Red candidates now survive a no-new-test edit via a first-touch-only
  `red_baseline`. New `speccraft-state build-repair-log`.
- **0049 — command-lib portability.** Three GNU-only silent no-ops fixed; kind-scoped
  status enum with `speccraft-state set-status --kind design|brief`; the `hooks-macos` CI
  job.
- **0050 — CI green again.** Writer-side state-key normalization; the release-binary
  clobber closed in three consumers; the no-GNU probe corrected; `realpath -m` and the
  GNU checksum tool ported out of shipped shell; new `speccraft-state
  design-fingerprint`.

**Minor, not patch.** New backward-compatible surface: four new subcommands
(`tasks-verify`, `build-repair-log`, `design-fingerprint`, and `set-status --kind`), a new
guard behaviour, three new `state.json` session keys. No existing caller contract changes.

**Patch-vs-minor is not a free choice here.** `install-binaries.sh` keys its fast path on
an exact `.binary-version` match against `plugin.json`, and spec 0050 established that
every CI job and the e2e harness now stamp that value. A bump therefore invalidates every
existing stamp and is the mechanism by which installed plugins pick up the new binaries —
which is precisely the staleness that cost eight red runs.

## What — the eight version locations

The pattern established by prior bumps (0032/0034/0035/0036/0041/0042/0043/0044/0046):

- **3 Go `const version`** — `tools/cmd/speccraft-{state,guard,drift}/main.go`.
- **4 grep/const oracles** — the sibling `version_test.go` for each binary, plus
  `tools/internal/speccraft/manifest_version_test.go` (the JSON-manifest grep oracle).
- **2 JSON manifests** — `.claude-plugin/plugin.json` and
  `.claude-plugin/marketplace.json`.

Each version-test function name encodes the version, so a bump **renames** the test
(registering a fresh red-candidate under the TDD guard) and updates its expectation to
`1.17.0` — a runtime RED against the still-`1.16.0` const — before the const/manifest
edit makes it GREEN. Each oracle also carries a NEGATIVE check rejecting the stale
version, so a half-applied bump fails rather than passing on the new value alone.

## Acceptance criteria

1. All three binaries report `1.17.0` via `--version`, and each `version_test.go` is
   renamed to encode `1170` with its expectation updated and its stale-version negative
   check advanced to reject `1.16.0`.
2. `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` both read
   `"version": "1.17.0"`, asserted by `manifest_version_test.go`'s positive match AND its
   negative check against `1.16.0`.
3. No **live version declaration** still reads `1.16.0` — i.e. no `const version =` and
   no `"version":` key outside `specs/**`. Deliberately narrower than "no occurrence of
   `1.16.0` anywhere", which was the first wording and is simply false: the stale-version
   negative oracles MUST contain the old string (that is their entire function), and
   prose in `ci.yml` and `tests/e2e/run.sh` legitimately names the v1.16.0 release when
   explaining the spec-0050 clobber. A predicate broad enough to forbid those would have
   to be contorted with exclusions until it no longer asserted anything — the useful
   invariant is about declarations, so that is what is checked, plus a positive assertion
   that the negative oracles still reference `1.16.0`.
4. `go test ./...`, `go vet`, the full bats suite and `speccraft-drift scan-all` are green
   before the bump is pushed. The bump lands INSIDE this spec, before its close.
5. `./bin/` is rebuilt from the bumped source and `.binary-version` re-stamped, so the
   dogfooding hooks in this very repo do not keep running 1.16.0 binaries against a
   1.17.0 manifest — which would make `install-binaries.sh` download the (not yet
   published) 1.17.0 release and fail.
6. The release is not "done" at the bump (spec 0021): a `v1.17.0` GitHub Release must
   exist carrying the four platform tarballs plus `checksums.txt`, with
   `scripts/verify-release.sh` passing strong-form against the published bytes. The tag
   is pushed by `auto-tag` using `RELEASE_TAG_PAT`, never `GITHUB_TOKEN`.
7. CI must be green on the bump commit itself. A red run means the tag published from a
   failing tree and the release is withdrawn rather than patched forward.

## Out of scope

- Any behaviour change. This spec edits version strings and nothing else.
- The follow-ups the four specs left open: probers for Python/JS/TS (the 0048 wedge is
  live there), `TrackEdit`'s unnormalized state keys, the aux-delegator false-quorum
  hazard, and whether a source-built `bin/` should ever be overwritten by a release of
  the same version.
- History compaction (13 entries / 115KB); explicitly deferred by the developer.

## Open questions

_none_
