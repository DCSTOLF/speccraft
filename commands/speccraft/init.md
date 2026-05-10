---
description: "Bootstrap speccraft in this repository"
argument-hint: "[--force]"
allowed-tools: ["Bash", "Read", "Write", "Edit"]
---

You are bootstrapping speccraft in the current repository.

Steps:

1. Run `bash $CLAUDE_PLUGIN_ROOT/scripts/install-binaries.sh` to ensure helper
   binaries are built.

2. Locate the repo root by walking up from `cwd` to the nearest directory
   containing `.git`. If none, error with: "No git repository found. Initialize
   one with `git init` first."

3. If `.speccraft/` already exists and `$1` is not `--force`, refuse:
   ".speccraft/ already exists. Use `/speccraft:init --force` to overwrite."

4. Copy `$CLAUDE_PLUGIN_ROOT/templates/speccraft/*` to `<repo>/.speccraft/`:
   - index.md
   - guardrails.md
   - architecture.md
   - conventions.md
   - history.md
   - agents.toml

5. Create `<repo>/specs/.gitkeep` (creating `specs/` if absent).

6. Append `.speccraft/state.json` to `<repo>/.gitignore` (creating if absent).
   Only append if the line isn't already present.

7. Initialize `<repo>/.speccraft/state.json`:
   ```json
   {"version":1,"active_spec":null,"session":{"id":"","edited_test_files":[],"edited_prod_files":[]}}
   ```

8. Open `.speccraft/index.md`, `.speccraft/architecture.md`, and
   `.speccraft/conventions.md` in the conversation. Ask the user to fill in:
   - **Project name and description** (one sentence)
   - **Stack** (major technologies, versions)
   - **Architectural layering** (2-5 bullet points)
   - **Top 3 guardrails** — their most important "never" or "always" rules

   Update all three files with the user's answers. For guardrails, add them
   to `.speccraft/guardrails.md` in addition to summarizing in index.md.

9. Update `.speccraft/history.md` to replace the `<date>` placeholder with
   today's date.

10. Print a summary:
    ```
    speccraft initialized in <repo root>

    Files created:
      .speccraft/index.md
      .speccraft/guardrails.md
      .speccraft/architecture.md
      .speccraft/conventions.md
      .speccraft/history.md
      .speccraft/agents.toml
      .speccraft/state.json  (gitignored)
      specs/.gitkeep

    Next: /spec:new "<title of your first spec>"
    ```

    If the user mentions they want call-graph or symbol-search capabilities,
    suggest installing CodeGraphContext as an MCP server alongside speccraft
    (see README "Recommended companions").
