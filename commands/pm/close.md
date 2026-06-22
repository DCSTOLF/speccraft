---
description: "Close the active product brief and clear the PM lane."
argument-hint: ""
allowed-tools: ["Read", "Write", "Edit", "Bash"]
---

Close the active product **brief**: flip its status to `closed` and clear the
PM state lane. Closing the PM lane never touches `active_spec` or
`active_design` (lane independence).

**IMPORTANT**: Execute ALL steps below using your tools before responding. Do
not describe steps — carry them out.

Steps:

1. **Resolve the active brief.**
   ```bash
   REPO_ROOT="$("$CLAUDE_PLUGIN_ROOT/bin/speccraft-state" find-root)"
   ACTIVE="$("$CLAUDE_PLUGIN_ROOT/bin/speccraft-state" get active_product)"
   BRIEF="$REPO_ROOT/product/$ACTIVE/brief.md"
   ```
   If `ACTIVE` is empty, error: "No active product brief."

2. **Flip status to closed.** Edit `$BRIEF` frontmatter `status:` → `closed`.
   A closed brief is immutable by convention — corrections go in a follow-up
   brief.

3. **Clear ONLY the PM lane:**
   ```bash
   "$CLAUDE_PLUGIN_ROOT/bin/speccraft-state" set active_product null
   ```

4. Confirm the brief is closed and note it remains the ideal `--from` source
   for a future `/speccraft:spec:new --from product/$ACTIVE`.
