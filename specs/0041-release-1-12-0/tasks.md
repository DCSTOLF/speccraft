---
spec: "0041"
---

# Tasks

- [x] T1 — state: rename+bump version_test (RED) → bump main.go const 1.12.0 (GREEN)
- [x] T2 — guard: rename+bump version_test (RED) → bump main.go const 1.12.0 (GREEN)
- [x] T3 — drift: rename+bump version_test (RED) → bump main.go const 1.12.0 (GREEN)
- [x] T4 — manifests: rename+bump manifest_version_test (RED) → bump plugin.json + marketplace.json (GREEN)
- [x] T5 — verify: go test ./... + go vet green; no stale 1.11.0; rebuild ./bin
