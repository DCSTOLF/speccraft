---
description: "Cross-model review of the current diff against the active spec"
argument-hint: "[--base <ref>]"
allowed-tools: ["Read", "Bash", "Write", "Agent", "TaskStop", "Bash(shasum:*)", "Bash(sha256sum:*)"]
---

Cross-model review of uncommitted changes (or `git diff <base>`).

Steps:

1. Resolve the plugin root (for the prompt template path below), then compute
   the diff:
   ```bash
   PLUGIN_ROOT="$(speccraft-state plugin-root)"
   ```
   - Default: `git diff HEAD` (working tree + staged).
   - With `--base <ref>`: `git diff <ref>...HEAD`.

**Dispatch is mode-aware and shared.** The registry's `mode` selects how each
reviewer is reached: `cli` and `acp` go through `aux-delegator`,
`codex-plugin` drives the Codex plugin's companion, and `subagent` is
dispatched by **this orchestrating session** via the Agent tool — a shell
cannot start one. The full procedure (compose, budget-check, dispatch by
mode, record outcomes, attestation, the subagent timeout protocol) lives in
the shared `review-round` runbook at `skills/review-round/SKILL.md`. Follow it
rather than re-deriving a per-command variant.

2. For each enabled agent in `.speccraft/agents.toml`, invoke `aux-delegator`
   with:
   - The diff
   - The active spec.md (if any)
   - Relevant `.speccraft/` files (conventions.md, guardrails.md)
   - The code-review prompt from
     `$PLUGIN_ROOT/templates/prompts/review.md`

3. Synthesize via the `cross-reviewer` subagent. Output to stdout (do not
   write to spec dir — this is per-iteration, not per-spec).

4. If any agent flags a `guardrail_violation` or `convention_violation`,
   surface it prominently. The user decides whether to fix or override.
