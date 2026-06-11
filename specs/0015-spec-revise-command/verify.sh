#!/usr/bin/env bash
# specs/0015-spec-revise-command/verify.sh
#
# Mechanical verification for AC11 (agents/spec-reviser.md frontmatter shape)
# and AC12 (commands/spec/revise.md frontmatter shape) of spec 0015.
#
# Run from the repo root:
#   bash specs/0015-spec-revise-command/verify.sh
#
# Exit 0 means AC11 and AC12 hold. Non-zero means at least one check failed;
# stderr names which.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
cd "$REPO_ROOT"

fails=0
note_fail() {
  echo "FAIL: $*" >&2
  fails=$((fails + 1))
}
note_pass() {
  echo "pass: $*"
}

# Extract the YAML frontmatter block (between the first two `---` lines) of a
# Markdown file to stdout. Empty output if the file lacks a frontmatter block.
extract_frontmatter() {
  local file="$1"
  [ -f "$file" ] || return 0
  awk '
    BEGIN { state = 0 }
    /^---$/ {
      if (state == 0) { state = 1; next }
      else if (state == 1) { state = 2; next }
    }
    state == 1 { print }
  ' "$file"
}

# ---------------------------------------------------------------------------
# AC11 — agents/spec-reviser.md
# ---------------------------------------------------------------------------
REVISER="agents/spec-reviser.md"

# AC11.a: file exists.
if [ -f "$REVISER" ]; then
  note_pass "AC11.a: $REVISER exists"
else
  note_fail "AC11.a: $REVISER does not exist"
fi

# Subsequent AC11 checks use frontmatter; skip if file missing.
if [ -f "$REVISER" ]; then
  FM_REVISER="$(extract_frontmatter "$REVISER")"

  # AC11.b: name: spec-reviser
  if printf '%s\n' "$FM_REVISER" | grep -qE '^name: spec-reviser$'; then
    note_pass "AC11.b: $REVISER frontmatter has 'name: spec-reviser'"
  else
    note_fail "AC11.b: $REVISER frontmatter missing 'name: spec-reviser'"
  fi

  # AC11.c: description: <non-empty>
  if printf '%s\n' "$FM_REVISER" | grep -qE '^description: .+'; then
    note_pass "AC11.c: $REVISER frontmatter has non-empty description"
  else
    note_fail "AC11.c: $REVISER frontmatter missing non-empty description"
  fi

  # AC11.d: tools list contains Read, Write, Edit, Bash.
  TOOLS_LINE="$(printf '%s\n' "$FM_REVISER" | grep -E '^tools:' || true)"
  ok_tools=1
  for tool in Read Write Edit Bash; do
    if ! printf '%s' "$TOOLS_LINE" | grep -qE "\\b${tool}\\b"; then
      ok_tools=0
      note_fail "AC11.d: $REVISER tools list missing $tool (line: $TOOLS_LINE)"
    fi
  done
  if [ "$ok_tools" = "1" ]; then
    note_pass "AC11.d: $REVISER tools list contains Read, Write, Edit, Bash"
  fi

  # AC11.e: tools list does NOT contain Agent.
  if printf '%s' "$TOOLS_LINE" | grep -qE '\bAgent\b'; then
    note_fail "AC11.e: $REVISER tools list contains forbidden 'Agent' entry"
  else
    note_pass "AC11.e: $REVISER tools list has no 'Agent' entry"
  fi

  # AC11.f: model: <non-empty>
  if printf '%s\n' "$FM_REVISER" | grep -qE '^model: .+'; then
    note_pass "AC11.f: $REVISER frontmatter has non-empty model"
  else
    note_fail "AC11.f: $REVISER frontmatter missing non-empty model"
  fi

  # AC11.g (paired-presence per conventions §grep oracle): body literally
  # pins the Q-DRIFT: token so the runtime e2e anchor is compile-time
  # discoverable. See review.md concern #2.
  if grep -qF 'Q-DRIFT:' "$REVISER"; then
    note_pass "AC11.g: $REVISER body pins the literal 'Q-DRIFT:' token"
  else
    note_fail "AC11.g: $REVISER body does not pin the literal 'Q-DRIFT:' token (Q-DRIFT anchor must be load-bearing in the prompt per review.md)"
  fi

  # AC11.h (paired-absence): body explicitly forbids editing command-owned
  # frontmatter keys. Structural shape: a "Forbidden edits" section heading
  # (or equivalent prohibition phrasing) appears, AND all four command-owned
  # key names appear in the body, AND at least one prohibition verb appears.
  # Per-line grep is sufficient since the four keys are listed in a Markdown
  # bullet list (one per line).
  if grep -qiE '^#+ +(forbidden edits|prohibited edits|do not edit|forbidden frontmatter)' "$REVISER" \
     && grep -qiE '(must not|must never|never modify|forbidden|prohibited)' "$REVISER" \
     && grep -qF 'revision:' "$REVISER" \
     && grep -qF 'status:' "$REVISER" \
     && grep -qF 'id:' "$REVISER" \
     && grep -qF 'created:' "$REVISER"; then
    note_pass "AC11.h: $REVISER body has Forbidden-edits section + all four command-owned keys + prohibition phrasing"
  else
    note_fail "AC11.h: $REVISER body missing one of: Forbidden-edits heading, prohibition phrasing, or one of the four command-owned key names (revision:/status:/id:/created:)"
  fi
fi

# ---------------------------------------------------------------------------
# AC12 — commands/spec/revise.md
# ---------------------------------------------------------------------------
REVISE_CMD="commands/spec/revise.md"

# AC12.a: file exists.
if [ -f "$REVISE_CMD" ]; then
  note_pass "AC12.a: $REVISE_CMD exists"
else
  note_fail "AC12.a: $REVISE_CMD does not exist"
fi

if [ -f "$REVISE_CMD" ]; then
  FM_REVISE="$(extract_frontmatter "$REVISE_CMD")"

  # AC12.b: description: <non-empty>
  if printf '%s\n' "$FM_REVISE" | grep -qE '^description: .+'; then
    note_pass "AC12.b: $REVISE_CMD frontmatter has non-empty description"
  else
    note_fail "AC12.b: $REVISE_CMD frontmatter missing non-empty description"
  fi

  # AC12.c: argument-hint: present (value may be empty string "" since
  # revise takes no args, mirroring sibling commands/spec/close.md which
  # OMITS argument-hint entirely. The contract accepts either: an explicit
  # `argument-hint: ""` line OR omission of the line entirely.)
  if printf '%s\n' "$FM_REVISE" | grep -qE '^argument-hint:'; then
    # If present, value should be "" (no positional args).
    if printf '%s\n' "$FM_REVISE" | grep -qE '^argument-hint: *""$'; then
      note_pass "AC12.c: $REVISE_CMD frontmatter has argument-hint: \"\" (no args)"
    else
      note_fail "AC12.c: $REVISE_CMD argument-hint present but value is not \"\" (revise takes no args)"
    fi
  else
    # Omission is acceptable per sibling close.md precedent.
    note_pass "AC12.c: $REVISE_CMD frontmatter omits argument-hint (acceptable per close.md precedent)"
  fi

  # AC12.d: allowed-tools list contains Read, Write, Edit, Bash.
  ALLOWED_LINE="$(printf '%s\n' "$FM_REVISE" | grep -E '^allowed-tools:' || true)"
  ok_allowed=1
  for tool in Read Write Edit Bash; do
    if ! printf '%s' "$ALLOWED_LINE" | grep -qE "\\b${tool}\\b"; then
      ok_allowed=0
      note_fail "AC12.d: $REVISE_CMD allowed-tools missing $tool (line: $ALLOWED_LINE)"
    fi
  done
  if [ "$ok_allowed" = "1" ]; then
    note_pass "AC12.d: $REVISE_CMD allowed-tools contains Read, Write, Edit, Bash"
  fi

  # AC12.e (paired-presence): the command body sources the helper library
  # per the spec-0015 §Mechanism design.
  if grep -qF 'commands/spec/revise.lib.sh' "$REVISE_CMD"; then
    note_pass "AC12.e: $REVISE_CMD body references commands/spec/revise.lib.sh"
  else
    note_fail "AC12.e: $REVISE_CMD body does not source commands/spec/revise.lib.sh"
  fi
fi

# ---------------------------------------------------------------------------
echo
if [ "$fails" -eq 0 ]; then
  echo "all acceptance checks passed (spec 0015 AC11+AC12)"
  exit 0
else
  echo "$fails acceptance check(s) failed" >&2
  exit 1
fi
