---
id: "0025"
title: "Spec consolidation into current domain specs on close"
status: closed
created: 2026-06-23
revision: 1
authors: [claude]
packages: []
related-specs: ["0024", "0022"]
---

# Spec 0025 — Spec consolidation into current domain specs on close

## Why

Closed specs accumulate in `specs/` as N permanent per-feature directories, so the
readable spec corpus grows unbounded and goes stale relative to current behavior.
A reader asking "what does the close gate actually do today?" has to reconstruct
the answer by diffing a chain of closed, point-in-time spec dirs (0012 cleared it,
0022 added sibling keys, …) rather than reading one current statement. This is the
same unbounded-growth / signal-decay problem that spec 0024 solved for
`history.md`, but for the spec corpus itself: every closed spec is kept at full
weight forever and is a live silo the reader must visit, so signal-to-noise falls
as the project scales — exactly when "what does it do now" matters most.

We want closing a spec to fold its final requirements into a consolidated,
**current** domain spec, so domain specs always reflect current behavior — while
the original closed spec and the superseded requirement text stay recoverable. The
payoff is "read current behavior of an area in one place," delivered without
reintroducing context bloat, because domain files are bounded (consolidated,
deduped, superseded text collapsed into an archive) unlike the unbounded closed-dir
pile.

## What

When a spec closes — and retroactively via `/speccraft:sync` — merge its final
requirements into the relevant **domain spec file(s)** (`specs/domains/<area>.md`)
instead of leaving it as an isolated closed directory. Reference delta-spec's
ADD / MODIFY / REMOVE merge-into-domain model as prior art for the merge semantics.

- **Open-set domains.** A domain lives at `specs/domains/<area>.md`. The domain set
  is open: **a domain exists iff its file exists** — there is no fixed enum and no
  registration step. Creating a new area is just writing a new `<area>.md`.
- **Routing — explicit-then-seeded.** An explicit frontmatter `domains: [<area>…]`
  on the closing spec is authoritative. When it is absent, a path/title heuristic
  **seeds a proposed routing target** that the developer confirms or corrects —
  routing is never silent/auto. A spec touching multiple domains is split
  per-domain, and the split is always shown for confirmation before any write.
- **Merge vocabulary = ADD / MODIFY / REMOVE per requirement, each carrying an
  explicit target locator on MODIFY/REMOVE.** An explicit `delta:` block on the
  spec is authoritative; when absent, a model-inferred ADD/MODIFY/REMOVE
  classification is surfaced as a fallback for confirmation. Every MODIFY and
  REMOVE entry MUST carry a **verbatim target-line locator** — the exact existing
  requirement-line text as it appears in the routed domain file, matched with its
  trailing `(spec NNNN)` provenance suffix STRIPPED (match on requirement text,
  ignore the suffix). The deterministic helper does an exact normalized match
  (trim the trailing provenance suffix + surrounding whitespace); if zero or more
  than one line matches, the entry falls through to the conflict path — it is
  never silently applied to a guessed line. ADD entries carry NO locator (they
  append). A MODIFY/REMOVE missing a locator is a malformed-block rejection (this
  is the "expose the deterministic seed of a model heuristic at the cheap layer"
  convention: exact-locator matching is deterministic/bats-pinned, so only genuine
  ambiguity ever reaches the model + conflict path). MODIFY collapses the
  superseded domain text into the archive and writes the new text in place.
- **Conflict = propose / confirm, never blocking; the open conflict has a named
  sink.** When a merge would conflict with an existing domain line (locator
  matches zero or >1 lines, or the proposed line conflicts), the conflict is
  proposed for resolution. Decline leaves the domain line **byte-unchanged** and
  records the open conflict in a `consolidation-conflicts.md` file written INSIDE
  the spec's own directory (`specs/NNNN-slug/consolidation-conflicts.md`) — not in
  `state.json` (which would entangle the single-writer rule) and not in the domain
  file (which keeps the byte-unchanged guarantee). **The spec still closes**: an
  unresolved conflict never blocks close. Because a spec with any open conflict is
  NOT moved to the archive (see Two archives), the conflict file lives alongside
  the un-consolidated spec under `specs/` and its mere existence is the
  discoverable signal — no content scan needed.
- **Inline provenance.** Each merged requirement carries a list-valued
  `(spec NNNN)` / `(specs NNNN, MMMM)` suffix; a MODIFY appends the modifying id to
  the existing list. A suffix-less line degrades gracefully (it is still merged,
  archived, and routed — just without a spec-id pointer).
- **Two archives, both clock-free; the dir-move is the LAST step.** (A) The closed
  spec **directory** is moved wholesale to `specs/.archive/NNNN-slug/`, but ONLY
  after the spec is FULLY RESOLVED — every delta entry applied with ZERO open
  conflicts remaining. The move is the LAST step in the sequence (the commit
  signal); this move is the mechanism that makes the spec stop being a live silo,
  and its frontmatter `status` stays `closed` (location, not a status value,
  signals "already consolidated"). On decline, or while any conflict is open,
  NOTHING moves — the spec stays a live silo under `specs/`, which is exactly what
  the location-based backfill predicate later re-offers. (B) Superseded
  requirement **text** is appended to `specs/domains/.archive/<area>.md` — a fixed
  path, clock-free, append-only file — as a self-describing entry: a small
  deterministic header line carrying area, source spec id(s), and operation
  (MODIFY|REMOVE), followed by the verbatim superseded requirement text INCLUDING
  its original `(spec NNNN)` provenance suffix. Dedup identity is a **full-entry
  byte-match (header + text)**, so two distinct supersession events whose payload
  text happens to be byte-identical produce different headers and BOTH persist (no
  silent provenance loss), while a true duplicate (same spec, op, text re-run)
  still dedups (the analogue of 0024's `history-archive/history.md`).
- **Idempotent domain writes, with a pinned per-delta write order.** Domain-file
  writes are idempotent so a crash or re-run is safe: ADD dedups by
  (locator-normalized text + provenance); a MODIFY/REMOVE whose target locator is
  already absent/applied is a no-op. **Within each MODIFY/REMOVE delta the write
  order is fixed: archive-B append FIRST, then the destructive domain mutation,
  then (once the whole spec is resolved) the dir-move LAST.** Archiving the
  superseded text before mutating the domain line is what makes a crash between the
  two writes recoverable — a crash after archive-B but before the mutation re-runs
  safely (archive-B full-entry dedup suppresses a duplicate entry, and the mutation
  applies exactly once), while a crash after the mutation finds the locator already
  absent and is a no-op with the preimage already durably archived. The reverse
  order (mutate, then archive) would lose the suffix-bearing preimage irrecoverably
  on a crash, since the re-run sees the locator gone and skips archiving. Combined
  with the dir-move-is-last rule, a partial or interrupted consolidation can be
  re-run without duplicating an ADD line, re-applying an already-applied
  MODIFY/REMOVE, or dropping a superseded-text archive entry.
- **Backfill.** `/speccraft:sync` gains a confirm-gated, per-spec-propose
  retroactive backfill that consolidates any closed spec still living under `specs/`
  — candidate = `status==closed` AND dir still under `specs/` (not
  `specs/.archive/`) AND no `consolidation-skip` marker — a location-based,
  clock-free predicate that subsumes both pre-feature specs and specs whose
  consolidation was declined at close, replayed in `.speccraft/history.md`
  chronological order (oldest-first). **Known interaction with spec 0024:** 0024's
  compaction folds the OLDEST `history.md` entries into a `## Compacted` thematic
  section and moves the originals to `history-archive/`, so a candidate whose entry
  has been compacted out no longer has a parseable `## YYYY-MM-DD … (spec NNNN)`
  line and falls to the `created:`-then-ID fallback bucket. Because the oldest
  closed specs are the most likely backfill candidates, that fallback is in practice
  the *dominant* path for old specs, not the exception — and `created:`-then-ID is
  presentation ordering only, NOT guaranteed closure order. This is acceptable
  because backfill fails safe: the replay order is confirm-gated and any
  out-of-order match routes to the non-blocking conflict path and is re-offered next
  run.
- **On-demand context loading.** `specs/domains/<area>.md` files join the
  `speccraft-context` skill load list but are pulled **lazily** only when the task
  is relevant to that area — exactly how `architecture.md` / `conventions.md` are
  pulled today.
- **Reviewable throughout.** The developer confirms routing, the delta split, the
  merge, and every conflict before anything is written; archived originals are
  never lost (archive files + git).

The deterministic mechanics (delta-block parse/validate including the
MODIFY/REMOVE locator exact-match, routing-seed key computation, archive move +
full-entry byte-dedup, idempotent domain writes, blast-radius enforcement,
domain-file structural invariants) live in a **pure-shell** sourceable helper at
`commands/spec/<name>.lib.sh` (the spec-0015 colocation convention) with bats
coverage — there is **NO new Go binary**. Because `.sh` and `.md` are not gated by
`speccraft-guard`, implementing this needs NO `/speccraft:spec:override` (a new Go
binary would have required the red→green/override path — but none is added). The
prose merge, conflict propose/confirm, inline-at-close gating, and the `sync`
backfill loop are model steps that reuse the existing `memory-keeper` (no new
store/agent).
**Reusing `memory-keeper` expands it from append-only to also propose/merge domain
requirements under confirmation** — a real responsibility addition that
`agents/memory-keeper.md` must spell out as a dedicated `# Mode` for consolidation
(mirroring how 0024 expanded it for compaction), not a hidden rewrite. Which
behaviors are pinned where is stated in **Acceptance criteria**, split into a
deterministic tier and a model-behavior tier as spec 0022 established.

## Decisions (from the new-spec interview)

- **Trigger = inline during `/speccraft:spec:close`, confirm-gated.** Rejected: a
  separate `/speccraft:spec:consolidate` command (this DIVERGES from 0024's
  manual-command shape). Chosen inline-at-close keeps the corpus current at the
  natural moment a spec finishes; close still completes even if consolidation is
  declined. The divergence from 0024 is deliberate and trigger-driven:
  consolidation is a natural post-condition of closing a spec (the requirements are
  final exactly at close), so inlining keeps the corpus current at the only natural
  trigger; 0024's compaction has no such natural trigger (it is periodic
  maintenance keyed on file size), so a separate explicit command was right there —
  different trigger semantics, deliberately different UX.
- **MODIFY/REMOVE carry an explicit verbatim target locator.** Every MODIFY/REMOVE
  delta entry names the exact existing requirement line (provenance suffix stripped
  for matching). The helper does an exact normalized match; zero-or-many matches
  fall through to the conflict path; a missing locator is a malformed-block
  rejection. Rejected: keying the match on the `(spec NNNN)` suffix (it is
  provenance, not identity — explicitly list-valued and non-unique) or on model
  fuzzy-search (would fire "conflict" on ordinary lookup misses).
- **Closed spec dir is MOVED to `specs/.archive/NNNN-slug/` as the LAST step, only
  when zero conflicts remain; frontmatter status UNCHANGED (`closed`).** The move
  is the commit signal; on decline or while any conflict is open, NOTHING moves and
  the spec stays a live silo under `specs/`. Moving a closed spec's directory is a
  RELOCATION, not a content modification — the `.md` files inside are not edited —
  so it does not violate the "never modify a closed spec" guardrail (and `.md` is
  not guard-gated anyway). "Already consolidated?" is inferred from LOCATION
  (presence under `specs/.archive/`), not a status field. Rejected: introducing a
  new `status: consolidated` value (it would force a state-machine change for no
  added signal — location is simpler).
- **Open-conflict sink = `consolidation-conflicts.md` inside the spec dir.**
  Rejected: `state.json` (entangles the speccraft-state single-writer rule) and the
  domain file (would break "domain line byte-unchanged"). Because an open-conflict
  spec is never moved, the conflict file lives alongside the un-consolidated spec
  under `specs/` and its existence is the discoverable signal (no content scan).
- **Domain context loading = on-demand by area.** Rejected: eager/always loading
  (reintroduces unbounded-context bloat) and human-only/never-loaded (forfeits the
  "read current behavior in one place" payoff). Safe because domain files are
  bounded (deduped; MODIFY collapses superseded text into the archive), unlike the
  unbounded closed-dir pile.
- **Open-set domains (`<area>.md` exists ⇒ domain exists).** Rejected: a fixed
  enum / registry of domains (adds a registration step and a maintenance silo).
- **Routing = heuristic-seed-then-confirm when `domains:` is absent; explicit
  `domains:` authoritative.** Rejected: block-and-prompt with no seed (more
  friction) and silent auto-route (unreviewable).
- **Merge vocabulary = ADD/MODIFY/REMOVE, explicit `delta:` authoritative with a
  model-inferred fallback surfaced for confirmation.**
- **Conflict = propose/confirm; decline records an open conflict and the spec still
  closes.** An unresolved conflict NEVER blocks close.
- **Two archives, clock-free** — wholesale dir MOVE as the last step (A) plus an
  append-only requirement-text archive (B). Each archive-B entry is a
  self-describing header (area + source spec id(s) + operation) followed by the
  verbatim superseded text WITH its original `(spec NNNN)` suffix; dedup identity is
  a **full-entry byte-match (header + text)**, NOT a payload-only match — so two
  distinct supersession events with byte-identical payloads keep distinct headers
  and both persist. Rejected: payload-only dedup (silently collapses distinct
  provenance).
- **Idempotent domain writes.** ADD dedups by (locator-normalized text +
  provenance); a MODIFY/REMOVE whose locator is already absent/applied is a no-op —
  so a crash/re-run before the dir-move neither duplicates nor re-applies.
- **Backfill via `/speccraft:sync`, per-spec propose, confirm-gated.** Candidate
  predicate is location-based + clock-free (`status==closed` AND dir still under
  `specs/` AND no `consolidation-skip` marker), subsuming pre-feature and
  declined-at-close specs. Ordering key is `.speccraft/history.md` chronological
  order (oldest-first), NOT ascending spec ID. Rejected: a date-based predicate
  (misses declined-at-close specs) and ascending-ID ordering (spec ID is not
  closure order). Per-spec progress is tracked by marker files, never by editing a
  closed spec's frontmatter.
- **Backfill reuses spec 0024's history.md parser.** The oldest-first replay
  consumes 0024's existing `## YYYY-MM-DD … (spec NNNN)` history-entry parser rather
  than writing a second chronology source — an explicit design coupling. A closed
  spec with NO history.md entry is appended AFTER all history-ordered specs, ordered
  among themselves by `created:` frontmatter date then by ID.
- **Reuse `memory-keeper` with a documented `# Mode` for consolidation.** Rejected:
  a new agent or store.
- **Two-tier testing per spec 0022** — the deterministic helper is a **pure-shell**
  sourceable `commands/spec/<name>.lib.sh` (spec-0015 colocation) with bats
  coverage; there is NO new Go binary, so implementing this needs NO
  `/speccraft:spec:override` (`.sh`/`.md` are not guard-gated). A SOURCED
  credit-gated e2e fixture covers the model tier; the deterministic SEED of each
  model heuristic (routing-seed key, delta parse, locator match) is pinned at the
  cheap bats layer (the 0024 "deterministic seed of a model heuristic" convention).

## Lifecycle / behavior contract

- **Close stays a superset, not a replacement.** Consolidation runs INLINE at
  `/speccraft:spec:close` after the existing close steps (state/index update,
  history append). If consolidation is declined or a conflict is left open, close
  still completes; consolidation never gates close.
- **Routing.** Read frontmatter `domains: [<area>…]`. If present, it is the routing
  target list. If absent, compute a deterministic routing-seed key from the spec's
  path/title and present the seeded target(s) for confirm/correct. A multi-domain
  spec is split per-domain and the full split is shown before any write.
- **Delta parse.** An explicit `delta:` block is parsed/validated deterministically
  into ordered ADD/MODIFY/REMOVE requirement entries; a malformed block is rejected
  with a diagnostic and produces no merge. Every MODIFY/REMOVE entry MUST carry a
  non-empty verbatim target locator; a MODIFY/REMOVE missing a locator is a
  malformed-block rejection. ADD entries carry no locator. When no `delta:` block
  exists, the model proposes an ADD/MODIFY/REMOVE classification as a fallback,
  surfaced for confirmation.
- **Merge.** Per target domain file: ADD appends the requirement with its
  `(spec NNNN)` suffix; MODIFY locates the existing line by an **exact normalized
  match** of its verbatim locator (trim the trailing `(spec NNNN)` provenance suffix
  + surrounding whitespace) and, on a unique match, replaces it, appends the
  modifying id to the suffix list, and sends the superseded text to archive (B);
  REMOVE locates its line the same way and, on a unique match, deletes it and sends
  its text to archive (B). If a MODIFY/REMOVE locator matches zero or more than one
  line, the entry falls through to the conflict path — it is never applied to a
  guessed line. **Multi-domain locator scoping:** because routing assigns each delta
  entry to a specific target domain file first, a MODIFY/REMOVE locator is matched
  ONLY within its routed domain file — there is no cross-file locator ambiguity by
  construction; if a spec author mis-routes such that the locator matches zero lines
  in the routed file, that is the normal no-unique-match → conflict-path case, not a
  special cross-file rule. The domain file keeps its header structure and the
  provenance-suffix grammar. Domain writes are idempotent: ADD dedups by
  (locator-normalized text + provenance), and a MODIFY/REMOVE whose locator is
  already absent/applied is a no-op.
- **Conflict propose/confirm, and conflict-file removal on resolution.** When a
  MODIFY/REMOVE locator matches zero or >1 lines, or a proposed line conflicts with
  existing domain text, the old-vs-new proposal is shown for accept/reject. Decline
  leaves the domain line byte-unchanged and records the open conflict in
  `specs/NNNN-slug/consolidation-conflicts.md` (inside the spec dir, written before
  any dir-move would fire); the spec still closes. While that conflict file exists,
  the spec dir is NOT moved, so the file's existence alongside the un-consolidated
  spec under `specs/` is itself the discoverable signal. **The helper DELETES
  `consolidation-conflicts.md` once every conflict it records has been resolved (the
  delta applied or the developer dropped it); the file's ABSENCE is exactly the
  zero-conflict precondition the dir-move gates on.** So a later re-run/backfill that
  resolves the last open conflict removes the file and the dir-move fires; a stale
  conflict file is never left to permanently pin the spec as a live silo.
- **Two archives — the dir-move is the LAST step.** (A) The closed spec dir is moved
  wholesale `specs/NNNN-slug/ → specs/.archive/NNNN-slug/` with frontmatter `status`
  left as `closed`, but ONLY after the spec is FULLY RESOLVED — every delta entry
  applied with ZERO open conflicts remaining — and the move is the LAST step in the
  sequence (the commit signal). Moving a closed spec's directory is a RELOCATION,
  not a content modification: the `.md` files inside are relocated, not edited, so
  it is not subject to the "never modify a closed spec" guardrail (and `.md` is not
  guard-gated). The only files ever ADDED inside a closed spec dir are the marker
  files (`consolidation-conflicts.md` / `consolidation-skip`), which are new sidecar
  files, not edits to `spec.md`/`plan.md`/`tasks.md`. On decline, or while any
  conflict is open, NOTHING moves. (B) Each superseded requirement is appended to
  `specs/domains/.archive/<area>.md` (fixed path, clock-free, append-only) as a
  self-describing entry: a deterministic header line (area + source spec id(s) +
  operation MODIFY|REMOVE) followed by the verbatim superseded text INCLUDING its
  original `(spec NNNN)` suffix. Dedup is a full-entry byte-match (header + text), so
  an entry already byte-present is never re-appended while two distinct events with
  byte-identical payloads both persist under distinct headers.
- **Backfill.** `/speccraft:sync` enumerates candidates by the location-based,
  clock-free predicate — `status==closed` AND dir still under `specs/` (not
  `specs/.archive/`) AND no `consolidation-skip` marker — which subsumes both
  pre-feature specs and specs whose consolidation was declined at close. It replays
  them in `.speccraft/history.md` chronological order: history.md is append-only
  newest-first, so replay is bottom-up = oldest-first, reusing spec 0024's existing
  `## YYYY-MM-DD … (spec NNNN)` history parser (an explicit design coupling — there
  is no second chronology source). A closed spec with NO history.md entry is ordered
  AFTER all history-ordered specs, sorted among themselves by `created:` frontmatter
  date then by ID. The full computed replay order is PRESENTED to the developer for
  confirmation before backfill runs. Per spec, backfill proposes the same routing →
  delta → merge → archive flow under confirmation. Progress/outcome is tracked by
  MARKER FILES inside each spec dir, never by editing a closed spec's frontmatter:
  moved-to-`.archive` ⇒ consolidated (terminal); `consolidation-conflicts.md`
  present ⇒ conflict-open (re-offer to resolve); a `consolidation-skip` sentinel
  file ⇒ declined (don't re-offer unless forced); none present ⇒ pending. So each
  eligible spec is proposed exactly once per run and a decided spec is not
  re-prompted.
- **Idempotence.** A spec already under `specs/.archive/` is treated as fully
  consolidated and skipped (no re-merge, no re-archive). Because the dir-move is the
  LAST step, a crash or re-run before it finds the spec still under `specs/` and
  safely re-runs the idempotent merge: ADD dedups by (locator-normalized text +
  provenance), an already-applied MODIFY/REMOVE is a no-op, and archive (B)
  full-entry byte-dedups — so a partial/interrupted consolidation neither duplicates
  an ADD line nor re-applies an already-applied MODIFY/REMOVE, and the dir-move only
  fires once zero conflicts remain.
- **Blast radius.** A consolidate run writes/moves ONLY `specs/domains/<area>.md`,
  `specs/domains/.archive/<area>.md`, `specs/.archive/NNNN-slug/`,
  `specs/NNNN-slug/consolidation-conflicts.md`, `specs/NNNN-slug/consolidation-skip`,
  plus the state/index updates close already performs. It NEVER edits `history.md`,
  `conventions.md`, `architecture.md`, or any other spec directory.
- **Context-skill invariant.** Both `specs/.archive/**` and
  `specs/domains/.archive/**` are NEVER added to the `speccraft-context` skill load
  list and carry NO `enforce:` markers (`speccraft-drift` never scans them) —
  mirroring 0024's history-archive invariant, so archiving can never silently
  re-bloat context. The live `specs/domains/<area>.md` files ARE on the load list,
  pulled lazily by area.
- **Template purity.** All domain-file shape assumptions — the `(spec NNNN)`
  provenance-suffix grammar, the `.archive/` layout, the header structure — live in
  the repo-root command/helper, NEVER in stack-agnostic assets under
  `templates/speccraft/`.

## Acceptance criteria

### Deterministic tier — pinned by the pure-shell `*.lib.sh` helper + bats

1. **Delta-block parse/validate, locator required on MODIFY/REMOVE.** A well-formed
   `delta:` block parses into the correct ordered set of ADD/MODIFY/REMOVE entries
   AND every MODIFY/REMOVE entry carries a non-empty verbatim target locator; a
   MODIFY/REMOVE missing a locator is a malformed-block rejection (diagnostic, no
   merge). A malformed block more generally is rejected with a diagnostic and
   produces no merge. ADD entries carry no locator. The locator is matched by exact
   normalized comparison (trailing `(spec NNNN)` provenance suffix + surrounding
   whitespace trimmed); zero-or-many matches do NOT apply and fall through to the
   conflict path. A suffix-less requirement line still parses (provenance id is
   empty, not an error).
2. **Routing-seed key is deterministic.** With `domains:` absent, the helper
   computes a stable routing-seed key from the spec's path/title that is identical
   across runs for the same input (the model proposal is seeded from this key, never
   the reverse).
3. **Archive dir-move-last + append-only full-entry dedup, no loss.** The dir move
   `specs/NNNN-slug/ → specs/.archive/NNNN-slug/` is a MOVE (never a delete), fires
   ONLY when zero conflicts remain, and is the LAST step; the moved dir's frontmatter
   `status` stays `closed`. Each archive-B entry is a deterministic header (area +
   source spec id(s) + operation MODIFY|REMOVE) followed by the verbatim superseded
   text WITH its `(spec NNNN)` suffix, appended to `specs/domains/.archive/<area>.md`;
   dedup identity is a FULL-ENTRY byte-match (header + text), so an identical re-run
   is never re-appended while two distinct events with byte-identical payloads but
   different headers both persist.
4. **Blast radius.** A consolidate run modifies only `specs/domains/<area>.md`,
   `specs/domains/.archive/<area>.md`, `specs/.archive/NNNN-slug/`,
   `specs/NNNN-slug/consolidation-conflicts.md`, `specs/NNNN-slug/consolidation-skip`,
   and the state/index files close already touches; `history.md`, `conventions.md`,
   `architecture.md`, and every other spec directory are byte-unchanged.
5. **Domain-file structural invariants.** The helper asserts the `(spec NNNN)` /
   `(specs NNNN, MMMM)` provenance-suffix grammar on every merged line (MODIFY
   appends the modifying id to the list) and asserts that neither `specs/.archive/`
   nor `specs/domains/.archive/` ever appears in the `speccraft-context` load list.
6. **Re-run idempotence after interruption, with pinned per-delta write order.** A
   re-run after a partial or interrupted consolidation neither duplicates an ADD line
   (deduped by locator-normalized text + provenance) nor re-applies an already-applied
   MODIFY/REMOVE (no-op when the target locator is already absent/applied), archive
   (B) full-entry byte-dedups, and the dir-move fires only when zero conflicts remain.
   The per-delta write order for MODIFY/REMOVE is **archive-B append FIRST, then the
   domain mutation, then dir-move LAST**, pinned at both crash windows: (a) a crash
   after archive-B append but before the domain mutation re-runs to exactly one
   archive-B entry (no duplicate) and applies the domain mutation once; (b) a crash
   after the domain mutation but before the dir-move re-runs to exactly one archive-B
   entry and a no-op domain mutation (locator already absent/applied). The
   reverse-order (mutate then archive) preimage-loss case is excluded by construction.

### Model-behavior tier — pinned by an e2e fixture (structural predicates only)

7. **Merge into the domain file (structural).** After a confirmed close, the routed
   `specs/domains/<area>.md` exists and its line count has increased, and the
   `(spec NNNN)` / `(specs NNNN, MMMM)` provenance-suffix regex matches on the merged
   line(s); for a MODIFY, the archive-B file `specs/domains/.archive/<area>.md` exists
   and is non-empty. (Structural predicates only — no assertion of merged prose
   content or feature-named keywords.)
8. **Conflict old-vs-new proposal, non-blocking, sink present, removed on
   resolution.** A conflicting MODIFY/REMOVE is shown as an old-vs-new proposal for
   accept/reject; on decline, `specs/NNNN-slug/consolidation-conflicts.md` EXISTS in
   the spec dir, the domain line is byte-unchanged, the spec STILL closes, and the
   spec dir is NOT moved to `specs/.archive/`. On a later run that resolves the last
   open conflict, the helper DELETES `consolidation-conflicts.md`; its absence is the
   zero-conflict precondition that lets the dir-move fire, so a resolved conflict
   never leaves a stale file pinning the spec as a live silo.
9. **Inline-at-close confirm-gating; decline moves nothing.** Consolidation runs
   inside `/speccraft:spec:close`, presents the proposed routing + split + merge +
   archive plan, and writes/moves nothing until the developer confirms; on decline,
   the domain files and `specs/` layout are byte-identical to before (the spec dir is
   NOT moved) and close still completes.
10. **Routing seed confirmed, multi-domain split shown.** With `domains:` absent the
    seeded target is presented for confirm/correct (never silently applied); a
    multi-domain spec's per-domain split is shown in full before any write.
11. **`/speccraft:sync` backfill propose loop.** `sync` proposes consolidation per
    spec for every candidate (`status==closed` AND dir still under `specs/` AND no
    `consolidation-skip` marker), ordered by `.speccraft/history.md` chronology
    (oldest-first, history-less or compacted-out specs last by `created:` then ID);
    each eligible spec is proposed at most once *within a run* (within-run dedup);
    accepting one routes/merges/archives it (dir moved); declining one writes a
    `consolidation-skip` marker so it is excluded by the candidate predicate on every
    *future* run (across-run skip-permanence); and an already-archived spec is skipped.
12. **Provenance recoverable (structural).** For every consolidated requirement, the
    archive-B header line (area + spec + op) plus the suffix-bearing verbatim text in
    a non-empty `specs/domains/.archive/<area>.md`, the moved spec dir present under
    `specs/.archive/NNNN-slug/` (A), and git let a reader answer "which spec(s)
    produced this" with NO collision-driven loss. (Asserted structurally: header-line
    shape present, archive file non-empty, moved dir exists — not merged prose
    content.)

## Out of scope

- **`history.md` compaction** (spec 0024 — separate change).
- A separate `/speccraft:spec:consolidate` command — consolidation is inline at
  close (rejected alternative, see Decisions).
- A new `status: consolidated` frontmatter value — "already consolidated" is
  inferred from location under `specs/.archive/` (rejected alternative, see
  Decisions).
- Semantically perfect routing / conflict detection — both are best-effort and
  always human-confirmed; a missed route or conflict is acceptable and correctable.
- A `[config]` / `[domains]` section for routing or merge thresholds — a possible
  follow-up, not built here.
- Eager/always-on loading of domain files into context — loading is on-demand by
  area only.

## Open questions

_none — every interview question and every cross-model-review blocker resolved (see
Decisions + Lifecycle): trigger (inline-at-close), spec-dir disposition (move-last +
status unchanged), context loading (on-demand), domain set (open-set), routing
(heuristic-seed-confirmed), merge vocabulary with required MODIFY/REMOVE locator
(B1), decline/move atomicity + idempotence (B2), the `consolidation-conflicts.md`
open-conflict sink (B3), location-based backfill predicate + history.md-order replay
with the `created:`-then-ID fallback for history-less specs + marker-file progress
(B4), archive-B self-describing header + full-entry dedup (B5), structural-only AC6/
AC11 (N1), the relocation-not-modification carve-out (N2), pure-shell helper / no Go
/ no override (N3), the deliberate 0024 trigger-semantics divergence (N4),
multi-domain locator scoping (N5), and the deterministic/model tier split. Round-2
review carry-forwards folded in pre-`reviewed`: per-delta write order archive-B →
mutation → move with both crash-window ACs (CF-1, codex), conflict-file deletion on
resolution (CF-2, claude-p), and the honest 0024-compaction/`created:`-fallback +
backfill-predicate wording reconciliation (CF-3, claude-p)._
