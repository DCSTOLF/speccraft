#!/usr/bin/env bash
# commands/spec/review-round.lib.sh — the persistent round directory and the
# post-round tree check (spec 0054, Phases E-F).
#
# Sourced by commands/spec/review.lib.sh. Three concerns live here, in order:
#
#   the round dir  — created, leased, published atomically, reclaimed by a
#                    lease-based sweep that NEVER deletes on age;
#   quarantine     — the override that retains a round dir when a reviewer may
#                    still be running, outranking both cleanup and the sweep;
#   the tree check — a content-aware snapshot that tells whether a reviewer
#                    wrote outside its round dir.
#
# Two invariants hold across the file and are each pinned by a test:
#
#   Nothing is deleted on age. A round that has legitimately run for an hour is
#   indistinguishable by mtime from one abandoned an hour ago, so every
#   deletion decision comes from a lease or from an expiry encoded in a
#   `.building-` name — both absolute timestamps chosen by the creator.
#
#   Detection is by CONTENT, not by path or porcelain text. Each cheaper
#   alternative has a documented hole and a test row that fails when it is
#   reintroduced.
#
# NO SIDE EFFECTS AT SOURCE TIME: sourcing defines functions and nothing more.
#
# Cross-shell self-location and zsh-reserved-name avoidance follow the spec-0029
# and spec-0030 conventions; no bare `status` locals.

# ---------------------------------------------------------------------------
# Spec 0054 Phase E — the persistent round directory (ACs 14, 14a, 14b, 14c, 14e).
#
# A round dir holds the composed payload and the digest sidecar for the life of
# a round. It must outlive the creating shell (reviewers run concurrently), be
# invisible to git in an ALREADY-initialized repo with no migration, and be
# reclaimable after a crash without ever deleting a round still running.
#
# Reclamation is LEASE-based, never age-based: an age rule cannot tell a round
# that has run for an hour from one abandoned an hour ago, and rounds here
# legitimately run long.
# ---------------------------------------------------------------------------

# Grace added to every lease beyond the round's own timeout, so a round that
# uses its full budget and then finalizes is never reclaimed from under itself.
REVIEW_ROUND_LEASE_GRACE_S="${REVIEW_ROUND_LEASE_GRACE_S:-300}"

# review_round_parent — the directory holding every round dir.
review_round_parent() {
  local root
  root="$(speccraft-state find-root 2>/dev/null || pwd)"
  printf '%s\n' "$root/.speccraft/.review-rounds"
}

# _review_round_write_gitignore <parent> — write `*` into <parent>/.gitignore,
# idempotently, via a same-dir temp plus rename.
#
# AC14a, and the reason there is no migration: the ignore rule lives INSIDE the
# round parent, so a repo initialized before this spec ignores round dirs
# without its own .gitignore being touched at all. (`/speccraft:init` only ever
# appended `.speccraft/state.json` to the host's file.) A `*` here also ignores
# this .gitignore itself, which is correct — it is machine state, not project
# intent — and git still reads an ignored .gitignore.
#
# Same-dir temp + rename so a reader never sees a half-written rule: an empty
# or truncated .gitignore would silently expose round payloads to `git add -A`.
_review_round_write_gitignore() {
  local parent="$1" tmp
  if [ -f "$parent/.gitignore" ] && [ "$(cat "$parent/.gitignore")" = '*' ]; then
    return 0
  fi
  tmp="$parent/.gitignore.tmp.$$"
  printf '*\n' > "$tmp"
  mv -f "$tmp" "$parent/.gitignore"
}

# review_round_lease_write <dir> <absolute-expiry-unix> — the lease, one line.
#
# Written ONCE per round and never renewed (AC14d): a renewable lease cannot
# bound anything, because an abandoned round holding a renewer would keep
# extending itself.
review_round_lease_write() {
  local dir="${1:-}" expiry="${2:-}"
  [ -n "$dir" ] && [ -d "$dir" ] || {
    review_error "review_round_lease_write: round dir not found: '${dir:-}'"
    return 2
  }
  case "$expiry" in
    '' | *[!0-9]*)
      review_error "review_round_lease_write: expiry must be an absolute unix timestamp, got '$expiry'"
      return 2
      ;;
  esac
  printf 'expires_at %s\n' "$expiry" > "$dir/lease"
}

# review_round_lease_expired <dir> — 0 expired, 1 active, 2 missing/unparseable.
#
# Three outcomes rather than two because the sweep treats "expired" and "cannot
# be read" the same way (both reclaimable) while a CALLER may want to tell them
# apart, and because collapsing them would make an unparseable lease read as
# active — the failure mode that leaks round dirs forever.
review_round_lease_expired() {
  local dir="${1:-}" expiry now
  [ -n "$dir" ] && [ -f "$dir/lease" ] || return 2
  expiry="$(awk '$1 == "expires_at" { print $2; exit }' "$dir/lease" 2>/dev/null || true)"
  case "$expiry" in
    '' | *[!0-9]*) return 2 ;;
  esac
  now="$(date +%s)"
  [ "$now" -ge "$expiry" ]
}

# review_round_dir_create <kind> <id> <timeout-s> — create a round dir and echo
# its path. Publishes atomically: the dir appears under its final name only
# once it already holds its lease.
#
# The sequence matters (AC14c). The expiry is fixed at `mkdir` time, BEFORE any
# fallible setup, and encoded in the temporary `.building-<expiry>-<rand>` name.
# So a creator killed mid-build leaves a directory that the sweep can reclaim by
# reading its own name — no age rule, no mtime, no guessing. The lease is then
# written INSIDE that temp dir and the whole thing renamed, so no round ever
# exists under its final name without a lease. Without that ordering, the
# "missing lease ⇒ reclaim" rule would race every creation.
#
# The chosen temp name is RECORDED, in two places, because a successful create
# renames it away and it cannot be observed by listing the directory
# afterwards. AC14e permits interleaving or instrumentation; this is the latter.
#
#   <round-dir>/build-name  — the durable record, and the one that works.
#   REVIEW_ROUND_BUILD_NAME — convenience for a direct caller only.
#
# The file is not redundant. Every real caller takes the round path by command
# substitution (`dir="$(review_round_dir_create ...)"`), which runs this
# function in a SUBSHELL, so the variable assignment is discarded before the
# caller can read it — a variable alone is instrumentation that no caller and
# no test can actually see.
review_round_dir_create() {
  local kind="${1:-}" round_id="${2:-}" timeout_s="${3:-}"
  [ -n "$kind" ] && [ -n "$round_id" ] || {
    review_error "review_round_dir_create: kind and id required"
    return 2
  }
  case "$timeout_s" in
    '' | *[!0-9]*)
      review_error "review_round_dir_create: timeout-s must be a non-negative integer, got '${timeout_s:-}'"
      return 2
      ;;
  esac

  local parent
  parent="$(review_round_parent)"
  mkdir -p "$parent" || return 1
  chmod 0700 "$parent" 2>/dev/null || true
  _review_round_write_gitignore "$parent" || return 1

  # `date +%s` plus shell arithmetic, never `date -d`: BSD date has no -d, so
  # the GNU spelling would pass CI and fail on macOS.
  local now expiry rand build final
  now="$(date +%s)"
  expiry=$((now + timeout_s + REVIEW_ROUND_LEASE_GRACE_S))

  # Uniqueness comes from mktemp's atomic creation, not from `$$-$RANDOM`.
  #
  # zsh hands a command-substitution subshell the SAME $RANDOM as its parent
  # unless the parent touches RANDOM in between, and EVERY real caller takes
  # the path by `dir="$(review_round_dir_create …)"` — so `$$` was the parent's
  # pid for both calls and `$RANDOM` was identical too. Two rounds from one zsh
  # shell got the same final name; `mv` then moved the second builder INSIDE
  # the first round's directory, returned 0, and handed both callers the same
  # path, so one round's cleanup deleted the other's payload. Found by
  # cross-model review, round 6.
  #
  # The expiry stays encoded in the temp name, which is the property AC14c
  # depends on: a creator killed mid-build leaves a directory the sweep can
  # reclaim by reading its own name.
  build="$(mktemp -d "$parent/.building-$expiry-XXXXXX")" || return 1
  chmod 0700 "$build" 2>/dev/null || true
  REVIEW_ROUND_BUILD_NAME="${build##*/}"
  rand="${REVIEW_ROUND_BUILD_NAME##*-}"

  review_round_lease_write "$build" "$expiry" || {
    rm -rf "$build"
    return 1
  }

  # Written BEFORE the rename, so it is inside the dir the instant it is
  # published — there is no window in which a round exists without its record.
  printf '%s\n' "$REVIEW_ROUND_BUILD_NAME" > "$build/build-name" || {
    rm -rf "$build"
    return 1
  }

  # `<kind>-<id>-<unix-ts>-<rand>`, the shape the contract names.
  final="$parent/$kind-$round_id-$now-$rand"
  # Checked before the rename, because `mv src existing-dir/` MOVES src INSIDE
  # it and reports success — the exact way two rounds came to share one
  # directory. mktemp's suffix plus the timestamp makes a genuine collision
  # vanishingly unlikely; this refuses the deterministic case loudly rather
  # than silently nesting.
  [ ! -e "$final" ] || {
    review_error "review_round_dir_create: '$final' already exists; refusing to publish a second round inside an existing round's directory"
    rm -rf "$build"
    return 1
  }
  mv "$build" "$final" || {
    rm -rf "$build"
    return 1
  }
  chmod 0700 "$final" 2>/dev/null || true
  printf '%s\n' "$final"
}

# review_round_cleanup <dir> — remove one round dir, refusing anything that is
# not strictly inside the round parent. Non-zero refusals delete NOTHING.
#
# The refusals are not defensive padding: this function runs `rm -rf` on a path
# assembled from a repo root, so `/`, an escaping `..`, and a symlink are each
# one bug away from deleting a user's work.
#
# BOTH sides are resolved before comparing (spec 0050 defect A). On macOS
# TMPDIR is itself a symlink, so the repo root resolves to a different prefix
# than the path a caller holds; comparing one resolved side against one
# unresolved side refuses every legitimate round dir instead.
#
# A symlink is refused rather than followed: deleting through one would remove
# a target outside the parent while every path check still passed.
review_round_cleanup() {
  local dir="${1:-}"
  [ -n "$dir" ] || {
    review_error "review_round_cleanup: path required"
    return 2
  }
  [ -e "$dir" ] || {
    review_error "review_round_cleanup: not found: '$dir'"
    return 2
  }
  [ ! -L "$dir" ] || {
    review_error "review_round_cleanup: refusing a symlink: '$dir'"
    return 1
  }
  [ -d "$dir" ] || {
    review_error "review_round_cleanup: not a directory: '$dir'"
    return 1
  }

  local parent canon_parent canon_dir
  parent="$(review_round_parent)"
  canon_parent="$(_review_canonical_dir "$parent")"
  canon_dir="$(_review_canonical_dir "$dir")"

  [ -n "$canon_parent" ] && [ -n "$canon_dir" ] || {
    review_error "review_round_cleanup: could not resolve '$dir' against the round parent"
    return 1
  }

  # STRICTLY inside: equal is refused too, since wiping the parent would take
  # every concurrent round with it.
  case "$canon_dir" in
    "$canon_parent"/?*) : ;;
    *)
      review_error "review_round_cleanup: refusing '$dir' — not inside the .review-rounds parent ($canon_parent)"
      return 1
      ;;
  esac

  # Quarantine beats cleanup (AC15a). Checked HERE, immediately before the
  # delete, so there is no path that validates the target and then removes it
  # while a reviewer may still be running.
  if review_round_quarantined "$canon_dir"; then
    # The COUNT, not just the first record. An operator told
    # "quarantined (subagent-stop-failed task_2)" resolves that one and expects
    # the dir to go; with two unresolved reviewers it will not, and the second
    # message would look like the same refusal repeating.
    review_error "review_round_cleanup: refusing '$dir' — $(review_round_quarantine_count "$canon_dir") reviewer(s) quarantined, first ($(_review_quarantine_field "$canon_dir" outcome) $(_review_quarantine_field "$canon_dir" id)); resolve or remove $canon_dir/quarantine first"
    return 1
  fi

  # AC14d — never while a reviewer might still write here. Proof comes from the
  # round's own stamps, not the clock: a reviewer whose deadline passed may
  # still be running, which is why TaskStop and stop-failed exist. Deleting a
  # live reviewer's output path fails SILENTLY — it writes into a removed
  # directory and the round records `subagent-no-output`, blaming the reviewer.
  #
  # SKIPPED when reclaiming (see review_round_reclaim). This gate is for the
  # round's OWN cleanup, while the round is still running and a stamp is still
  # coming. The sweep reclaims rounds that were ABANDONED — the orchestrator
  # died, so no stamp will ever arrive — and for those the expired lease is the
  # proof instead. Round 9 found that applying this gate on both paths broke
  # lease-based reclamation entirely for any round that launched a subagent,
  # and silently: the sweep's `|| true` swallowed the refusal.
  if [ "${REVIEW_ROUND_RECLAIMING:-0}" != 1 ]; then
    local pending_msg
    pending_msg="$(review_round_all_terminal "$canon_dir" 2>&1 >/dev/null)" || {
      # Strip the inner function's own prefix so the message reads as one
      # sentence rather than two stacked diagnostics.
      review_error "review_round_cleanup: refusing '$dir' — ${pending_msg#*: }"
      return 1
    }
  fi

  rm -rf "$canon_dir"
}

# review_round_reclaim <dir> — the SWEEP's deletion entry point.
#
# Identical to review_round_cleanup except that the proven-terminal gate does
# not apply, because the thing being reclaimed is by definition abandoned: its
# lease has expired, and the lease margin (`review_timeout_s + 300 s`) already
# bounds every reviewer's deadline. A subagent in a lease-expired round is
# necessarily past its own deadline, so "no stamp arrived" means the
# orchestrator died rather than that a reviewer is still working.
#
# The QUARANTINE refusal still applies — that is the one state where a reviewer
# may genuinely still be running past the lease, and it is why quarantine
# outranks the lease.
review_round_reclaim() {
  REVIEW_ROUND_RECLAIMING=1 review_round_cleanup "$@"
}

# review_round_sweep — reclaim abandoned round dirs. NO ARGUMENTS.
#
# Taking no argument is the point, not an omission. An age or `--max-age`
# parameter would make "this directory is old" a deletion reason, and a round
# that has legitimately run for an hour is indistinguishable by mtime from one
# abandoned an hour ago. Every decision here comes from a LEASE or from an
# expiry encoded in a `.building-` name, both of which are absolute timestamps
# chosen by the creator. An argument is therefore a usage error rather than
# something ignored: silently accepting one would read, at every call site, as
# though age sweeping were supported.
#
# Two rules:
#   published dirs  — reclaimed when the lease has EXPIRED, or is MISSING or
#                     UNPARSEABLE. The last two are reclaimable because
#                     review_round_dir_create publishes a dir only once it
#                     already holds its lease, so a published round without one
#                     is wreckage, never a round still being built.
#   .building-* dirs — reclaimed once the expiry encoded in the NAME has passed.
#                     Read off the name and never recomputed, so two builders
#                     abandoned with different timeouts are each judged on their
#                     own threshold. A fresh builder's expiry lies in the
#                     future, which is what keeps a concurrent sweep from
#                     racing every creation (AC14c).
#
# Deletion goes through review_round_cleanup, which re-validates that the
# target is strictly inside the round parent — the sweep walks a glob, so it is
# exactly the caller that should not be trusted to have built a safe path.
review_round_sweep() {
  [ "$#" -eq 0 ] || {
    review_error "review_round_sweep: takes no arguments — reclamation is lease-based, never age-based (got: $*)"
    return 2
  }

  local parent now entry name expiry rc
  parent="$(review_round_parent)"
  [ -d "$parent" ] || return 0
  now="$(date +%s)"

  # Published rounds. The glob does not match dotfiles, so `.gitignore` and the
  # `.building-` dirs are both out of this loop by construction.
  for entry in "$parent"/*; do
    [ -d "$entry" ] || continue
    [ ! -L "$entry" ] || continue
    rc=0
    review_round_lease_expired "$entry" || rc=$?
    case "$rc" in
      0 | 2)
        # Quarantined dirs are REPORTED, never deleted, even with an expired
        # lease (AC15a): the lease says the round is over, the quarantine says
        # a reviewer may still be running, and the second outranks the first.
        # One grep-able line per retained dir, so an operator can list them.
        if review_round_quarantined "$entry"; then
          # First ASK, then report. AC15a says a quarantine is reclaimed "once
          # the quarantine file is removed (operator action) **or a later
          # `status` confirms termination** — the same sweep reclaims it". The
          # sweep never probed, so a codex-plugin quarantine whose job had long
          # since finished was reported forever and the round dir leaked until
          # someone deleted it by hand. Found by cross-model review, round 6.
          #
          # The resolver is the only thing that decides: it probes the
          # companion root RECORDED in the quarantine file, refuses a
          # `subagent` quarantine outright (no shell-reachable API reports
          # whether a subagent is alive), and clears the file only on a
          # terminal status. A non-zero return means "still quarantined", which
          # is also what every error path returns — so an unprobeable record is
          # retained and reported rather than reclaimed on a failed probe.
          if review_round_quarantine_resolve "$entry" >/dev/null 2>&1; then
            review_round_reclaim "$entry" >/dev/null 2>&1 || \
              printf '%s: retained after resolve, cleanup refused %s\n' \
                "$entry" "$(_review_iso_now)"
          else
            printf '%s: quarantined %s %s lease-expired %s\n' \
              "$entry" \
              "$(_review_quarantine_field "$entry" outcome)" \
              "$(_review_quarantine_field "$entry" id)" \
              "$(_review_iso_now)"
          fi
        else
          # RECLAIM, not cleanup: the lease has expired, so this round is
          # abandoned and the proven-terminal gate does not apply. And a
          # refusal is REPORTED, never swallowed — round 9 found that a
          # `|| true` here left lease-expired rounds neither deleted nor
          # mentioned, on every sweep, forever.
          review_round_reclaim "$entry" >/dev/null 2>&1 || \
            printf '%s: lease-expired but not reclaimable %s\n' \
              "$entry" "$(_review_iso_now)"
        fi
        ;;
    esac
  done

  # Abandoned builders, judged on their own encoded expiry.
  for entry in "$parent"/.building-*; do
    [ -d "$entry" ] || continue
    [ ! -L "$entry" ] || continue
    name="${entry##*/}"
    # `.building-<expiry>-<rand>`, so the expiry is field 2.
    expiry="$(printf '%s\n' "$name" | awk -F- '{print $2}')"
    case "$expiry" in
      '' | *[!0-9]*)
        # A name we cannot read is left alone rather than guessed at: deleting
        # on an unreadable name would be deleting on no evidence.
        continue
        ;;
    esac
    if [ "$now" -ge "$expiry" ]; then
      review_round_cleanup "$entry" >/dev/null 2>&1 || true
    fi
  done
  return 0
}

# ---------------------------------------------------------------------------
# AC15a / AC15b — quarantine.
#
# Two outcomes leave a reviewer that MIGHT STILL BE RUNNING:
# `codex-cancel-unconfirmed` (cancel reported success, the confirming status
# did not agree) and `subagent-stop-failed`. Deleting the round dir then would
# destroy the only record of what was dispatched while the reviewer is still
# live — and the payload is what an operator needs to finish the job by hand.
#
# So quarantine beats BOTH reclamation paths: review_round_cleanup refuses a
# quarantined dir, and the sweep reports it instead of deleting it even once
# its lease has expired. Those two are mutually exclusive by construction, not
# by call order, which is what AC15a's "no exit path both quarantines and
# deletes" asks for.
# ---------------------------------------------------------------------------

REVIEW_QUARANTINE_OUTCOMES="codex-cancel-unconfirmed subagent-stop-failed"

# _review_iso_now — UTC ISO-8601, second precision. `date -u +…`, never
# `date -d`, which BSD date does not have.
_review_iso_now() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

# review_round_quarantine <dir> <id> <outcome> <mode> [<companion-root>] —
# retain the round dir and record why.
#
# A `codex-plugin` quarantine MUST carry a companion root, and it is recorded
# CANONICALIZED. The probe that later resolves this quarantine runs against
# this recorded path rather than re-resolving: `plugin_root` is per-agent, and
# between rounds the install may be removed or the registry entry dropped, so
# re-resolution can produce a different companion — which would then be asked
# about a job it never ran. Without a root there is nothing to probe, and
# probing an arbitrary install is worse than refusing.
#
# A `subagent` quarantine records NO root, because no shell-reachable API can
# ask whether a subagent is still alive. Only an operator removing the file
# resolves it.
review_round_quarantine() {
  local dir="${1:-}" q_id="${2:-}" outcome="${3:-}" mode="${4:-}" root="${5:-}"

  [ -n "$dir" ] && [ -d "$dir" ] || {
    review_error "review_round_quarantine: round dir not found: '${dir:-}'"
    return 2
  }
  [ -n "$q_id" ] || { review_error "review_round_quarantine: id required"; return 2; }
  contains_word() { case " $1 " in *" $2 "*) return 0 ;; *) return 1 ;; esac; }
  contains_word "$REVIEW_QUARANTINE_OUTCOMES" "$outcome" || {
    review_error "review_round_quarantine: unknown outcome '$outcome' (known: $REVIEW_QUARANTINE_OUTCOMES)"
    return 2
  }

  case "$mode" in
    codex-plugin)
      [ -n "$root" ] || {
        review_error "review_round_quarantine: mode codex-plugin requires a companion root — the resolving probe must go to the install that ran the job, never to a re-resolved one"
        return 2
      }
      root="$(_review_canonical_dir "$root")"
      ;;
    subagent)
      [ -z "$root" ] || {
        review_error "review_round_quarantine: mode subagent takes no companion root (got '$root')"
        return 2
      }
      ;;
    *)
      review_error "review_round_quarantine: mode must be codex-plugin or subagent, got '${mode:-}'"
      return 2
      ;;
  esac

  # IDEMPOTENT: a retried stop must not grow the record, or the count stops
  # meaning anything.
  if [ -f "$dir/quarantine" ] && grep -qxF "id $q_id" "$dir/quarantine"; then
    return 0
  fi

  # Same-dir temp + rename, and the existing records are carried over: a
  # half-written quarantine record would be read as "not quarantined" and the
  # dir reclaimed under a live reviewer.
  #
  # APPENDS rather than replacing. One round can have two reviewers whose stop
  # never confirmed; `mv -f` of a fresh single record meant the second
  # OVERWROTE the first, so the operator lost that agent's handle and
  # resolving the survivor would release the dir while the first reviewer might
  # still be writing to it (round 8). Each reviewer is one block, blank-line
  # separated, and the FIRST block stays first — `_review_quarantine_field` and
  # `review_round_quarantine_resolve` read it, and this spec's earlier tests
  # pin the sweep's report format built from it.
  local tmp="$dir/.quarantine.tmp.$$"
  {
    [ ! -f "$dir/quarantine" ] || { cat -- "$dir/quarantine"; printf '\n'; }
    printf 'id %s\n' "$q_id"
    printf 'outcome %s\n' "$outcome"
    printf 'mode %s\n' "$mode"
    printf 'at %s\n' "$(_review_iso_now)"
    [ -z "$root" ] || printf 'root %s\n' "$root"
  } > "$tmp"
  mv -f "$tmp" "$dir/quarantine"
}

# review_round_quarantined <dir> — zero when the dir is quarantined.
review_round_quarantined() {
  local dir="${1:-}"
  [ -n "$dir" ] && [ -f "$dir/quarantine" ]
}

# _review_quarantine_field <dir> <key> — one recorded value.
_review_quarantine_field() {
  [ -f "$1/quarantine" ] || return 1
  awk -v k="$2" '$1 == k { $1 = ""; sub(/^[ \t]+/, ""); print; exit }' "$1/quarantine"
}

# review_round_quarantine_resolve <dir> — ask the recorded companion whether
# the quarantined job is still running; clear the quarantine if it is not.
#
# codex-plugin only. The probe goes to the root RECORDED in the file — read
# back, never re-derived — which is the whole reason that field exists.
# A subagent quarantine is refused: there is no API by which a shell can ask
# whether a subagent is alive, so inventing a probe would mean guessing.
review_round_quarantine_resolve() {
  local dir="${1:-}"
  [ -n "$dir" ] && [ -d "$dir" ] || {
    review_error "review_round_quarantine_resolve: round dir not found: '${dir:-}'"
    return 2
  }
  review_round_quarantined "$dir" || {
    review_error "review_round_quarantine_resolve: not quarantined: '$dir'"
    return 2
  }

  # PER BLOCK. The record holds one blank-line-separated block per unresolved
  # reviewer, and each must be probed against ITS OWN recorded owner.
  #
  # Round 9 found the hazard this replaces, and it was one I introduced: the
  # resolver read only the FIRST block (`_review_quarantine_field` stops at the
  # first match) and then `rm -f`'d the WHOLE file on success. Two codex jobs
  # in one round, the first finished and the second still running, meant the
  # sweep reclaimed the dir under the live one — exactly the failure the
  # multi-block record was added to prevent. A codex-plugin block followed by a
  # subagent block wiped the subagent's quarantine too, which no probe is
  # allowed to resolve at all.
  #
  # Only RESOLVED blocks are removed, and the file goes only when none remain.
  local tmp kept=0 resolved=0 mode q_id root st block line
  # SAME-DIR temp, so the rename below is atomic. A /tmp temp can land on a
  # different filesystem, where `mv` degrades to copy-then-unlink and a reader
  # can see a half-written record — which is read as "not quarantined" and the
  # dir reclaimed under a live reviewer.
  tmp="$dir/.quarantine.resolve.$$"
  : > "$tmp" || return 2

  # Read the file one block at a time. `mode`/`id`/`root` are reset per block,
  # so a block missing a field cannot inherit the previous block's.
  mode=""; q_id=""; root=""; block=""
  _resolve_flush() {
    [ -n "$q_id" ] || { mode=""; root=""; block=""; return 0; }
    local keep=1
    case "$mode" in
      codex-plugin)
        if [ -n "$root" ]; then
          # `$PWD` preserves this probe's pre-0055 behaviour EXACTLY — the
          # helper used to send no `--cwd`, and the companion then resolved its
          # store from its own process cwd. It is a placeholder, not a design:
          # AC3a replaces it with the cwd recorded in the block, because a
          # probe against a GUESSED workspace root answers `No job found` for a
          # live job and the sweep would then reclaim the dir under a running
          # reviewer.
          st="$(review_codex_job_status "$root" "$q_id" "$PWD" 2>/dev/null || true)"
          if [ -n "$st" ] && _review_codex_job_terminal "$st"; then
            keep=0
            resolved=$((resolved + 1))
          fi
        else
          review_error "review_round_quarantine_resolve: block for '$q_id' records no companion root; cannot probe, retaining"
        fi
        ;;
      subagent)
        review_error "review_round_quarantine_resolve: a subagent quarantine ($q_id) cannot be resolved by a probe — no shell-reachable API reports whether a subagent is still running; remove $dir/quarantine once it is known to have stopped"
        ;;
      *)
        review_error "review_round_quarantine_resolve: unknown recorded mode '${mode:-}' for '$q_id' in $dir/quarantine; retaining"
        ;;
    esac
    if [ "$keep" -eq 1 ]; then
      [ "$kept" -eq 0 ] || printf '\n' >> "$tmp"
      printf '%s' "$block" >> "$tmp"
      kept=$((kept + 1))
    fi
    mode=""; q_id=""; root=""; block=""
  }

  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      '') _resolve_flush ;;
      'id '*)      q_id="${line#id }";      block="$block$line
" ;;
      'mode '*)    mode="${line#mode }";    block="$block$line
" ;;
      'root '*)    root="${line#root }";    block="$block$line
" ;;
      *)           block="$block$line
" ;;
    esac
  done < "$dir/quarantine"
  _resolve_flush
  unset -f _resolve_flush 2>/dev/null || true

  if [ "$kept" -eq 0 ]; then
    rm -f "$tmp" "$dir/quarantine"
    return 0
  fi
  # Same-dir temp + rename, as the writer uses: a half-written record would be
  # read as "not quarantined" and the dir reclaimed under a live reviewer.
  mv -f "$tmp" "$dir/quarantine"
  return 1
}

# ---------------------------------------------------------------------------
# ACs 17b / 17c — the content-aware tree snapshot.
#
# After a round, speccraft must tell whether a reviewer wrote outside its round
# dir. A subagent runs with the orchestrator's own tools, so nothing stops it
# editing the repo; `failed subagent-wrote-files` is how that is caught.
#
# Every cheaper implementation has a hole, and each is pinned by a required
# test row rather than left to prose:
#
#   `git status --porcelain` text — a tracked file that was ALREADY dirty keeps
#     a byte-identical ` M <path>` entry when its contents change again, and an
#     untracked directory collapses to one `?? <dir>/` entry however many files
#     appear beneath it.
#   a path-only untracked inventory — editing the bytes of an existing
#     untracked file adds and removes no paths at all.
#   `--exclude-standard` — `bin/probe` and `tools/bin/probe` are gitignored
#     here, so a built binary landing in either would be invisible. "Never
#     commit built binaries from bin/" is a stated guardrail, which makes that
#     the most consequential case rather than an edge one.
#   `--directory` — collapses an untracked tree back to a single entry.
#
# So this hashes CONTENT, per file.
# ---------------------------------------------------------------------------

# The volatile set: paths that legitimately change mid-round and must not read
# as a reviewer write. A CLOSED list of four (AC17b) — widening it is a visible
# edit to the test that counts these entries, never a silent addition.
#
#   .claude                       machine-local host-tool state; the orchestrating
#                                 session writes permission allowlists ANYWHERE
#                                 under here while the round runs
#   .speccraft/state.json         session state, written by the hooks themselves
#   tests/e2e/.logs               e2e run logs
#   .speccraft/.review-rounds     the round dirs, including the round under way
#
# `.claude` is the WHOLE TREE, not just `settings.local.json`. The spec's
# contract-level list names the tree and gives the reason — the orchestrating
# session writes permission allowlists here during a round — and a narrower
# entry made any other write under `.claude/` read as `failed
# subagent-wrote-files` against a reviewer that did nothing (cross-model review
# round 6). AC17b's test row names only the settings file, which is a scoped
# wording correction recorded in the spec rather than a reason to narrow the
# behaviour.
#
# The last entry is what makes AC17c's installed-base first round clean: the
# round parent and its .gitignore are both created by round setup, and both
# live under it.
REVIEW_TREE_VOLATILE=".claude .speccraft/state.json tests/e2e/.logs .speccraft/.review-rounds"

# _review_tree_is_volatile <repo-relative-path> — zero when the path IS a
# volatile entry or lies beneath one.
#
# The list is chopped with parameter expansion rather than iterated with
# `for v in $REVIEW_TREE_VOLATILE`: zsh does not word-split an unquoted
# expansion, so that loop saw the whole list as ONE entry and nothing was ever
# volatile — every round then blamed the orchestrator's own bookkeeping writes
# on a reviewer. See _review_list_has in review.lib.sh.
_review_tree_is_volatile() {
  local p="$1" rest="$REVIEW_TREE_VOLATILE" v
  while [ -n "$rest" ]; do
    v="${rest%% *}"
    case "$rest" in
      *' '*) rest="${rest#* }" ;;
      *)     rest="" ;;
    esac
    [ -n "$v" ] || continue
    [ "$p" != "$v" ] || return 0
    case "$p" in
      "$v"/*) return 0 ;;
    esac
  done
  return 1
}

# review_tree_snapshot — one line per file, digest-then-path, sorted.
#
# Enumerated from the repo root as: every TRACKED file, plus every untracked
# file listed per-file. `--others` WITHOUT `--exclude-standard` is deliberate —
# that flag is exactly what would hide a write into a gitignored `bin/` — and
# without `--directory`, which would collapse an untracked tree to one entry.
#
# Non-regular entries are recorded by path and type but never read: a dangling
# symlink has nothing to hash, and hashing a fifo would block forever.
#
# KNOWN LIMITATION, pinned by its own test rather than left implicit: git
# enumerates untracked regular files and symlinks, but NOT fifos or sockets —
# they appear in neither `ls-files --others` nor `status --porcelain`. So a
# reviewer creating one outside its round dir is not detected. Catching that
# would mean walking the whole worktree with find instead of asking git, and
# for this check a false positive is far more damaging than missing an exotic
# case (AC17c requires it to be sensitive WITHOUT being noisy). The `-p` and
# `-e` arms below are therefore defensive, not reachable through git today.
#
# NUL-delimited throughout, so a path containing a space or newline is one
# entry rather than several. `read -r -d ''` is used by both bash and zsh.
review_tree_snapshot() {
  local root listing rc=0
  root="$(speccraft-state find-root 2>/dev/null || pwd)"
  # Resolved here so a missing SHA-256 primitive is a named error BEFORE any
  # enumeration, rather than an "unreadable" line against every file.
  _review_digest_cmd >/dev/null || return 1

  # The enumeration's exit status is CHECKED, which it previously was not. The
  # two `git ls-files` calls sent stderr to /dev/null and the function returned
  # the status of `sort`, so outside a work tree — or with git failing for any
  # reason — the snapshot was EMPTY and succeeded. Two empty snapshots compare
  # equal, so the before/after check silently passed while detecting nothing at
  # all: a reviewer could write anywhere in the repo and the round would call
  # it clean. Found by cross-model review, round 6.
  listing="$(mktemp)" || return 1
  (
    cd "$root" 2>/dev/null || exit 2
    git ls-files -z > "$listing" 2>/dev/null || exit 3
    git ls-files --others -z >> "$listing" 2>/dev/null || exit 3
  ) || rc=$?
  if [ "$rc" -ne 0 ]; then
    rm -f "$listing"
    case "$rc" in
      2) review_error "review_tree_snapshot: cannot enter the repo root '$root'" ;;
      *) review_error "review_tree_snapshot: 'git ls-files' failed in '$root'; refusing to report an empty snapshot that would compare equal to any other and hide every out-of-bounds write" ;;
    esac
    return 1
  fi

  (
    cd "$root" 2>/dev/null || exit 1
    while IFS= read -r -d '' p; do
      [ -n "$p" ] || continue
      if _review_tree_is_volatile "$p"; then
        continue
      fi
      if [ -L "$p" ]; then
        printf 'symlink%57s  %s\n' '' "$p"
      elif [ -p "$p" ]; then
        printf 'fifo%60s  %s\n' '' "$p"
      elif [ -f "$p" ]; then
        # Through the wrapper, never `$digest "$p"`: the resolved value can be
        # two words and zsh would treat the whole thing as one command name.
        _review_digest_exec "$p" 2>/dev/null || printf 'unreadable%54s  %s\n' '' "$p"
      elif [ -e "$p" ]; then
        printf 'special%57s  %s\n' '' "$p"
      else
        printf 'absent%58s  %s\n' '' "$p"
      fi
    done < "$listing" | LC_ALL=C sort -u
  )
  rc=$?
  rm -f "$listing"
  return "$rc"
}

# ---------------------------------------------------------------------------
# ACs 20a / 20b / 17a — the subagent timeout, cancellation and collection
# protocol.
#
# A subagent is not a process. The shell cannot see it, signal it, or wait on
# it: only the orchestrating session can, through the Agent and TaskStop tools,
# across many separate tool calls between which NO shell state survives. Two
# consequences shape every helper below.
#
# First, the agent id and the deadline live in the round dir. A model that had
# to carry them in prose across a dozen tool calls would eventually carry them
# wrong, and the failure mode is silent: a reviewer nobody can stop.
#
# Second, the deadline is recorded as an ABSOLUTE epoch second, not as the
# timeout it came from. A relative timeout re-read on a later tool call
# restarts the clock every time it is consulted, so no reviewer is ever late
# and the whole protocol is inert.
# ---------------------------------------------------------------------------

# _review_subagent_rec <round-dir> <agent> — the record path, or exit 2 naming
# the reason. An agent name is a registry key, not a path: one carrying a
# separator would write outside the round dir.
_review_subagent_rec() {
  local dir="${1:-}" agent="${2:-}"
  [ -n "$dir" ] && [ -d "$dir" ] || {
    review_error "review subagent: round dir not found: '${dir:-}'"
    return 2
  }
  [ -n "$agent" ] || { review_error "review subagent: agent name required"; return 2; }
  # An allow-LIST, not a deny-list. The record is a `key=value` file read with
  # `awk -F=`, so a newline in the name breaks the format; a glob character can
  # match a path the caller did not mean; and registry names are
  # user-controlled. A deny-list of `/` and `\` missed both (round 8).
  case "$agent" in
    *[!A-Za-z0-9._-]*|.|..)
      review_error "review subagent: agent name '$agent' is not a bare registry key (allowed: letters, digits, dot, underscore, hyphen)"
      return 2
      ;;
  esac
  printf '%s/%s.subagent\n' "$dir" "$agent"
}

# review_subagent_completed <round-dir> <agent> — stamp the moment the
# orchestrator OBSERVED this reviewer finish, into its launch record.
#
# Call it the instant the completion notification arrives, before any other
# tool call. That instant is the only time the information exists: the
# orchestrator is re-invoked when a backgrounded agent finishes, and by the
# time it gets round to collecting, an unknown number of tool calls have passed.
#
# Why a stamp rather than the artifact's mtime, which was the first fix for the
# same defect: there is no portable way to read an mtime in shell. `date -r`
# means "read this FILE" to GNU date and "this epoch SECOND" to BSD date;
# `stat` wants `-c %Y` on GNU and `-f %m` on BSD, and this repo's portability
# guard flags the GNU spelling on sight — correctly, since it is exactly the
# kind of form that works on CI and fails on a maintainer's laptop. A stamp the
# round writes itself is integer arithmetic over data we own, and it records
# the event AC20b is actually about.
review_subagent_completed() {
  local dir="${1:-}" agent="${2:-}" rec now
  rec="$(_review_subagent_rec "$dir" "$agent")" || return 2
  [ -f "$rec" ] || {
    review_error "review_subagent_completed: no launch record for agent \"$agent\" in $dir"
    return 2
  }
  now="$(date +%s)"
  printf 'completed=%s\n' "$now" >> "$rec"
  printf '%s\n' "$now"
}

# _review_is_int <value> — a base-10 integer, optionally negative. A negative
# timeout is accepted on purpose: it is how a caller (and every test here)
# records a deadline already in the past without sleeping or injecting a clock.
_review_is_int() {
  case "${1:-}" in
    ''|-) return 1 ;;
    -*) case "${1#-}" in ''|*[!0-9]*) return 1 ;; esac ;;
    *[!0-9]*) return 1 ;;
  esac
  return 0
}

# review_subagent_record <round-dir> <agent> <agent-id> <timeout-s>
# — persist what the round will need to stop and judge this reviewer later.
review_subagent_record() {
  local dir="${1:-}" agent="${2:-}" id="${3:-}" timeout_s="${4:-}" rec now deadline
  rec="$(_review_subagent_rec "$dir" "$agent")" || return 2
  [ -n "$id" ] || {
    review_error "review_subagent_record: agent id required for agent \"$agent\" — a stop-failed outcome with no id is unactionable"
    return 2
  }
  _review_is_int "$timeout_s" || {
    review_error "review_subagent_record: timeout must be an integer number of seconds (got '${timeout_s:-}')"
    return 2
  }
  now="$(date +%s)"
  deadline=$((now + timeout_s))
  # Same-dir temp + rename: a half-written record would be read as a missing
  # one, and a missing record is a named error the round cannot proceed past.
  {
    printf 'agent=%s\n' "$agent"
    printf 'agent_id=%s\n' "$id"
    printf 'launched=%s\n' "$now"
    printf 'deadline=%s\n' "$deadline"
  } > "$rec.tmp.$$"
  mv -f "$rec.tmp.$$" "$rec"
}

# _review_subagent_field <round-dir> <agent> <key>
_review_subagent_field() {
  local dir="${1:-}" agent="${2:-}" key="${3:-}" rec val
  rec="$(_review_subagent_rec "$dir" "$agent")" || return 2
  [ -f "$rec" ] || {
    review_error "review subagent: no launch record for agent \"$agent\" in $dir"
    return 2
  }
  val="$(awk -F= -v k="$key" '$1 == k { print $2; exit }' "$rec")"
  [ -n "$val" ] || {
    review_error "review subagent: launch record for agent \"$agent\" has no $key"
    return 2
  }
  printf '%s\n' "$val"
}

# review_subagent_agent_id <round-dir> <agent>
review_subagent_agent_id() {
  _review_subagent_field "$1" "$2" agent_id
}

# review_subagent_deadline_expired <round-dir> <agent>
#   0 — the deadline has passed
#   1 — still within it
#   2 — no launch record, named
#
# "No record" is deliberately NOT "not expired". A reviewer the round never
# recorded would otherwise run forever while the cleanup gate waited on it.
review_subagent_deadline_expired() {
  local deadline now
  deadline="$(_review_subagent_field "$1" "$2" deadline)" || return 2
  _review_is_int "$deadline" || {
    review_error "review_subagent_deadline_expired: deadline '$deadline' is not an epoch second"
    return 2
  }
  now="$(date +%s)"
  [ "$now" -lt "$deadline" ] || return 0
  return 1
}

# review_subagent_collect <round-dir> <agent>
#   stdout `ok`                            — a usable artifact, on time
#   stdout `timeout late-completion`       — arrived after its deadline
#   stdout `failed subagent-no-output`     — returned without a verdict
#   exit 2                                 — no launch record, named
#
# Reads `<round-dir>/<agent>.out` FROM DISK (AC17a). Any further arguments are
# ignored: a collector that accepted pasted content would let an Agent tool
# result stand in for the artifact whose digest attestation covers, and the
# attestation would then prove nothing.
#
# Lateness is decided by the recorded COMPLETION stamp, not by the clock at
# collection time. That was wrong at first and round 8 caught it: the protocol
# has the orchestrator wait for the SLOWEST reviewer's deadline before
# collecting (§4 steps 3-4), so "now is past the deadline" was true for EVERY
# reviewer in any round containing one timeout — and a fast reviewer's
# perfectly timely verdict was recorded `timeout late-completion` and dropped
# from quorum. One slow reviewer could discard every other verdict.
#
# AC20b is about output that LANDS after its deadline, which is what
# `review_subagent_completed` stamps at the moment the notification arrives.
#
# No-output is decided FIRST: an agent that returned without writing a verdict
# is diagnosable whatever the clock said, and there is nothing to judge the
# timing of.
#
# A missing completion stamp is a NAMED error, never a guess. Falling back to
# "now" is precisely the bug above, and assuming on-time would let a genuinely
# late verdict into quorum — so the protocol has to have stamped it, and if it
# did not, that is the thing to fix.
review_subagent_collect() {
  local dir="${1:-}" agent="${2:-}" art deadline landed
  deadline="$(_review_subagent_field "$dir" "$agent" deadline)" || return 2
  art="$dir/$agent.out"
  # Whitespace-only counts as no output: a reviewer that wrote a newline has
  # not returned a verdict, and an empty verdict is the one thing worse than a
  # missing one.
  if [ ! -f "$art" ] || [ -z "$(LC_ALL=C tr -d '[:space:]' < "$art")" ]; then
    printf 'failed subagent-no-output\n'
    return 0
  fi
  landed="$(_review_subagent_field "$dir" "$agent" completed)" || {
    review_error "review_subagent_collect: agent \"$agent\" wrote an artifact but has no completion stamp; call review_subagent_completed when the notification arrives — collection time is NOT when it finished"
    return 2
  }
  # Both values validated. `[ "$x" -gt "$y" ]` on a non-integer errors with
  # status 2, which `if` reads as FALSE — so a malformed stamp would quietly
  # admit the verdict as on time instead of raising. The sibling
  # review_subagent_deadline_expired validated its value and this did not.
  _review_is_int "$landed" && _review_is_int "$deadline" || {
    review_error "review_subagent_collect: agent \"$agent\" has a malformed record (completed='$landed', deadline='$deadline'); refusing to guess whether its verdict was on time"
    return 2
  }
  if [ "$landed" -gt "$deadline" ]; then
    printf 'timeout late-completion\n'
    return 0
  fi
  printf 'ok\n'
}

# review_subagent_stop_failed <round-dir> <agent>
# — a TaskStop that did not confirm. Records the outcome naming the AGENT ID
# (the handle the host knows it by, not the registry name the operator chose)
# and quarantines the round dir, because a reviewer that may still be running
# needs its payload and its output path kept.
review_subagent_stop_failed() {
  local dir="${1:-}" agent="${2:-}" id
  id="$(review_subagent_agent_id "$dir" "$agent")" || return 2
  # No companion root: no shell-reachable API can ask whether a subagent is
  # still alive, so only an operator removing the file resolves this.
  review_round_quarantine "$dir" "$id" subagent-stop-failed subagent || return 2
  printf 'failed subagent-stop-failed %s\n' "$id"
}

# review_subagent_active_list <round-dir> — the registry names of every
# subagent launched in this round, one per line, sorted.
#
# "Active over the snapshot interval" is read from these records rather than
# inferred from wall-clock timing (conventions.md §Ledger write-lock:
# contention tests use the seam, never timing). Every subagent with a launch
# record WAS live at some point between the two snapshots by construction:
# `tree.before` is taken immediately after the round dir is created, and
# `tree.after` only once every reviewer is terminal. Asking instead "which
# agents are running right now" would attribute a write to nobody, because by
# §7 they have all returned.
review_subagent_active_list() {
  local dir="${1:-}"
  [ -n "$dir" ] && [ -d "$dir" ] || {
    review_error "review_subagent_active_list: round dir not found: '${dir:-}'"
    return 2
  }
  # `find`, not a glob. In zsh an unmatched glob is a FATAL error, so
  # `for f in "$dir"/*.subagent` would abort the caller on any round with no
  # subagent reviewers — which is most rounds.
  find "$dir" -maxdepth 1 -type f -name '*.subagent' 2>/dev/null \
    | sed 's|.*/||; s|\.subagent$||' \
    | LC_ALL=C sort
}

# review_attribute_tree_writes <round-dir>
# — compare the pre- and post-round tree snapshots and emit one outcome line
# per subagent that must answer for a write outside the round dir. Nothing on
# stdout means no reviewer is to blame.
#
# A subagent shares the orchestrating session's filesystem access, so an
# out-of-bounds write is DETECTABLE but not always ATTRIBUTABLE: with two
# subagents running concurrently nothing in the snapshot says which one wrote.
# The rule is therefore conditioned on how many were active (AC17d):
#
#   exactly one   — name THAT agent: `<agent> failed subagent-wrote-files`
#   more than one — fail every one of them, marked `<unattributed>`
#   none          — blame nobody; warn on stderr, emit nothing
#
# Failing both is deliberately harsh — one reviewer's misbehaviour voids the
# other's verdict. The alternatives are worse: guessing blames an innocent
# reviewer BY NAME, and letting both stand admits a verdict from a round whose
# integrity is unknown.
#
# `codex-plugin` reviewers are never swept in. They leave no launch record, and
# their `touchedFiles` is per job, self-attested and attributable on its own.
review_attribute_tree_writes() {
  local dir="${1:-}" before after list n agent
  [ -n "$dir" ] && [ -d "$dir" ] || {
    review_error "review_attribute_tree_writes: round dir not found: '${dir:-}'"
    return 2
  }
  before="$dir/tree.before"
  after="$dir/tree.after"
  # A missing snapshot must NEVER read as "no change": that would turn the
  # whole tree check into a no-op on exactly the round where it failed to run.
  [ -f "$before" ] || {
    review_error "review_attribute_tree_writes: no pre-round snapshot at $before — comparing against nothing cannot mean the tree is unchanged"
    return 2
  }
  [ -f "$after" ] || {
    review_error "review_attribute_tree_writes: no post-round snapshot at $after — comparing against nothing cannot mean the tree is unchanged"
    return 2
  }

  ! cmp -s "$before" "$after" || return 0

  list="$(review_subagent_active_list "$dir")" || return 2
  n="$(printf '%s\n' "$list" | grep -c . || true)"
  if [ "$n" -eq 0 ]; then
    review_error "review_attribute_tree_writes: the tree changed during this round but no subagent was launched, so no reviewer can be blamed; inspect $dir and the working tree"
    return 0
  fi
  if [ "$n" -eq 1 ]; then
    printf '%s failed subagent-wrote-files\n' "$list"
    return 0
  fi
  while IFS= read -r agent; do
    [ -n "$agent" ] || continue
    printf '%s failed subagent-wrote-files <unattributed>\n' "$agent"
  done <<EOF
$list
EOF
}

# review_attribute_tree_outcomes <round-dir> <outcomes-file>
#   0 — the tree was unchanged; the outcomes file is byte-unchanged
#   1 — at least one reviewer was disqualified and its record REPLACED
#   2 — a named error
#
# The companion to review_attribute_tree_writes, and the form the runbook must
# use. Round 8 caught the difference: the runbook APPENDED the attribution, so
# an implicated reviewer's `approve` stayed in the file alongside its own
# `failed subagent-wrote-files`. At quorum 1 the round then printed
# `responses_complete: false` AND `approval_quorum_met: true` — an innocent
# reviewer's approval carrying a round whose integrity is unknown, which is
# precisely what AC17d exists to prevent.
#
# So there is ONE authoritative record per reviewer. Same shape as
# review_hash_collision_outcomes, for the same reason.
review_attribute_tree_outcomes() {
  local dir="${1:-}" outcomes="${2:-}"
  [ -n "$dir" ] && [ -d "$dir" ] || {
    review_error "review_attribute_tree_outcomes: round dir not found: '${dir:-}'"
    return 2
  }
  [ -n "$outcomes" ] && [ -f "$outcomes" ] || {
    review_error "review_attribute_tree_outcomes: outcomes file not found: '${outcomes:-}'"
    return 2
  }

  local attributed rc=0
  attributed="$(review_attribute_tree_writes "$dir" 2>/dev/null)" || rc=$?
  [ "$rc" -ne 2 ] || return 2
  # A clean tree, or a change no reviewer can answer for: nothing to rewrite,
  # and the file must not be touched at all.
  [ -n "$attributed" ] || return 0

  local tmp line agent replacement
  tmp="$(mktemp)" || return 2
  while IFS= read -r line || [ -n "$line" ]; do
    [ -n "$line" ] || continue
    agent="${line%% *}"
    # The replacement for THIS agent, if it was implicated. Matched on the
    # agent column of the attribution output, so a reviewer whose name is a
    # prefix of another's is not swept in.
    replacement="$(printf '%s\n' "$attributed" \
      | awk -v a="$agent" '$1 == a { print; exit }')"
    if [ -n "$replacement" ]; then
      printf '%s\n' "$replacement" >> "$tmp"
    else
      printf '%s\n' "$line" >> "$tmp"
    fi
  done < "$outcomes"
  cat -- "$tmp" > "$outcomes"
  rm -f "$tmp"
  return 1
}

# ---------------------------------------------------------------------------
# ACs 14d / 15 — "proven terminal", and the cleanup gate that rests on it.
#
# The round dir holds every reviewer's payload AND the path each writes its
# verdict to. Cleanup therefore has two jobs that pull against each other: it
# must run on every exit path, and it must never run while a reviewer might
# still write there. Deleting a live reviewer's output path does not fail
# loudly — the reviewer writes into a removed directory and the round records
# `subagent-no-output`, which reads as the REVIEWER's fault.
#
# Proof comes from the round's own records, never from the clock. A reviewer
# whose deadline passed may still be running; that is precisely why TaskStop
# and the stop-failed outcome exist.
# ---------------------------------------------------------------------------

# review_subagent_terminal <round-dir> <agent> <reason>
# — stamp a reviewer that will never complete: timed out, confirmed stopped,
# refused at preflight. `review_subagent_completed` covers the happy path; this
# covers the rest, and without it a round containing one timeout could never be
# cleaned up and would have to wait for lease expiry.
#
# The reason is REQUIRED. A bare `terminal=` is unauditable: an operator
# reading the record cannot tell a confirmed stop from a give-up.
review_subagent_terminal() {
  local dir="${1:-}" agent="${2:-}" reason="${3:-}" rec
  rec="$(_review_subagent_rec "$dir" "$agent")" || return 2
  [ -f "$rec" ] || {
    review_error "review_subagent_terminal: no launch record for agent \"$agent\" in $dir"
    return 2
  }
  [ -n "$reason" ] || {
    review_error "review_subagent_terminal: a reason is required for agent \"$agent\" — 'terminal' with no reason cannot be audited"
    return 2
  }
  case "$reason" in
    *[!A-Za-z0-9._-]*)
      review_error "review_subagent_terminal: reason '$reason' must be a single bare token"
      return 2
      ;;
  esac
  printf 'terminal=%s %s\n' "$(date +%s)" "$reason" >> "$rec"
}

# review_round_all_terminal <round-dir>
#   0 — every recorded reviewer is proven terminal (or none was recorded)
#   1 — at least one is still pending; the pending names go to stderr
#   2 — a named error
#
# A round with NO launch records is terminal: nothing was launched through the
# record, so nothing can still be writing. Answering "pending" there would make
# cleanup unreachable for every cli-only round, which is most of them.
review_round_all_terminal() {
  local dir="${1:-}" pending="" agent rec
  [ -n "$dir" ] && [ -d "$dir" ] || {
    review_error "review_round_all_terminal: round dir not found: '${dir:-}'"
    return 2
  }
  while IFS= read -r agent; do
    [ -n "$agent" ] || continue
    rec="$dir/$agent.subagent"
    # Either stamp proves it: `completed` (it returned) or `terminal` (it was
    # stopped, timed out, or refused). An expired deadline is NOT a stamp.
    grep -qE '^(completed|terminal)=' "$rec" 2>/dev/null && continue
    pending="$pending $agent"
  done <<EOF
$(review_subagent_active_list "$dir")
EOF
  [ -n "$pending" ] || return 0
  review_error "review_round_all_terminal: still pending:$pending (each needs review_subagent_completed or review_subagent_terminal)"
  return 1
}

# review_round_quarantine_count <round-dir> — how many reviewers the dir has
# unresolved. Zero when there is no quarantine file at all.
#
# One round can have TWO reviewers whose stop never confirmed, and the record
# used to be written with `mv -f`: the second overwrote the first, the operator
# lost that agent's handle, and resolving the surviving record would release
# the dir while the first reviewer might still be writing to it. Found by
# round 8.
review_round_quarantine_count() {
  local dir="${1:-}"
  [ -n "$dir" ] && [ -d "$dir" ] || {
    review_error "review_round_quarantine_count: round dir not found: '${dir:-}'"
    return 2
  }
  [ -f "$dir/quarantine" ] || { printf '0\n'; return 0; }
  # `grep -c` prints 0 AND exits 1 when there is no match, so a
  # `grep -c … || printf '0\n'` emitted "0" TWICE for a record with no `id`
  # lines. Captured, then printed once.
  local n
  n="$(grep -c '^id ' "$dir/quarantine" 2>/dev/null || true)"
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  printf '%s\n' "$n"
}
