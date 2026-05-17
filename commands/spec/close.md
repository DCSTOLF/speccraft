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

7. Update `.speccraft/index.md`:
   - "Active spec" section → "none"
   - "Recent decisions" section → last 3 entries from history.md
