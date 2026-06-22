---
description: "Start a new product brief: allocate id, scaffold brief.md, set the PM lane."
argument-hint: "<title>"
allowed-tools: ["Read", "Write", "Edit", "Bash"]
---

Start a new **product brief** upstream of any spec. PM is a standalone,
advisory workflow — it never blocks specs.

**IMPORTANT**: Execute ALL steps below using your tools before responding. Do
not describe steps — carry them out.

The mechanism lives in `commands/pm/new.lib.sh` (testable via
`tests/hooks/pm-new-preflight.bats`); source it before use.

Steps:

1. **Bootstrap.**
   ```bash
   REPO_ROOT="$("$CLAUDE_PLUGIN_ROOT/bin/speccraft-state" find-root)"
   source "$CLAUDE_PLUGIN_ROOT/commands/pm/new.lib.sh"
   ```

2. **Allocate id + slug.**
   ```bash
   ID="$(pm_next_id "$REPO_ROOT/product")"
   SLUG="$(printf '%s' "$ARGUMENTS" | tr '[:upper:]' '[:lower:]' \
     | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')"
   BRIEF="$REPO_ROOT/product/$ID-$SLUG/brief.md"
   ```

3. **Scaffold.** `pm_scaffold_brief "$BRIEF" "$ID" "$ARGUMENTS"`.

4. **Fill in the content** using one of two paths:
   - **Pre-provided answers** (`why='...'`, `what='...'`, `metrics='...'`,
     `oos='...'`): edit `$BRIEF` directly, do NOT invoke pm-author.
   - **Interactive** (default): invoke the `pm-author` subagent to interview
     the user and fill in Why / What (incl. success metrics) / Out-of-scope /
     Open-questions.

5. **Set the PM lane** (independent of `active_spec` / `active_design`):
   ```bash
   "$CLAUDE_PLUGIN_ROOT/bin/speccraft-state" set active_product "$ID-$SLUG"
   ```

6. Respond with the brief id, title, and suggested next step
   (`/speccraft:pm:review`, then `/speccraft:pm:prioritize` or
   `/speccraft:pm:close`).
