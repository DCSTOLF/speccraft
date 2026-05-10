---
description: "Close the active spec: write changelog, propose memory updates"
allowed-tools: ["Read", "Write", "Edit", "Bash"]
---

Close the active spec.

Steps:

1. Read `.speccraft/state.json` for `active_spec`. If none, error.
   Read spec.md, tasks.md.

2. Verify all tasks in tasks.md are `[x]`. If not, ask the user to:
   (a) confirm closure anyway, or (b) re-open and finish the remaining tasks.

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

5. Show all proposed changes for user approval. Apply each approved change.

6. Set spec status to `closed`:
   ```bash
   # Edit spec.md frontmatter status: closed
   speccraft-state set active_spec null
   ```

7. Update `.speccraft/index.md`:
   - "Active spec" section → "none"
   - "Recent decisions" section → last 3 entries from history.md
