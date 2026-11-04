---
id: "0054"
title: "Review dispatch modes: codex-plugin and Claude subagent reviewers for every review command"
status: in-progress
created: 2026-10-02
revision: 0
authors: [claude]
packages: ["commands/spec", "commands/arch", "commands/pm", "agents", "templates/speccraft", "templates/prompts", "skills/aux-agents", "tools/internal/delegate", "tests/hooks", ".speccraft"]
related-specs: ["0011", "0035", "0050", "0052"]
domains: [external-tool-boundaries, spec-lifecycle]
---

# Spec 0054 — Review dispatch modes: `codex-plugin` and `subagent`

## Why

`.speccraft/agents.toml` knows two ways to reach a reviewer, `mode = "cli"`
(shell out to a command) and `mode = "acp"` (go through `acpx`). Both are
**shell-outs to a standalone binary**. Two reviewer sources that are now
routinely present in a Claude Code session cannot be named at all:

- **The Codex plugin for Claude Code** (`codex@openai-codex`, upstream
  `openai/codex-plugin-cc`). It wraps the Codex app server and carries the
  user's Codex auth, config (`~/.codex/config.toml`, project `.codex/config.toml`),
  job tracking and thread persistence. Reaching Codex via `cli` mode today
  (`codex exec …`) bypasses all of that and duplicates the model/effort knobs.
- **A Claude Code subagent.** A same-session reviewer needs no external binary,
  no auth, and no argv/stdin transport; with a distinct `model` it is a genuine
  second opinion. `claude -p` in `cli` mode is the only route today — a new
  process, a second auth path, and (measured on round 1 of this spec's own
  review) a non-interactive permission context that refused every hashing
  command, so its verdict was `attestation-failed`.

And only one review command uses the registry properly. `spec:review` has the
spec 0052 round (compose → budget-check → dispatch → outcomes → attestation);
`arch:review` and `pm:review` say "the same multi-model backend
`/speccraft:spec:review` uses, unchanged" with no runbook, so the model running
them improvises dispatch; `spec:review-code` loops "each enabled agent" through
`aux-delegator` with no notion of mode, budget or attestation.

### Which Codex entry point

The plugin exposes `/codex:review`, `/codex:adversarial-review`,
`/codex:rescue`, and the runtime they share,
`scripts/codex-companion.mjs`. Read against the installed 1.0.6 source:

| Entry point | What it reviews | Fit |
|---|---|---|
| `/codex:review` | git diff (working tree or `--base`) under Codex's built-in reviewer; **rejects** focus text | ✗: cannot be pointed at a spec, design, brief, or guardrails |
| `/codex:adversarial-review` | a git diff **it collects itself** + a short focus string, under a fixed prompt; output schema `approve \| needs-attention` with no room for digests | ✗: its `working-tree` scope reviews staged and unstaged changes separately and includes untracked files, so it reviews a different change than `git diff HEAD`; it cannot carry speccraft's payload, so attestation can never pass |
| `/codex:rescue` | a Sonnet forwarder subagent around `companion task` | ✗: defaults to `--write`; may rewrite the prompt; model re-types the payload into argv; may resume the prior thread |
| `companion task` | the prompt handed to it via `--prompt-file`; read-only and a fresh thread unless told otherwise | **✓ for all four review commands** |

`companion task` is **not** byte-exact: `runAppServerTurn` sends
`options.prompt?.trim()` (`scripts/lib/codex.mjs:1127` in 1.0.6). This spec
states that transformation and makes it harmless rather than claiming
byte-exactness (§2).

### Relationship to the External-tool boundaries convention (spec 0011)

That convention forbids speccraft from telling the model *which* external tool
to use where the tool owns its own routing. A dispatch adapter for a mode the
**user** wrote into their own `agents.toml` is different: the user chose the
tool; speccraft owns how its own review round reaches it — exactly as
`aux-delegator` already shells to `codex exec`. This spec adds that distinction
to `conventions.md` explicitly (AC24) so the implementation and the memory agree.

## What

### 1. Two new registry modes

`mode` gains `"codex-plugin"` and `"subagent"`. Valid modes: `cli | acp |
codex-plugin | subagent`. An **omitted** `mode` key normalizes to `cli`
(today's behaviour, unchanged); an **explicitly empty** or unrecognised value
(including case variants such as `Subagent`) is a named error at registry load,
in both the Go loader (`tools/internal/delegate`) and the shell reader
(`review.lib.sh`).

Per-mode fields:

| mode | optional fields |
|---|---|
| `codex-plugin` | `model`, `effort` (`none\|minimal\|low\|medium\|high\|xhigh`), `plugin_root` |
| `subagent` | `subagent_type` (default `speccraft:reviewer`), `model` (`opus\|sonnet\|haiku\|fable\|inherit`, default `inherit`) |

**Strict keys apply to the new modes only.** On a `codex-plugin` or `subagent`
entry, `cmd`, `input`, `acp_agent`, and the other new mode's fields are named
errors. `cli` and `acp` entries keep today's permissive decoding — unknown keys
(e.g. `install_hint`) stay ignored — so no existing host registry stops
loading (the opt-out convention for host-owned config). `reference_read`,
`strengths`, `enabled` apply to every mode; the Go `Agent` struct gains the
fields it reads (`ReferenceRead`, `Model`, `Effort`, `PluginRoot`,
`SubagentType`).

### 2. `codex-plugin` dispatch (all four commands)

**Plugin location.** `plugin_root` if set; else from
`~/.claude/plugins/installed_plugins.json`, key `codex@openai-codex`: the
entry with `scope: "local"` whose `projectPath` equals the repo root, else the
`scope: "user"` entry; the root is that entry's `installPath`. The root must
contain `scripts/codex-companion.mjs`.

**Capability check: version + readiness, never help text.** Round 2 confirmed
that 1.0.6's `printUsage` (line 82) omits `--prompt-file`, `--cwd` and `--json`
even though `handleTask` accepts all three. A help-text probe therefore fails
**closed against the one install this spec targets**, so it is rejected
outright. The supported-interface check is instead:

1. the companion's `version` lies in the supported range, which **starts at
   1.0.6** (the lowest version whose `handleTask` is known to accept this
   spec's argv). **Where that version comes from depends on how the root was
   resolved**, and both routes must have one — an explicit `plugin_root` wins
   resolution and may have no `installed_plugins.json` entry at all, so
   sourcing the version only from that file would make a valid explicit root
   permanently `unknown-version` with no satisfiable configuration:
   - root from `installed_plugins.json` → that entry's `version`;
   - root from an explicit `plugin_root` → the `version` in the
     **companion-owned manifest** at `<root>/.claude-plugin/plugin.json`.
   A root present in both is read from `installed_plugins.json`, so one
   resolution path yields one version. Below the range →
   `codex-plugin-unavailable: unsupported-companion <version>`; an absent or
   unparseable version → `codex-plugin-unavailable: unknown-version`. At or
   above the range the companion is accepted, forward-compatibly.
   These two are **sibling reasons, never concatenated**: the reason token is
   exactly one of `not-installed`, `companion-missing`,
   `unsupported-companion <version>`, `unknown-version`, so the named error is
   reproducible and greppable;
2. `node <root>/scripts/codex-companion.mjs setup --json` runs as the
   availability and auth preflight; its `ready` field (node + codex + auth)
   must be true. This is the structured missing/unauthenticated signal —
   `ready: false` maps to
   `codex-plugin-unavailable: not-ready <reason from setup>`, never to
   `codex-output-unparseable`.

   **Preflight is cached per canonical resolved plugin root, not per round.**
   `plugin_root` is a per-agent field, so two `codex-plugin` entries in one
   round can resolve to different installations, versions or auth states;
   preflighting "once per round" would establish readiness for one and assume
   it for the other. The cache key is therefore the **symlink-resolved
   absolute root**, and the version check of (1) is keyed the same way. Two
   agents sharing a root preflight once between them; two agents with
   different roots preflight once each, and either can be
   `codex-plugin-unavailable` while the other proceeds.

A fixture pins 1.0.6's **real** `printUsage` text, and asserts that a companion
whose help output omits `--prompt-file`/`--cwd`/`--json` still resolves
successfully. That test exists so that re-introducing a help-text probe fails
loudly (AC5).

**Command: a background job, polled.** A foreground `task` cannot be cancelled.
Round 2 confirmed the companion spawns the Codex broker **detached and
`unref`'d**, that closing its socket only clears ownership while the turn keeps
running, and that only `companion cancel <job-id>` reaches
`interruptAppServerTurn`. Killing the companion's process group therefore proves
the local caller stopped, not that the reviewer stopped. So the adapter uses the
job lifecycle:

```
node <root>/scripts/codex-companion.mjs task --background --fresh --json \
     --prompt-file <payload> --cwd <repo-root> [--model <model>] [--effort <effort>]
```

which returns a job id. The adapter then polls
`status <job-id> --json` on a fixed interval (5 s) until the job reports
terminal state or `review_timeout_s` elapses, retrieves the output with
`result <job-id> --json`, and on deadline expiry runs `cancel <job-id> --json`
and **confirms** cancellation via one further `status <job-id> --json` before
recording `<agent> timeout`. A cancel that does not confirm is
`<agent> failed codex-cancel-unconfirmed <job-id>`, which names the job so an
operator can finish the job off by hand — a reviewer that may still be running
is never silently treated as merely timed out.

Never `--write`, `--resume`, `--resume-last`. The payload is the round's
materialized artifact, passed by path. Background jobs are in scope **only** for
this adapter's own dispatch; speccraft never adopts, resumes or reports on a
Codex job it did not start.

**The one transformation.** The companion trims leading and trailing
whitespace. `review_compose_payload` already controls both ends; this spec
pins that every composed payload **begins with a non-whitespace byte and ends
with exactly one `\n`**, so the companion's trim removes exactly that final
newline and nothing else. The budget measures the untrimmed artifact (an
upper bound on what is sent). Digest attestation is over reference files, not
the payload, and is unaffected.

**Output.** `--json` emits `{status, threadId, rawOutput, touchedFiles,
reasoningSummary}`. **`status` is a number, not a string**: round 2 confirmed
`buildResultStatus` yields `0` on success and `1` otherwise
(`scripts/lib/codex.mjs:754` in 1.0.6) — it is never the string `"completed"`.
Success is therefore all three of: `status === 0` (numeric), a **zero exit
code**, and a **non-empty `rawOutput`**.

`review_parse_codex_task_output` extracts `rawOutput` as the response.
Distinct failure cases, so a transport fault is never mistaken for a verdict:

The table is **total over the three inputs** (exit status, JSON validity,
field contents), so no combination is left to an implementer's judgement:

| Condition | Outcome |
|---|---|
| zero exit, valid JSON, `status === 0`, non-empty `rawOutput` | the response (success) |
| **non-zero exit, with stdout that IS valid success-shaped JSON** | `failed codex-task-error` |
| non-zero exit, with stdout that does not parse as JSON | `failed codex-task-error` (stderr excerpt attached by the caller — see below) |
| zero exit, `status` non-zero, empty `rawOutput`, or valid JSON missing either field | `failed codex-output-unparseable` |
| non-empty `touchedFiles` | `failed codex-wrote-files`, **even with a valid verdict in `rawOutput`** |

The second row is the quadrant that matters and the one easiest to get wrong:
a companion that printed a well-formed result **and then exited non-zero** has
had a transport failure, and this spec's standing rule is that a transport
failure never becomes a verdict. Accepting the response because it "looks
fine", or filing it under `codex-output-unparseable` when the output parsed
perfectly well, are both wrong; it is a `codex-task-error`. `touchedFiles`
wins over every other row.

A read-only reviewer that wrote is a defect, never a verdict. The extracted
response then goes through the same verdict parse and
`review_validate_reference_access` as any other reviewer.

**Who holds which bytes.** `review_parse_codex_task_output` is given the
stdout file and the exit status, and **nothing else**: it classifies, and it
never reads stderr. The **caller** captures stderr to its own file during the
companion invocation and, on a `codex-task-error` classification, attaches the
excerpt to the recorded outcome afterwards. Stated explicitly because 0052's
convention is to pin which component holds which bytes rather than leave a
"(stderr excerpt recorded)" parenthesis to be guessed at.

**Timeout.** The polling loop above bounds the job by `review_timeout_s`. Each
individual companion invocation (`setup`, `task`, `status`, `result`, `cancel`)
additionally runs under a portable deadline wrapper (macOS has no
`timeout(1)`), so a hung companion process cannot stall the round; expiry of
the **job** deadline goes through `cancel <job-id>` + confirmation as above,
not through a process-group kill.

**Unavailable.** Plugin not installed, root unresolvable, version outside the
supported range, `node` absent, or `setup --json` reporting `ready: false`
(Codex missing or unauthenticated) → `<agent> failed codex-plugin-unavailable
<reason>` and a message pointing to `/codex:setup`. Never a fallback to
`codex exec`. Other reviewers still run.

### 3. `subagent` dispatch and the shipped `speccraft:reviewer`

Bash cannot call the Agent tool, so a `subagent` reviewer is dispatched by the
**orchestrating session**, not by `aux-delegator`. The shared runbook says so
per mode.

**Persistent, in-repo round directory.** Spec 0052 runs the round in one shell
with a temp dir trapped to it; a subagent dispatched between tool calls would
find its payload deleted, and a payload under `$TMPDIR` is outside the
project's permission scope. The round directory therefore becomes
`<repo-root>/.speccraft/.review-rounds/<kind>-<id>-<unix-ts>-<rand>/`, mode
0700. Its path is printed for the runbook to carry across tool calls.
`review_round_cleanup <dir>` removes it once every reviewer is **proven
terminal** — see "Quarantine" below, which is what "proven" excludes. Path
checks resolve symlinks on both sides before comparing (spec 0050 defect A).
`cli`/`acp`/`codex-plugin` read from the same directory.

**Published atomically with its lease.** `mkdir` followed by a separate
lease write is two steps, and the sweep's "missing lease ⇒ reclaim" rule
(below) turns the window between them into the deletion of a live round. So
`review_round_dir_create` builds the directory under the temporary name
`.building-<expiry-unix-ts>-<rand>` **inside** `.speccraft/.review-rounds/` (so
it is already ignored and on the same filesystem, which is what makes the `mv`
atomic), writes the `lease` into it, and only then `mv`s it to its final name.

**The build expiry is in the name, so it survives abandonment.** A half-built
directory has no `lease` to read — that is what makes it reclaimable — so a
sweep that had to *compute* its threshold would have nowhere to get
`review_timeout_s` from, and two concurrent rounds with different timeouts
would make any config read ambiguous. The name therefore carries the
**absolute expiry** (`now + review_timeout_s + 300`), fixed at `mkdir` time
**before any fallible setup**, so the single most-likely-to-be-abandoned state
is already self-describing. `review_round_sweep` reads the threshold off the
directory name and needs no configuration, no lease and no argument.
A round dir is therefore never visible to a sweep without its lease, and the
sweep may treat a lease-less dir as abandoned without racing a creator.

The `.building-` prefix is recognizable on purpose: `review_round_sweep`
reclaims a `.building-*` directory once **the expiry encoded in its own name**
has passed. That expiry is one lease period — `review_timeout_s + 300 s`, the
same quantity a lease's expiry is built from — but the sweep never recomputes
it; it reads it. This is not a reversal of the lease rule (a published round
always has a lease) but the stated exception to it, named in
`review_round_sweep`'s contract so the two rules cannot be confused.

`review_round_dir_create` takes `review_timeout_s` as an explicit parameter,
since the lease duration derives from it. The `*` `.gitignore` it writes at
`.review-rounds/` is itself written **same-dir temp + rename** (the
`AtomicWriteFile` convention already used elsewhere), so two concurrent rounds
racing on that idempotent write cannot expose a truncated file.

**Ignored without migration.** A rule added to the template's `.gitignore`
would reach only repos that re-run `/speccraft:init` after this change, leaving
the whole installed base able to commit round payloads via `git add -A`. So
`review_round_dir_create` instead writes `.speccraft/.review-rounds/.gitignore`
containing a single `*` line at creation time, idempotently. That ignores every
round dir, and the file itself, in **any** host repo with no migration step and
no template dependency. (This is the opt-out shape spec 0052's convention asks
for: protection is the default and arrives with the mechanism, not with a
re-init.)

**Lease, not age: sweeping is liveness-based.** Sweeping by mtime alone can
delete the payload of a round that is still running — a Codex reviewer can take
ten minutes and touches nothing meanwhile. Each round dir therefore carries a
`lease` file written at creation, holding an absolute expiry of
`start + review_timeout_s + 300 s` of margin. `review_round_sweep` deletes a
round dir **only** when its lease has expired, or when the lease file is
missing or unparseable (a dir from a crashed older version, no longer a
creation race — see "Published atomically" above); it never deletes on age
alone.

**The lease is never renewed, because no path needs it to be.** A lease is
written once, at creation, and is never re-stamped; there is no
`review_round_lease_renew`. Every path a round can take is already bounded
*inside* the expiry, or is covered by quarantine rather than by the lease:

| path | what bounds it |
|---|---|
| `codex-plugin` polling | stops at `review_timeout_s`; the lease runs to `+300 s` |
| `codex-plugin` cancel + confirm | one `cancel` and one `status`, each under `review_with_deadline` — tens of seconds, far inside the margin |
| `codex-plugin` unconfirmed cancel | **quarantine**, which retains the dir past lease expiry by its own rule |
| `subagent` | bounded by the same `review_timeout_s` deadline, then `TaskStop` |
| `subagent` stop-failed | **quarantine**, as above |
| `cli`/`acp` | run under `review_with_deadline <review_timeout_s>` |

So the `+300 s` margin plus the quarantine rule cover the full lifecycle, and a
renewal helper would have no caller. **Forward constraint:** a future
unbounded phase must either bound itself or quarantine; it may not rely on
extending a lease. (Why renewal was tried and dropped is in Notes for the
plan — design history, not contract.)

**Handoff: the reviewer writes its own artifact.** The subagent receives the
payload **path**, never pasted content. It must read the payload, review, and
report `payload_sha256` of the payload file alongside the existing reference
digests.

It then **writes its own review output to `<round-dir>/<agent>.out`**, and the
orchestrator only reads that file. Having the orchestrator transcribe the Agent
tool result into `.out` would make "verbatim" an instruction rather than a
mechanism: the orchestrator is itself a model, and a paraphrased or summarized
transcription would still pass the hash-compare rule, which catches duplication
but not rewording. Removing the transcription hop removes that class of
infidelity entirely, and the 0052 distinct-artifact / hash-compare rule then
covers subagents like every other reviewer.

The cost is that `speccraft:reviewer` is no longer strictly read-only, so the
write surface is bounded on both sides:

- the agent's instructions confine `Write` to `<round-dir>/<agent>.out` and
  forbid every other path;
- after the round, a **post-round tree check** compares a **content-aware
  snapshot** of the tree outside the round dir against its pre-round value.
  Any change records `<agent> failed subagent-wrote-files` — the same
  treatment `touchedFiles` gets for `codex-plugin`, and a defect rather than a
  verdict.

  **Attribution when several subagents run concurrently.** The snapshot is one
  pre/post pair for the **whole round**, while the outcome is **per agent**,
  and subagent reviewers are launched in the background — so a mismatch proves
  a write happened but not *which* reviewer made it. (Structurally the same
  trap as 0052's distinct-artifact rule: a per-round mechanism being asked for
  a per-agent verdict.) The rule is therefore stated rather than left to an
  implementation that could blame one, all, or an arbitrary reviewer — each
  choice yielding different quorum results:

  "Active" is defined over the **snapshot interval** — a subagent that was
  live at any point between the pre- and post-round snapshots — because a
  snapshot pair yields no mutation timestamp and so cannot place a write at an
  instant. The rule must be stated over what the mechanism can actually
  observe:

  - exactly **one** subagent active during the interval → that agent records
    `failed subagent-wrote-files`;
  - **more than one** active during the interval, and the write surface cannot
    be attributed → **every** such subagent records
    `failed subagent-wrote-files <unattributed>`.

  Failing all of them is deliberate and is the safe direction: the outcome
  counts toward **neither** predicate, so the round becomes incomplete rather
  than accepting a verdict from a reviewer that may have written out of
  bounds. One misbehaving reviewer can therefore nullify its concurrent peers —
  accepted, because the alternative is trusting a verdict whose author cannot
  be cleared.

  **`codex-plugin` is attributable, not exempt.** The companion reports
  `touchedFiles` **per job**, so a codex-plugin reviewer's writes are
  self-attested and that attestation is **trusted** — which is why such a
  reviewer is not swept up in an `<unattributed>` failure caused by a
  subagent. A companion that under-reports its own `touchedFiles` is a
  different threat model (a lying tool rather than an unattributable one) and
  is out of scope here, as is a reviewer that lies about its reference digests
  — the same trust boundary 0052 drew with "a digest proves access, not
  attention".

  **Not `git status --porcelain`.** Porcelain text cannot carry this
  guarantee: editing an **already-dirty** tracked file leaves its ` M <path>`
  entry byte-identical, and adding a file beneath an **already-untracked**
  directory leaves the same collapsed `?? <dir>/` entry. Both are the common
  case during implementation, and both would let an out-of-bounds write pass.
  (Observed live while reviewing this spec: `git status --porcelain` reported
  `?? specs/0054-review-dispatch-modes/` as one collapsed entry, so any new
  file written inside it would have been invisible to a porcelain diff.) The
  snapshot is therefore: the **sha256 of every tracked file** whose path is
  outside the round dir, **plus the sha256 of every untracked regular file**
  (enumerated recursively with `git ls-files --others -z`, **per file, never
  `--directory`-collapsed** — a future "optimization" to a directory listing
  would silently reinstate the collapsed-`??` hole above), plus the path and
  type of every untracked non-regular entry (symlink, fifo, socket), which is
  recorded but not hashed.

  **Digests, not an inventory, on both sides.** A path inventory alone leaves a
  third hole next to the two above: a reviewer can **rewrite the bytes of an
  existing untracked file** while adding and removing nothing, so the
  inventory is identical before and after. (This repo carries untracked
  `codex-plugin-readme.md` during this very spec's review, so the case is not
  hypothetical.)

  **No `--exclude-standard`: ignored paths are inside the guarantee.**
  `--exclude-standard` filters **gitignored** paths, so with it a reviewer
  writing to an ignored path outside the round dir changes nothing the
  snapshot sees. In this repo that is `bin/*`, `tools/bin/`,
  `.speccraft/state.json`, `.claude/` and `tests/e2e/.logs/` — and writing a
  built binary into `bin/` is the subject of a hard guardrail, so the most
  guardrail-relevant write was exactly the invisible one. (Verified during
  round 5: `bin/PROBE-FILE` was invisible to
  `git ls-files --others --exclude-standard` and visible to
  `git ls-files --others`.) The flag is therefore dropped.

  **The volatile set is named, justified and closed.** Dropping the flag pulls
  in paths that legitimately change mid-round through no fault of a reviewer,
  so exactly these are excluded, by explicit list rather than as a side effect
  of a git flag:

  | excluded path | why |
  |---|---|
  | `.speccraft/.review-rounds/` **(the whole tree)** | reviewers are *supposed* to write their `.out` in their round dir — and the exclusion covers the siblings too: the `*` `.gitignore` the round writes at creation, `.building-*` dirs, and concurrent rounds' dirs |
  | `.claude/` | machine-local; **the orchestrating session writes permission allowlists here during the round** |
  | `.speccraft/state.json` | session/spec state, written by speccraft's own commands mid-round |
  | `tests/e2e/.logs/` | test logs, not project intent |

  **Why the whole `.review-rounds/` tree and not just the round dir.** The `*`
  `.gitignore` is a **sibling** of the round dir, not inside it, and
  `review_round_dir_create` writes it idempotently — so on any installed-base
  repo's *first* round that file is genuinely new. Excluding only the round dir
  would put it in the post-round diff and record `subagent-wrote-files`
  against a reviewer that did nothing. Because this list is a **closed** set,
  an implementer could not have excluded it without a spec change, so the
  omission was a blocker rather than a detail.

  **Ordering is the real invariant.** `review_round_dir_create` runs **before**
  the pre-round snapshot is taken, so round setup is never visible to the
  diff. The exclusion above makes that robust rather than load-bearing: get
  the ordering right *and* exclude the tree, so neither alone has to hold.

  Nothing else is excluded — notably **not** `bin/` or `tools/bin/`. The list
  is part of the contract and is asserted as a closed set, so widening it is a
  spec change rather than an implementation detail. This is the fourth
  iteration of this guarantee (porcelain text → path inventory →
  regular-file digests → ignored paths included); the recurring cause was that
  each enumeration narrowed the guarantee somewhere, so the enumeration is now
  total and the *exceptions* carry the justification instead.

  A reviewer that modifies an already-dirty tracked file, adds a file under an
  untracked directory, edits an existing untracked file, or writes to a
  gitignored path such as `bin/` is caught.
- a missing or empty `<agent>.out` after the agent returns is
  `failed subagent-no-output`, never an empty verdict.

`review_validate_reference_access` checks `payload_sha256` for `subagent`-mode
responses. What remains unenforced — and is stated here as plainly as 0052's
"a digest proves access, not attention" — is that the reviewer reports its own
digests honestly; no mechanism in this spec proves a reviewer read what it
hashed.

**Permissions.** The four review commands' `allowed-tools` gain `Agent`,
`TaskStop`, `Bash(shasum:*)` and `Bash(sha256sum:*)` (and `Write` for
`review-code`, which now records outcomes). `TaskStop` is load-bearing, not
decorative: it is the only way the timeout protocol below can stop a background
reviewer, and the convention "allowed-tools must list the tools the command
body uses" makes its omission a defect. `speccraft:reviewer` reports
`permission_denied: <tool>` when a read or hash is refused, which maps to the
named outcome `failed subagent-permission-denied` — not a generic
`attestation-failed` (the uninformative outcome 0052 removed elsewhere).

**Timeout and cancellation protocol.** Spelled out step by step, because an
under-specified one is what left round 2's reviewers unable to tell a stopped
reviewer from a running one:

1. the orchestrator launches each subagent reviewer with the `Agent` tool
   **in the background**, which yields an agent id;
2. it records that id and an absolute deadline of
   `now + review_timeout_s` in the round dir, so the deadline survives across
   tool calls;
3. it waits for completion notifications rather than polling;
4. at the deadline, any reviewer that has not completed is stopped with
   `TaskStop <agent-id>` and recorded `<agent> timeout`. A `TaskStop` that
   errors is `<agent> failed subagent-stop-failed <agent-id>` — again naming
   the id rather than implying the reviewer stopped;
5. a reviewer that completes **after** its deadline has its output
   **ignored** and is recorded as `<agent> timeout late-completion`. A late
   verdict never re-enters quorum, because the round it belonged to is already
   finalized;
6. partial output is never a verdict, and
7. cleanup runs only once every reviewer is **proven** terminal — completed,
   timed out, or *confirmed* stopped.

**Quarantine: a round whose reviewer cannot be proven stopped is not cleaned
up.** Two outcomes this spec defines —
`failed codex-cancel-unconfirmed <job-id>` (§2) and
`failed subagent-stop-failed <agent-id>` — mean exactly "the reviewer may
still be running". Deleting the round dir then would remove a payload or an
output path still in use, while keeping it conflicts with a cleanup rule that
fires on every exit path. The two cannot both hold, so the round gets a third
terminal-ish state:

- the round dir is **retained**, not removed, and its `lease` is left in
  place and expires on schedule — nothing extends it, and nothing needs to,
  because it is the `quarantine` record and not the lease that keeps the dir
  from being reclaimed;
- a `quarantine` file records the unconfirmed job/agent id, the outcome, the
  time, the reviewer's **`mode`**, and — for `codex-plugin` — the **canonical
  resolved companion root**, so an operator (or a later round) can see *why*
  it survived **and can act on it**. The root and mode are not optional
  bookkeeping: the automatic resolution below has to invoke
  `status <job-id>` against *the companion that owns the job*, and with a
  per-agent `plugin_root` or two installations there is otherwise no way to
  pick it. A quarantine record naming an id but no owner is unresolvable;
- `review_round_cleanup` **refuses** a quarantined dir, non-zero, nothing
  deleted;
- `review_round_sweep` reclaims a quarantined dir only after its lease has
  expired **and** its quarantine is resolved. A quarantined dir whose lease
  expired but whose quarantine is unresolved is **reported, not deleted**, so
  an orphaned reviewer is visible rather than silently swept. The report is
  one grep-able line per dir, so it is usable by an operator:
  `<dir>: quarantined <outcome> <id> lease-expired <iso-ts>`;
- **how a quarantine resolves depends on the mode, and only one is
  automatic.** For `codex-plugin`, a later `status <job-id> --json` confirming
  the job is no longer active resolves it. For `subagent` there is **no
  equivalent probe** — the Agent tool exposes no termination query for an id
  whose `TaskStop` failed — so a quarantined subagent round resolves by
  **operator action only** (removing the `quarantine` file). Stated plainly
  here so an implementer does not go looking for a subagent `status` probe
  that does not exist;
- the round itself still finalizes: a quarantined reviewer's outcome is the
  named failure above, counting toward neither predicate.

This is the only place cleanup is not unconditional, and it is deliberate: the
alternative is deleting files a live process may read.

**Lifecycle failures.** Unknown `subagent_type` or an Agent launch error →
`failed subagent-launch <reason>`. Every failure keeps the prior durable
`review.md` byte-unchanged.

**`agents/reviewer.md`** (new, `speccraft:reviewer`): tools
`Read, Grep, Glob, Bash(shasum:*), Bash(sha256sum:*), Write`; frontmatter
`model: inherit`. The Bash scoping is **mechanical, not prose**: the four
review commands already scope their own Bash this way in `allowed-tools`, and
declaring bare `Bash` while asking the body to please only run `shasum` leaves
the same declared-vs-permitted gap that the post-round tree check exists to
compensate for on the `Write` side. The body still confines `Write` to the
single path `<round-dir>/<agent>.out` and forbids creating anything else — that
one cannot be expressed in frontmatter, which is why the tree check backs it.
It has **no `Edit`**, so it cannot modify an existing file in place.

**Naming: `speccraft:reviewer` vs `speccraft:cross-reviewer`.** These are two
different agents and the distinction is easy to lose. `speccraft:cross-reviewer`
(existing) is the **synthesizer**: it runs once per round, after dispatch, reads
every reviewer's `.out`, and writes the consolidated `review.md`.
`speccraft:reviewer` (new, this spec) is a **reviewer**: it runs once per
`subagent`-mode registry entry, during dispatch, reads the payload, and writes
only its own `<agent>.out`. One produces a verdict; the other combines
verdicts. `agents/reviewer.md` and `agents/cross-reviewer.md` each state the
contrast in their first lines so neither is dispatched in the other's place.

**Model.** The Agent tool has no explicit "inherit" value: an omitted model
resolves to the **agent definition's** `model`, then the parent's. So:
registry `model = opus|sonnet|haiku|fable` is passed explicitly — all four are
accepted by the Agent tool's `model` parameter, `fable` included (Fable 5.1,
`claude-fable-5-1`), so the accept list and the dispatch surface agree and
there is no enum to trim; `inherit`
(or absent) omits it, which resolves to the parent session's model **only
because `reviewer.md` declares `model: inherit`**. For a custom
`subagent_type`, an omitted model follows that agent's own frontmatter and
`review.md` records it as `requested: inherit (per <agent> definition)`.
A custom `subagent_type` must declare `Write`, since it has to produce its own
`<agent>.out`; one that does not is `failed subagent-launch
missing-write-tool` at dispatch time rather than a silent empty verdict. One
whose declared tools include `Edit` gets a review-time warning (it can modify
files in place, which the post-round tree check would catch only after the
fact).

**Quorum.** A subagent verdict counts toward `responses_complete` and
`approval_quorum_met` exactly like any other reviewer. `review.md` records each
verdict's `mode` and requested model.

**Same-vendor approval is recorded, not blocked.** The shipped template enables
one Claude subagent at `review_quorum = 1`, so a Claude-authored spec can reach
`status: reviewed` on one Claude reviewer's approval — a real weakening of the
cross-model premise on the default path. This spec makes that **visible rather
than impossible**: each verdict records a `vendor` (`anthropic` for `subagent`
and for a `cli` entry whose command is `claude`; `openai` for `codex-plugin`
and `codex`; otherwise `unknown`, derived from the registry entry, not guessed
from output), and when every approval counted toward a met quorum shares the
spec author's vendor, the round sets `single_vendor_approval: true` in
`review.md` alongside a one-line note.

**The vendor predicate is stated, not inferred.** `review_agent_vendor` is
decided by an **exact match on the basename of argv[0]** of the registry
entry's `cmd` — nothing else. `claude` and `claude-p` resolve by that rule
(`claude` → `anthropic`; `claude-p` → `unknown`, because it is not the
`claude` binary and speccraft will not guess at a wrapper), `/usr/local/bin/
claude` → `anthropic` (basename), `claude_wrapper.sh` → `unknown`,
`codex` → `openai`, `subagent` mode → `anthropic` by construction,
`codex-plugin` mode → `openai` by construction. No substring matching, no
first-token heuristics: a wrapper is `unknown` rather than quietly assumed,
since a wrong vendor label is worse than an absent one for a flag whose only
job is to be believed. Users who wrap a binary can state the vendor by naming
the real one in `cmd`.

**Quorum arithmetic is unchanged.** Requiring a non-Claude approval instead
would make a round unsatisfiable whenever the only non-Claude reviewer is
unavailable — precisely the `codex-plugin-unavailable` path this spec
introduces — turning a degraded reviewer into a hard block on the lifecycle.
Recording the fact lets a reader discount a single-vendor approval without
speccraft second-guessing a quorum the user configured.

### 4. One shared round for all four review commands

Compose → budget-check → dispatch → outcome-record → attestation becomes one
mode-aware runbook section (in a single runbook file every caller references)
plus `review.lib.sh` helpers, parameterized by the document(s) under review,
the inline set, the reference set, and the template:

| Command | Under review | Durable output | `--diff`/snapshot/fingerprint |
|---|---|---|---|
| `spec:review` | `specs/<id>/spec.md` | `specs/<id>/review.md` | yes (unchanged, 0035/0052) |
| `arch:review` | `design/<id>/design.md` | `design/<id>/review.md` | no |
| `pm:review` | `product/<id>/brief.md` | `product/<id>/review.md` | no |
| `spec:review-code` | ONE frozen diff + the active spec if any | stdout only (as today) | no |

**review-code freezes one diff.** The diff (`git diff HEAD`, or
`git diff <ref>...HEAD` with `--base`) is computed **once** into the round dir
and composed into every reviewer's payload, so every mode reviews identical
bytes. With no active spec, review-code still runs and the payload says so; a
spec is not required. The code-review template keeps a challenge framing.

**Decision: untracked files are out of the reviewed diff.** `git diff HEAD` and
`git diff <ref>...HEAD` both exclude untracked files, so `review-code` reviews
tracked changes only. This spec criticizes `/codex:adversarial-review` for
including untracked files (§Which Codex entry point), so the asymmetry is
deliberate and recorded here rather than left as an implicit side effect of
freezing one diff: the objection to `adversarial-review` is that it reviews a
**different and self-collected** change than the one speccraft composed and
attested, not that untracked files are uninteresting. One frozen, reproducible,
hashable diff is what makes attestation meaningful, and `git diff HEAD` is
exactly reproducible from the recorded `HEAD`, while a snapshot that also
swept in untracked files would not be. The payload states the exclusion in
prose so a reviewer knows a brand-new unstaged file is not in scope, and
`review.md`/stdout repeats it. Widening the scope (e.g. `--include-untracked`)
is deliberately left out of scope.

`arch:review`/`pm:review` keep their critic-first stage and write `review.md`
only on a complete round; an inert round writes nothing.

**Signatures stay compatible.** `review_budget_check <bytes> <input-mode>` and
`review_dispatch_payload <cmd> <input-mode> <artifact>` keep their signatures
and existing tests. New: `review_agent_transport <toml> <agent>` maps an agent
to the input-mode the budget check takes (`codex-plugin`, `subagent` →
`file`); `review_dispatch_agent <toml> <agent> <payload> <cwd>` routes on mode —
`cli`/`acp` to `review_dispatch_payload`, `codex-plugin` to the companion, and
`subagent` to a named error ("subagent reviewers are dispatched by the
orchestrating session"), so a bash path never silently drops one.

### 5. Review-only modes are refused by non-review consumers

`codex-plugin` and `subagent` are **review-dispatch** adapters. The registry is
shared, though, so `spec:delegate` and `aux-delegator` will see entries in
these modes as soon as a user adds one, and today they would improvise:
`spec:delegate` accepts any registered agent, and `aux-delegator` reads
`cmd`/`input` fields that neither new mode has. Leaving that to improvisation
is how a delegation silently becomes a no-op or an unquoted shell-out.

So both consumers **refuse** the review-only modes explicitly, with a named
error that says where the mode *is* supported:
`unsupported-mode: <mode> is a review-only dispatch mode (used by
spec:review, arch:review, pm:review, spec:review-code); spec:delegate
supports cli and acp`. The refusal is a precondition check before any
dispatch, so nothing is partially executed. `aux-delegator`'s agent
documentation states the same restriction.

This is a guardrail, not a roadmap: making `codex-plugin`/`subagent` work for
implement-mode delegation stays out of scope, and the error text does not
promise it.

### 6. Template, docs, convention

`templates/speccraft/agents.toml` gains a `subagent` entry, **enabled**, with
`model = "opus"`, and a `codex-plugin` entry with `enabled = false`. Existing
repos' registries are not migrated. `skills/aux-agents/SKILL.md` documents both
modes — what each adapter invokes, its guarantees, the `/codex:setup` remedy,
and the `speccraft:reviewer` / `speccraft:cross-reviewer` distinction — as
adapter documentation, not a recommendation of either tool.
`.speccraft/conventions.md` §External-tool boundaries gains the
user-configured-adapter clarification.

The template also carries a comment on the **same-vendor default**: with only
the `subagent` entry enabled, quorum can be met by a Claude reviewer on a
Claude-authored spec, which `review.md` will flag as
`single_vendor_approval: true`; enabling the `codex-plugin` entry (after
`/codex:setup`) is how a user gets a genuine cross-vendor round. The comment
states the trade-off without telling the user which tool to prefer, as the
convention requires.

## Contracts

- Valid modes: `cli`, `acp`, `codex-plugin`, `subagent`; omitted → `cli`.
- `review_agent_mode <toml> <agent>` → one of the four, or a named error.
- `review_agent_transport <toml> <agent>` → input-mode for `review_budget_check`.
- `review_dispatch_agent <toml> <agent> <payload> <cwd>` → mode router.
- `review_codex_plugin_root <toml> <agent>` → absolute root, or non-zero with
  `codex-plugin-unavailable: <reason>`, where `<reason>` is exactly one of
  `not-installed`, `companion-missing`, `unsupported-companion <version>`,
  `unknown-version` — siblings, never concatenated.
- `review_codex_preflight <root>` → zero when `setup --json` reports
  `ready: true`; else non-zero with `not-ready <reason>`. Memoized on the
  symlink-resolved absolute `<root>`, so two agents sharing a root preflight
  once and two roots preflight twice. **Resolution happens before the memoize
  key is formed, not after** — two different path strings that resolve through
  a symlink to the same root must share one cache entry (AC5c's aliasing row
  is what proves this; keying on the input string passes every other row).
- `review_codex_task_argv <toml> <agent> <payload> <cwd>` → NUL-separated argv
  for the `--background` launch.
- `review_codex_job_id <file>` → the job id from the launch output.
- `review_codex_job_status <root> <job-id>` → a terminal/pending token.
- `review_codex_job_result <root> <job-id>` → the raw result JSON.
- `review_codex_job_cancel <root> <job-id>` → zero only on **confirmed**
  cancellation; non-zero with `codex-cancel-unconfirmed`.
- `review_parse_codex_task_output <file> <exit-status>` → response text, or an
  outcome token. The exit status is an **explicit parameter**, not ambient:
  the classification rules in §2 distinguish `codex-task-error` from
  `codex-output-unparseable` by it, so a signature taking only the file could
  not implement its own table. The caller passes the status it captured from
  the companion invocation.
- `review_with_deadline <seconds> <cmd…>` → the command's status, or 124 on expiry.
- `review_round_dir_create <kind> <id> <timeout-s>` → prints the dir; also writes the
  `*` `.gitignore` in `.review-rounds/` (itself written atomically, same-dir
  temp + rename, per the `AtomicWriteFile` convention — so two concurrent
  rounds cannot race to a truncated file), and publishes the dir and its
  `lease` atomically (build under `.building-<expiry-unix-ts>-<rand>` in
  `.review-rounds/`, then `mv`). `<timeout-s>` is the registry's
  `review_timeout_s`; it is an explicit parameter because the lease duration
  derives from it and a helper that published a lease without being told the
  timeout would have no defensible source for it.
- `review_round_lease_write <dir> <timeout-s>` /
  `review_round_lease_expired <dir>`. **There is no renewal helper** — a lease
  is written once and never re-stamped (see §3 for why no path needs one).
- `review_round_quarantine <dir> <id> <outcome> <mode> [<companion-root>]` →
  writes the `quarantine` record. `<companion-root>` is **required for
  `codex-plugin`** (the canonical resolved root) and omitted for `subagent`,
  since only the former has a termination probe to invoke;
  `review_round_quarantined <dir>` → zero when quarantined.
- `review_round_cleanup <dir>` — refuses a quarantined dir.
- `review_round_sweep` — lease-based, no age argument; reports rather than
  deletes an unresolved quarantine (one line:
  `<dir>: quarantined <outcome> <id> lease-expired <iso-ts>`); reclaims a
  `.building-<expiry>-<rand>` dir once **the expiry in its own name** has
  passed. That expiry is one lease period — `review_timeout_s + 300 s`, the
  same quantity a lease expiry is built from — but the sweep **reads** it
  rather than recomputing it, so it needs no config, no argument and no lease,
  and two concurrent rounds with different `review_timeout_s` values are each
  judged by their own threshold. This is the single stated exception to the
  lease rule, since a half-built dir has no lease by definition.
- `review_tree_snapshot <round-dir>` → sha256 of every tracked file **and**
  every untracked regular file outside `<round-dir>`, plus path+type for
  untracked non-regular entries. Content, not an inventory; enumerated with
  `git ls-files --others -z` (**no `--exclude-standard`**, so ignored paths
  like `bin/` are covered) and per file, never `--directory`-collapsed. The
  excluded volatile set is a closed, contract-level list:
  `.speccraft/.review-rounds/` (the whole tree, covering the round dir, its
  `*` `.gitignore` sibling, `.building-*` and concurrent rounds), `.claude/`,
  `.speccraft/state.json`, `tests/e2e/.logs/`. The pre-round snapshot is taken
  **after** `review_round_dir_create`, so round setup is never in the diff.
- `review_agent_vendor <toml> <agent>` → `anthropic|openai|unknown`, by exact
  basename match on argv[0] of `cmd`.
- Subagent responses carry `payload_sha256: <hex>` and, on refusal,
  `permission_denied: <tool>`; the subagent writes its own
  `<round-dir>/<agent>.out`.
- New outcome tokens: `failed codex-plugin-unavailable`, `failed
  codex-output-unparseable`, `failed codex-task-error`, `failed
  codex-wrote-files`, `failed codex-cancel-unconfirmed`, `failed
  subagent-launch`, `failed subagent-permission-denied`, `failed
  subagent-wrote-files`, `failed subagent-no-output`, `failed
  subagent-stop-failed`, `timeout late-completion`. `failed
  subagent-wrote-files` carries an `<unattributed>` marker when more than one
  subagent was concurrently active and the write could not be attributed, in
  which case **every** such reviewer records it.
- A round dir is `quarantined` when a reviewer could not be proven stopped;
  cleanup refuses it and the sweep reports it.
- `review.md` records per verdict: `mode`, requested `model`, `vendor`; and per
  round, `single_vendor_approval: <bool>`.
- Non-review consumers (`spec:delegate`, `aux-delegator`) fail with
  `unsupported-mode: <mode> is a review-only dispatch mode`.

## Acceptance criteria

1. `LoadConfig` accepts `cli`, `acp`, `codex-plugin`, `subagent`; normalizes an
   omitted `mode` to `cli`; rejects an explicit empty `mode` and `Subagent`/`CLI`
   variants with an error naming the agent and the four valid values. Go table
   test.
2. `LoadConfig` rejects, with a named error, on `codex-plugin`/`subagent`
   entries: `cmd`, `input`, `acp_agent`; `subagent_type` on `codex-plugin`;
   `effort`/`plugin_root` on `subagent`; an `effort` outside the six values; a
   `model` outside `opus|sonnet|haiku|fable|inherit` on `subagent`. One row each.
3. **Regression:** a `cli` entry with an unknown key (`install_hint`) still
   loads; this repo's `.speccraft/agents.toml`, the shipped template, and every
   registry fixture under `tests/` load unchanged.
4. `review_agent_mode` and the Go loader agree on one shared fixture registry —
   identical accept/reject per entry (parity test).
5. `review_codex_plugin_root` resolves, under a fake `HOME`: `plugin_root`
   wins; else the `local` entry whose `projectPath` is the repo root; else the
   `user` entry's `installPath`; missing companion → `companion-missing`; no
   entry → `not-installed`; `version` below the supported range →
   `unsupported-companion <version>`; absent/unparseable `version` →
   `unknown-version`. The four reason tokens are asserted **exactly**, so the
   two version failures cannot be spelled as one concatenated token.
5d. **Version discovery per resolution path.** An explicit `plugin_root` with
   **no** `installed_plugins.json` entry resolves its version from
   `<root>/.claude-plugin/plugin.json` and succeeds at 1.0.6 — the row that
   fails if the version is sourced only from `installed_plugins.json`, which
   would leave a valid explicit root permanently `unknown-version`. Rows: root
   absent from `installed_plugins.json` but carrying a manifest; root present
   in both (reads `installed_plugins.json`); root with neither →
   `unknown-version`; manifest present but unparseable → `unknown-version`.
5a. **The capability check never reads help text.** A fixture holding 1.0.6's
   **real** `printUsage` output — which omits `--prompt-file`, `--cwd` and
   `--json` — resolves **successfully** at version 1.0.6 with
   `setup --json` ready. A test asserting this is what fails if a help-text
   probe is reintroduced; it is the regression guard for round 2's confirmed
   P1 (a help-text probe fails closed against the targeted install).
5b. `review_codex_preflight` maps a stub `setup --json`: `{"ready":true}` →
   zero; `{"ready":false,...}` → non-zero `not-ready <reason>`, surfaced as
   `codex-plugin-unavailable`, **never** `codex-output-unparseable`.
5c. **Preflight is memoized per resolved root, not per round.** Call counts are
   asserted against a stub companion: two `codex-plugin` agents sharing one
   `plugin_root` ⇒ **one** `setup` call; two agents with **different**
   `plugin_root` values ⇒ **one call each**; two paths that resolve through a
   symlink to the same root ⇒ one call. A fixture gives one root `ready: true`
   and the other `ready: false`: the first agent dispatches and the second
   records `codex-plugin-unavailable not-ready`, proving readiness is never
   assumed across roots.
6. `review_codex_task_argv` emits exactly `node <root>/scripts/codex-companion.mjs
   task --background --fresh --json --prompt-file <payload> --cwd <cwd>` plus
   `--model`/`--effort` only when set; negative assertions that `--write`,
   `--resume`, `--resume-last` never appear.
6a. **Job lifecycle** against a stub companion: launch yields a job id
   (`review_codex_job_id`); `status` is polled until terminal;
   `result <job-id> --json` supplies the output that
   `review_parse_codex_task_output` then parses. A stub that never terminates
   plus `review_timeout_s = 2` causes exactly one `cancel <job-id>` call,
   a confirming `status` call, and `<agent> timeout`.
6b. **Cancellation must be confirmed.** A stub whose `cancel` succeeds but
   whose following `status` still reports the job active records
   `failed codex-cancel-unconfirmed <job-id>` — not `timeout` — and the job id
   appears in the message. This is the round-2 broker defect: a reviewer that
   may still be running is never reported as merely timed out.
7. Dispatch through a stub `node` that records argv and `stat`s the file proves
   `--prompt-file` is the round artifact itself (inode-equal), not a copy.
8. Every payload `review_compose_payload` produces — full, scoped, arch, pm,
   review-code — begins with a non-whitespace byte and ends with exactly one
   `\n`; asserted per composer branch, including inputs that end with no
   newline and with several.
9. `review_parse_codex_task_output <file> <exit-status>` fixtures, exercising
   the **public two-argument signature** (a one-argument call is a test
   failure, since the classification below cannot be implemented without the
   status), with **numeric** `status`:
   `{"status":0,...}` + non-empty `rawOutput` + zero exit → the response;
   `{"status":1,...}` → `failed codex-output-unparseable`; `status: 0` with
   empty or absent `rawOutput` → `failed codex-output-unparseable`; invalid
   JSON with zero exit → `failed codex-output-unparseable`; non-zero exit with
   non-JSON stdout → `failed codex-task-error`; non-empty `touchedFiles` →
   `failed codex-wrote-files` even with a valid verdict in `rawOutput`.
   One row is **verbatim captured 1.0.6 output**.
   **Required row — the quadrant:** valid **success-shaped** JSON
   (`status: 0`, non-empty `rawOutput`) with a **non-zero exit code** →
   `failed codex-task-error`. Neither accepting the verdict nor filing it as
   `codex-output-unparseable` passes, so the table is total over
   (exit status × JSON validity × field contents) and no combination is left
   to implementer judgement.
9a. **Negative:** a fixture whose `status` is the *string* `"completed"` is
   **not** treated as success — it is `codex-output-unparseable`. Round 2
   confirmed 1.0.6 never emits that value (`buildResultStatus`, `codex.mjs:754`);
   this row fails if string-status matching is reintroduced, which would have
   misrecorded every successful review as a failure.
10. `review_with_deadline 1 <stub that sleeps 30>` returns 124 within 5 s and
    leaves no child process alive. It bounds each individual companion
    invocation; the **job** deadline is AC6a's cancel path, and a test asserts
    the codex-plugin timeout path calls `cancel` rather than killing a process
    group.
11. With the codex plugin absent, a round with `[codex-plugin, stub-cli]`
    records `failed codex-plugin-unavailable not-installed`, still dispatches
    the stub-cli agent, prints a message naming `/codex:setup`, and never
    executes a `codex` binary (a stub on `PATH` fails the test if run).
12. `review_agent_transport` returns `file` for both new modes; an 80 KB payload
    is `ok` for them and `refuse:argv-limit` for `cli`+`argv`. Existing
    `review_budget_check` / `review_dispatch_payload` tests pass unchanged.
13. `review_dispatch_agent` routes `cli` by `input`, `codex-plugin` through the
    AC6 argv, and returns non-zero for `subagent` with the named
    "orchestrating session" error and no stdout.
14. `review_round_dir_create` creates a 0700 dir under
    `<root>/.speccraft/.review-rounds/` that survives the creating shell (checked
    from a second shell). `review_round_cleanup`
    removes it and refuses — non-zero, nothing deleted — a path outside
    `.review-rounds/`, a symlink, `/`, and an escaping `..`; it is exercised
    under a symlinked `TMPDIR` and with a symlinked ancestor of the repo root.
14a. **Ignored with no migration.** `review_round_dir_create` writes
    `.speccraft/.review-rounds/.gitignore` containing `*`, and
    `git check-ignore` reports the round dir and its payload as ignored in
    **three** repos: this one, a repo freshly initialized from the template,
    and — the case that matters — a repo initialized **before** this change
    whose `.gitignore` is never touched (no re-init, no template update). A
    `git add -A` in that third repo stages nothing from the round dir. The
    call is idempotent across two rounds.
    The third repo is a **checked-in fixture** under
    `tests/hooks/fixtures/` carrying a `.gitignore` byte-identical to the
    template as it shipped *before* this spec — not a shape the test
    constructs at run time, which would prove the installed-base claim against
    a shape the test itself chose.
14b. **Sweeping is lease-based, never age-based.** Two round dirs are created
    with mtimes faked far in the past: one holding an unexpired `lease`, one
    whose lease has expired. `review_round_sweep` removes **only** the expired
    one and leaves the old-but-active round — payload intact — untouched. A dir
    with a missing or unparseable lease is also removed. A test asserts the
    sweep takes no age/`max-age` argument, so age alone can never drive a
    deletion.
14e. **The `<timeout-s>` parameter is wired, proven by test not signature.**
    `review_round_dir_create <kind> <id> <timeout-s>` called with two
    different timeouts yields leases with **two different expiries**, each
    `timeout + 300`. Two concurrent rounds with different `review_timeout_s`
    are each reclaimed on their **own** threshold, which a sweep that read a
    single config value could not achieve.
    **How the transient names are observed.** A successful create `mv`s the
    `.building-<expiry>-<rand>` name away, so the test cannot simply list the
    directory afterwards: it observes the name either by **interleaving** (a
    creator paused mid-build by a fault-injection seam, with the directory
    listed while it is still building) or by **instrumentation** (the helper
    records the temp name it chose). Stated because an AC that asserts a state
    the test cannot reach is the defect round 5 found in AC14d, and it should
    not be reintroduced one criterion over.
14c. **A round is published atomically with its lease.** No intermediate state
    is observable in `.review-rounds/` under its final name without a `lease`:
    a test interleaves `review_round_dir_create` with `review_round_sweep`
    (sweep run repeatedly in a loop against a creator in a loop) and the
    created round survives every time — the creation-vs-sweep race that
    "missing lease ⇒ reclaim" would otherwise open. A `.building-*` directory
    left behind by a killed creator is reclaimed **only once the expiry
    encoded in its own name has passed** — not by age or mtime: a fresh one
    survives a concurrent sweep, one whose encoded expiry is past does not.
    Published round dirs are never matched by that rule.
14d. **Every lifecycle path finishes inside its lease, with no renewal.**
    The lease is written once. **The load-bearing assertion is that a lease
    file's expiry is byte-identical before and after a full round** — that
    catches a re-stamp introduced under any name, including
    `_touch`/`_bump` or inlined `date` arithmetic. A companion grep that
    `review_round_lease_renew` is absent from `review.lib.sh` is a **convention
    nudge only**, not the guard: it pins one spelling and would miss the
    others, and is marked as such so a reader does not mistake the strawman for
    the real check. Each bounded path is then
    exercised against a concurrent sweep and survives: a `codex-plugin` job
    polling to the `review_timeout_s` deadline; its `cancel` + one confirming
    `status`; a `subagent` round to its deadline and `TaskStop`; and a
    `cli`-only round under `review_with_deadline`. The two **unbounded** cases
    — unconfirmed cancel and stop-failed — are covered by AC15a/15b's
    quarantine rules instead, and a test asserts a quarantined dir outlives
    its own expired lease, proving quarantine and not the lease is what
    retains it.
15. Every exit path of the shared round — complete, inert, dispatch error, a
    timed-out reviewer — ends with the round dir removed **once every reviewer
    is proven terminal**, and cleanup is never invoked while a recorded
    reviewer is still pending. Shell-sequence test with stub agents and a
    pending-reviewer marker.
15a. **Quarantine beats unconditional cleanup.** On
    `failed codex-cancel-unconfirmed` and on `failed subagent-stop-failed`:
    the round dir is **retained**, a `quarantine` record naming the job/agent
    id is written, `review_round_cleanup` on it returns non-zero and deletes
    nothing, and the round still finalizes with that reviewer's named failure
    counting toward neither predicate. `review_round_sweep` on a quarantined
    dir with an **expired** lease and an unresolved quarantine **reports and
    does not delete**; once the quarantine file is removed (operator action)
    or a later `status` confirms termination, the same sweep reclaims it.
    A test asserts the two rules cannot both fire — i.e. no exit path both
    quarantines and deletes. The sweep's report line is asserted to be
    grep-able in the stated shape.
15b. **Quarantine resolution is per mode, and names its owner.** A quarantined
    `codex-plugin` round is reclaimed automatically once a stub
    `status <job-id> --json` reports the job inactive — invoked against the
    **companion root recorded in the `quarantine` file**, not a re-resolved
    one. Required row: **two installations** with different `plugin_root`
    values, one job quarantined against each; each is probed with its own
    companion (asserted by per-root call counts), and a record lacking a root
    for a `codex-plugin` quarantine is a named error rather than a probe
    against an arbitrary install.
    **Required row — the recorded root is read back, not re-derived.** A row in
    which the recorded root **differs from what re-resolution would now
    produce** (the install was removed between rounds, or `plugin_root` was
    dropped from the registry): the probe must still go to the **recorded**
    root. Without it, an implementation that re-resolves from
    `installed_plugins.json` and happens to agree satisfies every other
    assertion — this is the only row that proves the field is *used* rather
    than merely written.
    A quarantined `subagent` round is **not** reclaimed by any probe — only by
    removing the `quarantine` file — and a test asserts no Agent-tool
    termination query is attempted for it.
16. `review_validate_reference_access` on a `subagent`-mode response: missing
    `payload_sha256` → `attestation-failed missing-payload-digest`; wrong →
    `attestation-failed payload-digest-mismatch`; `permission_denied: Bash` →
    `failed subagent-permission-denied`; correct + reference digests correct →
    valid. `cli` responses are unaffected (0052 tests unchanged).
16a. **Every prompt template teaches the attestation shape it will be parsed
    by.** This spec extends the attested block with `payload_sha256`, so the
    rule it relies on must hold first: for **each** template a round can
    dispatch (`review.md`, `re-review.md`, the code-review template, and the
    arch/pm templates), the documented `reference_access` block is extracted
    from the template, its placeholders filled, and fed to
    `_review_parse_reference_access` — it must pair up into
    `ACCESS-PATH`/`ACCESS-SHA`. A template that documents no block, or one the
    parser cannot pair, fails.
    **Regression (found live):** spec 0054's own review round 3 went inert on
    *format*, not access — both reviewers read the reference files and computed
    correct digests, then invented shapes (a YAML map `<path>: <digest>`, and
    `- path: X, sha256: Y` on one line) because `re-review.md` showed no schema
    and never named `reference_access`. Both shapes are pinned as rejected, and
    the `payload_sha256` addition is held to the same round-trip test, so a
    scoped round can attest at all.
17. Two byte-identical `<agent>.out` artifacts in one round — including two
    subagents — are reported as a dispatch failure, not two verdicts.
17a. **The subagent's own artifact is what gets validated.** The round reads
    `<round-dir>/<agent>.out` from disk; no step copies an Agent tool result
    into it. A missing or empty `.out` after the agent returns is
    `failed subagent-no-output`, not an empty verdict. A test asserts the
    runbook contains no instruction to transcribe the Agent result into `.out`
    (grep-level negative), so the transcription hop cannot return.
17b. **Post-round tree check is content-aware.** `review_tree_snapshot` is
    taken before and after. A stub subagent that writes outside the round dir
    records `failed subagent-wrote-files`; one that writes only
    `<round-dir>/<agent>.out` does not. The two cases that defeat a
    a weaker check are **required rows**, each asserted to be caught:
    - modifying a tracked file that was **already dirty** before the round
      (its porcelain entry ` M <path>` is byte-identical before and after);
    - adding a file beneath an **already-untracked directory** (porcelain
      collapses both states to the same `?? <dir>/` entry);
    - **editing the bytes of an existing untracked file**, adding and removing
      no paths at all — the row that fails if untracked files are inventoried
      by path instead of hashed;
    - **writing to a gitignored path outside the round dir** — `bin/probe`
      and `tools/bin/probe` — the row that fails if the enumeration keeps
      `--exclude-standard`. Writing a built binary into `bin/` is a hard
      guardrail subject, so this is the most consequential row, not an edge
      case.
    - **`git ls-files --others --directory`** must not satisfy this AC: a row
      adds two files under one untracked directory and asserts **both** appear
      in the snapshot. The per-file enumeration is otherwise prose-only, and
      the round-3 collapsed-`??` hole is cheap to re-pin head-on rather than
      leave to an "optimization" to reintroduce.
    The **volatile set is asserted as a closed list**: a mid-round write to
    `.claude/settings.local.json`, to `.speccraft/state.json`, to
    `tests/e2e/.logs/`, and to `.speccraft/.review-rounds/.gitignore` each
    leave the check passing (all excluded by name), while a write to any
    *other* ignored path fails it. A test asserts the exclusion list contains
    exactly those four entries, so widening it silently is not possible.
17d. **Attribution with two concurrent subagents.** Two `subagent` reviewers
    run concurrently and **one** writes outside the round dir: **both** record
    `failed subagent-wrote-files <unattributed>`, and the round's predicates
    are asserted — `responses_complete: false`, so neither verdict counts and
    quorum cannot be met by the innocent reviewer's approval. With exactly one
    subagent active, the outcome names **that** agent and carries no
    `<unattributed>` marker. A row with two concurrent subagents and **no**
    out-of-bounds write records neither failure, so the rule is not merely
    "fail everything when more than one runs". A `codex-plugin` reviewer
    running alongside a writing subagent is **not** failed, since its
    `touchedFiles` is per job and attributable.
17c. **Round setup is never mistaken for a reviewer write.** In a repo with no
    `.speccraft/.review-rounds/.gitignore` yet — the installed-base first-round
    case — a full round records **no** `subagent-wrote-files`, asserted two
    ways: the pre-round snapshot is taken **after** `review_round_dir_create`
    (sequence asserted), and the whole `.review-rounds/` tree is excluded, so
    either property alone suffices and neither is silently load-bearing.
    A negative row proves the check still passes when nothing outside the
    round dir changed, with a pre-existing dirty tree **and** a pre-existing
    untracked file present — so the mechanism is sensitive without being
    noisy. Tests assert the implementation neither compares porcelain text nor
    relies on a path-only untracked inventory.
18. `agents/reviewer.md`: name `reviewer`, tools exactly
    `Read, Grep, Glob, Bash(shasum:*), Bash(sha256sum:*), Write`,
    `model: inherit`; **no `Edit`** and **no bare `Bash`** (negative
    assertion — a bare `Bash` entry fails the test, since mechanical scoping
    is the point); the body instructs reading the payload by path, reporting
    `payload_sha256` and `permission_denied`, the speccraft verdict
    vocabulary, writing its output to `<round-dir>/<agent>.out`, and that no
    other path may be written. Frontmatter + phrase test.
18a. **Naming.** `agents/reviewer.md` and `agents/cross-reviewer.md` each state
    the reviewer-vs-synthesizer contrast, and `skills/aux-agents/SKILL.md`
    documents both names. A test asserts neither file describes itself with the
    other's role, so `speccraft:reviewer` is not dispatched where
    `speccraft:cross-reviewer` is meant.
18b. **Custom `subagent_type`.** One lacking `Write` →
    `failed subagent-launch missing-write-tool` at dispatch, before any Agent
    launch; one declaring `Edit` → a review-time warning that still dispatches.
19. Model passing: registry `opus` → the runbook's Agent dispatch instruction
    carries `model: opus`; `inherit`/absent → it carries no model, and the
    runbook text states this relies on `reviewer.md`'s `model: inherit`.
    Grep-level test on the runbook.
20. `commands/spec/review.md`, `commands/arch/review.md`,
    `commands/pm/review.md`, `commands/spec/review-code.md` each reference the
    shared round section, list `Agent`, **`TaskStop`**, `Bash(shasum:*)`,
    `Bash(sha256sum:*)` in `allowed-tools`, and name all four modes;
    `arch`/`pm` name `design.md`/`brief.md` and their own `review.md`; none
    still calls the backend "unchanged". Per-file test. `TaskStop` is asserted
    in all four, since the timeout protocol cannot stop a reviewer without it.
20a. **Subagent timeout protocol.** A stub subagent that never completes with
    `review_timeout_s = 2`: the reviewer is stopped via `TaskStop`, recorded
    `<agent> timeout`, and the round still finalizes. A `TaskStop` that errors
    records `failed subagent-stop-failed <agent-id>`.
20b. **Late completion is ignored.** A reviewer whose output lands after its
    deadline is recorded `<agent> timeout late-completion`, its verdict is
    **not** counted toward quorum, and the already-finalized `review.md` is
    byte-unchanged afterwards.
21. `arch:review` and `pm:review` write `review.md` only on a complete round;
    an inert round leaves an existing `review.md` byte-unchanged and creates
    none. Shell-sequence test with stub agents.
22. review-code freezes ONE diff: with a staged edit reversed in the working
    tree plus an untracked file, every reviewer's payload contains the same
    `git diff HEAD` bytes (and `<ref>...HEAD` with `--base`); with no active
    spec the round still runs and the payload states no spec is active.
22a. **The untracked-file exclusion is stated, not implied.** With an untracked
    file present, the composed payload contains prose naming the exclusion, and
    the round's stdout/`review.md` repeats it — so a reviewer is told a new
    unstaged file is out of scope rather than silently not seeing it. Phrase
    test on the payload and the output.
23. Quorum: one `subagent` `approve` + one `cli` `changes-requested` at quorum 1
    → `responses_complete: true`, `approval_quorum_met: true`; the subagent
    `attestation-failed` → `responses_complete: false`. The synthesized
    `review.md` lists each verdict's mode, requested model and vendor.
23a. **Same-vendor approval is flagged.** `review_agent_vendor` resolves by
    exact basename match on argv[0] of `cmd`, with these rows pinned:
    `claude` → `anthropic`; `/usr/local/bin/claude` → `anthropic`;
    `claude -p --allowedTools …` → `anthropic` (argv[0] only);
    `claude-p` → `unknown`; `claude_wrapper.sh` → `unknown`;
    `codex` → `openai`; `/opt/wrappers/opus` → `unknown`; `subagent` mode →
    `anthropic` and `codex-plugin` mode → `openai`, both by construction.
    No substring or first-token-prefix matching (negative rows), so the
    predicate is reproducible rather than per-implementer.
    A round where the only approval comes from an `anthropic` reviewer on a
    spec with `authors: [claude]` writes `single_vendor_approval: true` **and
    still meets quorum** (`approval_quorum_met: true`) — the flag is a record,
    not a gate. A round with one `anthropic` and one `openai` approval writes
    `single_vendor_approval: false`. A test asserts quorum arithmetic is
    byte-identical with and without the flag, so 0052's quorum tests are
    unaffected.
23b. **Review-only modes are refused elsewhere.** `spec:delegate` and
    `aux-delegator` given a `codex-plugin` or `subagent` entry fail with
    `unsupported-mode` naming the mode and the four review commands, before any
    dispatch (a stub that records invocation proves nothing ran).
    **Regression:** `cli` and `acp` delegation through both consumers is
    unchanged, with the existing delegate tests passing unedited.
24. `.speccraft/conventions.md` §External-tool boundaries contains the
    user-configured review-adapter clarification; `skills/aux-agents/SKILL.md`
    documents both modes and `/codex:setup` without "prefer"/"recommended"
    phrasing about either tool (checked by the same phrase rule the convention
    states).
25. `templates/speccraft/agents.toml` loads with `LoadConfig` and has one
    enabled `subagent` entry with `model = "opus"`, one `codex-plugin` entry
    with `enabled = false`, an explicit `reference_read` on every entry, and a
    comment stating the same-vendor-default trade-off and `/codex:setup` as the
    route to a cross-vendor round, with no "prefer"/"recommended" phrasing.
26. Live smoke (manual, recorded in the changelog, not CI): one
    `/speccraft:spec:review` round with a `codex-plugin` and a `subagent`
    reviewer both returning attested verdicts under default permissions, and
    one `/speccraft:spec:review-code` round with `codex-plugin`. The changelog
    records the companion version, the resolved job ids, and that the round
    went through `task --background` + `status` + `result`. **This AC requires
    a host where the Codex plugin is installed and authenticated**; it cannot
    be satisfied in a dev container that lacks it, and it is the only AC with
    that dependency — every other Codex-touching AC uses a stub `node` and a
    fake `HOME`.
    **Gated by an explicit knob, and loud when skipped.** AC26/26a run only
    when `SPECCRAFT_LIVE_CODEX_SMOKE=1`; without it they **skip with a message
    naming themselves**, never pass silently. Otherwise an engineer running the
    suite locally without `/codex:setup` could read AC27's "whole bats suite
    green" as having covered them. AC27 is restated to exclude the gated ACs
    explicitly, so "green" never implies the live smoke ran.
26a. **Cancellation smoke** (manual, same conditions): one live round
    deliberately timed out, showing `cancel <job-id>` confirmed and the Codex
    turn no longer active in `/codex:status`. This is the only check that the
    detached broker actually stops; no stub can prove it.
27. **CI runs without `SPECCRAFT_LIVE_CODEX_SMOKE`, so AC26/26a are skipped
    and a green suite never attests them** — stated first, because a reader
    grep-asserting this AC's opening sentence must not be able to conclude the
    live smoke ran. The gated skips appear in the CI log by name. Subject to
    that exclusion: whole bats suite and Go suite green on Linux and macOS
    jobs, and `bin/` not committed.

## Notes for the plan

- Every Codex-touching test uses a stub `node` and a fake `HOME`; CI never needs
  the Codex plugin, its auth, or network. AC26/26a are the two manual
  exceptions and need a host with the plugin installed.
- AC4's fixture is the single source for both readers' validation rows.
- The persistent round dir supersedes 0052's "one shell" rule for the dir's
  lifetime only; single composition, budget-before-dispatch and single
  materialization stand.
- The 0052 suite is the regression floor: it must pass with no edits.
- **Why there is no lease renewal** (design history, kept out of §3 so the
  contract stays greppable). A renewal helper was added in review round 4 to
  answer "the lease has no renewing owner", then spent three rounds looking for
  a path that needed it: round 5 found its test boundary unreachable (the poll
  loop stops at `review_timeout_s`, while the lease runs to `+300 s`); round 6
  found the cancel/confirm phase it was then attached to is a single call pair,
  and that a quarantined round is retained by its `quarantine` record rather
  than by its lease. Every candidate path was already bounded, so the helper
  was removed rather than given a loop to justify it. An implementer tempted to
  reintroduce renewal should first identify the unbounded phase that needs it —
  and then bound that phase instead.
- ACs inserted by this revision carry letter suffixes (`5a`, `6a`, …) so that
  existing references to AC4/AC9/AC14/AC20/AC26 — in this spec's notes and in
  `review.md` rounds 1-2 — keep pointing at the same criteria.
- The companion-interface facts this revision relies on (numeric `status` at
  `codex.mjs:754`, `printUsage` omitting the flags, the detached+`unref`'d
  broker, `cancel` as the only path to `interruptAppServerTurn`, `setup --json`
  exposing `ready`) were read from an installed 1.0.6 source tree. The plan's
  first task should **re-verify them against the installed plugin** before
  coding the adapter, since two of round 2's three P1s were exactly this class
  of error; the pinned fixtures (AC5a, AC9) exist so a drift fails a test.

## Out of scope

- `spec:delegate` / implement mode via `codex-plugin` or `subagent` — now an
  explicit named refusal (§5) rather than undefined behaviour.
- `/codex:review`, `/codex:adversarial-review`, `/codex:rescue` as dispatch targets.
- Codex background jobs **beyond this adapter's own dispatch**: speccraft
  starts, polls, collects and cancels only jobs it launched itself. Adopting,
  resuming or reporting on a pre-existing Codex job, and any speccraft surface
  over `/codex:status` / `/codex:result` / `/codex:cancel`, stay out.
  (`task --background` itself moved **into** scope this revision: a foreground
  turn cannot be cancelled, which was round 2's confirmed broker defect.)
- Widening `review-code` to untracked files (e.g. `--include-untracked`).
- `--diff` re-review, snapshot, and fingerprint finalization for designs and briefs.
- Migrating existing repos' `agents.toml`.
- The Codex plugin's stop-time review gate.
- A release/version bump (bump-before-close convention, separately).

## Open questions

_none_
