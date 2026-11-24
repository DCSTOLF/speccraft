---
description: "Cross-model review of the active spec via aux agents"
argument-hint: "[--quorum N] [--agents codex,opencode] [--diff]"
allowed-tools: ["Read", "Write", "Bash", "Agent", "TaskStop", "Bash(shasum:*)", "Bash(sha256sum:*)"]
---

Run cross-model review on the active spec.

**IMPORTANT**: Execute ALL steps below using your tools before responding. Do
not describe steps — carry them out.

Steps:

1. Resolve the plugin root (for the prompt template path below), then read
   `.speccraft/state.json` for `active_spec`. If none, error:
   "No active spec. Run /speccraft:spec:new first."
   ```bash
   PLUGIN_ROOT="$(speccraft-state plugin-root)"
   ```

**Dispatch is mode-aware and shared.** The registry's `mode` selects how each
reviewer is reached: `cli` and `acp` go through `aux-delegator`,
`codex-plugin` drives the Codex plugin's companion, and `subagent` is
dispatched by **this orchestrating session** via the Agent tool — a shell
cannot start one. The full procedure (compose, budget-check, dispatch by
mode, record outcomes, attestation, the subagent timeout protocol) lives in
the shared `review-round` runbook at `skills/review-round/SKILL.md`. Follow it
rather than re-deriving a per-command variant.

2. Read `.speccraft/agents.toml`. Determine which agents to invoke:
   - If `--agents` flag provided, use that list (validate each exists).
   - Else, all agents with `enabled != false`.

2b. **Diff-focused re-review (`--diff`, spec 0035).** When `--diff` is passed,
   capture the envelope and classify the round BEFORE dispatching. Source the
   helpers:
   ```bash
   source "$PLUGIN_ROOT/commands/spec/review.lib.sh"
   SPEC_DIR="specs/<active>"
   AUTHORS="$(review_doc_authors "$SPEC_DIR/spec.md")"
   # READ-ONLY. The snapshot promote is DEFERRED to step 6 (spec 0052 AC24):
   # promoting here would rewrite review-snapshot.md before any verdict exists,
   # so a round in which every reviewer refused would silently re-baseline the
   # anchor the NEXT --diff classifies against, and that round would misclassify.
   ENV="$(speccraft-state review-diff "$SPEC_DIR")"
   snapshot="$(jq -r .snapshot <<<"$ENV")"; changed="$(jq -r .changed <<<"$ENV")"
   base="$(jq -r '.base_fingerprint // ""' <<<"$ENV")"
   diff="$(jq -r .diff <<<"$ENV")"
   sections="$(jq -r '.changed_sections | tojson' <<<"$ENV")"
   prior="$(review_reviewed_sha256 "$SPEC_DIR/review.md" 2>/dev/null || true)"
   branch="$(review_classify "$snapshot" "$changed" "$base" "$prior")"
   ```
   Then branch:
   - `short-circuit` → do NOT dispatch any reviewer; report "no changes since
     last review" and stop.
   - `full-review` → fall back to the normal full review below, but emit a loud
     warning that `--diff` could not scope this round (first review, or the prior
     `review.md` is not usable / its `reviewed_sha256` ≠ the envelope
     `base_fingerprint`).
   - `scoped` → carry `$diff` and `$sections` forward to step 3, which prepends
     the populated re-review brief and attaches the round's frozen spec image
     plus the prior review as evidence.

   In every `--diff` branch the reviewer-visible spec content comes from the
   round's **frozen spec image**, read once in step 3 and never re-read while the
   round runs (spec 0035 AC11's single-read transaction, relocated off
   `review-snapshot.md` because AC24 no longer promotes it here). Without
   `--diff`, proceed with the full review at step 3.

3. **Compose → budget-check → dispatch, in that order**, following the shared
   runbook. The order is the point: a budget check *after* dispatch prevents
   nothing — the payload has already gone to the reviewer, and the 600 s
   timeout this whole command exists to replace still happens.

   The round lives in the **persistent round dir**, not a shell temp dir with
   an `EXIT` trap. A `subagent` reviewer is dispatched by this session in a
   later tool call, and a trap-cleaned temp dir would be gone by then — the
   reviewer would find no payload. Cleanup is the runbook's §8 gate instead.

   ```bash
   source "$PLUGIN_ROOT/commands/spec/review.lib.sh"
   # From agents.toml `defaults.review_timeout_s`; 600 s when unset, the same
   # default review_dispatch_agent applies.
   TIMEOUT_S="${REVIEW_TIMEOUT_S:-600}"
   ROUND_DIR="$(review_round_dir_create spec "$ACTIVE" "$TIMEOUT_S")"
   review_tree_snapshot > "$ROUND_DIR/tree.before"
   ROUND_SPEC="$ROUND_DIR/spec-frozen.md"
   OUTCOMES="$ROUND_DIR/outcomes.txt"; : > "$OUTCOMES"
   cp "$SPEC_DIR/spec.md" "$ROUND_SPEC"      # the ONE read of spec.md this round

   TEMPLATE="$PLUGIN_ROOT/templates/prompts/review.md"       # full round
   PRIOR=""
   if [ "$branch" = scoped ]; then
     # The re-review brief AND the prior review as inline evidence. Step 2b
     # promises to attach it; omitting it here composes a scoped round with no
     # previous findings in it, so the reviewer cannot tell whether a change
     # resolved anything.
     TEMPLATE="$PLUGIN_ROOT/templates/prompts/re-review.md"
     cp "$SPEC_DIR/review.md" "$ROUND_DIR/prior-review.md"
     PRIOR="$ROUND_DIR/prior-review.md"
   fi

   for agent in $AGENTS; do
     # TWO DIFFERENT THINGS, deliberately not one variable:
     #   MODE      — the dispatch mode (cli | acp | codex-plugin | subagent)
     #   TRANSPORT — the registry's `input` field, which is what the byte
     #               budget measures against
     # Passing the transport where the dispatch mode belongs silently applies
     # the pre-0054 contract: the subagent-only payload_sha256 check never
     # runs, and a permission denial is filed under the wrong token.
     MODE="$(review_agent_mode .speccraft/agents.toml "$agent")" || {
       printf '%s failed unknown-mode\n' "$agent" >> "$OUTCOMES"; continue; }
     TRANSPORT="$(review_agent_transport .speccraft/agents.toml "$agent")"

     # Reviewers that cannot open files must not be handed paths (AC26).
     if [ "$(review_agent_reference_read .speccraft/agents.toml "$agent")" = "false" ]; then
       review_reference_read_message "$agent"
       printf '%s refused reference-read-unsupported\n' "$agent" >> "$OUTCOMES"
       continue
     fi

     ART="$ROUND_DIR/$agent.payload"       # DISTINCT per agent
     DIG="$ROUND_DIR/$agent.digests"
     BYTES="$(review_materialize_payload "$ART" \
       review_compose_payload "$TEMPLATE" "$ROUND_SPEC" \
         --inline .speccraft/guardrails.md .speccraft/index.md ${PRIOR:+"$PRIOR"} \
         --reference .speccraft/architecture.md .speccraft/conventions.md \
         --digest-out "$DIG" \
         ${diff:+--diff "$diff"} ${sections:+--changed "$sections"})"

     review_payload_representable "$ART" || { printf '%s failed unrepresentable-payload\n' "$agent" >> "$OUTCOMES"; continue; }

     VERDICT="$(review_budget_check "$BYTES" "$TRANSPORT")"
     if [ "$VERDICT" != "ok" ]; then
       review_refusal_message "$agent" "$TRANSPORT" "$BYTES" "$VERDICT" \
         "$(review_rank_files .speccraft/guardrails.md .speccraft/index.md "$ROUND_SPEC")"
       printf '%s refused %s\n' "$agent" "$VERDICT" >> "$OUTCOMES"
       continue                                # PER AGENT: others still run
     fi

     # ONE router for every mode. `cli`/`acp` go out through the transport,
     # `codex-plugin` drives the companion, and `subagent` returns 3 — which is
     # this session's cue to dispatch it with the Agent tool per the runbook,
     # NOT an error. A direct review_dispatch_payload call here would hand a
     # codex-plugin or subagent entry an empty command and drop it silently.
     #
     # The command itself is resolved INSIDE the router, via review_agent_cmd,
     # which decodes the registry's TOML array form. That is why this body does
     # not read `cmd` at all: reading it here with review_agent_field would
     # yield the raw array text and dispatch the literal word `["codex",`.
     if [ "$MODE" = subagent ]; then
       printf '%s pending-subagent %s\n' "$agent" "$ART" >> "$OUTCOMES"
       continue                                # dispatched by this session
     fi
     review_dispatch_agent .speccraft/agents.toml "$agent" "$ART" \
       > "$ROUND_DIR/$agent.out"
   done
   ```

   Refusal is **per agent**. One over-budget reviewer must not sink a round the
   other reviewers can still complete — and a refused agent is recorded as a
   non-verdict, so it cannot be mistaken for an agent that simply agreed.

   Then dispatch every `pending-subagent` entry via the Agent tool, following
   the runbook's timeout protocol, and replace its record with the outcome.

   Invoke the `aux-delegator` subagent once per selected agent, passing
   `payload_file`, `input_mode` and `cwd` (the root `speccraft-state find-root`
   reports). It **must not** recompose anything. Run agents in parallel; per-agent
   timeout from `agents.toml.defaults.review_timeout_s` (default 600s).

   Every reviewer receives the spec, `guardrails.md` and `index.md` inline, and
   the two reference-tier memory files as a path, a byte size and a heading index
   — the `--reference` hand-off above. Nothing else is added to what a reviewer
   sees; in particular `history.md` is not sent.

4. Collect outcomes — one record per **required** reviewer, appended to
   `$OUTCOMES` (`$ROUND_DIR/outcomes.txt`) as
   `<agent> <outcome> [detail…]`:
   - a verdict: `approve` | `approve-with-comments` | `changes-requested` |
     `reject`, with `concerns[]`, `suggestions[]`, `guardrail_violations[]`,
     `convention_violations[]`;
   - or a non-verdict: `refused` (pre-dispatch budget refusal), `timeout`,
     `failed`, `attestation-failed`.

   Validate each verdict's reference-read attestation before counting it:
   ```bash
   # $MODE is the DISPATCH mode, never the transport: it selects the
   # subagent-only payload_sha256 rule and the permission-denial token.
   RESPONSE="$ROUND_DIR/$agent.out"
   TOK="$(review_validate_reference_access "$RESPONSE" "$DIG" "$MODE" "$ART" || true)"
   if [ "$TOK" != ok ]; then
     printf '%s %s\n' "$agent" "$(review_attestation_outcome "$TOK")" >> "$OUTCOMES"
   fi
   ```
   A verdict whose digests are absent, incomplete or mismatched counts toward
   **neither** predicate — the same rule as a timeout. It is reported in its own
   category, because a chronically failing reviewer must be diagnosable rather
   than silently excluded round after round.

   Give each agent a **distinct** artifact path and hash-compare the outputs
   before counting them. Identical hashes across two agents are a dispatch bug,
   not agreement — a round can otherwise report a quorum of N having actually
   consulted one model.

5. Gate synthesis on response completeness:
   ```bash
   if ! review_responses_complete "$OUTCOMES"; then
     review_finalize_round "$SPEC_DIR" "$QUORUM" "$OUTCOMES" spec \
       .speccraft/agents.toml "$AUTHORS"
     # INERT round: report every refusal and every verdict obtained, and stop.
     exit 0
   fi
   ```
   Do **not** invoke `cross-reviewer`, write or replace `review.md`, commit a
   fingerprint, or rewrite `review-snapshot.md` on an inert round. Status stays
   `draft`.

   Otherwise invoke the `cross-reviewer` subagent to synthesize the responses
   into a coherent `review.md` and an action recommendation.

6. Write `specs/<active>/review.md`, then finalize the round. `review_finalize_round`
   is the single place that promotes the snapshot and stamps the fingerprint, and
   it re-checks the completeness gate itself, so a durable write cannot happen
   behind this runbook's back:
   ```bash
   review_finalize_round "$SPEC_DIR" "$QUORUM" "$OUTCOMES" spec \
     .speccraft/agents.toml "$AUTHORS"
   ```
   On a complete round this promotes `review-snapshot.md` from `spec.md` and
   stamps exactly one `reviewed_sha256:` line via temp + rename — for ANY verdict
   including `changes-requested` (spec 0035 AC2). On any failure the prior
   `review.md` is left byte-unchanged, so a failed round is re-reviewed rather
   than silently trusted. Skip step 6 entirely on a `short-circuit`.

7. Read the report's two predicates. They gate different things:
   - `approval_quorum_met: true` (agreeing verdicts ≥ quorum, default 1) →
     update spec status to `reviewed`. This predicate ALONE gates the promotion.
   - otherwise → leave at `draft` and surface the synthesis with next steps.

   `responses_complete` is not a quorum count: a complete round of two
   `changes-requested` verdicts persists its `review.md` and stays `draft`. The
   report's `approval_quorum_met` line comes from `review_approval_quorum_met`,
   which counts only agreeing verdicts, so a refusal can never be read as one.

8. Suggest next step:
   - If reviewed: `/speccraft:spec:plan`
   - If changes-requested: edit spec.md, then re-run `/speccraft:spec:review`
