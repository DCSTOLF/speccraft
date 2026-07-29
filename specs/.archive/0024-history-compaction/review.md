---
spec: "0024"
reviewed: 2026-06-23
round: 2
verdict: approve-with-comments
quorum_met: true
agents: [codex, claude-p]
---

# Cross-model review — 0024 — Bounded, reviewable history.md compaction (round 2)

## Synthesis

Round-1 blockers B1–B6 are confirmed resolved in the revised spec: the
AC2/AC5 supersession-pointer contradiction is fixed (collapse restricted to
out-of-window entries, pointer lives on the archived/summarized side); the
window is now explicitly positional ("first N from the top of the file"); the
clock dependency is gone (count/byte threshold, fixed-path archive); the
deterministic/model-behavior AC split is drawn; the archive contract and summary
schema are defined; and the parsing contract is pinned to the observed header
shape.

Quorum is met (codex: approve-with-comments). The spec moves to `reviewed`.
The carry-forward findings below are precision tightening items — not
architectural rework — and must be folded into `spec.md` before or during
`/speccraft:spec:plan`.

---

## Carry-forward findings (fold into spec/plan)

### CF-1 (MUST — deterministic-tier parsing contract does not match corpus)

**Touches:** AC1, AC3, AC10, the parsing contract, and the supersession seed.

The spec's parsing contract and several ACs assume every entry header has the
form `## YYYY-MM-DD — <title> (spec NNNN)`. The real
`.speccraft/history.md` corpus contains entries with NO spec suffix
("Slash-command names fully qualified…", "Plugin packaged via dcstolf-tools
marketplace", "speccraft adopted") and at least one with a plural form
`(specs 0002, 0003)`. As written, the helper either miscounts the window (if it
requires the suffix) or cannot extract provenance/seed supersession (if it
matches date-only). The spec also conflates two different predicates: it says
entries are "counted by the `## YYYY-MM-DD — <title> (spec NNNN)` header"
AND "the first N such `## YYYY-MM-DD` headers" — those are different match
rules.

**Fix:** The window/COUNT key is the `## YYYY-MM-DD` date prefix alone (all
dated entries qualify, regardless of suffix). The provenance id is OPTIONAL and
LIST-valued (absent for suffix-less entries; multi-valued for plural forms like
`(specs 0002, 0003)`). `Specs:` lines and the supersession seed degrade
gracefully when no id is present (omit or mark as "unknown"). Update AC1, AC3,
AC10, and the Lifecycle parsing contract to reflect this.

---

### CF-2 — Re-compaction / multi-run merge is undefined

**Touches:** AC4, AC8.

AC4/AC8 cover archive idempotence on a second run but not how the
`## Compacted` section in `history.md` is handled. If a second compaction
regenerates that section from scratch, previously summarized decisions can be
silently rewritten — violating "bounded and true." If it only appends new `###`
themes, prior records are preserved but the merge algorithm is unspecified.

**Fix:** Add an AC stating that re-compaction treats the existing
`## Compacted` section as durable input: newly demoted entries are summarized
as new `###` theme groups and merged in, while existing `###` groups are never
regenerated or dropped. Prior `Specs:`, `Archive:`, and `Supersedes:`
provenance within that section is preserved verbatim.

---

### CF-3 — Archive dedup needs a stated deterministic identity key

**Touches:** AC3.

AC3 says "re-running never re-archives an already-archived entry" but does not
state the identity key used to detect that. Since `(spec NNNN)` is unreliable
for suffix-less and plural-suffix entries (CF-1), it cannot serve as a reliable
dedup key.

**Fix:** Define the "already-archived" identity as a full-entry byte-match
(header line + body, exactly as it appeared in `history.md`). This is robust to
all header shapes and is trivially assertable by the deterministic helper.

---

### CF-4 — Nudge byte-threshold can fire when nothing is compactable

**Touches:** AC11, AC6.

The nudge predicate is `> 15 entries OR > 40 KB`. The window is N = 10. Large
entries (0021/0022 are each multi-KB) mean 10 in-window entries can already
exceed 40 KB with nothing below the window, causing AC11 to suggest
`/speccraft:history:compact` while AC4 would report "nothing to compact" — a
false alarm.

**Fix:** Gate the byte-size arm of the nudge on there being at least one entry
below the window (i.e., total entry count > N). The count arm (`> 15 entries`)
already implies something is below the window, so it is unaffected. Update AC6
and AC11 accordingly.

---

### CF-5 — Motivating example is unreachable at current N

**Touches:** The Why section and the summary schema example.

The Why section sells the feature on the 0019→0023 supersession and the summary
schema shows `Supersedes: 0019 → 0023`. At N = 10, both 0019 (entry ~5 from
the top) and 0023 (entry ~1) currently sit inside the verbatim window, so
compaction cannot touch either of them yet. The headline use case is unreachable
until those entries age below the window.

**Fix:** Replace the illustrative `Supersedes:` example with an out-of-window
pair. Add one sentence acknowledging that a superseded entry still inside the
window is intentionally left verbatim until it ages out — this is correct
behavior, not a gap, and calling it out makes the spec more honest.

---

### CF-6 — Body-split brittleness on interior `##` headings

**Touches:** The parsing contract.

The spec defines an entry body as running "up to the next `## ` header."
A `##`-level heading embedded inside an ADR body (e.g. a "## Context" subsection
authored by hand) would truncate that entry's body and mis-count the next
heading as a new ADR entry.

**Fix:** Restrict the entry-boundary split to headers that match the ADR date
pattern (`## YYYY-MM-DD …`) OR the sentinel `## Compacted …` — not any `## `.
State this in the Lifecycle parsing contract so the implementer's regex is
unambiguous.

---

## Non-blocking suggestions

- **`.speccraft/history-archive/` must not enter the context load list.** Pin
  explicitly that this directory is NOT added to the `speccraft-context` skill's
  load list (the skill loads `history.md` by explicit name today, so the
  invariant holds, but a future edit could silently re-bloat context). It also
  carries no `enforce:` markers for speccraft-drift checks.

- **Call out the `memory-keeper` prompt change.** `memory-keeper` is currently
  append-only. Reusing it for summarize/propose/merge is a real responsibility
  expansion. Note explicitly in the spec (or in the plan) what changes in
  `agents/memory-keeper.md` so the "reuse, no new store" decision doesn't hide a
  substantial prompt rewrite that reviewers or future maintainers would want to
  see.

---

## Per-agent verdicts

### codex (gpt-5.5)

```yaml
verdict: approve-with-comments
concerns:
  - "Re-compaction semantics are still under-specified: after a prior compaction,
    the existing `## Compacted …` section must be parsed, preserved, and merged
    with newly demoted entries, or older summarized decisions can disappear from
    the bounded `history.md` view even though they remain in the archive."
  - "The archive de-duplication contract says re-running never re-archives already
    archived entries, but the spec does not state the deterministic identity key
    used to detect already-archived entries."
  - "The live ADR parsing contract treats an entry body as ending at the next
    `## ` header, which is brittle if historical ADR bodies ever contain
    second-level markdown headings."
suggestions:
  - "Add an AC stating that re-compaction preserves and merges the existing
    compacted summary with newly demoted entries, retaining prior `Specs:`,
    `Archive:`, and `Supersedes:` provenance."
  - "Define archive identity explicitly, preferably by canonical spec id from
    `(spec NNNN)` plus exact header/body hash, and specify what happens if the
    archive contains a matching spec id with different content."
  - "Either forbid `## ` headings inside ADR bodies by contract, or make the
    parser split only on headers matching `## YYYY-MM-DD — <title> (spec NNNN)`
    or `## Compacted …`."
guardrail_violations:
  - rule: "None"
    location: "N/A"
convention_violations:
  - rule: "None"
    location: "N/A"
```

### claude-p (claude-opus-4-8)

```yaml
verdict: changes-requested
concerns:
  - "Parsing contract is too rigid for its own corpus. The real
    .speccraft/history.md contains entries with NO `(spec NNNN)` suffix
    ('Slash-command names fully qualified…', 'Plugin packaged via dcstolf-tools
    marketplace', 'speccraft adopted') and a plural form `(specs 0002, 0003)`.
    AC1/AC3/AC10 and the supersession seed all lean on a singular,
    always-present `(spec NNNN)`. As written the helper either mis-counts the
    window (if it requires the suffix) or cannot extract provenance/seed
    supersession (if it matches date-only). The spec also conflates the two: it
    says entries are 'counted by the `## YYYY-MM-DD — <title> (spec NNNN)`
    header' AND 'the first N such `## YYYY-MM-DD` headers' — those are different
    match predicates."
  - "Nudge byte-threshold can fire when compaction is a guaranteed no-op.
    Threshold is `>15 entries OR >40 KB`; window is N=10. Entries are large
    (0021/0022 are each multi-KB), so 10 in-window entries can already exceed
    40 KB with nothing below the window. AC11 then nudges 'run
    /speccraft:history:compact' while AC4 makes that command report 'nothing to
    compact' and write nothing — a false alarm. The byte predicate is decoupled
    from 'is anything actually compactable.'"
  - "The motivating example contradicts the out-of-window rule. 'Why' sells the
    feature on the 0019→0023 supersession, and the summary schema example is
    literally `Supersedes: 0019 → 0023` — but at N=10 BOTH 0019 (entry #5 from
    top) and 0023 (#1) sit inside the verbatim window, so collapse can never
    touch them. The headline use case is unreachable until those entries age
    below the window."
  - "Multi-run summary-merge semantics are undefined. Idempotence (AC4/AC8)
    covers the archive append and the first-run schema, but not how a SECOND
    compaction reconciles newly-demoted entries with the EXISTING `## Compacted`
    section: append new `###` themes, or regenerate the section (re-running the
    model over already-summarized themes = rewriting a prior record, even if
    confirm-gated). 'Bounded and true' over repeated runs hinges on this."
  - "AC3 'never re-archives an already-archived entry' has no defined identity
    key. Re-demotion is largely prevented structurally (demoted entries leave
    the live body), but a deterministic-tier AC still needs a stated dedup key
    (full byte-match? `(spec NNNN)`?) to be assertable — and that key is exactly
    what concern #1 makes unreliable for suffix-less/plural entries."
suggestions:
  - "Explicitly state that `.speccraft/history-archive/` is NOT added to the
    speccraft-context skill's load list (it loads `history.md` by explicit name
    today, so the invariant holds — pin it so a future edit doesn't silently
    re-bloat context) and carries no `enforce:` markers for speccraft-drift."
  - "Specify the memory-keeper changes. It is an append-only agent today; adding
    propose/summarize/rewrite is a real responsibility expansion. Note what
    changes in agents/memory-keeper.md so the 'reuse, no new store' decision
    doesn't hide a large prompt rewrite."
  - "Define helper behavior for suffix-less and multi-spec headers directly:
    treat the `## YYYY-MM-DD` date as the window/counting key, make the
    provenance id optional and list-valued, and have `Specs:`/the supersession
    seed degrade gracefully when absent."
  - "Use an out-of-window pair for the `Supersedes:` example, and add one line
    acknowledging that a superseded entry still inside the window is intentionally
    left verbatim until it ages out."
guardrail_violations: []
convention_violations: []
```

---

## Recommended next action

Fold CF-1 through CF-6 into `spec.md` in rank order, then run
`/speccraft:spec:plan`:

1. **CF-1 (MUST):** Fix the parsing contract — count key is `## YYYY-MM-DD`
   date prefix alone; provenance id is optional and list-valued; `Specs:` and
   supersession seed degrade gracefully when absent. Update AC1, AC3, AC10, and
   the Lifecycle parsing contract.
2. **CF-2:** Add an AC for re-compaction merge: existing `## Compacted` section
   is durable input; newly demoted entries produce new `###` groups merged in;
   prior groups never regenerated or dropped.
3. **CF-3:** Define the archive dedup identity key as full-entry byte-match
   (header + body), replacing any reliance on `(spec NNNN)` as the dedup signal.
4. **CF-4:** Gate the byte-size nudge arm on entry count > N (something actually
   below the window); update AC6 and AC11.
5. **CF-5:** Replace the 0019→0023 `Supersedes:` example with an out-of-window
   pair; add one sentence that an in-window superseder stays verbatim until it
   ages out.
6. **CF-6:** Tighten the body-split rule to split only on `## YYYY-MM-DD …` or
   `## Compacted …` headers, not any `## `.
