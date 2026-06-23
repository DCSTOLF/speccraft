#!/usr/bin/env bats
# Tests for commands/history/compact.lib.sh — the deterministic tier of
# /speccraft:history:compact (spec 0024, AC1/AC3/AC4/AC5/AC6/AC9 + CF-1..CF-4,CF-6).
#
# Pure bash helpers, no side effects at source time — mirrors the
# commands/spec/revise.lib.sh colocation convention. RED until T3/T5/T7/T8/T9
# land the lib. The fixture history.md below deliberately covers every real-corpus
# shape the parser must survive (CF-1/CF-6):
#   - singular `(spec NNNN)` headers
#   - a suffix-less header (no provenance id)            [OLDER, out-of-window]
#   - a plural `(specs 0002, 0003)` header               [OLDER, out-of-window]
#   - an entry whose BODY contains an interior `## Context` heading (must NOT
#     be parsed as a new entry)
#   - a pre-existing `## Compacted (…)` section with a `### theme` (durable
#     re-compaction input; never counted as a dated entry)

setup() {
  PLUGIN_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  LIB="$PLUGIN_DIR/commands/history/compact.lib.sh"
  TEST_REPO="$(mktemp -d)"
  H="$TEST_REPO/.speccraft/history.md"
  mkdir -p "$(dirname "$H")"
  cat > "$H" <<'EOF'
# History

Append-only. Newest first.

## 2026-06-23 — Eee (spec 0023)

eee body

## 2026-06-22 — Ddd (spec 0022)

ddd body

## 2026-06-21 — Ccc (spec 0021)

ccc body

## 2026-06-20 — Bbb (spec 0020)

bbb body

## 2026-06-19 — Aaa (spec 0019)

aaa body

## 2026-06-18 — Nine (spec 0018)

nine body

## 2026-06-17 — Eight (spec 0017)

eight body

## Context

an interior heading inside a body — must not be parsed as a new entry

## 2026-06-16 — Seven (spec 0016)

seven body

## 2026-06-15 — Six (spec 0015)

six body

## 2026-06-14 — Five (spec 0014)

five body

## 2026-05-28 — speccraft adopted

suffix-less older entry

## 2026-05-22 — Lang support (specs 0002, 0003)

plural older entry

## Compacted (older than the active window)

_Full records preserved verbatim in `.speccraft/history-archive/history.md` and in git._

### Legacy theme
Specs: 0001. Archive: .speccraft/history-archive/history.md
A pre-existing compacted summary group.
EOF
  export PLUGIN_DIR LIB TEST_REPO H
}

teardown() {
  rm -rf "$TEST_REPO"
}

# ---- AC1 / CF-1 / CF-6 — parse + window split ----

@test "history_parse_entries: counts only dated ADR headers (12), not interior ## or ## Compacted" {
  source "$LIB"
  run history_parse_entries "$H"
  [ "$status" -eq 0 ]
  # 12 dated entries; the interior `## Context` and the `## Compacted` section are excluded.
  [ "$(printf '%s\n' "$output" | grep -c '^## 20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]')" -eq 12 ]
  printf '%s\n' "$output" | grep -qv '## Context'
  ! printf '%s\n' "$output" | grep -q '## Compacted'
}

@test "history_window_split: first N=10 by date header = window; remainder = older" {
  source "$LIB"
  run history_window_split "$H" 10 window
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c '^## 20[0-9][0-9]-')" -eq 10 ]
  printf '%s\n' "$output" | grep -qF '## 2026-06-23 — Eee (spec 0023)'

  run history_window_split "$H" 10 older
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c '^## 20[0-9][0-9]-')" -eq 2 ]
  printf '%s\n' "$output" | grep -qF '## 2026-05-28 — speccraft adopted'
  printf '%s\n' "$output" | grep -qF '## 2026-05-22 — Lang support (specs 0002, 0003)'
}

@test "history_window_split: the ## Compacted section is never counted toward N" {
  source "$LIB"
  # With N=12 (== number of dated entries), the older set is empty even though a
  # ## Compacted section exists below — proving it is not counted as an entry.
  run history_window_split "$H" 12 older
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c '^## 20[0-9][0-9]-')" -eq 0 ]
}

@test "history_window_split: body with interior ## heading stays one entry" {
  source "$LIB"
  run history_window_split "$H" 10 window
  [ "$status" -eq 0 ]
  # The Eight entry's body carries `## Context`; it must travel WITH that entry,
  # not be split off. The window text contains the interior heading verbatim.
  printf '%s\n' "$output" | grep -qF '## 2026-06-17 — Eight (spec 0017)'
  printf '%s\n' "$output" | grep -qF '## Context'
}

# ---- AC1 / CF-1 — provenance ids (optional, list-valued) ----

@test "history_provenance_ids: singular, plural, and suffix-less" {
  source "$LIB"
  run bash -c "source '$LIB'; printf '%s\n' '## 2026-06-21 — Ccc (spec 0021)' | history_provenance_ids"
  [ "$status" -eq 0 ]
  [ "$output" = "0021" ]

  run bash -c "source '$LIB'; printf '%s\n' '## 2026-05-22 — Lang support (specs 0002, 0003)' | history_provenance_ids"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | tr '\n' ',' )" = "0002,0003," ]

  run bash -c "source '$LIB'; printf '%s\n' '## 2026-05-28 — speccraft adopted' | history_provenance_ids"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ---- AC3 / AC5 / CF-3 — verbatim archive, full-byte dedup, blast radius ----

@test "history_archive_append: creates folder + appends verbatim headers" {
  source "$LIB"
  ARCH="$TEST_REPO/.speccraft/history-archive/history.md"
  history_window_split "$H" 10 older | history_archive_append "$ARCH"
  [ -f "$ARCH" ]
  grep -qF '## 2026-05-28 — speccraft adopted' "$ARCH"
  grep -qF '## 2026-05-22 — Lang support (specs 0002, 0003)' "$ARCH"
}

@test "history_archive_append: full-byte dedup (idempotent; differing body re-appended)" {
  source "$LIB"
  ARCH="$TEST_REPO/.speccraft/history-archive/history.md"
  entry=$'## 2026-04-01 — Solo (spec 0009)\n\nfirst body'
  printf '%s\n' "$entry" | history_archive_append "$ARCH"
  printf '%s\n' "$entry" | history_archive_append "$ARCH"            # identical → no-op
  [ "$(grep -c '^## 2026-04-01 ' "$ARCH")" -eq 1 ]
  entry2=$'## 2026-04-01 — Solo (spec 0009)\n\nDIFFERENT body'
  printf '%s\n' "$entry2" | history_archive_append "$ARCH"          # differing → appended
  [ "$(grep -c '^## 2026-04-01 ' "$ARCH")" -eq 2 ]
}

@test "history_archive_append: blast radius — only the archive changes" {
  source "$LIB"
  ARCH="$TEST_REPO/.speccraft/history-archive/history.md"
  printf 'arch\n' > "$TEST_REPO/.speccraft/architecture.md"
  printf 'conv\n' > "$TEST_REPO/.speccraft/conventions.md"
  printf 'idx\n'  > "$TEST_REPO/.speccraft/index.md"
  mkdir -p "$TEST_REPO/specs/0001-x"; printf 'spec\n' > "$TEST_REPO/specs/0001-x/spec.md"
  cp "$TEST_REPO/.speccraft/architecture.md" "$TEST_REPO/arch.snap"
  cp "$TEST_REPO/.speccraft/conventions.md"  "$TEST_REPO/conv.snap"
  cp "$TEST_REPO/.speccraft/index.md"        "$TEST_REPO/idx.snap"
  cp "$TEST_REPO/specs/0001-x/spec.md"       "$TEST_REPO/spec.snap"
  history_window_split "$H" 10 older | history_archive_append "$ARCH"
  cmp -s "$TEST_REPO/.speccraft/architecture.md" "$TEST_REPO/arch.snap"
  cmp -s "$TEST_REPO/.speccraft/conventions.md"  "$TEST_REPO/conv.snap"
  cmp -s "$TEST_REPO/.speccraft/index.md"        "$TEST_REPO/idx.snap"
  cmp -s "$TEST_REPO/specs/0001-x/spec.md"       "$TEST_REPO/spec.snap"
}

# ---- AC4 / AC6 / CF-4 — idempotent no-op + nudge predicate ----

@test "history_archive_append: nothing to compact writes no files" {
  source "$LIB"
  ARCH="$TEST_REPO/.speccraft/history-archive/history.md"
  older="$(history_window_split "$H" 20 older)"   # N >= entry count → empty older set
  [ -z "$older" ]
  printf '%s' "$older" | history_archive_append "$ARCH"
  [ ! -f "$ARCH" ]                                 # no archive created on a no-op
}

@test "history_nudge_predicate: nudge when count>N and count>15" {
  source "$LIB"
  run history_nudge_predicate 16 1000 10
  [ "$status" -eq 0 ]
  [ "$output" = "nudge" ]
}

@test "history_nudge_predicate: nudge when count>N and bytes>40KB" {
  source "$LIB"
  run history_nudge_predicate 11 42000 10
  [ "$status" -eq 0 ]
  [ "$output" = "nudge" ]
}

@test "history_nudge_predicate: quiet when bytes>40KB but nothing below window (count==N)" {
  source "$LIB"
  run history_nudge_predicate 10 50000 10
  [ "$status" -eq 0 ]
  [ "$output" = "quiet" ]
}

@test "history_nudge_predicate: quiet when small" {
  source "$LIB"
  run history_nudge_predicate 5 1000 10
  [ "$status" -eq 0 ]
  [ "$output" = "quiet" ]
}

# ---- AC11 / CF-2 — durable re-compaction input ----

@test "history_compacted_section_themes: extracts existing ### theme groups verbatim" {
  source "$LIB"
  run history_compacted_section_themes "$H"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF '### Legacy theme'
  printf '%s\n' "$output" | grep -qF 'Specs: 0001. Archive: .speccraft/history-archive/history.md'
  # the ## Compacted header + intro blurb are not part of the theme output
  ! printf '%s\n' "$output" | grep -q '## Compacted'
}

@test "history_compacted_section_themes: empty when no Compacted section" {
  source "$LIB"
  nofx="$TEST_REPO/.speccraft/nocompact.md"
  printf '# History\n\n## 2026-06-23 — Only (spec 0023)\n\nbody\n' > "$nofx"
  run history_compacted_section_themes "$nofx"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ---- AC9 / CF-1 — deterministic supersession seed (out-of-window only) ----

seed_fixture() {
  local f="$TEST_REPO/.speccraft/seed.md"
  cat > "$f" <<'EOF'
# History

## 2026-06-10 — Newest (spec 0030)

window entry; mentions spec 0020 in its body

## 2026-06-05 — Mid (spec 0023)

supersedes: 0019
also see spec 0020 for context

## 2026-06-01 — Older A (spec 0020)

plain body

## 2026-05-01 — Older B (spec 0019)

plain body
EOF
  echo "$f"
}

@test "history_supersession_seed: explicit supersedes: marker (out-of-window)" {
  source "$LIB"
  f="$(seed_fixture)"
  run history_supersession_seed "$f" 1
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qx '0019 0023'
}

@test "history_supersession_seed: in-body spec cross-reference" {
  source "$LIB"
  f="$(seed_fixture)"
  run history_supersession_seed "$f" 1
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qx '0020 0023'
}

@test "history_supersession_seed: window entries never emitted as either side" {
  source "$LIB"
  f="$(seed_fixture)"
  run history_supersession_seed "$f" 1
  [ "$status" -eq 0 ]
  # 0030 is the window entry (N=1); it references 0020 in its body but must never
  # appear in a seed pair (window bodies are not scanned; window ids excluded).
  ! printf '%s\n' "$output" | grep -q '0030'
}

@test "history_supersession_seed: empty without a deterministic signal" {
  source "$LIB"
  f="$TEST_REPO/.speccraft/nosignal.md"
  cat > "$f" <<'EOF'
# History

## 2026-06-10 — A (spec 0030)

plain

## 2026-06-05 — B (spec 0023)

plain body no refs

## 2026-06-01 — C (spec 0020)

plain
EOF
  run history_supersession_seed "$f" 1
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
