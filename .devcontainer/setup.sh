#!/usr/bin/env bash
# Runs once after container creation. Idempotent.
set -euo pipefail

echo "==> speccraft devcontainer setup"

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

# 4. Smoke check.
echo "==> Smoke check"
command -v claude || echo "   claude: NOT FOUND (install via Feature)"
command -v go     && go version
command -v jq     && jq --version
command -v git    && git --version
command -v codex  && codex --version || echo "   codex: mock"
command -v opencode && opencode --version || echo "   opencode: mock"

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
