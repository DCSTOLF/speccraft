---
description: "Turn the active spec into a test-first plan and tasks list"
argument-hint: "[--skip-review]"
allowed-tools: ["Read", "Write", "Edit", "Bash"]
---

Generate plan.md and tasks.md from the active spec.

Steps:

1. Read `.speccraft/state.json` for `active_spec`. If none, error.

2. Read spec.md. Require status >= `reviewed` OR status `draft` with
   `--skip-review` flag (warn loudly if skipping review).

3. List existing test files in directories matching `spec.packages`:
   ```bash
   find <pkg> -name '*_test.go' 2>/dev/null
   ```
   Pass this inventory to the planner so it can reason about which test
   files to extend vs. create new.

4. Invoke the `tdd-planner` subagent with:
   - spec.md content
   - Relevant `.speccraft/` files (guardrails, conventions, architecture)
   - The existing-tests inventory from step 3

   The planner must produce a sequence of RED→GREEN→REFACTOR steps. Each
   GREEN step must be preceded by a RED step. The planner names files and
   test functions concretely.

5. Write `plan.md` and `tasks.md`. Update spec status to `planned`.

6. Suggest next step: `/spec:implement` or manually start with the first RED test.
