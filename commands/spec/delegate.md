---
description: "Hand a discrete task to an aux agent and integrate the result"
argument-hint: "<agent> <task description>"
allowed-tools: ["Read", "Write", "Bash", "Task"]
---

Delegate "$2..." to aux agent "$1".

Steps:

1. Validate agent "$1" exists in `.speccraft/agents.toml`, **and that its mode
   can be delegated to at all**:
   ```bash
   source "$CLAUDE_PLUGIN_ROOT/commands/spec/review.lib.sh"
   review_require_delegatable_mode .speccraft/agents.toml "$1" || exit 1
   ```
   `codex-plugin` and `subagent` are **review-only** modes: the first reaches a
   companion that runs its own agent loop, and the second can only be started
   by the orchestrating session. Neither can be shelled out to with a task, so
   this gate runs BEFORE any context is composed — the helper prints the one
   refusal message, naming the four review commands where that agent does work.

2. Invoke the `aux-delegator` subagent with the task and a curated context
   slice:
   - Active spec.md content
   - Relevant `.speccraft/` files (guardrails, conventions, architecture)
   - The file paths the task touches, read directly

3. The aux agent returns a diff or a written response.
   - If a diff: present it for user approval before applying.
   - If a written response: integrate into the conversation.

4. If a diff was applied, run the project's test command
   (`speccraft-state test-command`) and report results.
