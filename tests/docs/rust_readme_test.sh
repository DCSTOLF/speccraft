#!/usr/bin/env bash
# Spec 0005 AC #7 + AC #12 docs: README.md must document the Rust
# support added in this spec.
#
# Required content:
#   - A "Rust" section header
#   - [tdd.rust] config block (subsection name + runner field)
#   - Mention of both inline tests AND integration tests
#   - Mention of cargo / cargo-nextest runners
#   - Mention of the pre-edit gate (crate fingerprint / cargo check)
#   - Mention of rust_test_baseline + rust-baseline recapture lifecycle (AC #12)
#   - Explicit statement that templates/speccraft/** is NOT modified (AC #7 path b)

set -euo pipefail

README="${README:-README.md}"

if [ ! -f "$README" ]; then
  echo "FAIL: $README does not exist" >&2
  exit 1
fi

want_keywords=(
  "Rust"                       # any Rust section/heading
  "[tdd.rust]"                 # config subsection literal
  "runner"                     # the runner field
  "cargo test"                 # default runner mention
  "cargo nextest"              # opt-in runner mention
  "inline"                     # inline-test path (AC #2)
  "integration"                # integration-test path (AC #3)
  "rust_test_baseline"         # AC #12 lifecycle field
  "rust-baseline recapture"    # AC #12 manual recapture subcommand
  "crate fingerprint"          # AC #10 pre-edit gate
  "stack-agnostic"             # confirms templates stay untouched (AC #7 path b)
)

missing=()
for kw in "${want_keywords[@]}"; do
  if ! grep -qF "$kw" "$README"; then
    missing+=("$kw")
  fi
done

if [ "${#missing[@]}" -gt 0 ]; then
  echo "FAIL: $README missing required Rust-section keywords:" >&2
  for kw in "${missing[@]}"; do
    echo "  - $kw" >&2
  done
  exit 1
fi

echo "OK: $README has all required Rust-section keywords (AC #7 + AC #12 docs)"
