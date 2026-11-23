---
description: "Review the active design: arch-critic self-check, then cross-model review."
argument-hint: ""
allowed-tools: ["Read", "Write", "Edit", "Bash", "Agent", "TaskStop", "Bash(shasum:*)", "Bash(sha256sum:*)"]
---

Review the active technical **design**. Two stages: a cheap single-model
self-check, then the cross-model review.

**IMPORTANT**: Execute ALL steps below using your tools before responding. Do
not describe steps — carry them out.

Steps:

1. **Resolve the active design.**
   ```bash
   REPO_ROOT="$(speccraft-state find-root)"
   ACTIVE="$(speccraft-state get active_design)"
   ```
   If empty, error: "No active design. Run /speccraft:arch:new first."
   `DESIGN="$REPO_ROOT/design/$ACTIVE/design.md"`.

2. **Self-check (runs FIRST).** Invoke the `arch-critic` subagent on `$DESIGN`.
   If it returns `needs-work`, surface the checklist failures and stop — fix the
   design, then re-run. The arch-critic is a single-model self-check, not a
   review quorum.

3. **Cross-model review.** Only after arch-critic is satisfied, run the shared
   `review-round` procedure (`skills/review-round/SKILL.md`) over the enabled
   agents in `.speccraft/agents.toml`, with `KIND=design`, `design.md` as the
   document under review and `templates/prompts/arch-review.md` as the
   template, then synthesize via the `cross-reviewer` subagent.

   Pass `--label "Design under review (frozen for this round)"` to the composer. The default heading says "Spec
   under review", which would tell the reviewer to check this document
   against acceptance criteria a design.md does not have.

   It is the same multi-model backend `/speccraft:spec:review` uses, and that
   backend now dispatches by the registry's `mode`: `cli` and `acp` through
   `aux-delegator`, `codex-plugin` through the Codex plugin's companion, and
   `subagent` from this orchestrating session via the Agent tool.

4. **Write** `design/$ACTIVE/review.md` with the synthesized verdict.

5. Suggest next step: `/speccraft:arch:decide`, then `/speccraft:arch:close`.
