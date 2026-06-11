---
id: "0016"
title: "Scrub README + v1-spec CodeGraphContext routing prose"
status: closed
created: 2026-06-11
authors: [claude]
packages: []
related-specs: ["0011"]
---

# Spec 0016 — Scrub README + v1-spec CodeGraphContext routing prose

## Why

Spec 0011 ("Defer code-intel routing to user globals", closed 2026-06-09)
established the principle now codified in
`templates/speccraft/conventions.md` §"External-tool boundaries": speccraft
does not duplicate routing authority for external tools it does not own.
Prescriptive prose telling speccraft to "prefer", "use", "should install",
or call a specific external tool "the recommended way" is not allowed;
neutral descriptions and examples (e.g. "Recommended companions", "such as
CodeGraphContext") are fine.

0011 scrubbed the three model-loaded surfaces it identified
(`skills/speccraft-context/SKILL.md`, `commands/init.md`,
`templates/speccraft/architecture.md`) but explicitly deferred two
human-facing prose surfaces:

- `README.md` (~10 CodeGraphContext references; the prescriptive ones
  this spec scrubs are at lines 355, 365, and 383 — including "It's the
  recommended way to answer" at line 365, which is the exact form of
  the banned phrasing pattern listed in `templates/speccraft/conventions.md`
  §"External-tool boundaries").
- `speccraft-v1-spec.md` at repo root (top-level overview spec —
  prescriptive routing prose at lines 33, 697, 1132–1133, 1369, and 1792).

The repo-root `speccraft-v1-spec.md` is a forward-looking overview
document, distinct from `specs/0001-speccraft-v1/spec.md` which is
closed-immutable and out of scope here.

The scrub closes the remaining gap from 0011 without touching code,
hooks, tests, or any closed spec.

## What

Doc-only edits to two files at repo root:

1. `README.md` — remove or rephrase every claim that prescribes
   routing FROM speccraft TO CodeGraphContext. The five specific
   strings this spec gates (see AC1) are the complete README scrub
   target; the feature-comparison table (lines 380–381), the
   "Recommended companions" section header, and the `enforce: cgc
   rule="..."` future-directive text are explicitly retained as
   neutral examples / future-speccraft-behavior descriptions.
2. `speccraft-v1-spec.md` — remove or rephrase every claim that
   prescribes routing FROM speccraft TO CodeGraphContext for queries
   or installation. The five specific strings this spec gates (see
   AC2) are the complete v1-spec scrub target; the §13 "Recommended
   companion: [CodeGraphContext]" bolded label (line 1369), the §20.1
   "Codebase-wide queries" subsection structure, and v1.x roadmap
   mentions of a possible future `enforce: cgc` bridge directive are
   explicitly retained (they describe prospective speccraft features
   and a named companion, not present-day routing authority).

A grep-assertion oracle (`verify.sh`) in the spec directory pins the
removed prescriptive phrases so the scrub is testable and reviewable
under the "Grep-assertion oracle for doc-only specs" convention.

## Acceptance criteria

1. **README.md scrub.** `verify.sh` confirms `README.md` does not
   contain any of the following five `grep -F` (fixed-string) absence
   targets:
   - ``prefer it over `grep`/`find` for structural questions`` (line 383)
   - `the speccraft skill will note its presence` (line 383)
   - `It's the recommended way to answer` (line 365 — exact match
     for the conventions.md banned phrasing pattern)
   - `use its tools to check architectural invariants` (line 355)
   - `prefer CodeGraphContext for structural queries` (defensive
     paraphrase pin — covers the case the rephrase reintroduces a
     near-variant)

   Paired presence anchor: `verify.sh` also confirms `README.md`
   still contains the fixed string `Recommended companions`
   (the section header that anchors the neutral companion endorsement
   the scrub is meant to preserve). Erasing the section to satisfy
   the absence checks fails this presence check.

2. **speccraft-v1-spec.md scrub.** `verify.sh` confirms
   `speccraft-v1-spec.md` does not contain any of the following five
   `grep -F` absence targets:
   - `prefer its tools for structural queries` (line 1132)
   - `suggest installing CodeGraphContext as an MCP server alongside speccraft`
     (line 697)
   - `should install it as an MCP server alongside speccraft` (line 1369)
   - `users who need these capabilities should install` (line 1792)
   - `the recommended integration with CodeGraphContext` (line 33)

   Paired presence anchor: `verify.sh` also confirms
   `speccraft-v1-spec.md` still contains the fixed string
   `Recommended companion` (the §20.1 section header that anchors
   the neutral companion mention the scrub is meant to preserve).
   Erasing the section fails this presence check.

3. **verify.sh shape and scope.**
   `specs/0016-scrub-readme-v1-spec-cgc-routing/verify.sh` exists, is
   marked executable, carries `#!/usr/bin/env bash` + `set -euo pipefail`,
   resolves the repo root from `${BASH_SOURCE[0]}`, and exits 0 when run
   from any CWD. Every `grep -F` invocation in the script is **file-scoped
   to `README.md` or `speccraft-v1-spec.md` by name** — repo-wide
   `grep -r` is forbidden because the absence-target strings literally
   appear inside this spec's own `spec.md` and would produce permanent
   false positives. Each AC1 + AC2 check is a labelled `grep` that
   accumulates a `fails` counter; the script exits non-zero on any
   failure. This is the oracle reviewers run and is the gating check
   at `/speccraft:spec:close`.

4. **Closed-spec immutability.** `specs/0001-speccraft-v1/spec.md`
   is byte-identical before and after this spec's implementation
   (closed-immutable rule from spec 0011's close, cross-referenced
   from `.speccraft/guardrails.md` §"Spec immutability"). `verify.sh`
   does not assert this — it's enforced by convention and PR diff
   review.

## Out of scope

- Any code, hook, Go-binary, or test-infrastructure change. This is
  a doc-only spec.
- `specs/0001-speccraft-v1/spec.md` — closed and immutable per the
  spec-immutability rule (cross-referenced in spec 0011's close).
- Re-litigating the "External-tool boundaries" principle from spec
  0011 — it is canonical in `templates/speccraft/conventions.md` and
  this spec only applies it to the two remaining doc surfaces.
- Routing prose about external tools other than CodeGraphContext
  (sourcegraph, LSP servers, tree-sitter, etc.). None were found in
  the target files during preflight; if any surface during the
  rewording pass, remove them under the same principle as an
  opportunistic bonus, but they are not gated by `verify.sh` and the
  spec does not require an exhaustive search-and-destroy beyond the
  two target files.
- Prescriptive prose about CodeGraphContext in files other than
  `README.md` and `speccraft-v1-spec.md`. Spec 0011 scrubbed the
  model-loaded surfaces; if a stale string survived in a third file,
  file a follow-up spec.
- README.md line 544 (`Install [CodeGraphContext](...) as an MCP
  server and Claude Code will pick up its tools automatically`) is a
  borderline-prescriptive phrasing reviewed during this spec's
  authoring and intentionally left in place under the AC1 narrowing
  (the five pinned strings are the complete README scrub target).
  Future-reader disclosure, not a missed scrub. If a follow-up
  decides to tighten this, file a new spec.
- Adding new sections, restructuring the documents, or revising
  unrelated prose. This is removal/rewording only.
- Updating `templates/speccraft/architecture.md` or any other
  template — those were handled by 0011.

## Open questions

_none_
