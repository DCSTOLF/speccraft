---
description: "Hand a discrete task to an aux agent and integrate the result"
argument-hint: "<agent> <task description>"
allowed-tools: ["Read", "Write", "Bash", "Task"]
---

Delegate "$2..." to aux agent "$1".

Steps:

1. Validate agent "$1" exists in `.speccraft/agents.toml`.

2. Invoke the `aux-delegator` subagent with the task and a curated context
   slice:
   - Active spec.md content
   - Relevant `.speccraft/` files (guardrails, conventions, architecture)
   - The file paths the task touches, read directly

3. The aux agent returns a diff or a written response.
   - If a diff: present it for user approval before applying.
   - If a written response: integrate into the conversation.

4. If a diff was applied, run `go test ./...` and report results.
