---
spec: "0031"
---

# Tasks

- [x] T1 — Write-envelope capture RED: `Test_WriteEnvelope_CapturesRedCandidates_{Go_Create,Go_Overwrite,Python_Create,Python_Overwrite,JSTS_Create}` (raw JSON, compile-stable, fail on empty capture) — AC3
- [x] T2 — Two-ordered-call E2E RED: `Test_WriteThenEditProd_NoOverride_Allows_{Go,Python}` (Write capture → Edit prod, fake runner, no override) — AC4
- [x] T3 — GREEN: add `ToolInput.Content`, `ToolName`-driven `applyEdit` switch (Write/Edit/default), thread tool name through `captureRedCandidates` + `computeJustAddedForEdit`; fix `captureCase`; add AC1(a–d)+AC2 unit pins — AC1, AC2, AC3, AC4, AC5(fixtures)
- [x] T4 — AC5 static regression guard: `Test_NoWriteHelperSetsNewStringWithoutContent` — AC5(guard)
- [x] T5 — Pin MultiEdit/NotebookEdit current no-capture behavior + `default`-branch comment; confirm `reserves-specs: ["0032"]` — AC7
- [x] T6 — Version RED: version tests to `1.7.1` (`…Reports171`/`…Const171` ×3) + `specs/0031-…/verify.sh` manifest oracle — AC6
- [x] T7 — Version GREEN: bump three `const version` + two `.claude-plugin/*.json` to `1.7.1`; release via auto-tag → release.yml → verify-release.sh — AC6
- [x] T8 — Final VERIFY: `go test ./...` + `bash specs/0031-…/verify.sh` all green together
