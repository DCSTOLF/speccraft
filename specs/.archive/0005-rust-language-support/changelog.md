---
spec: "0005"
closed: 2026-05-29
---

# Changelog — 0005 Rust language support

## Shipped

Organized by acceptance criterion. All 12 ACs satisfied; `go test ./...` green across 7 packages; 5 bash e2e/assertion scripts green.

### AC #1 — `[tdd.rust]` config + runner enum validation
- `tools/internal/speccraft/config.go`: new `RustConfig{Runner string}` on `TDDConfig`; `[tdd.rust]` section parser; `ReadConfigStrict` with allowed-value enum (`""`, `"cargo"`, `"nextest"`); `ErrInvalidConfig` sentinel.
- `tools/internal/speccraft/config_test.go`: 8 new tests (defaults, explicit cargo/nextest, unknown values, allowed-values listing, file/key/value in error message).

### AC #2 — Delta-based inline test detection (all four fixture cases)
- `tools/internal/speccraft/rusttok/tokenizer.go`: string/comment/char-literal-aware lexer; nested block comments; raw-string hash counting; byte strings.
- `tools/internal/speccraft/rusttok/extractor.go`: tokenizer-aware `fn <name>(` extraction over code spans only.
- `tools/internal/speccraft/rust_inline.go`: `FindCfgTestModBlocks` with multi-attribute mod recognition + brace-balanced body span.
- `tools/internal/speccraft/rust_delta.go`: `IsRustTestEdit` via pre/post canonical-ID set-difference.
- All four AC #2 fixture cases asserted (clean inline, string-literal NOT classified, multi-attribute, edit-without-new-test NOT classified). §L2 phantom-ID extraction documented as a test (the runner is the backstop).

### AC #3 — Integration test stem-mapping
- `tools/internal/speccraft/rust_stem.go`: `RustProdForTest` implementing three precedence rules; `lib.rs` exclusion.
- `tools/internal/speccraft/rust_stem_test.go`: 5 cases including `lib.rs` exclusion.

### AC #4 — Runner red-check three-outcome contract
- `tools/internal/speccraft/runner/runner.go`: language-neutral `Runner` interface, `Outcome` enum, `TestRecord`, `Request`, `Result`.
- `tools/internal/speccraft/runner/cargo_parse.go` + adapter: libtest text parser; crate-prefix stripping; build-failed vs all-passed vs at-least-one-failed classification.
- `tools/internal/speccraft/runner/nextest_parse.go` + adapter: libtest-json event parser; per-binary normalization; missing-binary error wrapping `tdd.rust.runner`.
- `AdapterFor(cfg)` factory selects adapter by config.
- All three outcomes covered by tests for both adapters using canned fixture output (no real `cargo-nextest` binary required).

### AC #5 — Workspace detection + 0006 error
- `tools/internal/speccraft/rust_workspace.go`: `IsCargoWorkspace` scans `Cargo.toml` for `[workspace]` line at column 0.
- `tools/cmd/speccraft-guard/main.go` Rust dispatch: workspace detected → exits non-zero; stderr contains `"0006"` and `"workspace support"` per AC assertion.

### AC #6 — End-to-end inline + integration cycles
- `tests/e2e/rust_inline_cycle.sh`: scaffolds fresh crate, exercises initial-capture → add failing inline test → make pass → post-baseline behavior → manual recapture.
- `tests/e2e/rust_integration_cycle.sh`: `src/foo.rs` + `tests/foo.rs` full cycle with stem-mapping unlock.
- Nextest path gated behind `SPECCRAFT_E2E_NEXTEST=1`; default skip with notice (not failure).

### AC #7 — README Rust section
- `README.md`: new `## Rust` section (~140 lines) covering config, inline-vs-integration recognition, runner red-check, pre-edit gate cache, baseline lifecycle, workspace handling, out-of-scope list, and §L2 macro limitation.
- `templates/speccraft/**` untouched per Template Purity guardrail.
- `tests/docs/rust_readme_test.sh`: grep-based assertions for all required sections.

### AC #8 — Canonical IDs + baseline single-writer
- `tools/internal/speccraft/rust_canonical.go`: `CanonicalInlineTestIDs` + `CanonicalIntegrationTestIDs` with nested-mod recursion.
- `tools/internal/speccraft/rust_discover.go`: `DiscoverRustTests` crate-walk + `JustAddedRustTests` set-difference.
- `tools/internal/speccraft/state_single_writer_test.go`: grep-based regression test asserting no non-state-package code writes the Rust state fields. Also satisfies AC #12(e).

### AC #9 — Toolchain provisioning + e2e fail-fast
- `tests/e2e/run.sh`: preamble checks `command -v cargo`; exits with `"cargo not found on PATH"` if absent.
- `.devcontainer/setup.sh`: idempotent `rustup` install (skipped if cargo already on PATH).
- `tests/e2e/assertions/test_cargo_preamble.sh`: bash assertion for the fail-fast behavior.

### AC #10 — Crate fingerprint + pre-edit gate cache
- `tools/internal/speccraft/runner/fingerprint.go`: whole-crate SHA-256 over sorted `(relpath, mtime-nanos, size)` tuples; tracked roots `src/`, `tests/`, `examples/`, `benches/` + `Cargo.toml`, `Cargo.lock`, `rust-toolchain.toml`, `.cargo/config.toml`; `target/` excluded.
- `tools/internal/speccraft/runner/gate.go`: `RunPreEditGate(root, ExecFunc)` — cache-hit returns nil with zero subprocesses; cache-miss invokes `cargo check --tests` and persists fingerprint on exit 0.
- Behavioral assertions cover cache-hit (empty shim log), three invalidation cases (touched file, unrelated `.rs`, `Cargo.toml`), and `target/` non-invalidation.

### AC #11 — `lib.rs` exclusion + `reserves-specs` convention
- `tools/internal/speccraft/rust_stem.go`: `lib.rs` exclusion enforced.
- `.speccraft/conventions.md`: new `### Optional: reserves-specs` subsection under "Spec frontmatter" covering all six bullets (purpose, shape, allocation, lifecycle, consistency, lower-bound).
- `tests/docs/conventions_reserves_specs_test.sh`: grep-based assertion for the convention text.

### AC #12 — Baseline lifecycle (initial / post-accept / recapture)
- `tools/internal/speccraft/rust_baseline.go`: `CaptureInitialRustBaseline`, `PostAcceptUpdateRustBaseline`, `RecaptureRustBaseline`.
- `tools/internal/speccraft/state.go`: three new `Session` fields (`RustTestBaseline`, `RustGateFingerprint`, `RustBaselineCaptured` — sentinel added mid-implementation, see Bug fixes below); six accessor helpers (`GetRustBaseline`, `SetRustBaseline`, `AppendRustBaseline`, `GetRustFingerprint`, `SetRustFingerprint`, `IsRustBaselineCaptured`).
- `tools/cmd/speccraft-state/main.go`: `get`/`set rust_test_baseline`, `get`/`set rust_gate_fingerprint`, `rust-baseline append`, `rust-baseline recapture`.
- `tools/cmd/speccraft-guard/main.go`: initial-capture short-circuit logs `"rust_test_baseline captured: N tests"` and skips red-check; post-accept update appends failing-just-added IDs.
- E2E exercises all three lifecycle paths.

### Surface-wide refactors
- `tools/cmd/speccraft-guard/main.go`: extracted `processToolUse(input, deps)` testable entrypoint, `dispatchByLanguage`, `rustDispatch`, `computeJustAddedForEdit`, `applyEdit`, `productionDeps`. Preserved the existing `goPythonProdGuard` codepath.
- `tools/cmd/speccraft-state/main.go`: extracted testable `run()` entrypoint.
- `tools/cmd/speccraft-guard/main_test.go`: 10 new tests + `recordingRunner` and `fingerprintAwareExec` fakes.
- `tools/cmd/speccraft-state/main_test.go` (new): 9 tests.

## Deviations from spec body

1. **`PostAcceptUpdateRustBaseline` signature.** The spec's §What.5 implied `(root, justAdded, records []runner.TestRecord)`. Implementation took `(root, justAdded, failedTestNames []string)` instead to avoid an import cycle — `speccraft` would otherwise import `runner`, which already imports `speccraft`. The caller (`rustDispatch`) does the runner→string conversion. Behavior is equivalent; the layering is cleaner.

2. **`Outcome` enum zero-value collision.** `OutcomeBuildFailed = 0` collides with Go's zero-value default. The test fake `recordingRunner` was patched to also check `Stderr == ""` to distinguish a genuine `OutcomeBuildFailed` from an uninitialized `Result`. A future cleanup might shift the enum so `OutcomeUnknown = 0`; deferred to avoid churning all existing runner-package tests.

3. **Pre-edit gate signature.** The spec hinted at `RunPreEditGate(root, cfg, exec)`. Implementation took only `(root, ExecFunc)` because the gate doesn't read config — `cargo check --tests` is fixed regardless of `runner` choice. Simpler and avoids spurious config coupling.

## Bug fixes during implementation

1. **Empty-crate initial-capture re-fired indefinitely.** First-run capture on a crate with zero pre-existing tests would write an empty baseline, then on the next invocation the empty baseline would be re-read as "unset" and the capture short-circuit would fire again forever. Fixed by adding a separate boolean sentinel `RustBaselineCaptured` to the session, set on first capture independently of the baseline list contents.

2. **`recordingRunner` `Outcome == 0` collision.** The runner test fake treated any zero-value `Outcome` as `OutcomeBuildFailed` (its underlying integer value), causing spurious failures in tests that constructed an empty `Result`. Fixed in the fake by also checking `Stderr == ""` before treating a zero outcome as "build failed".

3. **Production wiring gap in `preToolUse`.** During the testability refactor of `tools/cmd/speccraft-guard/main.go`, `preToolUse()` originally constructed `deps{}` without `exec` or `runnerFor`, silently skipping both the pre-edit gate and the runner in production while tests passed (they injected their own deps). Fixed by introducing `productionDeps()` that wires the real `exec.Command` and `runner.AdapterFor`.

## Deferred / out of scope

- **Cargo workspaces.** Spec 0006 reserved; guard exits with actionable error.
- **Nextest CI provisioning.** Kept opt-in via `SPECCRAFT_E2E_NEXTEST=1`; default skip with notice. Avoids forcing CI to install `cargo-nextest`.
- **`Outcome` enum shift to `OutcomeUnknown = 0`.** Deferred to a follow-up cleanup; would touch every test in `tools/internal/speccraft/runner/`.
- **Retroactive runner-primitive adoption by Go/Python.** Explicitly out of scope per spec §Out of scope.
- **Doctests, proc-macro crates, benchmarks, non-Cargo build systems.** Out of scope per spec.
- **§L1 cross-file unlock for inline-tests-only files.** Documented limitation; follow-up spec if real-world usage demands it.
- **§L2 macro phantom-ID elimination.** Requires `syn`/`tree-sitter-rust`; runner is the backstop in the meantime.

## Test coverage summary

| AC | Coverage location | Tests |
| --- | --- | --- |
| 1 | `tools/internal/speccraft/config_test.go` | 8 |
| 2 | `tools/internal/speccraft/{rusttok/,rust_inline_test.go,rust_delta_test.go}` | 30+ |
| 3 | `tools/internal/speccraft/rust_stem_test.go` | 5 |
| 4 | `tools/internal/speccraft/runner/*_test.go` (4 files) | 25+ |
| 5 | `tools/internal/speccraft/rust_workspace_test.go` + `speccraft-guard/main_test.go` | 5 |
| 6 | `tests/e2e/rust_inline_cycle.sh` + `rust_integration_cycle.sh` | 2 e2e scripts |
| 7 | `tests/docs/rust_readme_test.sh` | 1 bash script |
| 8 | `tools/internal/speccraft/{rust_canonical_test.go, rust_discover_test.go, state_single_writer_test.go}` | 15+ |
| 9 | `tests/e2e/assertions/test_cargo_preamble.sh` | 1 bash script |
| 10 | `tools/internal/speccraft/runner/{fingerprint_test.go, gate_test.go}` + guard tests | 14+ |
| 11 | `tests/docs/conventions_reserves_specs_test.sh` + `rust_stem_test.go` | 2 |
| 12 | `tools/internal/speccraft/rust_baseline_test.go` + guard + state-cmd tests + e2e | 12+ |

All 12 ACs covered.

## Notes for spec 0006 (Cargo workspace follow-up)

Things that should be inherited or revisited:

- **Workspace error message format.** The current guard emits the literal strings `"0006"` and `"workspace support"`. When 0006 ships, replace the hard error with workspace-aware dispatch; the existing assertion (AC #5) can be updated rather than removed, since the strings are still informative to users on older versions.
- **`dispatchByLanguage` extensibility pattern.** Spec 0005 introduced the pattern in `tools/cmd/speccraft-guard/main.go`. Workspace support should fit inside the existing `rustDispatch` rather than spawning a parallel codepath. Per-workspace-member iteration is the natural extension point.
- **Runner-invocation primitive.** The `tools/internal/speccraft/runner/` interface (`Request{WorkDir, FullyQualifiedTestName}`) already accepts a workdir; workspace adapters can iterate members by re-dispatching with a per-member `WorkDir`. No interface change anticipated.
- **Crate fingerprint.** The current fingerprint is rooted at a single `Cargo.toml`. Workspaces will need either a per-member fingerprint set (most likely) or a workspace-wide aggregate. The `state.json` field `rust_gate_fingerprint` is a single string today; a follow-up may need to make it a map or relocate it under a per-member key.
- **Baseline.** Same shape question: `rust_test_baseline` is a flat list today. Per-member baselines may need a nested structure, or the current flat list may suffice if canonical IDs already disambiguate via crate-name prefix (note: the current canonical ID form strips the crate prefix; this assumption may need to flip for workspaces).
- **`reserves-specs` lifecycle.** Per the convention added in AC #11, when 0006's `spec.md` is filed, this spec's `reserves-specs: ["0006"]` frontmatter entry should be removed (during 0006's first commit or during 0005's close, whichever is sooner).
