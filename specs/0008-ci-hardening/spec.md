---
id: "0008"
title: "CI hardening"
status: draft
created: 2026-05-29
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

2. **Decouple language-dispatch e2e from `claude -p` spend.** Today, the language-dispatch steps (`[8/N]` Rust, `[9/N]` Python, and the implicit Go module setup in `[1/N]`) run *after* five `claude -p` invocations. Any of those `claude -p` calls failing (credits, auth, transient API errors) blocks the language steps. The fix: introduce a mode that runs only the language-dispatch fixtures, skipping the `claude -p`-driven lifecycle steps. Either a new flag (`tests/e2e/run.sh --language-only`), a new entrypoint script (`tests/e2e/run-language-only.sh`), or splitting the existing run.sh into two scripts the CI workflow can invoke independently. Each script must be runnable on its own and exit independently.

3. **Add a language-only e2e job to `.github/workflows/ci.yml`.** This new job runs the language-dispatch fixtures inside the devcontainer without invoking the Claude API. It does NOT require `ANTHROPIC_API_KEY`. It runs on every push and PR (not just `push to main`), giving fast signal that the Rust and Python dispatch code in `speccraft-guard` is still correct after every change.

4. **Retroactively verify spec 0007's T10.** Once items 1–3 land, the Python step `[9/9]` (or its equivalent in the new split entrypoint) must run green in CI on the next push. Update spec 0007's `tasks.md` to mark T10 `[x]` with a reference to the run URL.

5. **Make the existing full e2e job (the `claude -p`-driven lifecycle) more robust.** When `claude -p` fails with `"Credit balance is too low"` (or any other clearly-environmental error), the job should exit with a non-zero status but emit a clear, parseable message so future debugging is fast. Optionally add a workflow-level annotation that the failure is environmental, not a code defect.

## Acceptance criteria

1. **`~/.claude/session-env` is writable in the devcontainer.** A test asserts: after `devcontainer up --workspace-folder .`, running `devcontainer exec ... mkdir -p ~/.claude/session-env && touch ~/.claude/session-env/probe` succeeds with exit 0. The probe file is owned by the same user that runs `bash tests/e2e/run.sh`.

2. **Language-only entrypoint exists and runs hermetically.** Either `tests/e2e/run.sh --language-only` or `tests/e2e/run-language-only.sh` (the implementer picks one and the spec accepts either). Whichever lands:
   - Runs the existing `rust_inline_cycle.sh`, `rust_integration_cycle.sh`, and `python_cycle.sh` fixtures in order.
   - Does NOT invoke `claude -p` at any point.
   - Does NOT require `ANTHROPIC_API_KEY` to be set.
   - Exits 0 on success, 2 on any fixture failure, matching the existing `fail()` convention.

3. **CI workflow has a new language-only job.** `.github/workflows/ci.yml` includes a job (e.g. `e2e-language-only`) that:
   - Runs on every `push` and `pull_request` event (not gated to `push to main`).
   - Builds the devcontainer.
   - Executes the language-only entrypoint from AC #2 inside the devcontainer.
   - Does NOT pass `ANTHROPIC_API_KEY` to the container — verifying the entrypoint really doesn't need it.
   - Reports `success` when all three fixtures pass green.

4. **First green run satisfies spec 0007's T10.** After this spec ships, the next push to a branch triggering the new language-only job produces a `success` status with the Python fixture (`python_cycle.sh`) visibly in the logs. The run URL is recorded in spec 0007's tasks.md as the retroactive proof of T10. (The implementer marks 0007's T10 `[x]` as part of closing this spec.)

5. **Full lifecycle job (existing `e2e-devcontainer`) emits a recognizable annotation on environmental failure.** When `claude -p` fails with credit/auth/transient errors, the job exit message includes a literal substring like `ENVIRONMENT_FAILURE:` or equivalent that downstream tooling (or a human reading logs) can distinguish from a real assertion failure. The exit code stays non-zero — this is observability, not error-swallowing.

6. **Documentation update.** A short note in `README.md` (under the existing `## Development` or in a new `## CI` subsection) explains: (a) which CI jobs require API credits and which don't, (b) the language-only entrypoint as the fast-signal path during development, (c) what `ENVIRONMENT_FAILURE:` means when seen in the full-lifecycle job.

## Out of scope

- Replacing `claude -p` in the full lifecycle e2e. The lifecycle tests genuinely exercise the spec workflow end-to-end; we're not pretending we can verify it without invoking Claude. The fix is to separate the cheap signals from the expensive signals, not to delete the expensive ones.
- Auto-funding the API key when credits run low. Out of scope; that's an ops decision, not a CI design.
- Rewriting `tests/e2e/run.sh` from scratch. The split should be minimal — extract the language-only steps, leave the lifecycle untouched as much as possible.
- Adding a Go language-only fixture. Go's e2e is intertwined with the lifecycle (the throwaway Go module is created in step `[1/N]` to give the lifecycle tests something to operate on). Decoupling it is non-trivial and deferred to a follow-up if anyone needs it.
- Hardening mock aux-agent installation. The `EACCES` fix (AC #1) is the smallest possible repair; deeper devcontainer hardening is a separate concern.

## Open questions

- Should the language-only job also run on `schedule:` (e.g. nightly) to catch external regressions, or is `push`+`pull_request` sufficient? Recommendation: `push` + `pull_request` is enough for now; add `schedule:` only if external regressions become an observed problem.
- The `EACCES` root cause may be either (a) the devcontainer base image creating `/home/vscode/.claude` with wrong ownership, (b) the named volume mount in `devcontainer.json` causing root-owned files inside, or (c) a combination. The implementer should probe at start time and document the actual root cause in the changelog.
