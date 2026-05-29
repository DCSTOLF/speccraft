#!/usr/bin/env bash
# Runs once after container creation. Idempotent.
set -euo pipefail

echo "==> speccraft devcontainer setup"

# 0. (Spec 0008 AC #1) Ensure ~/.claude is writable by the container user.
#    The named volume mount in devcontainer.json can land as root-owned
#    on first create, which breaks the aux-delegator harness (it tries to
#    mkdir ~/.claude/session-env and EACCESses). Reassert ownership
#    idempotently so this survives Rebuild Container.
#    Verified via tests/e2e/assertions/test_session_env_writable.sh.
CLAUDE_DIR="${HOME}/.claude"
if [ ! -d "$CLAUDE_DIR" ] || [ "$(stat -c '%U' "$CLAUDE_DIR")" != "$(id -un)" ]; then
  echo "==> Fixing ~/.claude ownership for $(id -un) (AC #1, spec 0008)..."
  sudo mkdir -p "$CLAUDE_DIR"
  sudo chown -R "$(id -un):$(id -gn)" "$CLAUDE_DIR"
  sudo chmod 0755 "$CLAUDE_DIR"
fi
# Pre-create session-env so the aux-delegator never trips on a missing
# parent. Also-idempotent — both mkdir and chown skip if already owned.
mkdir -p "${CLAUDE_DIR}/session-env"

# 1. Build helper binaries from source (no GitHub Releases call — we're on
#    the source-fallback path during development).
if [ -d tools ]; then
  echo "==> Building speccraft helper binaries from source..."
  bash scripts/install-binaries.sh
fi

# 2. Install mock aux-agent CLIs at /usr/local/bin so /spec:delegate and
#    /spec:review can be tested hermetically (no API costs, no auth).
#    Real CLIs override these if installed afterwards.
sudo bash .devcontainer/install-mock-agents.sh

# 3. Pre-warm the Go module cache (faster first build).
if [ -f tools/go.mod ]; then
  ( cd tools && go mod download )
fi

# 3b. Rust toolchain (spec 0005 AC #9). Idempotent — skipped if cargo is
#     already on PATH (rustup re-runs are harmless but slow).
if ! command -v cargo >/dev/null 2>&1; then
  echo "==> Installing Rust toolchain via rustup..."
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable --profile minimal
  # shellcheck disable=SC1091
  source "$HOME/.cargo/env" 2>/dev/null || true
else
  echo "==> Rust toolchain present: $(cargo --version)"
fi

# 4. Smoke check.
echo "==> Smoke check"
command -v claude || echo "   claude: NOT FOUND (install via Feature)"
command -v go     && go version
command -v jq     && jq --version
command -v git    && git --version
command -v codex    && echo "   codex: $(command -v codex)" || echo "   codex: NOT FOUND"
command -v opencode && echo "   opencode: $(command -v opencode)" || echo "   opencode: NOT FOUND"

if [ -x bin/speccraft-state ]; then
  echo "   speccraft-state: $(bin/speccraft-state --version 2>&1 | head -1)"
else
  echo "   speccraft-state: NOT BUILT (expected on first checkout before Phase 2)"
fi

echo "==> Done."
echo
echo "Next:"
echo "  1. Authenticate Claude Code: run 'claude' in a terminal and follow the prompt."
echo "     The auth token is stored in the named volume and persists across rebuilds."
echo "  2. To run e2e tests:    bash tests/e2e/run.sh"
echo "  3. To develop the plugin: open any session and start editing."
