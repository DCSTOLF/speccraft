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

"Where is X called?", "what does file Y export?", "which tests cover this code?" —
structural queries are a real need, but speccraft does not own how to answer them.
Speccraft defers to whatever code-intelligence tool the user has installed. Routing
(which tool to call, when to inline a query vs. quarantine it in a subagent, when
to fall back to grep) is owned by that tool's own configuration — typically
registered in the user's global CLAUDE.md or in the MCP server's own instructions.
Do not duplicate or override those rules here.

speccraft itself only knows about session edits (via `state.json`) and the literal
contents of `.speccraft/`.

## When NOT to use this skill

- The repo has no `.speccraft/` directory. The skill auto-detects and silently no-ops.
- The user is asking a generic question unrelated to the repo's code.

## Updating memory

Do not silently rewrite `.speccraft/` files. All updates go through `/spec:close` or
`/speccraft:sync` so the user reviews them.
