#!/usr/bin/env bash
# commands/spec/consolidate.lib.sh — deterministic helpers backing spec
# consolidation (spec 0025). SOURCED by commands/spec/close.md (inline-at-close)
# and commands/sync.md (backfill) at runtime, and by
# tests/hooks/spec-consolidate.bats at test time.
#
# All functions are pure (no side effects at source time). Errors go to stderr;
# stdout carries structured output. Mirrors the commands/spec/revise.lib.sh and
# commands/history/compact.lib.sh "Sourceable command helpers" colocation
# convention (spec 0015).
#
# This feature is PURE SHELL + Markdown + bats — no Go binary is added, so no
# /speccraft:spec:override is ever needed (.sh/.md/.bats are not guard-gated).
#
# Cross-spec coupling (explicit, spec 0025 §Backfill): the backfill ordering
# reuses spec 0024's history parser. consolidate.lib.sh sources
# commands/history/compact.lib.sh for history_parse_entries /
# history_provenance_ids rather than maintaining a second chronology source.

set -euo pipefail

# Source spec 0024's history parser for the backfill chronology (explicit
# coupling). Resolve relative to this file so it works from any CWD.
_CONSOLIDATE_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../history/compact.lib.sh
source "$_CONSOLIDATE_LIB_DIR/../history/compact.lib.sh"

# Anchored ERE for the trailing provenance suffix on a requirement line:
# " (spec NNNN)" or " (specs NNNN, MMMM)".
_CONSOLIDATE_SUFFIX_RE='[[:space:]]*\(specs?[[:space:]]+[0-9][0-9,[:space:]]*\)[[:space:]]*$'

# _consolidate_normalize  (reads one line on stdin, or as $1)
# Normalize a requirement line for locator matching: strip a leading list
# marker ("- "), strip the trailing (spec NNNN)/(specs …) provenance suffix, and
# trim surrounding whitespace. The provenance suffix is NEVER part of the match
# key (spec 0025 §Merge — the suffix is provenance, not identity).
_consolidate_normalize() {
  local line="${1-$(cat)}"
  line="$(printf '%s' "$line" | sed -E "s/${_CONSOLIDATE_SUFFIX_RE}//")"
  line="$(printf '%s' "$line" | sed -E 's/^[[:space:]]*-[[:space:]]*//; s/^[[:space:]]+//; s/[[:space:]]+$//')"
  printf '%s' "$line"
}

# consolidate_parse_delta <spec.md>
# Parse the frontmatter `delta:` block into ordered tab-separated records
# "OP<TAB>LOCATOR<TAB>TEXT", one per line. ADD carries an empty LOCATOR; REMOVE
# carries an empty TEXT. A MODIFY/REMOVE missing a non-empty locator, or an
# unrecognized list item, is a malformed-block rejection: a stderr diagnostic,
# a non-zero exit, and NO stdout (AC1). A suffix-less requirement text parses
# fine (empty provenance is not an error).
consolidate_parse_delta() {
  local spec="$1"
  [ -f "$spec" ] || { echo "consolidate_parse_delta: $spec not found" >&2; return 1; }
  awk '
    function emit(   o) {
      if (!have) return
      o = op
      if ((o == "MODIFY" || o == "REMOVE") && loc == "") { err = 1; emsg = o " entry missing locator" }
      recs[n++] = op "\t" loc "\t" txt
      have = 0; op = ""; loc = ""; txt = ""
    }
    /^delta:[[:space:]]*$/ { indelta = 1; next }
    indelta && /^[^[:space:]]/ { emit(); indelta = 0 }   # dedent ends the block
    indelta {
      if ($0 ~ /^[[:space:]]*-[[:space:]]*[A-Za-z]+:?/) {
        emit()
        line = $0
        sub(/^[[:space:]]*-[[:space:]]*/, "", line)
        op = line; sub(/:.*/, "", op); sub(/[[:space:]]+$/, "", op)
        txt = line
        if (txt ~ /^[A-Za-z]+:/) { sub(/^[A-Za-z]+:[[:space:]]*/, "", txt) } else { txt = "" }
        loc = ""; have = 1
        if (op != "ADD" && op != "MODIFY" && op != "REMOVE") { err = 1; emsg = "unknown op: " op }
      } else if ($0 ~ /^[[:space:]]*locator:/) {
        loc = $0; sub(/^[[:space:]]*locator:[[:space:]]*/, "", loc); sub(/[[:space:]]+$/, "", loc)
      }
    }
    END {
      emit()
      if (err) { printf("consolidate_parse_delta: %s\n", emsg) > "/dev/stderr"; exit 2 }
      for (i = 0; i < n; i++) print recs[i]
    }
  ' "$spec"
}

# consolidate_locator_match <domain.md> <locator>
# Print the single domain requirement line whose normalized text equals the
# normalized locator, and exit 0. On zero or more-than-one match, print nothing
# and exit non-zero — the no-unique-match → conflict-path seed (spec 0025 §Merge,
# AC1). Matching ignores the trailing provenance suffix and surrounding
# whitespace on both sides.
consolidate_locator_match() {
  local domain="$1" locator="$2"
  [ -f "$domain" ] || { echo "consolidate_locator_match: $domain not found" >&2; return 1; }
  local want match count=0
  want="$(_consolidate_normalize "$locator")"
  match=""
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    if [ "$(_consolidate_normalize "$line")" = "$want" ]; then
      count=$((count + 1)); match="$line"
    fi
  done < "$domain"
  if [ "$count" -eq 1 ]; then printf '%s\n' "$match"; return 0; fi
  echo "consolidate_locator_match: $count matches for locator (need exactly 1) → conflict" >&2
  return 1
}

# consolidate_routing_seed <spec.md>
# If the spec frontmatter carries `domains: [a, b]`, echo each area verbatim
# (authoritative). Otherwise derive a deterministic, run-stable area seed key
# from the title (lowercased, non-alphanumerics → '-', collapsed, trimmed) —
# identical across runs for the same input, with no clock/randomness (AC2).
consolidate_routing_seed() {
  local spec="$1"
  [ -f "$spec" ] || { echo "consolidate_routing_seed: $spec not found" >&2; return 1; }
  local domains_line
  domains_line="$(grep -E '^domains:[[:space:]]*\[' "$spec" | head -1 || true)"
  if [ -n "$domains_line" ]; then
    printf '%s\n' "$domains_line" \
      | sed -E 's/^domains:[[:space:]]*\[//; s/\][[:space:]]*$//' \
      | tr ',' '\n' \
      | sed -E 's/^[[:space:]]*//; s/[[:space:]]*$//; s/^["'\'']//; s/["'\'']$//' \
      | grep -v '^$'
    return 0
  fi
  local title
  title="$(grep -E '^title:' "$spec" | head -1 | sed -E 's/^title:[[:space:]]*//; s/^"//; s/"$//')"
  printf '%s\n' "$title" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'
}

# _consolidate_encode_entries  (reads archive-B entry text on stdin)
# Join each archive-B entry (a "## area | spec … | OP" header line plus its body
# lines) into ONE line, source lines separated by 0x1e, trailing blanks stripped
# — so a full-entry byte-match survives trailing-whitespace variation. Internal.
_consolidate_encode_entries() {
  awk '
    function flush() { if (have) { sub(/\036+$/, "", buf); print buf } }
    /^## /  { flush(); buf = $0; have = 1; next }
    have    { buf = buf "\036" $0 }
    END     { flush() }
  '
}

_consolidate_decode_entry() { printf '%s\n' "$1" | tr '\036' '\n'; }

# consolidate_archiveB_append <archive.md>  (reads entries to archive on stdin)
# Append each input archive-B entry (header "## area | spec … | OP" + verbatim
# suffix-bearing superseded text) to <archive.md>, skipping any entry already
# byte-present (FULL-ENTRY header+text match — AC3/B5). Creates the archive
# folder/file with a one-time preamble if absent. Append-only: never rewrites or
# deletes existing content; writes nothing when stdin is empty (AC4 blast radius).
consolidate_archiveB_append() {
  local archive="$1"
  local incoming
  incoming="$(_consolidate_encode_entries)"
  [ -n "$incoming" ] || return 0
  mkdir -p "$(dirname "$archive")"
  if [ ! -f "$archive" ]; then
    printf '# Domain requirement archive\n\nVerbatim superseded requirement text demoted from a domain file by spec consolidation. Append-only.\n\n' > "$archive"
  fi
  local existing enc
  existing="$(_consolidate_encode_entries < "$archive")"
  while IFS= read -r enc; do
    [ -n "$enc" ] || continue
    if ! printf '%s\n' "$existing" | grep -Fxq -- "$enc"; then
      { _consolidate_decode_entry "$enc"; echo; } >> "$archive"
      existing+=$'\n'"$enc"
    fi
  done <<< "$incoming"
}

# _consolidate_match_lines <domain.md> <locator>
# Print every domain line whose normalized text equals the normalized locator.
# Internal — callers count the result. Always exits 0.
_consolidate_match_lines() {
  local domain="$1" locator="$2" want line
  want="$(_consolidate_normalize "$locator")"
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    [ "$(_consolidate_normalize "$line")" = "$want" ] && printf '%s\n' "$line"
  done < "$domain"
  return 0
}

# _consolidate_rewrite_line <domain.md> <matched-line> <op> <text>
# Replace the first occurrence of <matched-line> with "- <text>" (MODIFY) or drop
# it (REMOVE). Internal.
_consolidate_rewrite_line() {
  local domain="$1" matched="$2" op="$3" text="$4" tmp line replaced=0
  tmp="$(mktemp)"
  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$replaced" -eq 0 ] && [ "$line" = "$matched" ]; then
      replaced=1
      [ "$op" = "MODIFY" ] && printf -- '- %s\n' "$text" >> "$tmp"
      continue
    fi
    printf '%s\n' "$line" >> "$tmp"
  done < "$domain"
  mv "$tmp" "$domain"
}

# consolidate_apply_delta <domain.md> <archive.md> <area> <spec_id> <op> <locator> <text>
# Apply one delta entry idempotently with the pinned per-MODIFY/REMOVE write
# order: archive-B append FIRST, then the destructive domain mutation (the caller
# performs the dir-move LAST, only at zero conflicts). Returns 0 on apply/no-op, 2
# on a genuine conflict (locator matched 0-with-no-prior-apply or >1 lines). Spec
# 0025 AC6 / CF-1.
#   ADD    — dedups by normalized text; appends "- <text>" when absent.
#   MODIFY — unique match → archive old line, replace with "- <text>"; locator
#            absent but new text already present → no-op; else (0/>1) → conflict.
#   REMOVE — unique match → archive old line, delete it; locator absent → no-op
#            (already applied); >1 → conflict.
consolidate_apply_delta() {
  local domain="$1" archive="$2" area="$3" spec_id="$4" op="$5" locator="$6" text="$7"
  [ -f "$domain" ] || { echo "consolidate_apply_delta: $domain not found" >&2; return 1; }
  case "$op" in
    ADD)
      local want line; want="$(_consolidate_normalize "$text")"
      while IFS= read -r line; do
        [ -n "$line" ] || continue
        [ "$(_consolidate_normalize "$line")" = "$want" ] && return 0   # dedup
      done < "$domain"
      printf -- '- %s\n' "$text" >> "$domain"
      return 0
      ;;
    MODIFY|REMOVE)
      local matches n; matches="$(_consolidate_match_lines "$domain" "$locator")"
      n="$(printf '%s' "$matches" | grep -c . || true)"
      if [ "$n" -eq 1 ]; then
        # write order: archive-B FIRST, then domain mutation (CF-1)
        printf '## %s | spec %s | %s\n%s\n' "$area" "$spec_id" "$op" "$matches" \
          | consolidate_archiveB_append "$archive"
        _consolidate_rewrite_line "$domain" "$matches" "$op" "$text"
        return 0
      elif [ "$n" -gt 1 ]; then
        return 2   # ambiguous → conflict path
      fi
      # zero matches
      if [ "$op" = "MODIFY" ]; then
        local want line; want="$(_consolidate_normalize "$text")"
        while IFS= read -r line; do
          [ -n "$line" ] || continue
          [ "$(_consolidate_normalize "$line")" = "$want" ] && return 0   # already applied
        done < "$domain"
        return 2   # genuine conflict (old gone, new absent)
      fi
      return 0     # REMOVE: locator absent ⇒ already-applied no-op
      ;;
    *) echo "consolidate_apply_delta: unknown op $op" >&2; return 1 ;;
  esac
}

# consolidate_blast_radius_ok <path>
# Return 0 iff <path> (repo-relative) is one of the allow-listed consolidation
# write targets; non-zero otherwise. Spec 0025 AC4.
consolidate_blast_radius_ok() {
  case "$1" in
    specs/domains/.archive/*.md) return 0 ;;
    specs/domains/*.md) return 0 ;;
    specs/.archive/[0-9][0-9][0-9][0-9]-*) return 0 ;;
    specs/[0-9][0-9][0-9][0-9]-*/consolidation-conflicts.md) return 0 ;;
    specs/[0-9][0-9][0-9][0-9]-*/consolidation-skip) return 0 ;;
  esac
  return 1
}

# consolidate_assert_domain_invariants <domain.md>
# Fail (non-zero) if any requirement line ("- …") lacks a trailing
# (spec NNNN)/(specs …) provenance suffix. Spec 0025 AC5.
consolidate_assert_domain_invariants() {
  local domain="$1" line
  [ -f "$domain" ] || { echo "consolidate_assert_domain_invariants: $domain not found" >&2; return 1; }
  while IFS= read -r line; do
    case "$line" in
      "- "*)
        if ! printf '%s' "$line" | grep -qE '\(specs?[[:space:]]+[0-9][0-9,[:space:]]*\)[[:space:]]*$'; then
          echo "consolidate_assert_domain_invariants: missing provenance suffix: $line" >&2
          return 1
        fi
        ;;
    esac
  done < "$domain"
  return 0
}

# consolidate_skill_excludes_archives <skill.md>
# Fail (non-zero) if either .archive tree appears in the context-skill load list.
# Spec 0025 AC5 / context-skill invariant.
consolidate_skill_excludes_archives() {
  if grep -qE 'specs/\.archive/|specs/domains/\.archive/' "$1"; then
    echo "consolidate_skill_excludes_archives: an .archive tree is on the load list" >&2
    return 1
  fi
  return 0
}

# consolidate_record_conflict <spec_dir> [message]
# Append a conflict line to <spec_dir>/consolidation-conflicts.md (created with a
# preamble if absent). Its existence keeps the spec a live silo. Spec 0025 B3/CF-2.
consolidate_record_conflict() {
  local sd="$1" msg="${2:-unspecified conflict}" f="$1/consolidation-conflicts.md"
  [ -f "$f" ] || printf '# Consolidation conflicts\n\nUnresolved conflicts for this spec; its presence keeps the spec dir a live silo (not archived) until resolved.\n\n' > "$f"
  printf -- '- %s\n' "$msg" >> "$f"
}

# consolidate_clear_conflict <spec_dir>
# Delete the conflict sink once every recorded conflict is resolved; its ABSENCE
# is the zero-conflict precondition the dir-move gates on. Spec 0025 CF-2.
consolidate_clear_conflict() { rm -f "$1/consolidation-conflicts.md"; }

# consolidate_archive_dir_move <spec_dir> <archive_parent>
# MOVE (never delete) <spec_dir> → <archive_parent>/<basename>, ONLY when no
# consolidation-conflicts.md remains; refuse (non-zero) otherwise. The move is the
# caller's LAST step; frontmatter status is left untouched (location signals
# "consolidated"). Spec 0025 AC3/AC6/B2.
consolidate_archive_dir_move() {
  local sd="$1" archive_parent="$2"
  [ -d "$sd" ] || { echo "consolidate_archive_dir_move: $sd not a directory" >&2; return 1; }
  if [ -f "$sd/consolidation-conflicts.md" ]; then
    echo "consolidate_archive_dir_move: refusing — open conflicts remain in $sd" >&2
    return 1
  fi
  mkdir -p "$archive_parent"
  mv "$sd" "$archive_parent/"
}

# consolidate_marker_state <spec_dir>
# Echo the spec's consolidation state from its location + marker files:
# consolidated (under specs/.archive/) | conflict-open | declined | pending.
# Spec 0025 AC11 / B4.
consolidate_marker_state() {
  local sd="$1"
  case "$sd" in
    */.archive/*) echo "consolidated"; return 0 ;;
  esac
  if [ -f "$sd/consolidation-conflicts.md" ]; then echo "conflict-open"; return 0; fi
  if [ -f "$sd/consolidation-skip" ]; then echo "declined"; return 0; fi
  echo "pending"
}

# consolidate_backfill_candidates <repo_root>
# Print the basename of every closed spec dir still living directly under specs/
# (excluding specs/domains and the hidden specs/.archive) with no consolidation-skip
# marker — the location-based, clock-free backfill candidate predicate. Spec 0025
# AC11 / B4.
consolidate_backfill_candidates() {
  local repo="$1" d base
  for d in "$repo"/specs/*/; do
    base="$(basename "$d")"
    [ "$base" = "domains" ] && continue
    [ -f "$d/spec.md" ] || continue
    grep -qE '^status:[[:space:]]*closed' "$d/spec.md" || continue
    [ -f "$d/consolidation-skip" ] && continue
    printf '%s\n' "$base"
  done
}

# consolidate_backfill_order <repo_root> <space-separated candidate basenames>
# Print the candidates in backfill replay order: history.md chronological
# (oldest-first, reusing spec 0024's history_parse_entries / history_provenance_ids
# — explicit coupling, no second chronology source), then any candidate with no
# parseable history entry (history-less or compacted-out by spec 0024) ordered LAST
# by `created:` then ID. Spec 0025 AC11 / CF-3.
consolidate_backfill_order() {
  local repo="$1" candidates="$2"
  local H="$repo/.speccraft/history.md"
  local -a cand=( $candidates )
  local emitted="" hdr id c
  if [ -f "$H" ]; then
    while IFS= read -r hdr; do
      while IFS= read -r id; do
        for c in "${cand[@]}"; do
          [ "${c%%-*}" = "$id" ] || continue
          case " $emitted " in *" $c "*) ;; *) printf '%s\n' "$c"; emitted="$emitted $c" ;; esac
        done
      done < <(printf '%s\n' "$hdr" | history_provenance_ids)
    done < <(history_parse_entries "$H" | tac)
  fi
  # history-less / compacted-out candidates last, by created: then id
  local tmp created; tmp="$(mktemp)"
  for c in "${cand[@]}"; do
    case " $emitted " in *" $c "*) continue ;; esac
    created="$(grep -E '^created:' "$repo/specs/$c/spec.md" 2>/dev/null | head -1 | sed -E 's/^created:[[:space:]]*//' || true)"
    printf '%s\t%s\t%s\n' "$created" "${c%%-*}" "$c" >> "$tmp"
  done
  sort -t"$(printf '\t')" -k1,1 -k2,2 "$tmp" | cut -f3
  rm -f "$tmp"
}
