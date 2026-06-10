#!/usr/bin/env bash
# tests/e2e/contains_adr_assertion_test.sh — assertion test for the
# contains_regex helper introduced by spec 0014.
#
# Exercises the *exact* predicate the production assertion in
# tests/e2e/run.sh:[7/9] /speccraft:spec:close uses, against two
# synthetic histories:
#
#   - positive: a history.md with a well-formed dated ADR header.
#     contains_regex must pass.
#   - negative: a history.md containing only the bare-template intro.
#     contains_regex must FAIL (we invert via a subshell — see below).
#
# The fixture and run.sh source the same lib.sh, so the predicate
# implementation is provably identical at runtime. If contains_regex's
# regex semantics ever drift in lib.sh, this fixture catches it before
# the brittle-assertion failure mode (the [7/9] step failing because
# memory-keeper happened to pick a non-feature ADR title) can recur.
#
# Exit codes match the E2E language-fixture pattern: 0 success, 2 on
# any assertion failure (via lib.sh's fail()).
set -euo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$LIB_DIR/lib.sh"

# note() — intra-scenario progress lines, mirrored from python_cycle.sh
# per the E2E language-fixture-pattern convention.
note() { echo "  $*"; }

echo "==> contains_adr_assertion_test (spec 0014)"

# ---------------------------------------------------------------------------
# AC3 precondition sanity: the bare template history.md must contain no
# date-anchored ADR header. If a future template change accidentally
# adds one, this fixture flags it before the fixture's own negative
# case (which depends on the template's bareness) could silently rot.
# ---------------------------------------------------------------------------
REPO_ROOT="$(cd "$LIB_DIR/../.." && pwd)"
TEMPLATE_HISTORY="$REPO_ROOT/templates/speccraft/history.md"
if grep -nE '^## 20[0-9]{2}-[0-9]{2}-[0-9]{2}' "$TEMPLATE_HISTORY" >/dev/null 2>&1; then
  fail "AC3 precondition: $TEMPLATE_HISTORY unexpectedly contains a date-anchored ADR header"
fi
note "AC3 precondition: $TEMPLATE_HISTORY has no date-anchored ADR header"

# ---------------------------------------------------------------------------
# Positive case: a history.md with a well-formed dated ADR header.
# contains_regex must succeed and emit a PASS line.
# ---------------------------------------------------------------------------
TMP_POS="$(mktemp -d -t adr-assert-pos.XXXXXX)"
trap 'rm -rf "$TMP_POS" "${TMP_NEG:-}"' EXIT

cat > "$TMP_POS/history.md" <<'EOF'
# History

Append-only. Newest first.

## 2026-06-10 — Sample (spec 0001)

body
EOF

note "positive case: history.md with dated ADR header"
contains_regex "$TMP_POS/history.md" "^## 20[0-9]{2}-[0-9]{2}-[0-9]{2}"

# ---------------------------------------------------------------------------
# Negative case: a history.md with only the bare template intro (no
# ADR yet). contains_regex must FAIL — i.e. exit non-zero via fail().
#
# Naive `contains_regex ...` here would exit the fixture via fail()
# (exit 2). We invert: run contains_regex inside a subshell with
# stderr/stdout suppressed; if the subshell *succeeds*, that means
# contains_regex matched when it shouldn't have, and we fail loudly.
# Documented inline so a future reader doesn't "simplify" this into a
# form that breaks under set -e.
# ---------------------------------------------------------------------------
TMP_NEG="$(mktemp -d -t adr-assert-neg.XXXXXX)"

cat > "$TMP_NEG/history.md" <<'EOF'
# History

Append-only. Newest first.
EOF

note "negative case: history.md with only bare-template intro"
if ( contains_regex "$TMP_NEG/history.md" "^## 20[0-9]{2}-[0-9]{2}-[0-9]{2}" ) >/dev/null 2>&1; then
  fail "negative case: contains_regex unexpectedly matched template-only history.md"
fi
note "negative case: contains_regex correctly rejected template-only history.md"

echo "PASS: contains_adr_assertion_test.sh"
