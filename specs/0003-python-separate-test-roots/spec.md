---
id: "0003"
title: "Python separate-tree test root resolution"
status: closed
created: 2026-05-15
closed: 2026-05-15
authors: [claude]
packages: ["tools/internal/speccraft", "tools/cmd/speccraft-guard", "tools/cmd/speccraft-state", "commands/speccraft"]
related-specs: ["0002"]
---

# Spec 0003 — Python separate-tree test root resolution

## 1. Summary

Python projects commonly keep tests in a dedicated `tests/` tree rather than
colocating them beside production files. Spec 0002 added the colocated sibling
heuristic (`test_*.py` / `*_test.py` in the same directory). This spec adds
a second lookup tier: when no sibling is found in the same directory,
`SiblingTestFiles` also searches one or more configurable **test roots** by
filename (not by mirrored path), returning any file whose stem matches
`test_<production-stem>.py` or `<production-stem>_test.py` anywhere under
each root.

`/speccraft:init` detects common test root candidates automatically so most
projects need zero configuration.

## 2. Goals

1. **Configurable test roots.** A `[tdd] test_roots` list in `.speccraft/speccraft.toml`
   (new file, parsed by `speccraft-state`) specifies extra directories to search.
   Default: empty (same-dir sibling behaviour from spec 0002 unchanged).

2. **Filename-based search.** For a production file `src/foo/bar.py`, each root is
   searched recursively for `test_bar.py` and `bar_test.py`. No path mirroring —
   just match on the base stem.

3. **Auto-detection in `/speccraft:init`.** The init command walks the repo root for
   candidate test directories (`tests/`, `test/`) and, if found, proposes adding
   them to `speccraft.toml` rather than silently injecting them. The user approves
   or skips; same-dir siblings remain the default with no config needed.

4. **Colocated siblings take precedence.** `SiblingTestFiles` returns same-dir results
   first; configured roots are searched only when same-dir yields nothing.

5. **Go files unaffected.** The new tier applies only to `.py` files.

## 3. Non-goals

- Mirrored path resolution (stripping `src/` prefix and prepending `test_root/`).
  Filename search handles 90% of real projects without requiring `src_root` config.
- TypeScript or other languages (separate specs).
- Auto-detection of any directory named `*test*` — only exact names `tests/` and `test/`
  are proposed; the user can add others manually.

## 4. Glossary

- **test root** — a directory (relative to repo root) that is searched recursively for
  Python test files when same-dir sibling lookup finds nothing.
- **stem match** — file whose base name is `test_<stem>.py` or `<stem>_test.py`, where
  `<stem>` is the base name of the production file without its extension.

## 5. Design

### 5.1 Config format

New file: `.speccraft/speccraft.toml`

```toml
[tdd]
test_roots = ["tests"]   # relative to repo root; can be a list
```

Parsed by `speccraft-state` (new subcommand `get-config` or extend existing config
loader). The guard binary reads this at startup if the file exists; missing file →
no extra roots (same-dir only).

### 5.2 `SiblingTestFiles` change

```
SiblingTestFiles(path, root, testRoots):
  1. same-dir glob (existing behaviour)
  2. if results non-empty → return
  3. if IsProductionPythonFile and testRoots non-empty:
       stem = base without extension
       for each testRoot:
         walk testRoot recursively
         collect files matching test_<stem>.py or <stem>_test.py
       return collected (deduped)
```

Repo root and test roots are passed in from the guard binary; the function itself
remains pure (no filesystem side-effects beyond what it already does).

### 5.3 `/speccraft:init` detection

After creating `.speccraft/`, the init command checks for `tests/` and `test/`
at the repo root. If found, it prints:

```
Detected test directory: tests/
Add to .speccraft/speccraft.toml as a TDD test root? [Y/n]
```

If approved, writes `.speccraft/speccraft.toml` with `test_roots = ["tests"]`.
If declined or not found, `speccraft.toml` is not created (same-dir behaviour).

## 6. Acceptance criteria

1. With `test_roots = ["tests"]` and no same-dir sibling, editing `src/foo/bar.py`
   when `tests/foo/test_bar.py` has been edited this session → **allowed**.
2. With `test_roots = ["tests"]` and no same-dir sibling, editing `src/foo/bar.py`
   when no `test_bar.py` anywhere under `tests/` has been edited → **blocked**.
3. Same-dir sibling found → same-dir result returned; `tests/` not searched.
4. No `speccraft.toml` → behaviour identical to spec 0002 (same-dir only).
5. `SiblingTestFiles` for `.go` files: unchanged (test roots never searched).
6. `/speccraft:init` in a repo with a `tests/` directory at root proposes adding it;
   declining leaves `speccraft.toml` absent.
7. `/speccraft:init` in a repo with no `tests/` or `test/` directory: no prompt,
   no `speccraft.toml` created.
8. `go test ./...` green.
