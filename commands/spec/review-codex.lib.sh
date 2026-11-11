#!/usr/bin/env bash
# commands/spec/review-codex.lib.sh — the `codex-plugin` reviewer adapter
# (spec 0054, Phase C).
#
# Sourced by commands/spec/review.lib.sh, which owns the mode router; this file
# owns everything specific to driving the Codex plugin's companion. Split out at
# step 28 to keep review.lib.sh from growing past ~1,600 lines, and because the
# adapter is the part a reader needs to follow end to end: resolve a plugin
# root, preflight it, launch a background job, poll it, collect its result, and
# classify what came back.
#
# Two invariants hold across the whole file and are each pinned by a test:
#
#   Portability. These libs are `source`d into the caller's shell, which on
#   macOS is zsh, so nothing here may assume bash semantics. In particular the
#   deadline wrapper uses neither `wait -n` (zsh: "job not found: -n") nor job
#   control (zsh refuses `set -m` in a script), and there is no timeout(1),
#   which macOS does not ship.
#
#   A transport fault is never a verdict. Every failure path emits one
#   `failed <token>` line and returns non-zero, so a caller records an outcome
#   instead of mistaking a broken companion for a reviewer's answer.
#
# NO SIDE EFFECTS AT SOURCE TIME: sourcing defines functions and nothing more.
# The preflight memo file is created lazily, inside the function that needs it.
#
# Cross-shell self-location and zsh-reserved-name avoidance follow the spec-0029
# and spec-0030 conventions; no bare `status` locals.

# ---------------------------------------------------------------------------
# AC10 — bounding a single companion invocation.
#
# This is NOT the job deadline. The Codex broker is spawned detached and
# unref'd, so stopping the local caller says nothing about the reviewer; the
# job's own budget ends in `companion cancel`, further down this file.
# ---------------------------------------------------------------------------

# _review_kill_tree <pid> — TERM a process and every descendant, DEEPEST FIRST.
#
# Depth-first matters: killing the parent before its children can leave the
# grandchildren reparented to init and running, which is the exact shape of
# "the reviewer kept going after we timed out".
#
# Portability notes, each one load-bearing:
#   - no `pkill -f`: its pattern would also match the caller's own argv;
#   - no process groups: the obvious route is `set -m`, and zsh refuses it in a
#     script ("can't change option: -m"). A sourced lib must not change the
#     caller's shell options in any case;
#   - `ps -eo pid=,ppid=` is POSIX and works on both BSD and GNU userland,
#     unlike `--ppid`, which is GNU-only.
_review_kill_tree() {
  local victim="$1" kid
  for kid in $(ps -eo pid=,ppid= | awk -v p="$victim" '$2 == p {print $1}'); do
    _review_kill_tree "$kid"
  done
  kill -TERM "$victim" 2>/dev/null || true
}

# review_with_deadline <seconds> <command> [args...] — run the command, and if
# it has not finished within <seconds>, kill its whole tree and return 124.
# Otherwise return the command's OWN exit status, unaltered. The command's
# stdout passes straight through.
#
# This bounds ONE companion invocation. It is deliberately NOT the job deadline:
# the Codex broker is spawned detached and `unref`'d, so killing the local
# caller proves only that the caller stopped. Stopping the reviewer needs
# `companion cancel <job-id>`, which is AC6a's path.
#
# Why a status file rather than `wait -n` on two jobs: `wait -n` is bash-only
# (zsh answers "job not found: -n", rc 127) and these libs are sourced into the
# caller's shell, which on macOS is zsh. Polling the file also sidesteps a
# subtler trap — `kill -0` SUCCEEDS on a zombie, so an unreaped child that has
# already exited still looks alive, and a kill -0 poll would wait out the full
# deadline on a command that finished immediately.
#
# Granularity is one second, so a command that finishes sooner still costs up to
# a second here. That is immaterial against a reviewer turn and against the
# 5 s status poll, and it keeps the loop free of fractional-sleep assumptions.
#
# A command whose own exit status is 124 is indistinguishable from an expiry.
# Nothing in this spec dispatches such a command: the companion's statuses are
# 0 and 1, and the caller classifies on those.
review_with_deadline() {
  local deadline_s="${1:-}"
  case "$deadline_s" in
    '' | 0 | *[!0-9]*)
      printf 'review_with_deadline: deadline must be a positive integer of seconds, got "%s"\n' \
        "$deadline_s" >&2
      return 2
      ;;
  esac
  shift
  [ "$#" -gt 0 ] || {
    printf 'review_with_deadline: no command given\n' >&2
    return 2
  }

  local rcfile waited=0 cmd_rc job_pid
  rcfile="$(mktemp)"

  # `set +e` inside the subshell is required, not defensive: this lib runs under
  # `set -e`, which would abort the subshell the instant the command exits
  # non-zero — before `echo $?` could record the status this function exists to
  # return. Without it every failing reviewer invocation looks like a timeout.
  #
  # Stdin must be restored explicitly. bash redirects a background job's stdin
  # from /dev/null when job control is off, which it always is here, so the
  # command would read NOTHING: the codex launch piped through xargs received
  # no argv and ran `env` bare, and this lib's own stdin transport
  # (`$cmd < artifact`) would hand a reviewer an empty payload while it still
  # answered. fd 9, not fd 3 — bats holds fd 3 for its TAP stream and this lib
  # is sourced into bats. If the duplication fails (stdin already closed), the
  # command runs without it rather than the whole call failing.
  local stdin_saved=0
  if exec 9<&0 2>/dev/null; then
    stdin_saved=1
  fi

  if [ "$stdin_saved" -eq 1 ]; then
    (
      set +e
      exec 0<&9 9<&-
      "$@"
      echo "$?" > "$rcfile"
    ) &
  else
    (
      set +e
      "$@"
      echo "$?" > "$rcfile"
    ) &
  fi
  job_pid=$!
  [ "$stdin_saved" -eq 0 ] || exec 9<&-

  # Ticks, not whole seconds. A one-second granularity would charge ~1s to
  # EVERY companion invocation — and the adapter makes several per reviewer
  # (launch, each status poll, result, cancel) — so a round would spend seconds
  # purely in this loop. Sub-second ticks keep the deadline exact to the second
  # while returning promptly when the command finishes.
  #
  # Fractional sleep is not in POSIX, so it is PROBED rather than assumed: GNU,
  # BSD/macOS and busybox all accept it, and where it is missing the loop falls
  # back to whole seconds and stays correct, just less responsive.
  local tick ticks_per_s waited_ticks=0 deadline_ticks
  if sleep 0.1 2>/dev/null; then
    tick=0.1
    ticks_per_s=10
  else
    tick=1
    ticks_per_s=1
  fi
  deadline_ticks=$((deadline_s * ticks_per_s))

  while [ ! -s "$rcfile" ] && [ "$waited_ticks" -lt "$deadline_ticks" ]; do
    sleep "$tick"
    waited_ticks=$((waited_ticks + 1))
  done
  waited=$((waited_ticks / ticks_per_s))

  if [ -s "$rcfile" ]; then
    cmd_rc="$(cat "$rcfile")"
    rm -f "$rcfile"
    wait "$job_pid" 2>/dev/null || true
    return "$cmd_rc"
  fi

  _review_kill_tree "$job_pid"
  # Reap quietly. bash announces a signalled job ("Terminated") when it reaps
  # one, and this function's stdout is parsed as reviewer output, so that notice
  # must not leak into it.
  wait "$job_pid" 2>/dev/null || true
  rm -f "$rcfile"
  return 124
}

# ---------------------------------------------------------------------------
# AC5 / AC5a / AC5d — resolving the Codex plugin root and its version.
# ---------------------------------------------------------------------------

# The lowest version whose handleTask is known to accept this spec's argv
# (--prompt-file, --cwd, --json). The range is open-ended above it, so a newer
# companion resolves forward-compatibly rather than needing a bump here.
REVIEW_CODEX_MIN_VERSION="1.0.6"
REVIEW_CODEX_PLUGIN_KEY="codex@openai-codex"

# _review_codex_installed_json — the host registry path, under $HOME so tests
# can redirect the whole lookup with a fake HOME.
_review_codex_installed_json() {
  printf '%s\n' "${HOME:-}/.claude/plugins/installed_plugins.json"
}

# _review_canonical_dir <path> — absolute, symlink-resolved directory path.
#
# Canonicalized with `cd` plus `pwd -P`, never with the GNU-only canonicalizers
# — realpath's -m flag, or readlink's -f — because macOS's userland has
# neither. The portability guard rejects both on sight, a comment included,
# which is why they are named descriptively here rather than spelled out; the
# first version of this comment tripped that guard.
#
# A non-directory is echoed unchanged, so the caller's own existence check
# produces the diagnostic rather than this helper swallowing the path.
_review_canonical_dir() {
  local d="${1:-}"
  [ -n "$d" ] && [ -d "$d" ] || { printf '%s\n' "$d"; return 0; }
  ( CDPATH='' cd -- "$d" 2>/dev/null && pwd -P )
}

# _review_version_parseable <version> — numeric dotted components only.
# Anything else ("", "not-a-version", "1.0.6-beta") is UNPARSEABLE and maps to
# unknown-version, never to a guess: a version we cannot read is not a version
# we may compare against the supported range.
_review_version_parseable() {
  case "${1:-}" in
    '') return 1 ;;
    *[!0-9.]*) return 1 ;;
    .* | *.) return 1 ;;
    *..*) return 1 ;;
    *) return 0 ;;
  esac
}

# _review_version_ge <a> <b> — true when a >= b, compared COMPONENT-WISE and
# numerically. A string compare would read 1.0.10 as below 1.0.6, which is the
# classic dotted-version bug; `$((...))` also strips leading zeros.
_review_version_ge() {
  local a="${1:-0}" b="${2:-0}" ai bi
  while [ -n "$a" ] || [ -n "$b" ]; do
    ai="${a%%.*}"
    bi="${b%%.*}"
    [ -n "$ai" ] || ai=0
    [ -n "$bi" ] || bi=0
    ai=$((ai))
    bi=$((bi))
    if [ "$ai" -ne "$bi" ]; then
      [ "$ai" -gt "$bi" ]
      return $?
    fi
    case "$a" in *.*) a="${a#*.}" ;; *) a="" ;; esac
    case "$b" in *.*) b="${b#*.}" ;; *) b="" ;; esac
  done
  return 0
}

# _review_codex_version_for_root <root> — the version for an ALREADY-RESOLVED
# root, from whichever source owns it.
#
# Which source is not a preference, it is a consequence of how the root was
# found (AC5d): a root installed_plugins.json knows about is described by that
# entry, and a root it has never heard of can only describe itself, via the
# companion-owned manifest. Sourcing the version ONLY from
# installed_plugins.json would leave a valid explicit plugin_root permanently
# unknown-version with no configuration able to satisfy it. A root present in
# both is read from installed_plugins.json, so one root yields one version.
#
# Echoes the raw version string, or nothing when neither source has one.
_review_codex_version_for_root() {
  local root="$1" reg entry_version canon
  reg="$(_review_codex_installed_json)"
  canon="$(_review_canonical_dir "$root")"

  if [ -f "$reg" ]; then
    # Match on the canonicalized installPath so a symlinked or trailing-slash
    # spelling of the same root still finds its entry.
    entry_version="$(
      jq -r --arg key "$REVIEW_CODEX_PLUGIN_KEY" '
        (.plugins[$key] // []) | .[] | select(.installPath != null)
        | [.installPath, (.version // "")] | @tsv
      ' "$reg" 2>/dev/null | while IFS="$(printf '\t')" read -r ipath iver; do
        [ -n "$ipath" ] || continue
        if [ "$(_review_canonical_dir "$ipath")" = "$canon" ]; then
          printf '%s\n' "$iver"
          break
        fi
      done
    )"
    if [ -n "$entry_version" ]; then
      printf '%s\n' "$entry_version"
      return 0
    fi
  fi

  # Fall through to the companion-owned manifest. An unparseable manifest
  # yields nothing, which the caller maps to unknown-version.
  local manifest
  manifest="$root/.claude-plugin/plugin.json"
  if [ -f "$manifest" ]; then
    jq -r '.version // empty' "$manifest" 2>/dev/null || true
  fi
}

# _review_codex_root_from_registry — the installPath per AC5's precedence:
# the `local` entry whose projectPath is THIS repo, else the `user` entry.
# A local entry belonging to a different project must not win, which is why
# projectPath is compared rather than merely being present.
_review_codex_root_from_registry() {
  local reg repo
  reg="$(_review_codex_installed_json)"
  [ -f "$reg" ] || return 1
  repo="$(speccraft-state find-root 2>/dev/null || pwd)"
  repo="$(_review_canonical_dir "$repo")"

  local found
  found="$(
    jq -r --arg key "$REVIEW_CODEX_PLUGIN_KEY" --arg repo "$repo" '
      (.plugins[$key] // []) as $e
      | ( [ $e[] | select(.scope == "local" and .projectPath == $repo) ][0].installPath
          // [ $e[] | select(.scope == "user") ][0].installPath
          // empty )
    ' "$reg" 2>/dev/null || true
  )"
  [ -n "$found" ] || return 1
  printf '%s\n' "$found"
}

# review_codex_plugin_root <agents.toml> <agent> — echo the resolved plugin
# root, or fail with EXACTLY ONE reason token.
#
# The reason tokens are siblings, never concatenated: `not-installed`,
# `companion-missing`, `unsupported-companion <version>`, `unknown-version`.
# AC5 pins that so the diagnostic stays greppable and reproducible — a message
# carrying two tokens tells an operator nothing about which condition to fix.
#
# The capability check is version + readiness and NEVER help text. 1.0.6's own
# printUsage omits --prompt-file, --cwd and --json even though handleTask
# accepts all three, so a help-text probe fails closed against the single
# install this spec targets. Readiness is review_codex_preflight's job; this
# function resolves and version-checks only, and runs the companion not at all.
review_codex_plugin_root() {
  local toml="${1:-}" agent="${2:-}"
  [ -n "$toml" ] && [ -f "$toml" ] || {
    review_error "review_codex_plugin_root: registry not found: '${toml:-}'"
    return 2
  }
  [ -n "$agent" ] || {
    review_error "review_codex_plugin_root: agent required"
    return 2
  }

  local keys
  keys="$(review_agent_keys "$toml" "$agent")" || return 2
  [ -n "$keys" ] || {
    review_error "review_codex_plugin_root: no agent named \"$agent\" in $toml"
    return 2
  }

  local root explicit=0
  if printf '%s\n' "$keys" | grep -qx 'plugin_root'; then
    root="$(review_agent_field "$toml" "$agent" plugin_root)"
    explicit=1
  fi

  if [ "$explicit" -eq 0 ] || [ -z "${root:-}" ]; then
    root="$(_review_codex_root_from_registry)" || {
      review_error "review_codex_plugin_root: agent \"$agent\": codex-plugin-unavailable: not-installed"
      return 1
    }
  fi

  # Companion presence is checked BEFORE the version. A root with no companion
  # is not a Codex install at all, so naming its version would be reporting on
  # something that is not there — and AC5 allows exactly one token.
  [ -f "$root/scripts/codex-companion.mjs" ] || {
    review_error "review_codex_plugin_root: agent \"$agent\": codex-plugin-unavailable: companion-missing"
    return 1
  }

  local version
  version="$(_review_codex_version_for_root "$root")"
  _review_version_parseable "${version:-}" || {
    review_error "review_codex_plugin_root: agent \"$agent\": codex-plugin-unavailable: unknown-version"
    return 1
  }
  _review_version_ge "$version" "$REVIEW_CODEX_MIN_VERSION" || {
    review_error "review_codex_plugin_root: agent \"$agent\": codex-plugin-unavailable: unsupported-companion $version"
    return 1
  }

  printf '%s\n' "$root"
}

# ---------------------------------------------------------------------------
# AC5b / AC5c — the availability and auth preflight, memoized per root.
# ---------------------------------------------------------------------------

# The memo is a TSV file, one line per canonical root:
#   <canonical-root><TAB><rc><TAB><reason>
#
# A file rather than an associative array because those need bash 4+ or zsh,
# and macOS's /bin/bash is 3.2. Created lazily inside the function, never at
# source time — sourcing this lib must stay free of side effects.
REVIEW_CODEX_PREFLIGHT_MEMO="${REVIEW_CODEX_PREFLIGHT_MEMO:-}"

# _review_codex_memo_init — ensure the memo file exists. Called as a PLAIN
# command, never inside `$(...)`: a subshell assignment would be discarded and
# every lookup would miss, silently turning the memo off.
_review_codex_memo_init() {
  if [ -n "${REVIEW_CODEX_PREFLIGHT_MEMO:-}" ] && [ -f "$REVIEW_CODEX_PREFLIGHT_MEMO" ]; then
    return 0
  fi
  REVIEW_CODEX_PREFLIGHT_MEMO="$(mktemp)"
  # EXPORTED so that a dispatcher which fans agents out through subshells still
  # shares one memo. Without this, a per-agent subshell would start with the
  # variable unset, mktemp a private memo, and preflight every agent
  # separately — the per-round behaviour AC5c exists to forbid, reappearing as
  # an invisible performance bug rather than a wrong answer.
  export REVIEW_CODEX_PREFLIGHT_MEMO
}

# review_codex_preflight <plugin-root> — run the companion's own availability
# and auth check, and return zero only when it reports ready.
#
# `setup --json` is the STRUCTURED missing/unauthenticated signal: its `ready`
# field is node && codex && auth (codex-companion.mjs:203 in 1.0.6). Every
# failure here is `codex-plugin-unavailable: not-ready <reason>` — NEVER
# `codex-output-unparseable`, which belongs to task output alone (AC5b). An
# availability problem reported as a parse problem sends an operator to inspect
# a response that was never produced.
#
# Memoized per CANONICAL root, not per round (AC5c). plugin_root is a per-agent
# field, so two codex-plugin agents in one round may resolve to different
# installations, versions or auth states; preflighting "once per round" would
# establish readiness for one and assume it for the other. Canonicalizing first
# means one installation reached by two names preflights once, while two real
# installations preflight once each. Failures are memoized too — re-running
# setup per agent against a broken install is exactly when it is slowest.
#
# The companion is invoked by the path as GIVEN, while the memo key is the
# canonical form: the operator sees the path they configured in the registry,
# and the cache still collapses aliases of one install.
#
# NOTE: this invocation is not yet wrapped in review_with_deadline. The
# dispatcher assembled in steps 25-27 owns the deadline value, so the bound is
# applied there rather than hard-coding a second one here.
review_codex_preflight() {
  local root="${1:-}"
  [ -n "$root" ] || {
    review_error "review_codex_preflight: plugin root required"
    return 2
  }

  local canon
  canon="$(_review_canonical_dir "$root")"

  _review_codex_memo_init

  local hit memo_rc memo_reason
  hit="$(awk -F'\t' -v k="$canon" '$1 == k { print; exit }' \
    "$REVIEW_CODEX_PREFLIGHT_MEMO" 2>/dev/null || true)"
  if [ -n "$hit" ]; then
    memo_rc="$(printf '%s\n' "$hit" | cut -f2)"
    memo_reason="$(printf '%s\n' "$hit" | cut -f3-)"
    [ "$memo_rc" = "0" ] && return 0
    review_error "review_codex_preflight: codex-plugin-unavailable: not-ready $memo_reason"
    return 1
  fi

  local out ready reason
  out="$(node "$root/scripts/codex-companion.mjs" setup --json 2>/dev/null || true)"
  # NOT `.ready // empty`: jq's `//` yields the alternative when the left side
  # is false OR null, so a companion honestly reporting `"ready": false` would
  # be indistinguishable from one that emitted no JSON at all — and would be
  # misreported as unparseable-setup-output instead of its real reason.
  ready="$(printf '%s\n' "$out" \
    | jq -r 'if has("ready") then (.ready | tostring) else "" end' 2>/dev/null || true)"

  if [ "$ready" = "true" ]; then
    printf '%s\t0\t\n' "$canon" >> "$REVIEW_CODEX_PREFLIGHT_MEMO"
    return 0
  fi

  if [ -z "$ready" ]; then
    # Not JSON, or no `ready` field at all. Still an availability failure: the
    # companion could not tell us it was ready, so it is not ready.
    reason="unparseable-setup-output"
  else
    # Prefer the companion's own nextSteps text — it is the only thing that
    # distinguishes "no node" from "not logged in". gsub keeps tabs and
    # newlines out of the TSV memo.
    reason="$(printf '%s\n' "$out" \
      | jq -r '(.nextSteps // []) | if length > 0 then (.[0] | gsub("[\t\n]"; " ")) else empty end' \
        2>/dev/null || true)"
    if [ -z "$reason" ]; then
      reason="$(printf '%s\n' "$out" | jq -r '
        [ (if (.node.available  // true) then empty else "node"  end),
          (if (.codex.available // true) then empty else "codex" end),
          (if (.auth.loggedIn   // true) then empty else "auth"  end) ]
        | if length == 0 then "setup reported not ready" else "missing: " + join(",") end
      ' 2>/dev/null || true)"
    fi
    [ -n "$reason" ] || reason="setup reported not ready"
  fi

  printf '%s\t1\t%s\n' "$canon" "$reason" >> "$REVIEW_CODEX_PREFLIGHT_MEMO"
  review_error "review_codex_preflight: codex-plugin-unavailable: not-ready $reason"
  return 1
}

# ---------------------------------------------------------------------------
# AC6 / AC7 — the background launch argv.
# ---------------------------------------------------------------------------

# review_codex_task_argv <agents.toml> <agent> <root> <payload> <cwd> —
# emit the companion launch argv, NUL-separated, one word per record.
#
# NUL-separated rather than a single string because the payload path and the
# repo root are arbitrary filesystem paths: a space in either would be split
# into two arguments by any whitespace-joined form, and the round artifact
# would be handed over under a truncated name. Callers dispatch with
# `xargs -0`, which preserves the word boundaries this emits.
#
# The emitted argv is `task --background --fresh --json --prompt-file <payload>
# --cwd <cwd>`, plus `--model`/`--effort` only when the registry sets them.
#
# Three flags are NEVER emitted, and each is a correctness requirement rather
# than a preference:
#   --write        a reviewer is read-only; a review that edited the tree is a
#                  defect, never a verdict (AC: touchedFiles wins over all).
#   --resume
#   --resume-last  a reviewer must not inherit a prior thread's context, or the
#                  round's payload stops being what was reviewed. `--fresh` is
#                  the positive counterpart and is always emitted.
#
# Background, not foreground: a foreground task cannot be cancelled, and the
# Codex broker is spawned detached and unref'd, so only `companion cancel
# <job-id>` reaches the running turn.
#
# The payload is passed BY PATH and is the round's own artifact — never a copy.
# AC7 pins that with an inode comparison, because a copy would decouple what
# the budget measured from what the reviewer read.
review_codex_task_argv() {
  local toml="${1:-}" agent="${2:-}" root="${3:-}" payload="${4:-}" cwd="${5:-}"

  [ -n "$toml" ] && [ -f "$toml" ] || {
    review_error "review_codex_task_argv: registry not found: '${toml:-}'"
    return 2
  }
  [ -n "$agent" ] || { review_error "review_codex_task_argv: agent required"; return 2; }
  [ -n "$root" ] || { review_error "review_codex_task_argv: plugin root required"; return 2; }
  [ -n "$cwd" ] || { review_error "review_codex_task_argv: cwd required"; return 2; }
  [ -n "$payload" ] && [ -f "$payload" ] || {
    review_error "review_codex_task_argv: payload artifact not found: '${payload:-}'"
    return 2
  }

  local keys
  keys="$(review_agent_keys "$toml" "$agent")" || return 2
  [ -n "$keys" ] || {
    review_error "review_codex_task_argv: no agent named \"$agent\" in $toml"
    return 2
  }

  local model="" effort=""
  if printf '%s\n' "$keys" | grep -qx 'model'; then
    model="$(review_agent_field "$toml" "$agent" model)"
  fi
  if printf '%s\n' "$keys" | grep -qx 'effort'; then
    effort="$(review_agent_field "$toml" "$agent" effort)"
  fi

  # Built in a local array-free way: the positional list is the only portable
  # ordered collection across bash 3.2 and zsh, so the words are emitted
  # directly instead of being accumulated.
  printf '%s\0' \
    node \
    "$root/scripts/codex-companion.mjs" \
    task \
    --background \
    --fresh \
    --json \
    --prompt-file "$payload" \
    --cwd "$cwd"

  [ -z "$model" ] || printf '%s\0' --model "$model"
  [ -z "$effort" ] || printf '%s\0' --effort "$effort"
}


# ---------------------------------------------------------------------------
# AC9 / AC9a — classifying the companion's task output.
# ---------------------------------------------------------------------------

# review_parse_codex_task_output <stdout-file> <exit-status> — classify one
# completed companion invocation. On success the reviewer's response goes to
# stdout and the return is zero; otherwise a single `failed <token>` line goes
# to stdout and the return is non-zero.
#
# BOTH arguments are required. The classification is total over (exit status x
# JSON validity x field contents), so it cannot be computed without the status;
# defaulting it would silently turn every transport failure into a verdict.
#
# The fields are read from the NESTED background shape, `.storedJob.result.*`.
# That is what `result <job-id> --json` emits (handleResult, 1.0.6
# codex-companion.mjs:910-925; tracked-jobs.mjs:166 stores the payload one
# level down, and the companion's own renderer reads
# storedJob.result.rawOutput at render.mjs:402). The FLAT shape is the
# FOREGROUND payload: it is rejected rather than accepted as a fallback,
# because a caller that forgot --background would otherwise silently produce a
# verdict, and one tested path beats two of which only one is exercised.
#
# Two fields are named `status` at different depths and this function must read
# the inner one:
#   .storedJob.status        string: queued|running|completed|failed|cancelled
#   .storedJob.result.status NUMBER: 0 success, 1 otherwise
# The outer one's success value really is the string "completed", so reading
# the right value at the wrong depth looks plausible and is wrong. The inner
# status must be numerically 0 AND of JSON type number, so a string "0" or
# "completed" cannot pass.
#
# Precedence, in order, because the rows overlap:
#   1. non-empty touchedFiles -> codex-wrote-files. Wins over EVERY other row:
#      a read-only reviewer that wrote is a defect, never a verdict, and the
#      verdict is withheld rather than reported alongside it.
#   2. non-zero exit -> codex-task-error, whatever the JSON says. A companion
#      that printed a well-formed result and THEN exited non-zero had a
#      transport failure, and a transport failure never becomes a verdict.
#      Filing this as codex-output-unparseable would be wrong too: the output
#      parsed perfectly well.
#   3. anything else short of success -> codex-output-unparseable.
review_parse_codex_task_output() {
  [ "$#" -eq 2 ] || {
    review_error "review_parse_codex_task_output: both <stdout-file> and <exit status> are required (got $#)"
    return 2
  }
  local out_file="$1" cmd_status="$2"

  [ -n "$out_file" ] && [ -f "$out_file" ] || {
    review_error "review_parse_codex_task_output: companion stdout not found: '${out_file:-}'"
    return 2
  }
  case "$cmd_status" in
    '' | *[!0-9]*)
      review_error "review_parse_codex_task_output: exit status must be a non-negative integer, got '$cmd_status'"
      return 2
      ;;
  esac

  # Empty when the file is not JSON, or carries no nested result object — which
  # is also how the flat foreground shape lands here.
  local result
  result="$(jq -c '.storedJob.result // empty' "$out_file" 2>/dev/null || true)"

  if [ -n "$result" ]; then
    local touched
    touched="$(printf '%s\n' "$result" \
      | jq -r '(.touchedFiles // []) | length' 2>/dev/null || true)"
    case "${touched:-0}" in
      '' | 0) : ;;
      *)
        printf 'failed codex-wrote-files\n'
        return 1
        ;;
    esac
  fi

  if [ "$cmd_status" -ne 0 ]; then
    printf 'failed codex-task-error\n'
    return 1
  fi

  [ -n "$result" ] || {
    printf 'failed codex-output-unparseable\n'
    return 1
  }

  local result_status raw
  result_status="$(printf '%s\n' "$result" \
    | jq -r 'if (.status | type) == "number" then (.status | tostring) else "" end' \
      2>/dev/null || true)"
  [ "$result_status" = "0" ] || {
    printf 'failed codex-output-unparseable\n'
    return 1
  }

  raw="$(printf '%s\n' "$result" \
    | jq -r 'if (.rawOutput | type) == "string" then .rawOutput else "" end' \
      2>/dev/null || true)"
  [ -n "$raw" ] || {
    printf 'failed codex-output-unparseable\n'
    return 1
  }

  printf '%s\n' "$raw"
}

# ---------------------------------------------------------------------------
# AC6a / AC6b — the job lifecycle.
#
# Every companion invocation below runs under review_with_deadline, which
# bounds ONE invocation. The JOB deadline is the poll's own budget, and it ends
# in `cancel`, never in a signal: the Codex broker is spawned detached and
# unref'd, so killing the local caller proves only that the caller stopped.
# ---------------------------------------------------------------------------

# Fixed by AC6a. Overridable so tests need not spend the real interval, while
# the default stays pinned by a test that greps this exact line.
REVIEW_CODEX_POLL_INTERVAL_S="${REVIEW_CODEX_POLL_INTERVAL_S:-5}"

# How long any single companion invocation may take. Separate from the job
# budget: a wedged `status` call must not consume the whole review_timeout_s.
REVIEW_CODEX_CALL_DEADLINE_S="${REVIEW_CODEX_CALL_DEADLINE_S:-60}"

# review_codex_job_id <launch-output-file> — the job id from `task
# --background --json`.
#
# Reads `.jobId` and nothing else. The launch payload also carries a `status`
# field whose value is the STRING "queued" — neither terminal nor an id — so a
# helper reaching for the wrong key would find something plausible.
review_codex_job_id() {
  local launch="${1:-}"
  [ -n "$launch" ] && [ -f "$launch" ] || {
    review_error "review_codex_job_id: launch output not found: '${launch:-}'"
    return 2
  }
  local job_id
  job_id="$(jq -r '.jobId // empty' "$launch" 2>/dev/null || true)"
  [ -n "$job_id" ] || {
    review_error "review_codex_job_id: no job id in the launch output: $launch"
    return 1
  }
  printf '%s\n' "$job_id"
}

# review_codex_job_status <root> <job-id> — the job's status STRING.
# Terminal: completed | failed | cancelled. Active: queued | running
# (job-control.mjs:262 and codex-companion.mjs:291 in 1.0.6).
review_codex_job_status() {
  local root="${1:-}" job_id="${2:-}"
  [ -n "$root" ] && [ -n "$job_id" ] || {
    review_error "review_codex_job_status: root and job id required"
    return 2
  }
  local out
  out="$(review_with_deadline "$REVIEW_CODEX_CALL_DEADLINE_S" \
    node "$root/scripts/codex-companion.mjs" status "$job_id" --json 2>/dev/null || true)"
  local st
  st="$(printf '%s\n' "$out" | jq -r '.job.status // empty' 2>/dev/null || true)"
  [ -n "$st" ] || {
    review_error "review_codex_job_status: could not read a status for job $job_id"
    return 1
  }
  printf '%s\n' "$st"
}

# _review_codex_job_terminal <status> — true for the companion's own terminal
# set, taken from the companion rather than guessed.
_review_codex_job_terminal() {
  case "${1:-}" in
    completed | failed | cancelled) return 0 ;;
    *) return 1 ;;
  esac
}

# review_codex_job_result <root> <job-id> <out-file> — capture `result <job-id>
# --json` for review_parse_codex_task_output, and return the companion's own
# exit status, which that parser needs as its second argument.
review_codex_job_result() {
  local root="${1:-}" job_id="${2:-}" out_file="${3:-}"
  [ -n "$root" ] && [ -n "$job_id" ] && [ -n "$out_file" ] || {
    review_error "review_codex_job_result: root, job id and output file required"
    return 2
  }
  local rc=0
  review_with_deadline "$REVIEW_CODEX_CALL_DEADLINE_S" \
    node "$root/scripts/codex-companion.mjs" result "$job_id" --json \
    > "$out_file" 2>/dev/null || rc=$?
  return "$rc"
}

# _review_codex_poll <root> <job-id> <timeout-s> — poll until the job reports
# terminal, echoing that status; return 124 when the budget runs out.
#
# The status is checked BEFORE the first sleep, so a job that finished during
# launch is not charged a whole interval. The final sleep is clamped to the
# remaining budget, so a 5 s interval cannot overshoot a 2 s deadline.
_review_codex_poll() {
  local root="${1:-}" job_id="${2:-}" timeout_s="${3:-}"
  [ -n "$root" ] && [ -n "$job_id" ] && [ -n "$timeout_s" ] || {
    review_error "_review_codex_poll: root, job id and timeout required"
    return 2
  }

  local waited=0 st nap
  while :; do
    st="$(review_codex_job_status "$root" "$job_id" 2>/dev/null || true)"
    if [ -n "$st" ] && _review_codex_job_terminal "$st"; then
      printf '%s\n' "$st"
      return 0
    fi
    [ "$waited" -lt "$timeout_s" ] || return 124

    nap="$REVIEW_CODEX_POLL_INTERVAL_S"
    [ "$((waited + nap))" -le "$timeout_s" ] || nap=$((timeout_s - waited))
    [ "$nap" -gt 0 ] || return 124
    sleep "$nap"
    waited=$((waited + nap))
  done
}

# review_codex_job_cancel <root> <job-id> — cancel the job and CONFIRM it
# stopped. Zero only on confirmed cancellation.
#
# One cancel, then exactly one confirming status. AC6b: a cancel that reports
# success while the following status still shows the job active is
# `failed codex-cancel-unconfirmed <job-id>`, NOT a timeout — a reviewer that
# may still be running must never be recorded as merely having timed out. The
# job id is named so an operator can finish it off by hand.
#
# No signals anywhere in this path. `cancel` is the only route to
# interruptAppServerTurn; a process-group kill would stop this caller and leave
# the turn running, producing exactly the false timeout above.
review_codex_job_cancel() {
  local root="${1:-}" job_id="${2:-}"
  [ -n "$root" ] && [ -n "$job_id" ] || {
    review_error "review_codex_job_cancel: root and job id required"
    return 2
  }

  review_with_deadline "$REVIEW_CODEX_CALL_DEADLINE_S" \
    node "$root/scripts/codex-companion.mjs" cancel "$job_id" --json \
    >/dev/null 2>&1 || true

  local st
  st="$(review_codex_job_status "$root" "$job_id" 2>/dev/null || true)"
  if [ -n "$st" ] && _review_codex_job_terminal "$st"; then
    return 0
  fi

  printf 'failed codex-cancel-unconfirmed %s\n' "$job_id"
  return 1
}

# ---------------------------------------------------------------------------
# AC11 / AC13 — the mode router and the unavailable diagnostic.
# ---------------------------------------------------------------------------

# review_codex_unavailable_message <reason> — the operator-facing guidance for
# a codex-plugin agent that could not be reached.
#
# Names the remedy, not just the diagnosis: every reason here is fixed by
# installing or authenticating the plugin, and `/codex:setup` is the command
# that does both. Deliberately NOT a suggestion to fall back to the codex CLI —
# that would review with a different tool under the same agent name.
review_codex_unavailable_message() {
  local reason="${1:-unknown}"
  printf 'codex-plugin unavailable (%s). Run /codex:setup to install or authenticate the Codex plugin, or set mode = "cli" for this agent.\n' \
    "$reason"
}

# _review_codex_dispatch <agents.toml> <agent> <artifact> <cwd> <timeout-s> —
# the whole codex-plugin path: resolve, preflight, launch, poll, collect, parse.
#
# On success the reviewer's response goes to stdout. Every failure emits one
# `failed <token>` line (or `timeout`) and returns non-zero, so the caller
# records an outcome rather than a verdict.
_review_codex_dispatch() {
  local toml="$1" agent="$2" art="$3" cwd="$4" timeout_s="$5"

  # Resolution and preflight failures are reported as the round outcome. Their
  # own diagnostics already went to stderr with the exact reason token.
  local root reason
  if ! root="$(review_codex_plugin_root "$toml" "$agent" 2>"$REVIEW_CODEX_LAST_ERR")"; then
    reason="$(_review_codex_reason_from "$REVIEW_CODEX_LAST_ERR")"
    printf 'failed codex-plugin-unavailable %s\n' "$reason"
    review_error "$(review_codex_unavailable_message "$reason")"
    return 1
  fi

  if ! review_codex_preflight "$root" 2>"$REVIEW_CODEX_LAST_ERR"; then
    reason="$(_review_codex_reason_from "$REVIEW_CODEX_LAST_ERR")"
    printf 'failed codex-plugin-unavailable %s\n' "$reason"
    review_error "$(review_codex_unavailable_message "$reason")"
    return 1
  fi

  local argv_file launch_file result_file
  argv_file="$(mktemp)"
  launch_file="$(mktemp)"
  result_file="$(mktemp)"

  review_codex_task_argv "$toml" "$agent" "$root" "$art" "$cwd" > "$argv_file" || {
    rm -f "$argv_file" "$launch_file" "$result_file"
    printf 'failed codex-task-error\n'
    return 1
  }

  # `xargs -0 env` executes the argv's own first word. A bare `xargs -0` would
  # default to `echo` and launch nothing at all.
  local launch_rc=0
  review_with_deadline "$REVIEW_CODEX_CALL_DEADLINE_S" \
    xargs -0 env < "$argv_file" > "$launch_file" 2>/dev/null || launch_rc=$?

  local job_id
  if [ "$launch_rc" -ne 0 ] || ! job_id="$(review_codex_job_id "$launch_file" 2>/dev/null)"; then
    rm -f "$argv_file" "$launch_file" "$result_file"
    printf 'failed codex-task-error\n'
    return 1
  fi

  local poll_rc=0
  _review_codex_poll "$root" "$job_id" "$timeout_s" >/dev/null || poll_rc=$?
  if [ "$poll_rc" -eq 124 ]; then
    rm -f "$argv_file" "$launch_file" "$result_file"
    # The job outlived its budget. Cancel, and CONFIRM — an unconfirmed cancel
    # is never reported as a plain timeout, because the reviewer may still be
    # running.
    local cancel_out cancel_rc=0
    cancel_out="$(review_codex_job_cancel "$root" "$job_id")" || cancel_rc=$?
    if [ "$cancel_rc" -ne 0 ]; then
      printf '%s\n' "$cancel_out"
      return 1
    fi
    printf 'timeout\n'
    return 1
  fi

  local result_rc=0
  review_codex_job_result "$root" "$job_id" "$result_file" || result_rc=$?

  local parsed parse_rc=0
  parsed="$(review_parse_codex_task_output "$result_file" "$result_rc")" || parse_rc=$?
  rm -f "$argv_file" "$launch_file" "$result_file"
  printf '%s\n' "$parsed"
  return "$parse_rc"
}

# REVIEW_CODEX_LAST_ERR — scratch file for a helper's stderr, so the reason
# token can be lifted out of it and reported as the round outcome.
REVIEW_CODEX_LAST_ERR="${REVIEW_CODEX_LAST_ERR:-}"

# _review_codex_reason_from <stderr-file> — the reason token a helper named.
# Exactly one token per message (AC5), so the first match is the reason.
_review_codex_reason_from() {
  local f="${1:-}" line
  [ -n "$f" ] && [ -f "$f" ] || { printf 'unknown\n'; return 0; }
  line="$(grep -oE 'not-installed|companion-missing|unsupported-companion [^ ]+|unknown-version|not-ready .*' "$f" 2>/dev/null | head -1 || true)"
  [ -n "$line" ] || line='unknown'
  printf '%s\n' "$line"
}
