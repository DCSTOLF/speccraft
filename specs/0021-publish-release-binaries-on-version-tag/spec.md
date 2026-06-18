---
id: "0021"
title: "Publish release binaries on version tag"
status: closed
created: 2026-06-18
authors: [claude]
packages: []
related-specs: ["0019-bump-version-to-1-1-0"]
---

# Spec 0021 — Publish release binaries on version tag

## Why

When a user installs the speccraft plugin and starts using it, Claude silently
compiles the Go helper binaries from source at session start instead of
downloading prebuilt release assets — and on machines without `go` on PATH the
plugin fails outright with the doctor message.

Root cause: the helper binaries are delivered exclusively through GitHub
Release assets (`bin/*` and `.binary-version` are gitignored and never ship with
the plugin, per the "never commit binaries" hard rule). `scripts/install-binaries.sh`
builds a download URL from `plugin.json`'s version
(`…/releases/download/vX.Y.Z/speccraft-X.Y.Z-<platform>.tar.gz`). The Release
workflow (`.github/workflows/release.yml`) triggers **only** on `on: push: tags: [v*]`.
No git tag has ever been pushed — `git tag -l` and `git ls-remote --tags origin`
are both empty, and `GET /releases` returns `[]`. Therefore:

- Every download URL 404s (verified: HTTP 404 for the v1.1.0 linux-arm64 asset),
  for **every** version — `1.0.0` never had a release either.
- `install-binaries.sh` swallows the 404 (`curl -fsSL … 2>/dev/null`) and falls
  through to its `go build` source-fallback, which has silently masked the fact
  that the release pipeline has never run end-to-end.
- Spec 0019's `1.0.0 → 1.1.0` bump made it visible by invalidating cached
  `.binary-version=1.0.0` stamps, re-triggering the fetch→404→rebuild cycle.

A second, latent defect would surface the moment a release *does* exist: the
producer and consumer disagree on the checksum file name. `release.yml` uploads
`checksums-merged.txt`, but `install-binaries.sh` fetches `checksums.txt`
(`SUMS_URL=".../v${EXPECTED}/checksums.txt"`). Because the tarball and checksum
downloads are chained with `&&`, the checksum 404 alone would re-trigger the
source fallback even with all tarballs present. The asset-name contract must be
made consistent as part of this fix.

This means the documented "download a tarball on first use (≤10 ms), no Go
required" experience does not exist for any user, and regressions of this kind
are invisible because the fallback succeeds quietly wherever Go happens to be
installed.

## What

Make release assets actually get published for the current plugin version, make
the producer/consumer asset contract consistent, and make a missing/incomplete
release a loud, caught failure instead of a silent source build.

1. **Remediate v1.1.0:** create and push an annotated `v1.1.0` tag so
   `release.yml` runs and publishes the four-platform tarballs + a checksum file,
   and verify the asset URLs resolve. v1.1.0 is treated as the first published
   release; superseded versions (1.0.0) are **not** backfilled (Q3).
2. **Fix the asset-name contract:** make `install-binaries.sh` and `release.yml`
   agree on the checksum file name (standardise on `checksums.txt` as the
   published asset), so a present release is actually installable.
3. **Automate tag-on-version-bump (Q1):** a `main`-push CI job detects when
   `.claude-plugin/plugin.json`'s version has no matching `vX.Y.Z` tag and
   creates+pushes that tag, which triggers `release.yml`. This makes "a version
   bump produces a release" mechanical rather than a manual checklist step. The
   tag **must** be pushed with a credential that re-triggers workflows — a PAT or
   deploy key — **not** the default `GITHUB_TOKEN`, because GitHub intentionally
   suppresses `on: push` (incl. `tags`) re-triggers for events caused by the
   built-in token (its infinite-loop guard). Pushing the tag with `GITHUB_TOKEN`
   would leave `release.yml` silently never firing — reproducing this very bug
   class. (Acceptable alternatives if a PAT/deploy key is undesirable: have the
   auto-tag job `workflow_dispatch` / `workflow_call` into the release build
   directly instead of relying on the tag-push event.)
4. **Add a release-completeness guard (Q2), deadlock-free by construction:** the
   guard keys off the **tag**, never off the bare `plugin.json` value, so it can
   never observe the legitimate transient "version bumped, tag/release not yet
   published" state:
   - **Primary:** a final verification step inside `release.yml` (runs after the
     upload, on the tag) that asserts the release for the just-pushed tag carries
     all four platform tarballs + the checksum file and that each asset URL
     resolves. A broken/partial publish fails the release job loudly.
   - **Secondary (optional, main/scheduled):** a check that fails only when a tag
     `vX.Y.Z` matching `plugin.json` **exists** but its release is missing or
     incomplete — i.e. an actually-broken state, not a pending one.
5. **Stop the source-fallback from hiding failures:** when the download path is
   taken and fails, `install-binaries.sh` must emit a visible warning naming the
   failed URL (not silenced) before falling back, and record provenance so
   `scripts/doctor.sh` can report "built from source (download unavailable)" as a
   distinct diagnostic state.

### Design decisions (resolving the review)

- **Deadlock-free ordering invariant:** version bump merges to `main` →
  auto-tag job pushes `vX.Y.Z` (via PAT/deploy key, per What#3) → `release.yml`
  builds + publishes + self-verifies. No CI check ever fails on the bare presence
  of an unreleased version in `plugin.json`; completeness is only ever asserted
  against an *existing tag*.
- **CI tier + credential profile (spec-0008 job-split convention):** all CI
  surfaces this spec adds — the auto-tag job (What#3), the `release.yml`
  self-verify step and the optional main/scheduled completeness guard (What#4) —
  are **cheap-hermetic** jobs that invoke no `claude -p` and need no
  `ANTHROPIC_API_KEY`. They use only repo-scoped credentials: `GITHUB_TOKEN` for
  read/verify/API calls, plus the tag-push PAT/deploy key from What#3 for the
  single tag-creation step. None belong in the credit-gated tier.
- **Provenance marker:** `install-binaries.sh` writes a gitignored
  `.binary-provenance` file alongside `.binary-version`, containing `download` or
  `source`. `doctor.sh` reads it to distinguish the two states. (Marker file, not
  active re-check — keeps `doctor.sh` offline and deterministic.)
- **Configurable release base:** the release base URL becomes overridable via an
  env var (e.g. `SPECCRAFT_RELEASE_BASE`) so shell tests can point the installer
  at a local fixture tarball/`file://` path and exercise download + checksum +
  failure paths hermetically, without network. This also de-hardcodes the URL
  (and resolves the `dcstolf` vs `DCSTOLF` case note).
- **`set -euo pipefail` interaction:** the failing `curl` must be caught with an
  explicit `if ! curl …; then warn; fallback; fi` rather than a `&&` chain with
  `2>/dev/null`, or `set -e` aborts before the warning/fallback can run.
- **"Complete" release:** exactly the four tarballs
  `speccraft-<version>-{linux-amd64,linux-arm64,macos-amd64,macos-arm64}.tar.gz`
  plus `checksums.txt`, on a **published** (non-draft) release. Prerelease
  (tag containing `-`) is allowed but must still carry the full asset set; draft
  releases do **not** count.

## Acceptance criteria

Each criterion names its verification oracle. Shell changes
(`install-binaries.sh`, `doctor.sh`, the new release-verify script) are pinned by
sibling shell tests wired into the existing `run_helper_unit_tests()` harness,
mirroring spec 0020's `revise_noop_assertion_test.sh` — these run credit-free.

1. **Release exists and is installable.** A published (non-draft) GitHub Release
   exists for the version in `.claude-plugin/plugin.json`, carrying all four
   platform tarballs plus `checksums.txt`, and the URLs `install-binaries.sh`
   constructs for the host platform's tarball **and** checksum file both resolve
   (HTTP 200).
   *Oracle:* `scripts/verify-release.sh <version>` (new) asserts HTTP 200 on the
   four tarball URLs + `checksums.txt`, and verifies checksums in the **strong
   form**: it downloads each tarball and recomputes its SHA-256 against the
   `checksums.txt` entry (not merely asserting the file resolves and lists four
   names), since only the strong form proves the published bytes are actually
   installable. Run as the final step of `release.yml` and reusable by the CI
   guard. RED→GREEN via a sibling shell test using a fixture base URL.

2. **Download happy path needs no Go.** With `go` absent from PATH,
   `scripts/install-binaries.sh` installs via download (checksum verified), writes
   `.binary-provenance=download`, and exits 0 without invoking `go build`.
   *Oracle:* a shell test runs the installer with a scrubbed PATH against a local
   fixture release served through `SPECCRAFT_RELEASE_BASE` (no network), asserting
   exit 0, binaries present, and that no source build ran.

3. **Failed download is loud and diagnosable.** When the download path fails,
   `install-binaries.sh` prints a warning to stderr naming the failed URL before
   any fallback, writes `.binary-provenance=source` when it falls back, and
   `scripts/doctor.sh` reports that provenance as a distinct "built from source
   (download unavailable)" state.
   *Oracle:* a shell test points `SPECCRAFT_RELEASE_BASE` at an unreachable/404
   base, asserting (a) the warning text + URL on stderr, (b)
   `.binary-provenance=source`, (c) `doctor.sh` surfaces the distinct state.

4. **CI guards release completeness without deadlock.** `release.yml` fails
   loudly when the release it just published for a pushed tag lacks any of the
   four tarballs or the checksum file; and no CI check fails merely because
   `plugin.json` names a version whose tag/release does not yet exist.
   *Oracle:* the AC1 `verify-release.sh` invocation wired as a required final step
   of `release.yml`; the deadlock-freedom property asserted by inspecting the
   guard's trigger (keyed to an existing tag, never to bare `plugin.json`).

5. **Version bump mechanically produces a tag.** Merging a `plugin.json` version
   change to `main` causes a matching `vX.Y.Z` tag to be created and pushed by CI
   (which in turn triggers `release.yml`); a bumped version **cannot remain
   untagged after the `main`-push workflow succeeds**, with no manual tagging step.
   *Oracle:* the auto-tag job's logic (diff `plugin.json` version vs existing
   tags) is unit-tested in shell against fixture inputs; end-to-end tag creation
   is observable in CI run history on the next real bump.

## Out of scope

- Build-time `-ldflags` version injection (deferred follow-up from specs
  0018/0019) — the hardcoded-const version mechanism is unchanged here.
- Committing prebuilt binaries to the repo (forbidden by the hard rule); release
  assets remain the sole delivery channel.
- Windows-native builds (WSL remains the supported path).
- Backfilling a `v1.0.0` release (Q3: 1.1.0 is the first published release).
- Changing what the binaries do or the TDD invariant; this spec is purely about
  packaging/distribution and its CI guards.

## Open questions

_none_
