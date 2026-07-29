---
description: "Bootstrap speccraft in this repository"
argument-hint: "[--workspace] [--force]"
allowed-tools: ["Bash", "Read", "Write", "Edit"]
---

You are bootstrapping speccraft in the current repository.

**IMPORTANT**: Execute ALL steps below using your tools before responding. Use
Bash for shell commands, Read for reading files, Write for creating files, and
Edit for modifying existing files. Do not describe steps — carry them out.

Steps:

1. Discover the plugin root. `speccraft-state` is on `PATH` via the plugin's
   `bin/` (installed by the SessionStart hook before any command runs), and it
   self-resolves the plugin's install directory:
   ```bash
   PLUGIN_ROOT="$(speccraft-state plugin-root)"
   ```
   If this errors, the plugin install is broken — reinstall it. (Unlike
   `$CLAUDE_PLUGIN_ROOT`, which is not reliably exported to slash-command bash,
   `speccraft-state plugin-root` derives the root from the binary's own location
   — see spec 0030.)

2. Run `bash "$PLUGIN_ROOT/scripts/install-binaries.sh"` to ensure helper
   binaries are built. If the script exits non-zero, print a warning but
   continue — the binaries may already be present.

3. Locate the repo root by walking up from `cwd` to the nearest directory
   containing `.git`. If none, error with: "No git repository found. Initialize
   one with `git init` first."

3a. **Parse the mode flags (spec 0042).** Source the lib and normalize the
    arguments — this recognizes `--workspace`/`--force` order-independently and
    rejects any unknown flag or stray positional:
    ```bash
    source "$PLUGIN_ROOT/commands/init.lib.sh"
    FLAGS="$(ws_arg_parse "$@")" || { echo "$FLAGS"; exit 1; }
    grep -qx workspace <<<"$FLAGS" && MODE=workspace || MODE=repo
    grep -qx force     <<<"$FLAGS" && FORCE=1        || FORCE=0
    ```

4. If `.speccraft/` already exists and `$FORCE` is not `1`, refuse:
   ".speccraft/ already exists. Use `/speccraft:init [--workspace] --force` to overwrite."

4a. **Workspace migration refusal (spec 0042 AC7).** When `MODE=workspace` and a
    `.speccraft/` already exists (a `--force` re-init), read its current kind:
    ```bash
    KIND="$(speccraft-state config-kind "<repo>" 2>/dev/null || echo unknown)"
    ```
    If `KIND` is `repo`, REFUSE: "This root is a repo-kind speccraft project;
    in-place migration to a workspace is out of scope. Create a workspace in a
    fresh root instead." (Do not overwrite the repo config — this refusal takes
    precedence over the `--force` overwrite matrix.) `KIND=workspace` proceeds
    idempotently; a fresh root (no `.speccraft/`) has no migration question.

5. Create `<repo>/.speccraft/` if it does not exist. Then copy each template
   by reading from PLUGIN_ROOT and writing to the repo:

   - **index.md — mode-dependent (spec 0042 AC5):**
     - `MODE=repo`: Read `$PLUGIN_ROOT/templates/speccraft/index.md` → Write to `<repo>/.speccraft/index.md`
     - `MODE=workspace`: Read `$PLUGIN_ROOT/templates/speccraft/index.workspace.md` → Write to `<repo>/.speccraft/index.md` (it carries the `<!-- speccraft:kind = workspace -->` marker + `## Members` header)
   - Read `$PLUGIN_ROOT/templates/speccraft/guardrails.md`  → Write to `<repo>/.speccraft/guardrails.md`
   - Read `$PLUGIN_ROOT/templates/speccraft/architecture.md`→ Write to `<repo>/.speccraft/architecture.md`
   - Read `$PLUGIN_ROOT/templates/speccraft/history.md`     → Write to `<repo>/.speccraft/history.md`
   - **Do NOT copy `conventions.md` here** — it is seeded from the detected stack
     in step 5a below (so a Python/JS/Rust repo does not receive Go conventions).
   - Read `$PLUGIN_ROOT/templates/speccraft/agents.toml`    → Write to `<repo>/.speccraft/agents.toml`

5a. **Seed `conventions.md` from the detected stack (spec 0034).** Source the
    colocated helper and call it — it copies the stack-agnostic template, then
    fills the Testing-section `speccraft:test-command` marker + a detected-stack
    note from `speccraft-state detect-stack`. It PRESERVES an existing
    `conventions.md` byte-for-byte (idempotent), and on an unknown stack writes a
    `TODO` placeholder + empty marker rather than a wrong default:
    ```bash
    source "$PLUGIN_ROOT/commands/init.lib.sh"
    seed_conventions "<repo>" "$PLUGIN_ROOT/templates/speccraft/conventions.md"
    ```

6. Create `<repo>/specs/.gitkeep` (creating `specs/` if absent).

7. Append `.speccraft/state.json` to `<repo>/.gitignore` (creating if absent).
   Only append if the line isn't already present.

8. Initialize `<repo>/.speccraft/state.json` via the sanctioned binary —
   do **not** Write/Edit this file directly, the spec-0012 PreToolUse
   hook blocks it:
   ```bash
   speccraft-state init
   ```
   `speccraft-state init` is idempotent: it writes the canonical empty
   shape (`{"version":1,"session":{"id":"","edited_test_files":[],"edited_prod_files":[]}}`)
   on first call and is a no-op if `.speccraft/state.json` already
   exists, so re-running `/speccraft:init` cannot silently nuke session
   state.

8a. **Detect Python test roots.** _(repo mode only — skip this step entirely when
    `MODE=workspace`; a workspace root holds no code.)_ Check whether `tests/` or
    `test/` exists at the repo root (in that order). If found, ask the user:

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

8b. **Scaffold the workspace artifacts (spec 0042).** _(workspace mode only — run
    only when `MODE=workspace`.)_ Discover candidate members, get approval, then
    write the manifest + workspace kind via the lib (`init.lib.sh` is already
    sourced from step 3a):

    1. **Preserve a curated manifest.** If `<repo>/workspace.yml` already exists,
       leave it untouched and SKIP member detection/approval entirely (AC6) — the
       curated member list wins. Otherwise continue.
    2. **Detect candidates** deterministically:
       ```bash
       CANDIDATES="$(ws_detect_members "<repo>")"   # sorted repo-kind children
       ```
    3. **Approve per candidate.** For each line in `$CANDIDATES`, ask the user
       "Add `<child>/` as a workspace member? [Y/n]"; collect the approved
       basenames into `MEMBERS` (space-separated). No candidates ⇒ empty set.
    4. **Write the artifacts** in the AC9-mandated order (manifest first, then the
       toml flip; the ledger is never created — AC4):
       ```bash
       ws_write_root "<repo>" $MEMBERS || { echo "workspace scaffold failed"; exit 1; }
       ```
       This writes `<repo>/workspace.yml` (canonical shape, members parse via
       `speccraft-state list-members`) and flips `<repo>/.speccraft/speccraft.toml`
       to `kind = "workspace"` (verify with `speccraft-state config-kind "<repo>"`
       ⇒ `workspace` and `speccraft-state find-workspace-root` ⇒ `<repo>`). Add
       `workspace.yml` and `speccraft.toml` to the printed file list in step 12.

    Do NOT emit `kind = "workspace"` or a `workspace.yml` in repo mode — these
    artifacts are produced only under this `--workspace` branch (AC8).

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
    suggest installing a code-intelligence MCP server (such as CodeGraphContext)
    alongside speccraft.
