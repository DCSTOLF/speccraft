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
   `--model "${CLAUDE_MODEL:-claude-opus-4-8}"` to the `"$CLAUDE_BIN" -p`
   invocation. _(Amended 2026-06-12: default was `claude-sonnet-4-6`; see
   Amendment below.)_
2. When the `CLAUDE_MODEL` environment variable is set to a non-empty value, the
   harness uses that value as the model (the default is not used).
3. When `CLAUDE_MODEL` is unset or empty, the harness uses `claude-opus-4-8`.
   _(Amended 2026-06-12: default was `claude-sonnet-4-6`.)_
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

## Amendment (2026-06-12) — revert default to Opus 4.8 after Sonnet failed the validation gate

**Trigger.** The "Validation gate" above named the first `e2e-devcontainer` run
on `main` as the Sonnet-sufficiency gate. That run —
[27367642623](https://github.com/DCSTOLF/speccraft/actions/runs/27367642623),
commit `537b769`, the spec-0017 implementation — **failed** at step `[9/13] TDD
invariant` with a genuine assertion failure (no `ENVIRONMENT_FAILURE` tag):

```
==> [9/13] TDD invariant
FAIL: expected 'farewell' in main.go
Override granted. The next production file edit will bypass the TDD invariant. Reason logged in `tasks.md`.
```

On Sonnet 4.6 the model handled the GREEN prompt ("implement `farewell()` in
`main.go`") by invoking `/speccraft:spec:override` — unnecessary, since the test
was already written in step 9a and the TDD guard would have allowed the edit —
and then stalled without writing `farewell()`, so the `contains main.go:
farewell` assertion failed. This is a real model-behaviour difference, not an
environmental flake. (For contrast, the prior commit `4529323`'s e2e run
[27348320071](https://github.com/DCSTOLF/speccraft/actions/runs/27348320071), on
the Opus default, failed the same step only with `ENVIRONMENT_FAILURE:
credit_exhausted` — an env issue, not a defect.)

**Fix.** Revert the `run_claude` default from `claude-sonnet-4-6` to
`claude-opus-4-8`. The `CLAUDE_MODEL` override variable, the `--help`
documentation, and the `test_run_claude_capture.sh` check #4 are **retained** —
the default string is the only change. Anyone who wants Sonnet (or any other
model) for a local run still sets `CLAUDE_MODEL=...`.

**Rationale for folding-in (not a follow-up spec).** Per the mid-implementation
amendment convention, all three conditions hold: the edit is strictly bounded
(the default-model string in one line of `run.sh` plus its paired probe check),
CI stays red until it lands (the spec's own validation gate failed), and the
theme is identical (this spec's subject *is* the e2e default model). AC1 and AC3
above are updated in place to name `claude-opus-4-8`; AC2 and AC4 are unchanged.

**Net effect vs the pre-spec baseline.** The original "Why" (cheaper default) is
**not** achieved — Sonnet did not pass the gate. But the spec still delivers a
real improvement: model selection is now **explicit and pinned** in `run.sh`
rather than silently inherited from a mutable account/CLI default, and it is
**overridable** via `CLAUDE_MODEL`. This preserves the durable half of the
original motivation (CI should not inherit an account-level default — the point
codex raised in review) while honestly dropping the cost-optimization half that
the validation gate disproved.
