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
