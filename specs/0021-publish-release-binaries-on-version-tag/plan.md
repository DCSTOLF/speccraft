---
spec: "0021"
status: planned
strategy: tdd
---

# Plan — 0021 Publish release binaries on version tag

## Overview

Spec 0021 is shell + CI/workflow centric. Frontmatter declares `packages: []`,
so there are **no Go test files to extend**. The test oracle here is the
established **sibling shell test under `tests/e2e/` wired into
`run_helper_unit_tests()`** pattern (specs 0014/0020) — these run credit-free in
both the `--language-only` CI path and the full lifecycle. Each shell-behavior
change is pinned by such a test, and writing the failing test FIRST (RED), then
editing the script (GREEN), satisfies the speccraft-guard TDD invariant for
shell work.

Two of the spec's acceptance criteria are partly **infra/operational outcomes**
that cannot be unit-asserted in CI. The plan separates, for every work item, the
**TDD-gated** part (pinned by a RED sibling test against a hermetic fixture) from
the **ops/manual** part (tag push, secret config), and tags each task `[TDD]` or
`[OPS]` in `tasks.md`.

### Resolved carry-forward decisions (from review.md synthesis)

These are decided here so implementation has no ad-hoc choices:

- **CF-1 (tag-push credential):** the auto-tag job pushes `vX.Y.Z` using a
  **repository-scoped PAT stored as the secret `RELEASE_TAG_PAT`**, used for the
  `git push origin <tag>` call — **never** the default `GITHUB_TOKEN` (GitHub's
  loop guard suppresses `on: push: tags` re-triggers for the built-in token, which
  would leave `release.yml` silently never firing — the exact bug class this spec
  eliminates). The PAT-vs-deploy-key choice is the PAT; configuring the secret is
  an `[OPS]` task. The version-diff *logic* that decides whether to create a tag
  is factored into a testable shell helper (`scripts/auto-tag.sh` `should_tag`)
  with a fixture-driven sibling test, separate from the push/secret.
- **CF-2 (CI tier + credential profile):** both new CI surfaces — the auto-tag
  job and the `release.yml` self-verify step — are **cheap-hermetic**, invoke no
  `claude -p`, and need no `ANTHROPIC_API_KEY`. They use only repo-scoped creds:
  `GITHUB_TOKEN` for read/verify/API, plus `RELEASE_TAG_PAT` for the single
  tag-push step. Neither belongs in the credit-gated tier. The optional secondary
  main/scheduled completeness guard is **not shipped** in this spec (kept out to
  avoid a second new CI job; the in-`release.yml` self-verify is the primary
  guard). This is recorded as a deliberate scoping decision below.
- **CF-3 (AC5 wording):** the testable invariant is "a merged version bump cannot
  remain untagged after the `main`-push workflow succeeds." `should_tag` returns
  true exactly when `plugin.json`'s version has no matching existing tag — the
  unit-asserted half. The end-to-end tag creation is observable only in CI run
  history on the next real bump (`[OPS]`/observational).
- **CF-4 (verify-release.sh scope):** `verify-release.sh` uses the **STRONG
  form** — it downloads each of the four platform tarballs and recomputes SHA-256
  against the `checksums.txt` entry, in addition to asserting HTTP 200 on all
  four tarballs + `checksums.txt`. `SPECCRAFT_RELEASE_BASE` makes this hermetic:
  the fixture test points it at a `file://` base with real tarballs + a real
  `checksums.txt` so download + recompute + the negative (corrupted/missing) cases
  run with no network.

## File-by-file approach

### New: `scripts/verify-release.sh` (AC1, AC4)
Given a version arg, build the four platform tarball URLs
`speccraft-<version>-{linux-amd64,linux-arm64,macos-amd64,macos-arm64}.tar.gz` +
`checksums.txt` under `${SPECCRAFT_RELEASE_BASE:-<github releases base>}/v<version>/`.
Assert HTTP 200 on each (via `curl -fsSL`, or `test -f` for a `file://` base),
download each tarball, recompute SHA-256, and compare to the matching
`checksums.txt` line. Exit 0 only if all four resolve and all four hashes match.
Loud, named failure otherwise. `set -euo pipefail`, absolute paths from
`${BASH_SOURCE[0]}`. Reused as `release.yml`'s final self-verify step.

### New: `scripts/auto-tag.sh` (AC5)
Houses the version-diff logic as pure, sourceable functions. `should_tag` reads
`plugin.json`'s version and the existing tag list (the tag list is **injected**
for testability — read from `git tag -l` in production, from a fixture string in
tests) and prints the tag name to create (`vX.Y.Z`) on stdout + exits 0 when no
matching tag exists; exits non-zero (no output) when the tag already exists. The
actual `git push origin <tag>` lives in the workflow step (using
`RELEASE_TAG_PAT`), NOT in the unit-tested function.

### Edit: `scripts/install-binaries.sh` (AC2, AC3)
- Honor `SPECCRAFT_RELEASE_BASE` override (default the current GitHub URL).
- Keep fetching `checksums.txt` (already does — the producer is what changes).
- Replace the `curl … 2>/dev/null && curl …` chain with an explicit
  `if ! curl …; then warn-naming-URL; fallback; fi` so `set -e` does not abort
  before the warning/fallback. The warning to stderr must name the failed URL.
- Write `.binary-provenance=download` on the download success path,
  `.binary-provenance=source` on the source-build fallback path.

### Edit: `scripts/doctor.sh` (AC3)
Read `.binary-provenance` (gitignored, sibling to `.binary-version`) and report
the distinct "built from source (download unavailable)" diagnostic state when it
contains `source`.

### Edit: `.github/workflows/release.yml` (AC1, AC4)
- Publish the checksum asset as `checksums.txt` (currently `checksums-merged.txt`:
  rename the merge output and the `files:` entry).
- Add a final job/step that runs `scripts/verify-release.sh "${github.ref_name#v}"`
  against the just-published release (after the release-create step), failing the
  release loudly on a partial/broken publish.

### Edit: `.github/workflows/ci.yml` (AC5)
Add an `auto-tag` job, `on: push` to `main`, cheap-hermetic, no
`ANTHROPIC_API_KEY`. It runs `scripts/auto-tag.sh` `should_tag`; when a tag is
needed it creates the annotated tag and `git push`es it using `RELEASE_TAG_PAT`.

### Edit: `.gitignore` (AC3)
Add `.binary-provenance`.

### New sibling tests under `tests/e2e/` (the RED oracles)
- `tests/e2e/verify_release_test.sh` — pins `verify-release.sh` (AC1).
- `tests/e2e/install_binaries_provenance_test.sh` — pins `install-binaries.sh`
  download/fallback/provenance behavior + `doctor.sh` reporting (AC2, AC3).
- `tests/e2e/auto_tag_version_diff_test.sh` — pins `auto-tag.sh::should_tag`
  version-diff logic against fixture tag lists (AC5).
- `tests/e2e/release_yml_asset_contract_test.sh` — static-grep meta-test that the
  producer (`release.yml`) and consumer (`install-binaries.sh`) agree on
  `checksums.txt` and that `release.yml` invokes `verify-release.sh` (AC1, AC4),
  plus deadlock-freedom: the verify guard is keyed to the pushed tag, and CI has
  no check that fails on bare `plugin.json`.

All four are sourced-`lib.sh` fixtures and wired into `run_helper_unit_tests()`.

## Test-first sequence

> Ordering rule honored: every GREEN is preceded by a RED. Symbol-introduction
> note: a brand-new RED test that *executes* a not-yet-existing script
> (`verify-release.sh`, `auto-tag.sh`) cannot have its first edit pass the
> speccraft-guard build-failure-is-not-RED check — the first symbol-introduction
> Edit/Write for each new script needs a **one-shot `/speccraft:spec:override`**
> (guardrails AC13 pattern). This is called out per step.

### Step 1 — verify-release.sh sibling test (RED)
- Add `tests/e2e/verify_release_test.sh` (source `lib.sh`, `note()` helper),
  Scenario A/B/C structure mirroring `revise_noop_assertion_test.sh`:
  - `Scenario A` (positive) — build a `file://` fixture base: a temp dir
    `v9.9.9/` containing the four tarballs + a correct `checksums.txt`; run
    `SPECCRAFT_RELEASE_BASE=file://$TMP scripts/verify-release.sh 9.9.9`; assert
    exit 0.
  - `Scenario B` (negative — missing asset) — drop one tarball; assert
    `verify-release.sh` exits non-zero and names the missing URL on stderr.
  - `Scenario C` (negative — checksum mismatch) — corrupt one tarball's bytes so
    its SHA-256 no longer matches `checksums.txt`; assert non-zero exit and a
    checksum-mismatch message. This is what makes it the STRONG form (CF-4).
- Tests fail: `scripts/verify-release.sh` does not exist yet.

### Step 2 — implement verify-release.sh (GREEN)
- Implement `scripts/verify-release.sh` per the file-by-file approach (HTTP-200 +
  download + SHA-256 recompute, `SPECCRAFT_RELEASE_BASE` honored, loud named
  failures). First create-file edit needs a one-shot
  `/speccraft:spec:override` (new-symbol/new-script; the Step-1 test cannot pass
  until the file exists).
- All Step-1 scenarios pass.

### Step 3 — install-binaries provenance + loud-failure sibling test (RED)
- Add `tests/e2e/install_binaries_provenance_test.sh` (source `lib.sh`):
  - `Scenario A` (download happy path, AC2) — `file://` fixture base with a valid
    tarball + correct `checksums.txt`; run `install-binaries.sh` with a scrubbed
    `PATH` (no `go`) and `SPECCRAFT_RELEASE_BASE` set into a temp `PLUGIN_DIR`;
    assert exit 0, binaries present, `.binary-provenance` == `download`, and that
    no source build ran (assert no go-build marker / go absent).
  - `Scenario B` (failed download is loud + falls back, AC3) — point
    `SPECCRAFT_RELEASE_BASE` at a 404/unreachable base with `go` available; assert
    (a) stderr warning text **naming the failed URL** before fallback, (b) exit 0
    via source build, (c) `.binary-provenance` == `source`.
  - `Scenario C` (doctor reports the distinct state, AC3) — seed
    `.binary-provenance=source` and run `doctor.sh`; assert it surfaces the
    distinct "built from source (download unavailable)" state.
- Tests fail: installer does not honor `SPECCRAFT_RELEASE_BASE`, does not write
  `.binary-provenance`, swallows the 404 with `2>/dev/null`, and `doctor.sh` does
  not read provenance.

### Step 4 — edit install-binaries.sh (GREEN, part 1 of Step-3 pin)
- Edit `scripts/install-binaries.sh`: `SPECCRAFT_RELEASE_BASE` override; replace
  the `&&`/`2>/dev/null` curl chain with `if ! curl …; then warn(URL); fallback;
  fi`; write `.binary-provenance=download` (success) / `=source` (fallback).
- Scenarios A and B of Step 3 pass.

### Step 5 — edit doctor.sh (GREEN, part 2 of Step-3 pin)
- Edit `scripts/doctor.sh`: read `.binary-provenance`; report the distinct
  "built from source (download unavailable)" state when it is `source`.
- Scenario C of Step 3 passes; all of Step 3 now green.

### Step 6 — auto-tag version-diff sibling test (RED)
- Add `tests/e2e/auto_tag_version_diff_test.sh` (source `lib.sh`):
  - `Scenario A` (no tag exists → tag) — fixture plugin.json version `1.1.0`,
    fixture tag list without `v1.1.0`; `should_tag` prints `v1.1.0`, exit 0.
  - `Scenario B` (tag exists → no-op) — same version, fixture tag list including
    `v1.1.0`; `should_tag` exits non-zero, prints nothing.
  - `Scenario C` (prerelease version) — version `1.2.0-rc1`, no matching tag;
    `should_tag` prints `v1.2.0-rc1`, exit 0 (prerelease tags allowed per spec).
- Tests fail: `scripts/auto-tag.sh` does not exist yet.

### Step 7 — implement auto-tag.sh should_tag (GREEN)
- Implement `scripts/auto-tag.sh` with the pure `should_tag` function (tag list
  injected for testability). First create-file edit needs a one-shot
  `/speccraft:spec:override` (new script).
- All Step-6 scenarios pass.

### Step 8 — release.yml / install-binaries asset-contract meta-test (RED)
- Add `tests/e2e/release_yml_asset_contract_test.sh` (source `lib.sh`), static
  grep over the workflow + installer (mirrors the live-predicate meta-test idea):
  - `Scenario A` — `release.yml` publishes the checksum asset as `checksums.txt`
    (and NOT `checksums-merged.txt` in the `files:` list). FAILs while the
    workflow still uploads `checksums-merged.txt` — the RED.
  - `Scenario B` — `release.yml` invokes `scripts/verify-release.sh` as a step
    (AC4 primary guard wired in).
  - `Scenario C` (deadlock-freedom, AC4) — assert the verify guard is keyed to the
    pushed tag (`github.ref_name`) and that no CI workflow has a step failing on
    the bare `plugin.json` version absent a tag; also assert
    `install-binaries.sh` fetches `checksums.txt` (consumer side of the contract).
- Tests fail: `release.yml` still uploads `checksums-merged.txt` and has no
  verify-release step.

### Step 9 — edit release.yml (GREEN)
- Edit `.github/workflows/release.yml`: publish `checksums.txt`; add the final
  `verify-release.sh "${github.ref_name#v}"` self-verify step (cheap-hermetic,
  `GITHUB_TOKEN` only).
- All Step-8 scenarios pass.

### Step 10 — wire all sibling tests into run_helper_unit_tests() (GREEN/integration)
- Edit `tests/e2e/run.sh` `run_helper_unit_tests()` to add, in helper-first order:
  ```
  ( bash "$E2E_DIR/verify_release_test.sh" )              || fail "verify_release_test.sh failed";              pass "verify_release_test.sh"
  ( bash "$E2E_DIR/install_binaries_provenance_test.sh" ) || fail "install_binaries_provenance_test.sh failed"; pass "install_binaries_provenance_test.sh"
  ( bash "$E2E_DIR/auto_tag_version_diff_test.sh" )       || fail "auto_tag_version_diff_test.sh failed";        pass "auto_tag_version_diff_test.sh"
  ( bash "$E2E_DIR/release_yml_asset_contract_test.sh" )  || fail "release_yml_asset_contract_test.sh failed";   pass "release_yml_asset_contract_test.sh"
  ```
- All four sibling tests now run in the credit-free `--language-only` path and the
  full lifecycle. `bash tests/e2e/run.sh --language-only` is green.

### Step 11 — .gitignore (GREEN, AC3 support)
- Add `.binary-provenance` under the `.binary-version` line in `.gitignore`.
  (Pinned indirectly by Step-3 Scenario A/B which assert the file is written; the
  gitignore line prevents the marker from being committed.)

### Step 12 — ci.yml auto-tag job (OPS-wiring, AC5)
- Edit `.github/workflows/ci.yml`: add the `auto-tag` job (`on: push` to `main`,
  cheap-hermetic, no `ANTHROPIC_API_KEY`) running `auto-tag.sh` `should_tag` and,
  when a tag is needed, creating + `git push`ing it via `RELEASE_TAG_PAT`. The
  decision logic is already unit-pinned (Step 6/7); the push/secret usage is
  config that's verified operationally in CI run history.

### Step 13 — Refactor (optional)
- If `verify-release.sh` and the AC1 fixture-building in
  `verify_release_test.sh` duplicate the "list the four platform tarball names"
  literal, extract a single `platform_tarballs <version>` emitter (in
  `verify-release.sh`, sourced by the test) so the canonical four-name list lives
  once. All tests still pass.

## Ops / manual tasks (not TDD-gated)

- **Push `v1.1.0`** (AC1 real-world half): create + push the annotated `v1.1.0`
  tag to trigger `release.yml` end-to-end and produce the first published release.
  Pre-condition for AC1's "a published release actually exists." Observed in CI
  run history; not unit-assertable.
- **Configure `RELEASE_TAG_PAT`** (AC5/CF-1): create the repository-scoped PAT and
  store it as the `RELEASE_TAG_PAT` secret used by the auto-tag job's push step.
  Without it the auto-tag push step cannot re-trigger `release.yml`.

## Which steps need /speccraft:spec:override

- **Step 2** (first edit creating `scripts/verify-release.sh`) — new script; the
  Step-1 RED test references a symbol/file that does not yet exist, so its first
  introduction is a build-failure-not-RED case (guardrails AC13). One-shot
  override for that single create-file edit.
- **Step 7** (first edit creating `scripts/auto-tag.sh`) — same, one-shot
  override for the create-file edit.
- All other GREEN steps edit existing files already pinned by a freshly-added
  failing sibling test and do not need an override.

## Risk

- **CF-1 silent-trigger trap** → mitigation: the plan fixes the push credential
  to `RELEASE_TAG_PAT` (PAT), never `GITHUB_TOKEN`; the asset-contract meta-test
  (Step 8) asserts the verify step is wired, and the `[OPS]` task names the secret
  explicitly so the chain isn't dead on arrival.
- **Hermetic `file://` vs real HTTPS divergence in verify-release.sh** →
  mitigation: the script branches on the base scheme (`test -f` for `file://`,
  `curl -fsSL` for `http(s)://`) but uses the *same* SHA-256 recompute path for
  both, so the strong-form integrity logic exercised by the fixture is identical
  to production.
- **PATH-scrub in install-binaries test masking a real go presence** →
  mitigation: Scenario A runs the installer under an explicitly scrubbed `PATH`
  that excludes `go`, and asserts no source-build marker, so a download-path
  regression can't hide behind an ambient `go`.
- **Secondary completeness guard descoped** → mitigation: documented as a
  deliberate decision (CF-2); the in-`release.yml` tag-keyed self-verify is the
  primary, deadlock-free guard and is sufficient for AC4. A scheduled guard can be
  a follow-up spec if drift recurs.
- **Real-world AC1/AC5 halves not gated by CI** → mitigation: explicitly listed as
  `[OPS]` tasks tied to CI-run-history observation, not pretend-tested; the
  testable logic (verify-release strong form, should_tag diff) is fully unit-pinned.
