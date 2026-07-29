---
spec: "0032"
closed: 2026-07-25
---

# Changelog — 0032 payloads (model MultiEdit + NotebookEdit in applyEdit)

## What shipped vs spec

Spec 0031 discriminated `speccraft-guard`'s red-candidate capture on tool
identity but modeled only `Write` and `Edit`, leaving MultiEdit and NotebookEdit
in a `default:` fallback commented "reserved for spec 0032." This spec closes
that reserved slot so authoring a RED test via either tool captures its test IDs
on a par with Write/Edit — and did so **override-free**.

Shipped changes, all in `tools/cmd/speccraft-guard` plus the version surfaces:

- **New named type `MultiEditEntry{OldString, NewString}`** (`json:"old_string"` /
  `json:"new_string"`) — named, not anonymous, so tests and future callers can
  construct it.
- **Two new `ToolInput` fields:** `Edits []MultiEditEntry` (`json:"edits"`) and
  `NewSource string` (`json:"new_source"`).
- **New helper `applyMultiEdit(pre, edits)`** — folds each entry as a
  first-occurrence `strings.Replace` over the RUNNING content (a later entry sees
  the earlier entry's output). An entry with `OldString == ""` is SKIPPED (avoids
  Go's prepend-on-empty); an entry whose `OldString` is absent is a silent no-op
  (best-effort; does NOT reproduce the real tool's hard error).
- **`applyEdit` gains explicit `case "MultiEdit"` → `applyMultiEdit` and
  `case "NotebookEdit"` → `ti.NewSource`** (empty string included, mirroring
  Write's `Content`). The switch keys on `ti.ToolName`, so the empty-vs-absent
  `new_source` zero-value ambiguity is moot — a plain `string` (not `*string`) is
  deliberate. The `default:` branch stays the unchanged-content fallback, its
  reserved-slot framing re-established generically for the next unknown tool.
  NotebookEdit is modeled as the modified cell's `new_source` only — `.ipynb` JSON
  is NOT parsed, so other cells' test IDs are not observed (accepted, pinned
  limitation).
- **The two 0031 characterization tests were inverted + renamed**
  (`…CapturesNoRedCandidates` → `…CapturesRedCandidate`) so the test NAME is itself
  a recurrence signal. `dispatchByLanguage`'s ToolName injection was already
  present, so AC8 is a regression PIN (dispatch round-trip), not a driver.
- **New `reserved_slot_test.go`:** a case-insensitive/whitespace-tolerant
  recurrence grep over the package's `*.go` (needles built from concatenated
  fragments, self-excluded) asserting no `"reserved spec 0032"` / `"unmodeled"`
  language survives; a `FutureEdit` fallback pin; the two dispatch pins; and
  `Test_ApplyEditDefaultComment_OmitsModeledTools`.
- **Version bump 1.8.0 → 1.9.0** across all three `const version` binaries (each
  via a renamed version-test RED→GREEN) + both manifests (`plugin.json`,
  `marketplace.json`) via the grep oracle (`manifest_version_test.go` renamed
  `_Is180`→`_Is190`).

### AC-by-AC

- AC1–AC4 (applyEdit exact oracles: sequential-distinct, running-content
  dependency, empty/absent/empty-old_string edges, NotebookEdit incl. `""`) —
  `apply_multinotebook_test.go`.
- AC5/AC6 (real-envelope capture) — the inverted `…CapturesRedCandidate` tests.
- AC7 (end-to-end override-free MultiEdit sibling RED → prod edit allowed) —
  `multiedit_e2e_test.go`.
- AC8 (dispatch round-trip) + AC9 (recurrence grep + `FutureEdit` fallback) —
  `reserved_slot_test.go`.
- AC10 (version bump) — source consts + version tests + manifest oracle done; the
  published-release half is the merge-time obligation below.

## Deviations / environmental findings

1. **Shipped OVERRIDE-FREE** (`tasks.md §Bypasses` empty). Every driving RED
   touching the new fields was authored at the `json.Unmarshal` envelope boundary
   (unknown key → zero value → compiles against the old struct, fails on behavior),
   dodging the spec-0018-AC13 build-failed-≠-RED trap. This confirms spec 0031's
   envelope-boundary meta-technique generalizes from the `Content` field to a
   struct-FIELD extension (`Edits`/`NewSource`), not just a single new field.

2. **Stale-cached-guard recurrence (the 0034 lineage).** The hook ran the STALE
   1.1.0 cached guard on PATH. When scrubbing main.go's `default:` comment (a gated
   comment-only prod edit), the sibling RED had been CLEARED by a prior no-new-test
   Edit to `reserved_slot_test.go` (the `strings` import add) — the documented
   "SetRedCandidates replaces per-file; a no-new-test edit clears a standing RED"
   behavior. Remedy: re-registered a GENUINE fresh companion RED
   (`Test_ApplyEditDefaultComment_OmitsModeledTools` — the default-branch comment
   must no longer NAME the now-modeled tools) via the Edit tool, which unblocked
   the scrub with NO override. Codified as a convention (below).

3. **A source-scanning meta-test scoping bug, caught + fixed in-session.** The
   companion test's first `strings.Index(src, "default:")` matched an EARLIER
   `default:` (main.go:93), sweeping the MultiEdit/NotebookEdit case labels into
   the scanned segment → false positive. Fixed by anchoring the scan to the
   `func applyEdit(` body FIRST, then locating `default:` within it. Lesson: a
   source-scanning meta-test must scope to its TARGET function, not the first
   textual match.

## Merge-time release obligation (AC10)

The bump is "done" only when the merge triggers the published-release chain —
`auto-tag` → `release.yml` → `verify-release.sh` — publishing and self-verifying
the `v1.9.0` tarballs + `checksums.txt`. Same merge-time obligation as specs
0031/0034.

## Files touched

- `tools/cmd/speccraft-guard/main.go` — `MultiEditEntry`, `Edits`/`NewSource`
  fields, `applyMultiEdit`, MultiEdit/NotebookEdit cases, scrubbed default comment,
  `const version = "1.9.0"`.
- `tools/cmd/speccraft-guard/apply_multinotebook_test.go` (new) — AC1–AC4.
- `tools/cmd/speccraft-guard/multiedit_e2e_test.go` (new) — AC7.
- `tools/cmd/speccraft-guard/reserved_slot_test.go` (new) — AC8/AC9.
- `tools/cmd/speccraft-guard/main_test.go` — inverted + renamed 0031 tests
  (AC5/AC6).
- `tools/cmd/speccraft-guard/version_test.go` — `_Const190`, assert 1.9.0.
- `tools/cmd/speccraft-state/main.go` + `version_test.go` — `1.9.0` const + test.
- `tools/cmd/speccraft-drift/main.go` + `version_test.go` — `1.9.0` const + test.
- `tools/internal/speccraft/manifest_version_test.go` — `_Is190`, positive
  `1.9.0` / negative `1.8.0`.
- `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` — `1.9.0`.

## ADR proposed for history.md

2026-07-25 — MultiEdit/NotebookEdit payload modeling closes spec 0031's reserved
slot, override-free; version 1.9.0 (spec 0032). (Applied.)

## Conventions proposed

- New (applied): "A no-new-test edit to the sibling holding your standing RED
  silently disarms it — keep the decisive fresh RED as the LAST test-file touch
  before a gated prod edit" (generalizing the stale-cached-guard §), with a note
  to scope a source-scanning meta-test to its target function.
