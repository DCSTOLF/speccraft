---
spec: "0003"
closed: 2026-05-15
---

# Changelog — 0003 Python separate-tree test root resolution

## What shipped

All acceptance criteria met.

**`tools/internal/speccraft/config.go`** (new):
- `SpeccraftConfig` / `TDDConfig` structs.
- `ReadConfig(root string) SpeccraftConfig` — reads `.speccraft/speccraft.toml`;
  missing file returns zero-value config (no error).
- `parseSpeccraftTOML` / `parseTOMLStringArray` — minimal hand-rolled parser;
  no new dependencies. Supports `[tdd] test_roots = ["a", "b"]`.

**`tools/internal/speccraft/config_test.go`** (new):
- 5 cases: missing file, single root, multiple roots, comments/blanks, wrong section.

**`tools/internal/speccraft/files.go`**:
- `SiblingTestFiles` signature extended: `(path, repoRoot string, testRoots []string)`.
- Tier-2 stem-match walk added: when same-dir returns nothing and path is `.py`,
  each `testRoot` is walked with `filepath.Walk`; files matching `test_<stem>.py`
  or `<stem>_test.py` are collected. Same-dir results take precedence.
- Go files: unaffected (`testRoots` ignored).

**`tools/internal/speccraft/files_test.go`**:
- `touch` helper for temp-dir filesystem setup.
- 6 new `TestSiblingTestFiles_*` cases covering Go unchanged, Python same-dir,
  Python root fallback, same-dir precedence, no roots, missing root dir.

**`tools/cmd/speccraft-guard/main.go`**:
- Loads `cfg := speccraft.ReadConfig(root)` after root discovery.
- Passes `root, cfg.TDD.TestRoots` to `SiblingTestFiles`.

**`commands/speccraft/init.md`**:
- New step 7a: detect `tests/` and `test/` at repo root; prompt user; write
  `.speccraft/speccraft.toml` on confirmation.

**`README.md`**:
- FAQ "Can I use it in a non-Go repo?" updated with Python colocated and
  separate-tree instructions, including `speccraft.toml` example.

## What wasn't specced but shipped

None.

## What was specced but not shipped

None.
