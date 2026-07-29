---
description: "Conduct the spec lifecycle across a workspace's member repos: decompose, dispatch per member, track in the ledger, reconcile."
argument-hint: "<design-id> [--straight-through]"
allowed-tools: ["Read", "Write", "Edit", "Bash", "Task"]
---

Conduct design 0001's per-member spec lifecycle across a `kind: workspace`
workspace. The conductor is **advisory and failure-isolated**: it *sequences* the
existing `/speccraft:spec:*` commands (never bypasses them or the TDD guard),
dispatches each phase into the member repo with **cwd scoped to that member**,
**resumes** from the ledger pointer, and a `blocked` member never stalls its
siblings.

> **Scope (spec 0039):** this is the orchestration MVP — resume-at-pointer +
> `in_flight` visibility + blocked-set/clear. Full crash-window idempotency
> (allocate-id-before-dispatch, artifact inspection before re-attempt) is deferred
> to a follow-up (0040).

**IMPORTANT**: Execute ALL steps below using your tools before responding. Do not
describe steps — carry them out. The deterministic logic lives in
`commands/arch/orchestrate.lib.sh` (bats-tested via `tests/hooks/arch-orchestrate.bats`);
source it before use.

## 1. Bootstrap

```bash
PLUGIN_ROOT="$(speccraft-state plugin-root)"
WS_ROOT="$(speccraft-state find-root)"   # run at the workspace root; this is its .speccraft/
source "$PLUGIN_ROOT/commands/arch/orchestrate.lib.sh"
DESIGN="$ARGUMENTS"                        # the <design-id>; strip any --straight-through
STRAIGHT=0; case "$ARGUMENTS" in *--straight-through*) STRAIGHT=1 ;; esac
```

`ledger-set`/`reconcile` resolve the workspace via `FindWorkspaceRoot` internally,
so run them at `WS_ROOT`. Confirm the workspace with `speccraft-state list-members`.

## 2. Decompose (model-drafted, human-confirmed)

Draft a decomposition mapping each member repo to a one-line brief, **present it to
the human, and only proceed once they confirm/edit it**. Write the confirmed mapping
to a TSV (`<member-path>\t<brief>` per line) and parse it:

```bash
members_briefs="$(orch_parse_decomposition "$WS_ROOT/.speccraft/decomposition.tsv")"
```

`orch_parse_decomposition` rejects a tab-less line, empty member/brief, a duplicate
member, or a member-path outside `^[A-Za-z0-9._/-]+$`.

## 3. Seed member rows (rows only — no dispatch here)

For each confirmed member, record the row in the ledger. **Do NOT dispatch
`spec:new` at seeding** — that happens once, in the `new` phase, so `new` is never
double-dispatched:

```bash
speccraft-state ledger-set "$DESIGN" "$member" spec ""   # seed the row
```

## 4. Drive each member — resume, dispatch, apply

For each member, **resume** from its ledger pointer and advance one phase at a time.
The ordered tokens are `new → reviewed → planned → implemented → validated`.

```bash
pointer="<member's last_completed_phase from the ledger, '' if none>"
action="$(orch_next_phase "$pointer")"     # resume at the phase after the pointer
[ "$action" = "done" ] && continue         # this member is fully validated

# Checkpoint (a): pause after `planned`, before running `implement`
if [ "$(orch_should_pause "$action" "$STRAIGHT")" = "pause" ]; then
  # halt and ask the human to approve implement (suppressed by --straight-through)
  :
fi

speccraft-state ledger-set "$DESIGN" "$member" in_flight "$action"   # mark mid-execution
```

Dispatch the phase **cwd-scoped** into the member and run it as a subagent/command:

```bash
orch_dispatch "$member" "$action"          # emits: (cd '<member>' && /speccraft:spec:<...>)
```

- `new` → `/speccraft:spec:new` (runs the Socratic interview). Run it **once**;
  capture the member-allocated `NNNN-slug` ref and record it:
  `speccraft-state ledger-set "$DESIGN" "$member" spec "$ref"`.
- `review` → `/speccraft:spec:review`, looping with `/speccraft:spec:revise` under
  `orch_review_verdict "$iteration" "$max" "$critic_verdict"`:
  - `pass` → advance; `revise` → dispatch `revise` and re-review;
  - `escalate` → **Checkpoint (b)**: summarize the sticking points for the human and
    stop; on restart after their input, the revise iteration resets to 0.
- `plan` → `/speccraft:spec:plan`; `implement` → `/speccraft:spec:implement`.
- `validate` → gate on the member's tests, then close:
  ```bash
  [ "$(orch_validate "<member test command>")" = "pass" ] && <dispatch /speccraft:spec:close>
  ```

Apply the phase result to the ledger (advisory, failure-isolated):

```bash
orch_apply_result "$WS_ROOT" "$DESIGN" "$member" "$action" "$exit_code"
```

On success it advances `last_completed_phase`, clears `blocked`, and clears
`in_flight`; on failure it sets `blocked` and clears `in_flight`, leaving the
pointer put. Either way, **move on to the next member** — a `blocked` member never
stalls its siblings, and a clean re-attempt clears `blocked`.

## 5. Reconcile

When every member is at `done` (or blocked), roll up:

```bash
speccraft-state reconcile "$DESIGN"        # done: <bool> + <status>\t<member>\t<spec-ref> per member
```

Report the rollup: the design is done when every member spec is `closed`.
