---
description: "Start a new spec via Socratic interview, then draft spec.md"
argument-hint: "<short title>"
allowed-tools: ["Read", "Write", "Edit", "Bash"]
---

Start a new spec titled: "$1"

**IMPORTANT**: Execute ALL steps below using your tools before responding. Use
Bash for shell commands, Read for reading files, Write for creating files, and
Edit for modifying existing files. Do not describe steps — carry them out.

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

3. Allocate next ID: run `ls specs/ 2>/dev/null` to list existing spec dirs,
   take the highest NNNN prefix + 1 (or 0001 if none). Slugify "$1"
   (lowercase, kebab-case, drop non-[a-z0-9-]).

4. Create the spec directory and write `specs/<id>-<slug>/spec.md`:

   ```markdown
   ---
   id: "<id>"
   title: "<title>"
   status: draft
   created: <YYYY-MM-DD>
   authors: [claude]
   packages: []
   related-specs: []
   ---

   # Spec <id> — <title>

   ## Why

   <motivation>

   ## What

   <scope description>

   ## Acceptance criteria

   1. <observable behavior>
   2. <observable behavior>
   3. <observable behavior>

   ## Out of scope

   - <item>

   ## Open questions

   _none_
   ```

5. Fill in the spec content using one of two paths:

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

6. Run:
   ```bash
   "$CLAUDE_PLUGIN_ROOT/bin/speccraft-state" set active_spec <id>-<slug>
   ```

7. Edit `.speccraft/index.md` to update the "Active spec" section to:
   `specs/<id>-<slug>/`

8. Respond with a brief confirmation: spec ID, title, and suggested next step
   (`/speccraft:spec:review` recommended, or `/speccraft:spec:plan --skip-review`).
