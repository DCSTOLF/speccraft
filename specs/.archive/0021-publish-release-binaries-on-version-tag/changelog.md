---
spec: "0021"
closed: 2026-06-18
---

# Changelog — 0021 Publish release binaries on version tag

## What shipped vs spec

The root cause was fixed exactly as specified: no `vX.Y.Z` tag had ever been
pushed, so the tag-triggered `release.yml` never ran, every release-asset URL
404'd, and `install-binaries.sh`'s silent `curl … 2>/dev/null && …` chain masked
it by falling through to a `go build`. The fix makes a bumped version
mechanically produce a tag, makes a missing/incomplete release a loud caught
failure, and fixes the producer/consumer asset-name contract.

Implemented (all five ACs satisfied):

- **AC1 / verify-release.sh (NEW `scripts/verify-release.sh`).**
  Release-completeness oracle in the **strong form** (CF-4 resolved): it
  downloads each of the four platform tarballs + `checksums.txt`, recomputes
  SHA-256, and fails loudly+named on any missing asset, missing checksum entry,
  or hash mismatch. Honors `SPECCRAFT_RELEASE_BASE` (with a `file://` fast-path)
  so the sibling test runs hermetically. Reused as `release.yml`'s final
  self-verify step.
- **AC2 / AC3 (`scripts/install-binaries.sh`, `scripts/doctor.sh`).**
  Installer honors `SPECCRAFT_RELEASE_BASE`; the `2>/dev/null` `&&` chain is
  replaced with explicit `if ! curl …; then echo "…failed…: $URL" >&2;
  download_ok=false; fi` (set -e safe), so a failed download names the URL on
  stderr before falling back. Writes a gitignored `.binary-provenance` =
  `download` | `source`. `doctor.sh` reads it and reports a distinct "built from
  source (download unavailable)" WARN state.
- **AC4 / AC5 (`.github/workflows/release.yml`, `.github/workflows/ci.yml`).**
  `release.yml` now publishes `checksums.txt` (was `checksums-merged.txt`) and
  appends a `verify-release.sh` self-verify step keyed to `github.ref_name`
  (deadlock-free: it only ever runs against an existing tag, never a bare
  `plugin.json` value). New `auto-tag` job in `ci.yml` (push to `main`, gated
  `if github.event_name == 'push' && github.ref == 'refs/heads/main'`) runs
  `auto-tag.sh should_tag` and, when the version is untagged, creates and pushes
  `vX.Y.Z` via `secrets.RELEASE_TAG_PAT` — NOT `GITHUB_TOKEN` (CF-1).
- NEW `scripts/auto-tag.sh` — pure `should_tag` (inputs injected via
  `SPECCRAFT_PLUGIN_JSON` / `SPECCRAFT_TAGS`) emitting `vX.Y.Z` when untagged,
  exiting non-zero when tagged.
- `.gitignore` gained `.binary-provenance`.

All four new sibling tests (`verify_release_test.sh`,
`install_binaries_provenance_test.sh`, `auto_tag_version_diff_test.sh`,
`release_yml_asset_contract_test.sh`) are wired into `run_helper_unit_tests()`
in `tests/e2e/run.sh` (helper-first order), so they gate close in BOTH the
credit-free `--language-only` path and the full lifecycle path.

## Deviations from spec/plan

- **No `/speccraft:spec:override` was needed (plan deviation).** The plan's
  "Which steps need /speccraft:spec:override" section assumed each new-script
  create-file edit (T2 verify-release.sh, T7 auto-tag.sh) would hit the
  build-failure-is-not-RED case and require a one-shot override (guardrails
  AC13). In practice `speccraft-guard` does not gate `.sh` files at all — only
  the four supported source languages (Go/Python/Rust/JS-TS) — so every script
  edit and sibling-shell-test edit went through without a TDD-gate block.
  tasks.md T2/T7 record this; the plan's override section is moot for this spec.
- **Checksum-collision fix beyond the named scope.** The spec scoped the asset
  fix to the *name* mismatch (`checksums-merged.txt` vs `checksums.txt`). The
  old `cat dist/checksums.txt | sort | uniq` merge step also produced colliding
  per-arch entries under `merge-multiple`; the release job now regenerates
  `cd dist && sha256sum *.tar.gz > checksums.txt` over all downloaded tarballs,
  so the published file carries one correct, bare-named entry per platform.
  Recorded as in-scope-adjacent: without it the strong-form verify (AC1/AC4)
  would fail on the real release.
- **Orthogonal CI paths-ignore tweak (agreed with user).** `ci.yml`'s
  `paths-ignore` (both `push` and `pull_request`) was extended to also skip CI
  for doc-only edits to `LICENSE`, `speccraft-technical-review.md`, and
  `speccraft-v1-spec.md`. This is a deliberate *denylist extension*, NOT an
  allowlist — an allowlist fails dangerous by silently skipping real changes,
  and `.claude-plugin/plugin.json` must keep triggering CI or the auto-tag job
  never fires. Not required by any AC; a hygiene improvement folded in.
- **Secondary main/scheduled completeness guard (What#4) deliberately NOT
  shipped.** The primary in-release self-verify is sufficient for AC4 and is
  deadlock-free; the optional secondary guard was descoped per the plan.
- **T15 (DRY `platform_tarballs` emitter) deferred** to keep the diff tight; the
  four-tarball name list currently lives in `verify-release.sh` plus two
  fixtures.

## Files touched

- scripts/verify-release.sh (new)
- scripts/auto-tag.sh (new)
- scripts/install-binaries.sh
- scripts/doctor.sh
- .github/workflows/release.yml
- .github/workflows/ci.yml
- .gitignore
- tests/e2e/run.sh
- tests/e2e/verify_release_test.sh (new)
- tests/e2e/install_binaries_provenance_test.sh (new)
- tests/e2e/auto_tag_version_diff_test.sh (new)
- tests/e2e/release_yml_asset_contract_test.sh (new)

## Cross-model review

Revision 1 changes-requested (codex + claude-p) on the AC4/AC5 ordering deadlock
and missing oracles. Revision 2 quorum met (codex approve-with-comments,
claude-p changes-requested) with four carry-forwards folded into the spec before
planning: CF-1 (push via PAT, not `GITHUB_TOKEN`), CF-2 (both new CI surfaces are
cheap-hermetic / `GITHUB_TOKEN`-only), CF-3 (AC5 reworded to "cannot remain
untagged after the main-push workflow succeeds"), CF-4 (strong-form checksums).

## Outstanding ops (not unit-gated)

- T13 `RELEASE_TAG_PAT` secret — DONE by user (fine-grained, Contents
  read/write, this repo).
- T14 — automatic on the push that lands this work: the `auto-tag` job will see
  `plugin.json=1.1.0` untagged and push `v1.1.0`, triggering `release.yml`.
  **Verify in CI run history:** the `auto-tag` job created `v1.1.0`,
  `release.yml` ran green (including the "Verify published release" step), and
  the four asset URLs + `checksums.txt` resolve. Watch-item: the verify step
  runs immediately after release creation — a transient asset-propagation 404 is
  possible on the first run; if so, a short retry/sleep is a one-line follow-up.

## ADR proposed for history.md

See the 2026-06-18 entry added to `.speccraft/history.md`.

## Conventions proposed

Folded into existing sections of `.speccraft/conventions.md` (no new top-level
headings):
- §Version bumps — auto-tag-on-bump must push via a PAT/deploy key, never
  `GITHUB_TOKEN`; release completeness is verified by `verify-release.sh`
  strong-form against a `SPECCRAFT_RELEASE_BASE` `file://` fixture.
- §Bash — `scripts/*.sh` (and their sibling shell tests) are NOT gated by
  `speccraft-guard`; no `/speccraft:spec:override` is needed for shell-only work.
- §CI — the `auto-tag` job is a third cheap-hermetic CI surface (`GITHUB_TOKEN`
  + `RELEASE_TAG_PAT`, no `ANTHROPIC_API_KEY`); `release.yml` self-verifies.
