#!/usr/bin/env bats
# Spec 0054 ACs 24 / 25 — the shipped template, the convention, and the skill.
#
# §External-tool boundaries (spec 0011) forbids speccraft from telling the model
# which external tool to call. The two modes this spec adds both reach external
# installs — the Codex plugin's companion, and whichever agent a registry entry
# names — so documenting them at all brushes against that rule. AC24 resolves
# it: a USER-CONFIGURED review adapter is not speccraft routing to a tool, it is
# speccraft honouring a choice the user already made. The convention has to say
# so, or the next reader applies the rule and deletes the documentation.
#
# The phrase rule is the convention's own: examples are allowed
# ("such as X", "e.g. X"), recommendations are not ("prefer X", "X is the
# recommended way"). Checked here with the same vocabulary, and the negative is
# proven to bite.
#
# AC25's template assertions are parsed PER ENTRY, never as a whole-file grep: a
# file containing `mode = "subagent"` somewhere and `enabled = false` somewhere
# satisfies a whole-file check while shipping the opposite configuration.

setup() {
  PLUGIN_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  TEMPLATE="$PLUGIN_DIR/templates/speccraft/agents.toml"
  CONV="$PLUGIN_DIR/.speccraft/conventions.md"
  AUX_SKILL="$PLUGIN_DIR/skills/aux-agents/SKILL.md"
  export PATH="$PLUGIN_DIR/bin:$PATH"
  TEST_DIR="$(mktemp -d)"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# The convention's own recommendation vocabulary. Applied to the SKILL and the
# template, which is what AC24 means by "the same phrase rule the convention
# states".
RECOMMEND_RE='prefer(red|ably)? |is the recommended|we recommend|recommended way|you should use|always use'

# entry_block <name> — one [[agents]] block from the template, by name.
# Per-entry parsing: a whole-file grep cannot tell which entry a key belongs to.
entry_block() {
  awk -v want="$1" '
    function flush() {
      if (inblk && name == want) { printf "%s", buf; exit }
      buf = ""; name = ""
    }
    # A new table header ENDS the current block, so the completed block is
    # tested BEFORE the buffer is reset. A first draft reset first, which threw
    # away every entry but the last and made the whole AC25 section vacuous —
    # caught by the parser premise row below.
    /^[ \t]*\[\[agents\]\]/ { flush(); inblk = 1; next }
    /^[ \t]*\[/             { flush(); inblk = 0; next }
    inblk {
      buf = buf $0 "\n"
      if ($0 ~ /^[ \t]*name[ \t]*=/) { n = $0; sub(/^[^=]*=[ \t]*"?/, "", n); sub(/".*$/, "", n); name = n }
    }
    END { flush() }
  ' "$TEMPLATE"
}

# entry_names — every entry's name, one per line.
entry_names() {
  awk '
    /^[ \t]*\[\[agents\]\]/ { inblk = 1; next }
    inblk && /^[ \t]*name[ \t]*=/ {
      n = $0; sub(/^[^=]*=[ \t]*"?/, "", n); sub(/".*$/, "", n); print n
    }
  ' "$TEMPLATE"
}

# ---------------------------------------------------------------------------
# The per-entry parser must work before anything relies on it
# ---------------------------------------------------------------------------

@test "the per-entry parser isolates one entry's keys from its neighbours" {
  # Premise for every AC25 row. Without it, a parser that returned the whole
  # file would make each row a whole-file grep — the exact thing AC25 forbids.
  local codex
  codex="$(entry_block codex)"
  [ -n "$codex" ] || { echo "no codex entry found" >&2; return 1; }
  printf '%s\n' "$codex" | grep -qF 'name = "codex"'
  printf '%s\n' "$codex" | grep -qF 'opencode' && {
    echo "the parser leaked a neighbouring entry into codex's block:" >&2
    printf '%s\n' "$codex" >&2
    return 1
  }
  return 0
}

@test "the per-entry parser finds every entry exactly once" {
  local names
  names="$(entry_names)"
  [ "$(printf '%s\n' "$names" | grep -c .)" -ge 4 ] || {
    echo "fewer entries than the template ships: $names" >&2
    return 1
  }
  [ "$(printf '%s\n' "$names" | sort | uniq -d | grep -c . || true)" -eq 0 ] || {
    echo "duplicate entry names: $names" >&2
    return 1
  }
}

# ---------------------------------------------------------------------------
# AC25 — the shipped template
# ---------------------------------------------------------------------------

@test "the template has exactly one subagent entry" {
  local n=0 name
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    entry_block "$name" | grep -qE '^[ \t]*mode[ \t]*=[ \t]*"subagent"' && n=$((n + 1))
  done <<EOF
$(entry_names)
EOF
  [ "$n" -eq 1 ] || { echo "expected exactly 1 subagent entry, found $n" >&2; return 1; }
}

@test "the subagent entry is enabled and sets model = opus" {
  local name blk found=""
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    blk="$(entry_block "$name")"
    printf '%s\n' "$blk" | grep -qE '^[ \t]*mode[ \t]*=[ \t]*"subagent"' || continue
    found="$name"
    # Enabled: either an explicit true, or no `enabled` key at all (the default).
    printf '%s\n' "$blk" | grep -qE '^[ \t]*enabled[ \t]*=[ \t]*false' && {
      echo "the subagent entry ships disabled; it is the one reviewer needing no install" >&2
      return 1
    }
    printf '%s\n' "$blk" | grep -qE '^[ \t]*model[ \t]*=[ \t]*"opus"' || {
      echo "the subagent entry does not set model = opus:" >&2
      printf '%s\n' "$blk" >&2
      return 1
    }
  done <<EOF
$(entry_names)
EOF
  [ -n "$found" ] || { echo "no subagent entry at all" >&2; return 1; }
}

@test "the subagent entry carries no cmd" {
  local name blk
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    blk="$(entry_block "$name")"
    printf '%s\n' "$blk" | grep -qE '^[ \t]*mode[ \t]*=[ \t]*"subagent"' || continue
    # The registry REFUSES a subagent entry with a cmd, so shipping one would
    # make a fresh /speccraft:init unable to load its own registry.
    printf '%s\n' "$blk" | grep -qE '^[ \t]*cmd[ \t]*=' && {
      echo "the shipped subagent entry carries a cmd, which the loader refuses:" >&2
      printf '%s\n' "$blk" >&2
      return 1
    }
  done <<EOF
$(entry_names)
EOF
  return 0
}

@test "the template has exactly one codex-plugin entry, shipped disabled" {
  local n=0 name blk
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    blk="$(entry_block "$name")"
    printf '%s\n' "$blk" | grep -qE '^[ \t]*mode[ \t]*=[ \t]*"codex-plugin"' || continue
    n=$((n + 1))
    # Disabled by default: it needs the Codex plugin installed, and a round that
    # refuses a reviewer the user never asked for is noise on every fresh init.
    printf '%s\n' "$blk" | grep -qE '^[ \t]*enabled[ \t]*=[ \t]*false' || {
      echo "the codex-plugin entry is not shipped disabled:" >&2
      printf '%s\n' "$blk" >&2
      return 1
    }
  done <<EOF
$(entry_names)
EOF
  [ "$n" -eq 1 ] || { echo "expected exactly 1 codex-plugin entry, found $n" >&2; return 1; }
}

@test "every entry carries an explicit reference_read" {
  local name blk missing=""
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    blk="$(entry_block "$name")"
    printf '%s\n' "$blk" | grep -qE '^[ \t]*reference_read[ \t]*=' || missing="$missing $name"
  done <<EOF
$(entry_names)
EOF
  [ -z "$missing" ] || {
    echo "entries with no explicit reference_read:$missing" >&2
    echo "the key is opt-out, so an absent one still works — but a fresh init" >&2
    echo "should not depend on that default" >&2
    return 1
  }
}

@test "the template states the same-vendor-default trade-off" {
  # The shipped default enables `codex` and the `subagent`: openai + anthropic,
  # a cross-vendor round. The trade-off worth stating is what happens when a
  # user disables codex — the round silently becomes single-vendor.
  grep -qiE 'vendor' "$TEMPLATE" || {
    echo "the template never mentions vendor at all" >&2
    return 1
  }
  grep -qF 'single_vendor_approval' "$TEMPLATE" || {
    echo "the template does not name the flag a single-vendor round records:" >&2
    grep -niE 'vendor' "$TEMPLATE" >&2
    return 1
  }
}

@test "the template names /codex:setup as the route to the codex-plugin mode" {
  grep -qF '/codex:setup' "$TEMPLATE" || {
    echo "the template does not name /codex:setup:" >&2
    grep -niE 'codex-plugin' "$TEMPLATE" >&2
    return 1
  }
}

@test "the template recommends no external tool" {
  grep -qiE "$RECOMMEND_RE" "$TEMPLATE" && {
    echo "the template reads as a speccraft recommendation:" >&2
    grep -niE "$RECOMMEND_RE" "$TEMPLATE" >&2
    return 1
  }
  return 0
}

@test "the template's mode comment lists all four modes" {
  # The header said `Each agent has a mode: "cli" or "acp"`. A user reading the
  # file they were just given has no other list.
  local m
  for m in cli acp codex-plugin subagent; do
    grep -qE "^#.*\b$m\b" "$TEMPLATE" || {
      echo "the template's comments never name the '$m' mode:" >&2
      grep -nE '^#' "$TEMPLATE" | head >&2
      return 1
    }
  done
}

@test "the template stays stack-agnostic" {
  # guardrails.md: templates must carry no Go-, Python- or HTTP-specific
  # assumptions. This spec adds prose to the file, so the rule is re-checked.
  grep -qiE '\bgo\.mod\b|\bpytest\b|\bnpm\b|\bcargo\b|localhost:[0-9]|HTTP/[0-9]' "$TEMPLATE" && {
    echo "the template acquired stack-specific content:" >&2
    grep -niE '\bgo\.mod\b|\bpytest\b|\bnpm\b|\bcargo\b|localhost:[0-9]|HTTP/[0-9]' "$TEMPLATE" >&2
    return 1
  }
  return 0
}

# ---------------------------------------------------------------------------
# AC24 — the convention
# ---------------------------------------------------------------------------

@test "conventions.md External-tool boundaries carries the review-adapter clarification" {
  local sec
  sec="$(awk '/^## External-tool boundaries/ { inb = 1; next } inb && /^## / { exit } inb' "$CONV")"
  [ -n "$sec" ] || { echo "could not isolate the section; row would be vacuous" >&2; return 1; }
  printf '%s\n' "$sec" | grep -qiE 'review adapter|review-adapter' || {
    echo "the section does not address user-configured review adapters:" >&2
    printf '%s\n' "$sec" | grep -nE '^-' >&2
    return 1
  }
  # The distinction that makes the two compatible: honouring a registry entry
  # the USER wrote is not speccraft routing to a tool.
  printf '%s\n' "$sec" | grep -qiE 'user-configured|the user.s own|configured by the user' || {
    echo "the clarification does not rest on the entry being the USER's choice" >&2
    return 1
  }
}

@test "the clarification names the two modes it licenses" {
  local sec m
  sec="$(awk '/^## External-tool boundaries/ { inb = 1; next } inb && /^## / { exit } inb' "$CONV")"
  for m in codex-plugin subagent; do
    printf '%s\n' "$sec" | grep -qF "$m" || {
      echo "the clarification does not name the '$m' mode" >&2
      return 1
    }
  done
}

@test "the clarification does not weaken the no-routing rule" {
  local sec
  sec="$(awk '/^## External-tool boundaries/ { inb = 1; next } inb && /^## / { exit } inb' "$CONV")"
  # The original prohibition must survive verbatim in substance: speccraft
  # still may not tell the model which tool to call.
  printf '%s\n' "$sec" | grep -qF 'No tool-specific routing in skills, commands, agents, or templates.' || {
    echo "the no-routing rule was altered or removed" >&2
    return 1
  }
  printf '%s\n' "$sec" | grep -qF 'Examples are allowed; recommendations are not.' || {
    echo "the examples-not-recommendations rule was altered or removed" >&2
    return 1
  }
}

# ---------------------------------------------------------------------------
# AC24 — the skill
# ---------------------------------------------------------------------------

@test "the skill documents what the codex-plugin adapter invokes" {
  grep -qE '^#+ .*codex-plugin' "$AUX_SKILL" || {
    echo "the skill has no codex-plugin section:" >&2
    grep -nE '^#+' "$AUX_SKILL" >&2
    return 1
  }
  # What it actually invokes, not just that it exists.
  grep -qE 'task --background|companion' "$AUX_SKILL" || {
    echo "the skill does not say what the codex-plugin adapter invokes" >&2
    return 1
  }
}

@test "the skill states the codex-plugin adapter's guarantees" {
  grep -qiE 'touched|attributab|per job|per-job' "$AUX_SKILL" || {
    echo "the skill does not state what the codex-plugin adapter guarantees" >&2
    return 1
  }
}

@test "the skill documents the subagent adapter and its guarantees" {
  grep -qE '^#+ .*subagent|^#+ reviewer' "$AUX_SKILL" || {
    echo "the skill has no subagent-adapter section:" >&2
    grep -nE '^#+' "$AUX_SKILL" >&2
    return 1
  }
  grep -qiE 'no .*install|needs no external|without an external' "$AUX_SKILL" || {
    echo "the skill does not state the subagent adapter's main guarantee" >&2
    return 1
  }
}

@test "the skill names /codex:setup as the remedy for an unavailable companion" {
  grep -qF '/codex:setup' "$AUX_SKILL" || {
    echo "the skill does not name /codex:setup:" >&2
    grep -niE 'codex-plugin|unavailable' "$AUX_SKILL" >&2
    return 1
  }
}

@test "the skill recommends no external tool" {
  grep -qiE "$RECOMMEND_RE" "$AUX_SKILL" && {
    echo "the skill reads as a speccraft recommendation:" >&2
    grep -niE "$RECOMMEND_RE" "$AUX_SKILL" >&2
    return 1
  }
  return 0
}

@test "the recommendation guard bites on recommending phrasing" {
  # Premise for the two negatives above. Without it, a typo in the pattern
  # would let both pass forever.
  local bad good
  for bad in 'prefer codex for this' 'the Codex plugin is the recommended way' \
             'we recommend the subagent mode' 'you should use codex-plugin' \
             'always use the subagent' 'preferably through the companion'; do
    printf '%s\n' "$bad" | grep -qiE "$RECOMMEND_RE" || {
      echo "the recommendation guard missed: $bad" >&2
      return 1
    }
  done
  # …and does not fire on the example phrasing the convention permits.
  for good in 'such as the Codex plugin' 'for example, codex-plugin' \
              'e.g. the subagent mode' 'the codex-plugin adapter invokes the companion'; do
    printf '%s\n' "$good" | grep -qiE "$RECOMMEND_RE" && {
      echo "the recommendation guard false-positived on permitted prose: $good" >&2
      return 1
    }
  done
  return 0
}

@test "the cross-reviewer template says the flag is omitted below quorum" {
  # The round reports no `single_vendor_approval:` line when quorum was not
  # met (operator ruling, 2026-11-24). A synthesizer that did not know this
  # would guess a value for the frontmatter field — inventing a claim about an
  # approval that never happened.
  local cross="$PLUGIN_DIR/agents/cross-reviewer.md"
  grep -qiE 'only when quorum was met|omit unless quorum' "$cross" || {
    echo "cross-reviewer.md does not say the flag is quorum-gated:" >&2
    grep -nF 'single_vendor_approval' "$cross" >&2
    return 1
  }
  grep -qiE 'omit the field|rather than guessing' "$cross" || {
    echo "cross-reviewer.md does not say what to do when the line is absent" >&2
    return 1
  }
}

@test "the runbook says the per-verdict vendor fields are not quorum-gated" {
  # Only the round-level flag is a claim about an approval; the per-verdict
  # fields describe the verdicts obtained and exist either way (AC23).
  local runbook="$PLUGIN_DIR/skills/review-round/SKILL.md"
  grep -qiE 'NOT gated|not gated' "$runbook" || {
    echo "the runbook does not distinguish the gated flag from the per-verdict fields:" >&2
    grep -nF 'single_vendor_approval' "$runbook" >&2
    return 1
  }
}

# ---------------------------------------------------------------------------
# The shipped default a fresh /speccraft:init can actually run.
#
# Operator ruling, 2026-11-24. The template enabled four reviewers: the three
# `cli` entries by omission (they predate this spec) plus the new `subagent`.
# On a host without those binaries all three dispatches fail,
# `responses_complete` goes false, and NO review.md is written — even though
# the subagent approved. An enabled reviewer whose binary is missing does not
# degrade gracefully; it makes the whole round inert.
#
# So exactly one reviewer ships enabled: the one that needs nothing installed.
# This is also what spec 0054 §6 already described ("with only the `subagent`
# entry enabled, quorum can be met by a Claude reviewer…"), so the template now
# matches its own documentation.
# ---------------------------------------------------------------------------

@test "the template ships exactly one enabled reviewer" {
  local name blk enabled=""
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    blk="$(entry_block "$name")"
    printf '%s\n' "$blk" | grep -qE '^[ \t]*enabled[ \t]*=[ \t]*false' && continue
    enabled="$enabled $name"
  done <<EOF
$(entry_names)
EOF
  [ "$(printf '%s\n' $enabled | grep -c .)" -eq 1 ] || {
    echo "expected exactly 1 enabled reviewer, got:$enabled" >&2
    echo "an enabled reviewer whose binary is absent makes every round inert" >&2
    return 1
  }
}

@test "the one enabled reviewer is the one that needs no binary" {
  local name blk
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    blk="$(entry_block "$name")"
    printf '%s\n' "$blk" | grep -qE '^[ \t]*enabled[ \t]*=[ \t]*false' && continue
    # The enabled one must be the subagent: no cmd, nothing to install.
    printf '%s\n' "$blk" | grep -qE '^[ \t]*mode[ \t]*=[ \t]*"subagent"' || {
      echo "the enabled reviewer '$name' is not the install-free one:" >&2
      printf '%s\n' "$blk" >&2
      return 1
    }
    printf '%s\n' "$blk" | grep -qE '^[ \t]*cmd[ \t]*=' && {
      echo "the enabled reviewer '$name' carries a cmd" >&2
      return 1
    }
  done <<EOF
$(entry_names)
EOF
  return 0
}

@test "each cli entry ships explicitly disabled, not merely absent" {
  # `enabled` is opt-OUT (an absent key means true), so "not enabled" has to be
  # written down. That is exactly how the three cli entries came to be enabled
  # in the first place — nobody ever wrote it.
  local name blk missing=""
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    blk="$(entry_block "$name")"
    printf '%s\n' "$blk" | grep -qE '^[ \t]*mode[ \t]*=[ \t]*"(subagent)"' && continue
    printf '%s\n' "$blk" | grep -qE '^[ \t]*enabled[ \t]*=[ \t]*false' || missing="$missing $name"
  done <<EOF
$(entry_names)
EOF
  [ -z "$missing" ] || {
    echo "entries enabled by omission:$missing" >&2
    return 1
  }
}

@test "the template explains why the cli entries ship disabled" {
  # Without the reason, the next reader re-enables them to be helpful and
  # reintroduces the inert round on every bare host.
  grep -qiE 'ship(s)? DISABLED|ship disabled' "$TEMPLATE" || {
    echo "the template does not say the cli entries ship disabled" >&2
    return 1
  }
  grep -qiE 'no review\.md is written|round is incomplete' "$TEMPLATE" || {
    echo "the template does not say what an absent binary costs:" >&2
    grep -niE 'disabled' "$TEMPLATE" >&2
    return 1
  }
}
