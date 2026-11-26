---
spec: "0054"
reviewers: [codex, claude-p]
quorum: 1
verdict: approve-with-comments
status: draft
generated: 2026-10-16T00:00:00Z
single_vendor_approval: false
---

# Cross-model review — 0054

## Round table

| round | payload | template | codex (`openai`) | claude-p (`anthropic`) | confirmed |
|---|---|---|---|---|---|
| 1 | — | full | changes-requested | **attestation-failed** | — (INERT) |
| 2 | 42,686 B | full | changes-requested | changes-requested | 4 P1 + 2 conv |
| 3 | 80,165 B | scoped | changes-requested | approve-with-comments | 4 (+1 refuted) |
| 4 | 89,268 B | scoped | changes-requested | approve-with-comments | 6 |
| 5 | 94,261 B | scoped | changes-requested | approve-with-comments | 4 |
| 6 | 98,465 B | scoped | changes-requested (1) | approve-with-comments | 3 |
| 7 | 99,871 B | scoped | changes-requested (2) | approve-with-comments (2) | 4 (all minor) |
| 8 | 102,490 B | scoped | changes-requested (2) | approve-with-comments (**0**) | 2 (1 substantive) |
| 9 | 106,505 B | scoped | **approve** (`concerns: []`) | **approve-with-comments** | 4 (all cosmetic) |

Every round from 2 on: both attested, outputs hash-distinct, git tree
unchanged. Round 9: `responses_complete: true`, `approval_quorum_met: true`.
Outputs `c186e221…` / `a492c45d…`.

**This is the first round both reviewers approve, and the first cross-vendor
approval.** `review_agent_vendor` resolves `codex` → `openai` and
`claude -p …` → `anthropic` (argv[0] basename), so the approvals no longer
share the author's vendor: **`single_vendor_approval: false`**, for the first
time in nine rounds. Rounds 3-8 each met quorum on a lone `anthropic`
approval; this one does not depend on it.

## codex — approve

**Verdict:** approve (attested), `concerns: []`, `guardrail_violations: []`,
`convention_violations: []`.

"The deltas resolve both substantive findings from the prior review… The
amended contracts and acceptance criteria agree with the new prose. I found no
regression against the previously settled attestation, distinct-artifact,
quarantine, cleanup, quorum, external-tool-boundary, or non-review-consumer
requirements. The two suggestions above concern test/prose precision only and
do not block implementation."

Two suggestions, both **CONFIRMED** and both test/prose precision:

- **AC14e cannot observe what it asserts without help.** It asserts the
  `.building-<expiry>-<rand>` names carry two different expiries, but a
  *successful* creation renames them away — so the AC must say it observes them
  through controlled interleaving or instrumentation, or it describes an
  unobservable state. (Same class as round 5's unreachable-AC14d finding, which
  is why it is worth fixing rather than waving through.)
- **"active at the time of the mismatch" is not knowable.** A pre/post snapshot
  yields no mutation timestamp, so the attribution rule's trigger must be
  defined over the **snapshot interval** — a subagent active at any point
  between the pre- and post-snapshot — not over an instant the mechanism cannot
  observe.

## claude-p — approve-with-comments

**Verdict:** approve-with-comments (attested). One concern, **CONFIRMED**,
cosmetic but worth the one-word fix.

- **`.building-*` naming is spelled two ways.** §3 line 261 and the
  `review_round_sweep` contract (line 750) say
  `.building-<expiry-unix-ts>-<rand>` / `.building-<expiry>-<rand>`, while the
  `review_round_dir_create` contract line 733 still says
  `.building-<ts>-<rand>` — which reads as a **creation** timestamp. An
  implementer working from the Contracts section alone could ship a creation-ts
  name, and the sweep would then have no expiry to read. Exactly the precision
  class rounds 7-8 flagged.

Suggestions: rename `<ts>` → `<expiry-unix-ts>` in the creator contract line so
all three statements use one spelling; sharpen AC14c from "older than one lease
period" (which reads age/mtime-based) to "once the expiry encoded in its own
name has passed"; and add one sentence making `codex-plugin`'s position
explicit — `touchedFiles` is **self-attested and trusted**, a lying companion
being a different threat model — since the current prose reads as
"`codex-plugin` is exempt", which is close but not the actual guarantee.

## Convention violations

_none from either reviewer in rounds 3-9._

## Synthesis

**The spec has converged.** Both vendors approve; the dissenting reviewer of
the previous eight rounds returns `concerns: []`; and all four remaining items
are one-word or one-phrase precision fixes that neither reviewer treats as
blocking. codex: "do not block implementation." claude-p: "Neither comment
blocks approval… the spec is ready for `/speccraft:spec:plan`."

**The arc, by severity:**

| round | character of findings |
|---|---|
| 2 | 4 P1 + 2 convention — wrong facts about the companion interface |
| 3 | 4 contradictions between new prose and new ACs |
| 4 | 1 mechanism gap + 3 contract-text |
| 5 | 1 guarantee-scope decision + 3 bounded |
| 6 | 1 self-inflicted contradiction + 2 mechanical |
| 7 | 4 × contract-text precision, 0 substantive |
| 8 | 1 contract-text + 1 substantive (attribution → quorum) |
| 9 | 4 × cosmetic, 0 substantive, **both vendors approve** |

Two things are worth recording for the plan. First, **three findings across
rounds 5-6 were introduced by the immediately preceding revision**, not
pre-existing — which is why every claim in every round was re-verified against
the spec text rather than counted, and why one claim (round 3's `fable`) was
refuted rather than applied. Second, **the two mechanisms that took longest to
settle both converged on the same principle**: the tree snapshot needed four
iterations and the lease duration three, and both ended at *the artifact
describes itself* — content digests over an inventory, and an absolute expiry
in the directory name over a value the reader recomputes. That is the
generalizable lesson from this spec's review, not a detail of either mechanism.

**Remaining work before `/speccraft:spec:plan`** — four fixes, no decisions:
1. `<ts>` → `<expiry-unix-ts>` in the `review_round_dir_create` contract line.
2. AC14c: "once the expiry encoded in its own name has passed", not age-based.
3. AC14e: state that the transient `.building-*` names are observed via
   controlled interleaving/instrumentation.
4. Attribution trigger: "active at any point in the pre/post snapshot
   interval", and one sentence that `codex-plugin`'s `touchedFiles` is
   self-attested and trusted rather than exempt.
reviewed_sha256: fb319ceac6bdb2cd94a6f521fc8be32b931228775f9b07e009214299631ff147
