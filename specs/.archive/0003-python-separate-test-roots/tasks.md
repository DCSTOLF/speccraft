---
spec: "0003"
---

# Tasks — 0003 Python separate-tree test root resolution

## Config + state

- [x] T1 — Define `.speccraft/speccraft.toml` schema (`[tdd] test_roots`)
- [x] T2 — Add `ReadConfig(root string)` to `tools/internal/speccraft` (minimal hand-rolled parser, no new deps)
- [x] T3 — `speccraft-guard` reads config at startup and passes `testRoots` to `SiblingTestFiles`

## Core logic

- [x] T4 — Extend `SiblingTestFiles` signature to accept `repoRoot string, testRoots []string`
- [x] T5 — Implement stem-match walk: for each root, `filepath.Walk`, match `test_<stem>.py` / `<stem>_test.py`
- [x] T6 — Same-dir precedence: skip root walk if same-dir returned results
- [x] T7 — Unit tests: with/without `testRoots`, stem match, precedence, Go unchanged

## Init detection

- [x] T8 — `commands/speccraft/init.md`: after scaffold, check for `tests/` and `test/` at repo root
- [x] T9 — If found, prompt user to add to `speccraft.toml`; write file on approval

## Polish

- [x] T10 — `go test ./...` green
- [x] T11 — README: update FAQ "Can I use it in a non-Go repo?" with `test_roots` config example
- [x] T12 — Update spec 0002 `related-specs` to include "0003" (already set)
