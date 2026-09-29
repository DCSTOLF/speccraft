#!/usr/bin/env bash
# Install mock aux-agent CLIs for hermetic e2e tests.
#
# The behavior lives in mock-agents/aux-review-mock.sh, installed under both
# agent names; this script only places it. It used to inline each mock as a
# heredoc, which meant the only way to exercise them was a ten-minute
# devcontainer job — and that is how the spec-0052 attestation regression
# reached `main`. A standalone file is covered by
# tests/hooks/e2e-mock-reviewer.bats in 45 seconds.
#
# No network, no API keys. Override a response with
# SPECCRAFT_MOCK_<AGENT>_RESPONSE_FILE; that file is emitted verbatim, which is
# how a test supplies a deliberately NON-attesting reviewer to exercise the
# inert-round path.
set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/mock-agents"
MOCK="$SRC_DIR/aux-review-mock.sh"

[ -f "$MOCK" ] || { echo "install-mock-agents: missing $MOCK" >&2; exit 1; }

for name in codex opencode; do
  install -m 0755 "$MOCK" "/usr/local/bin/$name"
done

echo "==> Installed mock aux agents: codex, opencode"
echo "   They read the dispatched payload, open each reference-tier path at the"
echo "   dispatched cwd, and return a real sha256 per path — so a review round"
echo "   against them exercises the spec-0052 reference-read attestation rather"
echo "   than being refused by it."
echo "   To use real CLIs, install them in the Dockerfile or via npm and they"
echo "   will take precedence over these mocks (PATH order)."
