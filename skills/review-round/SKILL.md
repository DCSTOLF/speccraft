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
| Verdict written to | `specs/<id>/review.md` | `design/<id>/review.md` | `product/<id>/review.md` | nothing durable |

Everything below is identical across the four.

## 0. Load the shell helpers

```bash
source "$CLAUDE_PLUGIN_ROOT/commands/spec/review.lib.sh"
```

That pulls in the codex adapter and the round-directory helpers too.

## 1. Create the round directory

```bash
ROUND_DIR="$(review_round_dir_create "<KIND>" "<id>" "$REVIEW_TIMEOUT_S")"
echo "round dir: $ROUND_DIR"
```

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

Use the **Agent** tool directly:

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
stopped**. Follow these steps in order:

1. Note the deadline when the Agent call is made: `review_timeout_s` from the
   registry, or its default.
2. When the deadline passes with no artifact, stop polling for a response.
3. Call **TaskStop** with that agent's id.
4. Confirm the stop: the agent must report terminated. A stop that returns
   without confirming is not a stop.
5. On a **confirmed** stop, record `<agent> timeout` and continue the round.
6. On an **unconfirmed** stop, record `failed subagent-stop-failed <agent>` —
   never a plain `timeout`. A reviewer that may still be running is a different
   situation from one that stopped late.
7. Quarantine the round dir:
   ```bash
   review_round_quarantine "$ROUND_DIR" "<agent>" subagent-stop-failed subagent
   ```
   The dir is then retained rather than cleaned up, and only an operator
   removing `$ROUND_DIR/quarantine` resolves it — no probe can tell whether a
   subagent is still alive.

A late response that arrives after the deadline is **ignored**: the round it
belonged to is already finalized, and a late verdict must never re-enter
quorum.

## 5. Record every outcome

One line per reviewer, whatever happened — a verdict, a `timeout`, or a
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
cmp -s "$ROUND_DIR/tree.before" "$ROUND_DIR/tree.after"
```

A difference means a reviewer wrote outside its round dir: record
`failed subagent-wrote-files`. With more than one subagent active the write
cannot be attributed, so **both** record it with an `<unattributed>` marker and
neither verdict counts.

Then finalize for this `KIND`, and clean up:

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
