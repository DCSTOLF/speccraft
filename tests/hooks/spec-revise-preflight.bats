#!/usr/bin/env bats
# Tests for commands/spec/revise.lib.sh — the testable shell helpers backing
# /speccraft:spec:revise (spec 0015).
#
# Covers preflight error paths (AC1, AC2, AC9, AC10) plus internal helpers
# named in spec 0015 §Mechanism: status-gate, active-spec-set check,
# ensure-revision-field, archive-collision preflight, source-artifact
# preflight.
#
# Helpers under test live in $PLUGIN_DIR/commands/spec/revise.lib.sh.
# Each @test sources the lib fresh (bats per-test subshell semantics) and
# exercises one helper against a seeded $TEST_REPO. Sourcing a nonexistent
# lib is the RED state; functions become defined as T4 lands.

setup() {
  PLUGIN_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  REVISE_LIB="$PLUGIN_DIR/commands/spec/revise.lib.sh"
  TEST_REPO="$(mktemp -d)"
  mkdir -p "$TEST_REPO/.speccraft" "$TEST_REPO/specs"
  # Empty state.json so default tests don't surface unrelated active-spec state.
  cat > "$TEST_REPO/.speccraft/state.json" <<'JSON'
{"version":1,"session":{"id":"","edited_test_files":[],"edited_prod_files":[]}}
JSON
  export REVISE_LIB
  export TEST_REPO
}

teardown() {
  rm -rf "$TEST_REPO"
}

# seed_spec creates $TEST_REPO/specs/0099-fixture/spec.md with a minimal
# frontmatter and body shape. Usage:
#   seed_spec <status> [revision] [packages_yaml]
# Defaults: revision=0, packages_yaml='[]'
seed_spec() {
  local status="$1"
  local revision="${2:-0}"
  local packages="${3:-[]}"
  local spec_dir="$TEST_REPO/specs/0099-fixture"
  mkdir -p "$spec_dir"
  if [ "$revision" = "MISSING" ]; then
    cat > "$spec_dir/spec.md" <<EOF
---
id: "0099"
title: "fixture"
status: $status
created: 2026-06-10
authors: [test]
packages: $packages
---

# Spec 0099 — fixture

## Why

test fixture.

## What

test fixture body.

## Acceptance criteria

1. fixture AC.

## Out of scope

- nothing.

## Open questions

_none_
EOF
  else
    cat > "$spec_dir/spec.md" <<EOF
---
id: "0099"
title: "fixture"
status: $status
created: 2026-06-10
authors: [test]
packages: $packages
revision: $revision
---

# Spec 0099 — fixture

## Why

test fixture.

## What

test fixture body.

## Acceptance criteria

1. fixture AC.

## Out of scope

- nothing.

## Open questions

_none_
EOF
  fi
  echo "$spec_dir"
}

# load_lib sources the revise.lib.sh if present. Each @test calls this; in
# the RED phase the file is absent and the source returns non-zero — the
# subsequent function call then fails because the function is undefined.
load_lib() {
  # shellcheck disable=SC1090
  if [ -f "$REVISE_LIB" ]; then source "$REVISE_LIB"; fi
}

# ---------------------------------------------------------------------------
# preflight_status_gate — rejects closed/archived/in-progress; accepts
# draft/reviewed/planned. AC1 (revisable-status gate).
# ---------------------------------------------------------------------------

@test "preflight_status_gate rejects closed" {
  spec_dir="$(seed_spec closed)"
  load_lib
  run preflight_status_gate "$spec_dir/spec.md"
  [ "$status" -ne 0 ]
  [[ "$output" == *"closed"* ]]
}

@test "preflight_status_gate rejects archived" {
  spec_dir="$(seed_spec archived)"
  load_lib
  run preflight_status_gate "$spec_dir/spec.md"
  [ "$status" -ne 0 ]
  [[ "$output" == *"archived"* ]]
}

@test "preflight_status_gate rejects in-progress" {
  spec_dir="$(seed_spec in-progress)"
  load_lib
  run preflight_status_gate "$spec_dir/spec.md"
  [ "$status" -ne 0 ]
  [[ "$output" == *"in-progress"* ]]
}

@test "preflight_status_gate accepts draft" {
  spec_dir="$(seed_spec draft)"
  load_lib
  run preflight_status_gate "$spec_dir/spec.md"
  [ "$status" -eq 0 ]
}

@test "preflight_status_gate accepts reviewed" {
  spec_dir="$(seed_spec reviewed)"
  load_lib
  run preflight_status_gate "$spec_dir/spec.md"
  [ "$status" -eq 0 ]
}

@test "preflight_status_gate accepts planned" {
  spec_dir="$(seed_spec planned)"
  load_lib
  run preflight_status_gate "$spec_dir/spec.md"
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# preflight_active_spec_set — errors when state.json has empty active_spec
# field, mentions /spec:new in error. AC2.
# ---------------------------------------------------------------------------

@test "preflight_active_spec_set errors on empty active_spec" {
  cat > "$TEST_REPO/.speccraft/state.json" <<'JSON'
{"version":1,"session":{"id":"","edited_test_files":[],"edited_prod_files":[]}}
JSON
  load_lib
  run preflight_active_spec_set "$TEST_REPO/.speccraft/state.json"
  [ "$status" -ne 0 ]
  [[ "$output" == *"/spec:new"* ]] || [[ "$output" == *"/speccraft:spec:new"* ]]
}

@test "preflight_active_spec_set accepts non-empty active_spec" {
  cat > "$TEST_REPO/.speccraft/state.json" <<'JSON'
{"version":1,"active_spec":"0099-fixture","session":{"id":"","edited_test_files":[],"edited_prod_files":[]}}
JSON
  load_lib
  run preflight_active_spec_set "$TEST_REPO/.speccraft/state.json"
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# ensure_revision_field — inserts revision: 0 when missing; idempotent when
# present. Covers spec §Mechanism step 2a.
# ---------------------------------------------------------------------------

@test "ensure_revision_field inserts revision: 0 when missing" {
  spec_dir="$(seed_spec draft MISSING)"
  load_lib
  # Pre-state: no revision: line.
  ! grep -qE '^revision:' "$spec_dir/spec.md"
  run ensure_revision_field "$spec_dir/spec.md"
  [ "$status" -eq 0 ]
  # Post-state: revision: 0 in frontmatter.
  grep -qE '^revision: 0$' "$spec_dir/spec.md"
}

@test "ensure_revision_field is idempotent when revision present" {
  spec_dir="$(seed_spec reviewed 2)"
  before="$(cat "$spec_dir/spec.md")"
  load_lib
  run ensure_revision_field "$spec_dir/spec.md"
  [ "$status" -eq 0 ]
  after="$(cat "$spec_dir/spec.md")"
  [ "$before" = "$after" ]
}

# ---------------------------------------------------------------------------
# preflight_archive_collisions — errors if review-r<N>.md, plan-r<N>.md,
# or tasks-r<N>.md already exists. AC9 + claude-p symmetric variant.
# ---------------------------------------------------------------------------

@test "preflight_archive_collisions reviewed r0 review-archive conflict" {
  spec_dir="$(seed_spec reviewed 0)"
  touch "$spec_dir/review.md" "$spec_dir/review-r0.md"
  load_lib
  run preflight_archive_collisions "$spec_dir" reviewed 0
  [ "$status" -ne 0 ]
  [[ "$output" == *"review-r0.md"* ]]
}

@test "preflight_archive_collisions planned r2 plan-archive conflict" {
  spec_dir="$(seed_spec planned 2)"
  touch "$spec_dir/review.md" "$spec_dir/plan.md" "$spec_dir/tasks.md" "$spec_dir/plan-r2.md"
  load_lib
  run preflight_archive_collisions "$spec_dir" planned 2
  [ "$status" -ne 0 ]
  [[ "$output" == *"plan-r2.md"* ]]
}

@test "preflight_archive_collisions planned r2 tasks-archive conflict" {
  spec_dir="$(seed_spec planned 2)"
  touch "$spec_dir/review.md" "$spec_dir/plan.md" "$spec_dir/tasks.md" "$spec_dir/tasks-r2.md"
  load_lib
  run preflight_archive_collisions "$spec_dir" planned 2
  [ "$status" -ne 0 ]
  [[ "$output" == *"tasks-r2.md"* ]]
}

@test "preflight_archive_collisions clean reviewed exits zero" {
  spec_dir="$(seed_spec reviewed 0)"
  touch "$spec_dir/review.md"
  load_lib
  run preflight_archive_collisions "$spec_dir" reviewed 0
  [ "$status" -eq 0 ]
}

@test "preflight_archive_collisions clean planned exits zero" {
  spec_dir="$(seed_spec planned 2)"
  touch "$spec_dir/review.md" "$spec_dir/plan.md" "$spec_dir/tasks.md"
  load_lib
  run preflight_archive_collisions "$spec_dir" planned 2
  [ "$status" -eq 0 ]
}

@test "preflight_archive_collisions draft source has nothing to check" {
  spec_dir="$(seed_spec draft 0)"
  load_lib
  run preflight_archive_collisions "$spec_dir" draft 0
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# preflight_source_artifacts — verifies review.md / plan.md / tasks.md exist
# for reviewed / planned sources. AC10.
# ---------------------------------------------------------------------------

@test "preflight_source_artifacts reviewed missing review.md errors" {
  spec_dir="$(seed_spec reviewed 0)"
  # No review.md created.
  load_lib
  run preflight_source_artifacts "$spec_dir" reviewed
  [ "$status" -ne 0 ]
  [[ "$output" == *"review.md"* ]]
}

@test "preflight_source_artifacts reviewed with review.md exits zero" {
  spec_dir="$(seed_spec reviewed 0)"
  touch "$spec_dir/review.md"
  load_lib
  run preflight_source_artifacts "$spec_dir" reviewed
  [ "$status" -eq 0 ]
}

@test "preflight_source_artifacts planned missing tasks.md errors" {
  spec_dir="$(seed_spec planned 2)"
  touch "$spec_dir/review.md" "$spec_dir/plan.md"
  # No tasks.md.
  load_lib
  run preflight_source_artifacts "$spec_dir" planned
  [ "$status" -ne 0 ]
  [[ "$output" == *"tasks.md"* ]]
}

@test "preflight_source_artifacts planned missing plan.md errors" {
  spec_dir="$(seed_spec planned 2)"
  touch "$spec_dir/review.md" "$spec_dir/tasks.md"
  load_lib
  run preflight_source_artifacts "$spec_dir" planned
  [ "$status" -ne 0 ]
  [[ "$output" == *"plan.md"* ]]
}

@test "preflight_source_artifacts planned with all three exits zero" {
  spec_dir="$(seed_spec planned 2)"
  touch "$spec_dir/review.md" "$spec_dir/plan.md" "$spec_dir/tasks.md"
  load_lib
  run preflight_source_artifacts "$spec_dir" planned
  [ "$status" -eq 0 ]
}

@test "preflight_source_artifacts draft requires nothing" {
  spec_dir="$(seed_spec draft 0)"
  load_lib
  run preflight_source_artifacts "$spec_dir" draft
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# extract_identifiers — pulls tokens from single-backtick spans inside §What,
# §Acceptance criteria, §Out of scope. Tokens must match
# [A-Za-z_][A-Za-z0-9_]{3,} (≥4 chars). Fenced code blocks are EXCLUDED
# (per spec 0015 plan-time refinement). Output is deduped via sort -u.
# Implements spec 0015 §Identifier-extraction rule.
# ---------------------------------------------------------------------------

# write_spec_with_what seeds a spec.md with a custom §What block body. The
# What body is appended after the standard frontmatter and `## Why` section.
write_spec_with_what() {
  local what_body="$1"
  local spec_dir="$TEST_REPO/specs/0099-fixture"
  mkdir -p "$spec_dir"
  cat > "$spec_dir/spec.md" <<EOF
---
id: "0099"
title: "fixture"
status: draft
created: 2026-06-10
authors: [test]
packages: []
revision: 0
---

# Spec 0099 — fixture

## Why

placeholder why.

## What

$what_body

## Acceptance criteria

1. fixture AC.

## Out of scope

- nothing.

## Open questions

_none_
EOF
  echo "$spec_dir"
}

@test "extract_identifiers picks single-backtick tokens >=4 chars" {
  spec_dir="$TEST_REPO/specs/0099-fixture"
  mkdir -p "$spec_dir"
  cat > "$spec_dir/spec.md" <<'EOF'
---
id: "0099"
title: "fixture"
status: draft
created: 2026-06-10
packages: []
revision: 0
---

# Spec 0099

## What

Mentions `Foo` (3 chars, ignored), `FooBar` (picked), `MyToken` (picked), `xy` (ignored).

## Acceptance criteria

1. fixture AC.

## Out of scope

- nothing.
EOF
  load_lib
  run extract_identifiers "$spec_dir/spec.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *"FooBar"* ]]
  [[ "$output" == *"MyToken"* ]]
  # The 3-char `Foo` must not be extracted. extract_identifiers emits one
  # token per line; assert that no line equals exactly "Foo".
  ! printf '%s\n' "$output" | grep -qE '^Foo$'
}

@test "extract_identifiers dedups repeated tokens" {
  spec_dir="$TEST_REPO/specs/0099-fixture"
  mkdir -p "$spec_dir"
  cat > "$spec_dir/spec.md" <<'EOF'
---
id: "0099"
title: "fixture"
status: draft
created: 2026-06-10
packages: []
revision: 0
---

# Spec 0099

## What

Has `SameToken` once, `SameToken` twice, `SameToken` thrice.

## Acceptance criteria

1. fixture AC.

## Out of scope

- nothing.
EOF
  load_lib
  run extract_identifiers "$spec_dir/spec.md"
  [ "$status" -eq 0 ]
  count="$(printf '%s\n' "$output" | grep -c '^SameToken$' || true)"
  [ "$count" = "1" ]
}

@test "extract_identifiers ignores tokens in Why section" {
  spec_dir="$TEST_REPO/specs/0099-fixture"
  mkdir -p "$spec_dir"
  cat > "$spec_dir/spec.md" <<'EOF'
---
id: "0099"
title: "fixture"
status: draft
created: 2026-06-10
packages: []
revision: 0
---

# Spec 0099

## Why

This mentions `WhyOnlyToken` which must NOT appear in output.

## What

This mentions `WhatToken` which MUST appear.

## Acceptance criteria

1. nothing.

## Out of scope

- nothing.
EOF
  load_lib
  run extract_identifiers "$spec_dir/spec.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *"WhatToken"* ]]
  ! [[ "$output" == *"WhyOnlyToken"* ]]
}

@test "extract_identifiers excludes fenced code blocks" {
  spec_dir="$TEST_REPO/specs/0099-fixture"
  mkdir -p "$spec_dir"
  cat > "$spec_dir/spec.md" <<'EOF'
---
id: "0099"
title: "fixture"
status: draft
created: 2026-06-10
packages: []
revision: 0
---

# Spec 0099

## What

Outside backticks `KeptToken` is picked.

```yaml
example:
  field: `FencedToken`
```

Inline `AnotherKept` here.

## Acceptance criteria

1. nothing.

## Out of scope

- nothing.
EOF
  load_lib
  run extract_identifiers "$spec_dir/spec.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *"KeptToken"* ]]
  [[ "$output" == *"AnotherKept"* ]]
  ! [[ "$output" == *"FencedToken"* ]]
}

# ---------------------------------------------------------------------------
# validate_packages <spec.md path> <repo root>
#
# Rejects glob entries, escape-path entries, non-string entries, and
# nonexistent paths. Accepts clean directory or file paths under the repo
# root. Implements spec 0015 packages[] field contract.
# ---------------------------------------------------------------------------

write_spec_with_packages() {
  local packages="$1"
  local spec_dir="$TEST_REPO/specs/0099-fixture"
  mkdir -p "$spec_dir"
  cat > "$spec_dir/spec.md" <<EOF
---
id: "0099"
title: "fixture"
status: draft
created: 2026-06-10
packages: $packages
revision: 0
---

# Spec 0099

## What

placeholder.

## Acceptance criteria

1. fixture.

## Out of scope

- nothing.
EOF
  echo "$spec_dir"
}

@test "validate_packages rejects glob entries" {
  spec_dir="$(write_spec_with_packages '["foo/*.go"]')"
  load_lib
  run validate_packages "$spec_dir/spec.md" "$TEST_REPO"
  [ "$status" -ne 0 ]
  [[ "$output" == *"glob"* ]] || [[ "$output" == *"wildcard"* ]]
}

@test "validate_packages rejects escape-path entries" {
  spec_dir="$(write_spec_with_packages '["../etc/passwd"]')"
  load_lib
  run validate_packages "$spec_dir/spec.md" "$TEST_REPO"
  [ "$status" -ne 0 ]
  [[ "$output" == *"escape"* ]] || [[ "$output" == *"outside"* ]] || [[ "$output" == *".."* ]]
}

@test "validate_packages rejects nonexistent paths" {
  spec_dir="$(write_spec_with_packages '["does/not/exist"]')"
  load_lib
  run validate_packages "$spec_dir/spec.md" "$TEST_REPO"
  [ "$status" -ne 0 ]
  [[ "$output" == *"does/not/exist"* ]]
}

@test "validate_packages accepts clean dir entries under repo root" {
  mkdir -p "$TEST_REPO/commands/spec"
  touch "$TEST_REPO/commands/spec/foo.md"
  spec_dir="$(write_spec_with_packages '["commands/spec"]')"
  load_lib
  run validate_packages "$spec_dir/spec.md" "$TEST_REPO"
  [ "$status" -eq 0 ]
}

@test "validate_packages accepts clean file entries under repo root" {
  mkdir -p "$TEST_REPO/agents"
  touch "$TEST_REPO/agents/spec-author.md"
  spec_dir="$(write_spec_with_packages '["agents/spec-author.md"]')"
  load_lib
  run validate_packages "$spec_dir/spec.md" "$TEST_REPO"
  [ "$status" -eq 0 ]
}

@test "validate_packages accepts empty list" {
  spec_dir="$(write_spec_with_packages '[]')"
  load_lib
  run validate_packages "$spec_dir/spec.md" "$TEST_REPO"
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# run_cross_check <spec.md path> <repo root>
#
# Orchestrates: if packages: [] empty, prints skip warning to stdout and
# returns zero. Else validates packages, extracts identifiers, runs grep
# across each package, emits drift items (one per missing token) on stdout.
# Implements spec 0015 §Mechanism step 6 and AC7.
# ---------------------------------------------------------------------------

@test "run_cross_check warns and skips when packages empty" {
  spec_dir="$(write_spec_with_packages '[]')"
  load_lib
  run run_cross_check "$spec_dir/spec.md" "$TEST_REPO"
  [ "$status" -eq 0 ]
  [[ "$output" == *"packages[] empty"* ]]
  [[ "$output" == *"skipping code cross-check"* ]]
}

@test "run_cross_check reports missing tokens as drift items" {
  mkdir -p "$TEST_REPO/commands/spec"
  echo "# just some content" > "$TEST_REPO/commands/spec/sample.md"
  spec_dir="$TEST_REPO/specs/0099-fixture"
  mkdir -p "$spec_dir"
  cat > "$spec_dir/spec.md" <<'EOF'
---
id: "0099"
title: "fixture"
status: draft
created: 2026-06-10
packages: ["commands/spec"]
revision: 0
---

# Spec 0099

## What

References `NonexistentSymbolXYZ` which does not appear in commands/spec.

## Acceptance criteria

1. nothing.

## Out of scope

- nothing.
EOF
  load_lib
  run run_cross_check "$spec_dir/spec.md" "$TEST_REPO"
  [ "$status" -eq 0 ]
  [[ "$output" == *"NonexistentSymbolXYZ"* ]]
}

@test "run_cross_check omits tokens that match in at least one path" {
  mkdir -p "$TEST_REPO/commands/spec"
  echo "this file mentions PresentSymbol somewhere" > "$TEST_REPO/commands/spec/sample.md"
  spec_dir="$TEST_REPO/specs/0099-fixture"
  mkdir -p "$spec_dir"
  cat > "$spec_dir/spec.md" <<'EOF'
---
id: "0099"
title: "fixture"
status: draft
created: 2026-06-10
packages: ["commands/spec"]
revision: 0
---

# Spec 0099

## What

References `PresentSymbol` which does appear in commands/spec.

## Acceptance criteria

1. nothing.

## Out of scope

- nothing.
EOF
  load_lib
  run run_cross_check "$spec_dir/spec.md" "$TEST_REPO"
  [ "$status" -eq 0 ]
  ! [[ "$output" == *"PresentSymbol"* ]]
}

# ---------------------------------------------------------------------------
# snapshot_spec / frontmatter_integrity_check / diff_against_snapshot
#
# snapshot_spec captures pre-revise state. frontmatter_integrity_check
# enforces command-owned-frontmatter invariance across the spec-reviser
# agent call. diff_against_snapshot detects no-op vs real-change with
# trailing-whitespace and trailing-newline normalization. AC3/AC4/AC5/AC6
# depend on these helpers. Plan-time refinement: frontmatter integrity is
# structurally enforced (review.md concern #3).
# ---------------------------------------------------------------------------

@test "snapshot_spec writes pre and frontmatter snapshot files" {
  spec_dir="$(seed_spec reviewed 1)"
  snap="$TEST_REPO/snap"
  mkdir -p "$snap"
  load_lib
  run snapshot_spec "$spec_dir/spec.md" "$snap"
  [ "$status" -eq 0 ]
  [ -f "$snap/spec.md.pre" ]
  [ -f "$snap/frontmatter.pre" ]
}

@test "frontmatter_integrity_check fails when revision changed" {
  spec_dir="$(seed_spec reviewed 1)"
  snap="$TEST_REPO/snap"
  mkdir -p "$snap"
  load_lib
  snapshot_spec "$spec_dir/spec.md" "$snap"
  # Simulate agent tampering with revision.
  sed -i 's/^revision: 1$/revision: 99/' "$spec_dir/spec.md"
  run frontmatter_integrity_check "$spec_dir/spec.md" "$snap"
  [ "$status" -ne 0 ]
  [[ "$output" == *"revision"* ]]
}

@test "frontmatter_integrity_check fails when status changed" {
  spec_dir="$(seed_spec reviewed 1)"
  snap="$TEST_REPO/snap"
  mkdir -p "$snap"
  load_lib
  snapshot_spec "$spec_dir/spec.md" "$snap"
  sed -i 's/^status: reviewed$/status: planned/' "$spec_dir/spec.md"
  run frontmatter_integrity_check "$spec_dir/spec.md" "$snap"
  [ "$status" -ne 0 ]
  [[ "$output" == *"status"* ]]
}

@test "frontmatter_integrity_check fails when id changed" {
  spec_dir="$(seed_spec reviewed 1)"
  snap="$TEST_REPO/snap"
  mkdir -p "$snap"
  load_lib
  snapshot_spec "$spec_dir/spec.md" "$snap"
  sed -i 's/^id: "0099"$/id: "0042"/' "$spec_dir/spec.md"
  run frontmatter_integrity_check "$spec_dir/spec.md" "$snap"
  [ "$status" -ne 0 ]
  [[ "$output" == *"id"* ]]
}

@test "frontmatter_integrity_check fails when created changed" {
  spec_dir="$(seed_spec reviewed 1)"
  snap="$TEST_REPO/snap"
  mkdir -p "$snap"
  load_lib
  snapshot_spec "$spec_dir/spec.md" "$snap"
  sed -i 's/^created: 2026-06-10$/created: 2026-06-11/' "$spec_dir/spec.md"
  run frontmatter_integrity_check "$spec_dir/spec.md" "$snap"
  [ "$status" -ne 0 ]
  [[ "$output" == *"created"* ]]
}

@test "frontmatter_integrity_check passes when only body changed" {
  spec_dir="$(seed_spec reviewed 1)"
  snap="$TEST_REPO/snap"
  mkdir -p "$snap"
  load_lib
  snapshot_spec "$spec_dir/spec.md" "$snap"
  # Real-change to body only.
  sed -i 's/test fixture body./EDITED BODY./' "$spec_dir/spec.md"
  run frontmatter_integrity_check "$spec_dir/spec.md" "$snap"
  [ "$status" -eq 0 ]
}

@test "diff_against_snapshot reports no-op when byte-identical" {
  spec_dir="$(seed_spec reviewed 1)"
  snap="$TEST_REPO/snap"
  mkdir -p "$snap"
  load_lib
  snapshot_spec "$spec_dir/spec.md" "$snap"
  # No edits.
  run diff_against_snapshot "$spec_dir/spec.md" "$snap"
  [ "$status" -eq 0 ]
  [ "$output" = "no-op" ]
}

@test "diff_against_snapshot treats added trailing newline as no-op" {
  spec_dir="$(seed_spec reviewed 1)"
  snap="$TEST_REPO/snap"
  mkdir -p "$snap"
  load_lib
  snapshot_spec "$spec_dir/spec.md" "$snap"
  # Append an extra newline.
  printf '\n' >> "$spec_dir/spec.md"
  run diff_against_snapshot "$spec_dir/spec.md" "$snap"
  [ "$status" -eq 0 ]
  [ "$output" = "no-op" ]
}

@test "diff_against_snapshot treats trailing horizontal whitespace as no-op" {
  spec_dir="$(seed_spec reviewed 1)"
  snap="$TEST_REPO/snap"
  mkdir -p "$snap"
  load_lib
  snapshot_spec "$spec_dir/spec.md" "$snap"
  # Add trailing spaces on the body line.
  sed -i 's/test fixture body./test fixture body.   /' "$spec_dir/spec.md"
  run diff_against_snapshot "$spec_dir/spec.md" "$snap"
  [ "$status" -eq 0 ]
  [ "$output" = "no-op" ]
}

@test "diff_against_snapshot reports changed when body word changes" {
  spec_dir="$(seed_spec reviewed 1)"
  snap="$TEST_REPO/snap"
  mkdir -p "$snap"
  load_lib
  snapshot_spec "$spec_dir/spec.md" "$snap"
  sed -i 's/test fixture body./EDITED CONTENT HERE./' "$spec_dir/spec.md"
  run diff_against_snapshot "$spec_dir/spec.md" "$snap"
  [ "$status" -eq 0 ]
  [ "$output" = "changed" ]
}

# ---------------------------------------------------------------------------
# bump_revision / archive_rename — the real-change branch of §Mechanism
# step 10. bump_revision increments `revision:` and flips status to draft.
# archive_rename moves stale review/plan/tasks artifacts per source status.
# AC3/AC4/AC5 depend on these helpers.
# ---------------------------------------------------------------------------

@test "bump_revision increments N to N+1 (5 to 6)" {
  spec_dir="$(seed_spec reviewed 5)"
  load_lib
  run bump_revision "$spec_dir/spec.md" reviewed
  [ "$status" -eq 0 ]
  grep -qE '^revision: 6$' "$spec_dir/spec.md"
}

@test "bump_revision increments N from 0 to 1" {
  spec_dir="$(seed_spec reviewed 0)"
  load_lib
  run bump_revision "$spec_dir/spec.md" reviewed
  [ "$status" -eq 0 ]
  grep -qE '^revision: 1$' "$spec_dir/spec.md"
}

@test "bump_revision sets status: draft on reviewed source" {
  spec_dir="$(seed_spec reviewed 2)"
  load_lib
  run bump_revision "$spec_dir/spec.md" reviewed
  [ "$status" -eq 0 ]
  grep -qE '^status: draft$' "$spec_dir/spec.md"
}

@test "bump_revision sets status: draft on planned source" {
  spec_dir="$(seed_spec planned 2)"
  load_lib
  run bump_revision "$spec_dir/spec.md" planned
  [ "$status" -eq 0 ]
  grep -qE '^status: draft$' "$spec_dir/spec.md"
}

@test "bump_revision leaves status: draft on draft source" {
  spec_dir="$(seed_spec draft 2)"
  load_lib
  run bump_revision "$spec_dir/spec.md" draft
  [ "$status" -eq 0 ]
  grep -qE '^status: draft$' "$spec_dir/spec.md"
  # Sanity: revision still bumped to 3.
  grep -qE '^revision: 3$' "$spec_dir/spec.md"
}

@test "archive_rename reviewed renames only review.md" {
  spec_dir="$(seed_spec reviewed 0)"
  echo "fake review" > "$spec_dir/review.md"
  echo "fake plan"   > "$spec_dir/plan.md"
  echo "fake tasks"  > "$spec_dir/tasks.md"
  load_lib
  run archive_rename "$spec_dir" reviewed 0
  [ "$status" -eq 0 ]
  [ -f "$spec_dir/review-r0.md" ]
  [ ! -f "$spec_dir/review.md" ]
  # plan.md and tasks.md untouched.
  [ -f "$spec_dir/plan.md" ]
  [ -f "$spec_dir/tasks.md" ]
  [ ! -f "$spec_dir/plan-r0.md" ]
  [ ! -f "$spec_dir/tasks-r0.md" ]
}

@test "archive_rename planned renames all three with -r<N> suffix" {
  spec_dir="$(seed_spec planned 2)"
  echo "fake review" > "$spec_dir/review.md"
  echo "fake plan"   > "$spec_dir/plan.md"
  echo "fake tasks"  > "$spec_dir/tasks.md"
  load_lib
  run archive_rename "$spec_dir" planned 2
  [ "$status" -eq 0 ]
  [ -f "$spec_dir/review-r2.md" ]
  [ -f "$spec_dir/plan-r2.md" ]
  [ -f "$spec_dir/tasks-r2.md" ]
  [ ! -f "$spec_dir/review.md" ]
  [ ! -f "$spec_dir/plan.md" ]
  [ ! -f "$spec_dir/tasks.md" ]
}

@test "archive_rename draft renames nothing" {
  spec_dir="$(seed_spec draft 0)"
  load_lib
  run archive_rename "$spec_dir" draft 0
  [ "$status" -eq 0 ]
  # No archives created.
  [ ! -f "$spec_dir/review-r0.md" ]
  [ ! -f "$spec_dir/plan-r0.md" ]
  [ ! -f "$spec_dir/tasks-r0.md" ]
}
