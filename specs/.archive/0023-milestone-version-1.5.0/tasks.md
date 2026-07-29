---
id: "0023"
spec: "0023"
---

# Tasks

- [x] T1 — (RED) Update the three sibling version tests to assert 1.5.0
      (version_test.go ×3) [AC2]
- [x] T2 — (GREEN) Bump the three `const version` declarations to 1.5.0
      (speccraft-{state,guard,drift}/main.go) [AC2, AC3]
- [x] T3 — Bump both manifests to 1.5.0 (plugin.json, marketplace.json),
      verified by grep oracle (positive 1.5.0 + no stray 1.1.0) [AC1]
- [x] T4 — Full suite green: `go test ./...` [AC3]
