---
spec: "0017"
status: planned
strategy: tdd
---

# Plan — 0017 e2e default model (slug rename: option → e2e-default-model)

## Overview

A one-line behavioral change plus an oracle extension plus three doc/housekeeping
touch-ups. The core change inserts `--model "${CLAUDE_MODEL:-claude-sonnet-4-6}"`
as the first argument after `-p` in the `run_claude()` helper at
`/workspaces/speccraft/tests/e2e/run.sh:173-189`, making CI's model choice
explicit (cheaper Sonnet 4.6, 200k context) and overridable via `CLAUDE_MODEL`.
The existing `> "$LOG_DIR/$log" 2>&1` redirect and the `|| { ... exit 3 }`
failure path are load-bearing (spec-0008 AC#5 classifier + the capture probe)
and MUST be preserved verbatim.

Everything else is doc hygiene: the spec slug/title is the lone convention
violation (`option` is a placeholder), the spec "What" snippet should be marked
illustrative, run.sh's `--help` usage block should advertise `CLAUDE_MODEL`, and
a validation-gate note should be recorded.

## Test strategy

- Oracle: `/workspaces/speccraft/tests/e2e/assertions/test_run_claude_capture.sh`
  — a standalone, credit-free Bash probe (exit 0 pass / 2 fail) that awk-extracts
  the `run_claude()` body from run.sh and runs labelled `grep -qE` checks against
  it. It already pins three properties (invokes `"$CLAUDE_BIN" -p`; combined
  `> "$LOG_DIR/$log" 2>&1` capture; failure path announces `claude -p failed` +
  `exit 3`). AC1 is verified by adding a **check #4** asserting the
  `--model "${CLAUDE_MODEL:-claude-sonnet-4-6}"` line is present in the extracted
  body. This is the canonical home for AC1's grep assertion and mirrors the
  existing checks #1-#3. The probe is invoked directly
  (`bash tests/e2e/assertions/test_run_claude_capture.sh` or via `devcontainer
  exec`); it is NOT run from run.sh or ci.yml.
- No behavioral test for AC2/AC3: AC2 (`CLAUDE_MODEL` non-empty → that value) and
  AC3 (unset/empty → `claude-sonnet-4-6`) are guaranteed by Bash `${VAR:-default}`
  parameter-expansion semantics — `:-` treats both empty AND unset as "use
  default". Reviewers agreed these need no separate behavioral test; a brittle
  subprocess test that stubs `$CLAUDE_BIN` would test Bash, not our code. The
  check-#4 grep over the literal expansion string `${CLAUDE_MODEL:-claude-sonnet-4-6}`
  is sufficient evidence for all three of AC1/AC2/AC3.
- AC4 (no other invocation/settings/workflow changed) is verified by inspection +
  the diff staying confined to run.sh and the probe; no new test is warranted.
- Validation gate: the next `e2e-devcontainer` run on `main` is the
  Sonnet-sufficiency validation gate — it exercises the full ~10-call lifecycle
  against Sonnet 4.6. If Sonnet regresses on the structural assertions, the
  recovery path is: local runs can override with `CLAUDE_MODEL=<model>` (env is
  local-only, not wired into CI), but a CI failure requires either a code change
  to the default in run.sh or a manual re-run — there is no CI env override.

## Test-first sequence

### Step 1 — Extend the capture oracle with the --model check (RED)
- Edit `/workspaces/speccraft/tests/e2e/assertions/test_run_claude_capture.sh`:
  - Add **check #4** after the existing check #3 (before the final `echo "OK: ..."`):
    a `grep -qE` over `$BODY` asserting the literal line
    `--model "${CLAUDE_MODEL:-claude-sonnet-4-6}"` is present, with a `fail`
    message and a `note` on success — mirroring checks #1-#3.
    Suggested pattern (escape `$` and `{`/`}` for grep -E):
    `grep -qE -- '--model[[:space:]]+"\$\{CLAUDE_MODEL:-claude-sonnet-4-6\}"'`
- Probe fails (exit 2): run.sh's `run_claude()` does not yet contain the
  `--model` line, so check #4's `grep -qE` finds nothing and triggers `fail`.

### Step 2 — Insert the --model flag into run_claude (GREEN)
- Edit `/workspaces/speccraft/tests/e2e/run.sh` (the `run_claude()` block at
  lines 173-189): insert a new line
  `    --model "${CLAUDE_MODEL:-claude-sonnet-4-6}" \`
  as the **first** argument after `"$CLAUDE_BIN" -p \` (i.e. before
  `--permission-mode bypassPermissions \`). Leave `--permission-mode`,
  `--output-format text`, `--plugin-dir "$PLUGIN_DIR"`, `"$prompt"`, the
  `> "$LOG_DIR/$log" 2>&1` redirect, and the `|| { ... exit 3 }` failure path
  unchanged.
- The probe passes (exit 0): all four checks now match. Satisfies AC1; AC2/AC3
  follow from `${VAR:-default}` semantics (no behavioral test, per strategy).

### Step 3 — Advertise CLAUDE_MODEL in the --help usage block (DOC)
- Edit `/workspaces/speccraft/tests/e2e/run.sh` (usage block at lines 42-43):
  add one `echo` line after the `--language-only` description, e.g.
  `echo "  CLAUDE_MODEL       env var: model passed to claude -p (default claude-sonnet-4-6)"`.
  Does not affect the probe or any AC; pure discoverability. (AC4: usage text is
  not a claude invocation, settings file, or workflow env — unaffected-jobs
  guarantee holds.)

### Step 4 — Mark the spec.md "What" snippet illustrative + record validation gate (DOC)
- Edit the active spec's `spec.md`:
  - Annotate the fenced code block in `## What` to state it illustrates only the
    inserted `--model` line; the surrounding redirect and `|| { ... exit 3 }`
    failure path are unchanged.
  - Add a one-sentence note (in `## What` or a short `## Validation` aside) that
    the next `e2e-devcontainer` run on `main` is the Sonnet-sufficiency gate, and
    that the recovery path is `CLAUDE_MODEL` (local-only) or a run.sh default
    change / manual re-run for CI.

### Step 5 — Rename the spec slug + title (REFACTOR / housekeeping, do last)
- Rename directory `/workspaces/speccraft/specs/0017-option/` →
  `/workspaces/speccraft/specs/0017-e2e-default-model/` (use `git mv`).
- Update `title:` frontmatter in spec.md from `"option"` to
  `"e2e default model"` and the `# Spec 0017 — option` heading.
- Update `.speccraft/state.json` `active_spec` via `speccraft-state set`
  (`0017-option` → `0017-e2e-default-model`); the single-writer rule forbids
  editing state.json directly. Stale session file-paths self-heal on the next
  PostToolUse write.
- Update `/workspaces/speccraft/.speccraft/index.md:38`: `specs/0017-option/`
  → `specs/0017-e2e-default-model/`.
- Sequenced LAST so earlier steps reference stable paths; the probe and run.sh
  edits are path-independent of the spec dir, so the rename cannot break them.
  All tests (the capture probe) still pass after the rename — the rename touches
  no code under test.

## Delegation

- All steps are Bash + Markdown edits in this repo; no specialist agent needed.
  Keep in-thread.

## Risk

- Risk: Sonnet 4.6 underperforms on the lifecycle's structural assertions →
  mitigation: the next `e2e-devcontainer` run on `main` is the validation gate;
  recover by overriding `CLAUDE_MODEL` locally or reverting the run.sh default.
- Risk: grep escaping for `${...}` in check #4 is wrong and the probe passes/fails
  spuriously → mitigation: RED step proves the probe fails before the run.sh edit;
  GREEN step proves it passes after — the two-sided RED→GREEN confirms the regex.
- Risk: the spec-dir rename desyncs state.json / index.md pointers →
  mitigation: rename is a single late step that updates the directory, the
  state.json active_spec (via speccraft-state), and index.md together; `git mv`
  preserves history.
- Risk: accidental disturbance of the `> "$LOG_DIR/$log" 2>&1` redirect or the
  `exit 3` failure path during the insert → mitigation: probe checks #2 and #3
  already pin both and would fail; insert is a single new line above
  `--permission-mode`.

## Rollback

- Revert the one-line insert in run.sh (Step 2) and check #4 in the probe
  (Step 1); the harness returns to inheriting the CLI default model. Doc steps
  (3-5) are independently revertable and carry no behavioral risk.
