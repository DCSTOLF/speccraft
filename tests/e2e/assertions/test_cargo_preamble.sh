#!/usr/bin/env bash
# Assertion for spec 0005 AC #9: tests/e2e/run.sh must fail fast with a
# clear "cargo not found on PATH" message when cargo is absent. This
# protects the Rust e2e path (AC #6) from silently misreporting cargo-
# absence as some other failure.
#
# Two checks:
#   1. Source-level: tests/e2e/run.sh contains the literal string
#      "cargo not found on PATH" — i.e. the preamble is wired.
#   2. Functional: when invoked with cargo absent from PATH, the preamble
#      writes the message to stderr and exits non-zero.
#
# Run from the repo root.

set -euo pipefail

RUNSH="${RUNSH:-tests/e2e/run.sh}"

if [ ! -f "$RUNSH" ]; then
  echo "FAIL: $RUNSH does not exist" >&2
  exit 1
fi

# --- Check 1: source-level grep ---
if ! grep -qF 'cargo not found on PATH' "$RUNSH"; then
  echo "FAIL: $RUNSH missing 'cargo not found on PATH' preamble check" >&2
  echo "      AC #9 requires the e2e harness to fail fast on missing cargo." >&2
  exit 1
fi

# --- Check 2: functional — invoke the preamble with cargo stripped ---
# We extract the preamble between the marker comments and exec it in a
# subshell with a PATH that does not contain any directory holding cargo.
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

sed -n '/# >>> cargo-preamble/,/# <<< cargo-preamble/p' "$RUNSH" > "$TMP"
if [ ! -s "$TMP" ]; then
  echo "FAIL: $RUNSH missing '# >>> cargo-preamble' ... '# <<< cargo-preamble' markers" >&2
  exit 1
fi

# Strip directories holding cargo from PATH.
STRIPPED_PATH=""
IFS=':' read -ra DIRS <<< "${PATH:-}"
for d in "${DIRS[@]}"; do
  if [ -z "$d" ]; then continue; fi
  if [ -x "$d/cargo" ]; then continue; fi
  STRIPPED_PATH="${STRIPPED_PATH}${STRIPPED_PATH:+:}$d"
done

set +e
output=$(PATH="$STRIPPED_PATH" bash "$TMP" 2>&1)
exit_code=$?
set -e

if [ "$exit_code" -eq 0 ]; then
  echo "FAIL: preamble exited 0 with cargo absent; expected non-zero" >&2
  exit 1
fi
if ! echo "$output" | grep -qF 'cargo not found on PATH'; then
  echo "FAIL: preamble did not print 'cargo not found on PATH' to stderr" >&2
  echo "      Got: $output" >&2
  exit 1
fi

echo "OK: $RUNSH cargo-preamble assertion (AC #9) passes"
