---
description: "Close the active design: route durable decisions through memory-keeper, then clear the Architect lane."
argument-hint: ""
allowed-tools: ["Read", "Write", "Edit", "Bash"]
---

Close the active **design**: record its durable decisions into project memory
via the existing `memory-keeper` (no new store), flip the design to `closed`,
and clear the Architect state lane. Closing the Architect lane never touches
`active_spec` or `active_product` (lane independence).

**IMPORTANT**: Execute ALL steps below using your tools before responding. Do
not describe steps — carry them out.

Steps:

1. **Resolve the active design.**
   ```bash
   REPO_ROOT="$("$CLAUDE_PLUGIN_ROOT/bin/speccraft-state" find-root)"
   ACTIVE="$("$CLAUDE_PLUGIN_ROOT/bin/speccraft-state" get active_design)"
   DESIGN="$REPO_ROOT/design/$ACTIVE/design.md"
   ```
   If `ACTIVE` is empty, error: "No active design."

2. **Propose memory updates via `memory-keeper`.** Invoke the `memory-keeper`
   subagent (the same backend `/speccraft:spec:close` uses, unchanged) with the
   design as input. It proposes:
   - a diff to `.speccraft/architecture.md`, and
   - a new dated ADR entry appended to `.speccraft/history.md`.
   **Do not apply yet** — present the proposed diff for confirmation. Until the
   user confirms, `architecture.md` and `history.md` must remain byte-unchanged.

3. **Apply only on confirmation.** If the user declines, write nothing. If they
   confirm, let `memory-keeper` apply the diff and append the ADR.

4. **Flip status to closed.** Edit `$DESIGN` frontmatter `status:` → `closed`.
   A closed design is immutable by convention — corrections go in a follow-up
   design.

5. **Clear ONLY the Architect lane:**
   ```bash
   "$CLAUDE_PLUGIN_ROOT/bin/speccraft-state" set active_design null
   ```

6. Confirm what was recorded (or that the user declined) and that the design
   remains an ideal `--from` source for a future
   `/speccraft:spec:new --from design/$ACTIVE`.
