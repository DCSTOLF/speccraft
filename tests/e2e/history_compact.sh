#!/usr/bin/env bash
# tests/e2e/history_compact.sh — credit-gated e2e fixture for
# /speccraft:history:compact (spec 0024, model-behavior tier AC7–AC11).
#
# SOURCED by tests/e2e/run.sh from inside the claude -p lifecycle (run_claude,
# LOG_DIR, jq, cmp, and the lib.sh predicates must already be in scope). Defines a
# function the lifecycle calls; no side effects at source time. Unlike the
# self-contained language cycles, the compaction flow can only be exercised by
# really driving the command body through claude.
#
# STRUCTURAL predicates only — never grep model prose (plan R3). Reuses the
# dated-ADR header SHAPE and the `cmp -s` byte-unchanged idiom from
# arch_close_memory.sh. Asserts:
#   - DECLINE: history.md AND the archive are byte-identical to before (AC7).
#   - CONFIRM: a `## Compacted (…)` section with a `###` theme carrying
#     `Specs:` + `Archive:` appears (AC8); the newest N `## YYYY-MM-DD` headers are
#     byte-identical to a pre-snapshot (AC2 cross-check); the archive file exists
#     with a dated header (provenance reachable, AC10); a seeded `Supersedes:` line
#     is present (AC9); a re-run preserves the prior theme (AC11 merge-not-drop).
#
# AC12 (the spec:close nudge) is pinned deterministically by
# tests/hooks/history-compact.bats (the predicate) and specs/0024-.../verify.sh
# (the close.md wiring) — not re-driven here, to avoid a redundant credit-gated run.

set -euo pipefail

ADR_HEADER_RE="^## 20[0-9]{2}-[0-9]{2}-[0-9]{2}"

# Seed a controlled history.md: 10 in-window entries + 2 OUT-OF-WINDOW entries,
# the newer of which `supersedes:` the older (a deterministic seed pair).
_history_compact_seed() {
  local h="$1" i
  {
    printf '# History\n\nAppend-only. Newest first.\n\n'
    for i in 23 22 21 20 19 18 17 16 15 14; do
      printf '## 2026-06-%02d — Window entry %s (spec 00%s)\n\nbody %s\n\n' "$i" "$i" "$i" "$i"
    done
    printf '## 2026-01-02 — Older newer (spec 0102)\n\nsupersedes: 0101\n\n'
    printf '## 2026-01-01 — Oldest (spec 0101)\n\noldest body\n\n'
  } > "$h"
}

history_compact() {
  command -v run_claude >/dev/null 2>&1 \
    || fail "history_compact must be sourced by run.sh (run_claude undefined)"

  local HIST=".speccraft/history.md"
  local ARCH=".speccraft/history-archive/history.md"
  _history_compact_seed "$HIST"

  # Snapshots for byte-unchanged / window-preserved assertions.
  local SNAP_HIST SNAP_WIN
  SNAP_HIST="$(mktemp)"; SNAP_WIN="$(mktemp)"
  cp "$HIST" "$SNAP_HIST"
  grep -E "$ADR_HEADER_RE" "$HIST" | head -10 > "$SNAP_WIN"   # the 10 window headers

  # ---- DECLINE path: nothing is written ----
  echo "==> [hist 1/2] /speccraft:history:compact (decline → no write)"
  run_claude "/speccraft:history:compact. Do NOT apply — decline the proposed compaction." hist-01-decline.log
  cmp -s "$SNAP_HIST" "$HIST" || fail "history:compact (decline) modified history.md"
  [ ! -e "$ARCH" ] || fail "history:compact (decline) created/changed the archive"
  pass "history:compact (decline) left history.md + archive byte-unchanged"

  # ---- CONFIRM path: window kept, older summarized + archived ----
  echo "==> [hist 2/2] /speccraft:history:compact (confirm)"
  run_claude "/speccraft:history:compact. Approve the proposed compaction (keep the newest 10 entries; summarize and archive the rest)." hist-02-confirm.log

  contains_regex "$HIST" "^## Compacted"
  contains_regex "$HIST" "^### "
  contains "$HIST" "Archive: .speccraft/history-archive/history.md"
  contains "$HIST" "Specs:"
  # AC2 cross-check: the 10 window headers are byte-identical to the snapshot.
  grep -E "$ADR_HEADER_RE" "$HIST" | head -10 > "$SNAP_WIN.after"
  cmp -s "$SNAP_WIN" "$SNAP_WIN.after" || fail "window entries not byte-identical after compaction"
  # AC10: originals reachable in the archive (a dated header is present there).
  exists "$ARCH"
  contains_regex "$ARCH" "$ADR_HEADER_RE"
  # AC9: the seeded supersession (0101 → 0102) surfaced as a Supersedes pointer.
  contains_regex "$HIST" "Supersedes:.*0101"
  pass "history:compact (confirm) kept window, wrote Compacted summary + archive + Supersedes"

  # ---- RE-COMPACTION: a second run preserves the prior theme (merge, not drop) ----
  local THEME
  THEME="$(grep -m1 -E '^### ' "$HIST" || true)"
  echo "==> [hist re] /speccraft:history:compact (second run preserves prior themes)"
  run_claude "/speccraft:history:compact. Approve any proposed compaction." hist-03-recompact.log
  if [ -n "$THEME" ]; then
    grep -Fq "$THEME" "$HIST" || fail "re-compaction dropped a prior ### theme ($THEME)"
    pass "re-compaction preserved prior theme group"
  fi

  rm -f "$SNAP_HIST" "$SNAP_WIN" "$SNAP_WIN.after"
}
