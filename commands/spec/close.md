---
description: "Close the active spec: write changelog, propose memory updates"
allowed-tools: ["Read", "Write", "Edit", "Bash"]
---

Close the active spec.

**IMPORTANT**: Execute ALL steps below using your tools before responding. Do
not describe steps — carry them out.

Steps:

1. Read `.speccraft/state.json` for `active_spec`. If none, error.
   Read spec.md, tasks.md.

2. Verify all tasks in tasks.md are `[x]`. If not, ask the user to:
   (a) confirm closure anyway, or (b) re-open and finish the remaining tasks.
   If the user's message contains "approve all" or the spec was created in a
   non-interactive context, proceed with closure regardless.

3. Compute the diff between when the spec started (commit at
   `started_at_sha` in spec frontmatter if set, else creation time resolved
   to a commit SHA) and HEAD:
   ```bash
   git diff <started_at_sha>...HEAD
   ```

4. Invoke the `memory-keeper` subagent with:
   - spec.md, plan.md, tasks.md
   - The full diff from step 3
   - Current `.speccraft/architecture.md`, `conventions.md`, `history.md`

   The agent proposes:
   - A `changelog.md` for the spec (what shipped vs spec, deviations)
   - An ADR entry for `history.md`
   - Convention additions/changes
   - Architecture updates (if any)

5. Show all proposed changes for user approval. If the user's message
   contains "approve all" or similar blanket approval, apply all changes
   automatically.

6. Edit `spec.md` frontmatter to set `status: closed`. Then run:
   ```bash
   "$CLAUDE_PLUGIN_ROOT/bin/speccraft-state" set active_spec null
   ```

   **Do not edit `.speccraft/state.json` directly under any circumstance**
   — even to "fix" a value the binary just produced. The only sanctioned
   writer is `speccraft-state`; the spec-0012 PreToolUse hook will
   reject any Edit/Write/MultiEdit/NotebookEdit targeting that file. If
   `set active_spec null` appears to leave a wrong value, that is a
   `speccraft-state` bug and the right response is to file a follow-up
   spec, not to hand-edit around it.

7. Update `.speccraft/index.md`:
   - "Active spec" section → "none"
   - "Recent decisions" section → last 3 entries from history.md

8. **History-compaction nudge (non-blocking; edits nothing).** After the close is
   complete, check whether `history.md` has grown past its bound and there is
   actually something below the recent window:
   ```bash
   REPO_ROOT="$("$CLAUDE_PLUGIN_ROOT/bin/speccraft-state" find-root)"
   source "$CLAUDE_PLUGIN_ROOT/commands/history/compact.lib.sh"
   HIST="$REPO_ROOT/.speccraft/history.md"
   COUNT="$(history_parse_entries "$HIST" | grep -c '^## ' || true)"
   BYTES="$(wc -c < "$HIST" | tr -d ' ')"
   if [ "$(history_nudge_predicate "$COUNT" "$BYTES" "$HISTORY_WINDOW_N")" = "nudge" ]; then
     echo "note: history.md has $COUNT entries / $BYTES bytes — consider running /speccraft:history:compact"
   fi
   ```
   This only prints a suggestion. It MUST NOT edit `history.md` or anything else;
   compaction happens solely via the explicit `/speccraft:history:compact` command.

9. **Inline spec consolidation (confirm-gated; never gates close).** After the
   close is otherwise complete (state/index/history already updated), fold the
   just-closed spec's final requirements into its domain file(s). This step is
   confirm-gated and additive — if the developer declines, or any conflict is left
   open, **the spec still closes** and NOTHING is moved (close still completes
   regardless). Source the helper and reuse `memory-keeper` (Mode: consolidate) for
   the prose merge + propose/confirm:

   > **Routing target & blast radius — do NOT confuse with step 4.** Consolidation
   > routes ONLY to `specs/domains/<area>.md` (the per-domain requirement files) and
   > NEVER writes `.speccraft/architecture.md`, `conventions.md`, or `history.md`.
   > Those `.speccraft/` files are the step-4 `Mode: close` memory updates, which are
   > a SEPARATE concern and are NOT a substitute for this step-9 consolidation:
   > folding requirements into `.speccraft/architecture.md`/`conventions.md` does NOT
   > consolidate them — the requirements must land in `specs/domains/`. A missing
   > `delta:` or `domains:` block is **a fallback, never a skip**: with no `delta:`,
   > `memory-keeper` proposes a confirm-gated ADD/MODIFY/REMOVE classification into
   > the routed domain file; with no `domains:`, the seeded area (now grounded by
   > `consolidate_existing_domains`) is presented for confirm/correct. Either way the
   > target is `specs/domains/`, never `.speccraft/`.

   ```bash
   REPO_ROOT="$("$CLAUDE_PLUGIN_ROOT/bin/speccraft-state" find-root)"
   source "$CLAUDE_PLUGIN_ROOT/commands/spec/consolidate.lib.sh"
   SPEC_DIR="$REPO_ROOT/specs/$ACTIVE"
   ```

   a. **Route.** `consolidate_routing_seed "$SPEC_DIR/spec.md"` yields the target
      area(s). An explicit frontmatter `domains:` is authoritative; otherwise the
      seeded area is PRESENTED for the developer to confirm/correct (never silent).
      Ground the proposal with the live domain set —
      `consolidate_existing_domains "$REPO_ROOT"` — so `memory-keeper` can prefer a
      good existing-domain match when one fits, or deliberately propose a clearly
      named NEW domain (open-set: a confirmed new `<area>` is created by writing
      `specs/domains/<area>.md`) when none fit. A multi-domain spec is split
      per-domain and the full split is shown before any write.
   b. **Parse the delta.** `consolidate_parse_delta "$SPEC_DIR/spec.md"` yields the
      ordered ADD/MODIFY/REMOVE records (each MODIFY/REMOVE carrying a verbatim
      locator). With no `delta:` block, the `memory-keeper` proposes a
      classification for confirmation.
   c. **Present the full plan and CONFIRM.** Show routing + split + the merge +
      every entry that would be archived. Write/move NOTHING until the developer
      confirms. On decline, the domain files and `specs/` layout are byte-identical
      to before.
   d. **Apply (on confirm).** Per entry, `consolidate_apply_delta <domain.md>
      <archive.md> <area> <spec-id> <op> <locator> <text>` (archive-B append FIRST,
      then the domain mutation). A return of `2` is a conflict: record it with
      `consolidate_record_conflict "$SPEC_DIR" "<old-vs-new>"` and continue — the
      spec still closes.
   e. **Commit move LAST, only at zero conflicts.** When every entry is applied and
      no `consolidation-conflicts.md` remains, `consolidate_archive_dir_move
      "$SPEC_DIR" "$REPO_ROOT/specs/.archive"` relocates the closed dir out of the
      live corpus (frontmatter `status` stays `closed`; location signals
      "consolidated"). While any conflict file exists the move is refused and the
      spec stays a live silo under `specs/` for a later `/speccraft:sync` backfill.
