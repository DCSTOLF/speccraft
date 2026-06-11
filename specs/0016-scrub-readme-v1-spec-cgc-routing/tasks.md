---
id: "0016"
spec: "0016"
---

# Tasks

- [x] **T1 — Author `verify.sh` grep-assertion oracle (RED)**
  - [x] T1.1 — Create `specs/0016-scrub-readme-v1-spec-cgc-routing/verify.sh`
        with `#!/usr/bin/env bash` + `set -euo pipefail`.
  - [x] T1.2 — Resolve repo root from `${BASH_SOURCE[0]}` and `cd` there.
  - [x] T1.3 — Write the 5 README absence checks (labelled, `grep -F`,
        file-scoped to `README.md`):
    - [x] #1 `` prefer it over `grep`/`find` for structural questions ``
          (single-quote the literal backticks)
    - [x] #2 `the speccraft skill will note its presence`
    - [x] #3 `It's the recommended way to answer`
    - [x] #4 `use its tools to check architectural invariants`
    - [x] #5 `prefer CodeGraphContext for structural queries` (defensive pin)
  - [x] T1.4 — Write the 1 README presence check (labelled,
        `grep -F`, file-scoped):
    - [x] #6 `Recommended companions`
  - [x] T1.5 — Write the 5 v1-spec absence checks (labelled, `grep -F`,
        file-scoped to `speccraft-v1-spec.md`):
    - [x] #7 `prefer its tools for structural queries`
    - [x] #8 `suggest installing CodeGraphContext as an MCP server alongside speccraft`
    - [x] #9 `should install it as an MCP server alongside speccraft`
    - [x] #10 `users who need these capabilities should install`
    - [x] #11 `the recommended integration with CodeGraphContext`
  - [x] T1.6 — Write the 1 v1-spec presence check (labelled, `grep -F`,
        file-scoped):
    - [x] #12 `Recommended companion`
  - [x] T1.7 — Accumulate failures in a `fails` counter; exit non-zero on any
        failure.
  - [x] T1.8 — Confirm presence labels are as explicit as absence labels
        (per `review.md` codex round-2 note) so failures distinguish
        over-deletion from missed scrub.
  - [x] T1.9 — `chmod +x verify.sh`.
  - [x] T1.10 — Run `verify.sh` against current `main`; confirmed non-zero
        exit, 9 absence checks fail (4 README + 5 v1-spec), defensive pin #5
        and both presence anchors pass. **RED state achieved.**

- [x] **T2 — Scrub `README.md` (GREEN, partial)**
  - [x] T2.1 — Edited line 355: removed `use its tools to check architectural
        invariants`; rewrote to factual cross-reference ("...tools that handle
        it (such as CodeGraphContext)").
  - [x] T2.2 — Edited line 365: removed `It's the recommended way to answer`;
        replaced with "It can answer questions like:".
  - [x] T2.3 — Edited line 383: removed both `` prefer it over `grep`/`find`
        for structural questions `` AND `the speccraft skill will note its
        presence`; replaced with factual install description ("...its tools
        are available alongside speccraft's").
  - [x] T2.4 — Confirmed `Recommended companions` section header,
        feature-comparison table (lines 380–381), and `enforce: cgc rule="..."`
        future-directive text untouched.
  - [x] T2.5 — Confirmed rewrite did NOT reintroduce `prefer CodeGraphContext
        for structural queries`.
  - [x] T2.6 — Re-ran `verify.sh`: README absence checks 1–5 pass, presence
        check 6 passes, v1-spec checks 7–12 still fail (as expected).

- [x] **T3 — Scrub `speccraft-v1-spec.md` (GREEN, full)**
  - [x] T3.1 — Edited line 33: removed `the recommended integration with
        CodeGraphContext`; replaced with "(such as CodeGraphContext) — see
        [§20.1] for an integration sketch".
  - [x] T3.2 — Edited line 697: removed `suggest installing CodeGraphContext as
        an MCP server alongside speccraft`; replaced with category-level
        "suggest installing a code-intelligence MCP server such as those
        listed in README §"Recommended companions"". **Line 698 cross-ref
        preserved** — surgical rewrite, not full-paragraph removal.
  - [x] T3.3 — Edited line 1132: removed `prefer its tools for structural
        queries`; replaced with factual "its tools are available for
        structural queries — typically pre-indexed and cheaper than
        re-scanning the source".
  - [x] T3.4 — Edited line 1369: removed `should install it as an MCP server
        alongside speccraft`; replaced with "It answers questions like ...".
        **`**Recommended companion:**` bolded label INTACT** at start of line.
  - [x] T3.5 — Edited line 1792: removed `users who need these capabilities
        should install`; replaced with "these capabilities are available via
        external MCP servers such as [CodeGraphContext]...". v1.x roadmap
        bullets at 1793/1794 untouched.
  - [x] T3.6 — Re-ran `verify.sh`: **all 12 checks pass; exit 0. Full GREEN.**

- [x] **T4 — Refactor: readability + semantic-drift review**
  - [x] T4.1 — Re-read rewritten paragraphs in `README.md` (lines 355, 365,
        383) end-to-end. No dangling fragments; descriptive content
        preserved (MCP-server capability, install instructions, factual
        roadmap mention).
  - [x] T4.2 — Re-read rewritten paragraphs in `speccraft-v1-spec.md` (lines
        33, 697, 1132, 1369, 1792) end-to-end. §13 bolded label
        `**Recommended companion: [CodeGraphContext]**` confirmed intact at
        line 1369.
  - [x] T4.3 — Re-ran `verify.sh`: still exits 0. No regression.

- [ ] **T5 — Close gate (commit, push, manual review, `/speccraft:spec:close`)**
  - [ ] T5.1 — Stage `verify.sh` (new, executable), `README.md`, and
        `speccraft-v1-spec.md`. Do NOT stage anything under
        `specs/0001-speccraft-v1/`.
  - [ ] T5.2 — Verify `git diff --cached -- specs/0001-speccraft-v1/spec.md`
        is empty (AC4 closed-immutable check).
  - [ ] T5.3 — Commit on a topic branch and push.
  - [ ] T5.4 — Confirm CI is green (no CI changes here; doc-only specs do
        not wire `verify.sh` into CI per convention).
  - [ ] T5.5 — Manual reviewer inspection of the diff (effective close gate
        for doc-only specs).
  - [ ] T5.6 — Run `/speccraft:spec:close`.
