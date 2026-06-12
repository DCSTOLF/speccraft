---
spec: "0017"
closed: 2026-06-12
---

# Changelog — 0017 e2e default model

## What shipped vs spec

- Pinned the model used by the e2e lifecycle harness explicitly at the call
  site: `run_claude()` in `tests/e2e/run.sh` now passes
  `--model "${CLAUDE_MODEL:-claude-opus-4-8}"` as the first argument after `-p`,
  applying to every `claude -p` lifecycle call. Before this spec the harness
  passed no `--model`, silently inheriting the mutable account/CLI default.
- Added an `env:` block to the `--help` usage output documenting `CLAUDE_MODEL`
  (default `claude-opus-4-8`, spec 0017) and `CLAUDE_BIN`.
- Extended the spec-0008 capture probe `tests/e2e/assertions/test_run_claude_capture.sh`
  with check #4, a `grep -qE` against the extracted `run_claude` body pinning the
  `--model "${CLAUDE_MODEL:-claude-opus-4-8}"` line.
- **Deviation from the as-reviewed spec (mid-implementation amendment,
  2026-06-12).** The reviewed-and-approved spec defaulted the model to
  `claude-sonnet-4-6` — the cost-optimization thesis. Both cross-model reviewers
  (codex, claude-p) returned approve-with-comments and explicitly flagged that
  switching the default tier changes the model under test with no evidence Sonnet
  passes the ~10-call lifecycle; claude-p named the next `e2e-devcontainer` run as
  the validation gate. That gate run
  ([27367642623](https://github.com/DCSTOLF/speccraft/actions/runs/27367642623),
  commit `537b769`) **failed** at `[9/13] TDD invariant` with a genuine assertion
  failure (no `ENVIRONMENT_FAILURE` tag): on Sonnet 4.6 the model reached for
  `/speccraft:spec:override` on the GREEN step — unnecessary, the test was already
  written — then stalled without implementing `farewell()`, so
  `contains main.go: farewell` failed. The amendment reverted the default to
  `claude-opus-4-8` (commit `a016dae`) and updated AC1/AC3 in place; the
  `CLAUDE_MODEL` override var, the `--help` docs, and probe check #4 were all
  retained. The cost-optimization goal was **not** achieved.
- **Net effect vs the pre-spec baseline:** the harness's model selection is now
  explicit and pinned in `run.sh` (no longer silently inheriting a mutable
  account/CLI default) and overridable via `CLAUDE_MODEL` — the durable half of
  the motivation, which was codex's stronger framing. The cheaper-default half was
  honestly dropped after the validation gate disproved Sonnet sufficiency.

## Files touched

- `tests/e2e/run.sh`
- `tests/e2e/assertions/test_run_claude_capture.sh`
- `.speccraft/index.md` (active-spec pointer; flips back to `none` at close)
- `specs/0017-e2e-default-model/{spec.md,plan.md,tasks.md,review.md}` (spec's own dir)

## Close gate

CI run [27386675522](https://github.com/DCSTOLF/speccraft/actions/runs/27386675522)
on commit `a016dae` (Opus default) is fully green including `e2e-devcontainer`.
