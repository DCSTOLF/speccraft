---
spec: "0008-ci-hardening"
reviewers: [codex]
quorum: 1
verdict: approve
generated: 2026-05-29T00:00:00Z
round: 3
---

# Cross-model review — 0008-ci-hardening (Round 3, final)

> **Round 3 (final). Supersedes the round-1 and round-2 reviews.**
> Reviewer roster: codex (codex-cli 0.135.0, model gpt-5.5) — real execution, verdict `approve`.
> claude-p: unavailable rounds 2 and 3. Aux-delegator's Bash tool-permission scope was denied in both sessions (verbatim: "Permission to use Bash has been denied"). Not a transient error; appears persistent in this session. claude-p was not counted in either round.
> Quorum requirement: 1 approve / approve-with-comments. **Quorum MET.** Spec moves to `status: reviewed`.

---

## codex (codex-cli 0.135.0, model gpt-5.5)

**Verdict:** approve

Concerns: none

Suggestions:

- Clarify in implementation notes (plan.md or commit-message convention) that the changelog URL write and `status: closed` flip live in the **same commit**, with the parent commit still `status: draft`. This is the timing condition that makes the pre-close gate safe; making it explicit avoids future drift.

Guardrail violations: none

Convention violations: none

---

## Three-round concern disposition

| Concern (raised) | R2 status | R3 status |
|---|---|---|
| AC #4 — closed-spec 0007 immutability (R1) | Fixed | Confirmed clean |
| AC #2 entrypoint contract loose (R1) | Fixed | Confirmed tight |
| AC #5 `ENVIRONMENT_FAILURE` undefined (R1) | Partially fixed | Matcher-enumerated; codex no longer concerned |
| Go scope ambiguous (R1) | Fixed | Confirmed |
| AC #4b self-referential closed-spec immutability (R2) | — | Deleted; replaced with §Post-merge verification (pre-close gate). Codex explicitly verified the timing argument: the changelog write and `status: closed` flip in the same commit, parent still `status: draft`, is not a post-close edit. |
| AC #5 auth category subjective (R2) | — | Auth matchers enumerated; codex no longer concerned. |

---

## Synthesis

All round-1 and round-2 blockers are resolved. Codex raised no new concerns. The single non-blocking suggestion (same-commit invariant) is low-effort and worth capturing at planning time.

### What is strong

- All round-1 and round-2 blockers resolved with no regressions introduced.
- Pre-close gate design avoids the closed-spec immutability constraint cleanly. Codex confirmed the timing argument: changelog URL plus `status: closed` in one commit, parent still `status: draft`, does not constitute a post-close edit.
- AC #5 `ENVIRONMENT_FAILURE` matchers are concrete enough that two independent implementers will converge on the same classification boundary.
- §Post-merge verification (pre-close gate) correctly separates PR-review deliverables from close-time verification. AC #4 gives reviewers a structural check that does not depend on waiting for a main-branch green run.
- Go scope explicitly bounded; deferred out of scope.

### Non-blocking suggestion (codex)

When writing plan.md or the commit-message convention for close-time work, state explicitly that the `specs/0008-ci-hardening/changelog.md` URL entry and the `status: closed` flip must appear in the **same commit**, with the parent commit still at `status: draft`. This invariant is what keeps the pre-close gate safe from the closed-spec immutability rule; naming it prevents future implementers from inadvertently splitting the writes across two commits.

### Operational notes

- **claude-p tool-permission issue** persists across rounds 2 and 3 in this session. To restore two-reviewer coverage on future specs: add `Bash(claude -p:*)` to `.claude/settings.json` `permissions.allow`, or run the parent session in `bypassPermissions` mode, or introduce a pre-approved script wrapper. Not blocking for spec 0008.
- **codex `--full-auto` deprecation** warning has appeared on three consecutive runs. Switch `.speccraft/agents.toml` to `--sandbox workspace-write`. Out of scope for spec 0008.

---

**Action:** Spec 0008 is approved. Proceed with `/speccraft:spec:plan`. The spec is small (6 ACs, 1 operational section, ~98 lines); planner output should be tight. When planning, encode codex's same-commit suggestion as either an implementation note in plan.md or a named task that states the commit-time invariant explicitly.
