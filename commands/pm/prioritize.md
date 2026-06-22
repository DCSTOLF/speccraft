---
description: "Mark the active product brief as prioritized (draft → prioritized)."
argument-hint: ""
allowed-tools: ["Read", "Write", "Edit", "Bash"]
---

Move the active product brief from `draft` to `prioritized`. This is an
optional lifecycle step signalling the brief is queued for design/spec work.

**IMPORTANT**: Execute ALL steps below using your tools before responding. Do
not describe steps — carry them out.

The mechanism lives in `commands/pm/prioritize.lib.sh` (testable via
`tests/hooks/pm-prioritize.bats`); source it before use.

Steps:

1. **Bootstrap.**
   ```bash
   REPO_ROOT="$("$CLAUDE_PLUGIN_ROOT/bin/speccraft-state" find-root)"
   ACTIVE="$("$CLAUDE_PLUGIN_ROOT/bin/speccraft-state" get active_product)"
   source "$CLAUDE_PLUGIN_ROOT/commands/pm/prioritize.lib.sh"
   BRIEF="$REPO_ROOT/product/$ACTIVE/brief.md"
   ```
   If `ACTIVE` is empty, error: "No active product brief."

2. **Transition status.** `pm_set_status "$BRIEF" prioritized` — this gates the
   source status (only a `draft` brief may be prioritized) and rewrites the
   `status:` frontmatter field in place.

3. Confirm the new status and suggest `/speccraft:pm:close` when done.
