---
name: aux-agents
description: "Reference card for each aux agent's strengths, invocation patterns, and known quirks. Used when deciding which agent to delegate to and how."
---

# aux-agents

Reference card for speccraft's supported auxiliary agents.

## codex

- **Strengths:** refactoring, code review, test-case enumeration, idiomatic Go
- **Mode:** CLI
- **Command:** `codex exec --full-auto`
- **Input:** stdin
- **Quirks:**
  - Requires `--full-auto` for non-interactive use (otherwise prompts for confirmation)
  - Works best with a focused, single-responsibility task
  - Output is typically a unified diff or written response

## opencode

- **Strengths:** analysis, planning, architectural reasoning, spec review
- **Mode:** CLI
- **Command:** `opencode run`
- **Input:** argv (last argument)
- **Quirks:**
  - Benefits from `--file <path>` for very long prompts
  - Returns structured analysis; less likely to produce diffs
  - Good for "is this design right?" questions

## claude-p

- **Strengths:** general-purpose; same model family as the main session
- **Mode:** CLI
- **Command:** `claude -p`
- **Input:** argv (last argument)
- **Quirks:**
  - Useful for tasks that need Claude-specific capabilities
  - Can see the full context passed via argv
  - Subject to the same rate limits as the main session

## codex-acp (opt-in)

- **Mode:** ACP via `acpx`
- **Requires:** `acpx` installed on PATH, `enabled = true` in agents.toml
- **Quirks:** uniform interface regardless of the underlying agent; useful for multi-agent workflows

## Choosing an agent

| Task | Best agent |
|---|---|
| Generate table-driven tests | codex |
| Review a spec for ambiguity | opencode or claude-p |
| Refactor for idiomaticity | codex |
| Architectural analysis | opencode |
| General coding task | claude-p |
| Parallel review (quorum) | codex + opencode |

## Invocation pattern

All invocations go through the `aux-delegator` subagent, which handles:
- Loading agents.toml
- Composing the prompt with context files
- Routing to CLI or ACP
- Capturing and returning output
