---
spec: "0015"
reviewers: [codex, claude-p]
quorum: 1
verdict: approve-with-comments
generated: 2026-06-10T01:00:00Z
---

# Cross-model review — 0015

## codex

**Verdict:** changes-requested

Concerns:
- The versioning ownership is contradictory: §spec-reviser purpose says the agent must not modify `revision:`, but §Versioning says the spec-reviser inserts it if absent. The ordered mechanism also leaves missing `revision:` untouched on a no-op, despite saying the field is required from this spec forward.
- The cross-check command claims POSIX portability while specifying `grep -r --include='*'`; `--include` is a GNU grep option, not POSIX. This weakens the stated rationale for choosing grep over ripgrep.
- The spec does not define behavior for invalid or missing `packages[]` paths, non-list package values, or paths outside the repo. Those cases affect safety and testability because the command shells out over user-controlled frontmatter paths.
- The no-op comparison says whitespace-only or terminal-newline deltas are ignored, but does not define the normalization algorithm. That can create ambiguous implementation and tests, especially if the agent rewrites wrapping or frontmatter spacing.
- AC7 asserts that the spec-reviser subagent was invoked, but the spec does not define a structural observable for invocation in the empty-packages case. Without a mock/stub mechanism or required stdout marker, that part is hard to test reliably.
- Archive mutation ordering is only partially specified. Step 10 sets `revision` before renaming artifacts and status, but an interruption after the frontmatter edit can leave a revised spec with stale downstream artifacts; the out-of-scope partial-failure note permits this, but the risk should be called out deliberately.

Suggestions:
- Move all `revision:` insertion and incrementing into command-owned logic, and state that the agent never inserts or edits command-owned frontmatter fields.
- Replace `grep -r --include='*'` with a portable shape, or explicitly require GNU grep in the command environment.
- Add preflight validation for `packages[]`: each entry must be a clean repo-relative file or directory path that exists, contains no glob syntax, and does not escape the repo.
- Define no-op normalization concretely, for example compare contents after trimming trailing horizontal whitespace and final newline only, or simplify to byte-identical comparison.
- Make AC7 structural by requiring the command to print a fixed handoff line before invoking the agent, or by using an explicit test fixture stub for `spec-reviser`.

**Guardrail violations:** none

**Convention violations:**
- rule: "Bash/portability claim: command specifies GNU grep option while describing grep as POSIX/universally available"
  location: "§What / Cross-check execution"

---

## claude-p

**Verdict:** approve-with-comments

Concerns:
- AC11 requires `model:` in spec-reviser.md frontmatter, but conventions.md §Markdown frontmatter only mandates `name/description/tools` for subagents. AC12 explicitly notes its tightening of conventions; AC11 makes the same shape change implicitly without the matching note, and without a paired §Convention amendment commitment.
- AC8's `^Q-DRIFT:` structural anchor only satisfies the spec-0014 "structural over content" convention if the prefix is load-bearing in the spec-reviser's prompt template. The spec asserts the agent "must emit" the prefix but never says the spec-reviser.md prompt body pins it as a required output-format token. Without that, AC8 grep'ing for `^Q-DRIFT:` is structurally indistinguishable from a content-grep — it depends on the model honoring an instruction in prose.
- Step 7's agent contract says the spec-reviser "must not modify" `revision:/status:/id:/created:`, but the command has no post-agent diff-check that reverts unauthorized frontmatter edits. If the agent ignores the contract, the command silently lets it through.
- Identifier extraction scans "single-backtick OR fenced code" but the §What rationale ("explicit opt-in mechanism") only holds for single-backticks. Fenced code blocks in spec.md commonly hold example code (YAML samples, hook envelopes, mock argv) full of identifiers the author never meant to assert exist in packages[].
- AC3/AC4/AC5/AC8 all depend on the spec-reviser subagent actually running and emitting a "real edit" or a Q-DRIFT line. The spec does not say whether these ACs run in a cheap e2e tier or the gated devcontainer tier. Spec 0011's e2e budget concern applies.
- Step 6 says cross-check uses `grep -r --include='*'`. `-r` is a GNU extension and `--include='*'` is a no-op. The spec's own justification text ("POSIX, universally available") is incorrect.

Suggestions:
- Add AC13 (or extend AC4) asserting the next-step suggestion `/speccraft:spec:review` appears on stdout after a real-change revise — step 10d describes it but no AC covers it.
- Specify the no-op detection mechanism at implementation level: presumably `cp specs/<id>/spec.md $TMPDIR/spec.md.pre` then `diff -q` post-agent, since "in memory" is not meaningful in a Markdown slash command.
- AC6 says "a spec.md whose only delta is whitespace or terminal newline is also considered a no-op" but `diff -q` is whitespace-sensitive; clarify whether `diff -wB` or an explicit normalization step is intended.
- Deduplicate extracted identifier tokens before grep'ing. A spec.md with a token mentioned eight times should not produce eight identical Q-DRIFT questions.
- Add a sentence about token-boundary semantics: grep without `-w` matches `Foo` inside `FooBar`. State whether this is intentional.
- Add a sibling AC for the symmetric collision case on a `planned` source where `plan-r<N>.md` exists but `review-r<N>.md` does not.

**Guardrail violations:** none

**Convention violations:**
- rule: "Markdown frontmatter (subagents require name/description/tools — model is not in the documented contract)"
  location: "AC11 asserts a `model:` key is required, but conventions.md §Markdown frontmatter does not list it. AC12 acknowledges its tightening; AC11 does not."

---

## Synthesis

Quorum is met: claude-p returned `approve-with-comments`. codex returned `changes-requested`. Per the decision rule the overall verdict is `approve-with-comments`.

The round-2 spec.md has resolved the most critical round-1 blockers (AC7 structural anchor, revision-bump ownership, archive collision, draft-source path, spec-reviser purpose, packages contract, grep vs ripgrep). Two issues survived into round-2 with independent convergence from both agents. These must be fixed before `/speccraft:spec:plan` is run. All other findings are refinements that can be tracked as plan-time tasks.

### Must-fix before plan (both agents converged)

**1. GNU grep vs POSIX claim.**
Both agents independently flagged that `grep -r --include='*'` uses GNU-only options (`-r` for recursive, `--include` for file-pattern filtering) while the spec's own justification text says grep is "POSIX, universally available." `--include='*'` is also a no-op (it matches all files, which is the default). The convention violation is live in §What / Cross-check execution. Fix: either replace the invocation with a portable form (e.g. `find <pkg-path> -type f | xargs grep <token>`) or drop the POSIX claim and explicitly state GNU grep is required in the command environment.

**2. `revision:` insertion ownership is still split.**
The §spec-reviser purpose paragraph correctly prohibits the agent from modifying `revision:`. However, §Versioning still says "the spec-reviser inserts it if absent on a target lacking the field." These two statements are contradictory. codex flags this as concern #1; claude-p flags the related gap (no post-agent diff-check that would catch unauthorized frontmatter edits). Fix: remove the insertion responsibility from the spec-reviser entirely. The command (step 2 or step 10a) must insert `revision: 0` if the field is absent, before or during the preflight phase, so the agent never needs to touch it. The spec-reviser.md prompt body must also explicitly prohibit writing `revision:`, `status:`, `id:`, and `created:`.

### Plan-time refinements (single-agent findings)

The following items were raised by one agent and do not block plan, but should become explicit implementation tasks:

- **AC11 `model:` field (claude-p).** AC12 acknowledges it tightens conventions.md; AC11 makes the same change silently. Either add an acknowledgment sentence to AC11 mirroring the AC12 pattern, or fold the `model:` requirement into the same follow-up amendment already committed in AC12.
- **Q-DRIFT structural anchor must be pinned in the prompt body (claude-p).** AC8 greps for `^Q-DRIFT:` but the spec only instructs the agent in prose. The spec-reviser.md prompt template must contain a required-output-format instruction that makes `Q-DRIFT:` a load-bearing token, not a politely requested one.
- **Post-agent frontmatter integrity check (claude-p).** The command should diff `revision:`, `status:`, `id:`, and `created:` before and after the agent runs and exit non-zero if any changed, to enforce the "agent must not modify" contract structurally.
- **Fenced-code block extraction scope (claude-p).** The rationale says "explicit opt-in mechanism via backticks," but fenced code blocks contain example identifiers the author never meant to assert. Clarify during implementation whether fenced blocks are included or excluded from the extraction scan.
- **e2e tier assignment for agent-dependent ACs (claude-p).** AC3/AC4/AC5/AC8 all require the subagent to run. Spec 0011's e2e budget concern applies; mark these ACs for the gated `e2e-devcontainer` tier, not `e2e-language-only`.
- **No-op normalization algorithm (codex).** "Whitespace or terminal newline" is not a precise comparison predicate. The implementation task should specify the exact diff invocation (e.g. `diff -wB` or explicit trailing-newline strip) to avoid ambiguity.
- **`packages[]` preflight validation (codex).** Paths that escape the repo, contain globs, or do not exist should be caught at preflight with a named error, consistent with the existing preflight pattern for archive and source artifacts.
- **AC7 subagent-invocation observable (codex).** The empty-packages branch asserts the subagent was invoked but provides no structural signal. The implementation task should define either a required stdout handoff line or a fixture stub approach.
- **Token deduplication and word-boundary semantics (claude-p).** Dedup extracted tokens before grep'ing; document whether `grep -w` is used or substring matches are intentional.
- **AC13 for next-step suggestion stdout (claude-p).** Step 10d prints `/speccraft:spec:review` but no AC asserts it. Add an AC or extend AC5.

**Action:** Before running `/speccraft:spec:plan`, make exactly two edits to spec.md:

1. Fix the `grep -r --include='*'` invocation in §What / Cross-check execution: replace with a portable form or replace the "POSIX, universally available" rationale with an explicit GNU grep requirement. Remove `--include='*'` as it is a no-op.
2. Resolve the `revision:` insertion split: delete the "spec-reviser inserts it if absent" sentence from §Versioning and assign that responsibility to the command (step 2 or a new step between 2 and 3: "If `revision:` is absent, insert `revision: 0` before proceeding"). The spec-reviser must never insert or modify command-owned frontmatter fields.

All other findings above are plan-time tasks and do not require spec.md edits before plan.
