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

# ---- AC7b/AC11: scoped payload builder sources the frozen snapshot ------------

@test "scoped payload embeds prior review.md body, frozen snapshot, diff and sections" {
  source "$LIB"
  printf 'SNAPSHOT-MARKER spec body\n' > "$TEST_DIR/review-snapshot.md"
  printf '# Prior Review\nPRIOR-MARKER\nreviewed_sha256: %s\n' "$VALID_SHA" > "$TEST_DIR/review.md"
  run review_build_payload "$TEMPLATE" "$TEST_DIR/review-snapshot.md" "$TEST_DIR/review.md" "DIFF-MARKER" "SECTIONS-MARKER"
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
  # remove spec.md: the command must source payloads from review-snapshot.md, never spec.md
  rm "$specDir/spec.md"
  printf '# Prior\nreviewed_sha256: %s\n' "$VALID_SHA" > "$specDir/review.md"
  run review_build_payload "$TEMPLATE" "$specDir/review-snapshot.md" "$specDir/review.md" "d" "s"
  [ "$status" -eq 0 ]
  [[ "$output" == *"FROZEN-CONTENT"* ]]
}
