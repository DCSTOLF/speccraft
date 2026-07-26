#!/usr/bin/env bash
# commands/spec/review.lib.sh — testable shell helpers backing the diff-focused
# re-review path of /speccraft:spec:review (spec 0035). Sourced both by
# commands/spec/review.md at runtime and by tests/hooks/spec-review-diff.bats.
#
# All functions are pure (no top-level side effects). The Go binaries own change
# DETECTION (speccraft-state review-diff / review-snapshot); this lib owns the
# command-layer UX: parsing the prior review fingerprint, classifying the run via
# the provenance gate, and building the scoped reviewer payload.
#
# Cross-shell self-location and zsh-reserved-name avoidance follow the spec-0029
# conventions; no bare `status` locals.

set -euo pipefail

# review_reviewed_sha256 <review.md> — echo the single usable reviewed_sha256
# value, or return non-zero. "Usable" (spec 0035 AC8) = exactly one line matching
# the anchored grammar ^reviewed_sha256: <64 lowercase hex>$. Zero, multiple, or
# malformed such lines → not usable.
review_reviewed_sha256() {
  local file="$1"
  [ -f "$file" ] || return 1
  local matches count
  matches="$(grep -E '^reviewed_sha256: [0-9a-f]{64}$' "$file" 2>/dev/null || true)"
  [ -n "$matches" ] || return 1
  count="$(printf '%s\n' "$matches" | grep -c .)"
  [ "$count" = "1" ] || return 1
  printf '%s\n' "${matches#reviewed_sha256: }"
}

# review_classify <snapshot> <changed> <base_fingerprint> <prior_reviewed_sha256>
# — echo the UX branch per the spec 0035 Provenance gate:
#   full-review   : first review (snapshot=false), OR the prior review.md is
#                   unusable / its fingerprint != base_fingerprint (baseline not
#                   the last-reviewed version — includes the failed-promote case).
#   short-circuit : baseline is the reviewed version AND nothing changed.
#   scoped        : baseline is the reviewed version AND the spec changed.
# The caller passes an empty prior_reviewed_sha256 when review.md is unusable.
review_classify() {
  local snapshot="$1" changed="$2" base="$3" prior="$4"
  if [ "$snapshot" != "true" ]; then
    printf 'full-review\n'
    return 0
  fi
  if [ -z "$prior" ] || [ "$prior" != "$base" ]; then
    printf 'full-review\n'
    return 0
  fi
  if [ "$changed" = "true" ]; then
    printf 'scoped\n'
  else
    printf 'short-circuit\n'
  fi
}

# review_build_payload <template> <snapshot_file> <prior_review_file> <diff>
#   <changed_sections>
# — echo the scoped re-review payload (spec 0035 AC7b): the populated re-review
# brief (template with the {{DIFF}} / {{CHANGED_SECTIONS}} markers substituted),
# followed by the CURRENT spec content read from the FROZEN review-snapshot.md
# (NOT spec.md — preserving the AC11 single-read transaction) and the prior
# review.md body as regression-context evidence.
review_build_payload() {
  local template="$1" snapshot="$2" prior="$3" diff="$4" sections="$5"
  local line
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      '{{DIFF}}') printf '%s\n' "$diff" ;;
      '{{CHANGED_SECTIONS}}') printf '%s\n' "$sections" ;;
      *) printf '%s\n' "$line" ;;
    esac
  done < "$template"
  printf '\n===== CURRENT SPEC (frozen review-snapshot.md) =====\n'
  cat "$snapshot"
  printf '\n===== PRIOR REVIEW (settled vs. open) =====\n'
  cat "$prior"
}
