---
id: "0016"
spec: "0016"
status: planned
strategy: tdd
---

# Plan — 0016 Scrub README + v1-spec CodeGraphContext routing prose

This is a **doc-only** spec. Per `.speccraft/conventions.md` §"Grep-assertion
oracle for doc-only specs" (introduced by spec 0011), the RED→GREEN cycle is
driven by a committed `verify.sh` grep-assertion script, not a behavioral
`_test.go`. Failing against current `main` is RED; edits to `README.md` and
`speccraft-v1-spec.md` that make every check pass are GREEN. There is no
behavioral test file to write. `spec.packages: []` is intentional.

## Test-first sequence

### Step 1 (T1) — Author `verify.sh` grep-assertion oracle (RED)

- Add `specs/0016-scrub-readme-v1-spec-cgc-routing/verify.sh`:
  - `#!/usr/bin/env bash` + `set -euo pipefail` per the general Bash convention.
  - Resolve repo root from `${BASH_SOURCE[0]}` and `cd` there so greps see
    consistent paths regardless of caller CWD.
  - Every `grep -F` invocation is **file-scoped by name** to `README.md` or
    `speccraft-v1-spec.md`. Repo-wide `grep -r` is forbidden: the absence-target
    strings literally appear inside this spec's own `spec.md`, which would
    produce permanent false positives (AC3).
  - A `fails` counter accumulates failures across labelled checks. Script
    exits non-zero on any failure.
  - **Twelve labelled checks total** (the complete list, per AC1 + AC2):

    **README absence (5)** — each labelled e.g.
    `[absence #N: README "<short id>"]`:
      1. `` prefer it over `grep`/`find` for structural questions `` (line 383;
         note the backticks inside the fixed-string argument — must be quoted
         so the shell does not interpret them as command substitution).
      2. `the speccraft skill will note its presence` (line 383).
      3. `It's the recommended way to answer` (line 365 — the exact conventions.md
         banned phrasing pattern).
      4. `use its tools to check architectural invariants` (line 355).
      5. `prefer CodeGraphContext for structural queries` (defensive paraphrase
         pin — covers a future rewrite reintroducing a near-variant).

    **README presence (1)** — labelled e.g.
    `[presence: README "Recommended companions" anchor]`:
      6. `Recommended companions` (the section header that anchors the neutral
         companion endorsement; erasing the section to satisfy absence checks
         must fail this).

    **speccraft-v1-spec.md absence (5)** — labelled e.g.
    `[absence #N: v1-spec "<short id>"]`:
      7. `prefer its tools for structural queries` (line 1132).
      8. `suggest installing CodeGraphContext as an MCP server alongside speccraft`
         (line 697).
      9. `should install it as an MCP server alongside speccraft` (line 1369).
      10. `users who need these capabilities should install` (line 1792).
      11. `the recommended integration with CodeGraphContext` (line 33).

    **speccraft-v1-spec.md presence (1)** — labelled e.g.
    `[presence: v1-spec "Recommended companion" anchor]`:
      12. `Recommended companion` (§13 line 1369 bolded label — substring
          match; survives the surrounding-paragraph rewrite in T3).

  - Per codex's round-2 review note (in `review.md`), **presence checks are
    labelled as explicitly as absence checks** so a reviewer reading a failure
    message can distinguish over-deletion from missed scrub at a glance.
  - Mark executable (`chmod +x`).
- Run `verify.sh` against current `main`. **MUST exit non-zero** — every
  absence-target string is still present in source. The non-zero exit plus
  diagnostic stderr IS the RED state.
- **Satisfies AC3** (shape and scope of `verify.sh`).

### Step 2 (T2) — Scrub `README.md` (GREEN, partial)

- Edit `README.md` to remove or rephrase the 5 pinned prescriptive strings.
  The three edit sites correspond to AC1's pinned line numbers:
  - **Line 355** — remove `use its tools to check architectural invariants`.
    Keep the surrounding factual description of MCP-tool availability; remove
    only the prescriptive verb phrase.
  - **Line 365** — remove `It's the recommended way to answer`. Rephrase the
    sentence so the descriptive content (what the tool answers, factually)
    survives without the prescriptive framing.
  - **Line 383** — remove both `` prefer it over `grep`/`find` for structural
    questions `` and `the speccraft skill will note its presence`. (Both
    strings are in the same paragraph.) Rephrase to factual description of
    capability without the routing prescription.
  - Defensive paraphrase pin (#5) is never present in `main` — the rewrite
    must not reintroduce `prefer CodeGraphContext for structural queries`.
- **Retain** the `Recommended companions` section header (line ~377) and the
  feature-comparison table (lines 380–381) — neutral examples per the spec's
  §What. The `enforce: cgc rule="..."` future-directive text is also retained
  (future-speccraft-behavior description, not present-day routing).
- Re-run `verify.sh`. **README absence checks 1–4 pass; defensive pin 5 passes
  (still absent); presence check 6 passes.** v1-spec checks 7–12 still fail
  (untouched). The script still exits non-zero.
- **Satisfies AC1** (README scrub).

### Step 3 (T3) — Scrub `speccraft-v1-spec.md` (GREEN, full)

- Edit `speccraft-v1-spec.md` to remove or rephrase the 5 pinned prescriptive
  strings. The five edit sites correspond to AC2's pinned line numbers:
  - **Line 33** — remove `the recommended integration with CodeGraphContext`.
    Rephrase so the descriptive context (what kind of integration, factually)
    survives without the "recommended" framing.
  - **Line 697** — remove `suggest installing CodeGraphContext as an MCP server
    alongside speccraft`. Note: line 698 contains a `(see README §"Recommended
    companions")` cross-reference inside the same scrub block. Removing the
    line-697 paragraph also removes the line-698 cross-ref. That is acceptable
    — see §Risk below.
  - **Line 1132** — remove `prefer its tools for structural queries`. Keep
    the factual MCP-capability description.
  - **Line 1369** — remove `should install it as an MCP server alongside
    speccraft`. **CRITICAL:** the §13 bolded label `**Recommended companion:**`
    is on this same line/paragraph and is the surviving anchor for v1-spec
    presence check #12. Do NOT touch the bolded label; remove only the
    prescriptive install verb phrasing.
  - **Line 1792** — remove `users who need these capabilities should install`.
    Rephrase the v1.x roadmap mention so the prospective `enforce: cgc` bridge
    directive description survives factually without the user-install
    prescription.
- Re-run `verify.sh`. **All 12 checks pass.** Script exits 0. Full GREEN.
- **Satisfies AC2** (v1-spec scrub).

### Step 4 (T4) — Refactor: readability + semantic-drift review (REFACTOR)

- Re-read the rewritten paragraphs in `README.md` (lines 355, 365, 383) and
  `speccraft-v1-spec.md` (lines 33, 697, 1132, 1369, 1792) end-to-end as
  prose, not as diff hunks.
- Confirm:
  - No dangling sentence fragments left by phrase removal (a paragraph that
    used to say "Install X; prefer it for Y" cannot become "Install X;.").
  - No semantic drift: a sentence describing CGC's MCP-server capabilities
    must still describe those capabilities factually — only the prescriptive
    verb / phrasing is removed, the descriptive content survives.
  - The `Recommended companions` README section header and the `Recommended
    companion` v1-spec §13 bolded label both still anchor real prose.
- Re-run `verify.sh`. Still exits 0.
- All twelve checks remain green.

### Step 5 (T5) — Close gate (commit, push, manual review, `/speccraft:spec:close`)

- Commit the edits on a topic branch:
  - `verify.sh` (new file, executable).
  - `README.md` (3 edit sites).
  - `speccraft-v1-spec.md` (5 edit sites).
- Push and verify CI is green. **No CI changes here** — this spec adds no
  workflow, and `verify.sh` for doc-only specs is not wired into CI per the
  convention ("Doc-only specs do not wire `verify.sh` into CI — the changes
  are one-shot and the grep cost is low enough for reviewer inspection"). The
  effective close gate is `verify.sh` exiting 0 locally plus manual reviewer
  inspection of the diff.
- Confirm `specs/0001-speccraft-v1/spec.md` is byte-identical to its
  pre-implementation state (closed-immutable; **AC4**). Verify with
  `git diff main -- specs/0001-speccraft-v1/spec.md` returning empty.
- Run `/speccraft:spec:close`.

## AC mapping

- **T1 → AC3** (`verify.sh` shape and scope; file-scoped `grep -F`; no `grep
  -r`; labelled checks; non-zero on failure).
- **T2 → AC1** (README absence of 5 pinned strings + presence of `Recommended
  companions`).
- **T3 → AC2** (v1-spec absence of 5 pinned strings + presence of `Recommended
  companion`).
- **T4** is the readability/semantic-drift refactor pass; protects against
  half-sentence artefacts. No new AC; defends the §What "removal/rewording
  only" framing.
- **T5 → AC4** (closed-spec immutability: confirm `specs/0001-speccraft-v1/
  spec.md` is byte-identical pre/post via `git diff`). Enforced by convention
  + PR diff review, not by `verify.sh`.

## Delegation

- **T1, T2, T3, T4, T5** → execute in-thread (no aux-agent dispatch). This is
  doc-only Bash + Markdown editing; no model-judgement-heavy step. The plan
  itself is the spec-coder agent's input; the spec-reviewer agent reviews the
  diff at PR time.

## Risk

- **Defensive paraphrase pin (#5) is trivially green.** `prefer
  CodeGraphContext for structural queries` is not present in current `main`
  — check #5 will pass on the very first `verify.sh` run, before any edit.
  That is intentional: its job is to catch a *future* rewrite reintroducing
  the banned wording, not to be a meaningful RED→GREEN signal in this cycle.
  Reviewers should not be surprised that the RED-state stderr only names 10
  failing checks (5 README absences + 5 v1-spec absences), not 11.

- **Line 698 cross-reference removal in v1-spec.** Line 698 contains a `(see
  README §"Recommended companions")` cross-reference inside the paragraph
  whose line-697 prescriptive phrase T3 removes. Removing the line-697
  paragraph also removes line 698's cross-ref. That is acceptable because
  the cross-ref points at the README, not at the v1-spec itself, and the
  v1-spec PRESENCE anchor (check #12, `Recommended companion`) is satisfied
  by the §13 line 1369 bolded label, which T3 is explicitly forbidden to
  touch. **Mitigation:** T3 step body and the T3.4 subtask in `tasks.md`
  both explicitly call out "do NOT touch the §13 bolded label."

- **Semantic drift from naive verb deletion.** Removing "prefer", "should
  install", and "the recommended way" without replacement could leave
  half-sentences ("Install X; ." / "X is . for Y."). **Mitigation:** T4
  is a dedicated end-to-end readability pass; each rewrite preserves the
  descriptive content (factual MCP-server description, factual roadmap
  mention) while removing only the prescriptive verb/phrasing. A reviewer
  scanning the diff will see prose that reads naturally, not phrase
  excisions.

- **Shell quoting of backticks in check #1.** The fixed-string argument to
  `grep -F` for check #1 (`` prefer it over `grep`/`find` for structural
  questions ``) contains literal backticks. Single-quote the argument to
  prevent the shell from interpreting them as command substitution. The
  `verify.sh` author must verify this by running the script — a botched
  quote will make check #1 spuriously pass (the grep target string is then
  malformed and never matches), giving a false GREEN.

- **`grep -F` vs `grep -r` (AC3).** Every check is file-scoped to `README.md`
  or `speccraft-v1-spec.md` by name. Using `grep -rF ... .` would scan this
  spec's own `spec.md` — which intentionally embeds every absence-target
  string verbatim — and produce permanent false positives that cannot be
  eliminated without rewriting `spec.md`, which is forbidden once
  status: reviewed by convention. **Mitigation:** T1 step body explicitly
  names the file-scope rule; spec.md AC3 names it as a gate.

- **Closed-spec leak via stray edit (AC4).** `specs/0001-speccraft-v1/spec.md`
  is closed-immutable. T2/T3 touch only `README.md` and `speccraft-v1-spec.md`
  at repo root, but a careless multi-file find-and-replace could leak. T4
  protects against this — re-reading rewritten paragraphs is scoped to the
  two target files. T5 explicitly verifies `git diff main --
  specs/0001-speccraft-v1/spec.md` is empty before close.
