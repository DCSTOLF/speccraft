---
id: "0017"
title: "e2e default model"
status: in-progress
created: 2026-06-11
authors: [claude]
packages: []
related-specs: []
---

# Spec 0017 — e2e default model

## Why

The only CI job that actually invokes Claude — `e2e-devcontainer` in
`.github/workflows/ci.yml` — runs `claude -p` through the `run_claude` helper in
`tests/e2e/run.sh` with **no `--model` flag**, no `ANTHROPIC_MODEL` env var, and
no `model` key in any settings file. With nothing specified, `claude -p` falls
back to the account/CLI default, currently **Opus 4.8**. Running the full e2e
lifecycle (init → new → review → revise → plan → TDD → close, ~10 `claude -p`
calls) on Opus is unnecessarily expensive for routine CI; Sonnet 4.6 with its
standard 200k context window is sufficient for the harness's structural
assertions. We want a cheaper default that is still overridable when a run needs
a different model.

## What

Apply "option 1" from the diagnosis: add a `--model` flag to the `run_claude`
invocation in `tests/e2e/run.sh` (the `"$CLAUDE_BIN" -p \` block, currently at
line 173), defaulting to `claude-sonnet-4-6` but overridable via a `CLAUDE_MODEL`
environment variable:

```bash
"$CLAUDE_BIN" -p \
  --model "${CLAUDE_MODEL:-claude-sonnet-4-6}" \
  --permission-mode bypassPermissions \
  --output-format text \
  --plugin-dir "$PLUGIN_DIR" \
  "$prompt"
```

> The block above illustrates **only the inserted `--model` line**. The
> surrounding flags, the trailing `> "$LOG_DIR/$log" 2>&1` combined-capture
> redirect, and the `|| { ... exit 3 }` failure path (run.sh:177–189) are
> unchanged — they are load-bearing for the spec-0008 AC#5 `classify_claude_failure`
> classifier and the `test_run_claude_capture.sh` probe.

Because Sonnet's default context window is 200k (the 1M window is a separate
opt-in beta that nothing here enables), selecting `claude-sonnet-4-6` yields the
smaller context automatically — no extra flag is needed.

Scope is limited to the `run_claude` helper in `tests/e2e/run.sh`. The flag is
inserted as the first argument after `-p` so it applies to every lifecycle call
the harness makes.

**Validation gate.** Switching the default tier changes the model under test, so
the next `e2e-devcontainer` run on `main` is the Sonnet-sufficiency gate — it
exercises the full ~10-call lifecycle against Sonnet 4.6. If Sonnet regresses on
the harness's structural assertions, the recovery path is to override
`CLAUDE_MODEL` locally (the env var is intentionally not plumbed into CI per
Out-of-scope); a CI failure requires either reverting the run.sh default or a
manual re-run, since there is no CI-side override.

## Acceptance criteria

1. The `run_claude` function in `tests/e2e/run.sh` passes
   `--model "${CLAUDE_MODEL:-claude-sonnet-4-6}"` to the `"$CLAUDE_BIN" -p`
   invocation.
2. When the `CLAUDE_MODEL` environment variable is set to a non-empty value, the
   harness uses that value as the model (the default is not used).
3. When `CLAUDE_MODEL` is unset or empty, the harness uses `claude-sonnet-4-6`.
4. No other `claude` invocation, settings file, or CI workflow env is changed;
   the `e2e-language-only`, `unit-*`, and `hooks` jobs (which never call
   `claude`) are unaffected.

## Out of scope

- Adding a `model` key to `.claude/settings.json` (would change interactive
  sessions in this repo, not just CI).
- Setting `ANTHROPIC_MODEL` in `.github/workflows/ci.yml` env / `--remote-env`
  (option 2 from the diagnosis — rejected as less explicit at the call site).
- Enabling Sonnet's 1M-token context beta.
- Changing the model used by any subagent or cross-model reviewer.

## Open questions

_none_
