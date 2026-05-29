---
spec: "0008"
---

# Tasks

- [x] T1 — AC #1 probe: add `tests/e2e/assertions/test_session_env_writable.sh` documenting ownership/mode of `/home/vscode/.claude` and the EACCES root cause (probe output captured into changelog)
- [x] T2 — AC #1 fix: make `~/.claude/session-env` writable idempotently via `.devcontainer/setup.sh` (and/or `Dockerfile`); survives `Rebuild Container`; Step 1 assertion passes
- [x] T3 — AC #2 RED: add `tests/e2e/assertions/test_language_only_flag.sh` asserting flag-accepted, no-claude, no-go-module, all-three-fixtures-run, fixture-failure-exits-2
- [x] T4 — AC #2 GREEN: implement `--language-only` flag in `tests/e2e/run.sh` (argv parse, skip lifecycle, reuse fixture invocations via shared helper)
- [x] T5 — AC #3 + AC #4 RED: add `tests/docs/test_language_only_job.sh` asserting the new job exists, runs on push+PR, invokes `--language-only`, does not pass `ANTHROPIC_API_KEY`, uses same devcontainer invocation, YAML parses
- [x] T6 — AC #3 + AC #4 GREEN: add `e2e-language-only` job to `.github/workflows/ci.yml` (no `if:` gate, no `ANTHROPIC_API_KEY`, runs `bash tests/e2e/run.sh --language-only`)
- [x] T7 — AC #5 probe: add `tests/e2e/assertions/test_run_claude_capture.sh` pinning `run_claude`'s stdout+stderr capture shape
- [x] T8 — AC #5 RED: add `tests/e2e/assertions/test_environment_failure_annotation.sh` driving `classify_claude_failure` against all enumerated matchers (credit_exhausted, auth, transient_api) plus the assertion-failure-not-annotated case
- [x] T9 — AC #5 GREEN: implement `classify_claude_failure()` in `run.sh` and wire into `run_claude`'s failure path; ordering: credit → auth → transient; exit code stays non-zero
- [x] T10 — AC #6 RED: add `tests/docs/test_ci_docs.sh` asserting README documents API-credit job split, language-only entrypoint, and `ENVIRONMENT_FAILURE:` semantics
- [x] T11 — AC #6 GREEN: add `## CI` subsection (or extend `## Development`) to `README.md` with the three documentation items
- [ ] T12 — Optional refactor: factor a `_log_contains_ci()` grep helper in `run.sh` if matcher duplication crosses two repetitions [deferred — duplication is intentional for readability; each matcher line documents its own pattern]
- [ ] T13 — Close-commit invariant: in a single commit on a follow-up branch, append `## Shipped` section to `specs/0008-ci-hardening/changelog.md` (recording probe root cause + first-green run URL + retroactive satisfaction of spec 0007 T10) and flip `spec.md` `status:` → `closed`; parent commit must still show pre-close status; do not split across commits
