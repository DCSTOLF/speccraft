---
spec: "0024"
closed: 2026-06-23
---

# Changelog — 0024 Bounded, reviewable history.md compaction

## What shipped vs spec

All twelve acceptance criteria are implemented across the two-tier split the spec
defined (deterministic AC1–6 + AC9-seed, model-behavior AC7–12).

- **Deterministic tier — `commands/history/compact.lib.sh` + `tests/hooks/history-compact.bats` (19 tests).**
  Pure bash helpers, mirroring the `revise.lib.sh` colocation convention:
  - `history_parse_entries` / `history_window_split` — positional window, keyed on
    the `## YYYY-MM-DD` date header ALONE; the `## Compacted …` section and any
    interior `## ` body heading are never counted (CF-1/CF-6, AC1).
  - `history_provenance_ids` — optional, list-valued (`(spec NNNN)` / `(specs A, B)`
    / none), degrades gracefully on suffix-less entries (CF-1).
  - `history_archive_append` — append-only to `.speccraft/history-archive/history.md`,
    full-entry byte-match dedup, no-op-safe on empty input (writes nothing), pure
    blast radius (CF-3, AC3/AC4/AC5).
  - `history_nudge_predicate` — pure; `count>N AND (count>15 OR bytes>40960)`, the
    count>N arm stops false alarms when nothing is compactable (CF-4, AC6).
  - `history_compacted_section_themes` — extracts existing `### theme` groups as
    durable re-compaction input (CF-2, AC11).
  - `history_supersession_seed` — deterministic out-of-window-only `<older> <newer>`
    pairs from explicit `supersedes:` markers + in-body `spec NNNN` xrefs; window
    entries never emitted; empty without signal (AC9, the codex round-1
    "deterministic test surface" ask).
- **Command + agent + wiring (P2).** `commands/history/compact.md` drives
  propose→confirm→apply (blast radius scoped to `history.md` + `history-archive/`);
  `agents/memory-keeper.md` gains a documented `# Mode: compact` (the reuse-not-new-
  store decision made into an explicit, reviewable responsibility expansion —
  propose/summarize/merge, pointer on the archived side, never drop a prior theme);
  the non-blocking nudge is wired into `commands/spec/close.md`.
- **Doc oracle (P2).** `specs/0024-history-compaction/verify.sh` (10 checks) pins
  the command frontmatter, the memory-keeper compact mode, the close-nudge wiring,
  and the paired context-skill invariant — the skill still loads `history.md` and
  does NOT load `history-archive` (so archiving can't silently re-bloat context).
- **e2e (P3).** `tests/e2e/history_compact.sh` — SOURCED credit-gated fixture
  (mirrors `arch_close_memory.sh`), registered `[10d/13]` in `run.sh`. Structural
  predicates only: decline byte-unchanged, `## Compacted`/`###`/`Specs:`/`Archive:`
  schema, window byte-identical, archive reachable, seeded `Supersedes:`,
  re-compaction theme survives.

## Test coverage

`bats tests/hooks` 96/96 (77 baseline + 19 new); `go test ./...` untouched-green
(no Go changed); `specs/0024-history-compaction/verify.sh` 10/10; all new shell
`bash -n` clean; run.sh source integrity OK. The e2e fixture's seed corpus
cross-checks against the real lib (12 entries → older=2, seed `0101 0102`).

## Deviations

- **No `/speccraft:spec:override` anywhere** — every artifact is `.sh`/`.md`/`.bats`/
  e2e, all ungated by `speccraft-guard`; the deterministic-tier RED was a failing
  bats run against the not-yet-created lib.
- **The e2e fixture is credit-gated** — verified deterministically (`bash -n` +
  seed-corpus-vs-lib cross-check + run.sh source integrity); the full `claude -p`
  lifecycle run is **pending user e2e** (the spec 0022 P3 posture).
- **T10 optional refactor skipped** — the date-header pattern is a shell constant
  (`_HISTORY_DATE_RE`), but the per-function awk programs embed the literal pattern
  (awk can't read the shell var inside `/.../`); extracting would add a templating
  layer for ~no gain.
- **AC12 nudge** is covered by bats (the predicate) + verify.sh (the close.md
  wiring) rather than re-driven in the credit-gated e2e — the deterministic layers
  pin it more cheaply and reliably.

## Architecture note

`.speccraft/history.md` is no longer an unbounded append-only file: it is now a
bounded recent window + a merged thematic `## Compacted` section, with full records
preserved verbatim in the new `.speccraft/history-archive/` folder (and git).
Compaction is opt-in and confirm-gated via `/speccraft:history:compact`.

## Follow-ups

- Run the full credit-gated `tests/e2e/run.sh` lifecycle to exercise the
  `history_compact` fixture end-to-end.
- Optional `[history]` config section, session-start nudge, and a future spec to
  teach `speccraft-guard`'s `applyEdit` to model the `Write` tool's `content`
  (the recurring override-cause noted in spec 0022).
