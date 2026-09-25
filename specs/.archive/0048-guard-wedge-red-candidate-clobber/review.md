---
spec: "0048"
reviewers: [codex, claude-p]
quorum: 1
rounds: 3
verdict: approve-with-comments
generated: 2026-08-09
---

# Cross-model review — 0048 (3 rounds)

## Provenance

Six aux-agent invocations across three rounds, all with distinct output digests. This is
recorded explicitly because spec 0047's round 1 produced a **false quorum**: two
delegators wrote the same unqualified temp path and the second returned the first's bytes
as its own verdict. Every round here used per-agent, per-round output paths, and all six
digests were compared for collisions before any synthesis.

| Round | Agent | Bytes | md5 | Verdict |
|---|---|---|---|---|
| 1 | codex | 5708 | `5645b13e7eec6d1be8db6f2d34fae684` | changes-requested |
| 1 | claude-p | 8931 | `7e00cf23e663ba9e2da8914b8df9306e` | changes-requested |
| 2 | codex | 3548 | `fea1a9161c3d949691f11980936a7ed8` | changes-requested |
| 2 | claude-p | 9687 | `b7c4f55c73493b2c30633a5776658090` | approve |
| 3 | codex | 3523 | `2a04e6b33810c18683f051606aa9be39` | changes-requested |
| 3 | claude-p | 5853 | `cf4555d8e9097059d514fdbe885e65b6` | approve |

No collisions. Rounds 2 and 3 were scoped re-reviews: round 2 via the `--diff` provenance
gate (`prior == base_fingerprint` → `scoped`), round 3 via an explicit delta brief that
attached codex's round-2 findings and required a RESOLVED / PARTIAL / NOT-RESOLVED
disposition for each.

## Outcome

**Quorum met** (`review_quorum = 1`; claude-p approved in rounds 2 and 3). Final verdict
recorded as **approve-with-comments** rather than plain approve, because codex never
withdrew to approve and the last revision is unreviewed (see §Residual risk).

## Round 1 — both changes-requested

The headline finding, reached independently by both reviewers, was a genuine design
defect: §What.A's "overlay still fails to build → allow the edit, record it" branch was
an **unbounded bypass** of the red→green invariant. While the tree did not build, *any*
Go production edit was admitted, with no observed RED and no override. Codex filed it as
a formal `guardrail_violations` entry; claude-p reached the same conclusion in discussion.
The spec's defence — that an unobservable signal is not really a bypass — did not survive
contact: unobservable-therefore-allow-everything is not a narrower rule, it is no rule.

Also blocking, both reviewers: the two deferred open questions (overlay package pattern,
probe deadline) were load-bearing — AC1/AC2/AC3/AC5 had no oracle without them; the
`build-repair` record was under-specified; and it had no consumer, so the spec shipped
state nothing read.

Single-reviewer findings, each verified against source before being accepted:

- **AC4 was unsatisfiable** — the message at `main.go:562-566` interpolates `res.Stderr`
  via `%s`, so "byte-identical" is impossible (claude-p).
- **AC6 collided with `GOCACHE`** — `go build` writes the cache, defeating a whole-root
  byte snapshot (claude-p).
- **Path normalization** was underspecified across overlay keys, baseline keys and
  `red_candidates` (codex).
- **Baseline best-effort had a hole** — a failed first-touch write lets a later touch set
  a wrong baseline and silently lose the standing candidate (codex).

Both reviewers independently recommended landing the prober in the cmd package on the
`processToolUse` seam rather than as a new `runner` export.

## Round 2 — codex changes-requested, claude-p approve

The revision adopted the bounded, self-closing repair mode codex proposed, pinned all
three probe parameters, named the `deps.proberForLang` seam, added the close-time
consumer, fixed AC4 and AC6, and decided the bootstrap seam. claude-p approved and
confirmed no regressions.

Codex held out with six concerns. Three were correct and material:

1. **The bound was per-episode, not per-session.** A clean probe reset the allowance, so
   break → 10 edits → repair → break again → 10 more was unbounded in aggregate. This was
   the sharpest catch of the review.
2. **The claim "feature work cannot be smuggled through repair mode" was false.** AC6
   deliberately admits unrelated edits, and a clean build does not retroactively
   establish that admitted edits participated in a red→green cycle.
3. **The fingerprint constrained nothing** — recorded but never compared, and
   "normalized" was undefined.

Plus: AC10 overclaimed future-proofing, and the baseline failure path was fail-closed but
not recoverable.

## Round 3 — codex changes-requested (1 of 6 remaining), claude-p approve

Codex marked five of six resolved. Both reviewers then converged independently on the
same genuine logic error in the round-3 poison-recovery text:

> the documented next-touch recovery cannot actually restore `TestAlpha` as a candidate,
> because that touch baselines already-poisoned disk content containing `TestAlpha`
> — codex

claude-p framed it as an either/or: capture failure must *either* block the test-file edit
(disk clean, touch 2 is a real retry) *or* the candidate is genuinely lost and AC14's
"candidate again" is wrong. This was a real incoherence, not a wording nit.

Codex also raised a new `convention_violation`: `.speccraft/conventions.md` still stated
that the build-failure rule must never be relaxed, directly contradicting the new §A.5
guardrail carve-out.

claude-p judged the guardrail amendment **acceptable as policy**, and named what would
change its mind: evidence the 10-edit cap is hit routinely (making it a standing
allowance rather than an escape hatch); a Go pre-edit gate becoming available at
comparable effort (which would close the language asymmetry at source and make repair
mode unnecessary); or evidence the close-time report goes unread, making the audit
theatre. It also noted codex's alternative — routing still-broken allowances through
`/speccraft:spec:override` — does not reduce the number of bypasses, it relabels them,
and spec 0047's 0→5 overshoot is evidence the override budget is exactly what the wedge
blows through.

## Post-round-3 revisions (unreviewed)

Applied after the last reviewer round, each a direct adoption of a reviewer proposal:

- **Capture failure now blocks the test-file edit** (claude-p's option (a)). Because the
  guard runs in `PreToolUse`, refusing the edit leaves disk byte-unchanged, so the retry
  re-captures correctly. The capture-failed marker is removed entirely — it could not
  recover, only produce a nicer error. AC14 rewritten around the disk-unchanged assertion.
  This is a deliberate behaviour change: it is the one case where a test-file edit is
  refused.
- **`.speccraft/conventions.md` amended alongside `guardrails.md`** (codex).
- **AC18's anti-drift pin made bidirectional and mechanical** (claude-p): the test reads
  the compiled `buildRepairMaxEdits` and asserts that value appears in the guardrail's
  carve-out sentence, regex-anchored on the sentence rather than the bare numeral.

## Residual risk

1. **The final text is unreviewed.** The three changes above landed after round 3. They
   adopt reviewer-proposed remedies, but no reviewer has seen the result. The
   `reviewed_sha256` below is the fingerprint of the final text; it records what the spec
   *is*, not that every line of it was reviewed.
2. **Codex never approved.** Its round-3 position was that a bounded, logged bypass is
   still a bypass. That objection is answered by policy (§A.5 amends the guardrail
   explicitly rather than arguing the exception away), not by mechanism — a reader who
   rejects the carve-out should reject the spec.
3. **AC6 is a deliberate trade.** Unrelated edits are admitted while the build is broken,
   because relatedness is not inferred. Bounded at 10 per session and logged, but real.

## Stopping rule

Stopped at three rounds. Round 1 → 2 closed eight of nine blocking findings; round 2 → 3
took codex from six concerns to one; round 3's residue was a single convergent logic error
plus two mechanical pins, all now applied. The signal for stopping is that the remaining
disagreement is **a policy judgement both reviewers have now stated clearly** rather than
an unresolved defect — further rounds would re-litigate the carve-out, not improve it.

## Action

Proceed to `/speccraft:spec:plan`. Carry into planning: the unreviewed post-round-3
delta, the 1-override budget, and AC14's disk-unchanged assertion as the load-bearing
half of the capture-failure test.
reviewed_sha256: 31668e7dda2ea0be09616b7fc82aec8f1a991e6507e05c8391252c22ba024fe3
