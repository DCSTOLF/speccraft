---
description: "Cross-model review of the active spec via aux agents"
argument-hint: "[--quorum N] [--agents codex,opencode] [--diff]"
allowed-tools: ["Read", "Write", "Bash"]
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

2. Read `.speccraft/agents.toml`. Determine which agents to invoke:
   - If `--agents` flag provided, use that list (validate each exists).
   - Else, all agents with `enabled != false`.

2b. **Diff-focused re-review (`--diff`, spec 0035).** When `--diff` is passed,
   capture the envelope and classify the round BEFORE dispatching. Source the
   helpers:
   ```bash
   source "$PLUGIN_ROOT/commands/spec/review.lib.sh"
   SPEC_DIR="specs/<active>"
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

3. **Compose → budget-check → dispatch, in that order.** Do the whole round in
   **one shell**: the temp directory must be live for all of it, and its cleanup
   trap can only fire in the shell that installed it.

   The order is the point. A budget check *after* dispatch prevents nothing — the
   payload has already gone to the CLI, and the 600 s timeout this whole command
   exists to replace still happens.

   ```bash
   source "$PLUGIN_ROOT/commands/spec/review.lib.sh"
   review_round_tmpdir                       # 0700, trap on EXIT HUP INT TERM
   ROUND_SPEC="$REVIEW_ROUND_TMPDIR/spec-frozen.md"
   OUTCOMES="$REVIEW_ROUND_TMPDIR/outcomes.txt"; : > "$OUTCOMES"
   cp "$SPEC_DIR/spec.md" "$ROUND_SPEC"      # the ONE read of spec.md this round

   TEMPLATE="$PLUGIN_ROOT/templates/prompts/review.md"       # full round
   # scoped --diff round: re-review brief + the prior review as evidence
   [ "$branch" != "scoped" ] || TEMPLATE="$PLUGIN_ROOT/templates/prompts/re-review.md"

   for agent in $AGENTS; do
     MODE="$(review_agent_field .speccraft/agents.toml "$agent" input)"
     CMD="$(review_agent_cmd .speccraft/agents.toml "$agent")"

     # Reviewers that cannot open files must not be handed paths (AC26).
     if [ "$(review_agent_reference_read .speccraft/agents.toml "$agent")" = "false" ]; then
       review_reference_read_message "$agent"
       printf '%s refused reference-read-unsupported\n' "$agent" >> "$OUTCOMES"
       continue
     fi

     ART="$REVIEW_ROUND_TMPDIR/$agent.payload"       # DISTINCT per agent
     DIG="$REVIEW_ROUND_TMPDIR/$agent.digests"
     BYTES="$(review_materialize_payload "$ART" \
       review_compose_payload "$TEMPLATE" "$ROUND_SPEC" \
         --inline .speccraft/guardrails.md .speccraft/index.md \
         --reference .speccraft/architecture.md .speccraft/conventions.md \
         --digest-out "$DIG" \
         ${diff:+--diff "$diff"} ${sections:+--changed "$sections"})"

     review_payload_representable "$ART" || { printf '%s failed unrepresentable-payload\n' "$agent" >> "$OUTCOMES"; continue; }

     VERDICT="$(review_budget_check "$BYTES" "$MODE")"
     if [ "$VERDICT" != "ok" ]; then
       review_refusal_message "$agent" "$MODE" "$BYTES" "$VERDICT" \
         "$(review_rank_files .speccraft/guardrails.md .speccraft/index.md "$ROUND_SPEC")"
       printf '%s refused %s\n' "$agent" "$VERDICT" >> "$OUTCOMES"
       continue                                # PER AGENT: others still run
     fi

     # aux-delegator is a pure dispatcher here: it sends these bytes unmodified.
     review_dispatch_payload "$CMD" "$MODE" "$ART"
   done
   ```

   Refusal is **per agent**. One over-budget reviewer must not sink a round the
   other reviewers can still complete — and a refused agent is recorded as a
   non-verdict, so it cannot be mistaken for an agent that simply agreed.

   Invoke the `aux-delegator` subagent once per selected agent, passing
   `payload_file`, `input_mode` and `cwd` (the root `speccraft-state find-root`
   reports). It **must not** recompose anything. Run agents in parallel; per-agent
   timeout from `agents.toml.defaults.review_timeout_s` (default 600s).

   Every reviewer receives the spec, `guardrails.md` and `index.md` inline, and
   the two reference-tier memory files as a path, a byte size and a heading index
   — the `--reference` hand-off above. Nothing else is added to what a reviewer
   sees; in particular `history.md` is not sent.

4. Collect outcomes — one record per **required** reviewer, appended to
   `$OUTCOMES` (`$REVIEW_ROUND_TMPDIR/outcomes.txt`) as
   `<agent> <outcome> [detail…]`:
   - a verdict: `approve` | `approve-with-comments` | `changes-requested` |
     `reject`, with `concerns[]`, `suggestions[]`, `guardrail_violations[]`,
     `convention_violations[]`;
   - or a non-verdict: `refused` (pre-dispatch budget refusal), `timeout`,
     `failed`, `attestation-failed`.

   Validate each verdict's reference-read attestation before counting it:
   ```bash
   if ! review_validate_reference_access "$RESPONSE" "$DIG"; then
     printf '%s attestation-failed %s\n' "$agent" "$(review_validate_reference_access "$RESPONSE" "$DIG" || true)" >> "$OUTCOMES"
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
     review_finalize_round "$SPEC_DIR" "$QUORUM" "$OUTCOMES"
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
   review_finalize_round "$SPEC_DIR" "$QUORUM" "$OUTCOMES"
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
