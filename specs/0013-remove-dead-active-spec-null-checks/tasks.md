---
spec: "0013"
---

# Tasks

- [x] T1 — Add `tools/internal/speccraft/root_test.go` with
  `TestActiveSpecDir_EmptyReturnsEmpty`,
  `TestActiveSpecDir_RealSpecIdReturnsJoinedPath`, and the
  load-bearing `TestActiveSpecDir_LiteralNullReturnsJoinedPath`
  (RED — third case fails against current `main`). Satisfies AC2.
- [x] T2 — Edit `tools/internal/speccraft/root.go`: remove
  `|| activeSpec == "null"` from `ActiveSpecDir` (line 45). Run
  `go test ./internal/speccraft/` from `tools/`; all three T1
  tests pass (GREEN). Satisfies AC1 (site 1).
- [x] T3 — Extend `tools/cmd/speccraft-guard/main_test.go` with
  `Test_ProdGuardPrologue_MissingActiveSpecKeyBlocks`, using
  `os.WriteFile` of the literal
  `{"version":1,"session":{"id":"","edited_test_files":[],"edited_prod_files":[]}}`
  to `<tmp>/.speccraft/state.json` (no `active_spec` key). Test
  passes today as an assertion-pinning refactor (not a classical
  RED). Satisfies AC3.
- [x] T4 — Edit `tools/cmd/speccraft-guard/main.go`: remove
  `|| state.ActiveSpec == "null"` from `prodGuardPrologue`
  (line 353). Run `go test ./cmd/speccraft-guard/` from `tools/`;
  T3 test still passes plus all existing tests stay green.
  Satisfies AC1 (site 2).
- [x] T5 — Verification + binary rebuild: run `go test ./...`
  from `tools/`, run `bats tests/hooks/` from repo root, run the
  AC1 grep oracle
  (`grep -rnE 'ActiveSpec == "null"|activeSpec == "null"' tools/`,
  expect zero matches), rebuild `bin/speccraft-guard` via
  `(cd tools && go build -o ../bin/speccraft-guard ./cmd/speccraft-guard)`,
  and confirm new test names via `go test -list`. Satisfies AC4
  and re-verifies AC1.
