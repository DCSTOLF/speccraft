---
description: "Cross-model review of the current diff against the active spec"
argument-hint: "[--base <ref>]"
allowed-tools: ["Read", "Bash", "Write", "Agent", "TaskStop", "Bash(shasum:*)", "Bash(sha256sum:*)"]
---

Cross-model review of uncommitted changes (or `git diff <base>...HEAD`).

**IMPORTANT**: Execute ALL steps below using your tools before responding. Do
not describe steps — carry them out.

Steps:

1. Resolve the plugin root (for the prompt template path below):
   ```bash
   PLUGIN_ROOT="$(speccraft-state plugin-root)"
   source "$PLUGIN_ROOT/commands/spec/review.lib.sh"
   ```

**Dispatch is mode-aware and shared.** The registry's `mode` selects how each
reviewer is reached: `cli` and `acp` go through `aux-delegator`,
`codex-plugin` drives the Codex plugin's companion, and `subagent` is
dispatched by **this orchestrating session** via the Agent tool — a shell
cannot start one. The full procedure (compose, budget-check, dispatch by
mode, record outcomes, attestation, the subagent timeout protocol) lives in
the shared `review-round` runbook at `skills/review-round/SKILL.md`. Follow it
rather than re-deriving a per-command variant.

2. **Freeze the diff ONCE, before any reviewer is dispatched.**
   ```bash
   ROUND_DIR="$(review_round_dir_create code "$(date +%s)" "$TIMEOUT_S")"
   DIFF_ART="$(review_freeze_diff "$ROUND_DIR" ${BASE:+"$BASE"})"
   ```
   `review_freeze_diff` runs `git diff HEAD` by default, or
   `git diff <ref>...HEAD` when `--base <ref>` was passed, and writes **one**
   artifact into the round dir. A second freeze in the same round is a named
   refusal.

   This ordering is the point. The working tree is live while a round runs, so
   recomputing the diff per agent lets two reviewers dispatched a second apart
   review different bytes — and then a disagreement between them is
   indistinguishable from a disagreement about the same change. It also makes
   the payload digest a `subagent` attests meaningless, because the thing
   hashed would be recomputed per reviewer.

   **Untracked files are NOT in the reviewed diff.** Both git forms exclude
   them, deliberately: that is what makes the frozen diff reproducible from the
   recorded `HEAD`. Say so in the round's output (step 5) — a reviewer or an
   operator who is not told assumes the diff is everything that changed and
   signs off on a branch carrying a brand-new file nobody read. Widening the
   scope to untracked files is out of scope for this command.

3. **No active spec is fine — the round still runs.** This command reviews a
   DIFF, so a spec is not required, and refusing without one would break
   exactly the ad-hoc change it exists for.
   ```bash
   ACTIVE="$(jq -r '.active_spec // ""' .speccraft/state.json 2>/dev/null || true)"
   if [ -n "$ACTIVE" ] && [ -f "specs/$ACTIVE/spec.md" ]; then
     SPEC_SRC="$ROUND_DIR/spec-frozen.md"
     cp "specs/$ACTIVE/spec.md" "$SPEC_SRC"      # the ONE read of spec.md this round
   else
     SPEC_SRC="$ROUND_DIR/no-active-spec.md"
     review_no_active_spec_notice > "$SPEC_SRC"
   fi
   ```
   The stand-in is written rather than left empty: the composer always emits a
   "Spec under review" heading, and nothing under it reads as a truncated
   payload rather than as a deliberate absence.

4. **Compose per agent from the frozen diff, then budget-check, then dispatch**
   — in that order, following the shared runbook. Each agent gets a DISTINCT
   artifact path; the diff is read from `$DIFF_ART`, never recomputed.
   ```bash
   OUTCOMES="$ROUND_DIR/outcomes.txt"; : > "$OUTCOMES"
   TEMPLATE="$PLUGIN_ROOT/templates/prompts/review-code.md"

   for agent in $AGENTS; do
     ART="$ROUND_DIR/$agent.payload"; DIG="$ROUND_DIR/$agent.digests"
     BYTES="$(review_materialize_payload "$ART" \
       review_compose_payload "$TEMPLATE" "$SPEC_SRC" \
         --inline .speccraft/guardrails.md .speccraft/index.md "$DIFF_ART" \
         --reference .speccraft/architecture.md .speccraft/conventions.md \
         --digest-out "$DIG")"
     # budget-check, dispatch by mode, record the outcome: see the runbook.
   done
   ```
   Refusal is **per agent**: one over-budget reviewer must not sink a round the
   others can still complete, and a refused agent is recorded as a non-verdict
   so it cannot be mistaken for one that agreed.

5. Synthesize via the `cross-reviewer` subagent and **report on stdout only** —
   this is per-iteration, not per-spec, so nothing is written to the spec dir.
   The report must print, alongside the verdicts:
   - the diff form used (`git diff HEAD`, or `git diff <ref>...HEAD`);
   - **the untracked-file exclusion**, stated plainly, so the operator knows a
     brand-new unstaged file was not reviewed;
   - which spec the diff was checked against, or that no spec was active.

6. If any agent flags a `guardrail_violation` or `convention_violation`,
   surface it prominently. The user decides whether to fix or override.

7. Clean the round up only once every reviewer is terminal — see the runbook's
   cleanup gate. A round with a reviewer still pending is quarantined, not
   deleted.
