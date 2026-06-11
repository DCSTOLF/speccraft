---
description: "Re-run Socratic interview on the active spec; archive stale artifacts, bump revision, return to draft."
argument-hint: ""
allowed-tools: ["Read", "Write", "Edit", "Bash"]
---

Re-run a Socratic interview against the **active** spec, optionally
cross-checking identifiers against `packages[]`, then archive stale
downstream artifacts and return the spec to `draft` status.

**IMPORTANT**: Execute ALL steps below using your tools before responding. Use
Bash for shell commands, Read for reading files, Write for creating files,
and Edit for modifying existing files. Do not describe steps — carry them
out.

The mechanism is implemented as named shell functions in
`commands/spec/revise.lib.sh`, which you must source before invoking any of
them. The lib is testable in isolation (see
`tests/hooks/spec-revise-preflight.bats`).

Steps:

1. **Bootstrap.** Source the helper library and resolve the repo root:
   ```bash
   REPO_ROOT="$("$CLAUDE_PLUGIN_ROOT/bin/speccraft-state" find-root)"
   source "$CLAUDE_PLUGIN_ROOT/commands/spec/revise.lib.sh"
   ```

2. **Preflight active-spec.** Verify `.speccraft/state.json` has a non-empty
   `active_spec`:
   ```bash
   preflight_active_spec_set "$REPO_ROOT/.speccraft/state.json" || exit 1
   ACTIVE="$(jq -r '.active_spec' "$REPO_ROOT/.speccraft/state.json")"
   SPEC_DIR="$REPO_ROOT/specs/$ACTIVE"
   SPEC_MD="$SPEC_DIR/spec.md"
   ```

3. **Preflight status gate.** Verify the spec's status is one of
   `draft|reviewed|planned`:
   ```bash
   preflight_status_gate "$SPEC_MD" || exit 1
   SOURCE_STATUS="$(grep -E '^status:' "$SPEC_MD" | head -1 | awk '{print $2}')"
   ```

4. **Ensure `revision:` field exists.** Idempotently inserts `revision: 0`
   if absent (command-owned; never delegated to the agent):
   ```bash
   ensure_revision_field "$SPEC_MD"
   N_OLD="$(grep -E '^revision:' "$SPEC_MD" | head -1 | awk '{print $2}')"
   ```

5. **Preflight archive collisions and source artifacts.** Refuse to proceed
   if archive targets already exist or source files are missing:
   ```bash
   preflight_archive_collisions "$SPEC_DIR" "$SOURCE_STATUS" "$N_OLD" || exit 1
   preflight_source_artifacts "$SPEC_DIR" "$SOURCE_STATUS" || exit 1
   ```

6. **Snapshot.** Capture pre-revise content for the post-agent diff and
   integrity check:
   ```bash
   SNAP_DIR="$(mktemp -d)"
   snapshot_spec "$SPEC_MD" "$SNAP_DIR"
   ```

7. **Cross-check (optional).** If `packages[]` is non-empty, extract
   identifier tokens and grep against the listed paths. Tokens with zero
   matches become drift items:
   ```bash
   DRIFT_ITEMS="$(run_cross_check "$SPEC_MD" "$REPO_ROOT")"
   ```
   If `DRIFT_ITEMS` is non-empty, present each line to the user as a
   Socratic question prefixed with the literal token `Q-DRIFT:` (see
   `agents/spec-reviser.md` §Q-DRIFT output contract). The spec-reviser
   subagent owns this presentation in step 8.

8. **Invoke the spec-reviser subagent.** Pass the current spec.md content
   and the `DRIFT_ITEMS` list. The subagent will interview the user,
   surface each drift item as a `Q-DRIFT:`-prefixed question, and edit the
   spec body sections (`## Why`, `## What`, `## Acceptance criteria`,
   `## Out of scope`, `## Open questions`) plus `packages:` in frontmatter
   when scope changes warrant. The subagent **must not** modify
   `revision:`, `status:`, `id:`, or `created:` — those are command-owned.

9. **Frontmatter integrity check.** Structurally enforce the prose
   prohibition: if the subagent touched any of the four command-owned
   keys, abort with a clear error (per review.md round-2 concern #3):
   ```bash
   frontmatter_integrity_check "$SPEC_MD" "$SNAP_DIR" || {
     echo "Restoring pre-revise spec.md from snapshot due to integrity violation." >&2
     cp "$SNAP_DIR/spec.md.pre" "$SPEC_MD"
     exit 1
   }
   ```

10. **Diff against snapshot.** Detect no-op vs real-change:
    ```bash
    OUTCOME="$(diff_against_snapshot "$SPEC_MD" "$SNAP_DIR")"
    ```

11. **No-op branch.** If `OUTCOME = "no-op"`, exit cleanly without
    archiving or bumping:
    ```bash
    if [ "$OUTCOME" = "no-op" ]; then
      echo "no changes — spec unchanged"
      exit 0
    fi
    ```

12. **Real-change branch.** Archive stale artifacts, bump revision, flip
    status to draft, then suggest the next step:
    ```bash
    archive_rename "$SPEC_DIR" "$SOURCE_STATUS" "$N_OLD" || exit 1
    bump_revision "$SPEC_MD" "$SOURCE_STATUS" || exit 1
    echo "Spec returned to draft at revision $((N_OLD + 1))."
    echo "Next step: /speccraft:spec:review"
    ```

Notes:

- `.speccraft/state.json` is **not** modified by this command. The
  active_spec stays set; session edit-tracking is irrelevant for revise.
  Preserves the single-writer discipline established by spec 0012.
- The spec-reviser subagent has tools `[Read, Write, Edit, Bash]` and does
  not include `Agent` — it cannot spawn Explore or codegraph subagents
  (per spec 0011: speccraft does not own code-intel routing).
- If the spec-reviser violates the Q-DRIFT output contract by reshaping
  the prefix, the structural anchor `^Q-DRIFT:` in the e2e fixture will
  fail and the implementation will need to be corrected — the prefix is
  load-bearing per spec 0014's structural-over-content convention.
