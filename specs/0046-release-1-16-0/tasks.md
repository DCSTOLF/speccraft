---
spec: "0046"
---

# Tasks

- [x] T1 — RED: rename version tests `…1150` → `…1160`, bump `want` to `1.16.0`, advance the stale-version negative checks to reject `1.15.0`
- [x] T2 — GREEN: bump the 3 Go `const version` from `1.15.0` to `1.16.0`
- [x] T3 — GREEN: bump the 2 JSON manifests (`plugin.json`, `marketplace.json`) from `1.15.0` to `1.16.0`
- [x] T4 — verify: `go test ./...` + `go vet` green; rebuild binaries to `./bin/`; `--version` reports `1.16.0`
