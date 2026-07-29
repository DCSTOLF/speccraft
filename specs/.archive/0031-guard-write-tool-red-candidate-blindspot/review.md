---
spec: "0031"
title: "TDD guard Write-tool red-candidate blind spot"
reviewers: [codex, claude-p]
quorum: 1
verdict: approve-with-comments
rounds: 2
generated: 2026-07-24T00:00:00Z
---

# Cross-model review — 0031 TDD guard Write-tool red-candidate blind spot

## Round 2 outcome (revision 1) — REVIEWED

Diff-focused re-review of revision 1 (which folded in the seven r0 blockers).

- **codex:** `changes-requested` → down to a SINGLE residual: the frontmatter
  omitted `reserves-specs: ["0032"]` (a real convention, `.speccraft/conventions.md`
  §"Optional: `reserves-specs`"). Confirmed blockers 1–3 and 5–7 adequately
  resolved; explicitly validated the ToolName change is Rust-compatible, AC1(d)
  is a sound defensive discriminator test, and AC7's characterization test does
  not perpetuate the bug.
- **claude-p:** `approve-with-comments` → all 7 r0 blockers resolved, no new
  contradictions. Two minor notes: the same `reserves-specs` field, and §What
  not spelling out the non-Write/non-Edit branch. Explicitly validated the three
  judgment calls: AC7 "pin current behavior" is correct (observable contract, not
  bug-entrenchment), AC6's 1.7.1 patch bump is correct SemVer, AC5's static check
  complements (not conflicts with) the behavioral fixtures.

**Resolution (folded into revision 1):**
- Added `reserves-specs: ["0032"]` to the frontmatter (codex's sole blocker;
  claude-p's convention note).
- Added a §What bullet defining the discriminator's default branch: any tool name
  other than Write/Edit → post-edit content equals pre-edit content → no
  red-candidates captured (the conservative default AC7 pins).

**Quorum:** met (claude-p `approve-with-comments`); codex's single residual was a
one-line frontmatter add, resolved in-text. Spec advanced to `reviewed`.
Convergence in 2 rounds — the diff-focused re-review kept round 2 scoped to the
r0-blocker deltas.

---

# Round 1 (revision 0) — retained for provenance

# Cross-model review — 0031 TDD guard Write-tool red-candidate blind spot

**Quorum:** NOT met. Quorum requires 1 agent to return `approve` or
`approve-with-comments`; both `codex` and `claude-p` returned
`changes-requested`, independently, with substantially overlapping findings.
The spec remains `draft` — it needs an edit-then-re-review pass, not a plan.

## codex

**Verdict:** changes-requested

Concerns:
- AC1/What use `old_string == ""` to identify Write, which does not
  unambiguously distinguish tool types; `ToolName` should drive
  Write-vs-Edit. Plain Go `string` fields also can't distinguish an absent
  JSON key from an explicitly empty one, so a genuine empty-content Write
  and an Edit with empty `old_string` collapse to the same `ToolInput`
  unless `ToolName` participates.
- AC3 describes a Write-shaped `tool_input` but doesn't require
  `ToolName == "Write"`; the regression test must exercise the full
  PreToolUse envelope including `tool_name`, and cover both creation AND
  overwrite semantics.
- AC4 is underspecified: doesn't pin the two-call `processToolUse`
  scenario, fake-runner result, sibling layout, expected test ID, or proof
  the normal red-check path ran; could pass via an override or another
  allow branch.
- "No override is consumed" (AC4) is ambiguous: starting with no pending
  override can't prove non-consumption; starting with one would make
  `prodGuardPrologue` bypass the runner. Require no override provisioned
  AND proof of runner-backed authorization (runner invoked with the
  captured ID, returns `OutcomeAtLeastOneFailed` with a matching failed
  record, nil production-edit result).
- AC5 permits grep-only even though corrected behavioral fixtures prove
  the contract; doesn't prohibit retaining helpers that infer Write from
  empty `old_string`.
- `MultiEdit` is gated but unmodeled → latent instance of the same
  fail-closed blind spot; deferral OK only with a concrete traceable
  follow-up (reserved/numbered spec), not a prose mention. `NotebookEdit`
  needs explicit disposition too.
- Rust scope is contradictory: says Rust already worked via disk state
  AND that Rust shares the broken `applyEdit` path; state exact affected
  Rust Write behavior and test, or explicitly exclude.

Guardrail violation:
- Open-questions bullet 1 invites folding a build-failed-as-RED carve-out,
  which conflicts with the guardrail "a production edit requires an
  OBSERVED failing just-added test; `OutcomeBuildFailed` is not RED;
  brand-new-symbol bootstrap uses a one-shot override." Keep it OUT.

Convention violation:
- Red-check capture must model the proposed edit with `applyEdit` and
  preserve fail-closed semantics — inferring tool semantics from empty
  `old_string` rather than the PreToolUse `tool_name` violates this.

## claude-p

**Verdict:** changes-requested

Concerns:
- Keep `applyEdit`'s Write/Edit branch keyed on `tool_name`, not the
  `old_string == ""` heuristic.
- AC4's "no override consumed" needs a named observation mechanism.
- AC4 covers only Go+Python while AC3 covers all three languages — align
  coverage.
- `MultiEdit`/`NotebookEdit` are an identical latent bug that should at
  least get a regression guard even if the fix stays out of scope.

Convention violations:
1. No version-bump plan — per `.speccraft/conventions.md` §Version bumps
   and spec 0021's release chain, a guard BEHAVIOR fix warrants a version
   bump with a sibling version-assertion test (spec 0030 bumped
   1.6.1→1.7.0 for a comparable guard/plumbing change).
2. The PreToolUse hook tool-enumeration convention
   (`.speccraft/conventions.md` §"PreToolUse hook tool enumeration",
   coverage asserted by
   `tests/hooks/pre-tool-use-state-guard.bats` "one case per gated tool
   name") implies each gated tool deserves explicit payload-modeling
   coverage.

## Orchestrator-verified facts (high confidence)

- `HookInput.ToolName` (`json:"tool_name"`) IS available to the guard —
  `hooks/pre-tool-use.sh` forwards the full envelope via
  `exec speccraft-guard pre-tool-use <<<"$INPUT"`, and `main.go` decodes
  `tool_name`. The ToolName-driven discriminator is feasible with **no new
  plumbing**.
- The tool-enumeration convention is real:
  `GATED_TOOLS="Edit Write MultiEdit NotebookEdit"`;
  `tests/hooks/pre-tool-use-state-guard.bats` exercises one case per gated
  tool.
- Current version is 1.7.0 (just shipped by spec 0030); a bump here would
  be 1.7.0→1.7.1 (behavior fix, patch) or 1.8.0 — the spec should state
  which and justify it against convention.

## Synthesis

Both reviewers converge strongly on the same root issue: **the spec's fix
still discriminates Write vs. Edit by the shape of the payload
(`old_string == ""`) instead of by the PreToolUse envelope's `tool_name`.**
This is a self-inflicted repeat of the class of bug the spec is meant to
fix — inferring tool semantics from incidental payload shape instead of
the explicit, already-available signal. Since `HookInput.ToolName` is
verified to be present with no new plumbing required, there is no
technical reason to keep the heuristic; this is BLOCKING.

Both reviewers also independently flag that AC4 (the end-to-end no-override
claim) is too weak to prove what it claims, and that MultiEdit/NotebookEdit
being unmodeled is a live instance of the same class of bug that deserves
more than a prose mention. claude-p additionally surfaces a convention gap
(no version-bump plan) that codex didn't raise but that is a real,
citable convention (spec 0030 precedent) — treat it as blocking-before-plan
alongside the others, since shipping a guard behavior fix without a version
bump breaks a documented release convention.

### Prioritized findings

**BLOCKING before plan (both agents converge, or a real convention/guardrail hit):**
1. **ToolName-driven discriminator** (both). Rewrite `applyEdit` (or a
   discriminated edit-op) to switch on `ToolName == "Write"` vs.
   `"Edit"`, not `old_string == ""`. Preserve Edit's replace semantics even
   with an empty `old_string` (an Edit with empty old_string is not a
   Write and must not be silently reinterpreted as one).
2. **AC4 causal-chain strengthening** (both). Replace "no override
   consumed" (unfalsifiable as stated) with an assertion of the full
   causal chain: fake runner is invoked exactly once, invoked with the
   captured canonical test ID, returns `OutcomeAtLeastOneFailed` with a
   matching failed record, production edit result is nil (allowed), and no
   override was provisioned going in.
3. **AC3 full-envelope + overwrite + language parity** (codex explicit,
   claude-p implicit via AC3/AC4 coverage mismatch). AC3's test must send
   the full `HookInput{ToolName: "Write", ...}` envelope (not just a bare
   `tool_input`), cover both file-creation and file-overwrite, and AC4
   should either match AC3's three-language coverage or the spec should
   state explicitly why Go+Python is sufficient (e.g., "one JS/TS case is
   representative of the shared extractor path already covered in AC3").
4. **MultiEdit/NotebookEdit concrete follow-up** (both). Do not leave this
   as a prose aside in "Out of scope." Add an explicit disposition in this
   spec (regression guard proving the current false-block behavior is
   intentional and documented) and reserve a numbered follow-up spec, not
   just a mention.
5. **Version-bump AC** (claude-p, backed by cited convention + spec 0030
   precedent). Add an AC stating the target version bump (1.7.0→1.7.1,
   patch, per orchestrator-verified current version) with a sibling
   version-assertion test, per `.speccraft/conventions.md` §Version bumps.
6. **Resolve OQ1 out of scope, firmly** (codex, guardrail-level). The
   open question about `OutcomeBuildFailed`-as-RED must be closed as
   explicitly out of scope for this spec, not left open for review to
   decide — leaving it open invites a guardrail violation (build-failed is
   not RED; that guardrail is not negotiable within this spec).
7. **Clarify Rust scope** (codex). The "Rust already worked via disk state
   AND shares the broken `applyEdit` path" sentence is self-contradictory.
   State precisely what changes for Rust (if anything) and either add a
   Rust regression case or explicitly exclude Rust with justification.

**Should-fix (single-agent but well-reasoned, doesn't block the plan phase but should land in this pass):**
- AC5: require the corrected behavioral fixtures to be the actual proof
  (not grep-only), plus add a narrow static check that no Write-labeled
  helper sets `NewString` without `Content` (codex).
- AC1 case enumeration: Write with non-empty content, Write with empty
  content, Edit with non-empty `old_string`, and a case where
  `NewString` is populated on a Write payload to prove it's ignored
  (codex, folded into the discriminator rewrite).

**Nits:**
- None called out separately by either agent beyond the above; all raised
  points affect either the fix's core contract, its regression coverage,
  or a real convention.

### Open questions — explicit resolutions

- **OQ1 (build-failed-as-RED carve-out):** Resolve as **OUT of scope**,
  stated plainly, not left open. This aligns with the existing guardrail
  ("a production edit requires an OBSERVED failing just-added test;
  `OutcomeBuildFailed` is not RED; brand-new-symbol bootstrap uses a
  one-shot override"). The open question can remain recorded as a
  possible *future* spec idea, but the spec.md text must not imply this
  spec's review is free to fold it in.
- **OQ2 (fold MultiEdit in?):** Resolve as **do NOT fold the fix in** to
  this spec — scope stays Write-only, matching the spec's own "Why" and
  evidence (spec 0030 incident). Instead: (a) reserve a numbered follow-up
  spec for MultiEdit/NotebookEdit payload modeling, and (b) add a
  regression-guard/disposition AC in *this* spec proving the current
  MultiEdit/NotebookEdit behavior (still fail-closed/blocked) is known and
  intentional, not silently reintroducing the same blind spot under a
  different tool name.

## Recommended spec edits

a. **Rewrite What + AC1** so `applyEdit` (or a discriminated edit-op)
   switches on `ToolName`: `"Write"` → use `Content` as full post-edit
   content; `"Edit"` → `strings.Replace(pre, OldString, NewString, 1)`,
   preserved byte-for-byte even when `OldString == ""`. Enumerate AC1
   cases explicitly:
   - Write, non-empty `Content` → returns `Content`.
   - Write, empty `Content` → returns `""`.
   - Edit, non-empty `OldString` → unchanged replace behavior.
   - Write payload with `NewString` also populated → `NewString` is
     ignored (proves the branch is keyed on `ToolName`, not on which
     fields are populated).

b. **AC3**: send the full envelope,
   `HookInput{ToolName: "Write", ToolInput: {FilePath, Content}}`
   with `NewString` absent. Cover both creation and overwrite. Either keep
   one case per language (Go/Python/JS-TS) or explicitly state that one
   JS/TS representative case suffices to cover the shared extractor path,
   and justify why.

c. **Rewrite AC4** as two ordered `processToolUse` calls (Write of the
   test file, then Edit of the production file) against an active
   in-progress spec state; fake runner receives the captured canonical
   test ID and returns `OutcomeAtLeastOneFailed` with a matching failed
   record; assert exactly one runner invocation, a nil production-edit
   result (allowed), and that no override was provisioned at any point in
   the scenario.

d. **AC5**: require the corrected behavioral fixtures themselves to be the
   proof the contract holds (not a grep-only check), plus add a narrow
   static check/test asserting no Write-labeled helper sets `NewString`
   without `Content`.

e. **Add a version-bump AC**: state the target version (1.7.0→1.7.1, per
   orchestrator-verified current version and this being a behavior-fix
   patch) with a sibling version-assertion test, and note the release
   path per `.speccraft/conventions.md` §Version bumps (spec 0030
   precedent).

f. **Add a MultiEdit/NotebookEdit disposition AC**: a regression guard (or
   documented false-block test) proving current behavior is known/
   intentional, plus a line reserving a specific numbered follow-up spec
   for the MultiEdit/NotebookEdit payload-modeling fix.

g. **Clarify the Rust bullet**: resolve the internal contradiction —
   state precisely whether/how Rust's Write path is affected by this fix,
   and either add a regression case or explicitly and non-contradictorily
   exclude Rust.

## Action

The spec is `draft`; the canonical path is edit-then-re-review, not a new
spec. **Fold the seven BLOCKING items above into spec.md** (the ToolName
discriminator is the highest-priority item — it is the same class of bug
the spec exists to fix), then re-run `/speccraft:spec:review` before
proceeding to `/speccraft:spec:plan`. Do not plan against the current
draft: AC1/AC3/AC4 as written would let an implementation pass review
while still discriminating Write vs. Edit by payload shape rather than by
`tool_name`, which is the exact defect class this spec is meant to close.
