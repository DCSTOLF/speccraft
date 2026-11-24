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

## The two reviewer subagents

Not aux CLI agents — these run inside the orchestrating session via the Agent
tool. Their names are one word apart and their jobs are disjoint, so dispatch
the right one:

### reviewer

- **Dispatch as:** `speccraft:reviewer`
- **Reads:** ONE payload file — a spec, design, brief or frozen diff, composed
  for it, passed as a path.
- **Returns:** ONE verdict, written to `<round-dir>/<agent>.out`. The round
  reads that artifact from disk; the agent's reply is only a confirmation.
- **Tools:** `Read, Grep, Glob, Bash(shasum:*), Bash(sha256sum:*), Write` —
  no `Edit`, and no bare `Bash`. That list is its only confinement, since it
  shares the session rather than running in a sandbox of its own.
- **Used by:** a registry entry whose `mode` is `subagent`. This is the one
  reviewer that needs no external CLI installed.

### cross-reviewer

- **Dispatch as:** `speccraft:cross-reviewer`
- **Reads:** the set of verdicts every reviewer returned — never the document
  under review.
- **Returns:** the **synthesized** `review.md` and an action recommendation.
- **Used by:** every review round, once, after the responses are collected.

Dispatching either where the other is meant yields a confident, wrong round: a
synthesizer handed one payload has nothing to cross-check and reports a quorum
of one, and a reviewer handed N responses reviews the responses instead of the
spec. Both agent files state the contrast in their opening lines.

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
