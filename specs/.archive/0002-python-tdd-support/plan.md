---
spec: "0002"
status: closed
strategy: in-place extension
---

# Plan — 0002 Python TDD support

## Step 1 — Extend `files.go` (RED → GREEN)

Files: `tools/internal/speccraft/files.go`, `tools/internal/speccraft/files_test.go`

- Write failing tests for `IsTestFile` (Python cases), `IsProductionPythonFile`, and the Python branch of `SiblingTestFiles`.
- Extend `IsTestFile` to match `test_*.py` and `*_test.py`.
- Add `IsProductionPythonFile`: `strings.HasSuffix(".py") && !IsTestFile(path)`.
- Extend `SiblingTestFiles`: switch on `filepath.Ext(path)` — `.py` globs both `test_*.py` and `*_test.py`; dedup via a `seen` map; default branch unchanged (`*_test.go`).

**Done when:** all `files_test.go` cases pass.

## Step 2 — Wire guard (GREEN)

Files: `tools/cmd/speccraft-guard/main.go`

- Change Rule 4 condition from `IsProductionGoFile(absPath)` to `IsProductionGoFile(absPath) || IsProductionPythonFile(absPath)`.
- Update block message: "edit a test in" → "edit a sibling test in" (language-neutral).

**Done when:** `go test ./...` green end-to-end.
