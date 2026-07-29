---
spec: "0025"
closed: 2026-06-23
---

# Changelog — 0025 Spec consolidation into current domain specs on close

## What shipped vs spec

- Inline-at-close, confirm-gated consolidation: closing a spec folds its final
  requirements into current `specs/domains/<area>.md` domain files (open-set:
  a domain exists iff its file exists), via an ADD/MODIFY/REMOVE merge vocabulary
  modeled on delta-spec. Consolidation never gates close — decline or an open
  conflict still lets close complete.
- MODIFY/REMOVE carry a REQUIRED verbatim target locator, matched by exact
  normalized comparison (trailing `(spec NNNN)` provenance suffix + surrounding
  whitespace trimmed); 0-or->1 matches fall through to the non-blocking conflict
  path, never applied to a guessed line. A locator-less MODIFY/REMOVE is a
  malformed-block rejection. This is the deterministic seed of the model heuristic,
  pinned in bats.
- Two clock-free archives: (A) the closed spec DIRECTORY is moved wholesale to
  `specs/.archive/NNNN-slug/` as the LAST step, only at zero conflicts, with
  frontmatter `status` left `closed` (location, not a status value, signals
  "consolidated"); relocation is not content-modification, so the closed-spec
  immutability guardrail holds. (B) Superseded requirement TEXT is appended to
  `specs/domains/.archive/<area>.md` with a self-describing header (area + spec +
  op) and FULL-ENTRY byte-dedup.
- Pinned per-delta write order for MODIFY/REMOVE: archive-B append FIRST, then the
  domain mutation, then the dir-move LAST — so a crash can't lose the suffix-bearing
  preimage. Both crash windows are bats-pinned (AC6).
- Open-conflict sink = `consolidation-conflicts.md` inside the spec dir (not
  `state.json`, dodging the single-writer rule; not the domain file, keeping it
  byte-unchanged). Deleted on resolution; its absence is the zero-conflict
  precondition the dir-move gates on.
- `/speccraft:sync` gains a confirm-gated, per-spec retroactive backfill loop.
  Candidate predicate is location-based + clock-free (`status==closed` AND under
  `specs/` AND no `consolidation-skip` marker); replay order is
  `.speccraft/history.md` chronology (oldest-first), NOT ascending spec ID. A spec
  whose history entry was compacted out by spec 0024 falls to a `created:`-then-ID
  fallback bucket (presentation-only, fails safe via the conflict path). Marker-file
  progress: moved=consolidated / `consolidation-conflicts.md`=conflict-open /
  `consolidation-skip`=declined / none=pending.
- `speccraft-context` SKILL loads `specs/domains/<area>.md` lazily by area, and
  NEVER the `.archive` trees — mirroring spec 0024's history-archive invariant so
  archiving can't silently re-bloat context.
- The deterministic tier is a pure-shell `commands/spec/consolidate.lib.sh` (the
  spec-0015 colocation convention), sourced by `close.md`, `sync.md`, and the bats
  suite. It itself `source`s `commands/history/compact.lib.sh` to reuse spec 0024's
  `history_parse_entries` / `history_provenance_ids` for the backfill chronology
  rather than writing a second parser (explicit cross-spec coupling, bats-pinned).
- `memory-keeper` is REUSED (no new agent/store): it gains a documented
  `# Mode: consolidate` expanding it from append-only to propose/merge domain
  requirements under confirmation — mirroring how spec 0024 added `# Mode: compact`.
- NO new Go binary; pure shell + Markdown + bats. Because `.sh`/`.md`/`.bats`/e2e
  are not guard-gated, NO `/speccraft:spec:override` was needed.

### Deviations

- **MODIFY new-line text is written AUTHOR-AUTHORITATIVE.** The spec body says MODIFY
  "appends the modifying id to the suffix list"; the deterministic helper does NOT
  mechanically re-merge the old provenance ids into the new suffix — the author
  writes the merged suffix verbatim in the delta text. AC5's suffix-grammar
  invariant still holds (every merged line carries a `(spec NNNN)` suffix). A
  mechanical suffix-merge is a possible follow-up.
- **The model tier (AC7–AC12) is credit-gated**; the full lifecycle e2e run is
  deferred to a real credit-gated CI job. Meanwhile it is verified deterministically
  (`bash -n` + 31 green bats + `verify.sh`), and the fixture asserts structural
  predicates only.

## Files touched

- `commands/spec/consolidate.lib.sh` (NEW — pure-shell deterministic helper; sources
  `commands/history/compact.lib.sh`)
- `tests/hooks/spec-consolidate.bats` (NEW — 31 deterministic tests, all green)
- `tests/e2e/spec_consolidate.sh` (NEW — SOURCED credit-gated fixture, `[10e/13]`)
- `specs/0025-spec-consolidation-on-close/verify.sh` (NEW — doc/wiring grep oracle)
- `commands/spec/close.md` (EDIT — step 9: inline confirm-gated consolidation)
- `commands/sync.md` (EDIT — step 4: retroactive backfill propose loop)
- `agents/memory-keeper.md` (EDIT — added `# Mode: consolidate`)
- `skills/speccraft-context/SKILL.md` (EDIT — lazy `specs/domains/<area>.md`; never `.archive`)
- `tests/e2e/run.sh` (EDIT — source + call the fixture as `[10e/13]`)

## ADR proposed for history.md

See the dated entry added to `.speccraft/history.md` (newest-first).

## Conventions proposed

- New: "A shared deterministic helper sourced by more than one command lives in
  `commands/<group>/<name>.lib.sh` and MAY itself `source` another command's
  `.lib.sh` to reuse a parser rather than duplicating it (explicit cross-spec
  coupling), pinned by a bats test that sources both libs."

## Architecture proposed

- New consolidated-domain layer `specs/domains/<area>.md` + two clock-free
  `.archive` trees (`specs/.archive/`, `specs/domains/.archive/`); `consolidate.lib.sh`
  sourced by both `close` and `sync`.
