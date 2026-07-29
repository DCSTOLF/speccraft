---
spec: "0011"
status: planned
strategy: tdd
---

# Plan — 0011 Defer code-intel routing to user globals

## Framing

This is a **documentation/template-only** spec. There is no Go code, no
hook, no runner, no e2e fixture to write. The three target packages —
`skills/speccraft-context`, `commands`, `templates/speccraft` — contain
only Markdown and TOML; an inventory of their existing test files
(`*_test.go`, `*_test.sh`) returns **nothing**. There is therefore no
behavioral RED test to write.

The RED→GREEN cycle is **grep-assertion based**:

- **RED** = a verification script that codifies all three acceptance
  criteria as `grep` invocations. Running it against current `main`
  fails on every check.
- **GREEN A/B/C** = three small Markdown edits, one per AC. After each
  edit the script's corresponding section flips from fail to pass.
- **REFACTOR** = optional final pass for cross-reference cleanup and a
  full clean run of the verification script.

The script is committed at `specs/0011-code-intel/verify.sh` so the
GREEN check is mechanical, reproducible, and reviewable.

## Test-first sequence

### Step 1 — Verification script that fails on current main (RED)

- Add `specs/0011-code-intel/verify.sh` (executable, `#!/usr/bin/env bash`,
  `set -euo pipefail`). The script asserts all three ACs:

  - **AC1 — `skills/speccraft-context/SKILL.md`:**
    - `grep -in 'codegraph\|cgc' skills/speccraft-context/SKILL.md`
      must return **zero** matches.
    - `grep -in 'defer' skills/speccraft-context/SKILL.md` must return
      **at least one** match (positive presence of deferral language).
    - `grep -in 'structural queries are a real need\|structural queries
      are a legitimate need' skills/speccraft-context/SKILL.md` must
      return at least one match (the section is replaced, not deleted).

  - **AC2 — `commands/init.md` (repo-wide):**
    - `grep -rni 'codegraph' commands/ agents/ hooks/ skills/ tools/
      templates/` must return **exactly one** line, and that line must
      be in `commands/init.md`.
    - `grep -niE 'such as|for example|e\.g\.,' commands/init.md` must
      return a line that also contains `CodeGraphContext` (example
      framing, not a recommendation).
    - `grep -niE 'call-graph|symbol-search' commands/init.md` must
      return at least one match (the conditional install-suggestion
      behaviour is preserved).

  - **AC3 — `templates/speccraft/architecture.md`:**
    - `grep -rni 'codegraph' templates/` must return **zero** matches.
    - `grep -in 'Advisory in v1' templates/speccraft/architecture.md`
      must still return a match (the layering rule stands).

- Tests fail because, on current `main`:
  - SKILL.md lines 28 and 33 contain `CodeGraphContext`.
  - SKILL.md contains no `defer` wording.
  - `commands/init.md:112` names CodeGraphContext but not as an example.
  - `templates/speccraft/architecture.md:11` names CodeGraphContext.
  - Repo-wide grep returns 4 lines, not 1.

  Running `bash specs/0011-code-intel/verify.sh` on current `main` must
  exit non-zero. This is the RED state.

### Step 2 — Replace SKILL.md routing block with neutral deferral (GREEN A)

- Edit `skills/speccraft-context/SKILL.md` lines 24-36 (the "Codebase-wide
  structural queries" section). Remove the two CodeGraphContext bullets
  and replace with a short, tool-neutral block that:
  - Acknowledges structural queries (where is X called?, what does Y
    export?, which tests cover Z?) are a real need.
  - States that speccraft **defers** to whatever code-intel tool the
    user has installed (typically registered via global CLAUDE.md or an
    MCP server's own instructions).
  - Does NOT enumerate tool names.
  - Retains the final sentence noting that speccraft itself only knows
    about session edits via `state.json` and the literal contents of
    `.speccraft/`.

- Satisfies **AC1**. After this edit:
  - `grep -in 'codegraph\|cgc' skills/speccraft-context/SKILL.md` → 0
  - `grep -in 'defer' skills/speccraft-context/SKILL.md` → ≥1
  - section non-empty and retains the "real need" acknowledgment

- All other ACs still red. Verification script still exits non-zero
  but the AC1 block now passes.

### Step 3 — Rephrase commands/init.md install-suggestion as example (GREEN B)

- Edit `commands/init.md` lines 111-113 (the install-suggestion at the
  tail of step 12). Keep the conditional trigger (only fires when the
  user mentions call-graph or symbol-search needs), but reword so
  CodeGraphContext is framed as one **example** of a code-intel MCP
  server, not the recommended tool. Example phrasing:

  > If the user mentions they want call-graph or symbol-search
  > capabilities, suggest installing a code-intelligence MCP server
  > (such as CodeGraphContext) alongside speccraft.

- Satisfies **AC2**:
  - Repo-wide `grep -rni 'codegraph' commands/ agents/ hooks/ skills/
    tools/ templates/` → exactly 1 line, in `commands/init.md`.
  - `grep -niE 'such as|for example|e\.g\.,' commands/init.md` returns
    a line containing `CodeGraphContext`.
  - `grep -niE 'call-graph|symbol-search' commands/init.md` still
    matches the surviving trigger phrase.

- AC3 still red.

### Step 4 — Strip CodeGraphContext from architecture template (GREEN C)

- Edit `templates/speccraft/architecture.md` line 11. Remove the
  `; enforced via CodeGraphContext if configured` clause. The
  parenthetical should collapse to `(Advisory in v1.)` so the layering
  rule stands on its own as advisory; enforcement is the host repo's
  choice.

- Satisfies **AC3**:
  - `grep -rni 'codegraph' templates/` → 0 matches.
  - `Advisory in v1` still present.

- Run `bash specs/0011-code-intel/verify.sh` end-to-end. All three AC
  blocks now pass; script exits 0. This is the GREEN state.

### Step 5 — Optional refactor & final verification (REFACTOR)

- Re-read the three edited sections for residual cross-references or
  awkward wording introduced by the edits (e.g. the SKILL.md section
  header may want a slight rename now that the body no longer lists
  tools; `commands/init.md` README pointer at the end of the
  install-suggestion may want to be relaxed if it specifically points
  at "Recommended companions" copy that will become stale).
- README.md is explicitly out of scope per the spec — do **not** edit
  it here. A separate README-cleanup pass handles that.
- Final clean run: `bash specs/0011-code-intel/verify.sh` must exit 0.
- The verify script itself stays in the spec directory as documentation
  of the AC checks; it is not wired into CI for this spec (the changes
  are one-shot and the repo-wide grep is cheap enough for reviewer
  inspection).

## Delegation

- No delegation. All three edits are small, surgical, single-file
  Markdown changes inside the speccraft repo itself — the work that
  the spec-author/spec-critic/cross-reviewer chain already produced
  the constraints for. Spinning up an aux agent (codex / opencode /
  claude-p) for ~10 lines of Markdown edits would add latency without
  improving correctness, and the verification script is the
  objective oracle.

## Risk

- **Wording drift between SKILL.md and the spec's "deferral" phrase
  requirement.** Mitigation: the verify.sh script enforces the
  literal `defer` token presence in SKILL.md, so any rewrite that
  drops the word fails RED automatically.
- **Accidentally satisfying AC2's "exactly one match" by deleting the
  install-suggestion entirely.** Mitigation: verify.sh also asserts
  positive presence of a trigger phrase (`call-graph` /
  `symbol-search`) in `commands/init.md`, so the suggestion line
  cannot vanish silently.
- **Accidentally satisfying AC1 by deleting the structural-queries
  section.** Mitigation: verify.sh asserts the "real need"
  acknowledgment phrase is present.
- **README.md drift.** The spec explicitly excludes README.md;
  reviewers may still flag it. Mitigation: §Out of scope in
  `spec.md` documents the deferral rationale (README is human-facing
  prose, not model-loaded routing) so the follow-up is captured.
