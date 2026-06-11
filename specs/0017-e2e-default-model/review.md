---
spec: "0017-option"
reviewers: [codex, claude-p]
quorum: 1
verdict: approve-with-comments
generated: 2026-06-11T00:00:00Z
---

# Cross-model review — 0017-option

## codex

**Verdict:** approve-with-comments

Concerns:
- The rationale depends on a mutable external fact: the Claude CLI/account default being "currently Opus 4.8". The implementation need is valid without that claim, but the claim may age quickly or be hard to verify from the repo.
- The spec does not require a verification step that the exact model identifier `claude-sonnet-4-6` is accepted by the installed Claude CLI in CI.

Suggestions:
- Rephrase the Why section around making CI model selection explicit and cost-controlled, and add a lightweight validation note or manual check for the selected model alias before merging.

## claude-p

**Verdict:** approve-with-comments

Concerns:
- The entire justification rests on the unverified claim that "Sonnet 4.6 is sufficient." The e2e exists to validate plugin behavior driven by a real model; dropping the default tier changes the model under test. No trial run or evidence is offered that the ~10-call lifecycle still passes its assertions on Sonnet.
- The "What" code block omits the trailing `> "$LOG_DIR/$log" 2>&1` redirect and the `|| { ... exit 3 }` failure path that exist at run.sh:177-189. A reader applying the snippet literally would delete the combined-capture shape that the assertion pins and that the spec-0008 AC#5 classifier depends on — also violating this spec's own AC4. The snippet should be marked as illustrating the single inserted line, not a full replacement of the block.
- No test strategy for the behavioral criteria. AC1 is grep-testable; AC2/AC3 (env-var precedence) — if guaranteed by bash `${VAR:-default}` semantics and needing no test, say so explicitly so the planner does not invent a brittle one.

Suggestions:
- Add a `CLAUDE_MODEL` line to the `--help` usage block (run.sh:42-43), mirroring how `CLAUDE_BIN` is an overridable env var — otherwise the override path is undiscoverable.
- State the recovery path if Sonnet regresses on push-to-main: the override is local-only, so a CI failure would require a code change or a manual re-run with the env var set.

Convention violations:
- **Slug and title are placeholder values.** The spec dir is `specs/0017-option/` and frontmatter title is `"option"` — neither is descriptive. Convention requires a meaningful slug, e.g. `0017-e2e-default-model` with a matching title such as "Pin e2e default model to Sonnet 4.6".

## Synthesis

Both reviewers approve the change as technically sound and correctly scoped. The `${CLAUDE_MODEL:-claude-sonnet-4-6}` expansion is correct (treats empty as unset, satisfying AC2 and AC3). The insertion point (first argument after `-p` in `run_claude`) is accurate per the source. The job-isolation claim in AC4 is structurally valid: `e2e-language-only` short-circuits before `run_claude` is invoked, and the other jobs never call `claude`. No guardrail violations were found by either agent.

**Grouped concerns, by priority:**

1. **Snippet incompleteness (claude-p only, minor but spec-as-contract).**
   The "What" code block ends at `"$prompt"` but omits the I/O redirect and error-exit tail that follows in the real file. As written, a planner applying it literally would truncate the block. Mark the snippet explicitly as showing only the inserted `--model` line, or extend it to the full block.

2. **Sonnet-sufficiency claim is asserted, not evidenced (both agents, independently).**
   codex flags that the Opus-4.8 default claim may age; claude-p flags that no trial run confirms Sonnet passes the full lifecycle. The stronger, durable rationale is: CI should not inherit an account-level model default at all — cost control and determinism are sufficient justification regardless of what Opus costs today. Adding one sentence acknowledging that the next `e2e-devcontainer` run on main IS the validation gate converts this from an assertion to an honest plan.

3. **Model ID is never validated in CI (codex).**
   A bad model alias would silently break the expensive job. AC1 (grep-testable) verifies the string is present but not that the CLI accepts it. A pre-merge manual check, or a note in the ACs, would close this gap.

4. **Slug and title are placeholders (claude-p, convention violation).**
   `0017-option` / `"option"` convey nothing. Rename the slug to something like `0017-e2e-default-model` and update the title (e.g., "Pin e2e default model to claude-sonnet-4-6") before the spec advances to `planned`.

5. **Override is undiscoverable (claude-p, minor).**
   `CLAUDE_MODEL` is not listed in the `--help` usage block alongside `CLAUDE_BIN`. Add it there so operators know the knob exists.

6. **No documented recovery path for a Sonnet regression (claude-p, minor).**
   The spec should note that if Sonnet causes a CI failure, the remediation is either a code change or re-running with `CLAUDE_MODEL=claude-opus-4-5` (or whichever model is desired).

**Action:** Advance to `reviewed`. Before or at the `planned` transition, address the following non-blocking items:

- Rename the spec dir slug and frontmatter title to something descriptive (item 4 above — this is the only convention violation and should be fixed first).
- Clarify the "What" snippet to make explicit it shows only the inserted line, not a complete replacement (item 1).
- Reframe the Why section to lead with "CI must not inherit an account-level model default" rather than the current Opus pricing claim (item 2).
- Add `CLAUDE_MODEL` to the `--help` usage block in the implementation task (item 5).
- Add a sentence to the ACs or Out-of-scope noting that AC2/AC3 rely on shell expansion semantics and need no separate test, and that the next `e2e-devcontainer` run validates Sonnet sufficiency (items 2 and 3).
