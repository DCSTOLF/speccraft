---
description: "Start a new spec via Socratic interview, then draft spec.md"
argument-hint: "<short title>"
allowed-tools: ["Read", "Write", "Edit", "Bash"]
---

Start a new spec titled: "$1"

Steps:

1. Confirm `.speccraft/` exists. If not, suggest `/speccraft:init` and stop.

2. Read `.speccraft/state.json`. If `active_spec` is set and that spec's
   status is `in-progress`, ask the user whether to:
   (a) close the active spec first (`/spec:close`),
   (b) park it (set status: blocked), or
   (c) cancel the new spec.

3. Allocate next ID: list `specs/NNNN-*` directories, take max + 1, zero-pad
   to 4 digits. Slugify "$1" (lowercase, kebab-case, drop non-[a-z0-9-]).

4. Create `specs/<id>-<slug>/` and a stub `spec.md` with frontmatter
   (status: draft) and empty sections.

5. Invoke the `spec-author` subagent to interview the user Socratically,
   filling in the spec template:
   - Why (motivation, problem, evidence)
   - What (scope, acceptance criteria — must be testable)
   - Out of scope
   - Open questions

   The interview must produce at least 3 acceptance criteria, each phrased
   as an observable behavior. If the user resists detail, the agent should
   note open questions but not fabricate criteria.

6. Save `spec.md` with status: draft. Run:
   ```bash
   speccraft-state set active_spec <id>-<slug>
   ```

7. Update `.speccraft/index.md` "Active spec" section to point at the new dir.

8. Suggest next step: `/spec:review` (recommended) or `/spec:plan --skip-review`.
