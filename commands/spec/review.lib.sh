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

# ---------------------------------------------------------------------------
# Spec 0052 — payload tiering and heading extraction.
#
# Tier membership is a FIXED TABLE, not a heuristic over the spec's content and
# not a size threshold: a file is inline or reference by identity, so the
# payload's shape cannot drift with the day's file sizes. Anything not in a
# table is an ERROR, never a silent default — `.speccraft/history.md` included,
# which this spec deliberately does not add to what a reviewer sees.
# ---------------------------------------------------------------------------

# Pasted verbatim: small, and guardrails in particular must be unmissable.
REVIEW_INLINE_SET=".speccraft/guardrails.md .speccraft/index.md"
# Sent as path + byte size + heading index; the reviewer reads what it needs.
REVIEW_REFERENCE_SET=".speccraft/architecture.md .speccraft/conventions.md"

review_error() { echo "$*" >&2; }

# _review_repo_relative <path> — echo <path> relative to the repository root.
# Absolute paths under the root are stripped to their repo-relative form; a
# leading `./` is removed; anything else is returned unchanged (and will fail
# the tier lookup, which is the point).
_review_repo_relative() {
  local p="$1" root
  root="$(speccraft-state find-root 2>/dev/null || pwd)"
  case "$p" in
    "$root"/*) p="${p#"$root"/}" ;;
    ./*)       p="${p#./}" ;;
  esac
  printf '%s\n' "$p"
}

# review_context_tier <path> — echo "inline" | "reference", or fail with a
# named error.
#
# The comparison is against the FULL repo-relative path, never the trailing
# basename. Matching on the basename would classify `vendor/other/.speccraft/
# conventions.md`, or a spec document that happens to be called
# `conventions.md`, as reference-tier — silently admitting a foreign file to
# the payload, or worse, omitting a real one's body on the assumption the
# reviewer can find it.
review_context_tier() {
  local path="${1:-}" rel entry
  [ -n "$path" ] || { review_error "review_context_tier: path required"; return 1; }
  rel="$(_review_repo_relative "$path")"
  for entry in $REVIEW_INLINE_SET; do
    [ "$rel" = "$entry" ] && { printf 'inline\n'; return 0; }
  done
  for entry in $REVIEW_REFERENCE_SET; do
    [ "$rel" = "$entry" ] && { printf 'reference\n'; return 0; }
  done
  review_error "review_context_tier: '$path' is not a known context file (tier table: $REVIEW_INLINE_SET $REVIEW_REFERENCE_SET)"
  return 1
}

# review_heading_index <file> — emit every `^## ` and `^### ` heading, in file
# order, and nothing else.
#
# PORTABILITY, load-bearing: the heading match uses anchored literal forms
# (`/^## /`, `/^### /`) and NEVER a regex INTERVAL EXPRESSION (a brace-delimited
# repetition count) on the hash run. This devcontainer runs mawk, which does not
# implement interval expressions and matches NOTHING for that form — silently,
# with exit 0. The identical spelling works under GNU `grep -E`, so the
# divergence is invisible without running it (cf.
# commands/history/compact.lib.sh:26, which spells the four-digit year as a
# bracket run rather than a repetition count for the same reason).
#
# The forbidden spelling is deliberately not written out here: this file sits
# under a scanned root, and tests/hooks/portability-guard.bats clause (f) flags
# the form in comments too, by design. The literal lives in that guard's
# fixtures and in tests/hooks/spec-review-payload.bats, both outside the scan.
#
# Fence grammar: a fence opens on a line whose first non-space run is three or
# more backticks or three or more tildes, and closes only on a line of the SAME
# character at the SAME OR GREATER length. An unclosed fence suppresses headings
# to end of file. Runs under LC_ALL=C so two hosts with different locales cannot
# produce different records from the same bytes.
review_heading_index() {
  local file="${1:-}"
  [ -n "$file" ] || { review_error "review_heading_index: file required"; return 1; }
  [ -e "$file" ] || { review_error "review_heading_index: $file not found"; return 1; }
  LC_ALL=C awk '
    # Length of the leading run of character c in s (interval-free).
    function runlen(s, c,   n) {
      n = 0
      while (substr(s, n + 1, 1) == c) n++
      return n
    }
    {
      line = $0
      sub(/\r$/, "", line)          # CRLF checkouts must not alter the record
      probe = line
      sub(/^[ ]*/, "", probe)       # a fence may be indented
      fc = substr(probe, 1, 1)
      n  = 0
      if (fc == "`" || fc == "~") n = runlen(probe, fc)

      if (infence) {
        # Close only on the same character at >= the opening length.
        if (n >= 3 && fc == fence_char && n >= fence_len) infence = 0
        next
      }
      if (n >= 3) { infence = 1; fence_char = fc; fence_len = n; next }
      if (line ~ /^## / || line ~ /^### /) print line
    }
  ' "$file"
}

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
