---
id: "0011"
title: "Defer code-intel routing to user globals"
status: closed
created: 2026-06-09
authors: [claude]
packages: ["skills/speccraft-context", "commands", "templates/speccraft"]
related-specs: []
---

# Spec 0011 — Defer code-intel routing to user globals

## Why

Speccraft currently maintains its own guidance on how to use external
code-intelligence tools (specifically CodeGraphContext / `cgc`). The most
prescriptive instance is `skills/speccraft-context/SKILL.md:26-33`, which
tells the main session to "prefer codegraph MCP tools for structural
queries" — undifferentiated, no distinction between heavy tools that
flood context (`codegraph_explore`, `codegraph_context`) and lightweight
tools that are safe inline (`codegraph_search`, `codegraph_callers`,
etc.).

Since that skill was written, `cgc`'s own installer (`codegraphcontext mcp
setup`) writes routing rules into the user's global CLAUDE.md, including
the heavy/lightweight distinction and the rule that broad exploration
must be quarantined inside an Explore subagent. This creates duplicate
authority: speccraft and cgc both telling the model how to use cgc's
tools, with speccraft's copy stale and less correct.

The failure surfaced in a real `/speccraft:spec:new` session on
2026-06-09. The user observed the model citing "your global instructions"
to choose Explore over direct codegraph calls, while speccraft's skill
was simultaneously saying "prefer codegraph tools." The model correctly
resolved the conflict in favor of the more specific global rule, but the
conflict itself was wasted attention and risks silent drift as cgc's
rules evolve.

Speccraft does not own codegraph routing and does not spawn Explore
subagents itself — verified by repo-wide grep: zero references to
"Explore" across `commands/`, `agents/`, `hooks/`, `skills/`, `tools/`,
`templates/`. Speccraft's six subagents are all domain-specific
(spec-author, spec-critic, tdd-planner, cross-reviewer, aux-delegator,
memory-keeper). Therefore speccraft should defer all code-intel routing
decisions to whatever tool the user has installed, rather than
maintaining a competing copy.

Two secondary violations of the same principle exist and should be fixed
in the same change for coherence:

- `commands/init.md:111-113` names CodeGraphContext specifically in the
  install-suggestion text. The detect-and-suggest pattern itself is fine
  (validated by user as a legitimate touch-point), but naming one tool
  by brand bakes in the same drift risk.
- `templates/speccraft/architecture.md:11` references "enforced via
  CodeGraphContext if configured" in a template that is copied verbatim
  into every user repo. This also violates the existing hard rule that
  templates under `templates/speccraft/` must stay stack-agnostic (see
  `guardrails.md`).

## What

Remove tool-specific code-intel routing from speccraft. Replace with
language that defers to whatever guidance the user's installed code-intel
tool has registered in their environment (typically via global CLAUDE.md
or an MCP server's own instructions).

Three concrete changes:

1. `skills/speccraft-context/SKILL.md` — replace the "Codebase-wide
   structural queries" block (currently lines 24-36) with a short
   acknowledgment that structural queries are a real need and that
   speccraft defers to whatever code-intel tool the user has installed.
   Do not enumerate tools.

2. `commands/init.md` — keep the conditional install-suggestion behavior
   (it's a legitimate value-add), but rephrase to be tool-agnostic. E.g.,
   "suggest installing a code-intelligence MCP server (such as
   CodeGraphContext) if the user mentions call-graph or symbol-search
   needs." Naming one example is fine; making it the only option is not.

3. `templates/speccraft/architecture.md` — remove the "enforced via
   CodeGraphContext if configured" parenthetical. The layering rule
   stands on its own as advisory. Enforcement is the host repo's choice.

**Note for the planner:** all three changes are documentation/template
edits. There is no Go code, no hook, no runner, and no e2e fixture to
write. The RED→GREEN cycle is grep-based: assertion scripts that fail
against the current files and pass after the edits. Do not reach for
`tests/e2e/` scaffolding.

**Example-vs-recommendation distinction.** Change 2 retains a single
mention of CodeGraphContext in `commands/init.md`, but only as one
example of a code-intel MCP server, not as speccraft's recommended
tool. The surviving phrasing must read like "such as CodeGraphContext"
or equivalent — examples are allowed; brand endorsements are not.

## Acceptance criteria

1. After the change, `skills/speccraft-context/SKILL.md` contains no
   references to codegraph- or cgc-specific routing. Verifiable by two
   mechanical checks, both of which must hold:
   - `grep -in 'codegraph\|cgc' skills/speccraft-context/SKILL.md`
     returns zero matches.
   - The "Codebase-wide structural queries" section (or its renamed
     replacement) still exists, is non-empty, and contains deferral
     language. Verifiable by `grep -in 'defer' skills/speccraft-context/SKILL.md`
     returning at least one match, and by inspection that the section
     retains an acknowledgment that structural queries are a real
     need (i.e., the fix is replacement, not deletion).

2. A full-repo grep — `grep -rni 'codegraph' commands/ agents/ hooks/
   skills/ tools/ templates/` — returns **exactly one** match, and
   that match is located in `commands/init.md`. Verifiable by two
   mechanical checks, both of which must hold:
   - The above grep returns exactly one line, in `commands/init.md`.
   - That line frames CodeGraphContext as one example of a code-intel
     MCP server, not as the recommended tool. Verifiable by `grep -i
     'such as' commands/init.md` returning a line that contains
     "CodeGraphContext" (or equivalent example-framing phrasing such
     as "for example," / "e.g.,").
   - The conditional install-suggestion behavior is preserved: the
     suggestion line still exists and still fires only when the user
     mentions call-graph or symbol-search needs.

3. Reading `templates/speccraft/architecture.md`, the layering section
   no longer names any specific enforcement tool. The parenthetical
   "(Advisory in v1; enforced via CodeGraphContext if configured.)"
   is gone or replaced with tool-neutral wording (e.g., "(Advisory in
   v1.)"). Verifiable by `grep -i 'codegraph' templates/` returning
   nothing.

## Out of scope

- Adding a "/speccraft:spec:revise" command or expanding `/speccraft:spec:new`
  to support "re-analyze existing draft" workflows. Surfaced in the same
  conversation but architecturally orthogonal — deserves its own spec.
- Verifying whether the Claude Code harness propagates `~/.claude.json`
  CLAUDE.md content into subagent prompts. Worth knowing, but doesn't
  affect this change: speccraft's own subagents are domain-specific
  and don't need codegraph routing, and the Explore-subagent path is
  owned entirely by the user's global rule plus the Claude Code harness.
- Any changes to the user's own global CLAUDE.md or to `cgc`'s installer.
  Speccraft has no say in either.
- Replacing the install-suggestion in `commands/init.md` with auto-detection
  of installed MCP servers. Possible future enhancement, not required here.
- `README.md` references to CodeGraphContext. The README is human-facing
  prose describing recommended companions, not model-loaded routing
  guidance. The same deferral principle applies in spirit, but stale
  README claims are documentation drift, not behavioral drift — they
  don't affect Claude's runtime behavior the way the SKILL.md routing
  did. A separate README-cleanup pass can update the copy without
  entangling it with this change.

## Open questions

_none_
