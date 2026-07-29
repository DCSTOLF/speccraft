# Domain: ci-and-e2e

CI workflows and the e2e fixture harness: `run.sh` entrypoints/flags, per-language fixtures, devcontainer provisioning, environmental-failure annotation.

- An end-to-end test under `tests/e2e/` drives a single-crate Rust fixture through a full red→green→refactor cycle covering both inline and integration tests using the real `speccraft-guard` binary and a real `cargo` runner invocation (spec 0005)
- The devcontainer image and the CI e2e job provide a working Rust toolchain, and the e2e harness fails fast with `"cargo not found on PATH"` when `cargo` is absent (spec 0005)
- `tests/e2e/python_cycle.sh` is a hermetic Bash fixture (mktemp workdir, trap cleanup) that drives `speccraft-guard` via the Claude Code hook JSON protocol to assert the sibling-tier and `test_roots`-tier reject-then-allow flows, the no-test-anywhere rejection, and that editing a test file is always allowed (spec 0007)
- The Python e2e fixture is wired into `tests/e2e/run.sh` as a numbered step, exits 0 on success and 2 on any assertion failure, and requires only `python3` (no `pytest`) from the base image (spec 0007)
- `tests/e2e/run.sh --language-only` runs only the Rust and Python fixture scripts with no `claude -p` invocation and without requiring `ANTHROPIC_API_KEY`, exiting 0 on success and 2 on failure and skipping the lifecycle Go-module setup (spec 0008)
- `.github/workflows/ci.yml` includes an `e2e-language-only` job that runs on every push and pull_request, builds the devcontainer, executes `run.sh --language-only`, and never receives `ANTHROPIC_API_KEY` (spec 0008)
- The devcontainer provisions `~/.claude/session-env` as writable by the e2e job user, idempotently and surviving container rebuilds (spec 0008)
- The full-lifecycle e2e job annotates environmental `claude -p` failures with an `ENVIRONMENT_FAILURE:` prefix and a category tag (`credit_exhausted`, `auth`, or `transient_api`) while keeping a non-zero exit; non-environmental failures stay unannotated (spec 0008)
