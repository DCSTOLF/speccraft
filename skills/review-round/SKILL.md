---
name: review-round
description: "The shared cross-model review round: compose one payload, budget-check it, dispatch it to every enabled reviewer by its mode, record outcomes, validate attestation, and finalize. Used by /speccraft:spec:review, /speccraft:arch:review, /speccraft:pm:review and /speccraft:spec:review-code."
---

# review-round

One round, four commands. `/speccraft:spec:review`, `/speccraft:arch:review`,
`/speccraft:pm:review` and `/speccraft:spec:review-code` all run **this**
procedure; they differ only in what goes under review and where the verdict is
written.

They share it because a reviewer mode handled wrongly in four separate command
bodies is handled wrongly four times, and because the payload's bytes are a
contract: exactly one composer, so there is exactly one answer to "what was
sent".

## Parameters each command supplies

| Parameter | spec:review | arch:review | pm:review | spec:review-code |
|---|---|---|---|---|
| `KIND` | `spec` | `design` | `brief` | `code` |
| Document(s) under review | the frozen `spec.md` image | `design.md` | `brief.md` | the frozen diff + the active spec, if any |
| Template | `templates/prompts/review.md` (or `re-review.md` when scoped) | `templates/prompts/arch-review.md` | `templates/prompts/pm-review.md` | `templates/prompts/review-code.md` |
| `DOC_DIR` | `specs/<id>` | `design/<id>` | `product/<id>` | the active spec dir, or the repo root |
| Verdict written to | `$DOC_DIR/review.md` | `$DOC_DIR/review.md` | `$DOC_DIR/review.md` | nothing durable |

Four shell variables are the **caller's** to set before step 0, because each
command resolves them differently:

- `AGENTS` — the space-separated reviewer names: the `--agents` list if one was
  passed, otherwise every registry entry with `enabled != false`.
- `DOC_DIR` — the row above.
- `QUORUM` — from the registry (`review_quorum`, default 1).
- `AUTHORS` — the document's `authors:` frontmatter value, passed through
  verbatim. `[claude, dstolf]` is fine; the helper normalizes brackets, commas
  and quotes itself. For `code` rounds use the active spec's authors, or leave
  it empty when no spec is active.

`$REVIEW_TIMEOUT_S` and `$CLAUDE_PLUGIN_ROOT` come from the environment. Every
other variable in this runbook's shell blocks is assigned by this runbook; if
you find yourself inventing one, a step is missing rather than obvious.
Everything below is identical across the four commands.

## 0. Load the shell helpers

```bash
source "$CLAUDE_PLUGIN_ROOT/commands/spec/review.lib.sh"
```

That pulls in the codex adapter and the round-directory helpers too.

## 1. Create the round directory

```bash
ROUND_DIR="$(review_round_dir_create "<KIND>" "<id>" "$REVIEW_TIMEOUT_S")"
OUTCOMES="$ROUND_DIR/outcomes"
: > "$OUTCOMES"
echo "round dir: $ROUND_DIR"
```

`$OUTCOMES` is created EMPTY here, before the first dispatch: a missing file and
a round where nobody answered read identically to every helper that consumes
it, and the dispatch steps below append to it rather than create it.

**Print the round dir path and carry it forward.** This runbook spans many tool
calls and the shell does not persist between them, so the path has to live in
the transcript — re-deriving it later would pick a different random suffix.

The directory is created `0700`, publishes atomically with its lease, and is
ignored by git with no change to the host repo's `.gitignore`.

Then take the **pre-round tree snapshot**, *after* the round dir exists:

```bash
review_tree_snapshot > "$ROUND_DIR/tree.before"
```

Taking it after creation is deliberate: round setup writes the round parent and
its `.gitignore`, and neither may be mistaken for a reviewer write.

## 2. Compose one payload PER AGENT, then budget-check it

Each reviewer gets its **own** artifact path and its own digest sidecar. Never
one shared `payload.md` dispatched to everyone: §6 attests
`$ROUND_DIR/<agent>.payload` by digest, and the round's duplicate-output check
(§6) is meaningless if every reviewer was handed the same file.

`--label` names what the reviewer is holding. The default says "Spec under
review", which is wrong for `arch:review` and `pm:review` — see the parameter
table above for the label each command passes.

```bash
for agent in $AGENTS; do
  ART="$ROUND_DIR/$agent.payload"
  DIG="$ROUND_DIR/$agent.digests"
  BYTES="$(review_materialize_payload "$ART" \
    review_compose_payload "<template>" "<document under review>" \
      --label "<label for this command>" \
      --inline .speccraft/guardrails.md .speccraft/index.md \
      --reference .speccraft/architecture.md .speccraft/conventions.md \
      --digest-out "$DIG")"

  VERDICT="$(review_budget_check "$BYTES" \
    "$(review_agent_transport .speccraft/agents.toml "$agent")")"
  if [ "$VERDICT" != ok ]; then
    printf '%s refused %s\n' "$agent" "$VERDICT" >> "$OUTCOMES"
    continue        # PER AGENT: the other reviewers still run
  fi
done
```

`review_budget_check` takes a **byte count**, not a path — it refuses anything
that is not a base-10 integer. `review_materialize_payload` echoes exactly that
count, measured on the file it just wrote, which is why composition goes through
it rather than through a plain redirect.

The digest sidecar goes **outside** the payload: a reviewer that could read the
expected digests could return them without opening the files, and attestation
would prove nothing.

Check the budget **before** dispatching. A budget check afterwards prevents
nothing — the payload has already gone to the reviewer, and the ten-minute
timeout this whole command exists to replace still happens.

## 3. Dispatch each enabled reviewer by its mode

Read the mode from the registry — never assume it:

```bash
MODE="$(review_agent_mode .speccraft/agents.toml "$agent")"
```

### `cli` and `acp`

```bash
review_dispatch_agent .speccraft/agents.toml "$agent" "$ROUND_DIR/$agent.payload" \
  > "$ROUND_DIR/$agent.out"
```

The transport comes from the registry's `input`; `acp` always goes by `acp`.

### `codex-plugin`

Same call — the router resolves the plugin root, preflights it, launches a
background job, polls it, collects the result and classifies it:

```bash
review_dispatch_agent .speccraft/agents.toml "$agent" "$ROUND_DIR/$agent.payload" \
  > "$ROUND_DIR/$agent.out"
```

An unavailable plugin records `failed codex-plugin-unavailable <reason>` and
the round continues with the other reviewers. Never fall back to the `codex`
CLI: that would review with a different tool under the same agent name.

### `subagent` — dispatched by the ORCHESTRATING SESSION

`review_dispatch_agent` **refuses** this mode, by design. A subagent can only
be started by the orchestrating session's own tooling, so it is never handed to
**aux-delegator** (which shells out to external CLIs) and never dispatched from
a shell.

**Preflight the agent's own definition first, before any launch** (AC18b):

```bash
TYPE="$(review_agent_field .speccraft/agents.toml "$agent" subagent_type)"
TYPE="${TYPE:-speccraft:reviewer}"
PRE="$(review_subagent_preflight "$CLAUDE_PLUGIN_ROOT/agents" "$TYPE")"
if [ "$PRE" != ok ]; then
  printf '%s %s\n' "$agent" "$PRE" >> "$OUTCOMES"
  continue        # do NOT launch; the other reviewers still run
fi
```

The round reads this reviewer's verdict from `$ROUND_DIR/<agent>.out`, so an
agent whose frontmatter lacks `Write` **cannot produce one**. Without the
preflight it would be launched, think for minutes, and return nothing — and the
failure would surface as a missing artifact rather than as the registry error
it is. The refusal is recorded against the agent (`failed subagent-launch
<reason>`) so the round can tell a refused reviewer from one never dispatched.

A warning on stderr — the agent declares `Edit`, or declares no `tools:` at all
and so inherits every tool — is **not** a refusal. Surface it and dispatch: the
operator named that agent on purpose.

Then use the **Agent** tool:

- `subagent_type`: the registry's `subagent_type`, defaulting to
  **`speccraft:reviewer`** — the fully qualified name, matching the Go loader
  (`toml.go:238`) and the spec. A bare `reviewer` is a different, probably
  nonexistent agent, and the two readers must not disagree about which agent a
  registry means.
- `prompt`: instruct the agent to read `$ROUND_DIR/<agent>.payload` and write its
  response to `$ROUND_DIR/<agent>.out`.
- `model`: **only when the registry sets one**, and only for a concrete model.

Model handling, exactly (AC19):

| Registry `model` | Agent call | Recorded as |
|---|---|---|
| `opus` | pass `model: opus` | `model: opus` |
| `sonnet`, `haiku`, `fable` | pass that model | that model |
| `inherit` | pass **no model** | `requested: inherit` |
| omitted | pass **no model** | `requested: inherit (per <agent> definition)` |

Omitting the model is safe because `agents/reviewer.md` declares
`model: inherit`, so the subagent inherits the orchestrator's model. Passing a
model that the registry did not ask for would silently override that.

For a **custom** `subagent_type` with no model, record
`requested: inherit (per <agent> definition)` — the agent's own definition
decides, and speccraft is not entitled to claim which model ran.

**Read the response from the artifact the reviewer wrote.** Open
`$ROUND_DIR/<agent>.out` and use those bytes. Do not re-state, summarize or
otherwise reproduce the Agent tool's return value into that file: the
attestation digest is computed over the artifact's bytes, and anything other
than the reviewer's own output breaks it — besides substituting a paraphrase
for the review.

## 4. Subagent timeout and cancellation protocol

A subagent that outruns `review_timeout_s` must be **stopped and proven
stopped**. A subagent is not a process — the shell cannot see it, signal it or
wait on it — so this protocol is yours to run, across tool calls between which
no shell state survives. Seven steps, in order:

1. **Launch each subagent reviewer in the background**, which yields an agent
   id. Backgrounded so the reviewers run concurrently and so you keep a handle
   to stop one by.
2. **Record that id and an absolute deadline** in the round dir, immediately:
   ```bash
   review_subagent_record "$ROUND_DIR" "$agent" "<agent-id>" "$TIMEOUT_S"
   ```
   The deadline is stored as an absolute epoch second, not as the timeout it
   came from: a relative timeout re-read on a later tool call restarts the
   clock each time it is consulted, so nothing is ever late.
3. **Wait for completion notifications rather than polling.** You are
   re-invoked when a backgrounded agent finishes; a poll loop would burn tool
   calls and still race the deadline. **The instant a notification arrives,
   before any other tool call, stamp it:**
   ```bash
   review_subagent_completed "$ROUND_DIR" "$agent"
   ```
   That instant is the only time the information exists. Step 6 judges lateness
   against this stamp, and it has no fallback: collection time is NOT when the
   reviewer finished, because you are about to wait for the slowest one.
4. **At the deadline, stop whatever has not completed.** Check it, then call
   **TaskStop** with that agent's recorded id:
   ```bash
   if review_subagent_deadline_expired "$ROUND_DIR" "$agent"; then
     ID="$(review_subagent_agent_id "$ROUND_DIR" "$agent")"   # TaskStop this
   fi
   ```
   On a **confirmed** stop record `<agent> timeout` and continue the round. A
   `TaskStop` that errors or returns without confirming is **not** a stop:
   ```bash
   printf '%s %s\n' "$agent" \
     "$(review_subagent_stop_failed "$ROUND_DIR" "$agent")" >> "$OUTCOMES"
   ```
   which records `failed subagent-stop-failed <agent-id>` — naming the id the
   host knows the agent by, not the registry name — and **quarantines** the
   round dir in the same move. A reviewer that may still be running is a
   different situation from one that stopped late, and its payload and output
   path must be kept. Only an operator removing `$ROUND_DIR/quarantine`
   resolves it: no probe can ask whether a subagent is alive.
5. **A reviewer whose output LANDS after its deadline has it ignored**, and is
   recorded `<agent> timeout late-completion`. Lateness is judged by the
   artifact's own modification time, not by the clock when you get round to
   collecting it — you waited for the slowest reviewer in step 4, so "now is
   past the deadline" is true for every reviewer in any round that contained
   one timeout. A late verdict must never re-enter quorum.
6. **Partial output is never a verdict.** Collect from disk, and **branch** on
   the result:
   ```bash
   COL="$(review_subagent_collect "$ROUND_DIR" "$agent")"
   if [ "$COL" != ok ]; then
     printf '%s %s\n' "$agent" "$COL" >> "$OUTCOMES"
     continue        # not a verdict; the other reviewers still run
   fi
   # else: proceed to §6's attestation, which records the real verdict
   ```
   **Do not append `COL` unconditionally.** `ok` is a PROCEED signal, the same
   shape `review_budget_check` and `review_subagent_preflight` use — it is not
   an outcome. The outcomes file is read as `<agent> <outcome> <rest>`, and a
   recorded `ok` hits the unknown-token arm, which aborts the WHOLE round with
   exit 2 at its first predicate. The other two answers,
   `timeout late-completion` and `failed subagent-no-output`, are real
   non-verdicts and are recorded as-is. A missing or whitespace-only
   `$ROUND_DIR/<agent>.out` is `subagent-no-output`, never an empty verdict.
7. **Cleanup runs only once every reviewer is proven terminal** — completed,
   timed out, or *confirmed* stopped. See §7's gate; it refuses a quarantined
   dir.

## 5. Record every outcome

`$OUTCOMES` was created empty in step 1, before any dispatch. One line per
reviewer, whatever happened — a verdict, a `timeout`, or a
`failed <token>`. A reviewer with no recorded outcome is indistinguishable from
one that was never dispatched.

## 6. Validate attestation

Validate ONCE, then map the token to the recorded outcome. Never interpolate
the validator's token straight into the outcomes file: its vocabulary is
`ok` / `invalid:<reason>` / `failed <reason>`, and the recorded outcome is
`attestation-failed <reason>`. `review_attestation_outcome` is the only
translation, and calling the validator twice risks two different answers for
one reviewer.

```bash
TOK="$(review_validate_reference_access "$ROUND_DIR/$agent.out" \
         "$ROUND_DIR/<agent>.digests" "$MODE" "$ROUND_DIR/<agent>.payload" || true)"
if [ "$TOK" != ok ]; then
  printf '%s %s\n' "<agent>" "$(review_attestation_outcome "$TOK")" >> "$OUTCOMES"
fi
```

Pass `$MODE`. The payload-digest rule and the permission-denial token are both
mode-dependent: a `subagent` must attest `payload_sha256` because it reads the
payload from a file, and its refusal is `subagent-permission-denied` (fix: the
command's `allowed-tools`) where any other reviewer's is `permission-denied`
(fix: that agent's `cmd` in `agents.toml`). Omitting the mode silently applies
the pre-0054 contract.

A verdict without a matching digest for every reference path does not count
toward either round predicate.

**Then hash-compare, before counting anything.**

```bash
review_hash_collision_outcomes "$ROUND_DIR" "$OUTCOMES" || true
```

Two byte-identical `<agent>.out` files mean the round did not consult two
models — one was asked once and recorded twice. That is a dispatch fault, and
counting it as agreement reports a quorum of N for a round that consulted one
reviewer, which is indistinguishable from real consensus. Both members of a
colliding pair are rewritten to `failed duplicate-output`, because the digest
cannot say which one is the duplicate. Reporting the collision without
rewriting the records would leave the round still reporting consensus with the
diagnostic printed harmlessly beside it.

## 7. Check the tree, then finalize

```bash
review_tree_snapshot > "$ROUND_DIR/tree.after"
review_attribute_tree_outcomes "$ROUND_DIR" "$OUTCOMES" || true
```

**`_outcomes`, not `_writes` >> the file.** The rewriting form REPLACES each
implicated reviewer's record; appending would leave its `approve` in place
beside its own `failed subagent-wrote-files`, and at quorum 1 the round would
then report `responses_complete: false` AND `approval_quorum_met: true` — the
disqualified approval still carrying the round. Exit 1 means "records were
rewritten", not failure; exit 0 means the tree was clean and the file is
byte-unchanged.

A difference means a reviewer wrote outside its round dir. Who answers for it
depends on **how many subagents were active** — with two running concurrently,
nothing in the snapshot says which one wrote:

| Subagents active | Recorded |
|---|---|
| exactly one | `<agent> failed subagent-wrote-files` — named |
| more than one | every one of them, marked `<unattributed>` |
| none | nothing; no reviewer can be blamed (a warning on stderr) |

Failing both is deliberately harsh: one reviewer's misbehaviour voids the
other's verdict, so `responses_complete` is false and the innocent reviewer's
approval cannot carry quorum. The alternatives are worse — guessing blames an
innocent reviewer by name, and letting both stand admits a verdict from a round
whose integrity is unknown.

A clean two-subagent round records **neither** failure. The rule is not "fail
everything when more than one runs".

`codex-plugin` reviewers are never swept in: they leave no launch record, and
their `touchedFiles` is per job, self-attested and attributable on its own.

Then finalize for this `KIND`. The verdict document is written **only on a
complete round** — gate it, write it, then finalize:

```bash
if ! review_responses_complete "$OUTCOMES"; then
  review_finalize_round "$DOC_DIR" "$QUORUM" "$OUTCOMES" "<KIND>" \
    .speccraft/agents.toml "$AUTHORS"
  # INERT round: report every refusal and every verdict obtained, and stop.
else
  # …Write the synthesized review.md for this KIND (nothing, for `code`)…
  review_finalize_round "$DOC_DIR" "$QUORUM" "$OUTCOMES" "<KIND>" \
    .speccraft/agents.toml "$AUTHORS"
fi
```

On the inert branch an existing `review.md` is left **byte-unchanged** and none
is created where none existed, for every one of the four kinds. That matters
beyond tidiness in the spec lane: the next `--diff` round classifies against
`review.md`'s `reviewed_sha256:`, so a review.md replaced by a synthesis of
refusals silently collapses spec 0035's provenance gate.

**Pass the registry and the authors.** Without the 5th and 6th arguments the
round still finalizes, but it reports no `single_vendor_approval:` line and no
per-verdict `mode=`/`model=`/`vendor=` — so ACs 23 and 23a are simply absent
from every real round, which is exactly how they shipped dead until round 8
noticed that no caller passed them.

`<KIND>` is not decoration. It selects which durable writes finalize performs:
`spec` promotes `review-snapshot.md` and stamps the fingerprint; `design` and
`brief` do neither, because those documents have neither; `code` writes nothing
at all. An unrecognised kind is a named error rather than a fall-through to
`spec` — a typo must not earn a non-spec directory the spec lane's writes.

Finally, clean up:

```bash
review_round_cleanup "$ROUND_DIR"
```

Cleanup happens only once **every** reviewer is proven terminal, and it refuses
a quarantined dir.

## Resolving a quarantine later

- `codex-plugin`: `review_round_quarantine_resolve "$ROUND_DIR"` probes the
  companion root **recorded in the quarantine file** — not a re-resolved one,
  because the install may have changed between rounds.
- `subagent`: no probe exists. The operator removes
  `$ROUND_DIR/quarantine` once the agent is known to have stopped.

A stale round dir is reclaimed by `review_round_sweep`, which is **lease-based
and takes no arguments**: age is never a reason to delete, because a round
running for an hour and one abandoned an hour ago look identical by mtime.
