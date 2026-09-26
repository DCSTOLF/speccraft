---
spec: "0051"
contract: done-means-v1
---

# Tasks

- [x] **T1** — RED: rename the four version oracles to encode `1170`, set expectations to `1.17.0`, advance the stale-version negative checks to reject `1.16.0` (AC1, AC2)
  done: $ [ "$(grep -l '1170' tools/cmd/speccraft-state/version_test.go tools/cmd/speccraft-guard/version_test.go tools/cmd/speccraft-drift/version_test.go tools/internal/speccraft/manifest_version_test.go | wc -l | tr -d ' ')" = 4 ] && [ -z "$(grep -n 'version != "1\.16\.0"\|got != "1\.16\.0"' tools/cmd/speccraft-state/version_test.go tools/cmd/speccraft-guard/version_test.go tools/cmd/speccraft-drift/version_test.go)" ] && grep -q 'NotStale1160' tools/cmd/speccraft-state/version_test.go && grep -q 'const stale = "1.16.0"' tools/internal/speccraft/manifest_version_test.go
- [x] **T2** — GREEN: bump the three Go `const version` to `1.17.0` (AC1)
  done: $ [ "$(grep -c 'const version = "1.17.0"' tools/cmd/speccraft-state/main.go tools/cmd/speccraft-guard/main.go tools/cmd/speccraft-drift/main.go | grep -c ':1')" = 3 ] && cd tools && go test ./cmd/... -run 'Version' -count=1
- [x] **T3** — GREEN: bump the two JSON manifests to `1.17.0` (AC2)
  done: $ grep -q '"version": "1.17.0"' .claude-plugin/plugin.json && grep -q '"version": "1.17.0"' .claude-plugin/marketplace.json && cd tools && go test ./internal/speccraft/ -run 'ManifestVersion' -count=1
- [x] **T4** — no live version DECLARATION still reads `1.16.0`, and the stale-version oracles still reference it (AC3)
  done: $ [ -z "$(grep -rn 'const version = "1\.16\.0"' --include='*.go' . | grep -v '^\./specs/')" ] && [ -z "$(grep -rn '"version": "1\.16\.0"' --include='*.json' . | grep -v '^\./specs/')" ] && grep -q '"1.16.0"' tools/cmd/speccraft-state/version_test.go && grep -q 'const stale = "1.16.0"' tools/internal/speccraft/manifest_version_test.go
- [x] **T5** — rebuild `./bin/` from the bumped source and re-stamp `.binary-version` (AC5)
  done: $ ./bin/speccraft-state --version | grep -q '1.17.0' && ./bin/speccraft-guard --version | grep -q '1.17.0' && ./bin/speccraft-drift --version | grep -q '1.17.0' && [ "$(cat .binary-version)" = "1.17.0" ]
- [x] **T6** — full verification before the push (AC4)
  done: $ bats tests/hooks/ && ./bin/speccraft-drift scan-all && cd tools && go vet ./... && go test ./... -count=1
