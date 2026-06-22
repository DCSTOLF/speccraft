---
description: "Start a new technical design: allocate id, scaffold design.md, set the Architect lane."
argument-hint: "<title>"
allowed-tools: ["Read", "Write", "Edit", "Bash"]
---

Start a new technical **design** upstream of a spec. Architect is a standalone,
advisory workflow — it never blocks specs.

**IMPORTANT**: Execute ALL steps below using your tools before responding. Do
not describe steps — carry them out.

The mechanism lives in `commands/arch/new.lib.sh` (testable via
`tests/hooks/arch-new-preflight.bats`); source it before use.

Steps:

1. **Bootstrap.**
   ```bash
   REPO_ROOT="$("$CLAUDE_PLUGIN_ROOT/bin/speccraft-state" find-root)"
   source "$CLAUDE_PLUGIN_ROOT/commands/arch/new.lib.sh"
   ```

2. **Allocate id + slug.**
   ```bash
   ID="$(arch_next_id "$REPO_ROOT/design")"
   SLUG="$(printf '%s' "$ARGUMENTS" | tr '[:upper:]' '[:lower:]' \
     | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')"
   DESIGN="$REPO_ROOT/design/$ID-$SLUG/design.md"
   ```

3. **Scaffold.** `arch_scaffold_design "$DESIGN" "$ID" "$ARGUMENTS"`.

4. **Fill in the content** using one of two paths:
   - **Pre-provided answers** (`feasibility='...'`, `components='...'`,
     `data='...'`, `nfrs='...'`): edit `$DESIGN` directly, do NOT invoke
     arch-author.
   - **Interactive** (default): invoke the `arch-author` subagent to interview
     the user and fill in Feasibility / Components / Data model / NFRs &
     trade-offs / Open-questions.

5. **Set the Architect lane** (independent of `active_spec` / `active_product`):
   ```bash
   "$CLAUDE_PLUGIN_ROOT/bin/speccraft-state" set active_design "$ID-$SLUG"
   ```

6. Respond with the design id, title, and suggested next step
   (`/speccraft:arch:review`, then `/speccraft:arch:decide` and
   `/speccraft:arch:close`).
