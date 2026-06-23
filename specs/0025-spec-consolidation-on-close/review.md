---
spec: "0025"
title: "Spec consolidation into current domain specs on close"
revision: 1
reviewers: [codex, claude-p]
quorum: 1
verdict: approve-with-comments
round: 2
generated: 2026-06-23T00:00:00Z
---

# Cross-model review — 0025 (round 2)

**Status: QUORUM MET.** claude-p returned `approve-with-comments`; codex returned `changes-requested` on one remaining durability gap. Per repo precedent (spec 0016 "fixed before flipping to reviewed", spec 0021 carry-forwards folded into spec before planning), the three remaining items (CF-1..CF-3) are being folded into `spec.md` before the status flips to `reviewed`.

---

## Round-2 outcome — revision 1 resolved all five round-1 blockers

Both reviewers confirm the fixes are substantive, not reworded:

- **B1 (MODIFY/REMOVE locator undefined)** — RESOLVED. AC1 now requires a verbatim target-line locator on every MODIFY/REMOVE, exact normalized match (suffix-stripped), bats-pinned; zero-or-many matches fall through to the conflict path; missing locator is a malformed-block rejection. Locator is no longer a fuzzy-search heuristic.
- **B2 (decline/move atomicity + ADD non-idempotence)** — RESOLVED. Dir-move is explicitly the LAST step (the commit signal); on decline or any open conflict, NOTHING moves; ADD dedups by (locator-normalized text + provenance); MODIFY/REMOVE is a no-op when the target locator is already absent/applied; AC6 pins re-run safety.
- **B3 (open-conflict sink undefined)** — RESOLVED. Named sink is `specs/NNNN-slug/consolidation-conflicts.md`, written before any dir-move fires, inside the spec dir, never in `state.json` and never in the domain file. Its existence is the discoverable signal; no content scan needed.
- **B4 (backfill predicate + ordering)** — RESOLVED. Candidate predicate is location-based and clock-free (`status==closed` AND dir still under `specs/` AND no `consolidation-skip` marker), subsuming pre-feature and declined-at-close specs. Ordering key is `.speccraft/history.md` chronological order (oldest-first, NOT ascending spec ID); history-less specs fall to `created:`-then-ID bucket last. Progress tracked by marker files, never by editing closed-spec frontmatter.
- **B5 (archive-B provenance / dedup)** — RESOLVED. Each archive-B entry has a self-describing header (area + source spec id(s) + operation); dedup is full-entry byte-match (header + text), so two distinct supersession events with byte-identical payloads keep distinct headers and both persist; AC12 scoped to structural predicates only.

Non-blockers N1–N5 also resolved: structural-only AC predicates (N1); relocation-not-modification carve-out (N2); pure-shell helper, no Go, no override (N3); 0024 trigger-semantics divergence justified in Decisions (N4); multi-domain locator scoped to routed file by construction (N5).

---

## codex

**Verdict:** changes-requested

Concerns:
- B-decline-atomicity mostly resolved, but interruption idempotence has ONE unresolved crash window: if a MODIFY/REMOVE updates the domain file BEFORE archive-B is appended, a re-run treats the missing locator as already-applied (no-op) and can no longer recover the suffix-bearing superseded text required for archive-B provenance. The spec's idempotence section describes safety after the dir-move but does not pin the within-delta write order for MODIFY/REMOVE operations.
- Lifecycle section lists the Merge step before the Two archives step; archive-B MUST contain the superseded text BEFORE the destructive domain MODIFY/REMOVE fires, or a crash between those two writes permanently loses the preimage.

Suggestions:
- Specify per-delta write order for MODIFY/REMOVE as: archive-B append FIRST, then domain mutation (MODIFY/REMOVE), then dir-move LAST. Full-entry dedup makes a re-run after archive-B-but-before-domain-mutation safe (archive-B entry already present; domain mutation not yet applied, so re-run applies it once).
- Add deterministic ACs for both crash points: (a) crash after archive-B append but before domain mutation — re-run produces no duplicate archive-B entry and successfully applies the domain mutation; (b) crash after domain mutation but before dir-move — re-run produces no duplicate archive-B entry and the domain mutation is a no-op (locator already absent/applied).

Guardrail violations: none

Convention violations: none

---

## claude-p

**Verdict:** approve-with-comments

Concerns:
- **0024↔0025 chronology coupling is silent about the dominant failure mode.** Spec 0024 folds the OLDEST `history.md` entries into a `## Compacted` thematic section (NOT the `## YYYY-MM-DD … (spec NNNN)` shape 0025's reused parser keys on) and moves originals to `history-archive/`. The oldest closed specs are exactly the most likely backfill candidates, so for them the "history.md oldest-first" replay collapses silently to the `created:`-then-ID fallback — which is NOT closure order. The spec defines the fallback but does not acknowledge that 0024 makes it the dominant path for old specs. Fails safe (confirm-gated, per-spec conflict path) but the headline ordering guarantee is weaker in practice than it reads.
- **Conflict-file lifecycle underspecified.** The marker scheme makes `consolidation-conflicts.md` present == conflict-open, and dir-move requires ZERO open conflicts, so resolving a conflict must remove that file before the dir can move — but nothing in What/Lifecycle/ACs states what removes `consolidation-conflicts.md` or when. A stale file left after resolution would permanently pin the spec as a live silo.
- **Backfill predicate wording diverges between What and AC11.** What says `status==closed AND dir still under specs/`; AC11 adds `AND no consolidation-skip` — the skip-exclusion is present in one place and absent in the other. Also, "proposed exactly once per run" (AC11) vs "declined → not re-offered" (Decisions) leave within-run dedup and across-run skip-permanence subtly ambiguous.

Suggestions:
- Add a note that when a candidate's history entry has been compacted out by 0024 (no parseable `## YYYY-MM-DD … (spec NNNN)` line), it falls to the `created:`-then-ID bucket and ordering there is presentation-only, closure-order NOT guaranteed.
- Specify conflict-file removal explicitly: "on conflict resolution the helper deletes `consolidation-conflicts.md`; its ABSENCE is the zero-conflict precondition for the dir-move." Pin in AC6 and AC8.
- Reconcile "no `consolidation-skip` marker" into the What backfill predicate (it is already in AC11) and distinguish "proposed exactly once per run" (within-run dedup) from "declined → not re-offered" (across-run skip-permanence) so both invariants are unambiguous.

Guardrail violations: none

Convention violations: none

---

## Synthesis

Revision 1 is a genuine, substantive response to all five round-1 blockers. The locator model, the idempotence/commit-signal design, the named conflict sink, the location-based backfill predicate, and the archive-B full-entry dedup are all correctly specified and the non-blockers are cleaned up. Both reviewers agree the architecture is sound and implementable.

**One real durability gap remains (codex, CF-1):** the per-delta write order for MODIFY/REMOVE is not pinned. The current spec says archive-B append and domain mutation are idempotent individually, but does not state that archive-B fires BEFORE the domain mutation within each delta. A crash between them loses the preimage irrecoverably (the re-run correctly treats the already-absent locator as a no-op but the archive-B entry was never written). This is a small, targeted fix — one sentence in Lifecycle/Idempotence plus two AC entries — not a structural revision.

**Two tidy-up gaps (claude-p, CF-2 and CF-3):** the conflict-file removal step is missing from the lifecycle and ACs, which would leave a stale marker permanently pinning a spec as unconsolidated; and the 0024↔0025 chronology coupling needs an honest acknowledgement that compacted-out history entries make the `created:`-then-ID fallback the dominant path for old specs, not the exception.

---

## Carry-forwards (folded into spec.md before plan)

**CF-1 (codex — real durability gap): per-delta write order for MODIFY/REMOVE must be pinned.**

The spec must state that for each MODIFY/REMOVE delta, the write order is: (1) append the archive-B entry FIRST, (2) then apply the domain mutation (MODIFY/REMOVE), (3) then dir-move LAST (already specified). This ordering ensures that a crash before archive-B cannot lose the suffix-bearing preimage, and full-entry dedup makes the post-archive/pre-mutation crash window safe (re-run finds archive-B already present, applies domain mutation once). Add to Lifecycle/Idempotence and add two deterministic AC entries: crash-after-archive-B-but-before-domain-mutation (no duplicate archive-B, domain mutation applied on re-run) and crash-after-domain-mutation-but-before-dir-move (no duplicate archive-B, domain mutation is a no-op on re-run).

**CF-2 (claude-p): conflict-file removal must be specified.**

The spec must state that on conflict resolution the helper DELETES `consolidation-conflicts.md`; its ABSENCE is the zero-conflict precondition for the dir-move. Without this, a resolved conflict leaves a stale marker that permanently prevents dir-move, pinning the spec as a live silo indefinitely. Pin in AC6 (re-run idempotence) and AC8 (conflict sink / non-blocking close).

**CF-3 (claude-p): acknowledge 0024↔0025 chronology coupling honestly; reconcile backfill predicate wording.**

Add a note — in Decisions (Backfill reuses spec 0024's history.md parser) or in Lifecycle (Backfill) — that a candidate whose history entry was compacted out by 0024 (now under `## Compacted` / `history-archive/`) has no parseable `## YYYY-MM-DD … (spec NNNN)` line for the replay parser, so it falls to the `created:`-then-ID bucket; ordering there is presentation-only and NOT guaranteed closure order. It still fails safe via the confirm-gated conflict path. Also reconcile the backfill predicate: add "AND no `consolidation-skip` marker" to the What section (already in AC11) and make within-run dedup ("proposed exactly once per run") and across-run skip-permanence ("declined → `consolidation-skip` written → not re-offered on future runs") unambiguous in both places.

---

## Recommended next step

Fold CF-1, CF-2, and CF-3 into `spec.md` now (pre-flip, per 0016/0021 precedent — these are carry-forward refinements, not new design decisions). Then flip `status` to `reviewed` and run `/speccraft:spec:plan`.
