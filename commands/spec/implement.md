---
description: "Execute the active plan TDD-style; optionally delegate tasks"
argument-hint: "[--delegate <agent>:<task-id>,...]"
allowed-tools: ["Read", "Write", "Edit", "Bash", "Task"]
---

Execute the active plan.

Steps:

1. Read `.speccraft/state.json` for `active_spec`. Read spec.md, plan.md,
   tasks.md. Set spec status to `in-progress` (persist via `speccraft-state
   set active_spec <id>`).

2. For each unchecked task in tasks.md, in order:
   a. If task is in the `--delegate` list, route via `aux-delegator`.
      Otherwise, execute in the main session.
   b. Honor TDD discipline: before editing any production file, the
      corresponding test file must have been edited more recently in this
      session. The PreToolUse hook enforces this automatically.
   c. Run `go test ./...` after each step. RED steps expect failure;
      GREEN steps expect success.
   d. On step completion, mark the task `[x]` in tasks.md.

3. After last task, run full test suite. If green, suggest `/speccraft:spec:close`.

4. If a step fails or stalls (>3 failed retries), pause and surface the
   blockage explicitly. Do not silently continue past failures.
