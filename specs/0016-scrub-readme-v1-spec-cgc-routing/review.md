---
spec: "0016"
reviewers: [codex, claude-p]
quorum: 1
verdict: approve-with-comments
rounds: 2
generated: 2026-06-11T00:00:00Z
---

# Review — spec 0016 (scrub README + v1-spec CGC routing)

## Aggregate verdict: approve-with-comments

Quorum: MET (2 / 1 approve-with-comments received). Spec status flipped from `draft` to `reviewed`.

## Reviewers (round 2)
- codex (verdict: approve-with-comments)
- claude-p (verdict: approve-with-comments)

## Round 1 → Round 2 delta

Round 1 returned changes-requested from both reviewers. The author applied five edits between rounds:

1. **AC1 expanded** from 2 → 5 README absence pins. Added `It's the recommended way to answer` (README:365 — exact match for the conventions.md banned phrasing pattern, claude-p's headline finding), `use its tools to check architectural invariants` (README:355), and a defensive paraphrase pin `prefer CodeGraphContext for structural queries`.
2. **AC2 expanded** from 2 → 5 v1-spec absence pins. Added lines 33 (`the recommended integration with CodeGraphContext`), 1369 (`should install it as an MCP server alongside speccraft`), and 1792 (`users who need these capabilities should install`).
3. **AC2 presence-anchor added** — `Recommended companion` must still appear in `speccraft-v1-spec.md` after the scrub. Satisfies the Grep-assertion oracle convention's absence/presence pairing requirement for the second file.
4. **AC3 file-scoped greps** — explicitly states all `grep -F` invocations target `README.md` or `speccraft-v1-spec.md` by name. Forbids repo-wide `grep -r` because the absence-target strings appear inside this spec's own `spec.md` (would cause permanent false positives).
5. **Out-of-scope contradiction resolved** — the `What` section no longer broadens scope to "any other external code-intel tool"; Out-of-scope retains the opportunistic-bonus clause for non-CGC routing prose.

## Round-2 reviewer feedback (non-blocking)

### codex
Single implementation suggestion: when writing `verify.sh`, label paired presence checks as explicitly as the absence checks so a reviewer reading a failure can tell over-deletion from missed scrub. Fold into the plan phase.

### claude-p
Three concerns, none blocking:

1. **§20.1 misattribution in the `What` section** — the spec said the `Recommended companion` anchor lives at §20.1 ("Codebase-wide queries"), but the `**Recommended companion: [CodeGraphContext]**` bolded label actually lives at §13 "Codebase-wide queries (deferred)" at line 1369. The presence grep still works (matches somewhere), but the implementer-facing prose was wrong. **Fixed in spec.md before flipping to `reviewed`** — the `What` section now correctly cites §13 line 1369 as the location of the bolded label and §20.1 as the subsection structure being retained.
2. **Presence-anchor fragility** — `Recommended companion` (substring) matches both line 698 (inside the line-697 scrub block, will be removed) and line 1369 (the §13 bolded label, will be retained). After scrub, only line 1369 survives — exactly the intended behavior. The fragility note is acknowledged; tightening the anchor to a more specific string is optional defensive work, not required by the convention.
3. **README:544 disclosure** — `Install [CodeGraphContext](...) as an MCP server and Claude Code will pick up its tools automatically` is borderline-prescriptive but intentionally left in place under the AC1 narrowing. **Disclosed in Out-of-scope before flipping to `reviewed`** — future readers will see this was reviewed, not missed.

## Convention compliance

- **External-tool boundaries (spec 0011):** AC1 + AC2 collectively pin every prescriptive routing string identified during preflight on the two target surfaces. No new prescriptive prose introduced.
- **Grep-assertion oracle for doc-only specs (spec 0011):** AC3 mandates `#!/usr/bin/env bash` + `set -euo pipefail`, repo-root resolution from `${BASH_SOURCE[0]}`, labelled checks, `fails` counter, non-zero exit on failure, and file-scoped greps. Both target files have paired absence + presence checks.
- **Spec immutability:** AC4 explicitly protects `specs/0001-speccraft-v1/spec.md` and references the guardrails.md rule.

## Guardrail compliance

- Doc-only spec — no code, hooks, binaries, templates, or closed-spec edits.
- TDD invariant not bypassed.
- No secrets or API keys in scope.

## Recommended next step

`/speccraft:spec:plan` — turn the four ACs into a RED→GREEN→REFACTOR task list. Plan should fold in codex's labelling suggestion when authoring `verify.sh`.
