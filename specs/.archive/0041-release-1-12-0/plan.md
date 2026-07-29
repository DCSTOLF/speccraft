---
spec: "0041"
status: planned
strategy: tdd
---

# Plan — 0041 Release 1.12.0

Version bump 1.11.0 → 1.12.0 across six locations. TDD via the renamed-version-test
technique (prior bumps' pattern): rename each version test (fresh red-candidate) +
advance its expectation → runtime RED against the old const → then the const/manifest
edit is GREEN. No override (each Go const edit rides its renamed failing sibling test).

- T1 — RED: state version_test.go rename Is1110→Is1120 (want 1.12.0) + NotStale1100→NotStale1110; GREEN: bump tools/cmd/speccraft-state/main.go const.
- T2 — RED: guard version_test.go rename Const1110→Const1120 (want 1.12.0); GREEN: bump tools/cmd/speccraft-guard/main.go const.
- T3 — RED: drift version_test.go rename Const1110→Const1120 (want 1.12.0); GREEN: bump tools/cmd/speccraft-drift/main.go const.
- T4 — RED: manifest_version_test.go rename VersionIs1110→VersionIs1120 (want "1.12.0", stale "1.11.0"); GREEN: bump plugin.json + marketplace.json (JSON, ungated).
- T5 — verify: go test ./... + go vet green; no stale 1.11.0; rebuild ./bin.
