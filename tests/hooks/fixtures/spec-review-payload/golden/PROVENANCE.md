# aux-delegator-nonreview.golden

Every line of `agents/aux-delegator.md` naming a non-review task mode
(`implement` or `analyze`), captured verbatim. Spec 0052 added it so the review
path could be rewritten freely while proving the non-review instructions did
not drift **as a side effect**.

Regenerate with:

```sh
grep -iE 'implement|analyze' agents/aux-delegator.md \
  > tests/hooks/fixtures/spec-review-payload/golden/aux-delegator-nonreview.golden
```

## Changes

- **Spec 0052** — created.
- **Spec 0054 (T61)** — one line updated: the agent's own input parameter was
  renamed `mode` → `task_mode`.

  Not a side effect; the point of the change. `aux-delegator` took a `mode`
  parameter of `review | implement | analyze` while an `agents.toml` entry
  carries a `mode` of `cli | acp | codex-plugin | subagent`. Two unrelated
  things under one word, in the file that reads both — and that exact
  conflation produced a live defect earlier in spec 0054, where
  `/speccraft:spec:review` passed a registry *transport* where a *dispatch
  mode* was expected and the attestation validator was handed the wrong
  vocabulary.

  Safe to rename: no caller passes the parameter by that name. The review path
  passes `payload_file`, `input_mode` and `cwd`
  (`commands/spec/review.md`), and `/speccraft:spec:delegate` passes a task and
  a context slice. Pinned by `review-only-mode-refusal.bats`, which now
  requires BOTH senses to be named and the bare `- \`mode\`:` input to be gone.

  `tests/hooks/spec-review-payload.bats` itself is byte-unchanged, as spec
  0054's close gate (T71) requires; only this fixture moved.
