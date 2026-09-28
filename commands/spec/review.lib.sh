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

# ---------------------------------------------------------------------------
# Spec 0052 — round predicates and the round's single durable-write point.
#
# A round's result is a set of records, one per REQUIRED reviewer, of the shape
#   <agent> <outcome> [detail…]
# and TWO predicates are taken over it. They are deliberately separate because
# they gate different things, and conflating them breaks a real path:
#
#   responses_complete  — every required reviewer returned a VERDICT. Gates
#     synthesis, the review.md write and the reviewed_sha256 commit — and holds
#     for ANY verdict, `changes-requested` included (spec 0035 AC2).
#   approval_quorum_met — AGREEING verdicts >= the quorum. Gates `status:
#     reviewed`, and nothing else.
#
# `review_quorum` counts agreement, so gating the durable write on it would
# forbid exactly what a legitimate changes-requested round does: persist its
# review. A refusal, a timeout, a failure and a failed digest attestation are
# all non-verdicts — an over-budget agent is held to the same standard as the
# timeout it replaces, or a round reaches quorum having consulted fewer models
# than the developer believes.
# ---------------------------------------------------------------------------

REVIEW_VERDICTS="approve approve-with-comments changes-requested reject"
REVIEW_AGREEING_VERDICTS="approve approve-with-comments"
# A timeout is not a verdict (spec 0035 review.md step 6), and neither is a
# pre-dispatch budget refusal or a reference read that could not be attested.
REVIEW_NON_VERDICTS="refused timeout failed attestation-failed"

# _review_outcome_kind <outcome> — echo "verdict" | "non-verdict"; return 2 and
# name the token otherwise. An unrecognised outcome must NOT fall through to
# "non-verdict": a typo would then read as a refusal, quietly making a round
# inert with no indication why.
_review_outcome_kind() {
  local outcome="${1:-}" entry
  for entry in $REVIEW_VERDICTS; do
    [ "$outcome" = "$entry" ] && { printf 'verdict\n'; return 0; }
  done
  for entry in $REVIEW_NON_VERDICTS; do
    [ "$outcome" = "$entry" ] && { printf 'non-verdict\n'; return 0; }
  done
  review_error "review: unknown outcome '$outcome' (verdicts: $REVIEW_VERDICTS; non-verdicts: $REVIEW_NON_VERDICTS)"
  return 2
}

# review_responses_complete <outcomes-file>
#   0 — every required reviewer returned a verdict
#   1 — at least one did not, or the set is empty (a round that never ran is
#       not a round in which everyone answered)
#   2 — malformed record, named on stderr
review_responses_complete() {
  local file="${1:-}" agent outcome rest kind seen=0 rc
  [ -n "$file" ] && [ -f "$file" ] || {
    review_error "review_responses_complete: an outcomes file is required (got '${file:-}')"
    return 2
  }
  while IFS=' ' read -r agent outcome rest || [ -n "$agent" ]; do
    [ -n "$agent" ] || continue
    [ -n "$outcome" ] || { review_error "review_responses_complete: record for '$agent' has no outcome"; return 2; }
    rc=0; kind="$(_review_outcome_kind "$outcome")" || rc=$?
    [ "$rc" -eq 0 ] || return 2
    seen=$((seen + 1))
    [ "$kind" = "verdict" ] || return 1
  done < "$file"
  [ "$seen" -gt 0 ] || return 1
  return 0
}

# review_approval_quorum_met <quorum> <outcomes-file>
#   0 — agreeing verdicts (approve / approve-with-comments) >= quorum
#   1 — below quorum
#   2 — malformed quorum or record
review_approval_quorum_met() {
  local quorum="${1:-}" file="${2:-}" agent outcome rest entry count=0 rc kind
  case "$quorum" in
    ''|*[!0-9]*) review_error "review_approval_quorum_met: quorum must be a base-10 integer (got '${quorum:-}')"; return 2 ;;
  esac
  [ -n "$file" ] && [ -f "$file" ] || {
    review_error "review_approval_quorum_met: an outcomes file is required (got '${file:-}')"
    return 2
  }
  while IFS=' ' read -r agent outcome rest || [ -n "$agent" ]; do
    [ -n "$agent" ] || continue
    [ -n "$outcome" ] || { review_error "review_approval_quorum_met: record for '$agent' has no outcome"; return 2; }
    rc=0; kind="$(_review_outcome_kind "$outcome")" || rc=$?
    [ "$rc" -eq 0 ] || return 2
    for entry in $REVIEW_AGREEING_VERDICTS; do
      [ "$outcome" = "$entry" ] && count=$((count + 1))
    done
  done < "$file"
  [ "$count" -ge "$quorum" ]
}

# review_finalize_round <spec-dir> <quorum> <outcomes-file>
# — the ONLY place a review round performs a durable write. Emits the round
# report on stdout and returns 0 whether or not the round was productive: a
# refusal is data, not a shell failure.
#
# When `responses_complete` is false the round is INERT — no snapshot promote,
# no fingerprint commit, review.md untouched — and the report says so while
# still naming every verdict that WAS obtained. That is what stops a
# refusal-only round wiping the prior review.md and collapsing spec 0035's
# provenance gate on the next --diff.
#
# The snapshot promote lives HERE rather than at the start of the round (spec
# 0052 AC24). `review-diff --promote` used to re-baseline review-snapshot.md
# before any verdict existed, so an all-refused round silently moved the anchor
# the NEXT round classifies against, and the following round misclassified.
review_finalize_round() {
  local spec_dir="${1:-}" quorum="${2:-}" file="${3:-}"
  local complete=false quorum_met=false synthesis=skipped state=draft
  local rc fp agent outcome rest kind
  [ -n "$spec_dir" ] || { review_error "review_finalize_round: spec dir required"; return 2; }

  rc=0; review_responses_complete "$file" || rc=$?
  [ "$rc" -ne 2 ] || return 2
  [ "$rc" -eq 0 ] && complete=true

  rc=0; review_approval_quorum_met "$quorum" "$file" || rc=$?
  [ "$rc" -ne 2 ] || return 2
  [ "$rc" -eq 0 ] && quorum_met=true

  if [ "$complete" = true ]; then
    synthesis=done
    fp="$(speccraft-state review-snapshot write "$spec_dir")" || {
      review_error "review_finalize_round: review-snapshot write failed; review.md left unchanged"
      return 1
    }
    speccraft-state review-commit "$spec_dir/review.md" "$fp" || {
      review_error "review_finalize_round: review-commit failed; review.md left unchanged"
      return 1
    }
    [ "$quorum_met" = true ] && state=reviewed
  fi

  printf 'responses_complete: %s\n' "$complete"
  printf 'approval_quorum_met: %s\n' "$quorum_met"
  printf 'synthesis: %s\n' "$synthesis"
  printf 'status: %s\n' "$state"

  # Every refusal AND every verdict obtained. A report naming only the failures
  # hides a real verdict from the developer; one naming only the verdicts hides
  # that the round consulted fewer models than it appears to have.
  while IFS=' ' read -r agent outcome rest || [ -n "$agent" ]; do
    [ -n "$agent" ] || continue
    rc=0; kind="$(_review_outcome_kind "$outcome")" || rc=$?
    [ "$rc" -eq 0 ] || return 2
    if [ "$kind" = "verdict" ]; then
      printf 'verdict: %s %s\n' "$agent" "$outcome"
    elif [ "$outcome" = "attestation-failed" ]; then
      # Its own category: a reviewer whose reference reads never attest must be
      # diagnosable, not merely excluded round after round (AC25).
      printf 'attestation-failure: %s%s\n' "$agent" "${rest:+ $rest}"
    else
      printf 'no-verdict: %s %s%s\n' "$agent" "$outcome" "${rest:+ $rest}"
    fi
  done < "$file"
  return 0
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

# review_build_payload <template> <frozen_spec> <prior_review_file> <diff>
#   <changed_sections>
# — echo the scoped re-review payload (spec 0035 AC7b): the populated re-review
# brief (template with the {{DIFF}} / {{CHANGED_SECTIONS}} markers substituted),
# followed by the CURRENT spec content read from the round's FROZEN spec image
# (NOT spec.md — preserving the AC11 single-read transaction) and the prior
# review.md body as regression-context evidence.
#
# The frozen image used to be review-snapshot.md, promoted at the start of the
# round; spec 0052 AC24 defers that promote to the end, so the caller passes the
# round's own frozen copy instead. This helper never names either file — it
# reads only the path it is given.
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
  printf '\n===== CURRENT SPEC (frozen round image) =====\n'
  cat "$snapshot"
  printf '\n===== PRIOR REVIEW (settled vs. open) =====\n'
  cat "$prior"
}
