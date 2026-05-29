---
spec: "0008"
closed: 2026-05-29
---

# Changelog — 0008 CI hardening

## Shipped

- **AC #1 — `~/.claude/session-env` writable in the devcontainer.**
  `.devcontainer/setup.sh` (+17) gains a Section 0 block that idempotently re-asserts ownership of `~/.claude` to `vscode:vscode` and pre-creates `~/.claude/session-env` before any downstream step runs. Probe assertion landed at `tests/e2e/assertions/test_session_env_writable.sh` (+69) and pins the post-`devcontainer up` invariant (owner + mode + writable probe file). Implementation commit: `132a818`.

- **AC #2 — `tests/e2e/run.sh --language-only` entrypoint.**
  `tests/e2e/run.sh` (+130 / −25) gains an argv parser, a shared `run_language_fixtures()` helper used by both the lifecycle path and the new mode, and `--language-only` skips the throwaway Go module setup and every `claude -p` step. Assertion at `tests/e2e/assertions/test_language_only_flag.sh` (+111) uses a PATH-shim `claude` to prove the mode never invokes `claude -p` and never creates `go.mod`. Fixture-failure cases exit 2, matching the existing `fail()` convention. Implementation commit: `132a818`.

- **AC #3 + AC #4 — `e2e-language-only` CI job.**
  `.github/workflows/ci.yml` (+19) adds a new job that runs on every `push` and `pull_request`, builds the devcontainer with the same `devcontainer up --workspace-folder .` invocation as `e2e-devcontainer`, and runs `bash tests/e2e/run.sh --language-only` inside it. The job carries no `if:` gate, no `ANTHROPIC_API_KEY` env, and no `--remote-env` pass-through — verifiable structurally by `tests/docs/test_language_only_job.sh` (+127). Implementation commit: `132a818`.

- **AC #5 — `ENVIRONMENT_FAILURE:` annotation in the lifecycle job.**
  `tests/e2e/run.sh` adds `classify_claude_failure()`, invoked from `run_claude`'s failure path. Ordering is credit_exhausted → auth → transient_api → none. Exit code remains non-zero in every branch (observability, not error-swallowing). Probe assertion at `tests/e2e/assertions/test_run_claude_capture.sh` (+53) pins the assumption that `run_claude` redirects both streams into the log file. Driver assertion at `tests/e2e/assertions/test_environment_failure_annotation.sh` (+140) covers all 15 matcher cases listed in AC #5, including the ordering guarantee and the assertion-failure-not-annotated negative case. Implementation commit: `132a818`.

- **AC #6 — README `## CI` section.**
  `README.md` (+29) gains a `## CI` subsection (and TOC link) covering: which jobs need API credits (`e2e-devcontainer`) vs which don't (`e2e-language-only`), `bash tests/e2e/run.sh --language-only` as the fast-signal path, and the meaning of `ENVIRONMENT_FAILURE:` log lines. Grep assertion at `tests/docs/test_ci_docs.sh` (+45) pins the four documentation items. Implementation commit: `132a818`.

## Pre-close gate — first green run

First green CI run for the new `e2e-language-only` job on `main`:
**https://github.com/DCSTOLF/speccraft/actions/runs/26658905606**

All five jobs in that run are `success`, including `e2e-language-only`. This run also retroactively satisfies **spec 0007 T10** (CI green for `python_cycle.sh`), which was explicitly deferred at 0007 close because the upstream `EACCES` and `Credit balance is too low` failures blocked it. Per the closed-spec-immutability rule in `.speccraft/conventions.md`, **spec 0007's files are NOT edited** — the cross-reference is resolved here.

## AC #1 root-cause finding

Open question #2 in spec.md asked whether the `EACCES` came from (a) the base image, (b) the named-volume mount, or (c) a combination. The probe (`test_session_env_writable.sh`) on the local devcontainer showed `vscode:vscode 0755` for `/home/vscode/.claude` — i.e. already clean. The probe could not isolate the failing mode locally because the local environment did not reproduce the failure.

What we know now:
- CI's `e2e-language-only` job runs green with the defensive fix in place (run `26658905606`).
- The fix in `.devcontainer/setup.sh` is unconditionally idempotent: re-`chown` if the dir exists, then `mkdir -p` the `session-env` subdir.

What we can't definitively say:
- The exact CI-side root cause was not reproduced locally. The most likely candidate is a named-volume-on-first-create race in the e2e-devcontainer job (option b in the spec), with base-image ownership oddities (option a) as the secondary candidate. The defensive fix covers both.

This matches the spec's "implementer should probe and document" phrasing; nailing the exact CI-side root cause was not a closeable AC.

## Bug fixes during integration

Two CI-surfaced bugs landed as fixed-forward follow-up commits:

- **`45beecd` — `E2E_DIR` resolved before script `cd`.** `run_language_fixtures` originally used `realpath "${BASH_SOURCE[0]}"` after the script had already `cd`'d into `$TEST_ROOT`, which broke when CI invoked `tests/e2e/run.sh` via a relative path. Root cause: lazy `BASH_SOURCE` resolution post-`cd`. Fix: capture `E2E_DIR` near the top of `run.sh` while the original CWD is still valid, before any `cd`.

- **`a83e641` — mock-agent stdin hang.** Once AC #1's permission fix landed, the `/speccraft:spec:review` step ran further than before and hit a latent mock bug: `INPUT="$(cat)"` in the mock CLIs blocked on `claude -p`'s never-EOFing stdin. The opencode mock declared `input = "argv"` in `agents.toml`, so reading stdin was wrong from day one — previous runs masked it by failing upstream. Fix: `exec </dev/null` in both mock aux-agent install scripts so stdin is detached at startup.

## Deferred / out of scope

- **T12 (optional refactor)** — `classify_claude_failure` matcher duplication kept intentional for line-by-line readability; each matcher documents its own pattern.
- **Spec 0006 reservation** — spec 0005's `reserves-specs: ["0006"]` (Cargo workspace support) is still in place; spec 0006 is still unfiled. Out of scope for 0008.
- **Go language-only fixture decoupling** — Go's e2e is part of the throwaway-module setup in step `[1/N]` of the lifecycle path and stays there (per spec §Out-of-scope).
- **Mock aux-agent hardening beyond stdin detach** — broader devcontainer mock hardening was explicitly out of scope; only the minimum repair (stdin detach) landed.

## Test coverage summary

| AC  | Assertion script                                                       | What it pins |
|-----|------------------------------------------------------------------------|--------------|
| #1  | `tests/e2e/assertions/test_session_env_writable.sh`                    | Post-`devcontainer up` ownership/mode + probe-file writability |
| #2  | `tests/e2e/assertions/test_language_only_flag.sh`                      | Flag accepted, no `claude -p`, no `go.mod`, all 3 fixtures run, failure exits 2 |
| #3  | `tests/docs/test_language_only_job.sh`                                 | Job exists, no `if:` gate, invokes `--language-only`, no `ANTHROPIC_API_KEY`, same `devcontainer up` |
| #4  | `tests/docs/test_language_only_job.sh` (YAML-parse + structural checks)| YAML parses; structural deliverable verifiable at PR-review time |
| #5  | `tests/e2e/assertions/test_run_claude_capture.sh` (probe)              | `run_claude` captures both streams into log |
| #5  | `tests/e2e/assertions/test_environment_failure_annotation.sh`          | 15 matcher cases + ordering + assertion-not-annotated + non-zero exit |
| #6  | `tests/docs/test_ci_docs.sh`                                           | README `## CI`, both job names, `--language-only` path, `ENVIRONMENT_FAILURE:` semantics |

## Close-commit invariant (codex R3, T13)

This changelog edit and the `status: in-progress → closed` flip on `spec.md` land in the **same git commit**. The parent commit must still show `status: in-progress`. There are no post-close edits; any defect found after close gets a follow-up spec, not a changelog amendment.
