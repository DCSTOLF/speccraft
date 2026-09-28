# Review — spec 0052

Six rounds, two reviewers per round, every output hash-verified distinct.

| round | payload | codex | claude-p |
|---|---|---|---|
| 1 | 185,372 B | changes-requested | approve-with-comments |
| 2 | 193,123 B | changes-requested | approve-with-comments |
| 3 | 197,238 B | changes-requested | approve-with-comments |
| 4 | 202,576 B | changes-requested | approve-with-comments |
| 5 | 209,104 B | changes-requested | approve-with-comments |
| 6 | (confirmation round — see below) | | |

The payload column is itself a finding: the review prompt grew **24 KB across
five rounds** purely because the spec under review got longer. By round 5 it had
passed the `REVIEW_MAX_PAYLOAD_BYTES` derivation basis — this spec's review
would refuse itself under the rule it proposes, which is exactly the case the
raise-me protocol in AC21 exists for.

## Round-1 incident: a false quorum, caught

Round 1 dispatched both reviewers through the `aux-delegator` subagent. Both
wrote artifacts to the **same** paths and returned **byte-identical** YAML —
every concern, every suggestion, including the same `spec 0014 farewell`
citation. Two different models do not produce identical output.

Re-running both CLIs directly with isolated paths produced three distinct
hashes: the surviving round-1 artifact matched neither genuine run, and codex's
real verdict (5,176 B) differed completely from what had been reported as
codex's. The round-1 "codex" report was claude-p's output relabelled.

**Durable lesson (for conventions.md at close):** an aux review round MUST give
each agent a distinct artifact path, and the synthesis MUST hash-compare outputs
before counting verdicts. Identical hashes across two agents are a dispatch bug,
not agreement. Without that check a round can report a quorum of N having
actually consulted one model — the same class of defect this spec exists to
prevent, arriving through the dispatch layer instead. Every round from 2 onward
used isolated paths and verified distinct hashes.

## Findings that changed the design

**Round 1 — a provably wrong criterion.** codex showed AC10's own example could
not refuse: `REVIEW_MAX_ARGV_BYTES=1 review_budget_check 2 stdin` returns `ok`,
since the argv limit does not apply to stdin and 2 bytes is far below the
payload default. Verified and corrected.

**Round 2 — quorum conflation (blocking).** The spec's below-quorum rule used
"verdict count", but `review_quorum` counts *agreeing* agents while
`review.md:75-79` writes `review.md` and stamps the fingerprint on *response
completeness* — "for ANY verdict including `changes-requested`". The rule as
written would have forbidden exactly what this session legitimately did in round
1. Split into `responses_complete` and `approval_quorum_met` (AC22/AC23).

Also round 2: `input: file` is a real third mode and ACP entries carry no
`input` key at all; the composer could not represent the scoped `--diff` payload
at all; and `history.md` had been added to the reference tier although it is not
sent today — scope creep inside a spec about bounding scope. All corrected.

**Round 3 — the attestation was theatre.** The spec proposed a **read sentinel**
placed in each reference record for the reviewer to echo. codex correctly killed
it: the sentinel is *in the prompt*, so echoing it proves only that the reviewer
read the prompt. It attested nothing while reading as though it did — the same
silent-plausibility failure the reference tier itself risks. Replaced with a
**content digest the reviewer computes**, expected value withheld from the
payload.

**Round 4 — the digest's own complexity.** Dispatching against an immutable
snapshot gave every reference two identities (the path named versus the path
read) and made access depend on a temp location a sandboxed CLI may not open.
Escalated as a design decision; resolved by digesting the **live file** and
dropping the snapshot. The residual TOCTOU window is seconds wide and fails
safe — a mismatch means the verdict is not counted, the same outcome as an
unread reference.

Also round 4: `reference_read` as a required flag would have broken every
already-initialized repo on `git pull`, since none carry the key. Made opt-out
(absent means `true`).

**Round 5 — ACP exempted, and a portability trap.** ACP is `acpx <agent>
<prompt>` — argv transport — but AC19's mode matrix omitted it, so an
implementation could have exempted the mode most likely to overflow. And
`sha256sum` is GNU-only: the spec guarded `awk` intervals meticulously while
leaving the identical BSD/GNU trap open on its primary attestation primitive.

## A reviewer claim that was wrong

Round 5 codex reported a `convention_violations` entry: that command libs must
be "pure functions with no filesystem mutations", violated by the composer
writing the payload artifact.

**This is incorrect.** `conventions.md:739` defines pure as *no side effects at
source time* — "sourcing the file from bats must be a no-op other than defining
functions". Filesystem-mutating functions are sanctioned precedent:
`revise.lib.sh` ships `archive_rename`, `snapshot_spec` and `bump_revision`, all
of which write. The citation was checked against the source before acting on it.

The underlying *suggestion* was adopted anyway on its own merits: the composer
now emits to stdout and the command driver owns the single artifact, which also
sidesteps the command-substitution trailing-newline strip.

## Verified independently during synthesis

claude-p predicted **code-block blindness** in the heading index. Checked: **0
of `conventions.md`'s 55 headings fall inside a fence today**, so the predicted
bug does not currently manifest — the risk is prospective, and AC4 now pins a
full fence grammar for it.

Verifying it surfaced a defect that *is* live and that neither reviewer named.
This environment's `awk` is **mawk, which does not support `{n,m}` intervals**,
and fails silently:

```
$ printf '## a\n### b\n' | awk '/^#{2,3} /{print "MATCH: "$0}'
(no output)
```

A `review_heading_index` written as `/^#{2,3} /` would emit **zero headings**
here and a full index under GNU `grep -E`, with no error either way — spec
0050's BSD-grep class exactly. `compact.lib.sh:26` already encodes the avoidance
(`[0-9][0-9][0-9][0-9]`, never `{4}`). Pinned by AC5 on both a source scan and a
behavioral arm, because a source scan alone would pass on a broken extractor.

## Disposition

The design was endorsed by both reviewers from round 2 onward and never
challenged: the tier split, the pre-dispatch budget, the two-predicate
separation, and the explicit rejection of auto-fallback, section-excerpting and
`ARG_MAX` probing all survived five rounds. Every finding landed in the
acceptance criteria, not the approach.

The spec went from 12 criteria to 29, consecutively numbered, with a `Contracts`
block pinning signatures and a `Notes for the plan` section warning against
atomizing shared seams.
reviewed_sha256: 46bd782e1b5797a7633b896ff5c0bd7d193548bc55756d201be5f234147f2883
