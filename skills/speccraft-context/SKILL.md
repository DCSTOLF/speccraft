---
name: speccraft-context
description: "Always-on: loads .speccraft/index.md and pulls deeper memory files (guardrails, architecture, conventions, history) when the user's task requires them. Trigger whenever the conversation involves code changes, architecture decisions, or anything project-specific in a repo that has a .speccraft/ directory."
---

# speccraft-context

You are working in a repository that uses speccraft. The session-start hook
has already injected `.speccraft/index.md` into context. This skill teaches
you when and how to pull deeper files.

## When to read each file

- `.speccraft/guardrails.md` — before writing code; before any tool call that
  could violate a hard rule. Read once per session, early.
- `.speccraft/conventions.md` — before writing code in a new package; before
  /spec:plan; before reviewing code.
- `.speccraft/architecture.md` — when the change crosses package boundaries;
  when discussing layering, dependencies, or new modules.
- `.speccraft/history.md` — when about to make a decision that resembles a
  prior one; when investigating "why is this like this".

## Codebase-wide structural queries

For "where is X called?", "what does file Y export?", or "which tests cover this code?" —
speccraft does NOT carry a built-in code graph in v1. Use whatever the user has configured:

- If [CodeGraphContext](https://github.com/CodeGraphContext/CodeGraphContext) is connected
  as an MCP server, prefer its tools for structural queries — they're pre-indexed and far
  cheaper than re-scanning the source.
- Otherwise, fall back to `rg` / `grep` for symbol search and `git grep` for diff-aware
  queries. Acknowledge the cost: structural questions on a large repo may want a
  CodeGraphContext install.

speccraft itself only knows about session edits (via `state.json`) and the literal
contents of `.speccraft/`.

## When NOT to use this skill

- The repo has no `.speccraft/` directory. The skill auto-detects and silently no-ops.
- The user is asking a generic question unrelated to the repo's code.

## Updating memory

Do not silently rewrite `.speccraft/` files. All updates go through `/spec:close` or
`/speccraft:sync` so the user reviews them.
