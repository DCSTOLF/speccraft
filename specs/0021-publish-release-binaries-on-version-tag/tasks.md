---
spec: "0021"
---

# Tasks

Each task is tagged `[TDD]` (has a RED sibling test gating it) or `[OPS]`
(operational/manual, verified in CI run history — not unit-assertable). The AC(s)
each task satisfies are named in parentheses.

## Phase 1 — verify-release.sh (release-completeness oracle)

- [x] T1 [TDD] Add `tests/e2e/verify_release_test.sh` — Scenario A (all 4 tarballs
  + checksums.txt resolve via `file://` fixture → exit 0), B (missing asset →
  loud named failure), C (checksum mismatch → strong-form failure). RED. (AC1)
- [x] T2 [TDD] Implement `scripts/verify-release.sh` (HTTP-200 + download +
  SHA-256 recompute, `SPECCRAFT_RELEASE_BASE` honored). GREEN. (No override
  needed — speccraft-guard does not gate `.sh` files.) (AC1, AC4)

## Phase 2 — install-binaries provenance + loud failure; doctor

- [x] T3 [TDD] Add `tests/e2e/install_binaries_provenance_test.sh` — Scenario A
  (download happy path, no `go` on PATH → exit 0, binaries present,
  `.binary-provenance=download`, no source build), B (404 base + go present →
  stderr warning naming failed URL before fallback, `.binary-provenance=source`),
  C (`doctor.sh` reports distinct "built from source (download unavailable)"
  state). RED. (AC2, AC3)
- [x] T4 [TDD] Edit `scripts/install-binaries.sh` — `SPECCRAFT_RELEASE_BASE`
  override; `if ! curl …; then warn(URL); fallback; fi` (set -e safe); write
  `.binary-provenance=download`/`=source`. GREEN (Scenarios A, B). (AC2, AC3)
- [x] T5 [TDD] Edit `scripts/doctor.sh` — read `.binary-provenance`, report the
  distinct source-fallback state. GREEN (Scenario C). (AC3)

## Phase 3 — auto-tag version-diff logic

- [x] T6 [TDD] Add `tests/e2e/auto_tag_version_diff_test.sh` — Scenario A (no
  matching tag → prints `vX.Y.Z`, exit 0), B (tag exists → exit non-zero, no
  output), C (prerelease version → prints `vX.Y.Z-rcN`, exit 0). RED. (AC5)
- [x] T7 [TDD] Implement `scripts/auto-tag.sh` with pure `should_tag` (tag list
  injected). GREEN. (No override needed — `.sh` not gated.) (AC5)

## Phase 4 — producer/consumer asset contract + primary guard

- [x] T8 [TDD] Add `tests/e2e/release_yml_asset_contract_test.sh` — Scenario A
  (`release.yml` publishes `checksums.txt`, not `checksums-merged.txt`), B
  (`release.yml` invokes `verify-release.sh`), C (deadlock-freedom: guard keyed to
  pushed `github.ref_name`, no CI step fails on bare `plugin.json`;
  `install-binaries.sh` fetches `checksums.txt`). RED. (AC1, AC4)
- [x] T9 [TDD] Edit `.github/workflows/release.yml` — publish `checksums.txt`; add
  final `verify-release.sh` self-verify step (cheap-hermetic, `GITHUB_TOKEN`
  only). GREEN. Also fixed the per-arch checksum collision: regenerate
  `checksums.txt` over all tarballs in the release job. (AC1, AC4)

## Phase 5 — harness wiring + gitignore

- [x] T10 [TDD] Wire the four sibling tests into `run_helper_unit_tests()` in
  `tests/e2e/run.sh` (helper-first order); all four + the two pre-existing
  helper tests pass. (AC1, AC2, AC3, AC4, AC5)
- [x] T11 [TDD] Add `.binary-provenance` to `.gitignore`. (AC3)

## Phase 6 — CI auto-tag job + ops

- [x] T12 [OPS] Edit `.github/workflows/ci.yml` — added `auto-tag` job (`on: push`
  to `main`, gated by `if: push && ref==main`, no `ANTHROPIC_API_KEY`): runs
  `auto-tag.sh should_tag`, creates + `git push`es the tag via `RELEASE_TAG_PAT`
  (NOT `GITHUB_TOKEN`). Logic unit-pinned by T6/T7; push/secret verified in CI
  run history once the secret (T13) is set. (AC5)
- [x] T13 [OPS] Configured the `RELEASE_TAG_PAT` repository secret — fine-grained
  PAT, Contents: read/write, scoped to this repo only, added as an Actions
  secret. (AC5)
- [ ] T14 [OPS] **(automatic on next push of this work to `main`; verify in CI)**
  When this spec lands on `main`, the `auto-tag` job (now present in `ci.yml`)
  sees `plugin.json=1.1.0` untagged → pushes `v1.1.0` via `RELEASE_TAG_PAT` →
  triggers `release.yml`, which publishes + self-verifies the first release.
  **Verify after push:** the `auto-tag` job created `v1.1.0`, `release.yml` ran
  green (incl. the "Verify published release" step), and the four asset URLs +
  `checksums.txt` resolve. (AC1)

## Phase 7 — optional refactor

- [ ] T15 [TDD] (optional, **deferred**) Extract a single `platform_tarballs
  <version>` emitter so the canonical four-tarball-name list lives once. Skipped
  to keep the diff tight; the list currently appears in `verify-release.sh` and
  two fixtures. Low-value DRY follow-up. (AC1)
