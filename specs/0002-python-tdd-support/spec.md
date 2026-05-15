---
id: "0002"
title: "Python TDD support"
status: closed
created: 2026-05-15
closed: 2026-05-15
authors: [claude]
packages: ["tools/internal/speccraft", "tools/cmd/speccraft-guard"]
related-specs: ["0001", "0003"]
---

# Spec 0002 — Python TDD support

## 1. Summary

Extend the speccraft TDD enforcement hook to cover Python production files alongside Go. The v1 sibling-test heuristic was Go-only (`*_test.go`). This spec adds the equivalent for Python, using pytest's two dominant naming conventions (`test_*.py` prefix and `*_test.py` suffix), so that editing a `.py` production file without a sibling test in the same directory is blocked by the same `PreToolUse` guard as Go.

## 2. Goals

1. `IsTestFile` recognises `test_*.py` (pytest default) and `*_test.py` (suffix style).
2. `IsProductionPythonFile` correctly classifies any `.py` that is not a test file.
3. `SiblingTestFiles` for a `.py` file globs both `test_*.py` and `*_test.py` in the same directory (deduplicating).
4. `speccraft-guard pre-tool-use` applies the same active-spec + TDD invariant to Python production files.
5. All new code is covered by table-driven unit tests in `files_test.go`.

## 3. Non-goals

- Separate-tree test resolution (e.g. `tests/` at repo root). Tracked in spec 0003.
- TypeScript, Rust, Java, or any other language.
- `conftest.py` special-casing (treated as production code — it is).

## 4. Acceptance criteria

1. `IsTestFile("src/foo/test_bar.py")` → `true`.
2. `IsTestFile("src/foo/bar_test.py")` → `true`.
3. `IsTestFile("src/foo/bar.py")` → `false`.
4. `IsTestFile("src/foo/conftest.py")` → `false`.
5. `IsProductionPythonFile("src/foo/bar.py")` → `true`.
6. `IsProductionPythonFile("src/foo/test_bar.py")` → `false`.
7. `SiblingTestFiles("src/foo/bar.py")` globs `test_*.py` and `*_test.py` in `src/foo/`; `SiblingTestFiles("src/foo/bar.go")` returns `*_test.go` only (unchanged).
8. Editing `bar.py` with an active spec but no sibling test edited in session → blocked with the same error message as Go.
9. `go test ./...` green.
