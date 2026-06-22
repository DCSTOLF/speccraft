---
description: "Review the active product brief: pm-critic self-check, then cross-model review."
argument-hint: ""
allowed-tools: ["Read", "Write", "Edit", "Bash"]
---

Review the active product **brief**. Two stages: a cheap single-model
self-check, then the cross-model review.

**IMPORTANT**: Execute ALL steps below using your tools before responding. Do
not describe steps — carry them out.

Steps:

1. **Resolve the active brief.**
   ```bash
   REPO_ROOT="$("$CLAUDE_PLUGIN_ROOT/bin/speccraft-state" find-root)"
   ACTIVE="$("$CLAUDE_PLUGIN_ROOT/bin/speccraft-state" get active_product)"
   ```
   If empty, error: "No active product brief. Run /speccraft:pm:new first."
   `BRIEF="$REPO_ROOT/product/$ACTIVE/brief.md"`.

2. **Self-check (runs FIRST).** Invoke the `pm-critic` subagent on `$BRIEF`.
   If it returns `needs-work`, surface the checklist failures and stop —
   fix the brief, then re-run. The pm-critic is a single-model self-check,
   not a review quorum.

3. **Cross-model review.** Only after pm-critic is satisfied, invoke the
   `cross-reviewer` subagent (the same multi-model backend `/speccraft:spec:review`
   uses, unchanged) over the enabled agents in `.speccraft/agents.toml`.

4. **Write** `product/$ACTIVE/review.md` with the synthesized verdict.

5. Suggest next step: `/speccraft:pm:prioritize` or `/speccraft:pm:close`.
