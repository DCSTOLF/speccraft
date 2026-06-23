---
description: "Reconcile .speccraft/ memory with reality. Detect drift."
allowed-tools: ["Read", "Write", "Edit", "Bash"]
---

Run a drift scan and a memory-keeper audit pass.

Steps:

1. Run `speccraft-drift scan-all` over `enforce:`-tagged conventions and
   guardrails. Report violations with file:line references.

2. Invoke the `memory-keeper` subagent in audit mode with:
   - The drift report from step 1
   - `git log --since=<last sync>` (or full log if first sync) for context
   - A sampled list of changed files since last sync

   Propose:
   - New conventions implied by repeated patterns visible in recent diffs
   - Architecture updates implied by new top-level packages
   - Stale entries in conventions.md / architecture.md

3. Present proposals for approval. Apply approved ones.

4. **Retroactive spec-consolidation backfill (confirm-gated, per spec).** Fold any
   closed spec that never went through inline-at-close consolidation into its
   domain file(s). This is the same routing → delta → merge → archive flow that
   `/speccraft:spec:close` runs inline, applied retroactively. Source the helper:

   ```bash
   REPO_ROOT="$("$CLAUDE_PLUGIN_ROOT/bin/speccraft-state" find-root)"
   source "$CLAUDE_PLUGIN_ROOT/commands/spec/consolidate.lib.sh"
   CANDIDATES="$(consolidate_backfill_candidates "$REPO_ROOT" | tr '\n' ' ')"
   ORDER="$(consolidate_backfill_order "$REPO_ROOT" "$CANDIDATES")"
   ```

   - **Candidate predicate (location-based, clock-free).**
     `consolidate_backfill_candidates` returns every spec dir still under `specs/`
     with `status: closed` and no `consolidation-skip` marker — subsuming both
     pre-feature specs and specs whose consolidation was declined at close.
   - **Replay order.** `consolidate_backfill_order` orders candidates by
     `.speccraft/history.md` chronology (oldest-first, reusing spec 0024's history
     parser). A candidate whose history entry was compacted out by spec 0024 (no
     parseable `## YYYY-MM-DD … (spec NNNN)` line) falls to a `created:`-then-ID
     bucket ordered LAST — presentation ordering only, not guaranteed closure order.
     PRESENT the full computed `ORDER` to the developer for confirmation before
     running.
   - **Per spec, confirm-gated.** For each candidate in order, propose the same
     routing → delta → merge → archive flow (reusing `memory-keeper` Mode:
     consolidate). On accept, apply and move the dir to `specs/.archive/`. On
     **decline**, write a `consolidation-skip` marker (`touch
     "$REPO_ROOT/specs/<id>/consolidation-skip"`) so the spec is excluded from every
     future run. Each eligible spec is proposed at most once per run; an
     already-archived spec is skipped.
