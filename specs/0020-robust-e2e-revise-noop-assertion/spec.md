---
id: "0020"
title: "Robust e2e revise no-op assertion"
status: closed
created: 2026-06-15
authors: [claude]
packages: []
related-specs: ["0014", "0015"]
---

# Spec 0020 — Robust e2e revise no-op assertion

## Why

The e2e lifecycle test step `[6/13] /speccraft:spec:revise no-op (AC6)` in
`tests/e2e/run.sh` failed in CI even though the `/speccraft:spec:revise` no-op
path behaved correctly (revision stayed at 1, nothing archived, frontmatter
untouched). The failure was purely an assertion-brittleness problem: line 289
does a fixed-string grep for `"no changes"` against the live `claude -p` output
log, but that log captures the model's free-text final message. The command's
no-op branch emits a deterministic marker (`revise.md` →
`echo "no changes — spec unchanged"`), yet the model paraphrased the outcome as
"no-op" / "byte-identical" instead of relaying the literal marker, so the grep
missed.

This is the exact failure class spec 0014 named: asserting on nondeterministic
model prose rather than on a structural/deterministic signal. The structural
proof that the no-op branch (not the real-change branch) ran already exists at
`run.sh:291` (`revision: 1` unchanged). The text assertion should be made
tolerant of phrasing so a correct no-op stops failing CI on wording alone.

## What

Loosen the no-op text assertion in `tests/e2e/run.sh` step [6/13] so it
tolerates the natural phrasings a model uses to report a no-op, while the
existing structural check (`revision: 1` not bumped) remains the load-bearing
proof. Replace the fixed-string `contains` call with a `contains_regex` call
whose pattern matches the command's deterministic marker AND the common
model paraphrases ("no-op", "byte-identical", "unchanged").

Concretely, change `run.sh:289` from:

```sh
contains "$LOG_DIR/06-revise-noop.log" "no changes"
```

to a tolerant extended-regex match, e.g.:

```sh
contains_regex "$LOG_DIR/06-revise-noop.log" "[Nn]o.?op|[Nn]o changes|byte-identical|unchanged"
```

No change to the command (`commands/spec/revise.md`) or its deterministic
`echo`; the brittleness lives in the test assertion, and per spec 0017's lesson
hardening model-output compliance is not a durable fix.

## Acceptance criteria

1. `tests/e2e/run.sh` step [6/13] uses `contains_regex` (not the fixed-string
   `contains`) for the `06-revise-noop.log` assertion, and the regex matches all
   of: the deterministic marker `no changes — spec unchanged`, the paraphrase
   `no-op`, and `byte-identical`.
2. The existing structural assertion that revision is NOT bumped
   (`contains_regex "$SPEC_DIR/spec.md" "^revision: 1"` at the no-op step) is
   retained unchanged — it remains the load-bearing proof the no-op branch ran.
3. `bash -n tests/e2e/run.sh` parses cleanly (no syntax error introduced), and
   the `contains_regex` helper invoked is the existing one defined in
   `tests/e2e/lib.sh` (no new helper required).

## Out of scope

- Editing `commands/spec/revise.md` or `commands/spec/revise.lib.sh` — the
  command's deterministic marker is correct; only the test assertion changes.
- Any other e2e step assertion, and the `--language-only` fixtures.
- Adding a case-insensitive variant helper to `lib.sh` (the explicit `[Nn]`
  character classes in the regex cover the observed capitalizations without a
  new helper).
- Re-running the credit-gated `e2e-devcontainer` CI job as a close gate (it is
  model-nondeterministic; the fix is verified by the structural assertions and
  `bash -n`, mirroring the doc-only/oracle close-gate convention).

## Open questions

_none_
