#!/usr/bin/env bats
# Spec 0054 AC8 — the payload's two ends.
#
# A SEPARATE file from spec-review-payload.bats on purpose: that one is spec
# 0052's byte-boundary floor and must keep passing unedited, so this spec adds
# its rows beside it rather than inside it.
#
# Why these two bytes matter. The Codex companion trims the prompt it is handed
# (`options.prompt?.trim()`, scripts/lib/codex.mjs:1127 in 1.0.6). That
# transformation cannot be switched off, so this spec pins the payload's ends
# instead: begin with a non-whitespace byte and end with exactly one newline,
# and the companion's trim then removes exactly that final newline and nothing
# else. Without the pin, "what the budget measured" and "what the reviewer
# read" differ by an unknown number of bytes.
#
# Every assertion measures the FILE, never a command substitution
# (.speccraft/conventions.md §"A byte-exactness contract measures a FILE"):
# `$(...)` strips trailing newlines, so a capture-based check of a trailing
# newline cannot fail and would be the one assertion guaranteed to be inert.

setup() {
  PLUGIN_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  LIB="$PLUGIN_DIR/commands/spec/review.lib.sh"
  export PATH="$PLUGIN_DIR/bin:$PATH"
  TEST_DIR="$(mktemp -d)"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# make_corpus — the same shape spec-review-payload.bats builds, duplicated
# rather than shared because that file is the 0052 floor and this spec does not
# edit it.
make_corpus() {
  mkdir -p "$TEST_DIR/.speccraft" "$TEST_DIR/round"
  printf '# Guardrails\n\nGUARDRAILS-BODY\n' > "$TEST_DIR/.speccraft/guardrails.md"
  printf '# Index\n\nINDEX-BODY\n'           > "$TEST_DIR/.speccraft/index.md"
  printf '# Arch\n\n## Arch One\n\nBODY\n'   > "$TEST_DIR/.speccraft/architecture.md"
  printf '# Conv\n\n## Conv One\n\nBODY\n'   > "$TEST_DIR/.speccraft/conventions.md"
  printf '# Spec\n\nFROZEN-SPEC-BODY\n'      > "$TEST_DIR/round/spec-frozen.md"
  printf 'TEMPLATE-HEAD\n\nDiff:\n{{DIFF}}\n\nSections:\n{{CHANGED_SECTIONS}}\n' \
    > "$TEST_DIR/template.md"
  cd "$TEST_DIR"
}

# first_byte_hex <file> — the file's first byte, as hex. Hex rather than
# `od -c`, because od -c renders a space AS a space and awk would then skip it
# as field separation, making the one case we care about invisible.
first_byte_hex() {
  od -An -tx1 -N1 "$1" | awk '{print $1}'
}

# assert_begins_nonblank <file> — 0a newline, 20 space and 09 tab are the three
# ways a composer leaks leading whitespace.
assert_begins_nonblank() {
  local b
  b="$(first_byte_hex "$1")"
  case "$b" in
    0a | 20 | 09 | '')
      echo "payload begins with whitespace (first byte 0x$b):" >&2
      head -c 120 "$1" | od -An -c | head -3 >&2
      return 1
      ;;
  esac
  return 0
}

# assert_one_trailing_newline <file> — exactly one. Both halves are needed: the
# last byte must BE a newline, and the byte before it must NOT be, or "ends
# with a newline" would also accept a payload ending in a blank line.
assert_one_trailing_newline() {
  local f="$1" last prev
  last="$(tail -c 1 "$f" | od -An -tx1 | awk '{print $1}')"
  [ "$last" = "0a" ] || {
    echo "payload does not end with a newline (last byte 0x$last):" >&2
    tail -c 60 "$f" | od -An -c | head -3 >&2
    return 1
  }
  prev="$(tail -c 2 "$f" | od -An -tx1 | awk '{print $1}')"
  [ "$prev" != "0a" ] || {
    echo "payload ends with more than one newline:" >&2
    tail -c 60 "$f" | od -An -c | head -3 >&2
    return 1
  }
  return 0
}

# compose_full <out> — a full round: inline files plus reference records.
compose_full() {
  review_compose_payload "$TEST_DIR/template.md" round/spec-frozen.md \
    --inline .speccraft/guardrails.md .speccraft/index.md \
    --reference .speccraft/architecture.md .speccraft/conventions.md \
    --digest-out "$TEST_DIR/digests.txt" > "$1"
}

# compose_scoped <out> — a scoped `--diff` round. The prior review.md travels
# as an INLINE file; a recipe that omits it silently composes a round with no
# prior review in it at all.
compose_scoped() {
  printf '# Prior review\n\nPRIOR-REVIEW-BODY\n' > "$TEST_DIR/review.md"
  review_compose_payload "$TEST_DIR/template.md" round/spec-frozen.md \
    --diff 'diff --git a/x b/x' \
    --changed '~ ## What (#1)' \
    --inline .speccraft/guardrails.md review.md \
    --reference .speccraft/architecture.md \
    --digest-out "$TEST_DIR/digests.txt" > "$1"
}

@test "the full-round payload begins with a non-whitespace byte" {
  source "$LIB"; make_corpus
  compose_full "$TEST_DIR/full.md"
  assert_begins_nonblank "$TEST_DIR/full.md"
}

@test "the full-round payload ends with exactly one newline" {
  source "$LIB"; make_corpus
  compose_full "$TEST_DIR/full.md"
  assert_one_trailing_newline "$TEST_DIR/full.md"
}

@test "the scoped --diff payload begins with a non-whitespace byte" {
  source "$LIB"; make_corpus
  compose_scoped "$TEST_DIR/scoped.md"
  assert_begins_nonblank "$TEST_DIR/scoped.md"
}

@test "the scoped --diff payload ends with exactly one newline" {
  source "$LIB"; make_corpus
  compose_scoped "$TEST_DIR/scoped.md"
  assert_one_trailing_newline "$TEST_DIR/scoped.md"
}

@test "a reference-less round still ends with exactly one newline" {
  source "$LIB"; make_corpus
  # This branch returns EARLY, after the "(none)" line, so it bypasses any
  # normalization placed at the end of the composer's happy path. The plan
  # called this one out specifically.
  review_compose_payload "$TEST_DIR/template.md" round/spec-frozen.md \
    --inline .speccraft/guardrails.md \
    --digest-out "$TEST_DIR/digests.txt" > "$TEST_DIR/noref.md"

  assert_begins_nonblank "$TEST_DIR/noref.md"
  assert_one_trailing_newline "$TEST_DIR/noref.md"
  grep -qF '(none)' "$TEST_DIR/noref.md"
}

@test "an input ending with no newline still yields exactly one trailing newline" {
  source "$LIB"; make_corpus
  # No trailing newline anywhere a composer might copy one from: not the
  # template, not the frozen spec, not the last inline file.
  printf 'TEMPLATE-HEAD\n\nNO-TRAILING-NEWLINE'      > "$TEST_DIR/template.md"
  printf '# Spec\n\nFROZEN-NO-NEWLINE'                > "$TEST_DIR/round/spec-frozen.md"
  printf '# Guardrails\n\nGUARDRAILS-NO-NEWLINE'      > "$TEST_DIR/.speccraft/guardrails.md"

  compose_full "$TEST_DIR/nonl.md"
  assert_begins_nonblank "$TEST_DIR/nonl.md"
  assert_one_trailing_newline "$TEST_DIR/nonl.md"
}

@test "an input ending with several newlines is collapsed to exactly one" {
  source "$LIB"; make_corpus
  printf '# Conv\n\n## Conv One\n\nBODY\n\n\n\n\n' > "$TEST_DIR/.speccraft/conventions.md"
  printf '# Spec\n\nFROZEN\n\n\n\n'               > "$TEST_DIR/round/spec-frozen.md"
  printf '# Index\n\nINDEX\n\n\n\n'               > "$TEST_DIR/.speccraft/index.md"

  compose_full "$TEST_DIR/manynl.md"
  assert_one_trailing_newline "$TEST_DIR/manynl.md"
}

@test "a template whose first line is blank leaks no leading newline" {
  source "$LIB"; make_corpus
  # The most likely real cause of a leading newline: a template that opens with
  # a blank line, which reads as harmless in an editor.
  printf '\n\nTEMPLATE-HEAD\n\nDiff:\n{{DIFF}}\n' > "$TEST_DIR/template.md"

  compose_full "$TEST_DIR/blankhead.md"
  assert_begins_nonblank "$TEST_DIR/blankhead.md"
  # The content itself must survive the trim — this normalizes the ends, it
  # does not drop the payload's first real line.
  grep -qxF 'TEMPLATE-HEAD' "$TEST_DIR/blankhead.md"
}

@test "a template whose first line is indented still begins with a non-whitespace byte" {
  source "$LIB"; make_corpus
  printf '    INDENTED-HEAD\n\nDiff:\n{{DIFF}}\n' > "$TEST_DIR/template.md"

  compose_full "$TEST_DIR/indent.md"
  assert_begins_nonblank "$TEST_DIR/indent.md"
  grep -qF 'INDENTED-HEAD' "$TEST_DIR/indent.md"
}

@test "normalizing the ends does not disturb the payload interior" {
  source "$LIB"; make_corpus
  compose_full "$TEST_DIR/full.md"

  # The whole point of the trim contract is that ONLY the ends are touched.
  # Blank lines inside the payload separate sections and must survive, or the
  # reviewer reads a wall of text.
  grep -qxF 'TEMPLATE-HEAD' "$TEST_DIR/full.md"
  grep -qxF 'FROZEN-SPEC-BODY' "$TEST_DIR/full.md"
  grep -qxF 'GUARDRAILS-BODY' "$TEST_DIR/full.md"
  grep -qxF '## Reference files (read these yourself)' "$TEST_DIR/full.md"
  # An interior blank line, asserted positively.
  awk 'BEGIN { n = 0 } /^$/ { n++ } END { exit (n > 0 ? 0 : 1) }' "$TEST_DIR/full.md"
  # And the digest sidecar still carries both reference files.
  [ "$(grep -c . "$TEST_DIR/digests.txt")" -eq 2 ]
}

@test "the composed payload is never empty" {
  source "$LIB"; make_corpus
  # A normalizer that stripped whitespace-only content could reduce a payload
  # to zero bytes, which would dispatch an empty review and still "pass" both
  # end assertions vacuously.
  compose_full "$TEST_DIR/full.md"
  [ -s "$TEST_DIR/full.md" ]
  [ "$(wc -c < "$TEST_DIR/full.md")" -gt 100 ]
}
