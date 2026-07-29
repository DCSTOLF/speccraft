---
spec: "0011"
closed: 2026-06-09
---

# Changelog — 0011 Defer code-intel routing to user globals

## What shipped vs spec

- `skills/speccraft-context/SKILL.md` — the "Codebase-wide structural
  queries" section was replaced with neutral deferral wording. The
  CodeGraphContext-specific bullets are gone; the section retains the
  acknowledgment that structural queries are a real need and explicitly
  defers routing to whatever code-intel tool the user has installed
  (typically via global CLAUDE.md or an MCP server's own instructions).
- `commands/init.md` — the conditional install-suggestion at the tail of
  step 12 was reworded so CodeGraphContext is framed as one example
  ("such as CodeGraphContext") of a code-intel MCP server. The
  call-graph / symbol-search trigger phrase is preserved; the suggestion
  still fires only when the user mentions those needs. The README
  "Recommended companions" pointer was dropped from this line, since
  README copy is queued for a separate cleanup pass.
- `templates/speccraft/architecture.md` — the parenthetical now reads
  `(Advisory in v1.)`. The "enforced via CodeGraphContext if configured"
  clause is gone. The layering rule stands as advisory; enforcement is
  the host repo's choice.

All three acceptance criteria pass under `specs/0011-code-intel/verify.sh`
(exit 0). No deviations from the spec body or plan.

## Files touched

- skills/speccraft-context/SKILL.md
- commands/init.md
- templates/speccraft/architecture.md
- specs/0011-code-intel/verify.sh (new — grep-assertion oracle)

## Out-of-scope follow-ups

- **README.md cleanup.** Cross-reference scan during T5 confirmed the
  README retains roughly ten CodeGraphContext references, some of which
  are now factually stale after this spec (e.g. claims that the
  speccraft skill prefers cgc over grep for structural questions).
  README was explicitly out of scope per §Out of scope (human-facing
  prose, not model-loaded routing — documentation drift, not behavioral
  drift). A separate README-cleanup pass should update the copy.
- **speccraft-v1-spec.md residual references.** The top-level overview
  spec at the repo root names CodeGraphContext in several places; it
  also is not under the three target package paths. Deserves the same
  cleanup pass as README.
- **`specs/0001-speccraft-v1/spec.md`.** Also names CodeGraphContext as
  the integration story for code intelligence. Spec 0001 is closed and
  therefore immutable per the spec-immutability rule; the residual
  reference is acknowledged here rather than fixed.
- **Adding `/speccraft:spec:revise`.** Surfaced in the same conversation
  that produced 0011 — `/speccraft:spec:new` does not have a
  "re-analyze existing draft" path. Architecturally orthogonal to this
  spec; deserves its own.

## Related-but-separate

- **Spec 0012 (null `active_spec` serialization bug).** During the same
  2026-06-09 session, the e2e-devcontainer CI job failed because
  `speccraft-state set active_spec null` writes the literal string
  `"null"` to `state.json` instead of clearing the field, and the
  `/speccraft:spec:close` instruction in `commands/spec/close.md`
  relies on that call. The same bug surfaced live in this session when
  spec 0010 closed in parallel. Orthogonal to 0011's documentation-only
  scope; tracked as its own spec. CI for `main` stays red until 0012
  lands.

## Cross-model review

Both aux agents (codex, claude-p) returned `approve-with-comments` with
no guardrail or convention violations. The must-fixes they surfaced
(AC1 testability gap, AC2 "at most one" → "exactly one", README
disposition, planner doc-only signal, SKILL.md positive content
assertion) were folded into the spec before plan ran. See
`specs/0011-code-intel/review.md`.
