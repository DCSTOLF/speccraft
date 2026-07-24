---
description: "Mark the active design as decided (draft → decided)."
argument-hint: ""
allowed-tools: ["Read", "Write", "Edit", "Bash"]
---

Move the active design from `draft` to `decided` — the design's direction is
settled and ready to record at close.

**IMPORTANT**: Execute ALL steps below using your tools before responding. Do
not describe steps — carry them out.

The mechanism lives in `commands/arch/decide.lib.sh` (testable via
`tests/hooks/arch-decide.bats`); source it before use.

Steps:

1. **Bootstrap.**
   ```bash
   PLUGIN_ROOT="$(speccraft-state plugin-root)"
   REPO_ROOT="$(speccraft-state find-root)"
   ACTIVE="$(speccraft-state get active_design)"
   source "$PLUGIN_ROOT/commands/arch/decide.lib.sh"
   DESIGN="$REPO_ROOT/design/$ACTIVE/design.md"
   ```
   If `ACTIVE` is empty, error: "No active design."

2. **Transition status.** `arch_set_status "$DESIGN" decided` — this gates the
   source status (only a `draft` design may be decided) and rewrites the
   `status:` frontmatter field in place.

3. Confirm the new status and suggest `/speccraft:arch:close` to record the
   decision into `.speccraft/architecture.md` + `history.md`.
