---
description: "Bootstrap speccraft in this repository"
argument-hint: "[--force]"
allowed-tools: ["Bash", "Read", "Write", "Edit"]
---

You are bootstrapping speccraft in the current repository.

**IMPORTANT**: Execute ALL steps below using your tools before responding. Use
Bash for shell commands, Read for reading files, Write for creating files, and
Edit for modifying existing files. Do not describe steps — carry them out.

Steps:

1. Discover the plugin root. Run:
   ```
   bash -c 'echo "${CLAUDE_PLUGIN_ROOT:-}"'
   ```
   Store the result as PLUGIN_ROOT. If the result is empty, try common locations:
   - Look for a directory that contains both `templates/speccraft/index.md` and
     `scripts/install-binaries.sh`. Check `~/.claude/plugins/speccraft/`,
     `~/.claude/plugins/speccraft@speccraft/`, and any path from
     `$CLAUDE_PLUGIN_DIR`.
   - If still not found, error: "Cannot locate speccraft plugin root. Please
     reinstall the plugin."

2. Run `bash "$PLUGIN_ROOT/scripts/install-binaries.sh"` to ensure helper
   binaries are built. If the script exits non-zero, print a warning but
   continue — the binaries may already be present.

3. Locate the repo root by walking up from `cwd` to the nearest directory
   containing `.git`. If none, error with: "No git repository found. Initialize
   one with `git init` first."

4. If `.speccraft/` already exists and `$1` is not `--force`, refuse:
   ".speccraft/ already exists. Use `/speccraft:init --force` to overwrite."

5. Create `<repo>/.speccraft/` if it does not exist. Then copy each template
   by reading from PLUGIN_ROOT and writing to the repo:

   - Read `$PLUGIN_ROOT/templates/speccraft/index.md`       → Write to `<repo>/.speccraft/index.md`
   - Read `$PLUGIN_ROOT/templates/speccraft/guardrails.md`  → Write to `<repo>/.speccraft/guardrails.md`
   - Read `$PLUGIN_ROOT/templates/speccraft/architecture.md`→ Write to `<repo>/.speccraft/architecture.md`
   - Read `$PLUGIN_ROOT/templates/speccraft/conventions.md` → Write to `<repo>/.speccraft/conventions.md`
   - Read `$PLUGIN_ROOT/templates/speccraft/history.md`     → Write to `<repo>/.speccraft/history.md`
   - Read `$PLUGIN_ROOT/templates/speccraft/agents.toml`    → Write to `<repo>/.speccraft/agents.toml`

6. Create `<repo>/specs/.gitkeep` (creating `specs/` if absent).

7. Append `.speccraft/state.json` to `<repo>/.gitignore` (creating if absent).
   Only append if the line isn't already present.

8. Initialize `<repo>/.speccraft/state.json`:
   ```json
   {"version":1,"active_spec":null,"session":{"id":"","edited_test_files":[],"edited_prod_files":[]}}
   ```

8a. **Detect Python test roots.** Check whether `tests/` or `test/` exists at the
    repo root (in that order). If found, ask the user:

    ```
    Detected test directory: <name>/
    Add to .speccraft/speccraft.toml as a Python TDD test root? [Y/n]
    ```

    - If the user confirms, write `.speccraft/speccraft.toml`:
      ```toml
      [tdd]
      test_roots = ["<name>"]
      ```
      and add `speccraft.toml` to the printed file list in step 11.
    - If the user declines, or neither directory is found, do not create
      `speccraft.toml` (same-directory sibling behaviour applies by default).
    - If both `tests/` and `test/` exist, prefer `tests/` and mention both in
      the prompt so the user can correct it manually if needed.

9. Gather the following information from the user. If the user's message
   already contains pre-provided answers (e.g. `project='X'`, `stack='Y'`,
   `layering='Z'`, `top guardrails='...'`), extract and use those values
   directly without asking. Otherwise open `.speccraft/index.md`,
   `.speccraft/architecture.md`, and `.speccraft/conventions.md` in the
   conversation and ask for:
   - **Project name and description** (one sentence)
   - **Stack** (major technologies, versions)
   - **Architectural layering** (2-5 bullet points)
   - **Top 3 guardrails** — their most important "never" or "always" rules

10. Update all three files with the collected answers. For guardrails, add them
    to `.speccraft/guardrails.md` in addition to summarizing in index.md.

11. Update `.speccraft/history.md` to replace the `<date>` placeholder with
    today's date.

12. Print a summary:
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

    Next: /speccraft:spec:new "<title of your first spec>"
    ```

    If the user mentions they want call-graph or symbol-search capabilities,
    suggest installing CodeGraphContext as an MCP server alongside speccraft
    (see README "Recommended companions").
