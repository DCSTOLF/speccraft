---
description: "Start a new spec via Socratic interview, then draft spec.md"
argument-hint: "<short title> [--from product/<id>|design/<id>]"
allowed-tools: ["Read", "Write", "Edit", "Bash"]
---

Start a new spec titled: "$1"

**IMPORTANT**: Execute ALL steps below using your tools before responding. Use
Bash for shell commands, Read for reading files, Write for creating files, and
Edit for modifying existing files. Do not describe steps — carry them out.

The scaffold mechanism (and the optional `--from` bridge) lives in
`commands/spec/new.lib.sh` (testable via `tests/hooks/spec-new-from.bats`);
source it before use.

Steps:

1. Confirm `.speccraft/` exists (Read `.speccraft/index.md`).
   If not, suggest `/speccraft:init` and stop.

2. Read `.speccraft/state.json`. If `active_spec` is set and that spec's
   status is `in-progress`, ask the user whether to:
   (a) close the active spec first (`/speccraft:spec:close`),
   (b) park it (set status: blocked), or
   (c) cancel the new spec.
   If running non-interactively (answers pre-provided in the message), proceed
   with creating the new spec without blocking.

3. **Parse arguments.** The title is the leading positional argument. If the
   message contains `--from product/<id>` or `--from design/<id>`, capture the
   referent (e.g. `product/0003-checkout`); otherwise there is no referent.
   `--from` is **advisory and pull-only** — a missing, deleted, or `closed`
   referent NEVER blocks `spec:new`; the helper surfaces a non-fatal note and
   proceeds (spec §Lifecycle, AC8). A `closed` brief/design is an ideal source.

4. Allocate next ID: run `ls specs/ 2>/dev/null` to list existing spec dirs,
   take the highest NNNN prefix + 1 (or 0001 if none). Slugify "$1"
   (lowercase, kebab-case, drop non-[a-z0-9-]).

5. **Bootstrap + scaffold via the lib.**
   ```bash
   REPO_ROOT="$("$CLAUDE_PLUGIN_ROOT/bin/speccraft-state" find-root)"
   source "$CLAUDE_PLUGIN_ROOT/commands/spec/new.lib.sh"
   SPEC="$REPO_ROOT/specs/<id>-<slug>/spec.md"
   ```
   - **Plain (no `--from`):** `spec_new_scaffold "$SPEC" "<id>" "<title>" "$(date +%F)" "$REPO_ROOT"`.
     This writes NO `informed-by` key — byte-shape parity with a today's spec.
   - **With `--from <referent>`:** `spec_new_scaffold "$SPEC" "<id>" "<title>" "$(date +%F)" "$REPO_ROOT" "<referent>"`.
     This pulls the referent's Why/What into the new spec and records a
     non-empty `informed-by: [<referent>]` frontmatter key. A dangling referent
     emits a non-fatal note on stderr and the spec is still generated with the
     advisory link recorded.

6. Fill in the spec content using one of two paths:

   **Path A — pre-provided answers** (non-interactive / scripted use):
   If the user's message contains patterns like `why='...'`, `what='...'`,
   `AC='...'`, `oos='...'`, extract and use them directly — do NOT invoke
   spec-author. Edit `specs/<id>-<slug>/spec.md` to replace the placeholder
   sections with:
   - **Why** from `why='...'`
   - **What** + **Acceptance criteria** from `what='...'` and `AC='...'`
   - **Out of scope** from `oos='...'`
   - **Open questions** — empty unless `questions='...'` is provided

   **Path B — interactive** (default, when no pre-provided answers):
   Invoke the `spec-author` subagent to interview the user Socratically,
   filling in the Why / What / AC / Out-of-scope / Open-questions sections.
   The interview must produce at least 3 testable acceptance criteria.

   When `--from` was used, the Why/What are already pre-populated from the
   referent — refine them rather than starting blank, and NEVER drop the
   `informed-by` frontmatter key.

7. Run:
   ```bash
   "$CLAUDE_PLUGIN_ROOT/bin/speccraft-state" set active_spec <id>-<slug>
   ```

8. Edit `.speccraft/index.md` to update the "Active spec" section to:
   `specs/<id>-<slug>/`

9. Respond with a brief confirmation: spec ID, title, and suggested next step
   (`/speccraft:spec:review` recommended, or `/speccraft:spec:plan --skip-review`).
