---
description: "Reconcile .speccraft/ memory with reality. Detect drift."
allowed-tools: ["Read", "Write", "Edit", "Bash"]
---

Run a drift scan and a memory-keeper audit pass.

Steps:

1. Run `speccraft-drift scan-all` over `enforce:`-tagged conventions and
   guardrails. Report violations with file:line references.

2. Invoke the `memory-keeper` subagent in audit mode with:
   - The drift report from step 1
   - `git log --since=<last sync>` (or full log if first sync) for context
   - A sampled list of changed files since last sync

   Propose:
   - New conventions implied by repeated patterns visible in recent diffs
   - Architecture updates implied by new top-level packages
   - Stale entries in conventions.md / architecture.md

3. Present proposals for approval. Apply approved ones.
