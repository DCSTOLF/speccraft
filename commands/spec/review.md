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
   run the read-before-overwrite transaction and classify the round BEFORE
   dispatching. Source the helpers:
   ```bash
   source "$PLUGIN_ROOT/commands/spec/review.lib.sh"
   SPEC_DIR="specs/<active>"
   # ONE read/diff/write: freeze the snapshot from spec.md, capture the envelope.
   ENV="$(speccraft-state review-diff "$SPEC_DIR" --promote)"
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
     `base_fingerprint`). Build reviewer payloads from the just-frozen
     `review-snapshot.md`, never re-reading `spec.md`.
   - `scoped` → for each agent, prepend the populated re-review brief and attach
     the frozen snapshot + prior review as evidence:
     ```bash
     review_build_payload "$PLUGIN_ROOT/templates/prompts/re-review.md" \
       "$SPEC_DIR/review-snapshot.md" "$SPEC_DIR/review.md" "$diff" "$sections"
     ```
   In every `--diff` branch the reviewer-visible spec content comes from
   `review-snapshot.md` (the frozen image), preserving the AC11 single-read
   transaction. Without `--diff`, proceed with the full review at step 3.

3. For each selected agent, invoke the `aux-delegator` subagent with payload:
   - The spec.md content
   - The relevant slice of `.speccraft/` (index.md + guardrails.md +
     architecture.md + conventions.md)
   - The review prompt template from
     `$PLUGIN_ROOT/templates/prompts/review.md`

   Run agents in parallel. Per-agent timeout from
   `agents.toml.defaults.review_timeout_s` (default 600s).

4. Collect verdicts. Each agent returns:
   verdict (approve | approve-with-comments | changes-requested | reject),
   concerns[], suggestions[], guardrail_violations[], convention_violations[].

5. Invoke the `cross-reviewer` subagent to synthesize the responses into a
   coherent `review.md` and an action recommendation.

6. Write `specs/<active>/review.md`. Then, ONLY after the review workflow has
   completed successfully (every required reviewer returned a verdict — a timeout
   is not a verdict — and the synthesis persisted), record the reviewed
   fingerprint as a single atomic commit (spec 0035 AC2), for ANY verdict
   including `changes-requested`:
   ```bash
   FP="$(speccraft-state review-snapshot write "specs/<active>")"  # freeze + sha256
   speccraft-state review-commit "specs/<active>/review.md" "$FP"
   ```
   This stamps exactly one `reviewed_sha256:` line via temp + rename; on any
   failure the prior `review.md` is left byte-unchanged, so a failed round is
   re-reviewed rather than silently trusted. Skip this on a `short-circuit`.

7. Determine quorum (default 1 approve or approve-with-comments):
   - If met: update spec status to `reviewed`.
   - If not met: leave at `draft` and surface the synthesis with next steps.

8. Suggest next step:
   - If reviewed: `/speccraft:spec:plan`
   - If changes-requested: edit spec.md, then re-run `/speccraft:spec:review`
