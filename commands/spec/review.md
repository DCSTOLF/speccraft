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

3. Freeze the round's spec image and dispatch. Do the freeze, the composition and
   the dispatch in **one shell**, so the round's temp directory is live for all of
   them and its cleanup trap can fire:
   ```bash
   ROUND_TMP="$(mktemp -d)"; trap 'rm -rf "$ROUND_TMP"' EXIT HUP INT TERM
   ROUND_SPEC="$ROUND_TMP/spec-frozen.md"
   cp "$SPEC_DIR/spec.md" "$ROUND_SPEC"   # the ONE read of spec.md this round
   # scoped rounds only:
   review_build_payload "$PLUGIN_ROOT/templates/prompts/re-review.md" \
     "$ROUND_SPEC" "$SPEC_DIR/review.md" "$diff" "$sections"
   ```
   Then, for each selected agent, invoke the `aux-delegator` subagent with payload:
   - The frozen spec image (`$ROUND_SPEC`), never `spec.md` re-read
   - The relevant slice of `.speccraft/` (index.md + guardrails.md +
     architecture.md + conventions.md)
   - The review prompt template from
     `$PLUGIN_ROOT/templates/prompts/review.md`

   Run agents in parallel. Per-agent timeout from
   `agents.toml.defaults.review_timeout_s` (default 600s).

4. Collect outcomes — one record per **required** reviewer, written to
   `$ROUND_TMP/outcomes.txt` as `<agent> <outcome> [detail…]`:
   - a verdict: `approve` | `approve-with-comments` | `changes-requested` |
     `reject`, with `concerns[]`, `suggestions[]`, `guardrail_violations[]`,
     `convention_violations[]`;
   - or a non-verdict: `refused` (pre-dispatch budget refusal), `timeout`,
     `failed`, `attestation-failed`.

   Give each agent a **distinct** artifact path and hash-compare the outputs
   before counting them. Identical hashes across two agents are a dispatch bug,
   not agreement — a round can otherwise report a quorum of N having actually
   consulted one model.

5. Gate synthesis on response completeness:
   ```bash
   if ! review_responses_complete "$ROUND_TMP/outcomes.txt"; then
     review_finalize_round "$SPEC_DIR" "$QUORUM" "$ROUND_TMP/outcomes.txt"
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
   review_finalize_round "$SPEC_DIR" "$QUORUM" "$ROUND_TMP/outcomes.txt"
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
   `changes-requested` verdicts persists its `review.md` and stays `draft`.

8. Suggest next step:
   - If reviewed: `/speccraft:spec:plan`
   - If changes-requested: edit spec.md, then re-run `/speccraft:spec:review`
