---
description: "Cross-model review of the active spec via aux agents"
argument-hint: "[--quorum N] [--agents codex,opencode]"
allowed-tools: ["Read", "Write", "Bash"]
---

Run cross-model review on the active spec.

**IMPORTANT**: Execute ALL steps below using your tools before responding. Do
not describe steps — carry them out.

Steps:

1. Read `.speccraft/state.json` for `active_spec`. If none, error:
   "No active spec. Run /spec:new first."

2. Read `.speccraft/agents.toml`. Determine which agents to invoke:
   - If `--agents` flag provided, use that list (validate each exists).
   - Else, all agents with `enabled != false`.

3. For each selected agent, invoke the `aux-delegator` subagent with payload:
   - The spec.md content
   - The relevant slice of `.speccraft/` (index.md + guardrails.md +
     architecture.md + conventions.md)
   - The review prompt template from
     `$CLAUDE_PLUGIN_ROOT/templates/prompts/review.md`

   Run agents in parallel. Per-agent timeout from
   `agents.toml.defaults.review_timeout_s` (default 600s).

4. Collect verdicts. Each agent returns:
   verdict (approve | approve-with-comments | changes-requested | reject),
   concerns[], suggestions[], guardrail_violations[], convention_violations[].

5. Invoke the `cross-reviewer` subagent to synthesize the responses into a
   coherent `review.md` and an action recommendation.

6. Write `specs/<active>/review.md`.

7. Determine quorum (default 1 approve or approve-with-comments):
   - If met: update spec status to `reviewed`.
   - If not met: leave at `draft` and surface the synthesis with next steps.

8. Suggest next step:
   - If reviewed: `/spec:plan`
   - If changes-requested: edit spec.md, then re-run `/spec:review`
