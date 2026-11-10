# Codex companion 1.0.6 — verified interface (spec 0054, T1)

Read on 2026-11-10 against the installed tree at
`~/.claude/plugins/cache/openai-codex/codex/1.0.6`
(marketplace `openai-codex` = `openai/codex-plugin-cc`, plugin sha `db52e28`,
`.claude-plugin/plugin.json` → `"version": "1.0.6"`).

`codex-plugin-readme-1.0.6.md` beside this file is the upstream README, vendored
byte-exact from `~/.claude/plugins/marketplaces/openai-codex/README.md` so a
later `diff` against upstream stays meaningful. It documents the *user-facing*
commands; everything below was read from the source, because the README does
not describe these payloads and the usage text actively understates the
accepted flags. (The plugin package itself ships no README — only the
marketplace checkout has one.)

## What the spec claimed, and what the source says

Every line reference in spec.md was checked. Four held exactly:

| spec.md claim | Verdict |
|---|---|
| `printUsage` line 82 is the `task` line and omits `--prompt-file`, `--cwd`, `--json` | **Confirmed**, verbatim — see `printusage-1.0.6.txt` |
| `handleTask` accepts all three anyway | **Confirmed**: `codex-companion.mjs:764` `valueOptions: ["model","effort","cwd","prompt-file"]`, `booleanOptions` includes `json` |
| `runAppServerTurn` trims the prompt (`codex.mjs:1127`) | **Confirmed**: `options.prompt?.trim() \|\| options.defaultPrompt \|\| ""` |
| `buildResultStatus` is numeric, never `"completed"` (`codex.mjs:754`) | **Confirmed**: `turnState.finalTurn?.status === "completed" ? 0 : 1` |

Also confirmed: `setup --json` really does expose `ready`, and it is exactly
`node && codex && auth` (`codex-companion.mjs:203`), and `-C` aliases to `cwd`
(`:145`).

One claim did **not** hold — see below.

## The output shape depends on foreground vs background

This is the discrepancy. spec.md §Output says `--json` emits a flat
`{status, threadId, rawOutput, touchedFiles, reasoningSummary}` and that
`review_parse_codex_task_output` "extracts `rawOutput`". That is the
**foreground** `task --json` shape (`codex-companion.mjs:511-517`).

But spec.md §Command mandates the **background** lifecycle
(`task --background` → poll `status` → `result`), and `handleResult`
(`:910-925`) emits:

```
{ job, storedJob }
```

with the flat payload stored one level down as `storedJob.result`
(`tracked-jobs.mjs:166` → `result: execution.payload`). The renderer agrees:
`render.mjs:402` reads `storedJob?.result?.rawOutput`.

So on the path the spec actually mandates:

- `rawOutput` is at **`.storedJob.result.rawOutput`**, not top level;
- the numeric success status is at **`.storedJob.result.status`**.

`task-success-1.0.6.json` pins the real nested shape. A parser written against
spec.md §Output as literally written would read `undefined` on every live run.

## Two different fields named `status`

A trap worth stating plainly, because the two are at different depths, carry
different types, and the spec's warning applies to only one of them:

| Path | Type | Values |
|---|---|---|
| `.job.status` / `.storedJob.status` | string | `queued`, `running`, `completed`, `failed`, `cancelled` |
| `.storedJob.result.status` | **number** | `0` success, `1` otherwise |

spec.md:189's "it is never the string `completed`" is true of the **inner**,
numeric one. The outer job status is the string `"completed"` and that *is*
the success value. A reviewer that checks `.status == "completed"` against the
launch payload also reads the string `"queued"` (`:700-709`), which is neither
terminal nor a verdict.

Terminal states are enumerated by the companion itself, not inferred:
`job-control.mjs:262` → `completed | failed | cancelled`. Active:
`queued | running` (`codex-companion.mjs:291`).

## `status` can wait natively

`handleStatus` (`:883-887`) accepts `--wait`, `--timeout-ms` and
`--poll-interval-ms`, none of which appear in the usage text. The spec's own
fixed-5s poll loop is still what AC6 specifies; this is noted only so the
choice is a decision rather than an oversight. `status --wait` requires a job
id (`:902-904`).

## Fixtures here

- `printusage-1.0.6.txt` — captured verbatim from
  `node .../codex-companion.mjs help` (exit 0, 9 lines, one trailing `\n`).
  AC5a's regression floor: a companion whose help text omits the three flags
  must still resolve, so re-introducing a help-text probe fails loudly.
- `task-success-1.0.6.json` — the real `result <job-id> --json` shape,
  including both `status` fields and a payload-shaped `rawOutput`.
- `stub-node.sh` — stands in for `node` on PATH; dispatches on the companion
  subcommand so the adapter can be tested with no plugin, no auth and no
  network. Knobs are documented in its header; `STUB_CODEX_ARGV_LOG` is the
  argv assertion surface for AC6, and `STUB_CODEX_CANCEL_CONFIRMS=0` drives
  the `codex-cancel-unconfirmed` path.
