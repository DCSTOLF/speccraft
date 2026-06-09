---
id: "0010"
status: planned
---

# Tasks — 0010 JavaScript and TypeScript support

- [x] Step 1 — RED: classifier suffix patterns (`TestIsJSTSTestFile_SuffixPatterns`)
- [x] Step 2 — GREEN: implement `IsJSTSTestFile` suffix matching
- [x] Step 3 — RED: `__tests__/` directory convention (`TestIsJSTSTestFile_TestsDirectorySegment`)
- [x] Step 4 — GREEN: add `__tests__/` segment recognition
- [x] Step 5 — RED: node_modules / dist exclusion (`TestIsJSTSTestFile_NodeModulesDistExcluded`)
- [x] Step 6 — GREEN: implement segment-exact exclusion via `isExcludedJSTSPath`
- [x] Step 7 — RED: `IsProductionJSTSFile` accept set (`TestIsProductionJSTSFile_AcceptsProductionExtensions`)
- [x] Step 8 — GREEN: implement `IsProductionJSTSFile`
- [x] Step 9 — RED: `IsTestFile` delegation (`TestIsTestFile_DelegatesToJSTS`)
- [x] Step 10 — GREEN: wire `IsJSTSTestFile` into `IsTestFile`
- [x] Step 11 — RED: declaration-file and basename edge cases (`TestIsJSTSTestFile_NonTestEdgeCases`)
- [x] Step 12 — GREEN/REFACTOR: tighten edge-case logic
- [x] Step 13 — RED: extract shared guard prologue (`TestProdGuardPrologue_*`)
- [x] Step 14 — GREEN: introduce `prodGuardPrologue` and rewire `goPythonProdGuard`
- [x] Step 15 — RED: `jsTsDispatch` sibling-test session lookup (`TestJsTsDispatch_*`)
- [x] Step 16 — GREEN: implement `jsTsDispatch` and dispatcher arm
- [x] Step 17 — RED+GREEN: e2e fixture `tests/e2e/javascript_cycle.sh`
- [x] Step 18 — GREEN: wire fixture into `run_language_fixtures` in `tests/e2e/run.sh`
- [x] Step 19 — REFACTOR (optional): tidy `IsTestFile` and shared lookups
