#!/usr/bin/env bash
# commands/spec/review.lib.sh — testable shell helpers backing
# /speccraft:spec:review. Sourced by commands/spec/review.md at runtime and by
# tests/hooks/spec-review-diff.bats (spec 0035) and
# tests/hooks/spec-review-payload.bats (spec 0052).
#
# The Go binaries own change DETECTION (speccraft-state review-diff /
# review-snapshot). This lib owns the command-layer UX in two layers:
#
#   spec 0035 — the provenance gate: parsing the prior review fingerprint and
#     classifying the round as full-review / scoped / short-circuit.
#   spec 0052 — the BYTE BOUNDARY. This file is the SOLE byte-producing owner for
#     review dispatch: it tiers the context, composes the one payload, measures
#     it against the budget, dispatches those exact bytes, validates the
#     reference-read attestation, and decides the round's two predicates. Nothing
#     else may compose reviewer bytes — a second composer means a second answer
#     to "what was sent", and the budget can only measure one of them.
#
# "Pure" here means NO SIDE EFFECTS AT SOURCE TIME: sourcing this file from bats
# defines functions and nothing more. Individual functions do write — the payload
# artifact, the digest sidecar, the round temp directory — which is sanctioned
# precedent (revise.lib.sh ships archive_rename, snapshot_spec, bump_revision).
# That distinction was raised as a convention violation in review round 5 and
# checked against .speccraft/conventions.md before being set aside.
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

# ---------------------------------------------------------------------------
# Cross-shell list membership and iteration.
#
# These libs are `source`d into whatever shell the .md command bodies run,
# which on macOS is zsh — and **zsh does not word-split an unquoted parameter
# expansion**. So the natural-looking
#
#     for entry in $REVIEW_INLINE_SET; do ...
#
# iterates ONCE under zsh, with the whole string as a single element, and every
# membership test it implements answers "no" for every input. Cross-model
# review round 6 found this across the tier table, the outcome tokens, the
# mode enum, the effort and model enums and the volatile set — every one of
# them on the main path of a review round, and all of them invisible to a suite
# that only ever ran under bash.
#
# The replacement chops the string with POSIX parameter expansion, which does
# exactly the same thing in both shells and starts no subprocess. A padded
# `case " $list " in *" $item "*)` was considered and rejected: the item lands
# on the PATTERN side, so an item containing a glob character would match more
# than itself.
#
# `_review_list_has` is the membership test. Where a caller needs each entry
# (to prefix-match, say), it chops the list inline the same way — a
# `while read` loop would put the match in a subshell that cannot return from
# its caller.
# ---------------------------------------------------------------------------

# _review_list_has <item> <space-separated-list> — zero iff <item> is an entry.
_review_list_has() {
  local needle="${1:-}" rest="${2:-}" head
  while [ -n "$rest" ]; do
    head="${rest%% *}"
    case "$rest" in
      *' '*) rest="${rest#* }" ;;
      *)     rest="" ;;
    esac
    [ -n "$head" ] || continue
    [ "$head" != "$needle" ] || return 0
  done
  return 1
}

# _review_list_join <space-separated-list> — echo the entries as "a, b, c", for
# a diagnostic that reads as a list of choices rather than as one odd string.
_review_list_join() {
  local rest="${1:-}" head out=""
  while [ -n "$rest" ]; do
    head="${rest%% *}"
    case "$rest" in
      *' '*) rest="${rest#* }" ;;
      *)     rest="" ;;
    esac
    [ -n "$head" ] || continue
    [ -z "$out" ] || out="$out, "
    out="$out$head"
  done
  printf '%s\n' "$out"
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
  local path="${1:-}" rel
  [ -n "$path" ] || { review_error "review_context_tier: path required"; return 1; }
  rel="$(_review_repo_relative "$path")"
  if _review_list_has "$rel" "$REVIEW_INLINE_SET"; then
    printf 'inline\n'; return 0
  fi
  if _review_list_has "$rel" "$REVIEW_REFERENCE_SET"; then
    printf 'reference\n'; return 0
  fi
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
  # `-e`, not `-f`: a reference source may be a FIFO or other non-regular file,
  # and the one-scan proof in tests/hooks/spec-review-payload.bats depends on it.
  [ -e "$file" ] || { review_error "review_heading_index: $file not found"; return 1; }
  _review_heading_stream < "$file"
}

# _review_heading_stream — the single heading/fence parser, reading stdin.
# review_heading_index wraps it for a path; _review_scan_reference feeds it the
# ONE buffer it read (AC8), so there is exactly one grammar in the lib rather
# than a file version and a buffer version drifting apart
# (.speccraft/conventions.md §"One shared parser entrypoint").
_review_heading_stream() {
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
  '
}

# ---------------------------------------------------------------------------
# Spec 0052 — the digest primitive, and the one-scan reference record.
# ---------------------------------------------------------------------------

# _review_digest_cmd — echo the SHA-256 command word, resolved ONCE per shell.
#
# PORTABILITY, load-bearing and the same class as the awk-interval trap guarded
# above: the GNU coreutils checksum tool is absent from a default macOS
# userland, while `shasum -a 256` ships on both BSD and GNU systems. This repo
# lost eight consecutive CI runs to that class (spec 0050), so `shasum` is
# PREFERRED and the GNU tool is reached only through a `command -v` probe whose
# resolved PATH is what gets executed — never a bare literal invocation, which
# tests/hooks/portability-guard.bats clause (e) correctly forbids under a
# shipped root.
_REVIEW_DIGEST_CMD="${_REVIEW_DIGEST_CMD:-}"
_review_digest_cmd() {
  [ -z "$_REVIEW_DIGEST_CMD" ] || { printf '%s\n' "$_REVIEW_DIGEST_CMD"; return 0; }
  if command -v shasum >/dev/null 2>&1; then
    _REVIEW_DIGEST_CMD="shasum -a 256"
  else
    local gnu
    gnu="$(command -v sha256sum 2>/dev/null || true)"
    [ -n "$gnu" ] || {
      review_error "review_digest: no SHA-256 primitive on PATH (looked for 'shasum -a 256', then the GNU coreutils checksum tool)"
      return 1
    }
    _REVIEW_DIGEST_CMD="$gnu"
  fi
  printf '%s\n' "$_REVIEW_DIGEST_CMD"
}

# _review_digest_exec <args…> — run the resolved SHA-256 primitive.
#
# A WRAPPER, not `$cmd "$@"`. The resolved value may be two words
# (`shasum -a 256`), and zsh does not word-split an unquoted expansion, so
# `$cmd "$@"` under zsh tried to execute a command literally named
# "shasum -a 256" — which made every digest in this lib, and therefore the whole
# attestation chain and the tree snapshot, fail on macOS. Cross-model review
# round 6 reproduced it. Dispatching on the resolved value keeps each form a
# real, separately-worded invocation that both shells read the same way.
#
# The GNU branch executes the PATH-resolved absolute path from `command -v`,
# never a bare literal, which is what portability-guard clause (e) requires.
_review_digest_exec() {
  local cmd
  cmd="$(_review_digest_cmd)" || return 1
  case "$cmd" in
    'shasum -a 256') shasum -a 256 "$@" ;;
    *)               "$cmd" "$@" ;;
  esac
}

# review_digest [<file>] — echo the bare lowercase hex SHA-256 of <file>, or of
# stdin when no file is given. Both primitives emit "<hex>  <name>", so the
# first field is taken.
review_digest() {
  local out
  if [ $# -gt 0 ]; then
    out="$(_review_digest_exec < "$1")" || return 1
  else
    out="$(_review_digest_exec)" || return 1
  fi
  printf '%s\n' "${out%% *}"
}

# _review_scan_reference <path> — read <path> ONCE and emit its record:
#   line 1   : "<byte-size> <sha256>"
#   lines 2+ : the heading index, in file order
#
# ONE read is a contract, not an optimisation (AC8). The obvious two-pass shape
# — `wc -c "$f"` then `grep '^## ' "$f"` — looks reasonable and is wrong: on a
# single-use source the size comes from one read and the index from another, so
# the record describes two different things. Everything below is derived from
# the single buffer.
#
# The buffer cannot carry a NUL byte, and that FAILS SAFE rather than silently:
# a NUL-bearing reference yields a digest the reviewer's own read will not
# match, the attestation fails, and the verdict is not counted — the same
# outcome as a reference that could not be read at all.
_review_scan_reference() {
  local file="${1:-}" buf size digest
  [ -n "$file" ] || { review_error "_review_scan_reference: path required"; return 1; }
  [ -e "$file" ] || { review_error "_review_scan_reference: $file not found"; return 1; }
  # The trailing-X sentinel preserves trailing newlines, which command
  # substitution would otherwise strip — the same byte-fidelity concern AC10
  # settles for the payload artifact, arriving one layer down.
  buf="$(LC_ALL=C cat -- "$file"; printf X)"
  buf="${buf%X}"
  size="$(printf '%s' "$buf" | LC_ALL=C wc -c | tr -d ' ')"
  digest="$(printf '%s' "$buf" | review_digest)" || return 1
  printf '%s %s\n' "$size" "$digest"
  printf '%s' "$buf" | _review_heading_stream
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
  local outcome="${1:-}"
  if _review_list_has "$outcome" "$REVIEW_VERDICTS"; then
    printf 'verdict\n'; return 0
  fi
  if _review_list_has "$outcome" "$REVIEW_NON_VERDICTS"; then
    printf 'non-verdict\n'; return 0
  fi
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
    ! _review_list_has "$outcome" "$REVIEW_AGREEING_VERDICTS" || count=$((count + 1))
  done < "$file"
  [ "$count" -ge "$quorum" ]
}

# The four lanes a review round can finalize. Kept as a space-separated list
# and read through _review_list_has, never with `for k in $VAR`: these helpers
# are sourced into the CALLER's shell, and zsh does not word-split an unquoted
# parameter expansion, so a loop form answers "no" to every kind on macOS.
REVIEW_ROUND_KINDS="spec design brief code"

# review_finalize_round <doc-dir> <quorum> <outcomes-file> [<kind>]
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
#
# <kind> defaults to `spec`, so every pre-0054 three-argument caller keeps
# exactly the behaviour above. The other three lanes have no spec.md to
# snapshot and no `reviewed_sha256:` envelope to stamp, so for them this
# function performs NO durable write at all (spec 0054 AC21):
#
#   design, brief — the synthesized `review.md` is the command's own Write,
#     gated on `responses_complete` by the runbook. finalize must not stamp a
#     fingerprint into it: speccraft-state review-commit rewrites the file's
#     frontmatter, which on a design/brief would corrupt a document whose
#     provenance nothing verifies.
#   code — nothing durable exists; the report IS the output (AC22a).
#
# `status:` stays `draft` for design and brief even at quorum. Those lanes are
# promoted by /speccraft:arch:decide and /speccraft:pm:prioritize, never by a
# review round, so `reviewed` would name a state neither machine has. For
# `code` there is no document and no lane, hence `n/a`.
#
# An unrecognised kind is exit 2 with the word named, NOT a fall-through to
# `spec`: a typo'd kind must not earn the spec lane's durable writes against a
# directory that is not a spec dir.
review_finalize_round() {
  local spec_dir="${1:-}" quorum="${2:-}" file="${3:-}" round_kind="${4:-spec}"
  local toml="${5:-}" authors="${6:-}"
  local complete=false quorum_met=false synthesis=skipped state=draft
  local rc fp agent outcome rest kind model
  [ -n "$spec_dir" ] || { review_error "review_finalize_round: spec dir required"; return 2; }
  _review_list_has "$round_kind" "$REVIEW_ROUND_KINDS" || {
    review_error "review_finalize_round: unknown kind '$round_kind' (want one of: $REVIEW_ROUND_KINDS)"
    return 2
  }
  [ "$round_kind" != code ] || state="n/a"

  rc=0; review_responses_complete "$file" || rc=$?
  [ "$rc" -ne 2 ] || return 2
  [ "$rc" -eq 0 ] && complete=true

  rc=0; review_approval_quorum_met "$quorum" "$file" || rc=$?
  [ "$rc" -ne 2 ] || return 2
  [ "$rc" -eq 0 ] && quorum_met=true

  if [ "$complete" = true ]; then
    synthesis=done
    if [ "$round_kind" = spec ]; then
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
  fi

  printf 'responses_complete: %s\n' "$complete"
  printf 'approval_quorum_met: %s\n' "$quorum_met"
  printf 'synthesis: %s\n' "$synthesis"
  printf 'status: %s\n' "$state"

  # The four lines above are spec 0052's contract and are emitted FIRST and
  # unconditionally. The vendor record below is additive: with no registry
  # argument nothing extra is printed, so every three-argument caller's report
  # is byte-identical to what 0052 produced. A test pins that.
  #
  # The status is CAPTURED, not discarded inside a printf argument. Round 8
  # caught that: `printf '…%s\n' "$(helper)"` throws away the helper's exit
  # code, so an approving agent missing from the registry — which makes
  # review_agent_vendor fail by name — printed `single_vendor_approval: ` with
  # an EMPTY value and still returned 0. A failure reported as success.
  if [ -n "$toml" ]; then
    local flag
    flag="$(review_single_vendor_approval "$toml" "$file" "$authors")" || {
      review_error "review_finalize_round: vendor resolution failed; the round's single_vendor_approval cannot be determined"
      return 2
    }
    printf 'single_vendor_approval: %s\n' "$flag"
  fi

  # Every refusal AND every verdict obtained. A report naming only the failures
  # hides a real verdict from the developer; one naming only the verdicts hides
  # that the round consulted fewer models than it appears to have.
  while IFS=' ' read -r agent outcome rest || [ -n "$agent" ]; do
    [ -n "$agent" ] || continue
    rc=0; kind="$(_review_outcome_kind "$outcome")" || rc=$?
    [ "$rc" -eq 0 ] || return 2
    if [ "$kind" = "verdict" ]; then
      if [ -n "$toml" ]; then
        # mode / requested model / vendor, so the synthesized review.md can say
        # WHO agreed rather than only how many did. An omitted registry model
        # is recorded `inherit`, which is what the dispatch actually does.
        model="$(review_agent_field "$toml" "$agent" model 2>/dev/null)" || model=""
        printf 'verdict: %s %s mode=%s model=%s vendor=%s\n' \
          "$agent" "$outcome" \
          "$(review_agent_mode "$toml" "$agent" 2>/dev/null || printf 'unknown')" \
          "${model:-inherit}" \
          "$(review_agent_vendor "$toml" "$agent" 2>/dev/null || printf 'unknown')"
      else
        printf 'verdict: %s %s\n' "$agent" "$outcome"
      fi
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

# ---------------------------------------------------------------------------
# Spec 0052 — the round's temp directory, the ONE payload artifact, and dispatch.
#
# "Bytes exactly as handed to the CLI" cannot be guaranteed through shell command
# substitution, which strips trailing newlines. So the payload is written to a
# single file, the budget is measured over THAT file, and THAT file is what gets
# piped to stdin, passed with --file, or read for an argv-mode invocation.
# Measured bytes and dispatched bytes are the same bytes by construction rather
# than by convention.
#
# This is the ONLY materialization permitted. No debug or convenience copy may be
# written anywhere else: a cached full prompt would reintroduce the unbounded
# artifact through a side channel while the budget check still reported success.
# ---------------------------------------------------------------------------

REVIEW_ROUND_TMPDIR="${REVIEW_ROUND_TMPDIR:-}"

_review_round_cleanup() {
  [ -z "${REVIEW_ROUND_TMPDIR:-}" ] || rm -rf "$REVIEW_ROUND_TMPDIR"
}

# The caller's EXIT handler, saved so installing ours does not DESTROY it.
# Silently clobbering EXIT is not a theoretical concern: it makes a failing bats
# test report nothing at all, so an assertion added to such a test would be
# inert — and a driver that had its own cleanup would simply lose it.
_REVIEW_PRIOR_EXIT="${_REVIEW_PRIOR_EXIT:-}"

_review_fire_prior_exit() {
  local spec="${_REVIEW_PRIOR_EXIT:-}" body raw
  [ -n "$spec" ] || return 0
  _REVIEW_PRIOR_EXIT=""          # fire once, never recurse
  body="${spec#trap -- }"
  body="${body% EXIT}"
  # `trap -p` emits a re-evalable single-quoted word, which is why this is a
  # quoting-safe unwrap rather than a hopeful one.
  eval "raw=$body" 2>/dev/null || return 0
  eval "$raw" || true
}

# review_round_tmpdir — create the round's 0700 temp directory, set
# REVIEW_ROUND_TMPDIR, and install the cleanup trap IMMEDIATELY after creation.
#
# It sets a variable rather than echoing the path ON PURPOSE. A caller writing
# `d="$(review_round_tmpdir)"` would install the trap inside the command
# substitution's subshell, which exits at once — deleting the directory before
# the round could use it. There is no spelling of this helper that is safe to
# call in a subshell, so it does not offer one.
#
# The trap covers EXIT HUP INT TERM, so a crash cannot leave a full review
# prompt on disk indefinitely. It CANNOT cover SIGKILL — that is a stated
# boundary, not an oversight: `kill -9` leaves the directory behind.
review_round_tmpdir() {
  REVIEW_ROUND_TMPDIR="$(mktemp -d)"
  chmod 700 "$REVIEW_ROUND_TMPDIR"
  _REVIEW_PRIOR_EXIT="$(trap -p EXIT)"
  trap '_review_round_cleanup; _review_fire_prior_exit' EXIT
  trap '_review_round_cleanup; _review_fire_prior_exit; exit 130' HUP INT TERM
}

# review_materialize_payload <artifact> <composer-command…>
# — run the composer with stdout REDIRECTED into a single mode-0600 artifact,
# and echo the artifact's byte count.
#
# Redirected, never captured: `bytes="$(compose)"` would strip the trailing
# newlines and the measured count would then describe bytes nobody dispatches.
# An artifact that already exists is REFUSED rather than overwritten, which is
# the single-materialization invariant enforced where it can actually be checked.
review_materialize_payload() {
  local art="${1:-}"
  [ -n "$art" ] || { review_error "review_materialize_payload: artifact path required"; return 1; }
  shift
  [ "$#" -gt 0 ] || { review_error "review_materialize_payload: a composer command is required"; return 1; }
  [ ! -e "$art" ] || {
    review_error "review_materialize_payload: refusing to materialize twice — '$art' already exists"
    return 1
  }
  ( umask 077; : > "$art" ) || return 1
  chmod 600 "$art"
  # The instrumented seam AC11 counts. Bounded to NAMED call sites: an unbounded
  # "no copy anywhere on the filesystem" check would be the vacuous negative
  # this spec argues against.
  [ -z "${REVIEW_MATERIALIZE_LOG:-}" ] || printf 'materialize %s\n' "$art" >> "$REVIEW_MATERIALIZE_LOG"
  "$@" > "$art" || {
    review_error "review_materialize_payload: composer failed; '$art' is incomplete"
    return 1
  }
  LC_ALL=C wc -c < "$art" | tr -d ' '
}

# review_seam_single_creation <log> — exit 0 iff exactly one payload artifact was
# created this round, naming every creation otherwise.
review_seam_single_creation() {
  local log="${1:-}" n
  [ -n "$log" ] && [ -f "$log" ] || {
    review_error "review_seam_single_creation: instrumentation log not found: '${log:-}'"; return 1; }
  n="$(grep -c . "$log" || true)"
  [ "$n" = "1" ] || {
    review_error "review_seam_single_creation: expected exactly ONE payload materialization this round, found $n:"
    review_error "$(cat -- "$log")"
    return 1
  }
  return 0
}

# ---------------------------------------------------------------------------
# Spec 0054 ACs 22 / 22a — review-code's ONE frozen diff.
#
# `spec:review-code` used to tell each agent to collect "the diff" itself. The
# working tree is live while a round runs, so two reviewers dispatched a second
# apart could review different bytes — and then a disagreement between them is
# indistinguishable from a disagreement about the same change. It also makes
# the payload digest a `subagent` attests (AC16) meaningless, because the thing
# hashed would be recomputed per agent.
#
# So the diff is frozen ONCE into the round dir and every payload composes from
# that single artifact.
# ---------------------------------------------------------------------------

# review_freeze_diff <round-dir> [<base>] — compute the reviewed diff exactly
# once into <round-dir> and echo the artifact's path.
#
# `git diff HEAD` by default; `git diff <base>...HEAD` when a base ref is given.
# `git diff HEAD` is the form the spec names, and the distinction is
# load-bearing: a staged edit that the working tree reverses nets to nothing
# against HEAD, while `git diff --cached` would report it and send every
# reviewer hunting a change that does not exist.
#
# Untracked files are OUT, deliberately (AC22a). Both git forms exclude them,
# and that is the property that makes the frozen diff reproducible from a
# recorded HEAD — a snapshot that also swept in untracked files would not be.
# The exclusion is stated in the payload prose and on the round's stdout rather
# than left implicit, because a reviewer who is not told assumes the diff is
# everything that changed.
review_freeze_diff() {
  local dir="${1:-}" base="${2:-}"
  [ -n "$dir" ] || {
    review_error "review_freeze_diff: round directory required"; return 1; }
  # Options are refused rather than ignored. The obvious future request is a
  # flag that widens the scope to untracked files; silently dropping an
  # unrecognized word would freeze the narrow diff while the caller believed
  # otherwise. The offending word is named at RUNTIME and never spelled out
  # here, so the out-of-scope flag has no literal mention in the shipped tree.
  case "$base" in
    --*)
      review_error "review_freeze_diff: '$base' is not an option — this takes an optional BASE REF only."
      review_error "  Widening the reviewed scope beyond the two git diff forms is out of scope (spec 0054)."
      return 1
      ;;
  esac
  [ -d "$dir" ] || {
    review_error "review_freeze_diff: round directory not found: '$dir'"; return 1; }

  local art="$dir/branch-under-review.diff"
  # The 0052 single-creation seam, applied to the diff. A second freeze in one
  # round is exactly the defect this function exists to remove, so it is a
  # named refusal rather than an overwrite.
  [ ! -e "$art" ] || {
    review_error "review_freeze_diff: refusing to freeze twice — '$art' already exists."
    review_error "  Every reviewer in a round must receive the SAME diff bytes; compose from the existing artifact."
    return 1
  }

  # The ref is verified BEFORE the artifact is created. `git diff` with an
  # unknown ref writes nothing and fails, which would otherwise leave a
  # zero-byte artifact that composes into a payload claiming there are no
  # changes — a false clean bill of health, the worst available outcome.
  if [ -n "$base" ]; then
    git rev-parse --verify --quiet "$base^{commit}" >/dev/null 2>&1 || {
      review_error "review_freeze_diff: unknown base ref '$base' — nothing was frozen."
      return 1
    }
  fi

  ( umask 077; : > "$art" ) || return 1
  chmod 600 "$art"
  if [ -n "$base" ]; then
    git diff "$base"...HEAD > "$art" || {
      review_error "review_freeze_diff: 'git diff $base...HEAD' failed; '$art' is incomplete"
      return 1
    }
  else
    git diff HEAD > "$art" || {
      review_error "review_freeze_diff: 'git diff HEAD' failed; '$art' is incomplete"
      return 1
    }
  fi
  # An EMPTY artifact is a legitimate outcome, not an error: a clean tree is a
  # round with a verdict ("nothing to review"), and refusing here would turn
  # the common no-op case into a crash.
  printf '%s\n' "$art"
}

# review_no_active_spec_notice — the stand-in the composer gets when no spec is
# active, on stdout.
#
# review-code reviews a DIFF, so a spec is not required (AC22) — refusing
# without one would break exactly the ad-hoc change this command exists for.
# But the composer always emits a "Spec under review" heading, and an EMPTY
# stand-in would put nothing under it, which reads as a truncated payload
# rather than as a deliberate absence. So the absence is spelled out.
review_no_active_spec_notice() {
  printf 'No active spec.\n\n'
  printf 'No spec is active for this round, so the diff has no acceptance criteria\n'
  printf 'to be checked against. Review it on its own merits: correctness, the\n'
  printf 'guardrails and conventions included below, and anything it deletes or\n'
  printf 'weakens that looks load-bearing.\n\n'
  printf 'Do not treat the missing spec as a defect in the change, and do not\n'
  printf 'invent criteria for it.\n'
}

# review_payload_representable <artifact> — the stated representability boundary.
#
# The payload domain is NUL-free, valid UTF-8. A NUL byte is refused because
# POSIX argv cannot carry one, which would make the measured-equals-dispatched
# claim unimplementable for argv mode; invalid UTF-8 is refused because two
# hosts could otherwise disagree about the same bytes. The diagnostic names
# WHICH of the two failed — "unrepresentable" alone would not tell the developer
# what to look for.
review_payload_representable() {
  local f="${1:-}" total stripped
  [ -n "$f" ] && [ -f "$f" ] || {
    review_error "review_payload_representable: artifact not found: '${f:-}'"; return 1; }
  total="$(LC_ALL=C wc -c < "$f" | tr -d ' ')"
  stripped="$(LC_ALL=C tr -d '\000' < "$f" | LC_ALL=C wc -c | tr -d ' ')"
  [ "$total" = "$stripped" ] || {
    review_error "review_payload_representable: '$f' contains a NUL byte; POSIX argv cannot carry one, so this payload cannot be dispatched byte-for-byte"
    return 1
  }
  if command -v iconv >/dev/null 2>&1; then
    iconv -f UTF-8 -t UTF-8 < "$f" >/dev/null 2>&1 || {
      review_error "review_payload_representable: '$f' is not valid UTF-8"
      return 1
    }
  else
    review_error "review_payload_representable: iconv is absent, so the UTF-8 arm was NOT checked for '$f' (the NUL arm was)"
  fi
  return 0
}

# review_dispatch_bytes <artifact> — set REVIEW_DISPATCH_PAYLOAD to the artifact's
# bytes EXACTLY, trailing newlines included.
#
# `var="$(cat f)"` strips them — the same defect review_materialize_payload
# closes for composition, arriving one step later, at the file-to-argv
# conversion. `read -d ''` reads to EOF without a NUL delimiter and returns
# non-zero there while still assigning, which is why the failure is tolerated.
review_dispatch_bytes() {
  local f="${1:-}"
  [ -n "$f" ] && [ -f "$f" ] || {
    review_error "review_dispatch_bytes: artifact not found: '${f:-}'"; return 1; }
  IFS= read -r -d '' REVIEW_DISPATCH_PAYLOAD < "$f" || true
  return 0
}

# review_dispatch_payload <agent-cmd> <input-mode> <artifact>
# — send the artifact's bytes to the CLI, unmodified, by the mode's transport.
#
# `file` mode passes the ROUND'S ARTIFACT itself. Writing a tempfile here would
# be the second copy AC11 forbids, and it is the most natural place for one to
# appear.
#
# <agent-cmd> is a SPACE-JOINED command string (what review_agent_cmd emits),
# and it is expanded into a real array here rather than left as a bare `$cmd`.
# `$cmd < "$art"` relied on the shell word-splitting the expansion, which bash
# does and **zsh does not** — under zsh the entire string became one command
# name, so every cli and acp reviewer failed with "command not found" naming
# the whole command line. Both shells expand `"${cmdv[@]}"` identically, and
# macOS bash 3.2 has indexed arrays (only the associative kind is missing).
#
# The words go into the FUNCTION's positional parameters rather than a named
# array: `argv` is a zsh-reserved parameter aliased to exactly that, so the
# positional form is both the portable idiom and the one convention allows.
review_dispatch_payload() {
  local cmd="${1:-}" mode="${2:-}" art="${3:-}" rest w
  [ -n "$cmd" ] || { review_error "review_dispatch_payload: agent command required"; return 1; }
  [ -n "$art" ] && [ -f "$art" ] || {
    review_error "review_dispatch_payload: payload artifact not found: '${art:-}'"; return 1; }

  # Built into the FUNCTION's own positional parameters — one idiom that both
  # shells expand identically, with no array-indexing differences in play, and
  # nothing of the caller's touched. `$1`-`$3` are already saved in locals
  # above, so resetting them here is safe.
  set --
  rest="$cmd"
  while [ -n "$rest" ]; do
    w="${rest%% *}"
    case "$rest" in
      *' '*) rest="${rest#* }" ;;
      *)     rest="" ;;
    esac
    [ -n "$w" ] || continue
    set -- "$@" "$w"
  done
  [ "$#" -gt 0 ] || { review_error "review_dispatch_payload: agent command is empty"; return 1; }

  case "$mode" in
    ''|stdin) "$@" < "$art" ;;
    file)     "$@" --file "$art" ;;
    argv|acp)
      review_dispatch_bytes "$art" || return 1
      "$@" "$REVIEW_DISPATCH_PAYLOAD"
      ;;
    *) review_error "review_dispatch_payload: unknown input mode '$mode' (known: argv, acp, stdin, file; empty normalizes to stdin)"; return 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# Spec 0052 — the pre-dispatch byte budget.
#
# The failure this replaces is a 600 s timeout, which is the least informative
# outcome available: ten minutes per agent, no verdict, and no indication
# whether the model was slow or the prompt never fit. Oversize is discovered
# HERE, before dispatch, with a remedy specific to the limit that bit.
# ---------------------------------------------------------------------------

# argv-mode agents only. Derived from the ~70 KB working limit reported from the
# field (tessera-cdc, 2026-09-25: a 622 KB prompt passed as ONE command-line
# argument to `claude -p`, timing out inside 600 s), rounded DOWN to a power of
# two. This is a conservative POLICY FLOOR, not a guarantee of process creation:
# real ARG_MAX varies (Linux 128 KB–2 MB, macOS 256 KB) and the environment
# block counts against it. Probing `getconf ARG_MAX` was considered and
# rejected — the usable limit is not ARG_MAX, and a probe would make the refusal
# boundary vary by machine, so a review that refuses in CI would pass locally.
REVIEW_MAX_ARGV_BYTES_DEFAULT=65536

# Every agent, every input mode. Derived from MEASUREMENT, not taste: the
# largest payload observed to complete successfully against both shipped CLIs is
# this spec's own round-3 review at 197,238 bytes, and 262144 is the next power
# of two above it. A payload beyond the largest one ever seen to work is refused
# rather than attempted.
#
# RAISE-ME PROTOCOL, because a spec only modestly longer than this one would
# refuse under it: do not raise this constant to make a round go through. Raise
# it only alongside a RECORDED observation of a larger payload completing
# against both shipped CLIs — and note that the `REVIEW_MAX_PAYLOAD_BYTES`
# environment override is the documented escape hatch for a one-off, which is
# why it is validated loudly rather than silently. Discovering the bound by
# tripping a refusal in CI is the outcome this comment exists to prevent.
REVIEW_MAX_PAYLOAD_BYTES_DEFAULT=262144

# The floor an override may not go below. Below this the value is definitionally
# a config bug rather than a policy choice — the compiled default is 64 KB.
REVIEW_MIN_LIMIT_BYTES=1024

# review_effective_limit <argv|payload> — echo the limit actually in force.
#
# The env override is the sanctioned one-shot escape hatch for an oversized
# round, so a malformed one must be LEGIBLE rather than silent: it warns on
# stderr naming the offending variable and proceeds with the compiled default.
# It never aborts the review — refusing to review because a limit was mistyped
# would trade one unhelpful failure for another.
review_effective_limit() {
  local which="${1:-}" var def raw present=0
  case "$which" in
    argv)
      var=REVIEW_MAX_ARGV_BYTES; def="$REVIEW_MAX_ARGV_BYTES_DEFAULT"
      [ -z "${REVIEW_MAX_ARGV_BYTES+x}" ] || { present=1; raw="$REVIEW_MAX_ARGV_BYTES"; }
      ;;
    payload)
      var=REVIEW_MAX_PAYLOAD_BYTES; def="$REVIEW_MAX_PAYLOAD_BYTES_DEFAULT"
      [ -z "${REVIEW_MAX_PAYLOAD_BYTES+x}" ] || { present=1; raw="$REVIEW_MAX_PAYLOAD_BYTES"; }
      ;;
    *) review_error "review_effective_limit: unknown limit '${which:-}' (want argv|payload)"; return 1 ;;
  esac
  [ "$present" -eq 1 ] || { printf '%s\n' "$def"; return 0; }
  local ok=1
  case "$raw" in
    ''|*[!0-9]*) ok=0 ;;
    *) [ "$raw" -ge "$REVIEW_MIN_LIMIT_BYTES" ] || ok=0 ;;
  esac
  [ "$ok" -eq 1 ] || {
    review_error "review: $var='$raw' is not a usable limit (want a base-10 integer >= $REVIEW_MIN_LIMIT_BYTES); using the compiled default $def"
    printf '%s\n' "$def"
    return 0
  }
  printf '%s\n' "$raw"
}

# review_budget_check <bytes> <input-mode> — echo "ok" or "refuse:<reason>" and
# exit 0 in BOTH cases: a refusal is data, not a shell failure.
#
# The mode matrix is taken from what aux-delegator actually does, not from
# assumption. `acp` is argv transport because aux-delegator invokes it as
# `acpx <agent> <prompt>` — normalizing it to stdin would have exempted the one
# mode most likely to overflow. Only an EMPTY/absent mode normalizes to stdin
# (a registry entry with no `input` key); an unrecognised mode is an error, so
# the next argv transport somebody adds cannot slip in exempt.
#
# `refuse:payload-limit` wins when both are exceeded, deterministically.
review_budget_check() {
  local bytes="${1:-}" mode="${2:-}" transport payload_limit argv_limit
  case "$bytes" in
    ''|*[!0-9]*) review_error "review_budget_check: bytes must be a base-10 integer (got '${bytes:-}')"; return 1 ;;
  esac
  case "$mode" in
    ''|stdin|file) transport=stream ;;
    argv|acp)      transport=argv ;;
    *) review_error "review_budget_check: unknown input mode '$mode' (known: argv, acp, stdin, file; empty normalizes to stdin)"; return 1 ;;
  esac
  payload_limit="$(review_effective_limit payload)"
  [ "$bytes" -le "$payload_limit" ] || { printf 'refuse:payload-limit\n'; return 0; }
  if [ "$transport" = argv ]; then
    argv_limit="$(review_effective_limit argv)"
    [ "$bytes" -le "$argv_limit" ] || { printf 'refuse:argv-limit\n'; return 0; }
  fi
  printf 'ok\n'
}

# review_rank_files <f…> — echo "<bytes>  <repo-relative path>" per file,
# largest first. The refusal names what is actually big, so the developer is not
# left to guess which file to compact.
review_rank_files() {
  local f
  for f in "$@"; do
    [ -e "$f" ] || continue
    printf '%s  %s\n' "$(LC_ALL=C wc -c < "$f" | tr -d ' ')" "$(_review_repo_relative "$f")"
  done | sort -rn
}

# review_refusal_message <agent> <mode> <bytes> <reason> <ranked-files>
# — the actionable refusal. Names the agent, its input mode, the measured bytes,
# the limit exceeded (from the RUNTIME effective value, so the diagnostic cannot
# disagree with the behavior when an override is in play), the oversized files,
# and a remedy SPECIFIC to the limit: stdin fixes an argv-limit refusal and does
# nothing at all for a payload-limit one.
review_refusal_message() {
  local agent="${1:-}" mode="${2:-}" bytes="${3:-}" reason="${4:-}" ranked="${5:-}"
  local mode_label="${mode:-stdin (no input key)}" argv_limit payload_limit line
  printf "review: REFUSING to dispatch '%s' — checked BEFORE the round runs, so this\n" "$agent"
  printf '  is a named refusal rather than a 600 s timeout with no explanation.\n'
  printf '  composed payload: %s bytes\n' "$bytes"
  printf '  input mode: %s\n' "$mode_label"
  case "$reason" in
    refuse:argv-limit)
      argv_limit="$(review_effective_limit argv)"
      printf '  over the ARGV limit of %s bytes (the whole prompt goes as ONE argument)\n' "$argv_limit"
      ;;
    refuse:payload-limit)
      payload_limit="$(review_effective_limit payload)"
      printf '  over the PAYLOAD limit of %s bytes (applies to every agent and every mode)\n' "$payload_limit"
      case "$mode" in
        argv|acp)
          argv_limit="$(review_effective_limit argv)"
          if [ "$bytes" -gt "$argv_limit" ]; then
            printf '  also over the ARGV limit of %s bytes — but that is not the binding\n' "$argv_limit"
            printf '  constraint here, and switching transport would not lift this refusal.\n'
          fi
          ;;
      esac
      ;;
    *) review_error "review_refusal_message: unknown reason '${reason:-}'"; return 1 ;;
  esac
  if [ -n "$ranked" ]; then
    printf '  largest inline files:\n'
    printf '%s\n' "$ranked" | while IFS= read -r line; do
      [ -n "$line" ] && printf '    %s\n' "$line"
    done
  fi
  case "$reason" in
    refuse:argv-limit)
      printf '  REMEDY: switch this agent to stdin in .speccraft/agents.toml:\n\n'
      printf '      input = "stdin"\n\n'
      printf '    stdin is not subject to the argv limit. Repos already initialized own\n'
      printf '    their .speccraft/agents.toml and are never rewritten, so the shipped\n'
      printf "    template's stdin default does not reach this repo on its own.\n"
      ;;
    refuse:payload-limit)
      printf '  REMEDY: compact the oversized memory files named above, or review a\n'
      printf '    shorter spec. Changing the input mode does NOT help — a stdin-mode agent is still refused above the payload limit.\n'
      printf '    For a legitimate one-off, REVIEW_MAX_PAYLOAD_BYTES is the sanctioned\n'
      printf '    escape hatch; raising the compiled default instead requires a recorded\n'
      printf '    observation of a larger payload completing against both shipped CLIs.\n'
      ;;
  esac
}

# ---------------------------------------------------------------------------
# Spec 0052 — the single composer.
# ---------------------------------------------------------------------------

# _review_each_path <newline-separated-list> — emit the non-empty entries.
_review_each_path() {
  printf '%s' "$1" | while IFS= read -r p; do
    [ -n "$p" ] && printf '%s\n' "$p"
  done
  return 0
}

# review_compose_payload <template> <spec-src>
#     --inline <f…> --reference <f…> --digest-out <path>
#     [--diff <diff>] [--changed <sections>]
# — emit the composed reviewer payload on STDOUT.
#
# This is the SOLE composer for both the full round and the spec-0035 scoped
# `--diff` round, which is why the template substitution and the evidence
# attachment live here: one place decides what bytes are sent, so the budget
# measures the bytes that are dispatched rather than a close-enough approximation.
#
# It writes NO payload file. The command driver redirects this stream once into
# the round's single mode-0600 artifact (AC10) — redirected, never captured into
# a variable, because command substitution strips trailing newlines and would
# make measured and dispatched bytes differ silently. The `--digest-out` sidecar
# is the one other thing it writes, and it never enters the payload (AC6): if
# the reviewer could see the expected digest it could echo it without opening
# the file, which is the read-sentinel theatre review round 3 killed.
#
# Path policy, per tier:
#   --reference  must classify as reference-tier and must EXIST. A named-but-
#                missing file is an error, never a quietly smaller payload.
#   --inline     must not classify as reference-tier (AC2) and must exist. A
#                path outside the tier table is permitted here — that is how the
#                prior review.md rides along as scoped-round evidence — and a
#                typo cannot hide in that allowance, because it will not exist.
_review_compose_payload_stream() {
  local template="${1:-}" spec_src="${2:-}"
  [ -n "$template" ] && [ -f "$template" ] || {
    review_error "review_compose_payload: template not found: '${template:-}'"; return 1; }
  [ -n "$spec_src" ] && [ -f "$spec_src" ] || {
    review_error "review_compose_payload: spec source not found: '${spec_src:-}'"; return 1; }
  shift 2

  local mode="" digest_out="" diff="" changed=""
  # The default is byte-identical to the literal this composer carried before
  # `--label` existed, because spec 0052's payload rows assert those bytes.
  local label="Spec under review (frozen for this round)"
  local label_seen=0
  local inline_set="" reference_set="" nl=$'\n'
  while [ $# -gt 0 ]; do
    case "$1" in
      --inline)     mode=inline ;;
      --reference)  mode=reference ;;
      --digest-out) digest_out="${2:-}"; shift; mode="" ;;
      --diff)       diff="${2:-}"; shift; mode="" ;;
      --changed)    changed="${2:-}"; shift; mode="" ;;
      --label)      label="${2:-}"; label_seen=1; shift; mode="" ;;
      --*) review_error "review_compose_payload: unknown option '$1'"; return 1 ;;
      *)
        case "$mode" in
          inline)    inline_set="${inline_set}${1}${nl}" ;;
          reference) reference_set="${reference_set}${1}${nl}" ;;
          *) review_error "review_compose_payload: unexpected argument '$1' (expected --inline/--reference first)"; return 1 ;;
        esac
        ;;
    esac
    shift
  done
  [ -n "$digest_out" ] || {
    review_error "review_compose_payload: --digest-out <path> is required (the digests must travel OUTSIDE the payload)"
    return 1
  }
  # An explicitly EMPTY label is refused rather than composed. `## ` with
  # nothing after it reads to the reviewer as a composer bug, and it is exactly
  # what an unset shell variable at the call site produces.
  [ "$label_seen" -eq 0 ] || [ -n "$label" ] || {
    review_error "review_compose_payload: --label requires a non-empty value (an empty label composes a bare '## ' heading)"
    return 1
  }

  # Validate EVERY path before reading any of them, so a failure late in the
  # reference set cannot leave a half-written digest sidecar behind.
  local p tier rc
  while IFS= read -r p; do
    rc=0; tier="$(review_context_tier "$p" 2>/dev/null)" || rc=$?
    if [ "$rc" -eq 0 ] && [ "$tier" = "reference" ]; then
      review_error "review_compose_payload: '$p' is a reference-tier file and must not be pasted inline"
      return 1
    fi
    [ -e "$p" ] || { review_error "review_compose_payload: inline file not found: '$p'"; return 1; }
  done < <(_review_each_path "$inline_set")
  while IFS= read -r p; do
    rc=0; tier="$(review_context_tier "$p" 2>/dev/null)" || rc=$?
    [ "$rc" -eq 0 ] && [ "$tier" = "reference" ] || {
      review_error "review_compose_payload: '$p' is not a reference-tier file"; return 1; }
    [ -e "$p" ] || { review_error "review_compose_payload: reference file not found: '$p'"; return 1; }
  done < <(_review_each_path "$reference_set")

  : > "$digest_out"

  # 1. the template, with the scoped-round markers substituted. Unset values
  #    substitute to EMPTY rather than surviving: a payload carrying a literal
  #    {{DIFF}} would be a reviewer-visible bug.
  local line
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      '{{DIFF}}')             printf '%s\n' "$diff" ;;
      '{{CHANGED_SECTIONS}}') printf '%s\n' "$changed" ;;
      *)                      printf '%s\n' "$line" ;;
    esac
  done < "$template"

  # 2. the document under review, from the round's frozen image. The composer
  #    never names spec.md — it reads only the path it is given (AC16).
  #
  #    The heading is the caller's `--label`, because two of AC8's five branches
  #    do not review a spec at all: arch holds a `design.md` and pm a
  #    `brief.md`. Calling those "Spec under review" tells the reviewer to go
  #    looking for acceptance criteria a product brief does not have, and sends
  #    it hunting a document that is not in the payload.
  printf '\n## %s\n\n' "$label"
  cat -- "$spec_src"

  # 3. each inline file, in full, under its repo-relative path.
  while IFS= read -r p; do
    printf '\n## File: %s\n\n' "$(_review_repo_relative "$p")"
    cat -- "$p"
  done < <(_review_each_path "$inline_set")

  # 4. the reference records: path, byte size and heading index — never a body.
  printf '\n## Reference files (read these yourself)\n\n'
  if [ -z "$reference_set" ]; then
    # Emitted, never omitted: a reviewer must be able to tell "none were sent"
    # from "the section was dropped by a bug" (AC7).
    printf '(none) — no reference-tier files were sent this round.\n'
    return 0
  fi
  printf 'These files are NOT pasted. Open each path below with your own tools,\n'
  printf 'read what you need, and return its sha256 in `reference_access`. Report\n'
  printf 'any you could not read in `reference_access_failures` — a verdict given\n'
  printf 'without a matching digest for every path does not count.\n\n'
  local rec first heads size digest rel
  while IFS= read -r p; do
    rec="$(_review_scan_reference "$p")" || return 1
    first="${rec%%$nl*}"
    heads=""
    case "$rec" in *"$nl"*) heads="${rec#*$nl}" ;; esac
    size="${first%% *}"
    digest="${first#* }"
    rel="$(_review_repo_relative "$p")"
    printf '%s  %s\n' "$digest" "$rel" >> "$digest_out"
    printf -- '- path: %s\n' "$rel"
    printf '  bytes: %s\n' "$size"
    printf '  headings:\n'
    if [ -n "$heads" ]; then
      printf '%s\n' "$heads" | while IFS= read -r line; do printf '    %s\n' "$line"; done
    else
      printf '    (no ## or ### headings)\n'
    fi
    printf '\n'
  done < <(_review_each_path "$reference_set")
  return 0
}

# _review_normalize_payload_ends <file> — emit the file with its two ends
# normalized: no leading whitespace, exactly one trailing newline.
#
# AC8. The Codex companion trims the prompt it is given
# (`options.prompt?.trim()`, scripts/lib/codex.mjs:1127 in 1.0.6) and that
# cannot be switched off, so the payload's ends are pinned instead. With both
# ends fixed, the companion's trim removes exactly the final newline and
# nothing else, and "what the budget measured" differs from "what the reviewer
# read" by exactly one known byte.
#
# ONLY the ends are touched. Interior blank lines separate the payload's
# sections and must survive, or the reviewer reads a wall of text.
#
# Leading horizontal whitespace on the first content line is stripped too, not
# just leading blank lines: AC8 requires the payload to BEGIN with a
# non-whitespace byte, and an indented first template line is otherwise
# indistinguishable from a leading newline at the byte level.
#
# Buffered in awk because the last content line cannot be known until EOF. The
# payload is bounded by the review budget, so this is a few tens of KB.
_review_normalize_payload_ends() {
  LC_ALL=C awk '
    { line[NR] = $0 }
    END {
      first = 0
      for (i = 1; i <= NR; i++) {
        if (line[i] ~ /^[ \t]*$/) continue
        first = i
        break
      }
      # Nothing but whitespace: emit nothing rather than a lone newline, so a
      # caller checking for an empty payload sees one.
      if (first == 0) exit 0

      last = 0
      for (i = NR; i >= 1; i--) {
        if (line[i] ~ /^[ \t]*$/) continue
        last = i
        break
      }

      head = line[first]
      sub(/^[ \t]+/, "", head)
      printf "%s\n", head
      for (i = first + 1; i <= last; i++) printf "%s\n", line[i]
    }
  ' "$1"
}

# review_compose_payload — see _review_compose_payload_stream for the body.
#
# This wrapper exists only to normalize the composed stream's two ends (AC8),
# and it does so for EVERY branch, the early reference-less return included:
# normalization placed at the end of the composer's happy path would miss that
# branch, which returns before it.
#
# The stream goes to a FILE rather than through `$(...)`, per
# .speccraft/conventions.md §"A byte-exactness contract measures a FILE".
#
# Stated precisely, because it is tempting to overclaim: substitution here
# would NOT currently change the result. `$(...)` strips every trailing
# newline and a following `printf '%s\n'` adds exactly one back, which happens
# to be what AC8 wants — checked by routing the stream that way and watching
# all 131 payload rows still pass. The file route is used because it does not
# depend on those two effects cancelling, because a shell variable cannot hold
# a NUL byte, and because the whole payload need not sit in memory.
#
# The ASSERTIONS are a different matter: a test that measured a trailing
# newline through `$(...)` could never fail, which is why the boundary suite
# measures the file.
#
# On failure nothing is emitted: a partial payload that reached a reviewer
# would be reviewed as if complete.
review_compose_payload() {
  local _rcp_body _rcp_rc=0
  _rcp_body="$(mktemp)"
  _review_compose_payload_stream "$@" > "$_rcp_body" || _rcp_rc=$?
  if [ "$_rcp_rc" -ne 0 ]; then
    rm -f "$_rcp_body"
    return "$_rcp_rc"
  fi
  _review_normalize_payload_ends "$_rcp_body"
  rm -f "$_rcp_body"
}

# ---------------------------------------------------------------------------
# Spec 0052 — reference-read attestation, and the registry capability flag.
#
# Handing a reviewer a path is only useful if the dispatched process can open
# files at the dispatched cwd. If it cannot, the reviewer critiques a file it
# never read and returns a plausible-looking verdict — a WORSE failure than the
# timeout it replaces, because a timeout is at least legible.
#
# An earlier design used a read SENTINEL: a token in each reference record for
# the reviewer to echo. That attested nothing — the sentinel is IN the prompt, so
# echoing it proves only that the reviewer read the prompt. The replacement is a
# digest the reviewer COMPUTES, with the expected value deliberately withheld
# from the payload, because a digest cannot be produced without the bytes.
#
# What this proves, precisely: a process with filesystem access at the dispatched
# cwd obtained those bytes. It does NOT prove the model reasoned over them — a
# reviewer could checksum a path without ever bringing the content into context.
# The weaker guarantee is the intended one: it converts "this agent cannot read
# files at all, and nobody noticed" from an invisible failure into a mechanical
# one, which is the failure actually reported from the field.
# ---------------------------------------------------------------------------

# _review_parse_reference_access <file> — emit a flat, ordered token stream:
#   HAS-ACCESS                 once, if a reference_access key appears at all
#   ACCESS-PATH <path>         one per list entry, in order
#   ACCESS-SHA <digest>        the digest following a path, if any
#   FAIL-PATH <path>           one per reference_access_failures entry
#   PAYLOAD-SHA <digest>       the payload_sha256 a subagent attests (spec 0054)
#   PERMISSION-DENIED <tool>   a tool the reviewer was refused mid-review
#
# Tolerant of how the shipped CLIs actually wrap YAML — fenced in ```yaml with
# free-form prose after, values quoted or bare, empty lists written inline as
# `[]`. A parser too strict for the real wrapping would fail EVERY verdict, and
# the symptom would look identical to a fleet of unreadable references. The
# captured round-1..6 corpus under tests/hooks/fixtures is what pins that.
_review_parse_reference_access() {
  local file="${1:-}"
  [ -n "$file" ] && [ -f "$file" ] || {
    review_error "_review_parse_reference_access: file not found: '${file:-}'"; return 1; }
  LC_ALL=C awk '
    function scalar(s,   v) {
      sub(/^[^:]*:[ \t]*/, "", s)
      if (substr(s, 1, 1) == "\"") {
        if (match(s, /"[^"]*"/)) return substr(s, RSTART + 1, RLENGTH - 2)
        return ""
      }
      sub(/#.*$/, "", s)
      gsub(/^[ \t]+|[ \t]+$/, "", s)
      return s
    }
    # Both at column 0, and both END any open block — they are siblings of
    # reference_access, not entries within it.
    /^[ \t]*payload_sha256:/ { print "PAYLOAD-SHA " scalar($0); blk=""; next }
    /^[ \t]*permission_denied:/ { print "PERMISSION-DENIED " scalar($0); blk=""; next }
    /^[ \t]*reference_access:[ \t]*\[\]/            { print "HAS-ACCESS"; blk=""; next }
    /^[ \t]*reference_access:[ \t]*$/               { print "HAS-ACCESS"; blk="access"; next }
    /^[ \t]*reference_access_failures:[ \t]*\[\]/   { blk=""; next }
    /^[ \t]*reference_access_failures:[ \t]*$/      { blk="fail"; next }
    # Any other key at column 0 ends the current block. List items are indented,
    # so this cannot cut a well-formed block short.
    /^[A-Za-z_]/ { blk="" }
    blk == "access" && /^[ \t]*-[ \t]*path:/ { print "ACCESS-PATH " scalar($0); next }
    blk == "access" && /^[ \t]*sha256:/      { print "ACCESS-SHA " scalar($0); next }
    blk == "fail"   && /^[ \t]*-[ \t]*path:/ { print "FAIL-PATH " scalar($0); next }
  ' "$file"
}

# review_validate_reference_access <response-file> <expected-digests-file>
# — echo "ok" and exit 0, or echo "invalid:<reason>" and exit non-zero.
#
# Validation is EXACT: every expected path present exactly once, no unknown path
# accepted, every digest equal to the composition-time value, and an empty
# reference_access_failures. A verdict failing any arm counts toward neither
# round predicate — the same rule as a timeout.
#
# Non-zero exit here, unlike review_budget_check's exit-0 refusal: a budget
# refusal is a routine policy outcome about OUR payload, while a response that
# fails validation is a fault in someone else's output.
review_validate_reference_access() {
  local resp="${1:-}" expected="${2:-}" mode="${3:-}" payload="${4:-}"
  local parsed line kind value
  [ -n "$resp" ] && [ -f "$resp" ] || {
    review_error "review_validate_reference_access: response file not found: '${resp:-}'"; return 2; }
  [ -n "$expected" ] && [ -f "$expected" ] || {
    review_error "review_validate_reference_access: expected-digests file not found: '${expected:-}'"; return 2; }

  parsed="$(_review_parse_reference_access "$resp")" || return 2

  # A refused tool is a DISPATCH failure, checked FIRST and reported on its own
  # terms. A reviewer runs under a permission model and can be refused
  # mid-review; filing that as an attestation fault would send an operator to
  # inspect the reviewer's digests when the fix is a tool grant. It is also why
  # this arm precedes the HAS-ACCESS check: a reviewer denied Bash could not
  # compute a digest at all, so its response legitimately carries no
  # reference_access.
  #
  # The TOKEN is per mode, because the remedy is per mode. A subagent is
  # refused by the ORCHESTRATOR's permission model, so the fix is a grant in
  # the command's `allowed-tools`. Any other reviewer is refused by its own CLI
  # invocation, so the fix is in that agent's `cmd` — this repo's registry
  # carries `--allowedTools … Bash(shasum:*)` on `claude -p` for exactly that
  # reason. Emitting `subagent-permission-denied` for a cli refusal sent the
  # operator to edit the wrong file; the arm was not mode-gated at all, and the
  # AC16 rows only ever exercised `subagent`, so nothing caught it.
  # Found by cross-model review, round 6.
  local denied
  denied="$(printf '%s\n' "$parsed" | awk '$1 == "PERMISSION-DENIED" { $1 = ""; sub(/^[ \t]+/, ""); print; exit }')"
  if [ -n "$denied" ]; then
    if [ "$mode" = subagent ]; then
      review_error "review: the subagent was denied the tool '$denied' mid-review; grant it in the command's allowed-tools"
      printf 'failed subagent-permission-denied %s\n' "$denied"
    else
      review_error "review: the reviewer was denied the tool '$denied' mid-review; grant it in this agent's cmd in agents.toml"
      printf 'failed permission-denied %s\n' "$denied"
    fi
    return 1
  fi

  printf '%s\n' "$parsed" | grep -q '^HAS-ACCESS$' || { printf 'invalid:absent\n'; return 1; }

  # The payload digest, for `subagent` mode only (spec 0054 AC16).
  #
  # A subagent reads the payload from a FILE in the round dir rather than
  # receiving it on a transport speccraft controls, so it attests WHICH BYTES
  # it read. Without this, a reviewer that opened the wrong path — or a stale
  # payload left by an earlier round — returns a verdict about something other
  # than what was sent, and every other attestation arm still passes.
  #
  # Scoped to subagent: a cli or acp reviewer is handed the bytes directly, so
  # there is nothing for it to confuse them with, and spec 0052's contract for
  # those modes is unchanged.
  if [ "$mode" = "subagent" ]; then
    [ -n "$payload" ] && [ -f "$payload" ] || {
      review_error "review_validate_reference_access: mode subagent requires the payload file"
      return 2
    }
    local claimed want
    claimed="$(printf '%s\n' "$parsed" | awk '$1 == "PAYLOAD-SHA" { print $2; exit }')"
    [ -n "$claimed" ] || {
      review_error "review: the subagent attested no payload_sha256"
      printf 'invalid:missing-payload-digest\n'
      return 1
    }
    want="$(review_digest "$payload" | awk '{print $1}')"
    [ "$claimed" = "$want" ] || {
      review_error "review: payload digest mismatch (attested $claimed, payload is $want)"
      printf 'invalid:payload-digest-mismatch\n'
      return 1
    }
  fi
  if printf '%s\n' "$parsed" | grep -q '^FAIL-PATH '; then
    review_error "review: the reviewer reported it could not read a reference file"
    printf 'invalid:read-failure\n'; return 1
  fi

  # Pair the stream up. A path with no digest before the next path — or at end of
  # stream — is malformed, not merely unmatched.
  local pending="" got="" nl=$'\n'
  while IFS= read -r line; do
    kind="${line%% *}"; value="${line#* }"
    case "$kind" in
      ACCESS-PATH)
        [ -z "$pending" ] || { printf 'invalid:malformed\n'; return 1; }
        pending="$value"
        ;;
      ACCESS-SHA)
        [ -n "$pending" ] || { printf 'invalid:malformed\n'; return 1; }
        got="${got}${pending} ${value}${nl}"
        pending=""
        ;;
    esac
  done <<EOF
$parsed
EOF
  [ -z "$pending" ] || { printf 'invalid:malformed\n'; return 1; }

  local p d seen="" expect_paths="" ep ed
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    ed="${line%% *}"; ep="${line##*  }"
    expect_paths="${expect_paths}${ep}${nl}"
  done < "$expected"

  # Duplicates first: one read presented twice could otherwise cover a path the
  # reviewer never opened.
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    p="${line%% *}"
    case "$nl$seen" in *"$nl$p$nl"*) printf 'invalid:duplicate-path\n'; return 1 ;; esac
    seen="${seen}${p}${nl}"
  done <<EOF
$got
EOF

  # Then: no unknown path, then no missing path, then every digest matching.
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    p="${line%% *}"
    case "$nl$expect_paths" in
      *"$nl$p$nl"*) ;;
      *) review_error "review: reviewer attested an unexpected path '$p'"; printf 'invalid:unknown-path\n'; return 1 ;;
    esac
  done <<EOF
$got
EOF
  while IFS= read -r ep; do
    [ -n "$ep" ] || continue
    case "$nl$seen" in
      *"$nl$ep$nl"*) ;;
      *) review_error "review: reviewer returned no digest for '$ep'"; printf 'invalid:missing-path\n'; return 1 ;;
    esac
  done <<EOF
$expect_paths
EOF
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    p="${line%% *}"; d="${line#* }"
    ed="$(grep -F "  $p" "$expected" | head -1)"; ed="${ed%% *}"
    [ "$d" = "$ed" ] || {
      review_error "review: digest mismatch for '$p' (the file changed between composition and review, or was never read)"
      printf 'invalid:digest-mismatch\n'; return 1
    }
  done <<EOF
$got
EOF
  printf 'ok\n'
}

# ---------------------------------------------------------------------------
# AC17 — two byte-identical artifacts are a dispatch failure, not two verdicts.
#
# This is the false-quorum bug the whole programme started from. If two
# reviewers' `.out` files are byte-identical, the round did not consult two
# models: something dispatched one reviewer twice, or wrote one response to
# both paths. Counting them as agreement reports a quorum of N for a round that
# asked one model once — the most misleading output this system can produce,
# because it is indistinguishable from genuine consensus.
#
# Spec 0052 left this as runbook PROSE ("hash-compare the outputs before
# counting them"), which nothing enforced.
# ---------------------------------------------------------------------------

# review_hash_compare_outputs <round-dir> — zero when every `<agent>.out` in
# the round is distinct; non-zero naming each colliding PAIR otherwise.
#
# Compared by digest over the FILES, not over captured strings: the codex
# adapter and the dispatcher both pass rawOutput through `$(...)`, which strips
# every trailing newline, and then print one back. Two responses differing only
# in trailing whitespace therefore arrive byte-identical, and a comparison on
# captured values would see a difference the reviewers' real bytes do not have.
#
# Pairwise, not "all equal": a round of three where two collide is still a
# dispatch bug, and the pair has to be named rather than the odd one out.
review_hash_compare_outputs() {
  local dir="${1:-}"
  [ -n "$dir" ] && [ -d "$dir" ] || {
    review_error "review_hash_compare_outputs: round dir not found: '${dir:-}'"
    return 2
  }

  local f agent digest table="" line other_agent other_digest found=0
  for f in "$dir"/*.out; do
    [ -f "$f" ] || continue
    agent="${f##*/}"; agent="${agent%.out}"
    digest="$(review_digest "$f")" || return 2
    # Walk what we have so far, so the FIRST member of a colliding pair is
    # named alongside the one that collided with it.
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      other_digest="${line%% *}"
      other_agent="${line#* }"
      [ "$other_digest" = "$digest" ] || continue
      review_error "review: '$other_agent' and '$agent' returned BYTE-IDENTICAL output ($digest)."
      review_error "  That is a dispatch fault, not agreement: one model was asked once and recorded twice."
      printf '%s %s\n' "$other_agent" "$agent"
      found=1
    done <<EOF
$table
EOF
    table="${table}${digest} ${agent}
"
  done
  [ "$found" -eq 0 ] || return 1
  return 0
}

# review_hash_collision_outcomes <round-dir> <outcomes-file> — rewrite every
# colliding reviewer's record to `failed duplicate-output`.
#
# Reporting a collision is not enough. Unless the records are actually changed,
# the round still counts both as approvals and still reports consensus — with
# the diagnostic printed harmlessly beside it. Both members of a pair are
# failed, because the digest cannot say which one is the duplicate.
review_hash_collision_outcomes() {
  local dir="${1:-}" outcomes="${2:-}"
  [ -n "$dir" ] && [ -d "$dir" ] || {
    review_error "review_hash_collision_outcomes: round dir not found: '${dir:-}'"
    return 2
  }
  [ -n "$outcomes" ] && [ -f "$outcomes" ] || {
    review_error "review_hash_collision_outcomes: outcomes file not found: '${outcomes:-}'"
    return 2
  }

  local pairs rc=0
  pairs="$(review_hash_compare_outputs "$dir" 2>/dev/null)" || rc=$?
  [ "$rc" -ne 2 ] || return 2
  [ -n "$pairs" ] || return 0

  # The set of implicated agents, one per line.
  local bad="" a b line
  while IFS=' ' read -r a b; do
    [ -n "$a" ] || continue
    bad="${bad}${a}
${b}
"
  done <<EOF
$pairs
EOF

  local tmp agent rest
  tmp="$(mktemp)" || return 2
  while IFS= read -r line || [ -n "$line" ]; do
    [ -n "$line" ] || continue
    agent="${line%% *}"
    rest="${line#* }"
    if printf '%s\n' "$bad" | grep -qxF -- "$agent"; then
      printf '%s failed duplicate-output\n' "$agent" >> "$tmp"
    else
      printf '%s\n' "$line" >> "$tmp"
    fi
  done < "$outcomes"
  cat -- "$tmp" > "$outcomes"
  rm -f "$tmp"
  return 1
}

# review_attestation_outcome <validator-token> — map what
# review_validate_reference_access emits to the token a round RECORDS.
#
# The validator's own vocabulary is spec 0052's `invalid:<reason>`, and the
# acceptance criteria name the recorded outcomes `attestation-failed
# <reason>` — `attestation-failed missing-payload-digest`, not
# `attestation-failed invalid:missing-payload-digest`. Nothing performed that
# translation: each command body interpolated the raw token, so every recorded
# attestation failure carried a spurious `invalid:` prefix.
#
# It survived because the AC16 rows asserted the reason as a SUBSTRING
# (`grep -qF missing-payload-digest`), which the prefixed form satisfies. The
# rows now assert the exact recorded line through this function, which is the
# only shape that can tell the two apart. Found by cross-model review, round 6.
#
# A `failed …` token is a DISPATCH failure and passes through unchanged: it is
# already a complete outcome and is deliberately not an attestation fault.
review_attestation_outcome() {
  local token="${1:-}"
  case "$token" in
    ok)
      printf 'ok\n'
      ;;
    invalid:*)
      printf 'attestation-failed %s\n' "${token#invalid:}"
      ;;
    'failed '*)
      printf '%s\n' "$token"
      ;;
    *)
      review_error "review_attestation_outcome: unrecognised validator token '${token:-}' (want ok, invalid:<reason> or 'failed <reason>')"
      return 1
      ;;
  esac
}

# ---------------------------------------------------------------------------
# Spec 0052 — per-agent registry reads.
#
# PER AGENT, never a whole-file grep: a whole-file answer would report the first
# entry's `input` for every agent, which is exactly how an agent added later with
# `argv` slips past the shipped-template check.
# ---------------------------------------------------------------------------

# review_agent_names <agents.toml> — echo each [[agents]] name, in file order.
review_agent_names() {
  local toml="${1:-}"
  [ -n "$toml" ] && [ -f "$toml" ] || { review_error "review_agent_names: not found: '${toml:-}'"; return 1; }
  LC_ALL=C awk '
    function scalar(s) {
      sub(/^[^=]*=[ \t]*/, "", s)
      if (substr(s, 1, 1) == "\"") {
        if (match(s, /"[^"]*"/)) return substr(s, RSTART + 1, RLENGTH - 2)
        return ""
      }
      sub(/#.*$/, "", s); gsub(/^[ \t]+|[ \t]+$/, "", s); return s
    }
    /^[ \t]*\[\[agents\]\]/ { inblk = 1; next }
    /^[ \t]*\[/             { inblk = 0 }
    inblk && /^[ \t]*name[ \t]*=/ { print scalar($0) }
  ' "$toml"
}

# review_agent_field <agents.toml> <agent> <key> — echo the value, or nothing.
review_agent_field() {
  local toml="${1:-}" agent="${2:-}" key="${3:-}"
  [ -n "$toml" ] && [ -f "$toml" ] || { review_error "review_agent_field: not found: '${toml:-}'"; return 1; }
  [ -n "$agent" ] && [ -n "$key" ] || { review_error "review_agent_field: agent and key required"; return 1; }
  LC_ALL=C awk -v want="$agent" -v key="$key" '
    function scalar(s) {
      sub(/^[^=]*=[ \t]*/, "", s)
      if (substr(s, 1, 1) == "\"") {
        if (match(s, /"[^"]*"/)) return substr(s, RSTART + 1, RLENGTH - 2)
        return ""
      }
      sub(/#.*$/, "", s); gsub(/^[ \t]+|[ \t]+$/, "", s); return s
    }
    function flush() {
      if (name == want && val != "") print val
      name = ""; val = ""
    }
    /^[ \t]*\[\[agents\]\]/ { flush(); inblk = 1; next }
    /^[ \t]*\[/             { flush(); inblk = 0 }
    inblk && /^[ \t]*name[ \t]*=/ { name = scalar($0); next }
    inblk {
      k = $0
      sub(/=.*$/, "", k)
      gsub(/[ \t]/, "", k)
      if (k == key) val = scalar($0)
    }
    END { flush() }
  ' "$toml"
}

# review_agent_cmd <agents.toml> <agent> — echo the agent's command as a
# space-separated word list.
#
# `review_agent_field` returns the RAW value, and for `cmd` that is TOML array
# text: passing `["codex", "exec", "--full-auto"]` to review_dispatch_payload
# would try to exec `["codex",`. This flattens it to `codex exec --full-auto`.
# Arguments containing whitespace are out of scope — no shipped entry has one,
# and a word list cannot represent it.
review_agent_cmd() {
  local raw
  raw="$(review_agent_field "$1" "$2" cmd)" || return 1
  [ -n "$raw" ] || return 0
  LC_ALL=C awk -v s="$raw" '
    BEGIN {
      n = 0
      while (match(s, /"[^"]*"/)) {
        printf "%s%s", (n++ ? " " : ""), substr(s, RSTART + 1, RLENGTH - 2)
        s = substr(s, RSTART + RLENGTH)
      }
      if (n == 0) printf "%s", s
      printf "\n"
    }'
}

# review_agent_argv <agents.toml> <agent> — emit the command's argv, ONE WORD
# PER LINE, losslessly.
#
# review_agent_cmd joins the same words with a space, which is what every
# consumer wants and is lossy for exactly one input: an argv element that
# itself contains a space. That element cannot survive a space-joined string,
# and `review_dispatch_payload`'s signature is frozen at
# `<cmd> <input-mode> <artifact>` (spec 0052), so the words cannot be handed to
# it in a richer form.
#
# Rather than mangle such an entry into two arguments and dispatch something
# nobody wrote, `review_dispatch_agent` uses this to DETECT the case and refuse
# by name. Every real registry — `["codex", "exec", "--sandbox",
# "workspace-write"]`, `["claude", "-p", "--allowedTools", …]` — is unaffected.
review_agent_argv() {
  local raw
  raw="$(review_agent_field "$1" "$2" cmd)" || return 1
  [ -n "$raw" ] || return 0
  LC_ALL=C awk -v s="$raw" '
    BEGIN {
      n = 0
      while (match(s, /"[^"]*"/)) {
        print substr(s, RSTART + 1, RLENGTH - 2)
        n++
        s = substr(s, RSTART + RLENGTH)
      }
      if (n == 0) print s
    }'
}

# review_agent_reference_read <agents.toml> <agent> — echo "true" | "false".
#
# OPT-OUT: an ABSENT flag means true. Making absence mean "incapable" would have
# been an operationally breaking upgrade — every already-initialized repo lacks
# the key, so every configured reviewer would become ineligible on the first
# `git pull`. Only an explicit `reference_read = false` refuses reference-tier
# dispatch.
review_agent_reference_read() {
  local flag
  flag="$(review_agent_field "$1" "$2" reference_read)" || return 1
  case "$flag" in
    false) printf 'false\n' ;;
    *)     printf 'true\n' ;;
  esac
}

# ---------------------------------------------------------------------------
# Spec 0054 — dispatch modes. The shell half of the registry reader.
#
# The Go loader (tools/internal/delegate/toml.go) and these helpers must agree
# entry-for-entry; the shared parity corpus is what holds them together.
# ---------------------------------------------------------------------------

# review_agent_keys <agents.toml> <agent> — echo the keys the named entry
# DEFINES, one per line, in document order.
#
# Presence, not value — and that distinction is the whole reason this exists.
# review_agent_field returns a value only `if (val != "")`, so `mode = ""` and
# an absent `mode` are both the empty string, and AC1 requires telling them
# apart: absent normalizes to cli, an explicit empty is a named error. The
# strict-key arms need presence too, since a forbidden or unknown KEY is
# forbidden whatever its value.
#
# This is the shell analogue of the loader's agentKeySets, which exists for the
# identical reason on the Go side (toml.MetaData.IsDefined cannot address
# array-of-table elements).
#
# Continuation lines of a multi-line array are not keys: the match requires
# `<bare key> =` at the start of the line, so `  "exec",` is skipped. Same
# limitation as every other reader here — no shipped registry spans lines.
review_agent_keys() {
  local toml="${1:-}" agent="${2:-}"
  [ -n "$toml" ] && [ -f "$toml" ] || {
    review_error "review_agent_keys: not found: '${toml:-}'"; return 1; }
  [ -n "$agent" ] || { review_error "review_agent_keys: agent required"; return 1; }
  LC_ALL=C awk -v want="$agent" '
    function scalar(s) {
      sub(/^[^=]*=[ \t]*/, "", s)
      if (substr(s, 1, 1) == "\"") {
        if (match(s, /"[^"]*"/)) return substr(s, RSTART + 1, RLENGTH - 2)
        return ""
      }
      sub(/#.*$/, "", s); gsub(/^[ \t]+|[ \t]+$/, "", s); return s
    }
    # Buffered and flushed at the end of the block, because `name` may be
    # written after the keys that precede it in the entry.
    function flush() {
      if (name == want && buf != "") printf "%s", buf
      name = ""; buf = ""
    }
    /^[ \t]*\[\[agents\]\]/ { flush(); inblk = 1; next }
    /^[ \t]*\[/             { flush(); inblk = 0 }
    inblk && /^[ \t]*[A-Za-z_][A-Za-z0-9_]*[ \t]*=/ {
      k = $0
      sub(/=.*$/, "", k)
      gsub(/[ \t]/, "", k)
      if (k == "name") name = scalar($0)
      buf = buf k "\n"
    }
    END { flush() }
  ' "$toml"
}

# These four mirror delegate.ValidModes / knownAgentKeys / ValidEfforts /
# ValidSubagentModels. They are duplicated across the Go and shell readers on
# purpose — two independent implementations is what the AC4 parity corpus
# exists to hold together, and deriving one from the other would make the
# parity check circular.
REVIEW_VALID_MODES="cli acp codex-plugin subagent"
REVIEW_KNOWN_AGENT_KEYS="name mode cmd input acp_agent strengths enabled reference_read model effort plugin_root subagent_type"
REVIEW_VALID_EFFORTS="none minimal low medium high xhigh"
REVIEW_VALID_SUBAGENT_MODELS="opus sonnet haiku fable inherit"

# _review_mode_forbidden_keys <mode> — echo the keys that belong to another mode.
# Mirrors delegate.forbiddenFields; an empty echo means "not a new mode", which
# is also what scopes strict-key checking (cli/acp keep today's permissive
# read so no already-written host registry stops loading).
_review_mode_forbidden_keys() {
  case "${1:-}" in
    codex-plugin) printf 'cmd input acp_agent subagent_type\n' ;;
    subagent)     printf 'cmd input acp_agent effort plugin_root\n' ;;
    *)            printf '\n' ;;
  esac
}

# _review_agent_mode_strict <agents.toml> <agent> <mode> — the strict-key and
# enum arms, applied to the NEW modes only.
#
# Byte-identical rules to the Go loader, in the same order (forbidden keys,
# then unknown keys, then the enums), so a registry rejected by one reader is
# rejected by the other for the same reason.
_review_agent_mode_strict() {
  local toml="${1:-}" agent="${2:-}" mode="${3:-}" forbidden keys k f val list
  forbidden="$(_review_mode_forbidden_keys "$mode")"
  # Not a new mode: today's permissive read, unchanged.
  [ -n "$forbidden" ] || return 0

  keys="$(review_agent_keys "$toml" "$agent")" || return 1

  local rest_f
  rest_f="$forbidden"
  while [ -n "$rest_f" ]; do
    f="${rest_f%% *}"
    case "$rest_f" in
      *' '*) rest_f="${rest_f#* }" ;;
      *)     rest_f="" ;;
    esac
    [ -n "$f" ] || continue
    printf '%s\n' "$keys" | grep -qxF -- "$f" || continue
    review_error "review_agent_mode: agent '$agent' has mode '$mode', which does not take '$f'"
    return 1
  done

  # Unknown keys are strict here and nowhere else.
  while IFS= read -r k; do
    [ -n "$k" ] || continue
    ! _review_list_has "$k" "$REVIEW_KNOWN_AGENT_KEYS" || continue
    review_error "review_agent_mode: agent '$agent' (mode '$mode') has unknown key '$k'"
    return 1
  done <<EOF
$keys
EOF

  # Enum checks belong to the mode that OWNS the field, which is why each is
  # guarded by its mode rather than by the key's mere presence.
  #
  # Membership goes through _review_list_has, not a padded `case`. The padded
  # form matched a CONTIGUOUS SUBSTRING of the enum list, so `model =
  # "opus sonnet"` was accepted as a valid single model — it is a substring of
  # the list. Cross-model review round 6 found it; the whole-entry comparison
  # closes it, and the enum rows below pin it.
  if [ "$mode" = codex-plugin ] && printf '%s\n' "$keys" | grep -qx effort; then
    val="$(review_agent_field "$toml" "$agent" effort)" || return 1
    _review_list_has "$val" "$REVIEW_VALID_EFFORTS" || {
      review_error "review_agent_mode: agent '$agent' has effort '$val'; valid values are $(_review_list_join "$REVIEW_VALID_EFFORTS")"
      return 1
    }
  fi

  if [ "$mode" = subagent ] && printf '%s\n' "$keys" | grep -qx model; then
    val="$(review_agent_field "$toml" "$agent" model)" || return 1
    _review_list_has "$val" "$REVIEW_VALID_SUBAGENT_MODELS" || {
      review_error "review_agent_mode: agent '$agent' has model '$val'; valid values are $(_review_list_join "$REVIEW_VALID_SUBAGENT_MODELS")"
      return 1
    }
  fi
  return 0
}

# review_agent_mode <agents.toml> <agent> — echo the entry's dispatch mode.
#
# An omitted `mode` echoes `cli` (today's behaviour, which is what keeps every
# already-written registry working). An explicitly empty or unrecognised value
# is a named error naming the agent and all four valid modes, so an operator can
# fix the registry without reading this source.
#
# Case-sensitive, like the loader: a permissive reader would accept "Subagent"
# and then route on a mode no dispatcher knows.
review_agent_mode() {
  local toml="${1:-}" agent="${2:-}" keys mode m
  [ -n "$toml" ] && [ -f "$toml" ] || {
    review_error "review_agent_mode: not found: '${toml:-}'"; return 1; }
  [ -n "$agent" ] || { review_error "review_agent_mode: agent required"; return 1; }

  keys="$(review_agent_keys "$toml" "$agent")" || return 1
  # No keys at all means no such entry — distinct from an entry with no mode,
  # which is legal and normalizes to cli.
  [ -n "$keys" ] || {
    review_error "review_agent_mode: no agent named '$agent' in $toml"
    return 1
  }

  # Line-EXACT: a substring test would read a future `mode_hint` as `mode`.
  printf '%s\n' "$keys" | grep -qx 'mode' || { printf 'cli\n'; return 0; }

  mode="$(review_agent_field "$toml" "$agent" mode)" || return 1
  if _review_list_has "$mode" "$REVIEW_VALID_MODES"; then
    _review_agent_mode_strict "$toml" "$agent" "$mode" || return 1
    printf '%s\n' "$mode"
    return 0
  fi

  # Joined in shell, not by `tr`/`sed`: spec 0049 removed both from this lib and
  # the portability sweep enforces it.
  review_error "review_agent_mode: agent '$agent' has mode '$mode'; valid modes are $(_review_list_join "$REVIEW_VALID_MODES")"
  return 1
}

# review_agent_transport <agents.toml> <agent> — echo the input-mode token that
# review_budget_check takes for this entry.
#
# One question, one answer, and deliberately NOT a change to
# review_budget_check: widening that function would have touched every spec-0052
# call site and its suite. The mapping is:
#
#   codex-plugin, subagent  ⇒ file   — both write the payload to the round dir
#                                      and hand over a PATH, so neither is
#                                      bounded by argv.
#   acp                     ⇒ acp    — argv transport, because aux-delegator
#                                      invokes it as `acpx <agent> <prompt>`.
#   cli                     ⇒ the registry's `input`, defaulting to stdin.
#
# `acp` is returned as itself rather than resolved to the entry's `input`: an
# acp entry carries no `input` key, so reading one would yield the empty string,
# which review_budget_check normalizes to stdin — exempting from the argv limit
# the one mode most likely to overflow it.
review_agent_transport() {
  local toml="${1:-}" agent="${2:-}" mode input
  mode="$(review_agent_mode "$toml" "$agent")" || return 1
  case "$mode" in
    codex-plugin|subagent) printf 'file\n'; return 0 ;;
    acp)                   printf 'acp\n';  return 0 ;;
  esac
  input="$(review_agent_field "$toml" "$agent" input)" || return 1
  # Absent `input` normalizes to stdin, matching review_budget_check's own
  # treatment of an empty mode and today's behaviour for every cli entry.
  [ -n "$input" ] || input=stdin
  printf '%s\n' "$input"
}

# review_reference_read_message <agent> — the named refusal for an agent that has
# opted out of reference-tier dispatch.
review_reference_read_message() {
  local agent="${1:-}"
  printf "review: NOT dispatching a reference-tier payload to '%s' — it declares\n" "$agent"
  printf '  reference_read = false in .speccraft/agents.toml, meaning it cannot open\n'
  printf '  files at the dispatched cwd. A reviewer that cannot read a reference would\n'
  printf '  return a plausible verdict on a file it never opened, which is worse than\n'
  printf '  the timeout this budget replaces. Remove the flag once the agent can read\n'
  printf '  files, or leave it excluded from reference-tier rounds.\n'
}

# review_full_paste_bytes <template> <spec-src> <files…> — echo the byte count of
# the PRE-0052 payload shape: every context file pasted in full.
#
# Retained for exactly one purpose — it is the ratio's DENOMINATOR. The tiering
# claim is "a reviewer handed a path plus a heading index costs a fraction of a
# full paste", and a claim like that is only meaningful against the
# counterfactual it replaces. Without this function the ratio tests would
# compare the new shape to nothing and pass vacuously. It is NOT a dispatch path
# and must never be wired to one.
review_full_paste_bytes() {
  local template="${1:-}" spec_src="${2:-}" f
  [ -n "$template" ] && [ -f "$template" ] || {
    review_error "review_full_paste_bytes: template not found: '${template:-}'"; return 1; }
  [ -n "$spec_src" ] && [ -f "$spec_src" ] || {
    review_error "review_full_paste_bytes: spec source not found: '${spec_src:-}'"; return 1; }
  shift 2
  {
    cat -- "$template"
    printf '\n## Spec under review (frozen for this round)\n\n'
    cat -- "$spec_src"
    for f in "$@"; do
      [ -e "$f" ] || { review_error "review_full_paste_bytes: not found: '$f'"; return 1; }
      printf '\n## File: %s\n\n' "$(_review_repo_relative "$f")"
      cat -- "$f"
    done
  } | LC_ALL=C wc -c | tr -d ' '
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

# ---------------------------------------------------------------------------
# Spec 0054 — the codex-plugin adapter lives in a sibling lib.
#
# `_REVIEW_LIB_DIR` self-locates with the canonical idiom below — the
# BASH_SOURCE expansion WITH its `:-$0` fallback, never without it. These libs
# are sourced into the caller's shell, which on macOS is zsh, where
# BASH_SOURCE is unset and an unguarded reference aborts the whole source under
# `set -u`. bash always populates it (so the fallback never fires there) and
# zsh sets `$0` to the sourced file's path (so the fallback is exactly right
# where it does).
#
# The fallback-less spelling is not written out even in this comment: the guard
# in spec-consolidate.bats counts tokens across the file and cannot tell prose
# from code, so naming it here would flag this lib. That is how this comment
# first failed the guard.
# ---------------------------------------------------------------------------
_REVIEW_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=./review-codex.lib.sh
. "$_REVIEW_LIB_DIR/review-codex.lib.sh"

# ---------------------------------------------------------------------------
# AC13 — the mode router.
# ---------------------------------------------------------------------------

# review_dispatch_agent <agents.toml> <agent> <artifact> [cwd] [timeout-s] —
# the ONE seam every review command reaches a reviewer through.
#
# Four modes, one place. Without this the four review commands would each grow
# their own dispatch, and a mode handled wrongly would be handled wrongly four
# times. Routing is by the registry's `mode`, and the transport within `cli` is
# by its `input` (spec 0052's contract, unchanged).
#
# `subagent` is a REFUSAL here and not an oversight: a subagent can only be
# started by the orchestrating session's own tooling, never from a shell. The
# branch says so by name and writes nothing to stdout — stdout is the
# reviewer's response channel, and anything emitted there would be fed to the
# verdict parser as though a reviewer had answered.
review_dispatch_agent() {
  local toml="${1:-}" agent="${2:-}" art="${3:-}"
  local cwd="${4:-}" timeout_s="${5:-${REVIEW_TIMEOUT_S:-600}}"

  [ -n "$toml" ] && [ -f "$toml" ] || {
    review_error "review_dispatch_agent: registry not found: '${toml:-}'"
    return 2
  }
  [ -n "$agent" ] || { review_error "review_dispatch_agent: agent required"; return 2; }
  [ -n "$art" ] && [ -f "$art" ] || {
    review_error "review_dispatch_agent: payload artifact not found: '${art:-}'"
    return 2
  }
  [ -n "$cwd" ] || cwd="$(speccraft-state find-root 2>/dev/null || pwd)"

  local mode
  mode="$(review_agent_mode "$toml" "$agent")" || return 2

  case "$mode" in
    cli | acp)
      local cmd transport
      # review_agent_cmd, NOT review_agent_field: the field accessor returns the
      # RAW TOML value, and for `cmd` that is array literal text. Every real
      # registry writes `cmd = ["codex", "exec", …]` — this repo's own does — so
      # the raw form made the shell try to execute the word `["codex",` and
      # every cli and acp reviewer failed with exit 127. The existing AC13 rows
      # passed only because their fixtures used a scalar `cmd`, a shape no real
      # registry uses. Found by cross-model review, round 6; the parity suite
      # now pins both the single-word and the multi-word array form.
      cmd="$(review_agent_cmd "$toml" "$agent")" || {
        review_error "review_dispatch_agent: agent \"$agent\" (mode $mode) has no usable cmd"
        return 2
      }
      [ -n "$cmd" ] || {
        review_error "review_dispatch_agent: agent \"$agent\" (mode $mode) has no cmd"
        return 2
      }
      # An argv element containing a space cannot survive the space-joined
      # string review_dispatch_payload takes, so it is refused by name rather
      # than silently split into two arguments and dispatched as something
      # nobody wrote.
      local w
      while IFS= read -r w; do
        case "$w" in
          *' '*)
            review_error "review_dispatch_agent: agent \"$agent\" has a cmd element containing a space (\"$w\"), which this transport cannot carry; split it into separate array elements"
            return 2
            ;;
        esac
      done <<EOF
$(review_agent_argv "$toml" "$agent")
EOF
      transport="$(review_agent_transport "$toml" "$agent")" || return 2
      review_dispatch_payload "$cmd" "$transport" "$art"
      ;;
    codex-plugin)
      [ -n "${REVIEW_CODEX_LAST_ERR:-}" ] && [ -f "${REVIEW_CODEX_LAST_ERR:-}" ] \
        || REVIEW_CODEX_LAST_ERR="$(mktemp)"
      _review_codex_dispatch "$toml" "$agent" "$art" "$cwd" "$timeout_s"
      ;;
    subagent)
      review_error "review_dispatch_agent: agent \"$agent\" is mode subagent, which only the orchestrating session can dispatch; the command body must start it via its own subagent tooling, not this lib"
      return 3
      ;;
    *)
      review_error "review_dispatch_agent: unknown mode '$mode' for agent \"$agent\""
      return 2
      ;;
  esac
}

# ---------------------------------------------------------------------------
# AC18b — preflight a `subagent` reviewer's own definition before launching it.
#
# A registry entry may name any agent as its reviewer. The round reads that
# reviewer's verdict from `<round-dir>/<agent>.out`, so an agent without the
# `Write` tool CANNOT produce one: it would be launched, think for minutes, and
# return nothing, and the round would then record a missing artifact. Reading
# the agent's frontmatter first turns that into an immediate named refusal.
#
# `Edit` is the other case and is deliberately NOT fatal. It is not needed for
# the round to work, but a reviewer that can Edit can rewrite the very document
# it is judging — so it warns on stderr and dispatches anyway, because the
# operator named that agent on purpose.
# ---------------------------------------------------------------------------

# _review_frontmatter_field <file> <key> — the value of a top-level key in the
# FIRST `---`-delimited block only. Scoped to the frontmatter on purpose: an
# agent whose body documents a well-formed `tools:` list in a fenced example
# must not thereby satisfy a check about its own grants.
# Both YAML forms of a value are read: the inline `key: [A, B]` and the BLOCK
# LIST
#
#     key:
#       - A
#       - B
#
# which is equally legal frontmatter. Reading only the same-line text made a
# block list look like an ABSENT key, which took the "declares no tools, so it
# inherits everything" branch — so an agent that explicitly granted itself
# `[Read, Grep]` and no `Write` passed preflight, and the round discovered it
# only as `subagent-no-output`, after a full model run. Found by round 8.
#
# A block list is emitted space-separated, so one caller (`_review_tools_has`)
# handles both forms without caring which was written.
_review_frontmatter_field() {
  awk -v key="$2" '
    NR == 1 && $0 == "---" { inb = 1; next }
    inb && $0 == "---"     { exit }
    collecting {
      # An indented `- item` continues the list; anything else ends it.
      if ($0 ~ /^[ \t]+-[ \t]*[^ \t]/) {
        v = $0; sub(/^[ \t]*-[ \t]*/, "", v)
        sub(/[ \t]+$/, "", v)
        out = (out == "" ? v : out " " v)
        next
      }
      print out; exit
    }
    inb {
      k = $0; sub(/:.*/, "", k); gsub(/[ \t]/, "", k)
      if (k == key) {
        v = $0; sub(/^[^:]*:[ \t]*/, "", v); sub(/[ \t]+$/, "", v)
        if (v != "") { print v; exit }
        # An empty same-line value: either a genuinely empty key or the head of
        # a block list. Keep reading to find out.
        collecting = 1
        out = ""
        next
      }
    }
    END { if (collecting) print out }
  ' "$1"
}

# _review_tools_has <tools-value> <tool> — is <tool> an ELEMENT of a
# `[A, B, C]` frontmatter list? Membership, never substring: `[Read, WriteFile]`
# does not grant `Write`, and `Bash(shasum:*)` is not a bare `Bash`.
_review_tools_has() {
  local list="${1:-}" needle="${2:-}"
  # Normalize the brackets and commas to spaces, then hand off to the
  # cross-shell word walker. NOT `for item in $list`: these libs are sourced
  # into the caller's shell, which on macOS is zsh, where an unquoted parameter
  # expansion is NOT word-split — the loop would see one blob and answer "no"
  # to every tool, so a Write-less agent would pass preflight on exactly the
  # platform nobody tests on.
  #
  # Nor a padded `case " $list " in *" $needle "*)`: that puts the needle on
  # the PATTERN side, where `Bash(shasum:*)` is a glob that matches far more
  # than itself.
  list="$(printf '%s\n' "$list" | tr '[],' '   ')"
  _review_list_has "$needle" "$list"
}

# review_subagent_preflight <agents-dir> <subagent-type>
#   stdout `ok`                                        — launch it
#   stdout `failed subagent-launch <reason> [<type>]`  — do NOT launch it
#   exit 2 with a named error                          — our bug, not the
#                                                        operator's registry
#
# A refusal is DATA, like review_budget_check's: exit 0 with a token on stdout,
# so the round records it against this agent and the other reviewers still run.
# The token is a whole outcome line beginning `failed`, because the outcomes
# file is read as `<agent> <outcome> <rest>` — a bare reason in the outcome
# column would hit _review_outcome_kind's unknown-token arm and abort the round
# with exit 2 instead of recording the refusal.
review_subagent_preflight() {
  local dir="${1:-}" type="${2:-}" bare file tools
  [ -n "$dir" ] || { review_error "review_subagent_preflight: agents dir required"; return 2; }
  [ -n "$type" ] || { review_error "review_subagent_preflight: subagent type required"; return 2; }
  # A missing plugin dir and a typo'd registry entry must be DISTINGUISHABLE:
  # the first is ours to fix, the second the operator's.
  [ -d "$dir" ] || { review_error "review_subagent_preflight: agents dir not found: $dir"; return 2; }

  # Strip ONLY speccraft's own qualifier. `speccraft:reviewer` is the dispatch
  # default and the file is `agents/reviewer.md`, so a preflight that stripped
  # nothing would refuse the one reviewer this spec ships.
  #
  # But `${type##*:}` strips EVERY qualifier, and round 8 showed what that
  # costs: `otherplugin:reviewer` was approved by inspecting *speccraft's*
  # agents/reviewer.md — which has Write — while the Agent tool would launch a
  # different plugin's agent, possibly one with no Write (the exact failure
  # this check exists to prevent) or one declaring Edit (whose warning is then
  # never shown). We cannot see another plugin's definitions, so the honest
  # answer is a named refusal rather than a check of the wrong file.
  case "$type" in
    speccraft:*) bare="${type#speccraft:}" ;;
    *:*)
      printf 'failed subagent-launch unsupported-subagent-plugin %s\n' "$type"
      return 0
      ;;
    *) bare="$type" ;;
  esac
  case "$bare" in
    *:*)
      printf 'failed subagent-launch unsupported-subagent-plugin %s\n' "$type"
      return 0
      ;;
  esac
  # A subagent type is a bare file stem. Anything carrying a path separator or
  # a dot segment is a registry error, not a path to resolve — an agents dir is
  # not a jumping-off point for the rest of the filesystem.
  case "$bare" in
    ''|.|..|*/*|*'\'*)
      printf 'failed subagent-launch unknown-subagent-type %s\n' "$type"
      return 0
      ;;
  esac

  file="$dir/$bare.md"
  [ -f "$file" ] || {
    # Named, because an operator with four registry entries cannot otherwise
    # tell which one points at an agent that is not there.
    printf 'failed subagent-launch unknown-subagent-type %s\n' "$type"
    return 0
  }

  tools="$(_review_frontmatter_field "$file" tools)"
  if [ -z "$tools" ]; then
    # Omitting `tools:` grants EVERY tool, so Write is present and the round
    # works — but so are Edit and unscoped Bash. That is the operator's choice
    # to make and ours to say out loud.
    review_error "review_subagent_preflight: agent \"$bare\" declares no tools, so it inherits EVERY tool including Edit and unscoped Bash; dispatching anyway"
    printf 'ok\n'
    return 0
  fi

  # The refusal is checked FIRST. A warn-first implementation would print the
  # Edit warning, fall through to `ok`, and launch a reviewer that cannot write
  # its verdict.
  _review_tools_has "$tools" Write || {
    printf 'failed subagent-launch missing-write-tool\n'
    return 0
  }

  ! _review_tools_has "$tools" Edit || {
    review_error "review_subagent_preflight: agent \"$bare\" declares Edit, so it can rewrite the document it is reviewing; dispatching anyway"
  }
  printf 'ok\n'
}

# ---------------------------------------------------------------------------
# Spec 0054 — the round directory and tree check live in a sibling lib.
# See the note above _REVIEW_LIB_DIR for why the fallback form is used.
# ---------------------------------------------------------------------------
# shellcheck source=./review-round.lib.sh
. "$_REVIEW_LIB_DIR/review-round.lib.sh"

# ---------------------------------------------------------------------------
# ACs 23 / 23a — vendor resolution and the same-vendor approval record.
#
# With a `subagent` reviewer available, the cheapest round to configure is one
# where every reviewer is Anthropic: the subagent, plus `claude -p`. That round
# LOOKS like cross-model review and reports a quorum, but every verdict came
# from one vendor's models — and often on a spec those same models wrote.
#
# So the round records it. The flag is a RECORD, NOT A GATE:
# `approval_quorum_met` is computed exactly as spec 0052 left it, and a test
# asserts the four round predicates are byte-identical with and without the
# flag enabled. Flagging is useful; silently refusing a round the operator
# deliberately configured is not ours to do.
# ---------------------------------------------------------------------------

# The vendor table. Deliberately tiny, and matched EXACTLY on a basename — no
# substring, no prefix, no suffix. `claudex`, `claude-code`, `myclaude` and
# `claude_wrapper.sh` all resolve to `unknown`, because a predicate that
# guesses is one every implementer reimplements differently, and a wrapper
# named after a vendor is not evidence about which API it reaches.
#
# `unknown` is a legitimate answer, never treated as agreement: a round whose
# approvals all resolve to `unknown` is NOT reported single-vendor, since "they
# are the same vendor" is precisely what is not known.
_review_vendor_of_basename() {
  case "${1:-}" in
    claude) printf 'anthropic\n' ;;
    codex)  printf 'openai\n' ;;
    *)      printf 'unknown\n' ;;
  esac
}

# review_agent_vendor <agents.toml> <agent> — echo the reviewer's vendor.
#
# The two modes this spec adds are resolved BY CONSTRUCTION rather than from a
# command: a `subagent` runs inside this Claude Code session, and
# `codex-plugin` reaches the Codex companion. Their `cmd`, if any, is never
# dispatched, so a leftover one must not be able to relabel the vendor.
review_agent_vendor() {
  local toml="${1:-}" agent="${2:-}" mode cmd base
  # Errors (a missing registry, an unknown agent) propagate by NAME from
  # review_agent_mode. `unknown` means "resolved, and we cannot tell" — a typo
  # in a registry entry must not arrive dressed as that answer.
  mode="$(review_agent_mode "$toml" "$agent")" || return 1
  case "$mode" in
    subagent)     printf 'anthropic\n'; return 0 ;;
    codex-plugin) printf 'openai\n';    return 0 ;;
  esac
  cmd="$(review_agent_cmd "$toml" "$agent" 2>/dev/null)" || cmd=""
  [ -n "$cmd" ] || { printf 'unknown\n'; return 0; }
  base="${cmd%% *}"    # argv[0] only: flags after it say nothing about vendor
  base="${base##*/}"   # and by basename, so an absolute path still resolves
  _review_vendor_of_basename "$base"
}

# review_single_vendor_approval <agents.toml> <outcomes-file> [<authors>]
#   stdout `true`  — every APPROVAL came from one known vendor, and every
#                    author that resolves to a known vendor is that same one
#   stdout `false` — otherwise
#
# Only approving verdicts count: a reviewer that participated and disagreed has
# not lent its vendor to the approval, which is the thing being described.
# A round with no approval at all is `false` — there is nothing to flag, and
# `true` would read as a claim about an approval that never happened.
#
# Authors resolve through the same table, and those that come back `unknown` —
# every human — are DROPPED rather than counted as a second vendor. Otherwise a
# human-authored spec could never be flagged, which is most of them.
review_single_vendor_approval() {
  local toml="${1:-}" file="${2:-}" authors="${3:-}"
  local agent outcome rest vendor seen="" approvals=0 a count=0 only=""
  [ -n "$toml" ] && [ -f "$toml" ] || {
    review_error "review_single_vendor_approval: registry not found: '${toml:-}'"
    return 2
  }
  [ -n "$file" ] && [ -f "$file" ] || {
    review_error "review_single_vendor_approval: outcomes file not found: '${file:-}'"
    return 2
  }

  while IFS=' ' read -r agent outcome rest || [ -n "$agent" ]; do
    [ -n "$agent" ] || continue
    _review_list_has "$outcome" "$REVIEW_AGREEING_VERDICTS" || continue
    approvals=$((approvals + 1))
    vendor="$(review_agent_vendor "$toml" "$agent")" || return 2
    _review_list_has "$vendor" "$seen" || {
      seen="$seen $vendor"; count=$((count + 1)); only="$vendor"
    }
  done < "$file"

  [ "$approvals" -gt 0 ] || { printf 'false\n'; return 0; }

  # An author with a known vendor joins the set: a spec written by claude and
  # approved only by anthropic is the sharpest case this flag exists for.
  #
  # The list is normalized first. Callers read it straight out of a spec's
  # `authors:` frontmatter, whose shape is `[claude, dstolf]` — so brackets and
  # commas have to go, or every author resolves to `unknown` and is DROPPED.
  # Round 8 flagged this; the reported symptom was wrong (the flag still read
  # `true` in the example given), but the underlying bug is real and worse:
  # with `authors = "[claude]"` and a single openai approval the answer flips
  # to `true` when it should be `false`, because the claude author never joined
  # the set.
  # Brackets, commas and quotes become SPACES, not nothing: deleting them would
  # fuse `[claude, dstolf]` into one token `claudedstolf`.
  authors="$(printf '%s\n' "$authors" | LC_ALL=C tr '[],"'"'" '     ')"
  while IFS= read -r a; do
    [ -n "$a" ] || continue
    vendor="$(_review_vendor_of_basename "${a##*/}")"
    [ "$vendor" != unknown ] || continue
    _review_list_has "$vendor" "$seen" || {
      seen="$seen $vendor"; count=$((count + 1)); only="$vendor"
    }
  done <<EOF
$(printf '%s\n' "$authors" | LC_ALL=C tr ' ' '\n')
EOF

  # Exactly one member, and it must be a KNOWN vendor.
  #
  # Counted as the set is built rather than with `set -- $seen`: that is an
  # unquoted parameter expansion, which zsh does NOT word-split, so the
  # positional count would be 1 for ANY number of vendors and every round
  # would report single_vendor_approval: true on macOS.
  if [ "$count" -eq 1 ] && [ "$only" != unknown ]; then
    printf 'true\n'
  else
    printf 'false\n'
  fi
}

# ---------------------------------------------------------------------------
# AC23b — `codex-plugin` and `subagent` are REVIEW-ONLY modes.
#
# `/speccraft:spec:delegate` and the `aux-delegator` subagent hand a task to an
# external CLI and integrate the result. Neither can do that through either new
# mode: `codex-plugin` reaches a companion that runs its own agent loop and
# reports touched files, and `subagent` can only be started by the
# orchestrating session's own tooling.
#
# A consumer that tried would not fail cleanly. `aux-delegator` composes a
# prompt and shells out, so a `subagent` entry — which carries no `cmd` at all
# — would produce an empty command line and a confident-looking empty result.
# Hence a PRECONDITION, checked before any dispatch.
#
# ONE text, here, used by both consumers. Two copies drift, and the second copy
# is the one nobody updates.
# ---------------------------------------------------------------------------

REVIEW_ONLY_MODES="codex-plugin subagent"
REVIEW_DELEGATABLE_MODES="cli acp"

# review_refuse_review_only_mode <mode>
#   exit 1 with the refusal on stderr — the caller must not dispatch
#   exit 2 if <mode> is delegatable, which means the CALLER's gate is inverted
#
# The message names where the mode DOES work. The operator configured that
# entry on purpose, so a refusal that only says "no" leaves them to guess.
#
# It promises no future support, deliberately: this is a guardrail, not a
# roadmap. "Not yet" would read as a scheduling accident, and the restriction
# is structural — a subagent cannot be started from a shell at all.
review_refuse_review_only_mode() {
  local mode="${1:-}"
  [ -n "$mode" ] || { review_error "review_refuse_review_only_mode: mode required"; return 2; }
  if _review_list_has "$mode" "$REVIEW_DELEGATABLE_MODES"; then
    review_error "review_refuse_review_only_mode: '$mode' IS delegatable; this helper refuses only $(_review_list_join "$REVIEW_ONLY_MODES") — the calling gate is inverted"
    return 2
  fi
  _review_list_has "$mode" "$REVIEW_ONLY_MODES" || {
    review_error "review_refuse_review_only_mode: unknown mode '$mode'"
    return 2
  }
  # The wording is the spec's, verbatim from §5 and §Contracts — unquoted
  # mode, the exact phrase "is a review-only dispatch mode", and the
  # parenthesized command list. An earlier draft paraphrased it, so a test or
  # an operator grepping the CONTRACTED string matched nothing (round 8).
  review_error "unsupported-mode: $mode is a review-only dispatch mode (used by spec:review, arch:review, pm:review, spec:review-code); spec:delegate supports $(_review_list_join "$REVIEW_DELEGATABLE_MODES")"
  return 1
}

# review_require_delegatable_mode <agents.toml> <agent>
# — the precondition both consumers call. Silent on success: it is a gate, not
# a step that reports. Launches nothing, by construction — it only reads the
# registry.
review_require_delegatable_mode() {
  local toml="${1:-}" agent="${2:-}" mode
  # An unknown agent propagates by NAME from review_agent_mode rather than
  # passing silently: a typo'd registry key must not look like a clean gate.
  mode="$(review_agent_mode "$toml" "$agent")" || return 2
  _review_list_has "$mode" "$REVIEW_ONLY_MODES" || return 0
  review_refuse_review_only_mode "$mode"
}

# review_doc_authors <document> — the document's `authors:` frontmatter value,
# verbatim. One implementation, so the four review commands cannot each invent
# a slightly different read.
#
# Emitted RAW (`[claude, dstolf]` and all), because
# review_single_vendor_approval normalizes brackets, commas and quotes itself —
# two places stripping the same punctuation is how one of them ends up
# stripping something the other needed.
review_doc_authors() {
  local f="${1:-}"
  [ -n "$f" ] || { review_error "review_doc_authors: document path required"; return 2; }
  [ -f "$f" ] || { review_error "review_doc_authors: not found: $f"; return 2; }
  _review_frontmatter_field "$f" authors
}
