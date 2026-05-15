---
spec: "0002"
closed: 2026-05-15
---

# Changelog — 0002 Python TDD support

## What shipped

All acceptance criteria met. Three functions extended or added in
`tools/internal/speccraft/files.go`:

- `IsTestFile` — now matches `test_*.py` and `*_test.py` in addition to `*_test.go`.
- `IsProductionPythonFile` — new; delegates to `IsTestFile` for the exclusion check.
- `SiblingTestFiles` — language-aware: `.py` files get a two-pattern glob (`test_*.py`,
  `*_test.py`) with deduplication; all other extensions keep the original `*_test.go` glob.

`tools/cmd/speccraft-guard/main.go` Rule 4 now fires for both
`IsProductionGoFile` and `IsProductionPythonFile`. Error message updated to
language-neutral wording ("sibling test" vs. "test").

Unit tests added in `files_test.go`: `TestIsTestFile` extended with Python cases;
`TestIsProductionPythonFile` added (6 cases).

## What wasn't specced but shipped

None.

## What was specced but deferred

Separate-tree resolution (`tests/` at repo root) was explicitly out of scope.
Tracked in spec 0003.
