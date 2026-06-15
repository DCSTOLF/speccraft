#!/usr/bin/env bash
# tests/e2e/revise_noop_assertion_test.sh — assertion test for the
# /speccraft:spec:revise no-op step's log assertion (spec 0020).
#
# Background: the e2e step [6/13] /speccraft:spec:revise no-op asserts the
# no-op branch ran by grepping the live `claude -p` final-message log
# (06-revise-noop.log). The command's no-op branch emits a deterministic
# marker ("no changes — spec unchanged"), but the model paraphrases it
# ("no-op", "byte-identical"), so a fixed-string `contains "no changes"`
# misses and CI fails on phrasing, not a defect. Spec 0020 makes that
# assertion tolerant via `contains_regex`.
#
# This fixture pins the run.sh assertion's behaviour, mirroring the spec
# 0014 contains_adr_assertion_test.sh precedent. It reads run.sh's *live*
# no-op assertion line so the predicate it validates cannot silently
# diverge from production:
#
#   - Scenario A: the no-op assertion line MUST be a `contains_regex`
#     call (not the fixed-string `contains`). FAILs while run.sh still
#     uses `contains "no changes"` — this is the spec 0020 RED.
#   - Scenario B: run.sh's live regex pattern MUST match all three
#     phrasings — the deterministic marker, "no-op", "byte-identical".
#   - Scenario C: the pattern must NOT match an unrelated real-change
#     line (no false positive); inverted via a subshell.
#
# The fixture and run.sh source the same lib.sh, so contains_regex's
# semantics are provably identical at runtime.
#
# Exit codes match the E2E language-fixture pattern: 0 success, 2 on any
# assertion failure (via lib.sh's fail()).
set -euo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$LIB_DIR/lib.sh"

# note() — intra-scenario progress lines, mirrored from python_cycle.sh
# per the E2E language-fixture-pattern convention.
note() { echo "  $*"; }

echo "==> revise_noop_assertion_test (spec 0020)"

REPO_ROOT="$(cd "$LIB_DIR/../.." && pwd)"
RUN_SH="$REPO_ROOT/tests/e2e/run.sh"

# ---------------------------------------------------------------------------
# Locate the live no-op log assertion line in run.sh. There are two lines
# mentioning 06-revise-noop.log (the run_claude invocation and the
# assertion); anchor on the assertion by requiring the line to start with
# a `contains`-family call. fail loudly if the count is not exactly 1, so
# a future reformat surfaces here rather than silently passing.
# ---------------------------------------------------------------------------
ASSERT_LINES="$(grep -nE '^[[:space:]]*contains([_a-z]*)?[[:space:]].*06-revise-noop\.log' "$RUN_SH" || true)"
N_MATCH="$(printf '%s\n' "$ASSERT_LINES" | grep -c . || true)"
if [ "$N_MATCH" -ne 1 ]; then
  fail "expected exactly 1 no-op log assertion line in $RUN_SH, found $N_MATCH:
$ASSERT_LINES"
fi
ASSERT_LINE="${ASSERT_LINES#*:}"
note "located no-op assertion line: ${ASSERT_LINE#"${ASSERT_LINE%%[![:space:]]*}"}"

# ---------------------------------------------------------------------------
# Scenario A: the assertion must be a `contains_regex` call, not the
# fixed-string `contains`. `contains` is a prefix of `contains_regex`, so
# distinguish on the token boundary.
# ---------------------------------------------------------------------------
note "scenario A: no-op assertion uses contains_regex (not fixed-string contains)"
if ! printf '%s\n' "$ASSERT_LINE" | grep -qE '^[[:space:]]*contains_regex[[:space:]]'; then
  fail "scenario A: no-op assertion must use contains_regex, got: $ASSERT_LINE"
fi
note "scenario A: ok"

# Extract the regex pattern — the last double-quoted argument on the line.
PATTERN="$(printf '%s\n' "$ASSERT_LINE" | sed -E 's/.*"([^"]*)"[[:space:]]*$/\1/')"
if [ -z "$PATTERN" ] || [ "$PATTERN" = "$ASSERT_LINE" ]; then
  fail "scenario B: could not extract regex pattern from: $ASSERT_LINE"
fi
note "scenario B: extracted live pattern: $PATTERN"

# ---------------------------------------------------------------------------
# Scenario B: the live pattern must match all three phrasings — the
# deterministic command marker, plus the model paraphrases that broke the
# original fixed-string assertion.
# ---------------------------------------------------------------------------
TMP="$(mktemp -d -t revise-noop-assert.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

while IFS= read -r phrase; do
  printf '%s\n' "$phrase" > "$TMP/log"
  note "scenario B: pattern matches phrasing: $phrase"
  contains_regex "$TMP/log" "$PATTERN"
done <<'PHRASES'
no changes — spec unchanged
no-op
byte-identical
PHRASES

# ---------------------------------------------------------------------------
# Scenario C: negative — an unrelated real-change summary must NOT match
# the pattern. Invert via subshell exactly as the ADR fixture does:
# contains_regex calls fail() (exit 2) on no-match, so a naive call would
# abort the fixture; run it in a subshell and treat a *successful* match
# as the failure.
# ---------------------------------------------------------------------------
printf '%s\n' "the spec was extensively rewritten and three acceptance criteria were added" > "$TMP/log-neg"
note "scenario C: pattern rejects an unrelated real-change line"
if ( contains_regex "$TMP/log-neg" "$PATTERN" ) >/dev/null 2>&1; then
  fail "scenario C: pattern unexpectedly matched an unrelated real-change line"
fi
note "scenario C: ok"

echo "PASS: revise_noop_assertion_test.sh"
