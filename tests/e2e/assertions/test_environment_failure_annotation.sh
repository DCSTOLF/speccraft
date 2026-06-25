#!/usr/bin/env bash
# Spec 0008 AC #5 — drive classify_claude_failure() against every
# enumerated matcher and confirm the right ENVIRONMENT_FAILURE: tag is
# emitted (or no tag for unmatched assertion failures). The classifier
# is sourced from tests/e2e/run.sh and invoked directly with fixture
# log content piped on stdin.
#
# Matchers (spec 0008 AC #5):
#   credit_exhausted: "Credit balance is too low"
#   auth:             401, 403, ANTHROPIC_API_KEY unset, "invalid x-api-key",
#                     "authentication failed", "unauthorized" (case-insensitive)
#   transient_api:    5xx, 429, "network", "timeout", "connection refused"
#                     (case-insensitive)
#
# Exit: 0 pass, 2 fail.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
RUNSH="$REPO_ROOT/tests/e2e/run.sh"

fail() { echo "FAIL: $*" >&2; exit 2; }
note() { echo "  $*"; }

# Source run.sh's helper definitions without triggering its main flow.
# run.sh is structured so the function definitions come before the
# main `# ---- 1.` section. We can source it via a guard that exits
# before any echo lines run. The cleanest approach: extract just the
# `classify_claude_failure` function into a temp file and source that.
TMP_FN="$(mktemp)"
trap 'rm -f "$TMP_FN"' EXIT

awk '
  /^classify_claude_failure\(\) \{/ { inside=1 }
  inside { print }
  inside && /^\}/ { exit }
' "$RUNSH" > "$TMP_FN"

if [ ! -s "$TMP_FN" ]; then
  fail "classify_claude_failure() not found in $RUNSH (T9 GREEN not yet landed?)"
fi
# shellcheck disable=SC1090
. "$TMP_FN"

if ! declare -F classify_claude_failure >/dev/null 2>&1; then
  fail "classify_claude_failure was not loaded as a shell function"
fi

# Helper: classify a fixture log and check the result.
# Tests where ANTHROPIC_API_KEY shouldn't be the trigger must set it
# to a non-empty sentinel before invoking the classifier.
assert_category() {
  local label="$1" log_content="$2" expected="$3"
  local got
  got=$(printf '%s' "$log_content" | classify_claude_failure)
  if [ "$got" != "$expected" ]; then
    fail "$label: got '$got', want '$expected' -- log: $(printf '%s' "$log_content" | head -2 | tr '\n' '|')"
  fi
  note "$label → $expected"
}

# Default: API key set to a sentinel so the empty-key auth trigger doesn't
# fire for cases that don't intend it. Individual cases override.
export ANTHROPIC_API_KEY="sk-test-sentinel"

# --- credit_exhausted ---
assert_category "credit_exhausted literal" \
  $'Some preamble\nCredit balance is too low\nMore stuff\n' \
  "ENVIRONMENT_FAILURE: credit_exhausted"

# --- auth: HTTP 401 ---
assert_category "auth via HTTP 401" \
  $'HTTP/1.1 401 Unauthorized\n{"error":"bad key"}\n' \
  "ENVIRONMENT_FAILURE: auth"

# --- auth: HTTP 403 ---
assert_category "auth via HTTP 403" \
  $'status: 403 Forbidden\n' \
  "ENVIRONMENT_FAILURE: auth"

# --- auth: no credential present ---
# Subshell that unsets BOTH credentials (CLAUDE_CODE_OAUTH_TOKEN and the
# legacy ANTHROPIC_API_KEY). The presence check fires only when neither
# is set, so a single set var must suppress it.
(
  unset ANTHROPIC_API_KEY CLAUDE_CODE_OAUTH_TOKEN
  got=$(printf 'some unrelated output' | classify_claude_failure)
  if [ "$got" != "ENVIRONMENT_FAILURE: auth" ]; then
    fail "auth via no credential: got '$got', want 'ENVIRONMENT_FAILURE: auth'"
  fi
  note "auth via no credential → ENVIRONMENT_FAILURE: auth"
)

# A single present credential (OAuth token only) suppresses the empty-
# credential auth trigger for otherwise-unmatched output.
(
  unset ANTHROPIC_API_KEY
  export CLAUDE_CODE_OAUTH_TOKEN="oat-test-sentinel"
  got=$(printf 'some unrelated output' | classify_claude_failure)
  if [ -n "$got" ]; then
    fail "OAuth-token-only present: got '$got', want '' (no env failure)"
  fi
  note "OAuth token present, no ANTHROPIC_API_KEY → unmatched (no auth trigger)"
)

# --- auth: substring matchers (case-insensitive) ---
assert_category "auth via 'invalid x-api-key'" \
  $'error: Invalid x-api-key provided\n' \
  "ENVIRONMENT_FAILURE: auth"
assert_category "auth via 'authentication failed'" \
  $'Error: Authentication failed for request\n' \
  "ENVIRONMENT_FAILURE: auth"
assert_category "auth via 'unauthorized'" \
  $'response: UNAUTHORIZED access\n' \
  "ENVIRONMENT_FAILURE: auth"

# --- transient_api: HTTP 5xx ---
assert_category "transient_api via HTTP 503" \
  $'HTTP/1.1 503 Service Unavailable\n' \
  "ENVIRONMENT_FAILURE: transient_api"
assert_category "transient_api via HTTP 502" \
  $'status: 502 Bad Gateway\n' \
  "ENVIRONMENT_FAILURE: transient_api"

# --- transient_api: HTTP 429 ---
assert_category "transient_api via HTTP 429" \
  $'HTTP/1.1 429 Too Many Requests\n' \
  "ENVIRONMENT_FAILURE: transient_api"

# --- transient_api: substring matchers ---
assert_category "transient_api via 'network'" \
  $'curl: (6) Could not resolve host: network unreachable\n' \
  "ENVIRONMENT_FAILURE: transient_api"
assert_category "transient_api via 'timeout'" \
  $'error: request timeout after 60s\n' \
  "ENVIRONMENT_FAILURE: transient_api"
assert_category "transient_api via 'connection refused'" \
  $'curl: (7) Failed to connect: Connection refused\n' \
  "ENVIRONMENT_FAILURE: transient_api"

# --- assertion failure (no annotation) ---
assert_category "unmatched assertion failure (no annotation)" \
  $'FAIL: expected to exist: foo.txt\nbut it was not there\n' \
  ""

# --- ordering: credit_exhausted beats auth when both substrings present ---
# This anchors the priority order codex's R3 suggestion implied. If a
# log happens to contain both "Credit balance is too low" and an HTTP
# 401, credit_exhausted is the more specific signal.
assert_category "credit_exhausted wins over auth (ordering)" \
  $'HTTP/1.1 401 Unauthorized\nCredit balance is too low\n' \
  "ENVIRONMENT_FAILURE: credit_exhausted"

echo "OK: classify_claude_failure() satisfies all AC #5 matchers + ordering"
