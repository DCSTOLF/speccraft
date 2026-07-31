#!/usr/bin/env bash
# commands/sync.lib.sh — deterministic helpers backing the /speccraft:sync WORKSPACE
# branch (spec 0043): out-of-band reconciliation of a workspace's ledger + member
# manifest against reality. Sourced by commands/sync.md at runtime and by
# tests/hooks/sync-workspace.bats at test time. Pure functions; no side effects at
# source time except sourcing its two sibling libs. Errors go to stderr (sync:
# prefix); stdout is reserved for structured findings. This is PURE SHELL — .sh is
# not guard-gated, so no /speccraft:spec:override is ever involved.
#
# Findings are emitted as exactly six tab-separated fields:
#   <class>\t<design>\t<member>\t<field>\t<value>\t<detail>
# For the three auto-fixable classes <field>/<value> name the ledger-set target;
# advisory classes leave them empty. Consumers MUST parse with `awk -F '\t'`
# (NF==6), never bash `IFS=$'\t' read` (tab is IFS-whitespace → empty columns lost).

set -euo pipefail

# Self-locate and source the reused machinery: the spec-0040 token machine
# (orch_reentry / orch_status_token / orch_next_phase / orch_in_flight_phase) and
# the spec-0042 ws_detect_members child scan.
_sync_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=commands/arch/orchestrate.lib.sh
source "$_sync_lib_dir/arch/orchestrate.lib.sh"
# shellcheck source=commands/init.lib.sh
source "$_sync_lib_dir/init.lib.sh"

sync_error() {
  echo "sync: $*" >&2
  return 1
}

# sync_emit <class> <design> <member> <field> <value> <detail> — one 6-field record.
sync_emit() {
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" "$6"
}

# sync_status_ahead <last_completed_phase> <member_status> — echo the token the
# pointer should advance to when the member's live status proves it is ahead of the
# stored pointer; otherwise print nothing and return non-zero. This is the
# out-of-band form of orch_reentry: ask whether the member already completed the
# phase AFTER the pointer. Never advances to an equal or earlier token (no rewind).
sync_status_ahead() {
  local lcp="${1-}" status="${2-}" next verdict token
  next="$(orch_next_phase "$lcp" 2>/dev/null)" || return 1
  [ "$next" = "done" ] && return 1                       # validated pointer: nothing ahead
  verdict="$(orch_reentry "$next" "$status" 2>/dev/null)" || return 1
  [ "$verdict" = "adopt" ] || return 1
  token="$(orch_status_token "$status" 2>/dev/null)" || return 1
  [ "$token" = "$lcp" ] && return 1                      # not strictly ahead
  printf '%s\n' "$token"
}

# sync_stale_in_flight <in_flight_value> <member_status> — classify an in_flight
# marker: `stale` (its phase's completion is already reflected in the status —
# crash residue, safe to clear), `live` (not yet reflected — possibly a running
# conductor, leave it), or `malformed` (the value is not a parseable phase).
sync_stale_in_flight() {
  local inflight="${1-}" status="${2-}" phase verdict
  phase="$(orch_in_flight_phase "$inflight" 2>/dev/null)" || { echo malformed; return 0; }
  verdict="$(orch_reentry "$phase" "$status" 2>/dev/null)" || { echo live; return 0; }
  [ "$verdict" = "adopt" ] && { echo stale; return 0; }
  echo live
}

# sync_ledger_drift <design> <member> <spec> <lcp> <in_flight> <blocked> <status> <resolved>
# — emit zero or more findings for one ledger member row. <status> is the member's
# live get-status; <resolved> is 1 when the spec ref resolved, else 0. A dangling
# ref short-circuits (drift can't be judged without a status). Order: status-ahead,
# stale-in-flight, stale-blocked, then advisories.
sync_ledger_drift() {
  local design="${1-}" member="${2-}" spec="${3-}" lcp="${4-}" inflight="${5-}" \
        blocked="${6-}" status="${7-}" resolved="${8-}" ahead="" malformed=0 st

  if [ -n "$spec" ] && [ "$resolved" != "1" ]; then
    sync_emit dangling-spec "$design" "$member" "" "" "spec ref does not resolve: $spec"
    return 0
  fi

  if ! orch_next_phase "$lcp" >/dev/null 2>&1; then
    sync_emit malformed-row "$design" "$member" "" "" "unknown last_completed_phase token: $lcp"
    malformed=1
  fi

  if [ "$malformed" -eq 0 ]; then
    ahead="$(sync_status_ahead "$lcp" "$status" 2>/dev/null || true)"
    [ -n "$ahead" ] && sync_emit status-ahead "$design" "$member" last_completed_phase "$ahead" \
      "advance pointer $lcp → $ahead (status $status)"
  fi

  if [ -n "$inflight" ]; then
    st="$(sync_stale_in_flight "$inflight" "$status")"
    case "$st" in
      stale)     sync_emit stale-in-flight "$design" "$member" in_flight "" \
                   "clear stale in_flight=$inflight (completion reflected in status $status)" ;;
      malformed) sync_emit malformed-row "$design" "$member" "" "" "in_flight failed to parse: $inflight" ;;
      live)      : ;;
    esac
  fi

  if [ -n "$blocked" ] && [ -n "$ahead" ]; then
    sync_emit stale-blocked "$design" "$member" blocked "" \
      "clear stale blocked=$blocked (member advanced to status $status)"
  fi
  return 0
}

# _sync_manifest_basenames <root> — the workspace.yml member set as normalized
# basenames (leading ./ stripped), one per line, sorted-unique.
_sync_manifest_basenames() {
  ( cd "$1" && speccraft-state list-members 2>/dev/null || true ) \
    | awk -F '\t' 'NF>=2{print $2}' | sed 's#^\./##' | LC_ALL=C sort -u
}

# sync_membership_audit <root> — advisory membership findings composing list-members
# (manifest), ws_detect_members (filesystem), and ledger-get (ledger). workspace.yml
# is NEVER rewritten. Design column is empty (membership is not design-scoped).
sync_membership_audit() {
  local root="$1" manifest base
  manifest="$(_sync_manifest_basenames "$root")"

  # stale-member: a manifest member missing on disk.
  ( cd "$root" && speccraft-state list-members 2>/dev/null || true ) \
    | awk -F '\t' '$1=="missing"{print $2}' | while IFS= read -r m; do
      [ -n "$m" ] && sync_emit stale-member "" "$m" "" "" "manifest member missing on disk: $m"
    done

  # unlisted-member: a kind=repo child not in the manifest.
  ws_detect_members "$root" 2>/dev/null | sed 's#^\./##' | while IFS= read -r base; do
    [ -z "$base" ] && continue
    printf '%s\n' "$manifest" | grep -qxF "$base" \
      || sync_emit unlisted-member "" "$base" "" "" "kind=repo child not in workspace.yml: $base"
  done

  # orphan-ledger-row: a ledger member path not in the manifest.
  ( cd "$root" && speccraft-state ledger-get 2>/dev/null || true ) \
    | awk -F '\t' 'NF>=2{print $2}' | sed 's#^\./##' | LC_ALL=C sort -u | while IFS= read -r base; do
      [ -z "$base" ] && continue
      printf '%s\n' "$manifest" | grep -qxF "$base" \
        || sync_emit orphan-ledger-row "" "$base" "" "" "ledger row for a non-member: $base"
    done
  return 0
}

# sync_apply_member_plan <root> <design> <member> <expected_row> <field=value>...
# — the AC10 conflict-safe apply. Re-read the member's ledger row ONCE; only if it
# is byte-identical to <expected_row> (captured at detection) apply the fixes via
# `ledger-set` in the fixed order last_completed_phase → in_flight → blocked (values
# passed as argv, never eval'd). If the row changed, emit a single `conflict` finding
# and apply nothing (no rewind, no clobber of newer state).
sync_apply_member_plan() {
  local root="$1" design="$2" member="$3" expected="$4"; shift 4
  local current p fix value
  current="$( ( cd "$root" && speccraft-state ledger-get "$design" 2>/dev/null || true ) \
              | awk -F '\t' -v m="$member" '$2==m{print; exit}' )"
  if [ "$current" != "$expected" ]; then
    sync_emit conflict "$design" "$member" "" "" "ledger row changed since detection; skipped"
    return 0
  fi
  for p in last_completed_phase in_flight blocked; do
    for fix in "$@"; do
      case "$fix" in
        "$p="*)
          value="${fix#*=}"
          ( cd "$root" && speccraft-state ledger-set "$design" "$member" "$p" "$value" ) || return 1
          ;;
      esac
    done
  done
  return 0
}
