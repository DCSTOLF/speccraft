---
id: "0008"
title: "CI hardening"
status: closed
created: 2026-05-29
closed: 2026-05-29
authors: [claude]
packages: [".github/workflows", "tests/e2e", ".devcontainer"]
related-specs: ["0005", "0007"]
---

# Spec 0008 — CI hardening

## Why

The e2e workflow has accumulated multiple infrastructure failures unrelated to the specs whose deliverables it's meant to verify:

1. **`/speccraft:spec:review` step fails with `EACCES`.** Older CI runs (e.g. run #28) failed at `[N] /speccraft:spec:review (mock agents)` with `EACCES: permission denied, mkdir '/home/vscode/.claude/session-env'`. `/home/vscode/.claude/` is not writable by the container user inside the e2e job, so the harness cannot create its per-session env directory. No `aux-delegator` subprocess (`codex`, `opencode`) can launch. Claude correctly declines to fabricate review verdicts and the step fails.

2. **`/speccraft:spec:plan` step fails with `"Credit balance is too low"`.** Recent runs (commit `079ed25`, `383c928`) reach `[5/N] /speccraft:spec:plan` and `claude -p` returns the literal string `Credit balance is too low`. The job exits 3 (`claude -p failed`) without ever reaching the per-language e2e steps `[8/N]` (Rust) and `[9/N]` (Python).

3. **Consequence: e2e never verifies language-dispatch steps.** Spec 0005's Rust fixtures (`[8/N]`) and spec 0007's Python fixture (`[9/N]`) are wired into `run.sh` but have never run in CI. Spec 0007 explicitly deferred its T10 (CI green) to this spec because the upstream failure made verification impossible.

These problems are pre-existing and orthogonal to the language-support specs. They block the e2e pipeline from providing any signal about the language dispatch code that 0005 and 0007 added.

## What

Scope of this change:

1. **Fix `~/.claude/session-env` permissions in the e2e job.** Either pre-create the directory with correct ownership in the devcontainer setup, adjust the e2e workflow to chown/chmod the path after `devcontainer up`, or change the harness to use a directory the container user can already write. Whichever mechanism lands, the fix must be idempotent and survive `Rebuild Container`.

2. **Decouple language-dispatch e2e from `claude -p` spend.** Today, the language-dispatch steps (`[8/N]` Rust, `[9/N]` Python) run *after* five `claude -p` invocations as part of `tests/e2e/run.sh`. Any of those `claude -p` calls failing (credits, auth, transient API errors) blocks the language steps. The fix: introduce a `--language-only` flag on `tests/e2e/run.sh` that runs only the existing Rust and Python fixture scripts and exits, skipping the entire `claude -p`-driven lifecycle. A single contract — one entrypoint, one flag — keeps AC #3's CI invocation and AC #6's documentation unambiguous.

   **Note on Go.** The Go end-to-end fixture is *not* a standalone `<lang>_cycle.sh`; Go's coverage in CI today is the throwaway Go module created in step `[1/N]` of the lifecycle path and exercised by the subsequent `claude -p` lifecycle steps. That coupling is intentional and stays. The `--language-only` mode therefore covers Rust + Python only; decoupling Go is deferred (see Out of scope). When the lifecycle job runs (the existing `e2e-devcontainer` job), the Go module setup and all language steps run together as before.

3. **Add a language-only e2e job to `.github/workflows/ci.yml`.** This new job runs the language-dispatch fixtures inside the devcontainer without invoking the Claude API. It does NOT require `ANTHROPIC_API_KEY`. It runs on every push and PR (not just `push to main`), giving fast signal that the Rust and Python dispatch code in `speccraft-guard` is still correct after every change.

4. **Retroactively verify spec 0007's T10 — proof recorded in 0008's changelog.** Once items 1–3 land, the Python fixture (`python_cycle.sh`) runs green in the new language-only CI job. **The proof of T10's retroactive satisfaction is recorded in this spec's `changelog.md` with the run URL of the first green language-only run.** Spec 0007 stays untouched — its `tasks.md` is *not* edited as part of this spec, per the closed-spec-immutability rule in `.speccraft/conventions.md`. Future readers consulting 0007 will see T10 listed as "deferred to spec 0008 (CI hardening)" with the cross-reference resolved by 0008's changelog.

5. **Make the existing full e2e job (the `claude -p`-driven lifecycle) more robust.** When `claude -p` fails with `"Credit balance is too low"` (or any other clearly-environmental error), the job should exit with a non-zero status but emit a clear, parseable message so future debugging is fast. Optionally add a workflow-level annotation that the failure is environmental, not a code defect.

## Acceptance criteria

1. **`~/.claude/session-env` is writable in the devcontainer.** A test asserts: after `devcontainer up --workspace-folder .`, running `devcontainer exec ... mkdir -p ~/.claude/session-env && touch ~/.claude/session-env/probe` succeeds with exit 0. The probe file is owned by the same user that runs `bash tests/e2e/run.sh`.

2. **Language-only entrypoint exists and runs hermetically.** `tests/e2e/run.sh --language-only` (single contract; no alternative entrypoint script — codex review on the previous draft flagged the looseness as a downstream-coupling risk for AC #3 + AC #6). The mode:
   - Runs the existing `rust_inline_cycle.sh`, `rust_integration_cycle.sh`, and `python_cycle.sh` fixtures in order.
   - Does NOT invoke `claude -p` at any point.
   - Does NOT require `ANTHROPIC_API_KEY` to be set.
   - Exits 0 on success, 2 on any fixture failure, matching the existing `fail()` convention.
   - Does NOT set up the throwaway Go module from step `[1/N]` (Go's e2e is part of the lifecycle path; see §Why and §Out-of-scope).

3. **CI workflow has a new language-only job.** `.github/workflows/ci.yml` includes a job named `e2e-language-only` that:
   - Runs on every `push` and `pull_request` event (not gated to `push to main`).
   - Builds the devcontainer using the same `devcontainer up` invocation as the existing `e2e-devcontainer` job, so cache (if any) and image build steps stay consistent across jobs.
   - Executes `bash tests/e2e/run.sh --language-only` inside the devcontainer.
   - Does NOT pass `ANTHROPIC_API_KEY` to the container — verifying the entrypoint really doesn't need it.
   - Reports `success` when all three fixtures pass green.

4. **Language-only job is structurally complete (implementation deliverable).** The new `e2e-language-only` job from AC #3 exists in `.github/workflows/ci.yml`, parses as valid YAML, references `bash tests/e2e/run.sh --language-only` as its execution step, and does not set `ANTHROPIC_API_KEY` in `env:` or pass it via `--remote-env`. Verifiable by reading the workflow file at PR-review time, before any CI run.

5. **Full lifecycle job (`e2e-devcontainer`) emits `ENVIRONMENT_FAILURE:` on enumerated environmental failures.** When `claude -p` fails for one of the following enumerated reasons, the job exit message includes the literal substring `ENVIRONMENT_FAILURE:` followed by a short category tag, so downstream tooling (or a human reading logs) can distinguish environment problems from real assertion failures:

   - **`ENVIRONMENT_FAILURE: credit_exhausted`** — stdout/stderr contains the literal substring `"Credit balance is too low"` (the Anthropic API error string when an account is out of quota).
   - **`ENVIRONMENT_FAILURE: auth`** — `claude -p` reports an authentication problem. At least the following matchers are required (any-of):
     - HTTP `401` in the response or error output;
     - HTTP `403` in the response or error output;
     - `ANTHROPIC_API_KEY` env var is unset or empty at the moment of invocation;
     - stdout/stderr contains `"invalid x-api-key"`, `"authentication failed"`, or `"unauthorized"` (case-insensitive substring match).
   - **`ENVIRONMENT_FAILURE: transient_api`** — `claude -p` reports a transient upstream failure. At least the following matchers are required (any-of):
     - HTTP `5xx` in the response or error output;
     - HTTP `429` (rate limit) in the response or error output;
     - stdout/stderr contains `"network"`, `"timeout"`, or `"connection refused"` (case-insensitive substring match).

   Implementations may extend these matcher sets with additional patterns, but **must** include every matcher listed above. Any `claude -p` failure that matches none of these categories (assertion mismatch in the lifecycle test itself, missing file, etc.) is **not** annotated and stays an unadorned assertion failure. The job exit code stays non-zero in all cases — this is observability, not error-swallowing.

6. **Documentation update.** A short note in `README.md` (under the existing `## Development` or in a new `## CI` subsection) explains: (a) which CI jobs require API credits and which don't, (b) the language-only entrypoint as the fast-signal path during development, (c) what `ENVIRONMENT_FAILURE:` means when seen in the full-lifecycle job.

## Post-merge verification (pre-close gate)

This section is operational, not a PR-review gate. It governs **when this spec can be closed**, not what reviewers check at merge.

- **Pre-close gate.** Spec 0008 cannot be closed until the new `e2e-language-only` CI job has produced at least one `success` run on `main`. The run URL is recorded in `specs/0008-ci-hardening/changelog.md` as part of the close commit — by definition, before the `status: closed` flip. This avoids the closed-spec-immutability variant that a post-close changelog edit would create.
- **What this verifies.** The first green run satisfies spec 0007's T10 (CI green for the Python fixture). The changelog entry says so explicitly. Spec 0007's files stay untouched per the closed-spec-immutability rule.
- **If the first run after merge fails for an enumerated `ENVIRONMENT_FAILURE:` reason** (AC #5), close is held until a subsequent run succeeds. The spec does not close on environmental flake.
- **If the first run reveals a real bug in the language-only entrypoint or the new job's wiring,** that is an in-spec implementation defect and gets fixed before close — no follow-up spec needed.

## Out of scope

- Replacing `claude -p` in the full lifecycle e2e. The lifecycle tests genuinely exercise the spec workflow end-to-end; we're not pretending we can verify it without invoking Claude. The fix is to separate the cheap signals from the expensive signals, not to delete the expensive ones.
- Auto-funding the API key when credits run low. Out of scope; that's an ops decision, not a CI design.
- Rewriting `tests/e2e/run.sh` from scratch. The split should be minimal — extract the language-only steps, leave the lifecycle untouched as much as possible.
- Adding a Go language-only fixture. Go's e2e is intertwined with the lifecycle (the throwaway Go module is created in step `[1/N]` to give the lifecycle tests something to operate on). Decoupling it is non-trivial and deferred to a follow-up if anyone needs it.
- Hardening mock aux-agent installation. The `EACCES` fix (AC #1) is the smallest possible repair; deeper devcontainer hardening is a separate concern.

## Open questions

- Should the language-only job also run on `schedule:` (e.g. nightly) to catch external regressions, or is `push`+`pull_request` sufficient? Recommendation: `push` + `pull_request` is enough for now; add `schedule:` only if external regressions become an observed problem.
- The `EACCES` root cause may be either (a) the devcontainer base image creating `/home/vscode/.claude` with wrong ownership, (b) the named volume mount in `devcontainer.json` causing root-owned files inside, or (c) a combination. The implementer should probe at start time and document the actual root cause in the changelog.
