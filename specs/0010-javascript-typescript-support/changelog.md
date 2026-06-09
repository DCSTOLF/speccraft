---
id: "0010"
closed: 2026-06-09
---

# Changelog — 0010 JavaScript and TypeScript support

## What shipped vs spec

Spec 0010 shipped end-to-end with no deviations from the v4 (final-quorum) spec text. JS/TS is now a first-class language in `speccraft-guard`, enforced by pure file-classification + session-state lookup — no Node, npm, Jest, or Vitest is invoked.

Concretely:
- `tools/internal/speccraft/files.go`: package-level `jsTSExts` slice, `isExcludedJSTSPath` (segment-exact match on `node_modules` / `dist`), `isDeclarationFile` (`.d.ts` / `.d.mts` / `.d.cts`), `IsJSTSTestFile` (16 suffix variants across `.test`/`.spec` × 8 extensions, plus `__tests__/` immediate-directory convention, with exclusion applied), and `IsProductionJSTSFile` (production extensions, non-test, non-declaration, non-excluded).
- `IsTestFile` extended to delegate into `IsJSTSTestFile` so all existing call sites pick up JS/TS recognition transparently.
- `tools/cmd/speccraft-guard/main.go`: introduced `prologueDecision` tri-state plus `prologueAllow` / `prologueBlock` / `prologueContinue` constants, extracted `prodGuardPrologue` from `goPythonProdGuard`, then added `jsTsDispatch` reusing the same prologue. The sibling-test resolver enumerates ~40 candidate paths per write and consults session state only.
- `dispatchByLanguage` gained a JS/TS case routing on the classifier output of `IsProductionJSTSFile` / `IsJSTSTestFile`.
- E2E coverage: `tests/e2e/javascript_cycle.sh` (scenarios A: RED no-sibling block, B: GREEN suffix sibling, C: GREEN `__tests__/` sibling, D: test file always allowed) wired into `tests/e2e/run.sh` as step `[10/10]` and exercised by the `--language-only` CI job.

## Review history

Four rounds of spec review were needed before quorum:
- v1 / v2 / v3 rejected by reviewing agents for requiring real Jest invocation (would have pulled Node into the guard), demanding runtime resolution of test files on disk (would have broken the session-state-only invariant), and proposing extension asymmetry between test and production classifiers.
- v4 dropped runtime invocation, aligned test/production classifiers on the same `jsTSExts` set, and scoped `__tests__/` to the immediate parent directory only. Both agents approved v4.

Out-of-scope items confirmed at quorum: Mocha and other non-Jest/Vitest frameworks, Bun and Deno runtimes, framework templates (React, Vue, etc.), monorepo tooling, runner-adapter integration under `runner/`, ancestor `__tests__/` walks, and additional build-output exclusions beyond `node_modules` and `dist`.

## Step 19 skipped

The optional REFACTOR step was a no-op: `jsTSExts` was already extracted as a package-level slice during Step 2, and the prologue extraction (Steps 13–14) landed cleanly without regressions in the existing override / Go / Python tests. No further refactoring was warranted.

## Acceptance criteria

All 11 ACs satisfied:
1. Suffix patterns recognized — 16 variants via `IsJSTSTestFile`.
2. `__tests__/` immediate-directory convention recognized.
3. `IsProductionJSTSFile` returns true for production source files (.js/.ts/.jsx/.tsx/.mjs/.cjs/.mts/.cts).
4. `node_modules/` and `dist/` segment-exact exclusion applies to both classifiers.
5. `IsTestFile` delegates to `IsJSTSTestFile`.
6. Guard blocks JS/TS production write when no sibling test is registered in session state (E2E scenario A).
7. Guard allows after a sibling test is registered (E2E scenarios B, C).
8. RED fixture exits 0 and `run.sh` reports PASSED.
9. GREEN scenarios pass once test is registered.
10. `--language-only` CI job exercises the fixture as step `[10/10]`.
11. Non-test JS/TS files (`.specs.ts`, `.d.ts`, a file literally named `__tests__.ts`) are not misclassified.

## Files touched

- `tools/internal/speccraft/files.go` (+86)
- `tools/internal/speccraft/files_test.go` (+169, 5 new test functions)
- `tools/cmd/speccraft-guard/main.go` (+98)
- `tools/cmd/speccraft-guard/main_test.go` (+180, 9 new tests — 4 for `prodGuardPrologue`, 5 for `jsTsDispatch`)
- `tests/e2e/javascript_cycle.sh` (new)
- `tests/e2e/run.sh` (+4, step counter 9→10)

## Deviations

None after final review quorum.
