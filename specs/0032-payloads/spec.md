---
id: "0032"
title: "payloads"
status: closed
created: 2026-07-25
authors: [claude]
packages: ["tools/cmd/speccraft-guard"]
related-specs: ["0031"]
---

# Spec 0032 — payloads

> **Revision 2 (2026-07-25)** — cross-model review round 1 (codex
> `changes-requested`, claude-p `approve-with-comments`). Fixes: AC1's broken
> fixture (`"PRE"` could never differ from itself under `a→b`/`c→d`) replaced
> with an exact-oracle fixture whose content contains the targets; edge cases
> pinned (empty `edits[]`, absent/empty `old_string`, empty `new_source`);
> MultiEdit sequential-dependency case added; the build-failed-≠-RED trap made
> an explicit AC constraint (envelope-boundary authoring, runtime-RED symbol);
> AC6 grep oracle pinned to exact phrases as a Go test; the published-release
> obligation restored to the version-bump AC; dispatch round-trip + unknown-tool
> fallback added. See [review.md](review.md).

## Why

Spec 0031 fixed the guard's red-candidate capture for the `Write` tool (it sends
`content`, not `new_string`) by switching `applyEdit` on tool identity. But it
left two write-tools unmodeled: **MultiEdit** (a sequential `edits[]` array of
`{old_string, new_string}` swaps) and **NotebookEdit** (a `new_source` cell
body). Their `applyEdit` `default:` branch returns the pre-edit content
unchanged, so a test file authored through either tool captures **zero**
red-candidates — meaning the just-added sibling test is invisible to
`siblingRedCheck` and the subsequent production edit is wrongly blocked (the
exact class of failure 0031 fixed for Write). 0031 deliberately pinned this gap
with two characterization tests marked "reserved spec 0032"
([main_test.go:1449-1512](../../tools/cmd/speccraft-guard/main_test.go#L1449-L1512))
and the code comment at
[main.go:404-409](../../tools/cmd/speccraft-guard/main.go#L404-L409). This spec
closes that reserved slot so authoring a RED test via MultiEdit or NotebookEdit
works override-free, exactly as it does via Write and Edit.

MultiEdit and NotebookEdit are already listed in `GATED_TOOLS` and the
`hooks/hooks.json` matcher — they are gated/allowed today; only the
content-modeling in `applyEdit` is missing. **No `hooks.json` change is
required.**

## What

Extend `ToolInput` and `applyEdit` in `tools/cmd/speccraft-guard/main.go` to
faithfully derive post-edit content for MultiEdit and NotebookEdit, so their
red-candidates are captured on a par with Write/Edit:

- **MultiEdit** — add a **named** entry type
  `type MultiEditEntry struct { OldString string `json:"old_string"`;
  NewString string `json:"new_string"` }` and a field `Edits []MultiEditEntry`
  (`json:"edits"`) on `ToolInput` (named, not anonymous, so tests and any future
  file can construct/reference it). `applyEdit` applies each entry **in array
  order**, each a **first-occurrence** replacement on the *running* content (the
  single-Edit branch's semantics, iterated — so a later entry sees an earlier
  entry's output). An entry with an **empty `OldString` is skipped** (not
  applied) to avoid Go `strings.Replace`'s prepend-on-empty behavior; an entry
  whose `OldString` is **absent** from the running content is a silent no-op
  (mirrors `strings.Replace`; we model best-effort, we do NOT reproduce the real
  tool's hard error — the guard only needs a plausible post-edit model). Prefer
  extracting `applyMultiEdit(pre string, edits []MultiEditEntry) string` so the
  sequential invariant lives in one greppable place.
- **NotebookEdit** — add a `NewSource string` field (`json:"new_source"`).
  `applyEdit` returns `NewSource` as the whole post-edit content — **including
  the empty string** (an emptied cell → `""`), exactly as the `Write` case
  returns `Content` including `""`. Because `applyEdit` switches on
  `ti.ToolName` (not on field presence), the Go zero-value ambiguity
  "empty `new_source`" vs "field absent" is a non-issue: a `NotebookEdit`
  envelope always routes to this case and `""` is the correct modeled content. A
  plain `string` (not `*string`) is therefore deliberate. We model the modified
  cell's new source directly; we do **not** parse `.ipynb` JSON structure, so
  test IDs in *other* cells are not observed — an accepted, pinned limitation.
- `applyEdit`'s `switch ti.ToolName` gains explicit `MultiEdit` and
  `NotebookEdit` cases; the `default:` branch (any still-unmodeled tool) keeps
  returning pre-edit content unchanged, and the reserved-slot framing is
  re-established for the *next* unknown tool.
- `ToolName` continues to be injected at the dispatch boundary
  (`dispatchByLanguage`) for these envelopes so the switch sees real tool
  identity.
- The two 0031 characterization tests are **inverted and renamed** (→
  `Test_MultiEditEnvelope_CapturesRedCandidate` /
  `Test_NotebookEditEnvelope_CapturesRedCandidate`) so the test-name itself is a
  recurrence signal; their "reserved spec 0032" language is removed.
- Version bump 1.8.0 → 1.9.0 (new guard capability).

**TDD-authoring constraint (load-bearing, from review).** All driving REDs MUST
be authored at the `json.Unmarshal` **envelope boundary** — decode a real
`{"tool_name":"MultiEdit","tool_input":{"edits":[…]}}` byte slice into a
`ToolInput` and assert on `applyEdit`/red-candidate behavior — never via a
direct struct-literal that names `Edits`/`NewSource` before those fields exist.
An unknown JSON key parses to the zero value, so the envelope-boundary test
**compiles against the current code** and fails only on behavior, dodging the
spec 0018 AC13 build-failed-≠-RED trap that cost spec 0034 a bootstrap override.
This spec extends an existing type/function (not a wholly-new symbol) and is
expected to ship **override-free**.

## Acceptance criteria

1. **MultiEdit sequential application (exact oracle).**
   `applyEdit("a c a", ToolInput{ToolName:"MultiEdit", Edits:[{"a"→"b"},{"c"→"d"}]})`
   returns exactly `"b d a"` (first entry replaces the first `a`; second entry
   then replaces `c` on the running content) — an exact-string assertion, not
   an inequality.
2. **MultiEdit sequential dependency.**
   `applyEdit("a", ToolInput{ToolName:"MultiEdit", Edits:[{"a"→"b"},{"b"→"c"}]})`
   returns exactly `"c"` — proving each entry applies to the *running* content
   (independent application would yield `"b"`). This is the criterion that makes
   MultiEdit ≠ "N independently-captured single Edits".
3. **MultiEdit edge cases**, each an exact-string assertion:
   (a) empty `Edits:[]` → returns `preContent` unchanged;
   (b) an entry whose `OldString` is absent from the running content → that
   entry is a silent no-op (content unchanged for it);
   (c) an entry with `OldString:""` → **skipped**, NOT prepended
   (`applyEdit("PRE", Edits:[{""→"X"}])` == `"PRE"`, never `"XPRE"`).
4. **NotebookEdit (exact oracle, empty included).**
   `applyEdit("PRE", ToolInput{ToolName:"NotebookEdit", NewSource:"X"})` == `"X"`
   AND `applyEdit("PRE", ToolInput{ToolName:"NotebookEdit", NewSource:""})` ==
   `""` (an emptied cell, NOT `preContent`, and NOT the ignored
   `Content`/`NewString` fields).
5. **MultiEdit capture (real envelope).** A test file authored via a real
   `{"tool_name":"MultiEdit","tool_input":{"edits":[…]}}` hook envelope that
   adds a new test id captures that id as a red-candidate
   (`GetRedCandidates` non-empty for the file) — the inverted, renamed
   `Test_MultiEditEnvelope_CapturesRedCandidate`.
6. **NotebookEdit capture (real envelope).** A test file authored via a real
   `{"tool_name":"NotebookEdit","tool_input":{"new_source":…}}` hook envelope
   that adds a new test id captures that id — the inverted, renamed
   `Test_NotebookEditEnvelope_CapturesRedCandidate`.
7. **End-to-end override-free.** After authoring a sibling RED test via
   MultiEdit — a new test id whose body asserts against an **already-existing**
   production symbol so the test is a *runtime* RED (not a compile failure) —
   the corresponding production-file edit is ALLOWED without an override, the
   same end-to-end path 0031 established for Write. The driving REDs for this
   spec are authored at the `json.Unmarshal` envelope boundary per the What's
   TDD-authoring constraint.
8. **Dispatch round-trip.** For `tool_name ∈ {MultiEdit, NotebookEdit}`,
   `dispatchByLanguage` injects `ToolName` so `applyEdit`'s switch routes to the
   correct case, not `default:`. Pinned by a test that would fail (fall through
   to the unchanged-content branch) if the dispatch-site injection regressed.
9. **Recurrence guard + preserved fallback (Go test, exact phrases).** A Go test
   scoped to `tools/cmd/speccraft-guard/` asserts NO source or comment contains
   any of the exact phrases `"reserved spec 0032"`, `"reserved for spec 0032"`,
   or `"unmodeled"` (in reference to MultiEdit/NotebookEdit) — pinned strings,
   not a bare `reserved` word match. The match is case-insensitive and
   whitespace-tolerant (collapse internal whitespace runs) so a cosmetic variant
   like `reserved  spec 0032` cannot bypass the guard. Additionally, a
   characterization test for
   an unknown `tool_name` (e.g. `"FutureEdit"`) asserts `applyEdit` returns
   `preContent` unchanged, re-establishing the `default:` fallback for the next
   still-unmodeled tool.
10. **Version bump 1.8.0 → 1.9.0.** `const version` is `1.9.0` in all three
    binaries (`speccraft-state`, `speccraft-guard`, `speccraft-drift`), each with
    a sibling version test asserting `1.9.0`; `plugin.json` and `marketplace.json`
    carry `"version": "1.9.0"` with no lingering `1.8.0` (grep oracle: positive
    new + negative stale). Per the §Version bumps guardrail, the bump is "done"
    only when the merge triggers the published-release chain (auto-tag →
    `release.yml` → `verify-release.sh`) publishing and self-verifying the
    `v1.9.0` tarballs + `checksums.txt` — a merge-time obligation, mirrored from
    specs 0031/0034.

## Out of scope

- Modeling any write-tool beyond MultiEdit and NotebookEdit; the `default:`
  branch stays as the unchanged-content fallback for future tools (AC9
  re-establishes the reserved slot).
- Parsing real `.ipynb` JSON (cell arrays, metadata). NotebookEdit's
  `new_source` is taken as the modeled post-edit content directly; test IDs in
  other notebook cells are not observed (an accepted limitation, pinned).
- Reproducing MultiEdit's real hard-error semantics (the real tool errors on an
  absent or non-unique `old_string`); the guard models a best-effort
  first-occurrence swap and no-ops on an absent target (AC3b).
- MultiEdit `replace_all` semantics: each `edits[]` entry is modeled as a
  first-occurrence swap; global replace is not modeled.
- Changing the `siblingRedCheck` invariant, the override mechanism, or any
  red-candidate storage/ttl semantics — this spec only feeds them correct
  post-edit content for two more tools.

## Open questions

_none_
