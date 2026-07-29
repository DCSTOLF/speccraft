---
spec: "0008"
status: planned
strategy: tdd
---

# Plan — 0008 CI hardening

## Preamble

This spec's deliverables are predominantly **Bash, YAML, and Markdown** — a
devcontainer permission fix, a new flag on `tests/e2e/run.sh`, a new
GitHub Actions job, an observability wrapper around `claude -p`, and a
README note. Strict unit-test-style Go RED→GREEN doesn't apply. The
plan follows the spec-0007 pattern (see `specs/0007-python-e2e-fixture/plan.md`
Preamble): each AC is sequenced as a RED step that adds an assertion
(grep-based or behavioral, under `tests/e2e/assertions/` or `tests/docs/`)
followed by a GREEN step that adds the minimum implementation to make
the assertion pass.

Two ACs (#1 devcontainer fix, #5 `claude -p` failure-mode matchers)
have unknown root cause / unknown internal shape that the spec
deliberately leaves open. Each gets a **probe step before the fix**, so
the actual mechanism gets documented in 0008's `changelog.md` rather
than assumed.

## Implementation note — close-commit invariant

(Surfaced from codex round-3 approve's single non-blocking suggestion.)

The spec's §Post-merge verification (pre-close gate) requires that the
first green `e2e-language-only` run on `main` be recorded in
`specs/0008-ci-hardening/changelog.md` **before** the `status: closed`
flip. To stay safe from the closed-spec-immutability rule:

- The changelog edit (adding the run URL + AC #8/T10 retroactive
  satisfaction note) and the `status: draft` → `status: closed` flip on
  `spec.md` **must land in the same git commit** (the close commit).
- The parent commit of the close commit must still show
  `status: draft` (or whatever pre-close status the spec is at).
- No post-close changelog edits. If a defect is found after close, a
  follow-up spec is filed, not an edit to this one.

This is encoded as T13 in `tasks.md`.

## Test-first sequence

### Step 1 — AC #1 probe: root-cause `~/.claude/session-env` EACCES (RED, observational)

- Add `tests/e2e/assertions/test_session_env_writable.sh`:
  - `Test_SessionEnvDir_Writable_ByContainerUser` — after `devcontainer up`,
    `devcontainer exec ... id -u` and `devcontainer exec ... stat -c '%u %g %a' /home/vscode/.claude`
    must show the directory owned by `vscode:vscode` (uid 1000) and at
    least mode 0755. Then `devcontainer exec ... mkdir -p ~/.claude/session-env && touch ~/.claude/session-env/probe`
    must exit 0 and the probe file's owner must match the runner uid.
  - `Test_SessionEnv_Probe_DocumentsRootCause` — script emits to stdout
    the literal owner/mode of `/home/vscode/.claude` and
    `/home/vscode/.claude/session-env` (if it exists) before the
    mkdir, so the changelog can quote them verbatim.
- Tests fail today (pre-fix): the open question in spec §Open questions
  is exactly that we don't yet know whether the failure is (a) base
  image ownership, (b) named-volume mount ownership, or (c) both. The
  probe records which.
- **Output of this step is captured into 0008's changelog** as the
  documented root cause (spec §Open questions, item 2 — "The implementer
  should probe at start time and document the actual root cause in the
  changelog.").

### Step 2 — AC #1 fix: make `~/.claude/session-env` writable, idempotently (GREEN)

- Based on Step 1's findings, apply the smallest possible fix in **one
  of** (in order of preference, pick whichever the probe shows is
  sufficient):
  - **Option A (preferred if the named volume is the culprit):** add a
    block to `.devcontainer/setup.sh` that runs *before* the smoke
    check, idempotently fixing ownership:
    ```bash
    # AC #1 (spec 0008): ensure ~/.claude is writable by the container
    # user. The named volume mount in devcontainer.json sometimes lands
    # as root-owned on first create; reassert ownership here.
    if [ -d "$HOME/.claude" ]; then
      sudo chown -R "$(id -u):$(id -g)" "$HOME/.claude" || true
    fi
    mkdir -p "$HOME/.claude/session-env"
    ```
  - **Option B (if the base image is the culprit):** add a `RUN` in
    `.devcontainer/Dockerfile` that pre-creates the directory with the
    right ownership before the `USER vscode` line.
  - **Option C:** both, with Option A as a runtime backstop for the
    named-volume race.
- The fix must survive `Rebuild Container` — verify by running
  `devcontainer up --workspace-folder . --remove-existing-container`
  twice and re-running the Step 1 assertion both times.
- All Step 1 tests pass.

### Step 3 — AC #2 RED: `tests/e2e/run.sh --language-only` assertion (RED)

- Add `tests/e2e/assertions/test_language_only_flag.sh`:
  - `Test_LanguageOnly_FlagAccepted` — `bash tests/e2e/run.sh --language-only`
    exits 0 in an environment with `claude` absent from `PATH` and
    `ANTHROPIC_API_KEY` unset. (Strips both before invocation.)
  - `Test_LanguageOnly_DoesNotInvokeClaude` — runs the script with a
    shim `claude` on PATH that writes `CLAUDE_INVOKED` to a sentinel
    file on any invocation; asserts the sentinel was not created.
  - `Test_LanguageOnly_DoesNotCreateGoModule` — runs the script and
    asserts the chosen `TEST_ROOT` never contains `go.mod` or
    `main.go` (the `[1/N]` Go-module setup is skipped).
  - `Test_LanguageOnly_RunsAllThreeFixtures` — greps the script's
    stdout for evidence that `rust_inline_cycle.sh`,
    `rust_integration_cycle.sh`, and `python_cycle.sh` each ran
    (using their existing `OK:` / `==>` progress markers).
  - `Test_LanguageOnly_FixtureFailureExitsTwo` — sets a temporary
    `PATH` with a non-existent `cargo` shim that exits 2; the run
    must exit 2 (matching the existing `fail()` convention) and not 1 or 3.
- All tests fail because the flag does not yet exist.

### Step 4 — AC #2 GREEN: implement `--language-only` flag in `run.sh` (GREEN)

- Edit `tests/e2e/run.sh`:
  - Add an argv parse near the top (after `set -euo pipefail`,
    after the cargo-preamble) that recognizes a single
    `--language-only` flag and sets `LANGUAGE_ONLY=1`. Any other
    argument is rejected with `usage` and exit 2.
  - When `LANGUAGE_ONLY=1` is set, skip everything from `[1/9]`
    through `[7/9]` (no Go module, no `claude -p`) and execute
    only the Rust + Python fixture subshells in a clearly-marked
    section. The header announces `==> language-only mode` to make
    log inspection unambiguous.
  - Reuse the existing `RUST_E2E_DIR` resolution and the existing
    `fail`/`pass` helpers. Do **not** duplicate code paths — extract
    the three fixture invocations into a small `run_language_fixtures()`
    helper if needed so both the full path and the language-only
    path call the same function.
- All Step 3 tests pass.
- Verification: `bash tests/e2e/run.sh --language-only` exits 0 in
  a shell with `claude` absent and `ANTHROPIC_API_KEY` unset.

### Step 5 — AC #3 + AC #4 RED: workflow structural assertion (RED)

- Add `tests/docs/test_language_only_job.sh`:
  - `Test_LanguageOnlyJob_Exists` — `.github/workflows/ci.yml`
    contains a job whose key is `e2e-language-only` (grep-based;
    YAML parse not required since later asserts also grep).
  - `Test_LanguageOnlyJob_RunsOnPushAndPR` — the new job does **not**
    carry the `if: github.event_name == 'push' && github.ref == 'refs/heads/main'`
    gate the existing `e2e-devcontainer` job has.
  - `Test_LanguageOnlyJob_InvokesLanguageOnlyFlag` — the job's
    `run:` block contains the literal `bash tests/e2e/run.sh --language-only`.
  - `Test_LanguageOnlyJob_DoesNotPassAnthropicKey` — the job does
    **not** mention `ANTHROPIC_API_KEY` in any form (no `env:` key,
    no `--remote-env`, no `${{ secrets.ANTHROPIC_API_KEY }}`
    reference inside the job's lines).
  - `Test_LanguageOnlyJob_UsesSameDevcontainerInvocation` — the job
    uses the same `devcontainer up --workspace-folder .` invocation
    as `e2e-devcontainer`, so cache and image-build steps stay
    consistent (grep for the literal command).
  - `Test_CiYml_ParsesAsValidYaml` — if `python3 -c "import yaml"`
    or `yq` is available in the test environment, parse the file
    and fail on syntax error; if neither is present, skip with a
    clear `SKIP:` message rather than fail (so the assertion is
    runnable without dev-tooling installs).
- All tests fail because the job does not yet exist.

### Step 6 — AC #3 + AC #4 GREEN: add `e2e-language-only` job to `ci.yml` (GREEN)

- Edit `.github/workflows/ci.yml`:
  - Add a new top-level job `e2e-language-only` after `e2e-devcontainer`.
  - **No** `if:` gating (so it runs on every push and PR, including
    PR forks where `ANTHROPIC_API_KEY` is unavailable — the whole
    point).
  - **No** `env: ANTHROPIC_API_KEY: ...` block.
  - Steps: `actions/checkout@v4`, install devcontainer CLI
    (`npm install -g @devcontainers/cli`), `devcontainer up
    --workspace-folder .`, then `devcontainer exec --workspace-folder .
    bash tests/e2e/run.sh --language-only` (note the absence of
    `--remote-env ANTHROPIC_API_KEY=...`).
- All Step 5 tests pass.

### Step 7 — AC #5 probe: confirm `run_claude` capture shape (RED, observational)

- Add `tests/e2e/assertions/test_run_claude_capture.sh`:
  - `Test_RunClaude_CapturesBothStreams` — verifies the existing
    `run_claude` redirects both stdout **and** stderr into the log
    file (currently `> "$LOG_DIR/$log" 2>&1` — yes, but the assertion
    pins this so a future refactor that splits the streams doesn't
    silently break the matchers).
  - `Test_RunClaude_LogPathStable` — verifies the log file name is
    deterministic per call (the matcher in Step 9 will grep the log).
- These probe tests document the assumption Step 9's matcher logic
  depends on. They pass against the current `run.sh`; if they ever
  fail in the future, the matcher needs re-checking. (Risk noted in §Risk below.)

### Step 8 — AC #5 RED: `ENVIRONMENT_FAILURE:` detection assertion (RED)

- Add `tests/e2e/assertions/test_environment_failure_annotation.sh`:
  - For each enumerated matcher in AC #5, drive the new
    `classify_claude_failure` (or equivalent) function with a canned
    stdin/stdout pair and assert the right tag is emitted:
    - `Test_Classify_CreditExhausted` — input contains
      `"Credit balance is too low"` → output contains
      `ENVIRONMENT_FAILURE: credit_exhausted`.
    - `Test_Classify_Auth_HTTP401` — input contains `HTTP 401` →
      `ENVIRONMENT_FAILURE: auth`.
    - `Test_Classify_Auth_HTTP403` — input contains `HTTP 403` →
      `ENVIRONMENT_FAILURE: auth`.
    - `Test_Classify_Auth_KeyUnset` — `ANTHROPIC_API_KEY` is unset
      at invocation → `ENVIRONMENT_FAILURE: auth`.
    - `Test_Classify_Auth_InvalidXApiKey` — input contains the
      substring `invalid x-api-key` (case-insensitive) →
      `ENVIRONMENT_FAILURE: auth`.
    - `Test_Classify_Auth_AuthenticationFailed` — input contains
      `authentication failed` (case-insensitive) →
      `ENVIRONMENT_FAILURE: auth`.
    - `Test_Classify_Auth_Unauthorized` — input contains
      `unauthorized` (case-insensitive) → `ENVIRONMENT_FAILURE: auth`.
    - `Test_Classify_TransientApi_HTTP5xx` — input contains `HTTP 500`
      (and separately `502`, `503`) → `ENVIRONMENT_FAILURE: transient_api`.
    - `Test_Classify_TransientApi_HTTP429` — input contains `HTTP 429`
      → `ENVIRONMENT_FAILURE: transient_api`.
    - `Test_Classify_TransientApi_Network` — input contains `network`
      → `ENVIRONMENT_FAILURE: transient_api`.
    - `Test_Classify_TransientApi_Timeout` — input contains `timeout`
      → `ENVIRONMENT_FAILURE: transient_api`.
    - `Test_Classify_TransientApi_ConnectionRefused` — input contains
      `connection refused` → `ENVIRONMENT_FAILURE: transient_api`.
    - `Test_Classify_AssertionFailure_NotAnnotated` — input is a
      plain assertion mismatch (e.g. `expected status:planned`); the
      function does **not** emit `ENVIRONMENT_FAILURE:`.
    - `Test_Classify_ExitCodeStillNonZero` — regardless of category,
      the overall script exit code stays non-zero. (Observability,
      not error-swallowing.)
- All tests fail because `classify_claude_failure` does not yet exist.

### Step 9 — AC #5 GREEN: implement classifier and wire into `run_claude` (GREEN)

- Add a `classify_claude_failure()` function to `tests/e2e/run.sh`
  that reads a log file path and emits the matched category tag to
  stderr, or no output if no match.
- Modify `run_claude`'s failure path: after `cat "$LOG_DIR/$log" >&2`
  and before `exit 3`, invoke `classify_claude_failure "$LOG_DIR/$log"`
  and let it print the `ENVIRONMENT_FAILURE: <category>` line on the
  classified branch.
- Use case-insensitive grep (`grep -iqF` for substring matches,
  `grep -iqE` for regex like `HTTP[[:space:]]*4(01|03)`).
- Order of checks: credit_exhausted → auth → transient_api → none.
  (Credit exhaustion is its own category in the spec; do not let
  the auth matchers eat it by accident.)
- All Step 8 tests pass.

### Step 10 — AC #6 RED: README docs assertion (RED)

- Add `tests/docs/test_ci_docs.sh`:
  - `Test_Readme_HasCiSubsection` — README contains a `## CI` or
    `### CI` heading, or extends `## Development` with the required
    content (grep for at least one of: `## CI`, `### CI`,
    `language-only`).
  - `Test_Readme_DocumentsApiCreditJobs` — README explicitly names
    which jobs require API credits (`e2e-devcontainer`) and which
    don't (`e2e-language-only`), via substring match on both job
    names.
  - `Test_Readme_DocumentsLanguageOnlyEntrypoint` — README mentions
    `tests/e2e/run.sh --language-only` as the fast-signal path.
  - `Test_Readme_DocumentsEnvironmentFailureAnnotation` — README
    mentions `ENVIRONMENT_FAILURE:` and explains what it means.
- All tests fail because the README section does not yet exist.

### Step 11 — AC #6 GREEN: add README note (GREEN)

- Add a `## CI` subsection (or extend `## Development`) to
  `README.md` covering:
  1. **Which jobs require API credits.** `e2e-devcontainer` runs
     `claude -p` and needs `ANTHROPIC_API_KEY` from repo secrets;
     `e2e-language-only` does not.
  2. **Language-only entrypoint as the fast-signal path.**
     `bash tests/e2e/run.sh --language-only` runs the Rust + Python
     fixtures without `claude -p`, no API key required. Use this
     locally and in PR signal.
  3. **What `ENVIRONMENT_FAILURE:` means.** When seen in the
     `e2e-devcontainer` job log, it tags the failure as
     environmental (credit exhaustion, auth, transient upstream),
     not a real assertion mismatch. Categories: `credit_exhausted`,
     `auth`, `transient_api`.
- All Step 10 tests pass.

### Step 12 — Refactor (optional)

- If Steps 4 and 9 introduce more than two grep-helper invocations
  with the same shape, factor a small `_log_contains_ci()` helper
  in `run.sh` to keep the matcher list readable.
- All tests still pass.

### Step 13 — Pre-close gate: close-commit invariant (operational, not code)

- (See Implementation note above.) When the language-only CI job
  produces its first `success` run on `main`:
  1. In a **single commit** on a follow-up branch:
     - Append a `## Shipped` section to
       `specs/0008-ci-hardening/changelog.md` recording:
       - The Step 1 probe's root-cause finding for `~/.claude/session-env`
         EACCES.
       - The run URL of the first green `e2e-language-only` run on `main`.
       - The note that this run retroactively satisfies spec 0007's
         T10 (Python fixture CI-green).
     - Flip `spec.md`'s frontmatter from `status: <pre-close>` to
       `status: closed`.
  2. Open a PR for that single commit. Merge to `main`. The parent
     commit of the close commit still shows the pre-close status.
- If the first run after merge fails for an enumerated
  `ENVIRONMENT_FAILURE:` reason, close is held. The spec does not
  close on environmental flake.
- If the first run reveals a real bug in the language-only entrypoint
  or new-job wiring, fix it in-spec before close (no follow-up
  needed).

## Delegation

- All steps → keep with the implementing agent (Claude Code main thread). Reasons:
  - The work is Bash, YAML, and Markdown. No Go, no multi-package
    coordination, no algorithm-heavy logic.
  - The probe steps (1, 7) are observational and need fast
    iteration against the live devcontainer; aux-agent dispatch
    overhead would dominate.
  - No step would benefit measurably from `opencode` (no large
    refactor) or `codex` (no formal reasoning over an algorithm).

## Risk

- **AC #1 root cause unknown until probed.** The spec leaves the
  `~/.claude/session-env` EACCES root cause as an open question.
  Mitigation: Step 1 is an explicit probe-and-document step before
  Step 2's fix. The probe output goes verbatim into the changelog
  per spec §Open questions, item 2.
- **AC #5 detection depends on `run_claude` capturing both streams.**
  The matchers grep the log file written by `run_claude`. If
  `run_claude` ever splits stdout from stderr, the matchers won't
  fire on stderr-only errors (e.g. `"Credit balance is too low"`
  may land on stderr depending on the `claude` CLI version).
  Mitigation: Step 7 pins this assumption with `Test_RunClaude_CapturesBothStreams`.
- **`--language-only` mode silently regresses the lifecycle path.**
  Reusing a `run_language_fixtures()` helper between the two modes
  is the simplest way to avoid drift, but it means the
  language-only path inherits any future bug introduced in the
  shared helper. Mitigation: the existing `e2e-devcontainer` job
  exercises the lifecycle plus the same fixtures, so any drift is
  caught by both jobs (in different failure modes).
- **YAML linting in the assertion (Step 5).** `python3 -c "import yaml"`
  is not guaranteed in every dev environment. Mitigation: the
  YAML parse check is graceful-skip rather than fail-if-missing.
  GitHub Actions itself catches malformed YAML at workflow-load
  time, so the structural check is belt-and-suspenders.
- **Close-commit invariant operational error.** A maintainer could
  forget to put the changelog edit and `status:closed` flip in the
  same commit. Mitigation: T13 in `tasks.md` names this explicitly;
  the Implementation note above gives the rule verbatim.
- **AC #1 fix and rebuild idempotency.** `chown -R` on a named
  volume that is empty on first create may race with the volume
  mount itself. Mitigation: the fix block guards with `[ -d ... ]`
  and is run from `postCreateCommand` (after the mount is live);
  `mkdir -p` follows so an empty volume still produces the
  required subdirectory.
