---
description: "Review the active design: arch-critic self-check, then cross-model review."
argument-hint: ""
allowed-tools: ["Read", "Write", "Edit", "Bash"]
---

Review the active technical **design**. Two stages: a cheap single-model
self-check, then the cross-model review.

**IMPORTANT**: Execute ALL steps below using your tools before responding. Do
not describe steps — carry them out.

Steps:

1. **Resolve the active design.**
   ```bash
   REPO_ROOT="$("$CLAUDE_PLUGIN_ROOT/bin/speccraft-state" find-root)"
   ACTIVE="$("$CLAUDE_PLUGIN_ROOT/bin/speccraft-state" get active_design)"
   ```
   If empty, error: "No active design. Run /speccraft:arch:new first."
   `DESIGN="$REPO_ROOT/design/$ACTIVE/design.md"`.

2. **Self-check (runs FIRST).** Invoke the `arch-critic` subagent on `$DESIGN`.
   If it returns `needs-work`, surface the checklist failures and stop — fix the
   design, then re-run. The arch-critic is a single-model self-check, not a
   review quorum.

3. **Cross-model review.** Only after arch-critic is satisfied, invoke the
   `cross-reviewer` subagent (the same multi-model backend
   `/speccraft:spec:review` uses, unchanged) over the enabled agents in
   `.speccraft/agents.toml`.

4. **Write** `design/$ACTIVE/review.md` with the synthesized verdict.

5. Suggest next step: `/speccraft:arch:decide`, then `/speccraft:arch:close`.
