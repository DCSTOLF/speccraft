#!/usr/bin/env bash
# Spec 0008 AC #3 + AC #4 — assert .github/workflows/ci.yml contains a
# valid `e2e-language-only` job that:
#   - runs on push AND pull_request (NOT gated to push to main)
#   - executes `bash tests/e2e/run.sh --language-only` inside devcontainer
#   - does NOT set ANTHROPIC_API_KEY in env: or pass it via --remote-env
#   - the YAML parses
#
# Verifiable by reading the workflow file at PR-review time — does not
# depend on CI actually running.
#
# Exit:
#   0 — all assertions pass
#   2 — assertion failed

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CIYAML="$REPO_ROOT/.github/workflows/ci.yml"

fail() { echo "FAIL: $*" >&2; exit 2; }
note() { echo "  $*"; }

if [ ! -f "$CIYAML" ]; then
  fail "$CIYAML does not exist"
fi

# ---- 1. YAML parses (best-effort; uses whichever parser is available) ----
yaml_check_passed=0
if command -v python3 >/dev/null 2>&1 \
   && python3 -c 'import yaml' 2>/dev/null; then
  python3 -c "
import sys, yaml
try:
    yaml.safe_load(open('$CIYAML'))
except Exception as e:
    sys.stderr.write(f'YAML parse error: {e}\n')
    sys.exit(1)
" && yaml_check_passed=1 || fail "ci.yml does not parse as valid YAML (PyYAML)"
fi
if [ "$yaml_check_passed" = "0" ] && command -v yq >/dev/null 2>&1; then
  yq eval '.' "$CIYAML" >/dev/null 2>&1 \
    && yaml_check_passed=1 \
    || fail "ci.yml does not parse as valid YAML (yq)"
fi
if [ "$yaml_check_passed" = "1" ]; then
  note "ci.yml parses as valid YAML"
else
  note "no PyYAML/yq available — skipped YAML parse check (CI will catch malformed YAML)"
fi

# ---- 2. Job exists ----
if ! grep -qE '^[[:space:]]+e2e-language-only:' "$CIYAML"; then
  fail "ci.yml does not declare an 'e2e-language-only:' job"
fi
note "e2e-language-only job declared"

# Extract the job's block for the rest of the checks. Block extraction:
# from the job header line until the next sibling job (top-level 2-space-indented key)
# or end of file.
JOB_BLOCK="$(awk '
  /^[[:space:]]+e2e-language-only:/ {
    found=1
    # Capture the indent depth of the job header (e.g. 2 spaces).
    match($0, /^[[:space:]]+/)
    header_indent=RLENGTH
    print
    next
  }
  # Stop when we hit a sibling job (a line indented at exactly the same
  # depth as the header, ending in `:`). Inner keys like `steps:` are
  # indented deeper than the job header, so they pass through.
  found {
    match($0, /^[[:space:]]*/)
    cur=RLENGTH
    if (cur <= header_indent && /:/ && /^[[:space:]]+[a-zA-Z_-]+:/) { exit }
    print
  }
' "$CIYAML")"

if [ -z "$JOB_BLOCK" ]; then
  fail "could not extract e2e-language-only job block"
fi

# ---- 3. References `tests/e2e/run.sh --language-only` ----
if ! echo "$JOB_BLOCK" | grep -qF -- 'tests/e2e/run.sh --language-only'; then
  fail "e2e-language-only job does not invoke 'tests/e2e/run.sh --language-only'"
fi
note "job invokes 'tests/e2e/run.sh --language-only'"

# ---- 4. Does NOT set ANTHROPIC_API_KEY ----
# Strip YAML comment lines (line-starting `#` with optional leading
# whitespace) so explanatory comments mentioning ANTHROPIC_API_KEY don't
# trigger false positives. The check looks for real `env:` references or
# `--remote-env` argv passes.
JOB_BLOCK_NOCOMMENT="$(echo "$JOB_BLOCK" | grep -vE '^[[:space:]]*#')"
if echo "$JOB_BLOCK_NOCOMMENT" | grep -qE 'ANTHROPIC_API_KEY'; then
  fail "e2e-language-only job references ANTHROPIC_API_KEY (must not — AC #3 + AC #4)"
fi
note "no ANTHROPIC_API_KEY reference in the job (comments excluded)"

# ---- 5. Triggered by push AND pull_request ----
# Look at the workflow-level `on:` block.
ON_BLOCK="$(awk '
  /^on:[[:space:]]*$/ { found=1; print; next }
  found && /^[^[:space:]]/ { exit }
  found { print }
' "$CIYAML")"

if ! echo "$ON_BLOCK" | grep -qE '^[[:space:]]+push:'; then
  fail "workflow does not trigger on push"
fi
if ! echo "$ON_BLOCK" | grep -qE '^[[:space:]]+pull_request:'; then
  fail "workflow does not trigger on pull_request"
fi
note "workflow triggers on push AND pull_request"

# ---- 6. NOT gated to push-to-main (job has no `if:` restricting it) ----
# The existing e2e-devcontainer job is gated by:
#   if: github.event_name == 'push' && github.ref == 'refs/heads/main'
# The new e2e-language-only job MUST NOT have that gate (spec AC #3).
if echo "$JOB_BLOCK" | grep -qE "github\.ref.*refs/heads/main"; then
  fail "e2e-language-only job is gated to push-to-main; must run on every push and PR"
fi
note "no push-to-main gate"

echo "OK: e2e-language-only job satisfies AC #3 + AC #4"
