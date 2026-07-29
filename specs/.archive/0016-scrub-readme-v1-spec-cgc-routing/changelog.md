---
spec: "0016"
closed: 2026-06-11
---

# Changelog — 0016 Scrub README + v1-spec CodeGraphContext routing prose

## What shipped vs spec

Shipped as specified. Doc-only spec, no deviations. Four tasks
landed in a single commit (`14aea82`); T5 is the close gate this
changelog records.

Three coupled artefacts landed:

1. **`README.md` scrub** (T2). Three edit sites at lines 355, 365,
   383 removed the five prescriptive strings AC1 pins:
   - Line 355 — removed `use its tools to check architectural
     invariants`; rewrote to factual cross-reference ("...tools
     that handle it (such as CodeGraphContext)").
   - Line 365 — removed `It's the recommended way to answer`
     (exact match for the conventions.md banned phrasing pattern);
     replaced with "It can answer questions like:".
   - Line 383 — removed both `` prefer it over `grep`/`find` for
     structural questions `` and `the speccraft skill will note
     its presence`; replaced with factual install description
     ("...its tools are available alongside speccraft's").
   - Defensive paraphrase pin (#5, `prefer CodeGraphContext for
     structural queries`) never present in `main`; rewrite did
     not reintroduce it. Forward-protection against future
     rewrites reintroducing a near-variant.
   - `Recommended companions` section header, feature-comparison
     table (lines 380–381), and `enforce: cgc rule="..."`
     future-directive text retained as neutral examples per AC1.

2. **`speccraft-v1-spec.md` scrub** (T3). Five edit sites at lines
   33, 697, 1132, 1369, 1792 removed the five prescriptive strings
   AC2 pins:
   - Line 33 — removed `the recommended integration with
     CodeGraphContext`; replaced with example-framed mention
     ("(such as CodeGraphContext) — see [§20.1] for an
     integration sketch").
   - Line 697 — removed `suggest installing CodeGraphContext as
     an MCP server alongside speccraft`; replaced with
     category-level "suggest installing a code-intelligence MCP
     server such as those listed in README §"Recommended
     companions"". **Line 698 cross-ref preserved** via surgical
     rewrite, not full-paragraph removal (plan §Risk mitigation).
   - Line 1132 — removed `prefer its tools for structural
     queries`; replaced with factual capability description.
   - Line 1369 — removed `should install it as an MCP server
     alongside speccraft`; replaced with "It answers questions
     like ...". **`**Recommended companion:**` bolded label INTACT**
     at start of line — it is the surviving anchor for AC2
     presence check #12.
   - Line 1792 — removed `users who need these capabilities
     should install`; replaced with "these capabilities are
     available via external MCP servers such as
     [CodeGraphContext]...". v1.x roadmap bullets at 1793/1794
     untouched.

3. **New `verify.sh` oracle** (T1, 108 lines). Twelve labelled
   `grep -F` checks (5 README absence + 1 README presence + 5
   v1-spec absence + 1 v1-spec presence). Every grep file-scoped
   to `README.md` or `speccraft-v1-spec.md` by name per AC3 —
   repo-wide `grep -r` forbidden because absence-target strings
   appear inside this spec's own `spec.md`. Per codex round-2
   note, presence checks are labelled as explicitly as absence
   checks so failure messages distinguish over-deletion from
   missed scrub. `fails` counter accumulates; non-zero exit on
   any failure. Defensive paraphrase pin (#5) trivially green in
   this cycle — forward-protection, not RED→GREEN signal.

T4 was a readability + semantic-drift refactor pass — re-read
the eight rewritten paragraphs end-to-end as prose, confirmed no
dangling sentence fragments and no semantic drift. All 12
`verify.sh` checks remained green.

## Deviations

None. Spec was followed cleanly. Two round-2 review concerns
fixed pre-commit (not deviations, both flagged before flipping
spec to `reviewed`):

- **§20.1 misattribution.** claude-p round-2 flagged that the
  `What` section originally cited §20.1 as the location of the
  `**Recommended companion:**` bolded label. The label actually
  lives at §13 line 1369. spec.md `What` section corrected
  pre-`reviewed` flip; the presence grep was unaffected
  (substring match works either way).
- **README:544 disclosure.** `Install [CodeGraphContext](...)
  as an MCP server and Claude Code will pick up its tools
  automatically` is borderline-prescriptive but intentionally
  left in place under the AC1 narrowing (the five pinned strings
  are the complete README scrub target). Explicitly disclosed in
  `spec.md` §Out-of-scope before flipping to `reviewed` —
  future-reader signal, not a missed scrub. If a follow-up
  decides to tighten this, it gets a new spec.

## AC close-gate evidence

- **AC1 (README scrub).** `verify.sh` checks #1–#5 (absence) +
  #6 (presence) all green.
- **AC2 (v1-spec scrub).** `verify.sh` checks #7–#11 (absence) +
  #12 (presence) all green.
- **AC3 (verify.sh shape and scope).** Script carries
  `#!/usr/bin/env bash` + `set -euo pipefail`, resolves repo
  root from `${BASH_SOURCE[0]}`, file-scoped greps, labelled
  checks, `fails` counter, non-zero exit on failure. All 12
  checks pass: `PASS: all 12 checks ok`.
- **AC4 (closed-spec immutability).**
  `git diff cf0d094..HEAD -- specs/0001-speccraft-v1/spec.md`
  returns empty — closed spec byte-identical pre/post.

CI close gate: CI run 27347943883 queued at close time on
commit `14aea82`. **Doc-only specs do not wire `verify.sh` into
CI per the spec-0011 "Grep-assertion oracle" convention**
("the changes are one-shot and the grep cost is low enough for
reviewer inspection"). The effective close gate per convention
is `verify.sh` exiting 0 locally plus manual reviewer
inspection of the diff — both satisfied. CI green is not a
gating condition for this spec.

## Files touched

- `README.md` (3 edit sites at lines 355, 365, 383)
- `speccraft-v1-spec.md` (5 edit sites at lines 33, 697, 1132,
  1369, 1792)
- `specs/0016-scrub-readme-v1-spec-cgc-routing/verify.sh` (new,
  108 lines, executable)
- `.speccraft/index.md` (active_spec bump)
- `specs/0016-scrub-readme-v1-spec-cgc-routing/` (spec, plan,
  tasks, review, this changelog)

## Out-of-scope follow-ups still queued

- Spec 0001's CodeGraphContext mention is closed-spec immutable
  and accepted as historical record per spec 0011's history.md
  entry. **No follow-up will be filed.**
- README:544 (`Install [CodeGraphContext](...) as an MCP
  server and Claude Code will pick up its tools automatically`)
  is borderline-prescriptive but disclosed in this spec's
  §Out-of-scope as intentionally left in place under the AC1
  narrowing. If a future reviewer decides to tighten, that
  decision gets its own spec — not assumed here.

Spec 0011's "README + `speccraft-v1-spec.md` CodeGraphContext
copy cleanup" follow-up is **resolved** by this spec.
