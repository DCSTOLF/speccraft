---
spec: "0019"
status: planned
strategy: tdd
---

# Plan — 0019 Bump version to 1.1.0

## Overview

Mechanical version bump 1.0.0 → 1.1.0 across five live surfaces: three Go
binaries (`const version`) and two JSON manifests. The Go surfaces are gated by
the TDD red→green hook invariant, so each `const` bump must be preceded by an
observed failing sibling test that asserts the NEW value (`"1.1.0"`). The JSON
manifests cannot be asserted by Go tests; they are verified with a `grep -F`
oracle (repo precedent: spec 0011/0016 grep-assertion pattern) folded into the
final verify step.

## Approach

- Each binary's `const version` lives in `package main` alongside its
  `*_test.go` sibling (or, for drift, a new sibling). A test that asserts
  `version == "1.1.0"` fails RED while the const is still `"1.0.0"`, then passes
  GREEN once the const is bumped — satisfying the one-line-const hook rule.
- `speccraft-state` additionally has a testable `run([]string, stdout, stderr)`
  entrypoint, so its test asserts the observable `--version` output (AC2's
  "`--version` prints `1.1.0`"). `guard` and `drift` print via `main()` with no
  test seam, so their tests pin the package-level `const version` directly
  (in-scope, sufficient for AC2's const clause and observable since `main()`
  prints exactly that const).
- JSON manifests (AC1) are verified by grep, not Go tests. This is stated
  explicitly per the spec's "decide and state which" instruction:
  **manifest verification is a verify-step grep oracle, not a unit test.**

## Test-first sequence

### Step 1 — Pin new version for speccraft-state (RED)
- Add `tools/cmd/speccraft-state/version_test.go`:
  - `Test_StateCmd_Version_Reports110` — runs `run([]string{"--version"}, &stdout, &stderr)`, asserts exit code 0 and `strings.TrimSpace(stdout) == "1.1.0"`.
- Tests fail: `const version` is still `"1.0.0"`, so `--version` prints `1.0.0` ≠ `1.1.0`.

### Step 2 — Bump speccraft-state version (GREEN)
- Edit `tools/cmd/speccraft-state/main.go:13`: `const version = "1.1.0"`.
- Step-1 test passes; the failing sibling test observed in Step 1 satisfies the hook's red→green invariant for this one-line const edit.

### Step 3 — Pin new version for speccraft-guard (RED)
- Add `tools/cmd/speccraft-guard/version_test.go`:
  - `Test_GuardCmd_Version_Const110` — asserts the package-level `version == "1.1.0"`.
- Tests fail: `const version` is still `"1.0.0"`. (`guard`'s `main()` prints this exact const via `fmt.Println(version)` at main.go:60-61, so pinning the const pins the observable `--version` output.)

### Step 4 — Bump speccraft-guard version (GREEN)
- Edit `tools/cmd/speccraft-guard/main.go:17`: `const version = "1.1.0"`.
- Step-3 test passes.

### Step 5 — Pin new version for speccraft-drift (RED)
- Add `tools/cmd/speccraft-drift/version_test.go` (NEW file — drift has no existing test):
  - `Test_DriftCmd_Version_Const110` — asserts the package-level `version == "1.1.0"`.
- Tests fail: `const version` is still `"1.0.0"` (main.go:12). The new test compiles against the existing `package main` const.

### Step 6 — Bump speccraft-drift version (GREEN)
- Edit `tools/cmd/speccraft-drift/main.go:12`: `const version = "1.1.0"`.
- Step-5 test passes.

### Step 7 — Bump JSON manifests (no Go test; grep-oracle verified)
- Edit `.claude-plugin/plugin.json` line 3: `"version": "1.1.0"`.
- Edit `.claude-plugin/marketplace.json` line 13: `"version": "1.1.0"`.
- Not gated by the Go TDD hook (JSON files). Verified in Step 8.

### Step 8 — Verify (no refactor needed)
- Run `go build ./...` and `go test ./...` from `tools/` — must succeed (AC3).
- Grep oracle for manifests (AC1):
  - `grep -F '"version": "1.1.0"' .claude-plugin/plugin.json` — must match.
  - `grep -F '"version": "1.1.0"' .claude-plugin/marketplace.json` — must match.
  - `grep -RF '"version": "1.0.0"' .claude-plugin/` — must find nothing (no remaining 1.0.0 version field).
- No REFACTOR step: each const is an independent one-liner; the version tests share no extractable logic worth deduplicating for a mechanical bump.

## Delegation

- All steps → handle in-process (no delegation). Reason: mechanical one-line edits with trivial sibling tests; no specialized agent strength applies and delegation overhead would exceed the work.

## Risk

- Hook blocks the const edit because the RED test asserted the old value → mitigation: each version test asserts the NEW value `"1.1.0"` so it is observed failing before the bump and passing after (per spec Constraints).
- New `version_test.go` in `speccraft-drift` introduces the package's first test and could surface a latent compile issue → mitigation: Step 8 `go build ./...` + `go test ./...` gate catches it; the test only references the existing package-level `version` const.
- A stray `1.0.0` remains somewhere in `.claude-plugin/` → mitigation: Step 8 negative grep (`grep -RF '"version": "1.0.0"'`) fails the verify if any version field is left behind.
- Out-of-scope `1.0.0` strings (e.g. `speccraft-v1-spec.md`, ldflags) accidentally touched → mitigation: edits are scoped to the five named surfaces only; negative grep is restricted to `.claude-plugin/`.
