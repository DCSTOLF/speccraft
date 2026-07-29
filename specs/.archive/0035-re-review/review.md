---
spec: "0035"
reviewers: [claude-p, codex]
quorum: 1
verdict: approve
generated: 2026-07-26T00:00:00Z
---

# Cross-model review — 0035-re-review

## Round 1 (2026-07-25)

| Agent | Verdict |
|---|---|
| claude-p | changes-requested |
| codex | not run (blocked by auto-mode classifier; requires explicit user authorization of `codex exec --full-auto`) |

Quorum requirement: 1 agent giving `approve` or `approve-with-comments`. **Not met** this round — the single agent that produced a verdict returned `changes-requested`, and the second configured agent (codex) did not run at all, so there is no approving verdict to satisfy quorum.

## claude-p

**Verdict:** changes-requested

Concerns:
- AC6's either/or ("exits non-zero OR reports a distinguished `"snapshot": false` envelope") is unresolved, and the non-zero branch also **violates the detect-stack convention**: a first-review-with-no-snapshot is a legitimate, resolvable state, so convention dictates exit 0 with a distinguished envelope, not a non-zero exit reserved for genuinely unresolvable cases. Pick one path and pin it in the spec.
- AC5 mixes two anchor-identifier schemes ("markdown section heading(s) / acceptance-criteria numbers") without saying which one wins or how they compose for `changed_sections`. Since reviewer prompts will embed these strings verbatim, the exact identifier form (heading text? slug? `"AC N"`? `"## Acceptance criteria/N"`?) has to be nailed down before there is a testable oracle.
- AC7 requires a constructed reviewer payload/template that includes changed sections plus a regression-sweep instruction, but the injection mechanism is unspecified. Slash commands are static markdown, so how the diff + AC list get into the prompt (a preprocessor? a state subcommand emitting the payload? a formatting subagent?) is load-bearing for AC7's oracle — the spec currently describes the WHAT without committing to a HOW a test can pin.
- AC10 asserts the snapshot doesn't break the drift scan, but `review-snapshot.md` is a byte-copy of `spec.md` and may itself contain `enforce:` prose. Either `speccraft-drift` must explicitly exclude `review-snapshot.md` by name/glob, or this AC is a live false-positive-rule-duplication risk that the spec doesn't resolve.
- Snapshot write **timing** is unpinned: AC1 doesn't say when in the review flow the snapshot is written. If it's written after dispatch, a mid-review edit to `spec.md` can leave the snapshot diverging from what reviewers actually saw (and from the fingerprint in AC2). Pin the write to the moment the reviewer payload is constructed, not "at review time."
- Snapshot lifecycle at spec close is undefined — does `review-snapshot.md` persist in the closed spec directory forever, get archived, or get removed? Inert now, but will confuse any future re-open path; cheaper to decide once, here.

Suggestions:
- Have `speccraft-state` own the snapshot **write** (e.g. `speccraft-state review-snapshot write <spec-dir>`), not just the diff read — mirrors the "state.json only writer" pattern, gives AC1/AC2 a single call site, and makes them testable via a Go test rather than a bash fixture.
- Flag the AC13 new-symbol bootstrap trap explicitly in the plan: `review-diff` is a wholly new subcommand/type (`RunReviewDiff`/`ReviewDiff`), so the `json.Unmarshal` envelope trick from spec 0034 doesn't apply — expect and pre-authorize ONE override to introduce the new symbol rather than discovering it mid-execution.
- State explicitly that AC11's version-bump-in-lockstep across guard/drift binaries is a no-op-behavior bump, not evidence those binaries changed — future readers of a spec that changes one binary out of step will otherwise be confused by the precedent.
- Clarify the AC4/AC9 division of labor: the short-circuit is the command's response to `review-diff`'s `{"changed": false}` — state binary owns detection, command owns UX — so a reader doesn't think the short-circuit is enforced in both layers (or only one).
- Reconsider whether byte-identical (AC4) is too strict: a trailing-newline or whitespace-only edit invalidates the snapshot and triggers a full diff even though nothing semantic changed. If byte-identical is the intentional, safer default, add a one-line note to head off a future "why did whitespace trigger a full review" report.
- Consider recording fingerprints for `plan.md`/`tasks.md` too, even though only `spec.md` is diffed now — cheap to add today, avoids a schema migration if a future spec extends diffing to those files.

## codex

**Verdict:** not run

Codex was configured as the second aux reviewer for this round but did not produce a verdict. The dispatch was blocked by Claude Code's auto-mode safety classifier, which refuses to let a subagent run `codex exec --full-auto` (an autonomous agent loop with sandbox/approvals disabled) without explicit user authorization of that specific command. This is an environment/authorization gap, not a codex rejection of the spec — no concerns, suggestions, or violations were produced.

## Synthesis

Both the motivation and scope of 0035 are sound: the snapshot-at-review-time anchor (vs. git history) correctly targets the common case of an uncommitted draft spec mid-review-cycle, and the out-of-scope list heads off the obvious scope-creep hazards (semantic diffing, git anchoring, quorum/verdict changes, closed-spec re-review). The blocking issues are all contract-level ambiguities in the acceptance criteria, not implementation details — they need to be pinned in spec.md before plan.md can produce testable oracles:

1. **AC6's either/or is also a convention violation.** The non-zero-exit branch for "no prior snapshot" contradicts the detect-stack convention (resolvable states exit 0 with a distinguished envelope). This is the one flagged convention violation and the most severe single item — it must be resolved before this spec can proceed, since it double-counts as both an ambiguity and a rule breach.
2. **AC5's anchor-identifier scheme is unresolved** — heading text vs. slug vs. "AC N" vs. a combination — and this identifier is exactly what gets embedded in reviewer prompts, so it's load-bearing for the AC5/AC7 oracles.
3. **AC7's payload-construction mechanism is undefined.** The spec says a reviewer payload must be scoped to changed sections plus a regression-sweep instruction, but slash commands are static markdown — there's no stated mechanism (preprocessor, state subcommand emitting the payload, or a formatting step) for injecting the diff + AC list. Without this, AC7 can't be tested.
4. **AC10's drift-scan interaction is a live risk**, not just a documentation gap: a snapshot that's a byte-copy of spec.md can carry `enforce:`-style prose that `speccraft-drift` may misinterpret as duplicate rules. The spec must say whether `speccraft-drift` excludes `review-snapshot.md` by name/glob.
5. **Snapshot write timing is vague** ("at review time") and needs to be pinned to the payload-construction moment so the fingerprint in AC2 and what reviewers actually saw never diverge.
6. **Snapshot lifecycle at spec close is unaddressed** — decide now (persist / archive / remove) rather than leaving it to be discovered by a future re-open feature.

No guardrail violations were reported. One convention violation was reported (see AC6, detailed above and in claude-p's section).

The suggestions are all non-blocking refinements and can be folded into the same revision pass: `speccraft-state` as sole snapshot writer, pre-authorizing the expected `ReviewDiff`/`RunReviewDiff` new-symbol override, clarifying the version-bump-is-a-lockstep-noop precedent, clarifying AC4/AC9 layering, deciding on byte-identical strictness (and documenting the whitespace-edge-case tradeoff if kept), and optionally fingerprinting `plan.md`/`tasks.md` for future-proofing.

**Action:** Revise `specs/0035-re-review/spec.md` to resolve, at minimum, the four must-fix ambiguities before re-review:
1. Pin AC6 to a single exit-code/envelope contract for "no prior snapshot" that follows the detect-stack convention (exit 0, distinguished envelope — not non-zero).
2. Pin AC5's `changed_sections` identifier scheme to one concrete, unambiguous form.
3. Specify AC7's payload-construction mechanism (what emits the scoped reviewer prompt, and how).
4. State AC10's `speccraft-drift` exclusion for `review-snapshot.md` explicitly (or otherwise resolve the false-positive risk).

Also pin the snapshot-write timing (AC1) and decide the snapshot lifecycle at spec close, and fold in the non-blocking suggestions above where cheap. Once revised, re-run `/speccraft:spec:review`. If the user explicitly authorizes `codex exec --full-auto` for this project, re-run review with codex included to get a genuine second opinion toward quorum; until then, quorum rests solely on claude-p and currently is not met.

---

## Round 2 (2026-07-25)

Diff-focused re-review (dogfooding the diff-review feature itself) against `spec.md` rev2, which folded in all four Round-1 must-fix items plus the timing/lifecycle pins.

| Agent | Verdict |
|---|---|
| claude-p | approve-with-comments |
| codex | not run (still blocked by the same auto-mode classifier on `codex exec --full-auto`; requires explicit user authorization) |

Quorum requirement: 1 agent giving `approve` or `approve-with-comments`. **MET** this round — claude-p's `approve-with-comments` alone satisfies quorum=1.

### claude-p

**Verdict:** approve-with-comments

claude-p confirmed all four Round-1 blockers are resolved in rev2:

- **AC6 exit-code either/or** — resolved. AC6 now exits 0 with `"snapshot": false` for the no-prior-snapshot case, matching the detect-stack convention exactly; the Round-1 convention violation no longer applies.
- **AC5 anchor scheme** — resolved. The new "Anchor scheme" subsection unambiguously pins `changed_sections` to verbatim `##`-level heading text, with per-line/per-AC-number explicitly rejected.
- **AC7 payload mechanism** — resolved. AC7 now names the concrete artifact (`templates/prompts/re-review.md`), specifies what's injected, who injects it, and a grep-oracle verification path.
- **AC10 drift interaction** — resolved. `review-snapshot.md` lives under `specs/`, outside `.speccraft/`, and AC10 requires a regression test pinning drift's scan scope excludes `specs/**`.

Concerns raised (all non-blocking polish, rev2 wording only):
- Fingerprint algorithm ambiguity in AC1/AC2/AC4 (no stated normalization for CRLF/LF/BOM/trailing-newline).
- `##`-heading anchor scheme's interaction with the non-normative "Implementation notes" section was unaddressed (could surface as a `changed_sections` entry with no scoping note).
- AC7's grep oracle described the needle language but didn't pin the exact verbatim strings.
- AC10's regression test location (which package/file) was unnamed.

Suggestions: matched 1:1 with the concerns above — pin sha256 + raw-bytes explicitly, add a scoping note (or explicit inclusion) for `##`-heading detection over Implementation notes / Out of scope, name the two grep needles verbatim, and name the AC10 test file.

### codex

**Verdict:** not run

Same environment/authorization gap as Round 1: the auto-mode safety classifier blocks a subagent from invoking `codex exec --full-auto` without explicit user authorization of that specific command. Not a codex rejection — no concerns, suggestions, or violations were produced. Codex remains available as a second opinion if the user explicitly authorizes the command for this project.

### Polish items — resolution status (rev3)

All four Round-2 polish items were folded into `spec.md` as rev3 immediately following this review, before this file was updated:

1. **Fingerprint algorithm ambiguity** → **ADDRESSED**. AC1/AC2/AC4 now pin "sha256 of the raw `spec.md` file bytes," explicitly with no CRLF/LF, BOM, or trailing-newline normalization, plus an idempotence note (AC1: re-invoking with byte-identical `spec.md` reproduces the same fingerprint).
2. **`##`-heading interaction with the non-normative Implementation-notes section** → **ADDRESSED**. The Anchor scheme subsection now states that ALL `##`-level headings are in-scope for `changed_sections` detection, including `## Out of scope` and `## Implementation notes (non-normative)` — no special-casing.
3. **AC7 grep needles underspecified** → **ADDRESSED**. AC7 now pins two verbatim needles: the regression-sweep phrase `assess ONLY the deltas since last review + regressions`, and the injection-point markers `{{CHANGED_SECTIONS}}` / `{{DIFF}}`.
4. **AC10 drift-scope test location unnamed** → **ADDRESSED**. AC10 now names `tools/internal/speccraft/drift_scope_test.go` (with a fallback note if scope resolution instead lives in the `speccraft-drift` cmd package).

### Guardrail / convention violations (Round 2)

- Guardrail violations: none.
- Convention violations: none. The Round-1 AC6/detect-stack convention violation is resolved as of rev2 and remains resolved in rev3.

### Round 2 synthesis

rev2 closed all four Round-1 blockers cleanly and rev3 closed all four residual Round-2 polish items, each with a direct, testable pointer (specific AC, specific field name, specific verbatim string, or specific test file path). No agent flagged a guardrail or convention violation this round. Quorum (1 approve/approve-with-comments) is met on claude-p alone; codex remains unavailable pending explicit user authorization of `codex exec --full-auto`, and running it would still be a valuable second opinion but is not required to clear quorum.

**Action:** Move spec 0035 to `reviewed`. No further spec revision is required before proceeding to `plan.md`. If the user later authorizes `codex exec --full-auto` for this project, an optional codex pass can be run for a second opinion, but it is not a gate.

---

Starting with Round 3, the user explicitly authorized `codex exec --sandbox workspace-write` for this project. From this point on, review dispatched **both** `codex` (`codex exec --sandbox workspace-write`) and `claude-p` (`claude -p`) as independent aux reviewers on every round, using speccraft's diff-focused re-review mode (each round reviews only the delta against the previously reviewed `spec.md` fingerprint). This is the first genuine dual-model convergence run for 0035, and it ran long: nine rounds, rev3 through rev9, driven almost entirely by codex's adversarial passes surfacing correctness bugs claude-p did not catch.

## Round 3 (2026-07-26) — reviewed rev3

| Agent | Verdict |
|---|---|
| codex | changes-requested |
| claude-p | approve-with-comments |

Quorum **met** (claude-p), but codex's `changes-requested` identified substantive correctness problems that were not blocking on quorum grounds alone and were carried forward.

**codex findings:**
1. The read-before-overwrite transaction described for snapshot promotion is unimplementable via separate, directory-based subcommands: each step requires its own read of `spec.md`, opening a TOCTOU window between diff computation and snapshot write.
2. Duplicate `##`-heading identity (e.g. two `## Notes` sections) collapses under a plain `[]string` schema for `changed_sections` — ordinal position isn't representable.
3. The missing-prior-`review.md` branch (first review, snapshot exists but no recorded verdict) is unpinned.
4. AC7's claim that the reviewer payload includes evidence is not oracle-verified — nothing pins that the injected content is actually present, only that the template exists.
5. AC13 is self-contradictory (conflicting statements about what triggers the version bump).
6. The spec's "Why" section over-claims token savings without a basis.

**claude-p findings (approve-with-comments):** suggested per-binary version tests (rather than one combined test), an AC7 negative needle (asserting absence of unrelated content), and pinning `schema: 1` on the envelope for forward-compatibility.

## Round 4 (2026-07-26) — reviewed rev4

| Agent | Verdict |
|---|---|
| codex | changes-requested |
| claude-p | approve-with-comments |

rev4 addressed items 3-6 from Round 3 (missing-prior-review branch, AC7 evidence-inclusion oracle, AC13 contradiction, Why over-claim) and claude-p's three suggestions. codex confirmed those resolved but **sharpened** its two structural objections rather than accepting rev4's fix:
- The read-before-overwrite transaction is still unimplementable across the CLI subcommand boundary — no amount of within-subcommand pinning closes the TOCTOU window between separate `read` and `write` invocations.
- The ordinal is still not representable in the plain-string `changed_sections` schema; annotating prose around the string doesn't give a test anything to assert against.

claude-p reconfirmed approve-with-comments on rev4's changes.

## Round 5 (2026-07-26) — reviewed rev5

rev5 made a structural change to resolve both of codex's Round 4 objections at once: it refolded the transaction onto a single new subcommand, `review-diff --promote`, so the read, diff, and snapshot write happen in one process invocation (no separate read/write calls, no TOCTOU window) and sourced reviewer payloads from the frozen snapshot rather than a live re-read. It also ordinal-encoded duplicate headings directly into the schema.

| Agent | Verdict |
|---|---|
| codex | changes-requested |
| claude-p | approve-with-comments |

codex accepted the `--promote` restructuring as solving the transaction and ordinal problems, but found a new, more serious bug it introduced:
1. **Retry-safety bug**: because `--promote` writes the new snapshot *before* the reviewer is dispatched, and AC9's short-circuit is unconditional on "snapshot unchanged," a review run that fails mid-flight (after promote, before the reviewer actually runs) leaves the snapshot promoted but the review never happened — a subsequent retry sees "unchanged" and silently short-circuits, skipping review entirely.
2. The claimed reserved-anchor collision protection (that a specific anchor name can't collide with a real heading) was factually false as written.
3. Duplicate-count ordinal shifts (what happens to ordinals when a duplicate heading is added or removed between fingerprints) were under-specified.

claude-p approved rev5 with comments (no mention of the retry-safety issue — codex-only finding).

## Round 6 (2026-07-26) — reviewed rev6

rev6 added an AC9 fingerprint-match retry gate (the short-circuit now requires the *reviewed* fingerprint, not just "unchanged since last promote," to match) and switched `changed_sections` to a structured `{kind, heading, ordinal, side}` shape to close the duplicate-ordinal gap.

| Agent | Verdict |
|---|---|
| codex | changes-requested |
| claude-p | approve-with-comments |

codex accepted the retry-gate mechanism in principle but found it didn't cover the actual failure path, plus additional new bugs:
1. **Baseline-provenance bug**: a failed run promotes an unreviewed baseline B (from A); the spec is then further edited to C; the fingerprint-match retry gate only checks "does current match reviewed," so the subsequent review run diffs B→C (scoped correctly against the *promoted* snapshot) but the earlier A→B delta — never actually reviewed — silently escapes review forever.
2. Duplicate-count "over-report" (the structured schema could report more changed entries than actually changed, e.g. re-numbering unrelated duplicates) contradicted the byte-identical short-circuit rule elsewhere in the spec.
3. "Usable" (describing when a snapshot may be promoted/read) was judged too weak/vague to be a testable predicate.
4. AC3 had a direct exit-code contradiction between two clauses.

claude-p approved rev6 with comments (again, no mention of the baseline-provenance issue — codex-only finding).

## Round 7 (2026-07-26) — reviewed rev7

rev7 was the largest single revision of the run. It added `base_fingerprint` to the envelope and a **Provenance gate**: both the scoped-review path and the unconditional short-circuit now require `review.md`'s recorded `reviewed_sha256` to equal `base_fingerprint` before either can fire, closing the baseline-provenance escape from Round 6. It also switched to pure ordinal-key matching for `changed_sections` (eliminating the over-report path), pinned ordinal counting to one canonical document side, strengthened the "usable" predicate to a concrete testable condition, resolved the AC3 exit-code contradiction, required an injected test seam for AC11, and pinned AC2's write-ordering.

| Agent | Verdict |
|---|---|
| codex | changes-requested |
| claude-p | **approve** |

codex confirmed the provenance gate closes the baseline-escape bug and the other Round 6 items are resolved, but held at `changes-requested` on two remaining, narrower items:
1. AC2's verb "returns" (describing when the fingerprint is recorded) is too weak — it doesn't rule out stamping the fingerprint even when the underlying operation failed.
2. The "usable" predicate's grammar was still imprecise enough to leave a testable edge case unpinned.

claude-p moved from approve-with-comments to a clean **approve** on rev7.

## Round 8 (2026-07-26) — reviewed rev8

rev8 rewrote AC2 to require the fingerprint be written only after the review **workflow** completes successfully, independent of the review's verdict (approve/changes-requested/reject all count as "completed successfully" for write purposes) — with nothing written at all on a hard failure. It also pinned an anchored regex grammar for the recorded line (`^reviewed_sha256: [0-9a-f]{64}$`), added heading-whitespace trimming to the anchor scheme, specified the exit code for an unreadable snapshot, and added a command-layer bash oracle for AC11.

| Agent | Verdict |
|---|---|
| codex | changes-requested |
| claude-p | **approve** |

codex's remaining objection narrowed to a single item: AC2's wording — "written after `review.md` is persisted" — is **circular** (it defines the write-ordering in terms of another write happening, without pinning an atomic boundary), so a partially-written `review.md` with the fingerprint line present but the rest of the file truncated (e.g. process killed mid-write) is not ruled out by the spec as written.

claude-p held at approve on rev8.

## Round 9 (2026-07-26) — reviewed rev9 — **DUAL APPROVE**

rev9 resolved codex's sole remaining objection by rewriting AC2 as a single **atomic commit**: `review.md` (including the `reviewed_sha256` line) is fully constructed in a temp file, then atomically renamed into place; "success" is defined as the rename succeeding; there is no intermediate state where the fingerprint line exists without the rest of the file, and any failure prior to the rename leaves the prior `review.md` byte-unchanged. rev9 also pinned that a review timeout does not count as a "returned verdict" (closing a residual AC2 edge case) and reworded AC7's oracle clause (b) to source the current-spec bytes from the frozen snapshot rather than a live re-read.

| Agent | Verdict |
|---|---|
| codex | **approve** |
| claude-p | **approve** |

Both reviewers confirmed all 13 acceptance criteria are deterministically RED-testable with no remaining blocker. The only note carried forward was non-blocking: use a same-filesystem temp file for the atomic rename, and reuse the existing `state.json` temp+rename helper rather than writing a new one — folded into the spec's non-normative Implementation notes rather than gating approval.

---

## Final synthesis (Rounds 3-9)

**FINAL VERDICT = approve (dual-model, quorum well exceeded).**

This review dogfooded the spec's own diff-focused re-review mode across Rounds 2 through 9: each round re-reviewed only the delta against the previously reviewed `spec.md` fingerprint rather than the whole document, which is exactly the workflow 0035 itself implements.

Across Rounds 3-8, codex's adversarial passes drove out four genuine correctness bugs that a single-model review would very likely have missed, since claude-p approved (or approved-with-comments) through every round in which these bugs were present and never independently surfaced any of them:

1. **Unimplementable transaction** (Round 3-4): the read-before-overwrite snapshot transaction couldn't be expressed across separate CLI subcommand invocations (TOCTOU window) — resolved by folding read/diff/write into a single `review-diff --promote` invocation (rev5).
2. **Retry-safety bug** (Round 5): promote-before-dispatch plus an unconditional short-circuit meant a failed run could silently cause a subsequent retry to skip review entirely — resolved by an AC9 fingerprint-match retry gate (rev6).
3. **Baseline-provenance bug** (Round 6): a failed run's promoted-but-unreviewed baseline let one full edit's worth of changes permanently escape review — resolved by the AC2/AC9 Provenance gate requiring `review.md`'s recorded fingerprint to match the base fingerprint before either the scoped review or the short-circuit can fire (rev7).
4. **AC2 atomicity** (Round 7-8): "written after review.md is persisted" was circular and didn't rule out a torn write — resolved by defining the fingerprint write as part of a single atomic construct-then-rename commit (rev9).

This is the productive-disagreement value the field-feedback action plan anticipated from cross-model review: codex's `changes-requested` streak (Rounds 3-8) was not noise or false-positive friction — each round's objection was a real, distinct correctness bug, and each was resolved by a structural spec change (not just wording) before the next round. No guardrail violations were reported in any round. No convention violations were reported past Round 1 (the AC6 detect-stack violation resolved at rev2 and never recurred).

**Action:** Spec 0035 is approved by both configured aux reviewers (codex, claude-p) as of rev9, quorum (1) well exceeded by 2/2 approve. No further spec revision is required. Proceed to `plan.md`.
