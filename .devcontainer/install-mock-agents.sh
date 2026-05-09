#!/usr/bin/env bash
# Install mock aux-agent CLIs for hermetic e2e tests.
# Each mock reads its prompt from stdin (or argv) and writes a canned response
# determined by env vars or simple heuristics. No network, no API keys.
set -euo pipefail

install_mock() {
  local name="$1"
  local body="$2"
  cat > "/usr/local/bin/$name" <<EOF
#!/usr/bin/env bash
# Mock $name for speccraft e2e tests.
# Override behavior by setting SPECCRAFT_MOCK_${name^^}_RESPONSE_FILE.
set -euo pipefail
$body
EOF
  chmod +x "/usr/local/bin/$name"
}

# codex: review-shaped output.
install_mock "codex" '
INPUT="$(cat)"
if [ -n "${SPECCRAFT_MOCK_CODEX_RESPONSE_FILE:-}" ] && [ -f "${SPECCRAFT_MOCK_CODEX_RESPONSE_FILE}" ]; then
  cat "${SPECCRAFT_MOCK_CODEX_RESPONSE_FILE}"
  exit 0
fi
cat <<RESP
verdict: approve-with-comments
concerns:
  - "Acceptance criterion phrasing could be more observable."
suggestions:
  - "Add explicit error-path test."
guardrail_violations: []
convention_violations: []

(mock codex response)
RESP
'

# opencode: planner-shaped output.
install_mock "opencode" '
INPUT="$(cat 2>/dev/null || true)"
if [ -n "${SPECCRAFT_MOCK_OPENCODE_RESPONSE_FILE:-}" ] && [ -f "${SPECCRAFT_MOCK_OPENCODE_RESPONSE_FILE}" ]; then
  cat "${SPECCRAFT_MOCK_OPENCODE_RESPONSE_FILE}"
  exit 0
fi
cat <<RESP
verdict: approve
concerns: []
suggestions:
  - "Consider table-driven tests."
guardrail_violations: []
convention_violations: []

(mock opencode response)
RESP
'

echo "==> Installed mock aux agents: codex, opencode"
echo "   To use real CLIs, install them in the Dockerfile or via npm and they"
echo "   will take precedence over these mocks (PATH order)."
