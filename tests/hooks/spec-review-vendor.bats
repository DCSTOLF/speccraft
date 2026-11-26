#!/usr/bin/env bats
# Spec 0054 ACs 23 / 23a — vendor resolution, the mixed-mode quorum, and the
# same-vendor approval record.
#
# Why vendor at all: with a `subagent` reviewer available, the cheapest round
# to configure is one where every reviewer is Anthropic — the subagent, plus
# `claude -p`. That round LOOKS like cross-model review and reports a quorum,
# but every verdict came from one vendor's models, and on a spec those same
# models wrote. The flag exists so that is visible in the record.
#
# It is a RECORD, NOT A GATE. `approval_quorum_met` is unchanged by it, and one
# row asserts the quorum arithmetic is byte-identical with and without it, so
# spec 0052's quorum tests cannot be quietly altered by this spec.
#
# Resolution is by EXACT basename match on argv[0]. Not substring, not
# first-token prefix: `claudex`, `claude-code` and `claude_wrapper.sh` all
# resolve to `unknown`, because a predicate that guesses is a predicate every
# implementer reimplements differently. `unknown` is a legitimate answer and is
# never treated as agreement.

setup() {
  PLUGIN_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  LIB="$PLUGIN_DIR/commands/spec/review.lib.sh"
  CROSS="$PLUGIN_DIR/agents/cross-reviewer.md"
  export PATH="$PLUGIN_DIR/bin:$PATH"
  TEST_DIR="$(mktemp -d)"
  TOML="$TEST_DIR/agents.toml"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# entry <name> <mode> [<cmd-toml>] — one [[agents]] block appended to $TOML.
entry() {
  local name="$1" mode="$2" cmd="${3:-}"
  {
    printf '[[agents]]\n'
    printf 'name = "%s"\n' "$name"
    printf 'mode = "%s"\n' "$mode"
    printf 'enabled = true\n'
    printf 'reference_read = true\n'
    [ -z "$cmd" ] || printf 'cmd = %s\n' "$cmd"
    printf '\n'
  } >> "$TOML"
}

outcomes() {
  local f="$TEST_DIR/outcomes.txt"
  printf '%s\n' "$@" > "$f"
  printf '%s\n' "$f"
}

# vendor_of <cmd-toml> — resolve a one-off cli entry's vendor.
vendor_of() {
  : > "$TOML"
  entry probe cli "$1"
  review_agent_vendor "$TOML" probe
}

# ---------------------------------------------------------------------------
# AC23a — the pinned resolution rows
# ---------------------------------------------------------------------------

@test "review_agent_vendor resolves claude to anthropic" {
  source "$LIB"
  [ "$(vendor_of '["claude"]')" = "anthropic" ]
}

@test "an absolute path resolves by basename" {
  source "$LIB"
  [ "$(vendor_of '["/usr/local/bin/claude"]')" = "anthropic" ]
}

@test "flags after argv[0] are ignored" {
  source "$LIB"
  [ "$(vendor_of '["claude", "-p", "--allowedTools", "Read,Grep"]')" = "anthropic" ]
}

@test "codex resolves to openai" {
  source "$LIB"
  [ "$(vendor_of '["codex", "exec", "--full-auto"]')" = "openai" ]
}

@test "claude-p resolves to unknown" {
  source "$LIB"
  # The registry's AGENT NAME is `claude-p`; the binary is `claude`. Resolution
  # reads the command, never the name, so a renamed entry cannot change the
  # vendor and a wrapper named after the vendor cannot claim it.
  [ "$(vendor_of '["claude-p"]')" = "unknown" ]
}

@test "claude_wrapper.sh resolves to unknown" {
  source "$LIB"
  [ "$(vendor_of '["claude_wrapper.sh"]')" = "unknown" ]
}

@test "a wrapper named after a model resolves to unknown" {
  source "$LIB"
  # `/opt/wrappers/opus` — a model name is not a vendor, and nothing about the
  # path says which vendor's API it reaches.
  [ "$(vendor_of '["/opt/wrappers/opus"]')" = "unknown" ]
}

@test "no substring matching: claudex resolves to unknown" {
  source "$LIB"
  [ "$(vendor_of '["claudex"]')" = "unknown" ]
}

@test "no first-token-prefix matching: claude-code resolves to unknown" {
  source "$LIB"
  [ "$(vendor_of '["claude-code"]')" = "unknown" ]
}

@test "no suffix matching: a path ending in the vendor name is not enough" {
  source "$LIB"
  # `myclaude` and `xcodex` share a suffix with a known binary. A `*claude`
  # glob would resolve both.
  [ "$(vendor_of '["myclaude"]')" = "unknown" ]
  [ "$(vendor_of '["xcodex"]')" = "unknown" ]
}

@test "subagent mode resolves to anthropic by construction" {
  source "$LIB"
  : > "$TOML"
  entry sub subagent
  # No cmd at all: a subagent runs inside this session, so its vendor is known
  # from the mode rather than from any binary.
  [ "$(review_agent_vendor "$TOML" sub)" = "anthropic" ]
}

@test "codex-plugin mode resolves to openai by construction" {
  source "$LIB"
  : > "$TOML"
  entry cxp codex-plugin
  [ "$(review_agent_vendor "$TOML" cxp)" = "openai" ]
}

@test "a subagent entry cannot carry a cmd to mislabel its vendor with" {
  source "$LIB"
  : > "$TOML"
  entry sub subagent '["codex"]'
  # The question "could a leftover cmd relabel a constructed vendor?" has a
  # stronger answer than "the mode wins": the registry refuses the entry
  # outright, so the ambiguous state cannot be reached. Pinned here because
  # that refusal is now load-bearing for vendor resolution too, not only for
  # dispatch — if it were ever relaxed, this row is where it surfaces.
  run review_agent_vendor "$TOML" sub
  [ "$status" -ne 0 ]
  printf '%s\n' "$output" | grep -qF "cmd" || {
    echo "the refusal does not name the offending key: $output" >&2
    return 1
  }
}

@test "a cli entry with no cmd is unknown, not an error" {
  source "$LIB"
  : > "$TOML"
  entry bare cli
  [ "$(review_agent_vendor "$TOML" bare)" = "unknown" ]
}

@test "an unknown agent is a named error, not unknown-vendor" {
  source "$LIB"
  : > "$TOML"
  entry real cli '["claude"]'
  run review_agent_vendor "$TOML" nosuch
  [ "$status" -ne 0 ]
  printf '%s\n' "$output" | grep -qF "nosuch"
}

# ---------------------------------------------------------------------------
# AC23 — the mixed-mode round
# ---------------------------------------------------------------------------

@test "one subagent approve plus one cli changes-requested meets quorum 1" {
  source "$LIB"
  run review_responses_complete "$(outcomes 'sub approve' 'codex changes-requested')"
  [ "$status" -eq 0 ]
  run review_approval_quorum_met 1 "$(outcomes 'sub approve' 'codex changes-requested')"
  [ "$status" -eq 0 ]
}

@test "a subagent attestation-failed makes responses_complete false" {
  source "$LIB"
  run review_responses_complete "$(outcomes 'sub attestation-failed digest-mismatch' 'codex approve')"
  [ "$status" -eq 1 ]
}

# ---------------------------------------------------------------------------
# AC23a — the single-vendor approval record
# ---------------------------------------------------------------------------

@test "an anthropic-only approval on a claude-authored spec is single-vendor" {
  source "$LIB"
  : > "$TOML"
  entry sub subagent
  entry codex cli '["codex", "exec"]'
  run review_single_vendor_approval "$TOML" \
    "$(outcomes 'sub approve' 'codex changes-requested')" claude
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "one anthropic plus one openai approval is not single-vendor" {
  source "$LIB"
  : > "$TOML"
  entry sub subagent
  entry codex cli '["codex", "exec"]'
  run review_single_vendor_approval "$TOML" \
    "$(outcomes 'sub approve' 'codex approve')" claude
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}

@test "only APPROVING reviewers count toward the vendor set" {
  source "$LIB"
  : > "$TOML"
  entry sub subagent
  entry codex cli '["codex", "exec"]'
  # codex participated and disagreed. Its vendor must not dilute the flag:
  # the round's APPROVAL still came from one vendor, which is the point.
  run review_single_vendor_approval "$TOML" \
    "$(outcomes 'sub approve' 'codex reject')" claude
  [ "$output" = "true" ]
  # A refusal is likewise not an approval.
  run review_single_vendor_approval "$TOML" \
    "$(outcomes 'sub approve' 'codex refused refuse:argv-limit')" claude
  [ "$output" = "true" ]
}

@test "approve-with-comments counts as an approval for the flag" {
  source "$LIB"
  : > "$TOML"
  entry sub subagent
  entry codex cli '["codex", "exec"]'
  run review_single_vendor_approval "$TOML" \
    "$(outcomes 'sub approve-with-comments' 'codex approve')" claude
  [ "$output" = "false" ]
}

@test "a round with no approval at all is not single-vendor" {
  source "$LIB"
  : > "$TOML"
  entry sub subagent
  # There is nothing to flag. `true` here would read as "the approval came
  # from one vendor" about a round that had none.
  run review_single_vendor_approval "$TOML" \
    "$(outcomes 'sub changes-requested')" claude
  [ "$output" = "false" ]
}

@test "approvals that all resolve to unknown are not single-vendor" {
  source "$LIB"
  : > "$TOML"
  entry w1 cli '["wrapper_one.sh"]'
  entry w2 cli '["wrapper_two.sh"]'
  # Both unknown. "They are the same vendor" is exactly what we do not know,
  # so claiming it would be worse than saying nothing.
  #
  # The author must be a HUMAN here. With `claude` as author this row passed
  # for the wrong reason — the author's `anthropic` made the vendor set size 2,
  # so the answer was `false` whether or not `unknown` was excluded, and
  # deleting that exclusion reddened nothing.
  run review_single_vendor_approval "$TOML" \
    "$(outcomes 'w1 approve' 'w2 approve')" dstolf
  [ "$output" = "false" ]
  # A SINGLE unknown approval is the same answer, for the same reason.
  run review_single_vendor_approval "$TOML" "$(outcomes 'w1 approve')" dstolf
  [ "$output" = "false" ]
}

@test "an author resolving to a known vendor joins the set" {
  source "$LIB"
  : > "$TOML"
  entry codex cli '["codex", "exec"]'
  # Authored by claude (anthropic), approved only by codex (openai): two
  # vendors, so not single-vendor — the author did not approve its own work.
  run review_single_vendor_approval "$TOML" \
    "$(outcomes 'codex approve')" claude
  [ "$output" = "false" ]
}

@test "an author with no known vendor does not dilute the flag" {
  source "$LIB"
  : > "$TOML"
  entry sub subagent
  # A human author resolves to `unknown` and is dropped, so the flag still
  # reports what it is named for: every approval came from one vendor.
  run review_single_vendor_approval "$TOML" \
    "$(outcomes 'sub approve')" "dstolf"
  [ "$output" = "true" ]
}

@test "multiple authors are all resolved" {
  source "$LIB"
  : > "$TOML"
  entry sub subagent
  run review_single_vendor_approval "$TOML" \
    "$(outcomes 'sub approve')" "dstolf claude"
  [ "$output" = "true" ]
  run review_single_vendor_approval "$TOML" \
    "$(outcomes 'sub approve')" "dstolf codex"
  [ "$output" = "false" ]
}

# ---------------------------------------------------------------------------
# AC23 / AC23a — what the round REPORTS
# ---------------------------------------------------------------------------

make_spec_dir() {
  SPEC_DIR="$TEST_DIR/specs/0001-x"
  mkdir -p "$SPEC_DIR"
  printf '# Spec\n\nSPEC\n' > "$SPEC_DIR/spec.md"
  printf '# Spec\n\nSNAP\n' > "$SPEC_DIR/review-snapshot.md"
  printf '# Review\n\nPRIOR\n' > "$SPEC_DIR/review.md"
}

@test "the round report names each verdict's mode, model and vendor" {
  source "$LIB"
  make_spec_dir
  : > "$TOML"
  entry sub subagent
  entry codex cli '["codex", "exec"]'
  printf 'model = "opus"\n' >> "$TOML"
  run review_finalize_round "$SPEC_DIR" 1 \
    "$(outcomes 'sub approve' 'codex changes-requested')" spec "$TOML" claude
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qE '^verdict: sub approve .*mode=subagent' || {
    echo "no mode on the subagent verdict: $output" >&2
    return 1
  }
  printf '%s\n' "$output" | grep -qE '^verdict: sub approve .*vendor=anthropic' || {
    echo "no vendor on the subagent verdict: $output" >&2
    return 1
  }
  printf '%s\n' "$output" | grep -qE '^verdict: codex changes-requested .*vendor=openai' || {
    echo "no vendor on the cli verdict: $output" >&2
    return 1
  }
  printf '%s\n' "$output" | grep -qE '^verdict: sub approve .*model=' || {
    echo "no requested model on the verdict: $output" >&2
    return 1
  }
}

@test "the report records single_vendor_approval and still meets quorum" {
  source "$LIB"
  make_spec_dir
  : > "$TOML"
  entry sub subagent
  run review_finalize_round "$SPEC_DIR" 1 "$(outcomes 'sub approve')" spec "$TOML" claude
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qxF 'single_vendor_approval: true'
  # THE FLAG IS A RECORD, NOT A GATE.
  printf '%s\n' "$output" | grep -qxF 'approval_quorum_met: true'
  printf '%s\n' "$output" | grep -qxF 'status: reviewed'
}

@test "a cross-vendor round records the flag as false" {
  source "$LIB"
  make_spec_dir
  : > "$TOML"
  entry sub subagent
  entry codex cli '["codex", "exec"]'
  run review_finalize_round "$SPEC_DIR" 1 \
    "$(outcomes 'sub approve' 'codex approve')" spec "$TOML" claude
  printf '%s\n' "$output" | grep -qxF 'single_vendor_approval: false'
  printf '%s\n' "$output" | grep -qxF 'approval_quorum_met: true'
}

@test "quorum arithmetic is byte-identical with and without the flag" {
  source "$LIB"
  make_spec_dir
  : > "$TOML"
  entry sub subagent
  local without with
  # Spec 0052's callers pass three arguments. Their report must not change by
  # one byte, or this spec has silently rewritten a contract it only extends.
  without="$(review_finalize_round "$SPEC_DIR" 1 "$(outcomes 'sub approve')" \
    | grep -E '^(responses_complete|approval_quorum_met|synthesis|status):')"
  with="$(review_finalize_round "$SPEC_DIR" 1 "$(outcomes 'sub approve')" spec "$TOML" claude \
    | grep -E '^(responses_complete|approval_quorum_met|synthesis|status):')"
  [ "$without" = "$with" ] || {
    echo "the four round predicates changed when the flag was enabled:" >&2
    diff <(printf '%s\n' "$without") <(printf '%s\n' "$with") >&2 || true
    return 1
  }
}

@test "a three-argument call emits no vendor fields and no flag line" {
  source "$LIB"
  make_spec_dir
  run review_finalize_round "$SPEC_DIR" 1 "$(outcomes 'sub approve')"
  [ "$status" -eq 0 ]
  # Without a registry there is nothing to resolve, and inventing `unknown`
  # for every reviewer would be noise in every pre-existing caller's report.
  printf '%s\n' "$output" | grep -qF 'single_vendor_approval' && {
    echo "a three-argument call emitted a flag line: $output" >&2
    return 1
  }
  printf '%s\n' "$output" | grep -qF 'vendor=' && {
    echo "a three-argument call emitted vendor fields: $output" >&2
    return 1
  }
  return 0
}

@test "the no-flag guards bite on the six-argument call" {
  source "$LIB"
  # Premise for the row above: prove the flag line and the vendor fields DO
  # appear when the registry is supplied, so their absence is a real
  # distinction rather than a pattern that never matches.
  make_spec_dir
  : > "$TOML"
  entry sub subagent
  run review_finalize_round "$SPEC_DIR" 1 "$(outcomes 'sub approve')" spec "$TOML" claude
  printf '%s\n' "$output" | grep -qF 'single_vendor_approval' || {
    echo "the six-argument call emits no flag, so the negative is vacuous" >&2
    return 1
  }
  printf '%s\n' "$output" | grep -qF 'vendor=' || {
    echo "the six-argument call emits no vendor, so the negative is vacuous" >&2
    return 1
  }
}

@test "the cross-reviewer's review.md template carries mode, model and vendor" {
  # The synthesized document is what a human reads weeks later. A round flag
  # that only ever appeared on stdout would be lost the moment the terminal
  # scrolled.
  local col
  for col in Mode Model Vendor; do
    grep -qiE "\\b$col\\b" "$CROSS" || {
      echo "cross-reviewer.md's template has no $col column:" >&2
      grep -nA4 'Verdict' "$CROSS" >&2
      return 1
    }
  done
  # Scoped to the template's FRONTMATTER block, not the whole file. A
  # whole-file grep is satisfied by the prose that merely tells the agent where
  # the value comes from, so the field could be deleted from the template
  # without a red.
  local fm
  fm="$(awk '/^   ---$/ { n++; next } n == 1' "$CROSS")"
  [ -n "$fm" ] || {
    echo "could not isolate the template's frontmatter; row would be vacuous" >&2
    grep -n -- '---' "$CROSS" >&2
    return 1
  }
  printf '%s\n' "$fm" | grep -qF 'single_vendor_approval' || {
    echo "the template's frontmatter does not record the round flag:" >&2
    printf '%s\n' "$fm" >&2
    return 1
  }
}

# ---------------------------------------------------------------------------
# Phase G.5 — remediation from cross-model code-review round 8.
# ---------------------------------------------------------------------------

@test "a vendor-resolution failure aborts finalize instead of printing an empty field" {
  source "$LIB"
  make_spec_dir
  : > "$TOML"
  entry known cli '["codex", "exec"]'
  # An approving agent that is not in the registry makes review_agent_vendor
  # fail by name. The flag was printed inside a printf argument, so the
  # substitution's exit status was DISCARDED: the report carried
  # `single_vendor_approval: ` with an empty value and finalize still returned
  # 0 — a failure reported as success (round 8).
  printf 'gone approve\n' > "$TEST_DIR/outcomes.txt"
  run review_finalize_round "$SPEC_DIR" 1 "$TEST_DIR/outcomes.txt" spec "$TOML" claude
  [ "$status" -eq 2 ] || {
    echo "expected exit 2 on an unresolvable vendor, got $status" >&2
    return 1
  }
  printf '%s\n' "$output" | grep -qF 'gone' || {
    echo "the error does not name the unresolvable agent: $output" >&2
    return 1
  }
  # And no half-written flag line.
  printf '%s\n' "$output" | grep -qE '^single_vendor_approval: *$' && {
    echo "an empty flag line was printed: $output" >&2
    return 1
  }
  return 0
}

@test "the authors list is accepted in the shape a spec's frontmatter carries it" {
  source "$LIB"
  : > "$TOML"
  entry cx cli '["codex", "exec"]'
  # The caller reads `authors:` straight out of frontmatter, where the value is
  # `[claude, dstolf]`. Splitting on spaces alone left every author as
  # `[claude,` or `dstolf]`, which resolve to `unknown` and are DROPPED — so a
  # claude-authored spec approved only by openai reported `true` (one vendor)
  # when the correct answer is `false` (two).
  local f
  f="$(outcomes 'cx approve')"
  local a
  for a in 'claude' '[claude]' 'claude,' '[claude, dstolf]' '["claude", "dstolf"]'; do
    run review_single_vendor_approval "$TOML" "$f" "$a"
    [ "$output" = "false" ] || {
      echo "authors='$a' gave '$output', want false (claude + codex = two vendors)" >&2
      return 1
    }
  done
  # …and a human-only list still leaves the approval single-vendor.
  for a in 'dstolf' '[dstolf]' '[dstolf, someone-else]'; do
    run review_single_vendor_approval "$TOML" "$f" "$a"
    [ "$output" = "true" ] || {
      echo "authors='$a' gave '$output', want true (no known author vendor)" >&2
      return 1
    }
  done
}

@test "review_doc_authors reads the frontmatter value verbatim" {
  source "$LIB"
  # One implementation, so the four commands cannot each invent a slightly
  # different read. Emitted RAW: the normalization lives in one place, and two
  # places stripping the same punctuation is how one strips what the other
  # needed.
  printf -- '---\nid: "0001"\nauthors: [claude, dstolf]\nstatus: draft\n---\n\n# Spec\n' \
    > "$TEST_DIR/spec.md"
  run review_doc_authors "$TEST_DIR/spec.md"
  [ "$status" -eq 0 ]
  [ "$output" = "[claude, dstolf]" ] || {
    echo "got '$output', want the raw frontmatter value" >&2
    return 1
  }
}

@test "review_doc_authors on a document with no authors key is empty, not an error" {
  source "$LIB"
  # A design or brief may legitimately have none; the round still finalizes and
  # the flag then describes the approvals alone.
  printf -- '---\nid: "0001"\nstatus: draft\n---\n\n# Design\n' > "$TEST_DIR/design.md"
  run review_doc_authors "$TEST_DIR/design.md"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "review_doc_authors on a missing document is a named error" {
  source "$LIB"
  run review_doc_authors "$TEST_DIR/nope.md"
  [ "$status" -ne 0 ]
  printf '%s\n' "$output" | grep -qF 'nope.md'
}

@test "every shipped review command passes the registry and the authors" {
  # The feature shipped DEAD: review_finalize_round only emits the vendor
  # record when given a 5th and 6th argument, and no caller passed them, so
  # ACs 23 and 23a were absent from every real round. Both round-8 reviewers
  # found it independently.
  local f n
  for f in commands/spec/review.md commands/arch/review.md commands/pm/review.md \
           commands/spec/review-code.md; do
    # INVOCATIONS, not mentions: `^<indent>review_finalize_round <arg>`.
    # A plain `grep -c` also counts the prose in spec/review.md step 6 that
    # names the function, which made this row demand a registry argument on a
    # sentence.
    n="$(grep -cE '^[[:space:]]+review_finalize_round ' "$PLUGIN_DIR/$f" || true)"
    [ "$n" -gt 0 ] || { echo "$f does not finalize at all" >&2; return 1; }
    # Every call site must carry the registry, on its own continuation line.
    [ "$(grep -A1 -E '^[[:space:]]+review_finalize_round ' "$PLUGIN_DIR/$f" \
        | grep -c 'agents.toml' || true)" -ge "$n" ] || {
      echo "$f has $n finalize call(s) but fewer registry arguments:" >&2
      grep -n -A1 -E '^[[:space:]]+review_finalize_round ' "$PLUGIN_DIR/$f" >&2
      return 1
    }
    grep -qF 'AUTHORS' "$PLUGIN_DIR/$f" || {
      echo "$f never resolves AUTHORS" >&2
      return 1
    }
  done
}

@test "a vendor failure leaves the spec dir untouched" {
  source "$LIB"
  make_spec_dir
  : > "$TOML"
  entry known cli '["codex", "exec"]'
  # Round 9: the flag was computed AFTER the snapshot promote and the
  # fingerprint stamp, so an unresolvable vendor left review-snapshot.md
  # promoted and reviewed_sha256 written and THEN returned 2 — a partially
  # committed round that reads as a failed one. Nothing may move.
  local before_snap before_rev
  before_snap="$(cat "$SPEC_DIR/review-snapshot.md")"
  before_rev="$(cat "$SPEC_DIR/review.md")"
  printf 'gone approve\n' > "$TEST_DIR/outcomes.txt"
  run review_finalize_round "$SPEC_DIR" 1 "$TEST_DIR/outcomes.txt" spec "$TOML" claude
  [ "$status" -eq 2 ]
  [ "$(cat "$SPEC_DIR/review-snapshot.md")" = "$before_snap" ] || {
    echo "review-snapshot.md was promoted despite the failure" >&2
    return 1
  }
  [ "$(cat "$SPEC_DIR/review.md")" = "$before_rev" ] || {
    echo "review.md was stamped despite the failure" >&2
    return 1
  }
  printf '%s\n' "$output" | grep -qiF 'nothing was written'
}

@test "the happy path still promotes and still reports the flag" {
  source "$LIB"
  # The converse, so moving the check earlier cannot have disabled the writes.
  make_spec_dir
  : > "$TOML"
  entry known cli '["codex", "exec"]'
  printf 'known approve\n' > "$TEST_DIR/outcomes.txt"
  run review_finalize_round "$SPEC_DIR" 1 "$TEST_DIR/outcomes.txt" spec "$TOML" claude
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qxF 'status: reviewed'
  printf '%s\n' "$output" | grep -qE '^single_vendor_approval: (true|false)$'
  grep -qE '^reviewed_sha256: [0-9a-f]{64}$' "$SPEC_DIR/review.md"
  grep -qF 'SPEC' "$SPEC_DIR/review-snapshot.md"
}

# ---------------------------------------------------------------------------
# The flag is GATED ON A MET QUORUM — operator ruling, 2026-11-24.
#
# Code-review rounds 8 and 9 both argued for this and the ruling went with
# them. The reasoning that won: `single_vendor_approval` describes an APPROVAL
# the round acted on, so reporting it for a round that never reached quorum
# invites "approved, by one vendor" where the round was not approved at all.
#
# I had argued the other way — that the near-miss round is exactly when an
# operator wants the record. Recorded here so the next reader sees it was a
# decision, not an oversight.
# ---------------------------------------------------------------------------

@test "a round that did not meet quorum reports no flag at all" {
  source "$LIB"
  make_spec_dir
  : > "$TOML"
  entry sub subagent
  # One anthropic approval, quorum 2: complete, but not approved.
  run review_finalize_round "$SPEC_DIR" 2 "$(outcomes 'sub approve')" spec "$TOML" claude
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qxF 'approval_quorum_met: false'
  printf '%s\n' "$output" | grep -qF 'single_vendor_approval' && {
    echo "the flag was reported for a round that did not meet quorum:" >&2
    printf '%s\n' "$output" >&2
    return 1
  }
  return 0
}

@test "a round that met quorum still reports the flag" {
  source "$LIB"
  make_spec_dir
  : > "$TOML"
  entry sub subagent
  # The converse, so the gate cannot have simply disabled the flag.
  run review_finalize_round "$SPEC_DIR" 1 "$(outcomes 'sub approve')" spec "$TOML" claude
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qxF 'approval_quorum_met: true'
  printf '%s\n' "$output" | grep -qxF 'single_vendor_approval: true'
}

@test "an inert round reports no flag, because it cannot have met quorum" {
  source "$LIB"
  make_spec_dir
  : > "$TOML"
  entry sub subagent
  run review_finalize_round "$SPEC_DIR" 1 "$(outcomes 'sub timeout')" spec "$TOML" claude
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qxF 'responses_complete: false'
  printf '%s\n' "$output" | grep -qF 'single_vendor_approval' && {
    echo "an inert round reported the flag" >&2
    return 1
  }
  return 0
}

@test "per-verdict mode, model and vendor are NOT gated on quorum" {
  source "$LIB"
  make_spec_dir
  : > "$TOML"
  entry sub subagent
  entry codex cli '["codex", "exec"]'
  # AC23 asks for each verdict's mode, requested model and vendor
  # unconditionally — they describe the verdicts OBTAINED, not the approval.
  # Only the round-level flag is a claim about an approval.
  run review_finalize_round "$SPEC_DIR" 2 \
    "$(outcomes 'sub approve' 'codex changes-requested')" spec "$TOML" claude
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qxF 'approval_quorum_met: false'
  printf '%s\n' "$output" | grep -qE '^verdict: sub approve .*vendor=anthropic' || {
    echo "the per-verdict vendor was suppressed with the flag:" >&2
    printf '%s\n' "$output" >&2
    return 1
  }
  printf '%s\n' "$output" | grep -qE '^verdict: codex changes-requested .*vendor=openai'
}

@test "an unresolvable vendor is not fatal when quorum was not met" {
  source "$LIB"
  make_spec_dir
  : > "$TOML"
  entry known cli '["codex", "exec"]'
  # Resolution is skipped along with the reporting, so a round nobody will read
  # the flag for is not failed over a value nobody asked for. The fatal arm is
  # pinned by the quorum-met row below it.
  printf 'gone approve\n' > "$TEST_DIR/outcomes.txt"
  run review_finalize_round "$SPEC_DIR" 2 "$TEST_DIR/outcomes.txt" spec "$TOML" claude
  [ "$status" -eq 0 ] || {
    echo "a below-quorum round was failed over a flag it does not report:" >&2
    printf '%s\n' "$output" >&2
    return 1
  }
  # …and WITH quorum met the same registry error is still fatal, and still
  # leaves the spec dir untouched.
  local before
  before="$(cat "$SPEC_DIR/review-snapshot.md")"
  run review_finalize_round "$SPEC_DIR" 1 "$TEST_DIR/outcomes.txt" spec "$TOML" claude
  [ "$status" -eq 2 ]
  [ "$(cat "$SPEC_DIR/review-snapshot.md")" = "$before" ]
}
