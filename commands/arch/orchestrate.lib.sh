#!/usr/bin/env bash
# commands/arch/orchestrate.lib.sh — deterministic helpers backing
# /speccraft:arch:orchestrate (spec 0039). Sourced by commands/arch/orchestrate.md
# at runtime and by tests/hooks/arch-orchestrate.bats at test time. Pure functions,
# no side effects at source time. Errors go to stderr (orchestrate: prefix); stdout
# is reserved for structured output. Never assigns a var named `status` (zsh binds
# it; bats binds `$status`).

set -euo pipefail

# orchestrate_error <message...> — central error envelope: message to stderr,
# non-zero return. stdout is left clean for structured output.
orchestrate_error() {
  echo "orchestrate: $*" >&2
  return 1
}

# orch_next_phase <last_completed_token> — echo the next ACTION to run, resuming
# from the ledger pointer. Unknown token → error.
orch_next_phase() {
  case "${1:-}" in
    "")          echo new ;;
    new)         echo review ;;
    reviewed)    echo plan ;;
    planned)     echo implement ;;
    implemented) echo validate ;;
    validated)   echo done ;;
    *)           orchestrate_error "unknown phase token: '${1:-}'" ;;
  esac
}

# orch_completed_token <action> — echo the ledger token written back after the
# action succeeds. `revise` and unknown actions have no token (they do not advance
# the pointer) → error.
orch_completed_token() {
  case "${1:-}" in
    new)       echo new ;;
    review)    echo reviewed ;;
    plan)      echo planned ;;
    implement) echo implemented ;;
    validate)  echo validated ;;
    *)         orchestrate_error "no completed token for action: '${1:-}'" ;;
  esac
}

# orch_should_pause <next_action> <straight_through> — checkpoint (a): echo `pause`
# iff the next action is `implement` and straight-through is not enabled; else `go`.
orch_should_pause() {
  local next="${1:-}" straight="${2:-}"
  if [ "$next" = "implement" ] && [ "$straight" != "1" ]; then
    echo pause
  else
    echo go
  fi
}

# orch_review_verdict <iteration> <max> <critic_verdict> — review->revise control:
# `pass` on a pass verdict; else `revise` while iteration < max; else `escalate`
# (checkpoint b). iteration = completed revise cycles (0 at first review).
orch_review_verdict() {
  local iter="${1:-0}" max="${2:-0}" verdict="${3:-}"
  if [ "$verdict" = "pass" ]; then
    echo pass
  elif [ "$iter" -lt "$max" ]; then
    echo revise
  else
    echo escalate
  fi
}

# _orch_trim <string> — strip leading/trailing whitespace (interior kept).
_orch_trim() {
  local s="${1-}"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

# orch_parse_decomposition <file> — parse the human-confirmed decomposition into
# normalized `<member-path>\t<brief>` lines. Blank lines and full-line `#` comments
# (first non-whitespace char is `#`) are ignored. Each other line splits on its
# FIRST tab (member = before, brief = remainder verbatim); both are end-trimmed.
# Errors (stderr, non-zero): no tab, empty member/brief, duplicate member, or a
# member-path outside the safe charset ^[A-Za-z0-9._/-]+$.
orch_parse_decomposition() {
  local file="${1:-}"
  [ -f "$file" ] || { orchestrate_error "decomposition file not found: '$file'"; return 1; }
  local line lead member brief m
  local -a seen=()
  while IFS= read -r line || [ -n "$line" ]; do
    lead="${line#"${line%%[![:space:]]*}"}"      # leading whitespace removed
    [ -n "$lead" ] || continue                    # blank
    [ "${lead:0:1}" != "#" ] || continue          # full-line comment (incl. indented)
    case "$line" in
      *$'\t'*) : ;;
      *) orchestrate_error "decomposition line has no tab: '$line'"; return 1 ;;
    esac
    member="$(_orch_trim "${line%%$'\t'*}")"
    brief="$(_orch_trim "${line#*$'\t'}")"
    [ -n "$member" ] || { orchestrate_error "empty member-path in decomposition"; return 1; }
    [ -n "$brief" ] || { orchestrate_error "empty brief for member '$member'"; return 1; }
    [[ "$member" =~ ^[A-Za-z0-9._/-]+$ ]] || { orchestrate_error "invalid member-path (charset ^[A-Za-z0-9._/-]+\$): '$member'"; return 1; }
    if [ "${#seen[@]}" -gt 0 ]; then
      for m in "${seen[@]}"; do
        [ "$m" != "$member" ] || { orchestrate_error "duplicate member-path: '$member'"; return 1; }
      done
    fi
    seen+=("$member")
    printf '%s\t%s\n' "$member" "$brief"
  done < "$file"
}

# orch_dispatch <member-path> <action> — echo the cwd-scoped invocation the
# orchestrator runs for a phase: (cd '<member-path>' && <mapped-command>). The
# member-path is single-quoted so dispatch can never eval-inject; the output never
# contains --root (the member's own FindRoot resolves).
orch_dispatch() {
  local member="${1:-}" action="${2:-}" cmd
  case "$action" in
    new)       cmd="/speccraft:spec:new" ;;
    review)    cmd="/speccraft:spec:review" ;;
    revise)    cmd="/speccraft:spec:revise" ;;
    plan)      cmd="/speccraft:spec:plan" ;;
    implement) cmd="/speccraft:spec:implement" ;;
    validate)  cmd="/speccraft:spec:close" ;;
    *)         orchestrate_error "unknown dispatch action: '$action'"; return 1 ;;
  esac
  printf "(cd '%s' && %s)\n" "$member" "$cmd"
}

# orch_validate <test_cmd> — the deterministic validate gate: run the member's
# configured test command (trusted repo config — the same trust boundary the
# guard's runner uses) and echo `pass` on exit 0 else `fail`.
orch_validate() {
  if sh -c "${1:-false}"; then
    echo pass
  else
    echo fail
  fi
}

# orch_apply_result <workspace-root> <design> <member> <action> <exit_code> — the
# advisory, failure-isolated ledger transition, written through 0038's
# `speccraft-state ledger-set`. in_flight is cleared on EVERY completed attempt (a
# finished attempt is not mid-execution). On success: advance the pointer + clear
# blocked + clear in_flight. On failure: set blocked, clear in_flight, leave the
# pointer put. Never touches sibling rows.
orch_apply_result() {
  local ws="${1:-}" design="${2:-}" member="${3:-}" action="${4:-}" code="${5:-1}"
  local set_ledger tok
  set_ledger() { ( cd "$ws" && speccraft-state ledger-set "$design" "$member" "$1" "$2" ); }
  if [ "$code" -eq 0 ]; then
    tok="$(orch_completed_token "$action")" || return 1
    set_ledger last_completed_phase "$tok"
    set_ledger blocked ""
  else
    set_ledger blocked "$action failed"
  fi
  set_ledger in_flight ""
}

# ==== spec 0040: crash-safe re-entry helpers ====

# orch_status_ordinal <status> — rank a member-spec status for re-entry comparison
# ("" / blocked never reach a completion ordinal). Unknown non-empty → error.
orch_status_ordinal() {
  case "${1-}" in
    "")              echo -1 ;;
    blocked)         echo -1 ;;
    draft)           echo 0 ;;
    reviewed)        echo 1 ;;
    planned)         echo 2 ;;
    in-progress)     echo 3 ;;
    closed|archived) echo 4 ;;
    *)               orchestrate_error "unknown status: '${1-}'" ;;
  esac
}

# orch_status_token <status> — the ledger token a completion status implies (adopt
# jumps the pointer here). "" / blocked / unknown → error (only called on adopt).
orch_status_token() {
  case "${1-}" in
    draft)           echo new ;;
    reviewed)        echo reviewed ;;
    planned)         echo planned ;;
    in-progress)     echo implemented ;;
    closed|archived) echo validated ;;
    *)               orchestrate_error "no ledger token for status: '${1-}'" ;;
  esac
}

# orch_phase_completion_status <phase> — the status that proves a phase completed.
orch_phase_completion_status() {
  case "${1-}" in
    new)       echo draft ;;
    review)    echo reviewed ;;
    plan)      echo planned ;;
    implement) echo in-progress ;;
    validate)  echo closed ;;
    *)         orchestrate_error "unknown phase: '${1-}'" ;;
  esac
}

# orch_reentry <in_flight_phase> <member_status> — echo `adopt` when the member's
# status ordinal >= the phase's completion ordinal, else `reattempt`. "" / blocked
# (ordinal -1) never adopt.
orch_reentry() {
  local phase="${1-}" st="${2-}" member_ord comp_status comp_ord
  member_ord="$(orch_status_ordinal "$st")" || return 1
  comp_status="$(orch_phase_completion_status "$phase")" || return 1
  comp_ord="$(orch_status_ordinal "$comp_status")" || return 1
  if [ "$member_ord" -ge "$comp_ord" ]; then
    echo adopt
  else
    echo reattempt
  fi
}

# orch_in_flight_phase <in_flight_value> — extract the phase: a bare token (no `=`)
# is the phase; a structured value yields the first `phase=<p>` token (any position,
# first-wins); `=` tokens without `phase=`, or empty, → error.
orch_in_flight_phase() {
  local val="${1-}" tok
  case "$val" in
    "") orchestrate_error "empty in_flight value" ;;
    *=*)
      for tok in $val; do
        case "$tok" in phase=*) echo "${tok#phase=}"; return 0 ;; esac
      done
      orchestrate_error "in_flight has no phase= token: '$val'"
      ;;
    *) echo "$val" ;;
  esac
}

# orch_find_member_spec <member-root> <design-id> — crash-safe adoption key for the
# `new` phase: echo the NNNN-slug of the member spec whose `informed-by` frontmatter
# names `design/<design-id>` (what `spec:new --from design/<id>` writes). Scans
# specs/* then specs/.archive/*. Zero → empty, exit 0. ≥2 → error (ambiguous — the
# very double-allocate this prevents). A get-frontmatter READ failure on any
# candidate → error (never a false zero-match).
orch_find_member_spec() {
  local root="${1-}" design="${2-}" spec fm d
  local -a matches=()
  for d in "$root"/specs/*/ "$root"/specs/.archive/*/; do
    spec="${d}spec.md"
    [ -f "$spec" ] || continue
    if fm="$(speccraft-state get-frontmatter "$spec" informed-by 2>/dev/null)"; then
      case "$fm" in
        *"design/$design"*) matches+=("$(basename "$d")") ;;
      esac
    else
      orchestrate_error "get-frontmatter read failure on '$spec'"; return 1
    fi
  done
  case "${#matches[@]}" in
    0) : ;;
    1) echo "${matches[0]}" ;;
    *) orchestrate_error "ambiguous adoption: ${#matches[@]} member specs back-reference design/$design"; return 1 ;;
  esac
}
