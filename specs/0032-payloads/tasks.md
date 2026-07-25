---
spec: "0032"
---

# Tasks

## Phase 1 — Model MultiEdit + NotebookEdit payloads
- [x] T1 — RED: `apply_multinotebook_test.go` AC1-4 exact-oracle applyEdit tests (envelope-boundary decode)
- [x] T2 — RED: invert+rename 0031 characterization tests → `CapturesRedCandidate` (AC5, AC6)
- [x] T3 — RED: `multiedit_e2e_test.go` `Test_MultiEditSiblingRed_NoOverride_Allows_Go` (AC7)
- [x] T4 — GREEN: add `MultiEditEntry`, `Edits`/`NewSource` fields, `applyMultiEdit` helper, MultiEdit+NotebookEdit cases

## Phase 3 — Recurrence guard + fallback/dispatch pins
- [x] T5 — RED: `reserved_slot_test.go` — recurrence grep (AC9) + FutureEdit fallback pin (AC9) + dispatch-injection pins (AC8) + default-comment companion RED
- [x] T6 — GREEN: scrub "reserved for spec 0032"/"unmodeled" language from main.go `default:` comment (+ residual in main_test.go)

## Phase 4 — Version bump 1.8.0 → 1.9.0
- [x] T7 — RED: guard `version_test.go` → `_Const190`, assert "1.9.0"
- [x] T8 — GREEN: `speccraft-guard/main.go` `const version = "1.9.0"`
- [x] T9 — RED: state `version_test.go` → `_Is190`, assert "1.9.0"
- [x] T10 — GREEN: `speccraft-state/main.go` `const version = "1.9.0"`
- [x] T11 — RED: drift `version_test.go` → `_Const190`, assert "1.9.0"
- [x] T12 — GREEN: `speccraft-drift/main.go` `const version = "1.9.0"`
- [x] T13 — RED: `manifest_version_test.go` → `_Is190`, positive "1.9.0" / negative "1.8.0"
- [x] T14 — GREEN: bump `plugin.json` + `marketplace.json` to "1.9.0"

## Bypasses

_None — shipped override-free. Every driving RED was authored at the
`json.Unmarshal` envelope boundary (dodging the spec-0018-AC13 build-failed-≠-RED
trap), and each gated production edit was preceded by an observed sibling RED
registered via the Edit tool (the stale-cached-guard tactic)._
