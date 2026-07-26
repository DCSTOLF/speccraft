---
id: "0035"
title: "re-review"
status: closed
created: 2026-07-25
authors: [claude]
packages: ["tools/cmd/speccraft-state", "tools/internal/speccraft", "commands/spec"]
related-specs: ["0018", "0015", "0020"]
---

# Spec 0035 — re-review

<!-- rev2-rev6 history condensed: anchor scheme / exit-code / payload mechanism /
     drift scope (r2); sha256+needle+schema polish (r3); read-before-overwrite
     transaction, (frontmatter)/(preamble) anchors, regression evidence, per-
     binary version tests, override budget (r4); --promote single-read refold,
     ordinal duplicates, missing-review fallback (r5); retry-safety gate,
     structured changed_sections, fingerprint==reviewed_sha256, closed-spec
     --promote refusal (r6).
     rev7: round-6 (codex changes-requested + claude-p approve-with-comments) —
     (1) BASELINE PROVENANCE: envelope now exposes `base_fingerprint` (old
     snapshot sha256, null on first review); the command gates BOTH scoped review
     AND short-circuit on prior review.md.reviewed_sha256 == base_fingerprint, so
     a promoted-but-unreviewed baseline (failed run) forces a full review instead
     of letting the un-reviewed delta escape. (2) Determinism rule switched to
     pure ordinal-key matching — removed the blanket duplicate-count over-report
     that contradicted the byte-identical rule. (3) ordinal document-side pinned
     (removed=old idx, added=new idx, modified=shared idx). (4) "usable"
     review.md = exactly one syntactically valid 64-hex reviewed_sha256. (5) AC3
     exit-code wording de-contradicted. (6) AC11 requires the injected seam (mtime
     dropped — not portable sub-second). (7) AC2 pins reviewed_sha256 is written
     AFTER the reviewer returns.
     rev8: round-7 (codex changes-requested [2 narrow] + claude-p approve) —
     AC2 tightened: reviewed_sha256 written only after the review WORKFLOW
     completes successfully (all quorum-required reviewers verdicted + review.md
     persisted), verdict-independent, nothing written on any failure; "usable"
     pinned to the anchored grammar ^reviewed_sha256: [0-9a-f]{64}$; heading key
     whitespace-trimmed (AC5); unreadable OLD snapshot → non-zero (AC3); AC11
     gains a command-layer bash oracle (rm spec.md between promote and payload).
     rev9: round-8 (codex changes-requested [1 narrow] + claude-p approve) — AC2
     rewritten as a SINGLE ATOMIC COMMIT (construct complete review.md incl the
     reviewed_sha256 line in a temp file, then atomic rename; success == rename
     succeeds; no intermediate fingerprint-free write; any pre-rename failure
     leaves the prior file byte-unchanged); timeout≠returned-verdict pinned; AC7
     oracle (b) reworded to source current-spec bytes from the frozen snapshot. -->



## Why

Field feedback: when `/speccraft:spec:review` is re-run, reviewers re-evaluate
the whole spec every round — re-litigating already-settled sections — so the
round count balloons (the field session took 4 rounds to converge). Hand-building
a "only assess what changed since the last review + check for regressions" brief
and prepending it to round 2 cut that session to 2 rounds.

The value is **re-litigation avoidance**, not merely "not reading the whole
spec": reviewers still receive the full current spec.md as regression context
(AC7), but are instructed to assess only the deltas and to sweep the unchanged,
previously-approved criteria for regressions rather than re-arguing them.

The anchor is a **snapshot taken at review time**, not git history: review runs
while the spec is still `draft` and typically uncommitted (review → revise →
re-review all precede the first commit), so a git-diff anchor would have nothing
to compare against in the common case. A self-contained snapshot is also
deterministic and reuses the spec-0020 robust-noop precedent — a byte-identical
snapshot short-circuits instead of dispatching reviewers.

## What

Add a diff-focused re-review path to `/speccraft:spec:review`:

1. **`speccraft-state review-snapshot write <spec-dir>`** — the primitive that
   copies the current `spec.md` to `<spec-dir>/review-snapshot.md` and prints the
   fingerprint. `speccraft-state` is the sole snapshot writer.

2. **`speccraft-state review-diff <spec-dir> [--promote]`** — reads `spec.md`
   once, compares it against the prior `review-snapshot.md`, and emits a versioned
   JSON envelope (mirrors the `detect-stack` pattern, spec 0034), including the
   OLD snapshot's `base_fingerprint`. With `--promote`, the SAME in-memory byte
   image it just diffed is written as the new snapshot before the process exits.

3. **A `--diff` flag on `/speccraft:spec:review`** that runs the transaction
   below and then, using the envelope + prior review evidence, either
   short-circuits, falls back to a full review with a loud warning, or dispatches
   a scoped re-review sourced from the frozen snapshot.

4. Version bump and the standing merge-time release obligation.

### Ordering (the read-before-overwrite transaction — pins AC11)

One `--diff` run performs a single authoritative read and sources everything
downstream from the frozen snapshot:

1. Call `review-diff <spec-dir> --promote` ONCE. Inside that single process: read
   `spec.md` bytes once → read the OLD `review-snapshot.md` (capturing its
   `base_fingerprint`) → compute the envelope → write those same `spec.md` bytes
   as the NEW `review-snapshot.md`. The old snapshot is read (and fingerprinted)
   before it is overwritten; the new snapshot is the exact byte image diffed.
2. The command builds every reviewer payload (scoped re-review AND the AC8 full-
   review fallback) from the **newly-written `review-snapshot.md`** — never
   re-reading `spec.md`. No TOCTOU window.
3. Gate the UX (AC8/AC9) on the envelope + prior review evidence, then dispatch.

### Provenance gate (pins AC8/AC9)

The command classifies the run from three facts: the envelope's `snapshot` /
`changed` / `base_fingerprint`, and the prior `review.md`'s `reviewed_sha256`
(when usable). A `review.md` is **usable** iff it is present, readable, and
contains exactly one line matching the anchored grammar
`^reviewed_sha256: [0-9a-f]{64}$` (a single space after the colon, no
leading/trailing whitespace, matched per-line — occurrences inside fenced/quoted
prose do not count). Zero, multiple, or malformed such lines → not usable.
Classification:

- `snapshot:false` (first review) → **full review** (AC8).
- Else if `review.md` is not usable, OR its `reviewed_sha256` ≠ the envelope
  `base_fingerprint` → **full review** (AC8). This is the provenance check: unless
  the baseline the diff was computed FROM is exactly the version that was last
  successfully reviewed, the deltas are untrustworthy (e.g. a prior run promoted a
  snapshot then died before writing `review.md`), so re-review everything.
- Else (baseline is the reviewed version):
  - `changed:false` → **short-circuit**, no reviewers (AC9).
  - `changed:true` → **scoped re-review** of `changed_sections` + regression sweep
    (AC7).

### Anchor scheme (pins AC5)

`changed_sections` is a JSON array of **structured** entries — not bare strings —
so it is deterministic and cannot alias. Each entry is
`{"kind": "section"|"frontmatter"|"preamble", "heading": string, "ordinal": int,
"side": "added"|"removed"|"modified"}`, where `heading`/`ordinal` are present only
for `kind:"section"`:

- A `##`-level section body change → `kind:"section"` with the heading text
  (the text after the `## ` prefix, with leading/trailing whitespace trimmed, so
  `## Why` and `## Why ` are the same key). Because `kind` is explicit, a literal
  `## (frontmatter)` heading is `kind:"section"` and never aliases the
  `kind:"frontmatter"` entry.
- A YAML front-matter change → `{"kind":"frontmatter","side":"modified"}`.
- A preamble change (between front matter and the first `##` heading — the `# `
  H1 and the `<!-- rev … -->` block) → `{"kind":"preamble","side":"modified"}`.

**Determinism rule.** `changed_sections` is a pure function of (old bytes, new
bytes). Within each document, sections are keyed by *(heading text, 1-based
ordinal among identical headings)*. Matching is ordinal-aligned: the k-th
occurrence of heading H in the old document matches the k-th occurrence of H in
the new document. Then:

- A matched pair whose bodies **differ** → one `side:"modified"` entry;
  `ordinal` = k (the shared occurrence index).
- An occurrence present only in the old document → `side:"removed"`, `ordinal` =
  its index in the OLD document.
- An occurrence present only in the new document → `side:"added"`, `ordinal` =
  its index in the NEW document.
- A matched pair whose bodies are **byte-identical** → emitted NEVER, even if an
  unrelated edit shifted its line numbers or another heading's counts.

There is no blanket over-report: a duplicate-count change surfaces only as the
specific unmatched occurrences (`added`/`removed`), never as spuriously-`modified`
identical bodies. A **rename** (`## Why` → `## Motivation`) is therefore a removed
`Why` plus an added `Motivation`. Granularity is the section, never per-line or
per-AC-number.

### Layering (pins ownership)

`speccraft-state review-diff` OWNS change detection (`snapshot`/`changed` +
`diff` + `changed_sections` + `fingerprint` + `base_fingerprint`); the
`/speccraft:spec:review` command OWNS the UX response and the provenance gate
above (consulting the prior `review.md`). Detection lives in one layer.

## Acceptance criteria

1. `speccraft-state review-snapshot write <spec-dir>` writes
   `<spec-dir>/review-snapshot.md` equal to the current `spec.md`, overwriting any
   prior snapshot in place (no `*-rN` proliferation), and prints the fingerprint —
   the **sha256 of the raw `spec.md` file bytes**, no CRLF/LF, BOM, or trailing-
   newline normalization. The write is a true no-op when the on-disk snapshot is
   already byte-identical: no rewrite, no mtime touch, same fingerprint (spec-0020
   robust-noop parity). On a `<spec-dir>` with no readable `spec.md` it exits
   non-zero.

2. `review.md` records the reviewed `spec.md` fingerprint — the same sha256 of the
   raw file bytes from AC1 — as exactly one `reviewed_sha256:` line. Writing is a
   **single atomic commit**, not a two-step append: after every quorum-required
   reviewer has returned a verdict (a timeout or absent verdict is NOT a returned
   verdict) and aggregation succeeds, the command constructs the COMPLETE
   `review.md` — already containing its one `reviewed_sha256:` line — in a
   temporary file, then atomically replaces the prior artifact via rename. The
   review workflow is deemed successful only once that rename succeeds; there is
   never an intermediate fingerprint-free write of `review.md`. This is
   verdict-independent — a completed `changes-requested` (or any other) verdict
   still records the baseline, so the next `--diff` scoped-reviews the fix. On ANY
   failure before the atomic rename — dispatch, reviewer, timeout, partial-fan-out,
   aggregation, or the rename itself — the prior `review.md` and its
   `reviewed_sha256` are left byte-unchanged (a promoted-but-not-reviewed baseline
   thus has no matching fingerprint, which the provenance gate relies on).
   Recomputing the sha256 over `review-snapshot.md` reproduces the recorded value.

3. `speccraft-state review-diff <spec-dir> [--promote]` emits the versioned JSON
   envelope `{"schema":1, "snapshot":bool, "changed":bool, "changed_sections":[…],
   "diff":"…", "fingerprint":"…", "base_fingerprint":"…"|null}` on stdout (schema
   pinned to the integer `1`). `fingerprint` is the sha256 of the current captured
   `spec.md` bytes (NOT the old snapshot's) and is the exact value the command
   records as AC2's `reviewed_sha256`; `base_fingerprint` is the sha256 of the OLD
   `review-snapshot.md` (captured before any promote), or `null` when
   `snapshot:false`. **Read-only** `review-diff` (no `--promote`) exits 0 whenever
   `spec.md` resolves — including no-prior-snapshot AND a `closed` spec — and
   non-zero only when `spec.md` cannot be read, OR when `review-snapshot.md`
   exists but is unreadable (a truncated/permission-denied snapshot is genuinely
   unresolvable — distinct from an ABSENT snapshot, which is the resolvable
   `snapshot:false` first-review state). `--promote` adds exactly one
   exception to that exit-0 rule: on a `closed` spec it is refused (exits non-zero,
   writes nothing), honoring closed-spec immutability; otherwise `--promote`, after
   the envelope is computed, writes the diffed bytes as the new snapshot via AC1's
   writer.

4. When `spec.md` is byte-identical to `review-snapshot.md`, `review-diff` reports
   `"snapshot": true`, `"changed": false`, empty `diff`, empty `changed_sections`,
   and `base_fingerprint == fingerprint`. Byte-identical (not semantic) equality
   over the same raw bytes as AC1 is intentional; the command decides the UX.

5. When `spec.md` differs, `review-diff` reports `"changed": true` and
   `changed_sections` contains structured entries per the Anchor scheme's
   Determinism rule (`kind`/`heading`/`ordinal`/`side`; ordinal document-side as
   specified; no blanket over-report). An unchanged (byte-identical) body is NEVER
   emitted, even under an ordinal shift; a changed region ALWAYS produces at least
   one entry; duplicate headings are individually distinguishable via `ordinal`.

6. `review-diff` on a spec directory with **no** prior snapshot exits 0 and
   reports `"snapshot": false`, `"changed": false`, empty diff/sections, and
   `base_fingerprint: null`. It does not exit non-zero for this resolvable
   first-review state. With `--promote` it still establishes the baseline snapshot.

7. A new `templates/prompts/re-review.md` prompt template exists carrying the
   markers `{{DIFF}}` and `{{CHANGED_SECTIONS}}` and an explicit regression-sweep
   instruction over previously-approved criteria. On the scoped-re-review path
   (Provenance gate), the command prepends this populated brief to each reviewer
   payload AND includes, as evidence, the **prior `review.md`** and the **full
   frozen `review-snapshot.md`**. Two oracles: (a) a template grep with BOTH
   polarities — POSITIVE needles `assess ONLY the deltas since last review +
   regressions` and `{{CHANGED_SECTIONS}}`; NEGATIVE needle scoped to
   `templates/prompts/re-review.md` ONLY (not the command doc) forbidding whole-
   spec-review language such as `read the whole spec`, `from scratch`, or `review
   the entire spec`; and (b) a command-level test asserting the CONSTRUCTED payload
   contains the prior `review.md` body and the current spec content (sourced from
   the frozen `review-snapshot.md` per AC11, whose bytes equal `spec.md` by
   construction — the command never re-reads `spec.md`).

8. `/speccraft:spec:review --diff` performs a full review with a loud warning
   exactly on the two full-review branches of the Provenance gate: `snapshot:false`
   (first review), OR the prior `review.md` is not usable / its `reviewed_sha256` ≠
   the envelope `base_fingerprint` (baseline not the last-reviewed version). The
   full-review fallback also sources spec content from the just-promoted
   `review-snapshot.md` (preserving AC11). The "loud warning" wording is UX-owned
   and NOT oracle-pinned.

9. `/speccraft:spec:review --diff` short-circuits — dispatches NO reviewer and
   reports "no changes since last review" — exactly when the Provenance gate's
   short-circuit branch holds: `changed:false` AND a usable prior `review.md` whose
   `reviewed_sha256` equals `base_fingerprint` (which equals `fingerprint` when
   unchanged, AC4). Any `changed:false` run lacking that matching review falls back
   to a full review (AC8), so a failed promoted run is safely retryable. The exact
   short-circuit string is command-owned UX and NOT oracle-pinned.

10. `review-snapshot.md` lives under `specs/`, outside the `.speccraft/` memory-
    file set that `speccraft-drift` scans, so a snapshot byte-copying `enforce:`
    prose from `spec.md` cannot trip drift. A regression test pins drift's scope
    excludes `specs/**` by calling the SAME scan function the drift hook invokes
    (not a bespoke re-implementation), placed in whichever package exports it. The
    snapshot also does not break `preflight_archive_collisions`, and the snapshot +
    `--diff` behavior is documented in `.speccraft/conventions.md`.

11. Within one `--diff` run the Ordering transaction holds: a single
    `review-diff --promote` reads `spec.md` once, reads (and fingerprints) the OLD
    snapshot before overwriting it, and writes the NEW snapshot exactly once from
    the diffed byte image; the command then sources every reviewer payload (scoped
    or fallback) from that frozen `review-snapshot.md` and never re-reads
    `spec.md`. The oracle asserts this via an **injected writer/reader seam** (a
    test double capturing call order) — NOT mtime observation, which is not a
    portable sub-second oracle — proving the old snapshot is read before the new is
    written. For the command layer (markdown/bash, where an FS seam is awkward),
    the companion oracle is a bash test that removes `spec.md` between the
    `review-diff --promote` call and payload construction and asserts payloads are
    still built successfully — proving the command reads the frozen
    `review-snapshot.md`, never `spec.md`.

12. Version bumped 1.9.0 → 1.10.0 across the three `const version` binaries via
    **three** renamed sibling version tests — one per binary (speccraft-state,
    speccraft-guard, speccraft-drift), each its own RED→GREEN — plus both JSON
    manifests via a grep oracle (positive new + negative stale). Guard/drift bumps
    are lockstep no-op-behavior bumps. The merge-time published-verified release
    chain (auto-tag → release.yml → verify-release.sh) is the definition of done.

13. This spec ships with **at most one** recorded `/speccraft:spec:override` — the
    single new-symbol bootstrap of the `review-diff`/`review-snapshot` type (see
    Implementation notes). A second override is a hard failure of this AC, permitted
    only by first amending this spec (mid-implementation-amendment convention) to
    raise the budget with a recorded reason. Absent such an amendment, >1 override
    fails the spec. (spec-0034 measurable-override-budget precedent.)

## Out of scope

- Diffing anything other than `spec.md` (plan.md/tasks.md deltas are not
  re-reviewed; `reviewed_sha256:` covers spec.md only).
- Per-acceptance-criterion or per-line change granularity; the anchor is the `##`
  section / `(frontmatter)` / `(preamble)` (see Anchor scheme).
- A semantic/AST diff; a section-anchored textual diff is sufficient.
- Changing the quorum, verdict vocabulary, or the aux-delegator → cross-reviewer
  fan-out — reported as working, unchanged.
- Git-history-based anchoring (rejected in favor of the snapshot).
- Re-review of already-`closed` specs as a workflow. Distinction: read-only
  `review-diff` on a closed spec returns a resolvable envelope (AC3), but
  `--promote` is refused (AC3) and the `--diff` command flow is not a reopen path.
  At close, `review-snapshot.md` persists as an inert artifact (like `review.md`).

## Open questions

_none_

## Implementation notes (non-normative)

- The new `review-diff`/`review-snapshot` subcommands introduce a wholly-new
  symbol, so the spec-0031 json.Unmarshal envelope-boundary RED trick does NOT
  apply. Expect **one** pre-authorized `/speccraft:spec:override` to bootstrap that
  first new symbol (spec-0018-AC13 new-symbol build-failure limitation, same as
  spec 0034's `DetectStack`). AC13 makes the budget measurable.
- `--promote` is the seam that keeps AC11's single-read transaction implementable
  across the CLI boundary; everything downstream reads the frozen snapshot.
- The `base_fingerprint` provenance gate is what makes promote-before-dispatch
  correct in ALL cases, not just the no-change retry: a scoped review only runs
  when the diff's baseline is provably the last-reviewed version, so an edit
  layered on top of an unreviewed promoted snapshot cannot smuggle its earlier
  delta past review — that run falls back to a full review instead.
- AC2's atomic commit should reuse the existing `speccraft-state` state.json
  temp+rename helper rather than introducing a parallel one, and the temp file
  MUST be created on the same filesystem as `review.md` (same directory is the
  obvious choice) so the rename is a true atomic swap, not a cross-device copy.
  Expose injectable temp-write/rename seams so the fault-injection RED tests
  (rename failure → prior file byte-unchanged; mid-write crash → no
  fingerprint-free artifact ever observed) are deterministic. (Both round-9
  reviewers flagged this as a non-blocking implementation nicety.)
