---
description: "Cross-model review of the current diff against the active spec"
argument-hint: "[--base <ref>]"
allowed-tools: ["Read", "Bash"]
---

Cross-model review of uncommitted changes (or `git diff <base>`).

Steps:

1. Compute the diff:
   - Default: `git diff HEAD` (working tree + staged).
   - With `--base <ref>`: `git diff <ref>...HEAD`.

2. For each enabled agent in `.speccraft/agents.toml`, invoke `aux-delegator`
   with:
   - The diff
   - The active spec.md (if any)
   - Relevant `.speccraft/` files (conventions.md, guardrails.md)
   - The code-review prompt from
     `$CLAUDE_PLUGIN_ROOT/templates/prompts/review.md`

3. Synthesize via the `cross-reviewer` subagent. Output to stdout (do not
   write to spec dir — this is per-iteration, not per-spec).

4. If any agent flags a `guardrail_violation` or `convention_violation`,
   surface it prominently. The user decides whether to fix or override.
