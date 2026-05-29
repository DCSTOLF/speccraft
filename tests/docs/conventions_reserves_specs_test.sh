#!/usr/bin/env bash
# Spec 0005 AC #11: .speccraft/conventions.md must document the
# `reserves-specs` frontmatter field introduced by this spec.
#
# Required content (from AC #11):
#   - The literal field name `reserves-specs`
#   - The six rules: purpose, shape, allocation, lifecycle, consistency, lower-bound

set -euo pipefail

CONV="${CONV:-.speccraft/conventions.md}"

if [ ! -f "$CONV" ]; then
  echo "FAIL: $CONV does not exist" >&2
  exit 1
fi

want_keywords=(
  "reserves-specs"          # the field itself
  "Purpose"                 # bullet 1
  "Shape"                   # bullet 2
  "Allocation"              # bullet 3
  "Lifecycle"               # bullet 4
  "Consistency"             # bullet 5
  "Lower-bound"             # bullet 6 (lower-bound rule)
  "speccraft:spec:new"      # tool that should skip reserved IDs
  "0006"                    # this spec's reserved id
)

missing=()
for kw in "${want_keywords[@]}"; do
  if ! grep -qF "$kw" "$CONV"; then
    missing+=("$kw")
  fi
done

if [ "${#missing[@]}" -gt 0 ]; then
  echo "FAIL: $CONV missing reserves-specs documentation keywords:" >&2
  for kw in "${missing[@]}"; do
    echo "  - $kw" >&2
  done
  exit 1
fi

echo "OK: $CONV has all required reserves-specs documentation (AC #11)"
