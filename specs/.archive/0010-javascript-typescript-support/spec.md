---
id: "0010"
title: "JavaScript and TypeScript support"
status: closed
created: 2026-06-08
authors: [claude]
packages: ["tools/internal/speccraft", "tools/cmd/speccraft-guard", "tests/e2e"]
related-specs: ["0002-python-tdd-support", "0005-rust-language-support"]
---

# Spec 0010 — JavaScript and TypeScript support

## Why

JavaScript and TypeScript form the largest language ecosystem in active use, and they are a natural gap in speccraft's current language coverage (Go, Python, Rust). Adding first-class JS/TS recognition to the guard expands reach and removes a foreseeable adoption blocker for the largest pool of potential users. No specific user demand has been recorded; this is proactive coverage rather than reactive bug-fix work.

## What

Extend speccraft's TDD guard to recognize JavaScript and TypeScript test files so that the red→green invariant is enforced for JS/TS projects identically to the existing Go and Python patterns: pure file-classification + session-state lookup, no test-runner subprocess.

Scope:
- New classifier functions in `tools/internal/speccraft/files.go`:
  - `IsJSTSTestFile(path string) bool` — returns true for any path matching the test-file patterns below, after applying exclusion rules.
  - `IsProductionJSTSFile(path string) bool` — returns true for JS/TS source files that are not test files and not under excluded directories.
- **Exclusion rule (applied before all JS/TS classification, using `filepath.Clean` semantics):** any path whose slash-separated components include `node_modules` or `dist` as an exact segment returns false from both `IsJSTSTestFile` and `IsProductionJSTSFile`. For example, `src/dist/foo.ts` is excluded; `src/distribution/foo.ts` is not.
- Test-file patterns recognized by `IsJSTSTestFile` (after exclusion):
  - Suffix patterns: `*.test.js`, `*.test.ts`, `*.test.jsx`, `*.test.tsx`, `*.test.mjs`, `*.test.cjs`, `*.test.mts`, `*.test.cts`, and the corresponding `*.spec.*` variants for each extension.
  - `__tests__/` directory convention: any `.js`, `.ts`, `.jsx`, `.tsx`, `.mjs`, `.cjs`, `.mts`, `.cts` file whose path contains a `__tests__/` path segment is classified as a test file.
- Production-file extensions recognized by `IsProductionJSTSFile` (after exclusion and after `IsJSTSTestFile` — file must be neither a test file nor a declaration file): `.js`, `.ts`, `.jsx`, `.tsx`, `.mjs`, `.cjs`, `.mts`, `.cts`. Files whose names end in `.d.ts`, `.d.mts`, or `.d.cts` (TypeScript declaration files in any module format) are not classified as production by `IsProductionJSTSFile`, nor are they classified as test files by `IsJSTSTestFile`.
- **Sibling-test resolver:** `jsTsDispatch` evaluates a production file write by consulting session state (the set of test files registered as written in the current cycle via `session.EditedTestFiles`). For a production file `<dir>/<stem>.<ext>`, at least one of the following candidate paths must appear in `session.EditedTestFiles`:
  1. Same-directory suffix match: `<dir>/<stem>.test.<any-ext>` or `<dir>/<stem>.spec.<any-ext>` for any `<any-ext>` in `{js,ts,jsx,tsx,mjs,cjs,mts,cts}`.
  2. Immediate sibling `__tests__/` directory (one level up from the production file only): `<dir>/__tests__/<stem>.test.<any-ext>`, `<dir>/__tests__/<stem>.spec.<any-ext>`, or `<dir>/__tests__/<stem>.<any-ext>`.
  The check is against session state only — a test file that exists on disk but was not registered in the current cycle does not satisfy the invariant. Both the generated candidate paths and the paths stored in `session.EditedTestFiles` are compared in `filepath.Clean` form.
- **Gate symmetry:** `jsTsDispatch` applies the same prerequisite gates as `goPythonProdGuard` (active spec set, status `in-progress`, `ConsumeOverride`) before the sibling-test check. These gates must be extracted into a shared prologue helper before `jsTsDispatch` is added — not copy-pasted — so the symmetry is enforced by code, not by reviewer vigilance.
- **`IsTestFile` integration:** `IsJSTSTestFile` is wired into the existing `IsTestFile` top-level function in `files.go` so that session-state test registration (which calls `IsTestFile`) recognizes JS/TS patterns automatically.
- A new dispatch arm `jsTsDispatch` added to `dispatchByLanguage` in `tools/cmd/speccraft-guard/main.go`.
- A hermetic e2e fixture `tests/e2e/javascript_cycle.sh` following the established `<lang>_cycle.sh` pattern (mktemp workdir, hook-protocol JSON on stdin, exit codes 0/1/2, `reset_state()` between RED and GREEN scenarios). Includes at least one TypeScript-specific assertion (`*.test.ts` path) alongside JavaScript assertions. No JS runtime required — the fixture drives `speccraft-guard` via shell JSON, same as the Python and Rust fixtures. Wired into `run_language_fixtures()` in `tests/e2e/run.sh`.

## Acceptance criteria

1. **`IsJSTSTestFile` recognizes suffix patterns.** Given file paths ending in each of the 16 test-file suffix variants (`.test.{js,ts,jsx,tsx,mjs,cjs,mts,cts}` and `.spec.*` equivalents), `IsJSTSTestFile` returns true. Verifiable via table-driven unit test in `tools/internal/speccraft/`.
2. **`IsJSTSTestFile` recognizes the `__tests__/` directory convention.** Given paths `src/__tests__/foo.test.ts`, `__tests__/bar.js`, and `lib/__tests__/baz.mts`, `IsJSTSTestFile` returns true. Verifiable via unit test.
3. **`IsProductionJSTSFile` returns true for production source files.** Given paths `src/index.ts`, `src/utils.mjs`, `lib/helpers.cts`, and `app/main.jsx`, `IsProductionJSTSFile` returns true. Verifiable via unit test.
4. **`node_modules/` and `dist/` paths are excluded by both classifiers.** Given paths `node_modules/jest/build/index.js`, `node_modules/pkg/__tests__/foo.test.ts`, and `dist/bundle.js`, both `IsJSTSTestFile` and `IsProductionJSTSFile` return false. `src/distribution/foo.ts` and `src/distutils/foo.ts` are NOT excluded (non-exact segment). Verifiable via unit test.
5. **`IsTestFile` delegates to `IsJSTSTestFile`.** Given a `.test.ts`, `.spec.js`, or `__tests__/foo.ts` path, the top-level `IsTestFile` function returns true. Verifiable via unit test on `IsTestFile`.
6. **Guard blocks a JS/TS production write when no sibling test is registered in session state.** Given a session with no prior test-file edits in `session.EditedTestFiles`, an attempt to write `src/foo.ts` is rejected with non-zero exit and a stderr message in the same format as existing dispatch arms (e.g., "no sibling test registered for src/foo.ts"). A pre-existing `src/foo.test.ts` on disk that was not registered in this cycle does not satisfy the check. Verifiable by invoking `speccraft-guard pre-tool-use` with a JSON hook-envelope and asserting exit code and stderr substring.
7. **Guard allows a JS/TS production write after the sibling test has been registered.** Given a session where `src/foo.test.ts` was previously registered in `session.EditedTestFiles`, writing `src/foo.ts` exits zero. Verifiable by `javascript_cycle.sh` exercising the GREEN scenario.
8. **E2E RED scenario: fixture exits 0 and run.sh reports the step passed.** The `javascript_cycle.sh` RED state (production write attempted before test registration) causes the guard to reject the write with non-zero exit; the fixture asserts this rejection, exits 0 itself, and `run.sh` reports the step passed. Verifiable by running `tests/e2e/run.sh --language-only`.
9. **E2E GREEN scenario passes.** After the test file is registered in session state, the guard allows the write, the fixture exits 0, and `run.sh` reports the step passed. Verifiable by running `tests/e2e/run.sh --language-only` end-to-end.
10. **`--language-only` CI job exercises the fixture.** `tests/e2e/run.sh --language-only` executes `javascript_cycle.sh` as part of `run_language_fixtures()`. Verifiable by running the language-only path and confirming the step counter increments for the JS/TS fixture.
11. **Non-test JS/TS files are not misclassified.** Files `src/index.ts`, `src/utils.mjs`, `src/config.cts`, `src/foo.specs.ts` (`.specs.ts` ≠ `.spec.ts`), `src/types.d.ts`, `src/types.d.mts`, `src/types.d.cts` (declaration files), and `__tests__.ts` (filename containing `__tests__` but not a path segment) all return false from `IsJSTSTestFile`. `src/types.d.ts`, `src/types.d.mts`, `src/types.d.cts` also return false from `IsProductionJSTSFile`. Verifiable via unit test.

## Out of scope

- **Mocha and other test frameworks.** Only Jest and Vitest file conventions (`*.test.*`, `*.spec.*`, `__tests__/`) are supported. Mocha, AVA, Tap, Jasmine, `node:test`, and `Deno.test` are explicitly deferred.
- **Bun and Deno runtimes.** Bun/Deno runtime support is deferred to a follow-up spec; the guard and fixture have no runtime dependency.
- **Framework-specific project templates.** No scaffolding, fixtures, or guard behavior tailored to React, Vue, Svelte, Angular, Next.js, Nuxt, SolidJS, or any other UI/app framework.
- **Monorepo tooling.** No special handling for Nx, Turborepo, Lerna, pnpm workspaces, Yarn workspaces, or Bun workspaces. The guard treats each file path on its own merits.
- **Package manager integration.** No `npm`, `pnpm`, `yarn`, or `bun install` orchestration inside the guard or fixture.
- **Type-checking enforcement.** The guard does not invoke `tsc` or validate TypeScript types; it only classifies files by name.
- **Test-runner subprocess.** The guard and e2e fixture use pure file-classification and session-state — no Jest or Vitest process is spawned.
- **Runner adapter.** JS/TS adds no adapter under `tools/internal/speccraft/runner/`. Runner adapters remain Rust-only (spec 0005). The guard uses the same pure-classification + session-state path as Go and Python.
- **Additional build-output directories** (`coverage/`, `build/`, `.next/`, `out/`). Only `node_modules/` and `dist/` are excluded by this spec. Additional exclusions are deferred.
- **Ancestor `__tests__/` walk.** The sibling resolver only checks the immediate `<dir>/__tests__/` directory (one level above the production file). Upward ancestor traversal is not performed.

## Open questions

_none_
