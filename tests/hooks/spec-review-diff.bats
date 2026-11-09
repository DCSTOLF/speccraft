#!/usr/bin/env bats
# Spec 0035 — diff-focused re-review. Covers the AC7a re-review prompt template
# (grep oracle, both polarities), the AC8/AC9 provenance-gate helpers in
# commands/spec/review.lib.sh, and the AC7b/AC11 payload builder.

setup() {
  PLUGIN_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  TEMPLATE="$PLUGIN_DIR/templates/prompts/re-review.md"
  LIB="$PLUGIN_DIR/commands/spec/review.lib.sh"
  export PATH="$PLUGIN_DIR/bin:$PATH"
  TEST_DIR="$(mktemp -d)"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# ---- AC7a: template grep oracle (positive + negative, scoped to the template) --

@test "re-review template exists" {
  [ -f "$TEMPLATE" ]
}

@test "re-review template carries {{DIFF}} and {{CHANGED_SECTIONS}} markers" {
  grep -qF '{{DIFF}}' "$TEMPLATE"
  grep -qF '{{CHANGED_SECTIONS}}' "$TEMPLATE"
}

@test "re-review template carries the regression-sweep instruction" {
  grep -qF 'assess ONLY the deltas since last review + regressions' "$TEMPLATE"
}

@test "re-review template forbids whole-spec-review language (negative needle, template only)" {
  ! grep -qiF 'read the whole spec' "$TEMPLATE"
  ! grep -qiF 'from scratch' "$TEMPLATE"
  ! grep -qiF 'review the entire spec' "$TEMPLATE"
}

# ---- the scoped template must teach the attestation shape --------------------
# Spec 0054 review round 3 went INERT on FORMAT, not access: both reviewers read
# the reference files and computed correct digests, then invented their own
# shapes (codex a YAML map `  <path>: <digest>`; claude-p one entry per line,
# `- path: X, sha256: Y`). Neither pairs up in _review_parse_reference_access.
# Cause: re-review.md — unlike review.md — never showed the accepted schema and
# never named reference_access among the fields it asks for. A scoped round
# therefore could not attest no matter how honest the reviewer was.

@test "re-review template names reference_access among the required output fields" {
  grep -qF 'reference_access' "$TEMPLATE"
  grep -qF 'reference_access_failures' "$TEMPLATE"
}

@test "re-review template's documented attestation shape round-trips through the real parser" {
  # Not a string match: extract the block the template DOCUMENTS, fill the
  # placeholders, and feed it to the parser the validator actually uses. If the
  # template teaches a shape the parser cannot pair up, this fails.
  local block resp
  block="$TEST_DIR/block.txt"; resp="$TEST_DIR/resp.out"
  awk '/^reference_access:/{f=1} f{print} f&&/sha256:/{exit}' "$TEMPLATE" > "$block"
  [ -s "$block" ]
  sed -e 's|"<repo-relative path, exactly as given to you>"|.speccraft/architecture.md|' \
      -e "s|\"<the digest you computed AFTER reading that file>\"|$(printf 'a%.0s' $(seq 64))|" \
      "$block" > "$resp"

  source "$LIB"
  run _review_parse_reference_access "$resp"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qx 'HAS-ACCESS'
  printf '%s\n' "$output" | grep -qx 'ACCESS-PATH .speccraft/architecture.md'
  printf '%s\n' "$output" | grep -q '^ACCESS-SHA aaaa'
}

@test "the two shapes real reviewers invented are rejected (round-3 regression)" {
  # Proves the negative assertion bites: these are the literal shapes codex and
  # claude-p emitted in round 3, and both must fail to pair up.
  local dig="$TEST_DIR/dig"; : > "$dig"
  local d="$(printf 'a%.0s' $(seq 64))"
  printf '%s  .speccraft/architecture.md\n' "$d" > "$dig"
  source "$LIB"

  # codex's shape: a YAML map, no `- path:` key at all.
  printf 'reference_access:\n  .speccraft/architecture.md: %s\n' "$d" > "$TEST_DIR/map.out"
  run review_validate_reference_access "$TEST_DIR/map.out" "$dig"
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid:missing-path"* ]]

  # claude-p's shape: path and sha256 collapsed onto one line.
  #
  # The reason is pinned, not matched loosely as *"invalid:"*: a validator that
  # rejected every response for an unrelated reason would satisfy a bare
  # "something was invalid" assertion, and this case exists to prove the
  # pairing logic specifically. The map form above yields missing-path (the
  # path never parses); this one yields malformed (a path with no digest
  # before end of stream) — two shapes, two distinct reasons.
  printf 'reference_access:\n- path: .speccraft/architecture.md, sha256: %s\n' "$d" > "$TEST_DIR/oneline.out"
  run review_validate_reference_access "$TEST_DIR/oneline.out" "$dig"
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid:malformed"* ]]
}

# ---- AC8/AC9: usable reviewed_sha256 parser + provenance-gate classifier ------

VALID_SHA="0000000000000000000000000000000000000000000000000000000000000000"

@test "review_reviewed_sha256 extracts the single valid line" {
  source "$LIB"
  printf '# Review\n\nreviewed_sha256: %s\n' "$VALID_SHA" > "$TEST_DIR/review.md"
  run review_reviewed_sha256 "$TEST_DIR/review.md"
  [ "$status" -eq 0 ]
  [ "$output" = "$VALID_SHA" ]
}

@test "review_reviewed_sha256 rejects zero valid lines" {
  source "$LIB"
  printf '# Review\n\nno fingerprint here\n' > "$TEST_DIR/review.md"
  run review_reviewed_sha256 "$TEST_DIR/review.md"
  [ "$status" -ne 0 ]
}

@test "review_reviewed_sha256 rejects multiple lines" {
  source "$LIB"
  printf 'reviewed_sha256: %s\nreviewed_sha256: %s\n' "$VALID_SHA" "$VALID_SHA" > "$TEST_DIR/review.md"
  run review_reviewed_sha256 "$TEST_DIR/review.md"
  [ "$status" -ne 0 ]
}

@test "review_reviewed_sha256 rejects malformed (uppercase, short, extra space)" {
  source "$LIB"
  printf 'reviewed_sha256: ABCDEF\n' > "$TEST_DIR/a.md"
  run review_reviewed_sha256 "$TEST_DIR/a.md"; [ "$status" -ne 0 ]
  printf 'reviewed_sha256:  %s\n' "$VALID_SHA" > "$TEST_DIR/b.md"  # two spaces
  run review_reviewed_sha256 "$TEST_DIR/b.md"; [ "$status" -ne 0 ]
}

@test "review_classify: no snapshot -> full-review" {
  source "$LIB"
  run review_classify false false null ""
  [ "$output" = "full-review" ]
}

@test "review_classify: snapshot but prior != base -> full-review" {
  source "$LIB"
  run review_classify true true "$VALID_SHA" "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
  [ "$output" = "full-review" ]
}

@test "review_classify: snapshot, unusable (empty) prior -> full-review" {
  source "$LIB"
  run review_classify true false "$VALID_SHA" ""
  [ "$output" = "full-review" ]
}

@test "review_classify: snapshot, prior==base, changed=false -> short-circuit" {
  source "$LIB"
  run review_classify true false "$VALID_SHA" "$VALID_SHA"
  [ "$output" = "short-circuit" ]
}

@test "review_classify: snapshot, prior==base, changed=true -> scoped" {
  source "$LIB"
  run review_classify true true "$VALID_SHA" "$VALID_SHA"
  [ "$output" = "scoped" ]
}

# ---- AC7b/AC11: the scoped payload sources the frozen image -------------------
#
# Re-pointed by spec 0052 T19 from `review_build_payload` to
# `review_compose_payload`, which retired it: there is now exactly ONE composer
# for both the full round and the scoped `--diff` round, so exactly one thing
# decides what bytes are sent and the byte budget measures all of them. These two
# criteria are unchanged — the frozen image is still the spec source and the
# prior review still rides along as regression-context evidence; it is the
# evidence's channel that moved (the composer's `--inline` set).

@test "scoped payload embeds prior review.md body, frozen snapshot, diff and sections" {
  source "$LIB"
  printf 'SNAPSHOT-MARKER spec body\n' > "$TEST_DIR/review-snapshot.md"
  printf '# Prior Review\nPRIOR-MARKER\nreviewed_sha256: %s\n' "$VALID_SHA" > "$TEST_DIR/review.md"
  run review_compose_payload "$TEMPLATE" "$TEST_DIR/review-snapshot.md" \
    --inline "$TEST_DIR/review.md" \
    --digest-out "$TEST_DIR/digests.txt" \
    --diff "DIFF-MARKER" --changed "SECTIONS-MARKER"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SNAPSHOT-MARKER"* ]]
  [[ "$output" == *"PRIOR-MARKER"* ]]
  [[ "$output" == *"DIFF-MARKER"* ]]
  [[ "$output" == *"SECTIONS-MARKER"* ]]
  [[ "$output" == *"assess ONLY the deltas since last review + regressions"* ]]
}

@test "payload builds from the frozen snapshot after spec.md is removed (AC11 command oracle)" {
  source "$LIB"
  specDir="$TEST_DIR/specs/0001-x"
  mkdir -p "$specDir"
  printf 'FROZEN-CONTENT via promote\n' > "$specDir/spec.md"
  # promote freezes the snapshot from spec.md bytes
  run speccraft-state review-diff "$specDir" --promote
  [ "$status" -eq 0 ]
  # remove spec.md: the composer must read only the <spec-src> it is given
  rm "$specDir/spec.md"
  printf '# Prior\nreviewed_sha256: %s\n' "$VALID_SHA" > "$specDir/review.md"
  run review_compose_payload "$TEMPLATE" "$specDir/review-snapshot.md" \
    --inline "$specDir/review.md" \
    --digest-out "$TEST_DIR/digests.txt" \
    --diff "d" --changed "s"
  [ "$status" -eq 0 ]
  [[ "$output" == *"FROZEN-CONTENT"* ]]
}

@test "review_build_payload is retired — there is exactly one composer" {
  source "$LIB"
  # Two composers means two answers to "what bytes are sent", and the budget can
  # only measure one of them.
  run type -t review_build_payload
  [ "$status" -ne 0 ]
  run grep -rnF 'review_build_payload' "$PLUGIN_DIR/commands" "$PLUGIN_DIR/agents"
  [ "$status" -ne 0 ]
}
