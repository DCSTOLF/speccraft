---
spec: "0005"
---

# Tasks — 0005 Rust language support

Strict TDD: each RED introduces failing tests; the following GREEN makes them pass; REFACTOR steps are observable-behavior-preserving.

## Group A — Config

- [x] T1 (RED) — config_test.go: assert `[tdd.rust] runner` parses (`"cargo"` default, explicit `"cargo"`, explicit `"nextest"`) [AC #1, partial]
- [x] T2 (GREEN) — config.go: add `RustConfig{Runner string}` to `TDDConfig`, parse `[tdd.rust]` section [AC #1, partial]
- [x] T3 (RED) — config_test.go: assert unknown `runner` value returns error citing file, key, value, and allowed enum [AC #1, partial]
- [x] T4 (GREEN) — config.go: add `ReadConfigStrict` validating `Rust.Runner` against allowed enum [AC #1]

## Group B — State extension

- [x] T5 (RED) — state_test.go: assert `Session.RustTestBaseline` and `Session.RustGateFingerprint` round-trip through load/save [AC #5, AC #8, AC #10, AC #12, partial]
- [x] T6 (GREEN) — state.go: add `RustTestBaseline []string` and `RustGateFingerprint string` to `Session` [AC #5, AC #8, AC #10, AC #12, partial]
- [x] T7 (RED) — tools/cmd/speccraft-state/main_test.go (new): assert `get`/`set`/`rust-baseline append` for the two new fields via the binary [AC #8, AC #10, AC #12, partial]
- [x] T8 (GREEN) — speccraft-state main.go + state.go helpers: wire `get`/`set` subcommands and `rust-baseline append` for the new fields [AC #8, AC #10, AC #12, partial]
- [x] T9 (RED+GREEN) — state_single_writer_test.go: grep-based regression test that no non-state-package code writes the Rust state fields [AC #8, AC #12(e)]

## Group C — Runner package

- [x] T10 (RED) — runner/runner_test.go: assert `Outcome` enum + string values + `Runner` interface shape [AC #4, partial]
- [x] T11 (GREEN) — runner/runner.go: declare `Outcome`, `TestRecord`, `Request`, `Result`, `Runner` interface [AC #4, partial]
- [x] T12 (RED) — runner/cargo_parse_test.go: libtest text parser cases (passed/failed/ignored/integration/crate-prefix/multi/empty) [AC #4, partial]
- [x] T13 (GREEN) — runner/cargo_parse.go: implement `parseLibtestText` per spec §What.3 regex [AC #4, partial]
- [x] T14 (RED) — runner/cargo_adapter_test.go: argv shape + classify three outcomes + ignored-not-failure [AC #4, partial]
- [x] T15 (GREEN) — runner/cargo_adapter.go: implement `CargoAdapter.Run` per spec §What.3 [AC #4, partial]
- [x] T16 (RED) — runner/nextest_parse_test.go: libtest-json parser cases [AC #4, partial]
- [x] T17 (GREEN) — runner/nextest_parse.go: implement `parseLibtestJSON` [AC #4, partial]
- [x] T18 (RED) — runner/nextest_adapter_test.go: argv shape + three outcomes + missing-binary error [AC #4, AC #1, partial]
- [x] T19 (GREEN) — runner/nextest_adapter.go: implement `NextestAdapter.Run` [AC #4, AC #1, partial]
- [x] T20 (RED) — runner/runner_test.go: assert `AdapterFor(cfg)` returns the right concrete adapter (cargo default, nextest opt-in) [AC #1, AC #4, partial]
- [x] T21 (GREEN) — runner/runner.go: implement `AdapterFor` factory [AC #1, AC #4, partial]

## Group D — Static recognition (tokenizer + extractor + delta)

- [x] T22 (RED) — rusttok/tokenizer_test.go: line/block comments (nested), `"..."` with escapes, raw strings (`r"..."`, `r#"..."#`, `r##...##`), byte strings, char literals, mixed regions [AC #2, partial]
- [x] T23 (GREEN) — rusttok/tokenizer.go: implement `Tokenize` returning `[]Span` of `Code`/`Comment`/`StringLike` regions [AC #2, partial]
- [x] T24 (RED) — rusttok/extractor_test.go: `fn <name>(` extraction, ignores `fn` in strings/comments/raw-strings, recognizes `async`/`pub`/generic [AC #2, partial]
- [x] T25 (GREEN) — rusttok/extractor.go: implement `ExtractFnNames` consuming tokenizer code spans [AC #2, partial]
- [x] T26 (RED) — rust_inline_test.go: `FindCfgTestModBlocks` cases including multi-attribute, `pub mod`, nested mods, negatives [AC #2, partial]
- [x] T27 (GREEN) — rust_inline.go: implement `FindCfgTestModBlocks` returning body spans via tokenizer-aware brace balancing [AC #2, partial]
- [x] T28 (RED) — rust_canonical_test.go: canonical ID extraction (single, multi, nested, integration, string-literal ignored) [AC #8, partial]
- [x] T29 (GREEN) — rust_canonical.go: implement `CanonicalInlineTestIDs` and `CanonicalIntegrationTestIDs` [AC #8, partial]
- [x] T30 (RED) — rust_delta_test.go: 4 AC #2 fixture cases (a clean inline, b string-literal NOT classified, c multi-attribute, d edit-without-new-test NOT classified) + L2 phantom-ID extraction [AC #2, §L2]
- [x] T31 (GREEN) — rust_delta.go: implement `IsRustTestEdit` via pre/post canonical-ID set-difference; append L2 runner-backstop assertion test [AC #2, §L2]
- [x] T32 (RED) — rust_stem_test.go: stem-mapping cases including `lib.rs` exclusion [AC #3, AC #11, partial]
- [x] T33 (GREEN) — rust_stem.go: implement `RustProdForTest` [AC #3, AC #11, partial]
- [x] T34 (RED) — rust_discover_test.go: crate-walk discovery (inline, integration, nested mod, `lib.rs` walked for inline, `target/` skipped) + set-difference [AC #8]
- [x] T35 (GREEN) — rust_discover.go: implement `DiscoverRustTests` + `JustAddedRustTests` [AC #8]
- [x] T36 (REFACTOR, optional) — consolidate `rust_*.go` helpers if duplication emerges [no AC]

## Group E — Crate fingerprint + pre-edit gate

- [x] T37 (RED) — runner/fingerprint_test.go: deterministic + tracked-roots inclusion + `target/` exclusion + each invalidation case [AC #10, partial]
- [x] T38 (GREEN) — runner/fingerprint.go: implement `ComputeCrateFingerprint` [AC #10, partial]
- [x] T39 (RED) — runner/gate_test.go: cache-hit zero-subprocess + three invalidation cases + `target/` non-invalidation + fingerprint update on success [AC #10, partial]
- [x] T40 (GREEN) — runner/gate.go: implement `RunPreEditGate` consuming the fingerprint and `cargo check --tests` exec [AC #10, partial]

## Group K — Baseline lifecycle (AC #12)

- [x] T41 (RED) — rust_baseline_test.go: `CaptureInitialRustBaseline` writes walked IDs when empty (a, b), skips when non-empty; `PostAcceptUpdateRustBaseline` appends only failing-just-added IDs (c), dedups; `RecaptureRustBaseline` overwrites (d) [AC #12 (a)(b)(c)(d)]
- [x] T42 (GREEN) — rust_baseline.go: implement `CaptureInitialRustBaseline`, `PostAcceptUpdateRustBaseline`, `RecaptureRustBaseline` [AC #12 (a)(b)(c)(d)]
- [x] T43 (RED) — speccraft-state/main_test.go: `rust-baseline recapture` overwrites baseline from walk; empty-crate case clears baseline [AC #12]
- [x] T44 (GREEN) — speccraft-state/main.go: implement `rust-baseline recapture` subcommand calling `RecaptureRustBaseline` [AC #12]

## Group F — Guard wiring

- [x] T45 (RED) — rust_workspace_test.go: detection cases (package only, workspace only, hybrid, missing) [AC #5, partial]
- [x] T46 (GREEN) — rust_workspace.go: implement `IsCargoWorkspace` [AC #5, partial]
- [x] T47 (RED) — speccraft-guard/main_test.go: workspace fixture → non-zero exit + stderr contains `"0006"` and `"workspace support"` [AC #5]
- [x] T48 (GREEN) — speccraft-guard/main.go: dispatch workspace-detected error [AC #5]
- [x] T49 (RED) — speccraft-guard/main_test.go: initial-capture: empty baseline + Rust edit → no runner invocation, baseline populated, stderr log `"rust_test_baseline captured: 3 tests"`, exit 0; second invocation → runner IS called [AC #12 (a)]
- [x] T50 (GREEN) — speccraft-guard/main.go: invoke `CaptureInitialRustBaseline`, short-circuit red-check on capture, log to stderr [AC #12 (a)]
- [x] T51 (RED) — speccraft-guard/main_test.go: red-check three outcomes + ignored-rule + just-added intersection (in-set accept, not-in-set reject) + post-accept appends failing-just-added to baseline [AC #4, AC #8, AC #12 post-accept]
- [x] T52 (GREEN) — speccraft-guard/main.go: wire Rust dispatch through `runner.AdapterFor` + `DiscoverRustTests` + `JustAddedRustTests`; call `PostAcceptUpdateRustBaseline` on accept [AC #4, AC #8, AC #12 post-accept]
- [x] T53 (RED) — speccraft-guard/main_test.go: pre-edit gate cache-hit no-subprocess + cache-miss runs `cargo check --tests` + build-failed rejects [AC #10]
- [x] T54 (GREEN) — speccraft-guard/main.go: call `runner.RunPreEditGate` before initial-capture and red-check [AC #10]

## Group G — Toolchain provisioning

- [x] T55 (RED) — tests/e2e bash assertion: `run.sh` exits non-zero with `"cargo not found on PATH"` when `cargo` absent [AC #9]
- [x] T56 (GREEN) — tests/e2e/run.sh preamble + `.devcontainer/setup.sh` rustup install [AC #9]

## Group H — End-to-end

- [x] T57 (RED) — tests/e2e/rust_inline_cycle.sh + rust_integration_cycle.sh: assert initial-capture path, full red→green cycles (inline + integration), manual `rust-baseline recapture`; opt-in nextest path gated on `SPECCRAFT_E2E_NEXTEST=1` [AC #6, AC #12]
- [x] T58 (GREEN) — implementation from Groups A–F + K makes the e2e scripts pass [AC #6, AC #4 partial, AC #12 partial]

## Group I — Docs

- [x] T59 (RED) — tests/docs/rust_readme_test.sh: grep-based assertions for Rust section, `[tdd.rust]` block, `runner` mention, `rust_test_baseline` + `rust-baseline recapture` lifecycle mention [AC #7, AC #12 docs]
- [x] T60 (GREEN) — README.md: add Rust section (inline vs integration, config, runner, pre-edit gate cache, baseline lifecycle, §L2 limitation); do NOT modify `templates/speccraft/**` [AC #7, AC #12 docs]
- [x] T61 (RED) — tests/docs/conventions_reserves_specs_test.sh: grep for `reserves-specs` + six required bullet keywords [AC #11]
- [x] T62 (GREEN) — .speccraft/conventions.md: add `### Optional: reserves-specs` subsection covering all six bullets [AC #11]

## Group J — Optional refactor

- [x] T63 (REFACTOR, optional) — extract per-language dispatcher in `speccraft-guard/main.go` if duplication emerges [no AC]
