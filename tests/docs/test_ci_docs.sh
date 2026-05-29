#!/usr/bin/env bash
# Spec 0008 AC #6 — assert README documents the CI changes from this spec:
#   (a) which CI jobs require API credits and which don't
#   (b) the language-only entrypoint as the fast-signal path
#   (c) what `ENVIRONMENT_FAILURE:` means in the lifecycle job
#
# Exit: 0 pass, 2 fail.

set -euo pipefail

README="${README:-README.md}"

fail() { echo "FAIL: $*" >&2; exit 2; }
note() { echo "  $*"; }

if [ ! -f "$README" ]; then
  fail "$README does not exist"
fi

# Each of these keywords must appear at least once in the README.
want_keywords=(
  "ANTHROPIC_API_KEY"             # docs (a) — jobs requiring API credits name the secret
  "e2e-language-only"             # docs (a)+(b) — the new job name
  "--language-only"               # docs (b) — the flag form
  "ENVIRONMENT_FAILURE"            # docs (c) — the annotation prefix
  "credit_exhausted"              # docs (c) — at least one enumerated category surfaced
)

missing=()
for kw in "${want_keywords[@]}"; do
  if ! grep -qF -- "$kw" "$README"; then
    missing+=("$kw")
  fi
done

if [ "${#missing[@]}" -gt 0 ]; then
  echo "FAIL: $README missing required CI documentation keywords:" >&2
  for kw in "${missing[@]}"; do
    echo "  - $kw" >&2
  done
  exit 2
fi

note "all required CI keywords present"
echo "OK: $README documents spec 0008 CI changes (AC #6)"
