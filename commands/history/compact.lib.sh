#!/usr/bin/env bash
# commands/history/compact.lib.sh — deterministic helpers backing
# /speccraft:history:compact (spec 0024). Sourced by commands/history/compact.md
# at runtime and by tests/hooks/history-compact.bats at test time.
#
# All functions are pure (no side effects at source time). Errors go to stderr;
# stdout carries structured output. Mirrors the commands/spec/revise.lib.sh
# "Sourceable command helpers" colocation convention.
#
# Parsing contract (spec 0024 §Lifecycle, CF-1/CF-6): a live ADR entry begins
# with a `## YYYY-MM-DD` header and runs until the next `## YYYY-MM-DD` header OR
# the `## Compacted …` sentinel. The window/count key is the DATE header alone —
# never the optional trailing `(spec NNNN)` / `(specs A, B)` suffix (the real
# corpus has suffix-less and plural entries). The parser splits ONLY on those two
# header shapes, so a `## ` heading inside an entry body never starts a new entry.

set -euo pipefail

# Config constants (OQ3 — "constants in the command's helper lib"). Overridable
# via the environment for testing; defaults are the documented values.
HISTORY_WINDOW_N="${HISTORY_WINDOW_N:-10}"
HISTORY_NUDGE_ENTRIES="${HISTORY_NUDGE_ENTRIES:-15}"
HISTORY_NUDGE_BYTES="${HISTORY_NUDGE_BYTES:-40960}"

# Anchored ERE for a dated ADR header line: "## YYYY-MM-DD ...".
_HISTORY_DATE_RE='^## [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] '

# history_parse_entries <history.md>
# Emit, in file order, the header line of every dated ADR entry. The
# `## Compacted …` section and any interior `## ` body heading are excluded.
history_parse_entries() {
  local file="$1"
  [ -f "$file" ] || { echo "history_parse_entries: $file not found" >&2; return 1; }
  awk '
    /^## Compacted/ { exit }
    /^## [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] / { print }
  ' "$file"
}

# history_window_split <history.md> <N> <window|older>
# Print the verbatim text (headers + bodies) of either the first N dated entries
# (the window) or the dated entries after the first N (the older set). The file
# preamble (before the first dated header) and the `## Compacted …` section are
# never emitted; the count key is the date header alone (CF-1).
history_window_split() {
  local file="$1" n="$2" which="$3"
  [ -f "$file" ] || { echo "history_window_split: $file not found" >&2; return 1; }
  case "$which" in window|older) ;; *)
    echo "history_window_split: which must be 'window' or 'older'" >&2; return 1 ;;
  esac
  awk -v n="$n" -v which="$which" '
    /^## Compacted/ { stop = 1 }
    stop { next }
    /^## [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] / { idx++; started = 1 }
    started {
      if (which == "window") { if (idx <= n) print }
      else                   { if (idx >  n) print }
    }
  ' "$file"
}

# _history_encode_entries  (reads entry text on stdin)
# Emit each dated entry as ONE line, its source lines joined by the 0x1e (RS)
# control byte and trailing blank lines stripped — so a full-entry byte-match
# survives trailing-whitespace variation. Non-entry preamble and the
# `## Compacted …` section are ignored. Internal helper.
_history_encode_entries() {
  awk '
    function flush() { if (have) { sub(/\036+$/, "", buf); print buf } }
    /^## Compacted/                                    { flush(); have=0; exit }
    /^## [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] /   { flush(); buf=$0; have=1; next }
    have                                               { buf = buf "\036" $0 }
    END                                                { flush() }
  '
}

# _history_decode_entry <encoded-line>
# Inverse of one _history_encode_entries record: 0x1e back to newlines, with a
# trailing newline. Internal helper.
_history_decode_entry() {
  printf '%s\n' "$1" | tr '\036' '\n'
}

# history_archive_append <archive.md>  (reads the entries to archive on stdin)
# Append each input dated entry verbatim (original header intact) to <archive.md>,
# skipping any entry already byte-present (full header+body match — CF-3). Creates
# the archive folder/file (with a one-time preamble) if absent. Append-only: never
# rewrites or deletes existing archive content. Writes ONLY under <archive.md>'s
# directory (blast radius — AC5).
history_archive_append() {
  local archive="$1"
  local incoming
  incoming="$(_history_encode_entries)"          # read stdin once
  [ -n "$incoming" ] || return 0                 # nothing to archive → no file write (AC4)
  mkdir -p "$(dirname "$archive")"
  if [ ! -f "$archive" ]; then
    printf '# History archive\n\nVerbatim records demoted from history.md by /speccraft:history:compact. Append-only.\n\n' > "$archive"
  fi
  local existing enc
  existing="$(_history_encode_entries < "$archive")"
  while IFS= read -r enc; do
    [ -n "$enc" ] || continue
    if ! printf '%s\n' "$existing" | grep -Fxq -- "$enc"; then
      { _history_decode_entry "$enc"; echo; } >> "$archive"
      existing+=$'\n'"$enc"
    fi
  done <<< "$incoming"
}

# history_nudge_predicate <count> <bytes> <N>
# Pure: print "nudge" iff there is something below the window (count > N) AND
# history exceeds a bound (count > HISTORY_NUDGE_ENTRIES OR bytes >
# HISTORY_NUDGE_BYTES); else "quiet". Gating on count>N is what stops the
# byte-size arm firing when nothing is actually compactable (CF-4). Exit 0.
history_nudge_predicate() {
  local count="$1" bytes="$2" n="$3"
  if [ "$count" -gt "$n" ] \
     && { [ "$count" -gt "$HISTORY_NUDGE_ENTRIES" ] || [ "$bytes" -gt "$HISTORY_NUDGE_BYTES" ]; }; then
    echo "nudge"
  else
    echo "quiet"
  fi
}

# history_compacted_section_themes <history.md>
# Emit the existing `### theme` groups (verbatim, from the first `### ` inside the
# `## Compacted …` section through EOF). This is the DURABLE re-compaction input:
# a later run merges newly demoted entries into these groups instead of
# regenerating them (CF-2 / AC11). Empty output when there is no Compacted section.
history_compacted_section_themes() {
  local file="$1"
  [ -f "$file" ] || { echo "history_compacted_section_themes: $file not found" >&2; return 1; }
  awk '
    /^## Compacted/ { inc=1; next }
    inc && /^### / { grab=1 }
    grab { print }
  ' "$file"
}

# history_supersession_seed <history.md> <N>
# Emit deterministic candidate supersession pairs "<older-id> <newer-id>", one per
# line, sorted/deduped — restricted to OUT-OF-WINDOW entries only (AC9/CF-1). For
# each older entry that HAS a provenance id (suffix-less entries yield no seed), its
# body is scanned for `supersedes: NNNN` markers and `spec[s] NNNN` cross-references;
# a referenced id that is itself another out-of-window entry's id becomes the older
# side. Window entries are never scanned and never appear as either side. Best-effort
# only — the command proposes these and the developer confirms; emits nothing when no
# deterministic signal exists.
history_supersession_seed() {
  local file="$1" n="$2"
  [ -f "$file" ] || { echo "history_supersession_seed: $file not found" >&2; return 1; }
  local older older_ids
  older="$(history_window_split "$file" "$n" older)"
  [ -n "$older" ] || return 0
  # Set of out-of-window provenance ids (one per line).
  older_ids="$(printf '%s\n' "$older" | grep -E "$_HISTORY_DATE_RE" | while IFS= read -r h; do
    printf '%s\n' "$h" | history_provenance_ids
  done)"
  {
    local enc entry header e_id body refs r
    while IFS= read -r enc; do
      [ -n "$enc" ] || continue
      entry="$(_history_decode_entry "$enc")"
      header="$(printf '%s\n' "$entry" | head -n1)"
      e_id="$(printf '%s\n' "$header" | history_provenance_ids | head -n1)"
      [ -n "$e_id" ] || continue                       # suffix-less → no newer side
      body="$(printf '%s\n' "$entry" | tail -n +2)"
      refs="$(printf '%s\n' "$body" \
        | grep -oE 'supersedes:[[:space:]]*[0-9]{4}|specs?[[:space:]]+[0-9]{4}([,[:space:]]+[0-9]{4})*' \
        | grep -oE '[0-9]{4}' || true)"
      for r in $refs; do
        [ "$r" != "$e_id" ] || continue
        if printf '%s\n' "$older_ids" | grep -qx -- "$r"; then
          printf '%s %s\n' "$r" "$e_id"
        fi
      done
    done < <(printf '%s\n' "$older" | _history_encode_entries)
  } | sort -u
}

# history_provenance_ids  (reads a header line, or entry text, on stdin)
# Emit each zero-padded spec id from the header's `(spec NNNN)` / `(specs A, B)`
# suffix, one per line. A suffix-less header emits nothing (optional, list-valued
# provenance — CF-1). Only the first input line (the header) is inspected, so a
# `(see spec NNNN)` reference inside a body never leaks in.
history_provenance_ids() {
  local header
  header="$(head -n1)"
  if [[ "$header" =~ \(specs?[[:space:]]+([0-9,[:space:]]+)\) ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}" | grep -oE '[0-9]{4}'
  fi
}
