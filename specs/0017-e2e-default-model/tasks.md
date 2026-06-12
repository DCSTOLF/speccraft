---
spec: "0017"
---

# Tasks

- [x] T1 [RED] Add check #4 (`--model "${CLAUDE_MODEL:-claude-sonnet-4-6}"` grep) to `tests/e2e/assertions/test_run_claude_capture.sh`; probe exits 2 (line absent in run.sh) — covers AC1
- [x] T2 [GREEN] Insert `--model "${CLAUDE_MODEL:-claude-sonnet-4-6}" \` as first arg after `-p` in `run_claude()` at `tests/e2e/run.sh:173`; probe exits 0 — satisfies AC1 (AC2/AC3 by `${VAR:-default}` semantics, no behavioral test)
- [x] T3 [DOC] Add a `CLAUDE_MODEL` line to the `--help` usage block in `tests/e2e/run.sh:42-43` — discoverability; AC4 (unaffected jobs unchanged)
- [x] T4 [DOC] Mark the `## What` code snippet in `spec.md` as illustrating only the inserted `--model` line, and add the `e2e-devcontainer` Sonnet-sufficiency validation-gate + recovery-path note
- [x] T5 [REFACTOR] Rename `specs/0017-option/` → `specs/0017-e2e-default-model/` (git mv), update spec.md title/heading, `.speccraft/state.json` active_spec (via `speccraft-state set`), and `.speccraft/index.md:38`; probe still passes — fixes the slug/title convention violation

## Amendment 2026-06-12 — revert default to Opus after Sonnet failed the validation gate

- [x] T6 [RED] Point check #4 in `tests/e2e/assertions/test_run_claude_capture.sh` at `claude-opus-4-8`; probe exits 2 (run.sh still has sonnet) — amended AC1/AC3
- [x] T7 [GREEN] Change `run_claude` default in `tests/e2e/run.sh` to `--model "${CLAUDE_MODEL:-claude-opus-4-8}"` and update the `--help` `CLAUDE_MODEL` line; probe exits 0 — satisfies amended AC1/AC3, CLAUDE_MODEL knob retained
- [x] T8 [DOC] Record the amendment in `spec.md` (trigger: failed run 27367642623; fix; fold-in rationale; net-effect-vs-baseline) and update AC1/AC3 in place
