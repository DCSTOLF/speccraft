---
id: "0024"
title: "Bounded, reviewable history.md compaction"
status: closed
created: 2026-06-23
authors: [claude]
packages: []
related-specs: ["0019", "0022", "0023"]
---

# Spec 0024 — Bounded, reviewable history.md compaction

## Why

`.speccraft/history.md` is append-only and grows without bound — already 22 dated
ADR entries / ~60KB and climbing one entry per closed spec. The
`speccraft-context` skill loads it on demand, so an ever-growing file degrades
model performance and bloats context exactly as the project scales, which is when
the historical signal matters most. Older decisions are also frequently
*superseded* — e.g. the spec 0019 version bump is superseded by spec 0023 (a
collapse that becomes available once both entries age below the recent window) —
yet every entry is kept at full weight forever, so the file's signal-to-noise
ratio falls over time.

We want a compaction capability that keeps `history.md` **bounded and true**:
small enough to stay cheap to load, while never losing the ability to answer
"why was this decided." Compaction must be **explicit and reviewable** — a
decision record is never silently rewritten.

## What

Add an explicit, confirm-gated compaction operation for `.speccraft/history.md`,
plus a non-blocking nudge that suggests running it.

- **Manual command + threshold nudge.** A new explicit command
  (`/speccraft:history:compact`) is the ONLY thing that ever rewrites
  `history.md`. Separately, a count/size threshold surfaces a NON-blocking
  suggestion (at `spec:close`) to run that command when history exceeds its
  bound *and there is actually something below the window* (see Lifecycle). The
  nudge edits nothing.
- **Bounded recent window — positional, by entry count.** The **first N** ADR
  entries in file order (default N = 10) are kept verbatim at full fidelity.
  Because entries are appended newest-first, "first N from the top of the file"
  *is* the newest N — and unlike a date sort it is deterministic even though the
  live file is not strictly date-ordered. The **count/window key is the
  `## YYYY-MM-DD` date header alone** — NOT the optional trailing spec suffix
  (the real corpus has suffix-less entries and a plural `(specs 0002, 0003)`
  form, so the suffix cannot be the counting key). Everything *below* the window
  is eligible for compaction.
- **Optional, list-valued provenance.** Where present, the trailing
  `(spec NNNN)` / `(specs NNNN, MMMM)` header suffix is the provenance id and a
  supersession seed; where absent, `Specs:` and the supersession seed degrade
  gracefully (the entry is still windowed, archived, and summarized — just
  without a spec-id pointer).
- **Merged thematic summary in-file (defined shape).** Entries below the window
  are removed from the full-weight body and represented by a single
  `## Compacted (older than the active window)` section containing `###`-level
  theme groups (schema in Lifecycle). The compacted section deliberately uses
  `###` theme headers, never `## YYYY-MM-DD`, so the window parser can never
  miscount a summary as a live ADR.
- **Verbatim archive folder, clock-free, append-only, deduped.** Every demoted
  entry is appended verbatim — original `## YYYY-MM-DD …` header intact — to a
  single append-only file inside a new `.speccraft/history-archive/` folder
  (`.speccraft/history-archive/history.md`). The path is fixed (no wall-clock in
  the name), so repeat compactions just append. The **dedup identity is a
  full-entry byte-match (header + body)**: an entry already byte-present in the
  archive is never re-appended (the spec-id suffix is NOT the identity key, since
  it is optional/plural). Entries are also recoverable from git. Provenance is
  thus doubly preserved: archive file + git ref.
- **Proposed supersession collapse — out-of-window only.** A best-effort
  heuristic detects when a later entry supersedes an earlier one, seeded by
  explicit `supersedes:` markers when present, otherwise inferred from the
  optional `(spec NNNN)` suffix, in-entry "spec NNNN" cross-references, and
  overlapping touched surfaces. Collapse only ever rewrites entries that are
  **both below the window**; an in-window superseder keeps its verbatim text and
  the pointer to the superseded original lives on the archived/summarized side
  (this is what keeps AC2 and AC9 from conflicting). Detected collapses are
  **proposed, not applied**: each is shown for accept/reject before the rewrite.
- **Re-compaction is merge, not regenerate.** When `history.md` already has a
  `## Compacted` section, the next run treats that section as DURABLE input:
  newly demoted entries fold into it (joining an existing `###` theme or adding a
  new one), and prior `###` groups — with their `Specs:`/`Archive:`/`Supersedes:`
  provenance — are preserved, never re-summarized or dropped. This is what makes
  "bounded and true" hold across repeated runs.
- **Confirm-before-rewrite.** The command computes and PRESENTS the full proposed
  result (window kept verbatim + the merged summary + the list of entries to
  archive + the proposed collapses) and changes nothing until the developer
  confirms. Decline = no-op.

The deterministic mechanics (parsing, window split, archive append+dedup,
threshold check, blast radius) live in a Go/bats-testable helper; the prose
summarization and the propose/confirm interaction are model steps that reuse the
existing `memory-keeper` (no new store). **Reusing `memory-keeper` expands it from
append-only to also propose/summarize/merge under confirmation** — a real
responsibility addition that `agents/memory-keeper.md` must spell out (not a
hidden rewrite). Which behaviors are pinned where is stated in **Acceptance
criteria**, split into a deterministic tier and a model-behavior tier as spec
0022 established.

## Decisions (from the new-spec interview + two cross-model review rounds)

- **Trigger = manual command + non-blocking threshold nudge.** Automatic
  (unconfirmed) rewriting is rejected — it violates "explicit and reviewable."
- **Recent window bounded by entry count, selected positionally (first N from the
  top), keyed on the `## YYYY-MM-DD` date alone.** Rejected: a date *sort* (the
  live file's tail is not date-ordered, so it would diverge from file order),
  age/size windows (a clock or an unpredictable cut point), and keying on the
  spec suffix (it is optional/plural in the real corpus).
- **Clock-free throughout.** The nudge threshold is entry-count or byte-size only
  (no "age"); the archive is a fixed-path append-only file, not a date-stamped
  per-run file.
- **Nudge gated on compactability.** The nudge fires only when there is something
  below the window (`count > N`) AND history exceeds the bound — so it never
  suggests a command that AC4 would make a no-op.
- **Supersession = heuristic, proposed, seeded by explicit/optional markers,
  always human-confirmed, restricted to out-of-window entries.**
- **Archive dedup identity = full-entry byte-match (header + body)**, not the spec
  suffix.
- **Re-compaction merges into the existing `## Compacted` section** (durable
  input), never regenerates it.
- **Compacted form = merged thematic `###` summary in `history.md` + verbatim
  entries appended to `.speccraft/history-archive/history.md`** (folder, not
  deleted), on top of git recoverability.
- **Summarizer = reuse `memory-keeper`** (OQ1) with an explicit prompt expansion;
  no new `history-compactor` agent.
- **Config = constants in the command's helper lib** (OQ3): window `N = 10`;
  nudge when `count > N` AND (`> 15` entries OR `> 40 KB`). A `[history]` config
  section is a possible follow-up, not built here.
- **Nudge surface = `spec:close` only** (OQ4); session-start deferred.

## Lifecycle / behavior contract

- **Append stays unchanged.** New ADRs are still appended newest-first to
  `history.md` by `memory-keeper` at `spec:close`; compaction is a separate,
  later, opt-in operation, never a side effect of close.
- **Parsing contract.** A live ADR entry is `## YYYY-MM-DD` followed by its body
  up to the **next `## YYYY-MM-DD` header or the `## Compacted …` header** — the
  parser splits ONLY on those two header shapes, so a `## ` heading that ever
  appears inside an entry body cannot break parsing. The window is the first N
  `## YYYY-MM-DD` headers in file order; the `## Compacted …` section and its
  `###` themes are never counted. An optional trailing `(spec NNNN)` /
  `(specs NNNN, MMMM)` is parsed as a list-valued provenance id when present.
- **Summary schema.** Each `###` theme group carries: a theme title; a `Specs:`
  line listing contributing spec id(s) when known (omitted/`—` when an entry had
  no suffix); an `Archive:` pointer (`.speccraft/history-archive/history.md`); a
  one-paragraph merged decision summary; and, for a collapsed chain, a
  `Supersedes:` pointer. Illustrative shape (uses real below-window specs):

  ```
  ## Compacted (older than the active window)

  _Full records preserved verbatim in `.speccraft/history-archive/history.md` and in git._

  ### Multi-language TDD support
  Specs: 0005, 0007, 0010. Archive: .speccraft/history-archive/history.md
  Added Rust, Python, and JS/TS support to speccraft-guard's red→green red-check.
  ```
  For a collapsed chain, add e.g. `Supersedes: <older> → <newer>` — only when
  BOTH entries are below the window; an in-window superseder is intentionally left
  verbatim until it ages out.
- **Idempotence + re-compaction.** Running compact when no entry is below the
  window is a no-op: it reports "nothing to compact" and writes no files. When a
  `## Compacted` section already exists, a later run merges newly-demoted entries
  into it (preserving prior `###` groups and their provenance) and appends only
  not-yet-archived entries (full-byte dedup) to the archive.
- **Blast radius.** Compaction touches ONLY `.speccraft/history.md` and
  `.speccraft/history-archive/`. It never edits `architecture.md`,
  `conventions.md`, any spec file, or `index.md`. The post-compaction window still
  begins with `## YYYY-MM-DD` entries, so the existing e2e close-gate assertion
  (`history.md` gains a dated ADR header) keeps passing.
- **Context-skill invariant.** `.speccraft/history-archive/` is NOT added to the
  `speccraft-context` skill's load list (the skill loads `history.md` by explicit
  name), so archiving cannot silently re-bloat context; the archive carries no
  `enforce:` markers for `speccraft-drift`.
- **Template purity.** Any `history.md` shape assumptions (header regex, archive
  layout) live in the helper/command at repo root, never in a stack-agnostic
  template or skill under `templates/speccraft/`.

## Acceptance criteria

### Deterministic tier — pinned by the Go/bats helper

1. **Window split (positional, date-keyed).** The helper selects the first N
   entries whose header matches `## YYYY-MM-DD` in file order as the window and
   everything below as "older"; the count key is the date header alone (an entry
   with no `(spec NNNN)` suffix and one with `(specs 0002, 0003)` are both counted
   correctly); the `## Compacted …` section and its `###` themes are never counted.
   Default N = 10.
2. **Window preserved byte-identical.** After a confirmed compaction, the N window
   entries are byte-identical to their pre-compaction text.
3. **Verbatim archive, append-only, deduped, no loss.** Every demoted entry is
   appended — original `## YYYY-MM-DD …` header intact — to
   `.speccraft/history-archive/history.md` (created, never a deletion); no demoted
   entry's content is lost; an entry already byte-present (header + body) in the
   archive is never re-appended on a later run.
4. **Idempotent no-op.** Running compact when nothing is below the window reports
   "nothing to compact" and writes no files.
5. **Blast radius.** A compaction run modifies only `.speccraft/history.md` and
   `.speccraft/history-archive/`; `architecture.md`, `conventions.md`, spec files,
   and `index.md` are byte-unchanged.
6. **Nudge predicate.** The nudge is a pure function of entry count and byte size
   (no clock): true iff `count > N` AND (`count > 15` OR `bytes > 40 KB`); false
   otherwise — so it never fires when nothing is below the window.

### Model-behavior tier — pinned by an e2e fixture (structural predicates only)

7. **Confirm-gated.** `/speccraft:history:compact` presents a proposed rewrite
   (window kept verbatim + merged summary + entries-to-archive + proposed
   collapses) and makes NO change to `history.md` or `.speccraft/history-archive/`
   until the developer confirms. On decline, both are byte-identical to before.
8. **Merged thematic summary conforms to schema.** After confirm, the
   `## Compacted …` section exists and each `###` theme group carries a title, a
   `Specs:` line (id(s) when known), an `Archive:` pointer, a one-paragraph
   summary, and (for a collapse) a `Supersedes:` pointer.
9. **Supersession proposed, not silent, out-of-window only.** A detected
   supersession is shown for accept/reject before the rewrite; on accept the chain
   folds into the final decision with the pointer on the archived/summarized side,
   never by mutating a verbatim window entry; an in-window superseder is left
   untouched.
10. **Provenance preserved.** For every demoted decision, the summary (`Specs:`
    when known) + the archived verbatim entry (original dated header) + git let a
    reader answer "why was this decided" and reach the original record.
11. **Re-compaction merges, never regenerates.** A second compaction over a file
    that already has a `## Compacted` section preserves the existing `###` groups
    and their `Specs:`/`Archive:`/`Supersedes:` provenance, folding newly demoted
    entries in without re-summarizing or dropping prior groups.
12. **Non-blocking nudge.** When the AC6 predicate is true, `spec:close` surfaces
    a suggestion to run `/speccraft:history:compact`; the nudge blocks nothing,
    edits nothing, and does not appear otherwise.

## Out of scope

- **Spec consolidation** (merging/retiring spec directories) — a separate change.
- Compacting any other memory file (`conventions.md`, `architecture.md`) —
  `history.md`-only.
- Automatic, unconfirmed rewriting of decision records — always confirm-gated.
- Changing how NEW entries are authored (`memory-keeper` still appends
  newest-first at close).
- Semantically perfect supersession detection — the heuristic is best-effort and
  always human-confirmed; a missed supersession is acceptable.
- A `[history]` config section / session-start nudge / date-stamped archive files
  — possible follow-ups, not built here.

## Open questions

_none — OQ1–OQ4 resolved (see Decisions); round-1 blockers B1–B6 and round-2
carry-forwards CF-1–CF-6 folded in (see review.md)._
