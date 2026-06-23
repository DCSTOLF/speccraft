---
description: "Compact .speccraft/history.md: keep a bounded recent window, merge older entries into a thematic summary, archive originals verbatim — confirm before any rewrite."
argument-hint: "[--window N]"
allowed-tools: ["Read", "Write", "Edit", "Bash"]
---

Compact `.speccraft/history.md` so it stays **bounded and true**: keep the newest
N entries verbatim, fold everything older into a merged thematic summary, and move
the originals verbatim into an append-only archive. This is the ONLY command that
rewrites `history.md`, and it **never rewrites without your confirmation**.

**IMPORTANT**: Execute ALL steps below using your tools before responding. Do not
describe steps — carry them out. The deterministic mechanics live in
`commands/history/compact.lib.sh` (unit-tested by
`tests/hooks/history-compact.bats`); source it before use.

Blast radius: this command touches ONLY `.speccraft/history.md` and
`.speccraft/history-archive/`. It must never edit `architecture.md`,
`conventions.md`, `index.md`, or any spec file.

Steps:

1. **Bootstrap.**
   ```bash
   REPO_ROOT="$("$CLAUDE_PLUGIN_ROOT/bin/speccraft-state" find-root)"
   source "$CLAUDE_PLUGIN_ROOT/commands/history/compact.lib.sh"
   HIST="$REPO_ROOT/.speccraft/history.md"
   ARCHIVE="$REPO_ROOT/.speccraft/history-archive/history.md"
   N="${WINDOW:-$HISTORY_WINDOW_N}"   # default 10; honor --window N if provided
   ```

2. **Compute the split (no writes yet).**
   ```bash
   OLDER="$(history_window_split "$HIST" "$N" older)"
   ```
   If `OLDER` is empty, report **"nothing to compact — history is within the
   recent window"** and STOP (no-op; write nothing).

3. **Gather inputs for the summary.**
   ```bash
   WINDOW_TEXT="$(history_window_split "$HIST" "$N" window)"
   EXISTING_THEMES="$(history_compacted_section_themes "$HIST")"   # durable input
   SEED="$(history_supersession_seed "$HIST" "$N")"                # older→newer pairs
   PREAMBLE="$(awk '/^## [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] /{exit} {print}' "$HIST")"
   ```

4. **Propose the rewrite via `memory-keeper` (compact mode).** Invoke the
   `memory-keeper` subagent in `# Mode: compact` with: the `OLDER` entries, the
   `EXISTING_THEMES` (durable — MERGE into them, never regenerate or drop), and the
   `SEED` supersession pairs (propose each collapse; out-of-window only). It returns
   a proposed `## Compacted (older than the active window)` section of merged `###`
   theme groups conforming to the summary schema (title; `Specs:`; `Archive:
   .speccraft/history-archive/history.md`; one-paragraph decision; `Supersedes:` for
   an accepted collapse).

5. **Present for confirmation — DO NOT WRITE YET.** Show the user:
   - the proposed new `history.md` = `PREAMBLE` + `WINDOW_TEXT` (verbatim, unchanged)
     + the proposed `## Compacted` section;
   - the list of entries that will be appended to the archive (`OLDER`'s headers);
   - each proposed supersession collapse from `SEED`, for accept/reject.
   Until the user confirms, `history.md` and `.speccraft/history-archive/` MUST
   remain byte-unchanged. If the user declines, write nothing and stop.

6. **Apply only on confirmation.**
   ```bash
   # a. archive originals verbatim (append-only, full-byte dedup)
   printf '%s\n' "$OLDER" | history_archive_append "$ARCHIVE"
   # b. rewrite history.md: preamble + verbatim window + the confirmed Compacted section
   {
     printf '%s\n' "$PREAMBLE"
     printf '%s\n' "$WINDOW_TEXT"
     printf '\n'
     printf '%s\n' "$CONFIRMED_COMPACTED_SECTION"
   } > "$HIST.tmp" && mv "$HIST.tmp" "$HIST"
   ```
   Keep the window entries byte-identical; place every supersession pointer on the
   archived/summarized side, never by mutating a window entry.

7. Confirm what was compacted: how many entries moved to the archive, the theme
   groups in the new `## Compacted` section, and that the newest N entries are
   unchanged. Note that full records remain in
   `.speccraft/history-archive/history.md` and in git.
