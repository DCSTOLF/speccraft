---
spec: "0005"
status: planned
strategy: tdd
---

# Plan — 0005 Rust language support

Strict test-first. Every GREEN step is preceded by a RED step that introduces failing tests for the behavior the GREEN step will satisfy. REFACTOR steps are observable-behavior-preserving cleanups.

The plan is grouped into ten concerns. Dependencies between concerns:

- Group A (config schema) lands before Groups C (runner adapters) and F (guard wiring) — runner-adapter selection reads the parsed `runner` field, and the workspace error path is reached after config parse.
- Group B (state extension: `rust_test_baseline`, `rust_gate_fingerprint`) lands before Groups F and K — guard reads/writes the new fields via `speccraft-state`.
- Group C (runner adapters) lands before Group F — guard wiring calls the runner adapter.
- Group D (static recognition: tokenizer + extractor + delta) lands before Groups F and K — guard's red-check consumes the just-added test set, and baseline lifecycle (Group K) consumes the same canonical-ID walk.
- Group E (fingerprint cache) is independent of A/C/D/F/K and may interleave at any point after Group B (it persists via `rust_gate_fingerprint`).
- Group K (baseline lifecycle, AC #12) lands after Groups B and D, and before or interleaved with Group F (the guard's initial-capture short-circuit and post-accept update fire from inside the guard's Rust dispatch).
- Groups G (toolchain), H (e2e), and I (docs) land last.

## Test-first sequence

### Step 1 — Config: parse `[tdd.rust] runner` (RED)

- Extend `tools/internal/speccraft/config_test.go`:
  - `Test_ReadConfig_RustRunner_DefaultsToCargo` — `[tdd.rust]` absent → parsed `Rust.Runner == "cargo"`.
  - `Test_ReadConfig_RustRunner_ExplicitCargo` — `runner = "cargo"` → parsed `Rust.Runner == "cargo"`.
  - `Test_ReadConfig_RustRunner_ExplicitNextest` — `runner = "nextest"` → parsed `Rust.Runner == "nextest"`.
- Tests fail: the `TDDConfig` struct has no `Rust` sub-struct yet, so the assertion references a field that does not compile.

Covers: AC #1 (parse), partial AC #4 (runner selection plumbing).

### Step 2 — Config: parse `[tdd.rust] runner` (GREEN)

- Edit `tools/internal/speccraft/config.go`:
  - Add `RustConfig` struct with `Runner string` (default `"cargo"` materialized by `ReadConfig`).
  - Add `Rust RustConfig` field to `TDDConfig`.
  - Extend `parseSpeccraftTOML` with an `inRust` section flag that recognizes `[tdd.rust]` and reads `runner = "..."`.
  - After parse, if `cfg.TDD.Rust.Runner == ""`, set it to `"cargo"`.
- All Step 1 tests pass.

### Step 3 — Config: reject unknown `runner` values (RED)

- Extend `tools/internal/speccraft/config_test.go`:
  - `Test_ReadConfig_RustRunner_UnknownValueRejected` — `runner = "auto"` causes `ReadConfig` (or `ReadConfigStrict`) to return a non-nil error whose message contains the literal strings `"speccraft.toml"`, `"runner"`, and `"auto"`.
  - `Test_ReadConfig_RustRunner_AllowedValuesListed` — error from `runner = "foo"` enumerates `"cargo"` and `"nextest"` in its message.
- Tests fail: current `ReadConfig` silently accepts any string and returns no error.

Covers: AC #1 (validation).

### Step 4 — Config: reject unknown `runner` values (GREEN)

- Edit `tools/internal/speccraft/config.go`:
  - Add `ReadConfigStrict(root) (SpeccraftConfig, error)` (keep `ReadConfig` lenient for back-compat with existing callers).
  - Validation rule: `Rust.Runner` must be one of `""`, `"cargo"`, `"nextest"`; otherwise return `fmt.Errorf("speccraft.toml: tdd.rust.runner = %q: allowed values are \"cargo\", \"nextest\": %w", val, ErrInvalidConfig)`.
- All Step 3 tests pass.

### Step 5 — State: add `RustTestBaseline` + `RustGateFingerprint` fields (RED)

- Extend `tools/internal/speccraft/state_test.go`:
  - `Test_Session_RustTestBaseline_RoundTrip` — write a `Session` with `RustTestBaseline = ["foo::tests::a", "tests::bar::b"]`, reload, assert equal slice.
  - `Test_Session_RustGateFingerprint_RoundTrip` — write a `Session` with `RustGateFingerprint = "abc123"`, reload, assert equal.
  - `Test_Session_RustFields_EmptyByDefault` — fresh `LoadState` on missing file → empty baseline, empty fingerprint.
- Tests fail: `Session` does not yet have the two new fields.

Covers: AC #8 storage, AC #10 storage, AC #12 storage.

### Step 6 — State: add `RustTestBaseline` + `RustGateFingerprint` fields (GREEN)

- Edit `tools/internal/speccraft/state.go`:
  - Add `RustTestBaseline []string` (json `rust_test_baseline`) and `RustGateFingerprint string` (json `rust_gate_fingerprint`) to `Session`.
- All Step 5 tests pass.

### Step 7 — `speccraft-state` get/set/append for new Rust fields (RED)

- Create `tools/cmd/speccraft-state/main_test.go` (new file — first test for this binary):
  - `Test_StateCmd_GetRustTestBaseline_EmptyByDefault` — invoke `main` (via a thin testable entrypoint, or via `os/exec` over the built binary) with `get rust_test_baseline` on a fresh fixture → exit 0, stdout is `"[]"` (JSON array form).
  - `Test_StateCmd_SetRustTestBaseline_PersistsList` — `set rust_test_baseline '["a::b","c::d"]'` then `get rust_test_baseline` returns the same JSON.
  - `Test_StateCmd_AppendRustTestBaseline_DedupsAndAppends` — `rust-baseline append '["a::b","c::d"]'` against a baseline of `["a::b"]` writes the union `["a::b","c::d"]` (dedup, sorted order).
  - `Test_StateCmd_GetRustGateFingerprint_EmptyByDefault` — fresh → empty string.
  - `Test_StateCmd_SetRustGateFingerprint_Persists` — set `"deadbeef"`, get returns `"deadbeef"`.
- Tests fail: the `get`/`set`/`rust-baseline` switch in `tools/cmd/speccraft-state/main.go` does not recognize the new field names.

Covers: AC #8 (single-writer), AC #10 (single-writer), AC #12 partial (post-accept append path is wired through `speccraft-state`).

### Step 8 — `speccraft-state` get/set/append for new Rust fields (GREEN)

- Edit `tools/cmd/speccraft-state/main.go`:
  - Add `get rust_test_baseline`, `set rust_test_baseline <json-array>`, `get rust_gate_fingerprint`, `set rust_gate_fingerprint <hex-string>`.
  - Add a `rust-baseline append <json-array>` subcommand that loads the current baseline, set-unions the provided IDs, sorts, and writes back via the state package.
- Edit `tools/internal/speccraft/state.go`:
  - Add helpers `GetRustBaseline(root) ([]string, error)`, `SetRustBaseline(root, []string) error`, `AppendRustBaseline(root, []string) error`, `GetRustFingerprint(root) (string, error)`, `SetRustFingerprint(root, string) error`. All take the file lock.
- All Step 7 tests pass.

### Step 9 — Single-writer guardrail assertion (RED+GREEN)

- Add `tools/internal/speccraft/state_single_writer_test.go`:
  - `Test_RustState_NoExternalWriters_Grep` — scan `tools/cmd/` and `tools/internal/` for assignments to `RustTestBaseline` or `RustGateFingerprint`, and for JSON keys `rust_test_baseline`/`rust_gate_fingerprint` written outside `tools/cmd/speccraft-state/` and `tools/internal/speccraft/state.go`. Allow `_test.go` files. Fail if any other writer is found.
- The test is structurally a RED→GREEN pair only because it is *new*. Implementation work for it is zero; the assertion encodes a regression guard for future commits. It also fulfils the AC #12(e) requirement that all three baseline mutations route through `speccraft-state`, because the only writer the grep allows is the state-cmd source tree plus the state-package internals.

Covers: AC #8 (single-writer assertion), AC #12(e) (extended single-writer assertion).

### Step 10 — Runner interface + outcome enum (RED)

- Create `tools/internal/speccraft/runner/runner_test.go`:
  - `Test_Outcome_StringValues` — `OutcomeBuildFailed`, `OutcomeAllPassed`, `OutcomeAtLeastOneFailed` stringify to `"build_failed"`, `"all_passed"`, `"at_least_one_failed"`.
  - `Test_TestRecord_StatusValues` — record `Status` values constrained to `"passed"`, `"failed"`, `"ignored"` (via a `StatusFromString` parser that rejects others).
  - `Test_Runner_InterfaceShape_Compile` — assignment-style test: a `var _ Runner = (*fakeRunner)(nil)` declaration that compiles only if the interface has `Run(ctx context.Context, req Request) (Result, error)` shape.
- Tests fail: the `runner` package does not exist.

Covers: AC #4 (interface).

### Step 11 — Runner interface + outcome enum (GREEN)

- Create `tools/internal/speccraft/runner/runner.go`:
  - `type Outcome int` with `OutcomeBuildFailed`, `OutcomeAllPassed`, `OutcomeAtLeastOneFailed` and a `String()` method.
  - `type TestRecord struct { TestName, Scope, Status string }`.
  - `type Request struct { WorkDir, FullyQualifiedTestName string }`.
  - `type Result struct { Outcome Outcome; Records []TestRecord; Stderr string }`.
  - `type Runner interface { Run(ctx context.Context, req Request) (Result, error) }`.
- All Step 10 tests pass.

### Step 12 — Cargo adapter: libtest text parser (RED)

- Create `tools/internal/speccraft/runner/cargo_parse_test.go`:
  - `Test_ParseLibtestText_PassingTest` — `test foo::tests::it_works ... ok` → one record `{TestName: "foo::tests::it_works", Status: "passed"}`.
  - `Test_ParseLibtestText_FailingTest` — `test foo::tests::it_fails ... FAILED` → `{Status: "failed"}`.
  - `Test_ParseLibtestText_IgnoredTest` — `test foo::tests::it_skipped ... ignored` → `{Status: "ignored"}`.
  - `Test_ParseLibtestText_IntegrationTestStem` — `test foo::it_works ... ok` (from `tests/foo.rs`) → `{TestName: "foo::it_works", Scope: "tests::foo"}`.
  - `Test_ParseLibtestText_StripsCratePrefix` — `test mycrate::foo::tests::a ... ok` parsed against caller-provided crate-name `"mycrate"` → `TestName == "foo::tests::a"`.
  - `Test_ParseLibtestText_MultipleTests` — mixed pass/fail/ignored block → records in encounter order.
  - `Test_ParseLibtestText_NoRecordsOnEmpty` — empty / no `test X ... Y` lines → empty record slice.
- Tests fail: parser does not exist.

Covers: AC #4 cargo branch (parser correctness).

### Step 13 — Cargo adapter: libtest text parser (GREEN)

- Create `tools/internal/speccraft/runner/cargo_parse.go`:
  - `func parseLibtestText(stdout string, cratePrefixToStrip string) []TestRecord` implementing the regex `^test (?P<name>.+) \.\.\. (?P<status>ok|FAILED|ignored)$` per spec §What.3.
  - Status mapping: `ok` → `"passed"`, `FAILED` → `"failed"`, `ignored` → `"ignored"`.
  - Strip leading `<cratePrefixToStrip>::` if present.
- All Step 12 tests pass.

### Step 14 — Cargo adapter: invocation + outcome classification (RED)

- Create `tools/internal/speccraft/runner/cargo_adapter_test.go`:
  - `Test_CargoAdapter_BuildArgv_TargetsExactTest` — argv `["test", "--no-fail-fast", "--quiet", "--", "--exact", "foo::tests::it_fails"]`.
  - `Test_CargoAdapter_Classify_AllPassed` — stdout with one `ok` record and exit 0 → `OutcomeAllPassed`.
  - `Test_CargoAdapter_Classify_AtLeastOneFailed` — stdout with one `FAILED` and non-zero exit → `OutcomeAtLeastOneFailed`.
  - `Test_CargoAdapter_Classify_BuildFailed` — non-zero exit + stderr containing `"error[E"` or `"could not compile"` and no `test ... FAILED` records → `OutcomeBuildFailed`.
  - `Test_CargoAdapter_IgnoredRecordsAreNotFailures` — stdout with one `ignored` and exit 0 → `OutcomeAllPassed`.
- Tests use a fake `execCommand` injected into the adapter; no real `cargo` invoked.
- Tests fail: the cargo adapter type does not exist.

Covers: AC #4 cargo branch (all three outcomes), AC #4 `ignored` rule.

### Step 15 — Cargo adapter: invocation + outcome classification (GREEN)

- Create `tools/internal/speccraft/runner/cargo_adapter.go`:
  - `type CargoAdapter struct { exec func(name string, args ...string) ([]byte, []byte, int, error); CrateName string }`.
  - `func (c *CargoAdapter) Run(ctx, req) (Result, error)`:
    1. Build argv per spec §What.3 cargo line.
    2. Run, capture stdout/stderr/exitcode.
    3. Parse stdout via `parseLibtestText`.
    4. Classify: any `failed` record → `AtLeastOneFailed`; else exit 0 → `AllPassed`; else non-zero exit + no `failed` records → `BuildFailed`.
- All Step 14 tests pass.

### Step 16 — Nextest adapter: libtest-json event parser (RED)

- Create `tools/internal/speccraft/runner/nextest_parse_test.go`:
  - `Test_ParseLibtestJSON_PassingEvent` — JSONL `{"type":"test","event":"ok","name":"mycrate::foo::tests::it_works"}` → `{TestName:"foo::tests::it_works", Status:"passed"}`.
  - `Test_ParseLibtestJSON_FailingEvent` — `"event":"failed"` → `Status: "failed"`.
  - `Test_ParseLibtestJSON_IgnoredEvent` — `"event":"ignored"` → `Status: "ignored"`.
  - `Test_ParseLibtestJSON_PerBinaryNormalization` — multi-binary stream produces one consolidated record list in encounter order.
  - `Test_ParseLibtestJSON_IgnoresNonTestEvents` — `{"type":"suite",...}` lines do not produce records.
  - `Test_ParseLibtestJSON_BadLinesSkipped` — malformed JSON line does not panic; other lines still parse.
- Tests fail: parser does not exist.

Covers: AC #4 nextest branch (parser).

### Step 17 — Nextest adapter: libtest-json event parser (GREEN)

- Create `tools/internal/speccraft/runner/nextest_parse.go`:
  - `func parseLibtestJSON(stdout string, cratePrefixToStrip string) []TestRecord` reading JSONL events.
  - Event-type mapping: `"ok"` → `"passed"`, `"failed"` → `"failed"`, `"ignored"` → `"ignored"`.
- All Step 16 tests pass.

### Step 18 — Nextest adapter: invocation + outcome classification (RED)

- Create `tools/internal/speccraft/runner/nextest_adapter_test.go`:
  - `Test_NextestAdapter_BuildArgv_TargetsExactTest` — argv `["nextest", "run", "--no-fail-fast", "--message-format", "libtest-json", "-E", "test(=foo::tests::it_fails)"]`.
  - `Test_NextestAdapter_Classify_AllPassed`, `_AtLeastOneFailed`, `_BuildFailed`, `_IgnoredNotFailure` mirroring Step 14.
  - `Test_NextestAdapter_MissingBinary_Error` — injected exec reports `exec: "cargo-nextest": executable file not found` → adapter returns error whose message contains `"cargo-nextest"` and `"tdd.rust.runner"` (per spec §What.1 missing-binary rule).
- Tests fail: nextest adapter does not exist.

Covers: AC #4 nextest branch (all three outcomes), AC #1 missing-binary error.

### Step 19 — Nextest adapter: invocation + outcome classification (GREEN)

- Create `tools/internal/speccraft/runner/nextest_adapter.go`:
  - `type NextestAdapter struct { exec ...; CrateName string }`.
  - `Run` builds argv per spec §What.3 nextest line, runs, parses via `parseLibtestJSON`, classifies via the same priority as cargo.
  - On `ErrNotFound` from exec, return wrapped error citing the config key.
- All Step 18 tests pass.

### Step 20 — Adapter factory: `Runner` selection from config (RED)

- Add to `tools/internal/speccraft/runner/runner_test.go`:
  - `Test_AdapterFor_CargoConfig_ReturnsCargoAdapter` — `AdapterFor(SpeccraftConfig{TDD:{Rust:{Runner:"cargo"}}})` returns a `*CargoAdapter`.
  - `Test_AdapterFor_NextestConfig_ReturnsNextestAdapter` — analogous.
  - `Test_AdapterFor_EmptyConfig_DefaultsToCargo` — empty `Runner` defaults to cargo.
- Tests fail: no factory exists.

Covers: AC #1 (selection), AC #4 (config-driven dispatch).

### Step 21 — Adapter factory: `Runner` selection from config (GREEN)

- Add `AdapterFor(cfg SpeccraftConfig) Runner` to `tools/internal/speccraft/runner/runner.go`.
- All Step 20 tests pass.

### Step 22 — Rust tokenizer: string/comment-aware lexer (RED)

- Create `tools/internal/speccraft/rusttok/tokenizer_test.go`:
  - `Test_Tokenize_BareIdentifiers` — `fn it() {}` emits a code-region span covering the whole input.
  - `Test_Tokenize_SkipsLineComment` — `// fn x()` produces one comment region; the `fn x()` text is inside the skipped region.
  - `Test_Tokenize_SkipsBlockComment` — `/* fn x() */` is wholly skipped.
  - `Test_Tokenize_SkipsNestedBlockComment` — `/* outer /* inner */ outer */` is wholly skipped (Rust nests block comments).
  - `Test_Tokenize_SkipsDoubleQuotedString` — `let s = "fn x()";` skips the string region.
  - `Test_Tokenize_SkipsEscapedQuoteInString` — `"a\"b"` does not terminate at the escaped quote.
  - `Test_Tokenize_SkipsRawString_NoHash` — `r"fn x()"` is skipped.
  - `Test_Tokenize_SkipsRawString_OneHash` — `r#"fn "x"()"#` is skipped (inner `"` does not terminate).
  - `Test_Tokenize_SkipsRawString_MultipleHashes` — `r##"fn "#x()"##` is skipped.
  - `Test_Tokenize_SkipsByteString` — `b"fn x()"` is skipped.
  - `Test_Tokenize_SkipsByteRawString` — `br#"fn x()"#` is skipped.
  - `Test_Tokenize_SkipsCharLiteral` — `'x'` is skipped; `'\n'` is skipped; lifetime token `'a` after a generic-args context is NOT a char (parser must distinguish — for our use, skipping `'a` is harmless).
  - `Test_Tokenize_MixedRegions` — input combining all of the above produces the expected interleaved code/skip spans.
- Tests fail: package does not exist.

Covers: AC #2 (tokenizer foundation, all four fixture cases depend on this).

### Step 23 — Rust tokenizer: string/comment-aware lexer (GREEN)

- Create `tools/internal/speccraft/rusttok/tokenizer.go`:
  - `type Span struct { Start, End int; Kind Kind }` where `Kind` is one of `Code`, `Comment`, `StringLike` (covers `"..."`, raw strings, byte strings, char literals).
  - `func Tokenize(src string) []Span` — state machine over runes/bytes, returning a non-overlapping ordered span list that fully covers `src`.
  - Handles: `//...\n`, `/* ... */` with nesting, `"..."` with `\"` escapes, `r"..."` / `r#"..."#` / `r##...##` with matched-hash terminators, `b"..."`, `br"..."`/`br#"..."#`, `'x'` and `'\n'` char literals.
- All Step 22 tests pass.

### Step 24 — `fn <name>(` extractor over tokenizer output (RED)

- Create `tools/internal/speccraft/rusttok/extractor_test.go`:
  - `Test_ExtractFnNames_SingleFn` — `fn it() {}` → `["it"]`.
  - `Test_ExtractFnNames_MultipleFns` — two `fn` items → both names in source order.
  - `Test_ExtractFnNames_IgnoresFnInString` — `"fn x()"` → `[]`.
  - `Test_ExtractFnNames_IgnoresFnInComment` — `// fn x()` → `[]`.
  - `Test_ExtractFnNames_IgnoresFnInBlockComment` — `/* fn x() */` → `[]`.
  - `Test_ExtractFnNames_IgnoresFnInRawString` — `r#"fn x()"#` → `[]`.
  - `Test_ExtractFnNames_AsyncFnRecognized` — `async fn it() {}` → `["it"]`.
  - `Test_ExtractFnNames_PubFnRecognized` — `pub fn it() {}` → `["it"]`.
  - `Test_ExtractFnNames_GenericFnRecognized` — `fn it<T>(x: T) {}` → `["it"]`.
- Tests fail: extractor does not exist.

Covers: AC #2 (the extractor consumed by the delta computation).

### Step 25 — `fn <name>(` extractor over tokenizer output (GREEN)

- Create `tools/internal/speccraft/rusttok/extractor.go`:
  - `func ExtractFnNames(src string) []string` — runs `Tokenize`, walks code spans, for each `fn <ident>(` occurrence emits `<ident>`.
  - Uses a small regex `\bfn\s+([A-Za-z_][A-Za-z0-9_]*)\s*[(<]` applied within code spans only.
- All Step 24 tests pass.

### Step 26 — Inline `#[cfg(test)] mod` regex (RED)

- Create `tools/internal/speccraft/rust_inline_test.go`:
  - `Test_FindCfgTestModBlocks_BareCfgTest` — `#[cfg(test)] mod tests { ... }` → one block with name `"tests"` and accurate body span.
  - `Test_FindCfgTestModBlocks_CfgAny` — `#[cfg(any(test, foo))] mod t { ... }` → one block named `"t"`.
  - `Test_FindCfgTestModBlocks_MultipleAttributesBetween` — `#[cfg(test)]\n#[allow(dead_code)]\nmod tests { ... }` → one block.
  - `Test_FindCfgTestModBlocks_PubMod` — `#[cfg(test)]\npub mod tests { ... }` → one block.
  - `Test_FindCfgTestModBlocks_NoMatch_PlainModNoCfg` — `mod tests {}` → `[]`.
  - `Test_FindCfgTestModBlocks_NoMatch_CfgTestNoMod` — `#[cfg(test)] fn x() {}` → `[]`.
  - `Test_FindCfgTestModBlocks_NestedMod` — nested `mod inner { ... }` inside the outer test mod is included in the outer block's body span.
- Tests fail: function does not exist.

Covers: AC #2 (regex contract feeding the delta computation).

### Step 27 — Inline `#[cfg(test)] mod` regex (GREEN)

- Create `tools/internal/speccraft/rust_inline.go`:
  - `type CfgTestModBlock struct { ModName string; BodyStart, BodyEnd int }`.
  - `func FindCfgTestModBlocks(content string) []CfgTestModBlock` matching `#[cfg(test)]` or `#[cfg(any(test, ...))]` attribute, optionally followed by zero or more outer-attribute lines and/or `pub`, then `mod <ident> {` at the same leading-whitespace column. Returns body spans (`{...}`) using balanced-brace scan that consults the tokenizer to skip braces inside strings/comments.
- All Step 26 tests pass.

### Step 28 — Canonical-ID extractor: combine block regex + fn extractor (RED)

- Create `tools/internal/speccraft/rust_canonical_test.go`:
  - `Test_CanonicalRustTestIDs_SingleInlineMod` — `src/foo.rs` content with `#[cfg(test)] mod tests { fn it_works() {} }` and stem `"foo"` → `["foo::tests::it_works"]`.
  - `Test_CanonicalRustTestIDs_MultipleFns` — two `fn`s in one mod → two canonical IDs.
  - `Test_CanonicalRustTestIDs_NestedMod` — `mod tests { mod inner { fn x() {} } }` → `"foo::tests::inner::x"`.
  - `Test_CanonicalRustTestIDs_IntegrationStem` — `tests/bar.rs` with `fn alpha() {}` (no inline mod wrapper) and integration stem `"bar"` → `["bar::alpha"]`.
  - `Test_CanonicalRustTestIDs_IgnoresStringLiteralFn` — content with `let s = "fn fake() {}";` inside the test mod → no phantom ID.
- Tests fail: function does not exist.

Covers: AC #8 (canonical-ID form used end-to-end).

### Step 29 — Canonical-ID extractor: combine block regex + fn extractor (GREEN)

- Create `tools/internal/speccraft/rust_canonical.go`:
  - `func CanonicalInlineTestIDs(content, fileStem string) []string` — runs `FindCfgTestModBlocks`, for each block extracts inner `fn` names via `rusttok.ExtractFnNames` on the body span, prepends `<fileStem>::<modName>::` (or nested-mod chain for nested) and emits the canonical ID.
  - `func CanonicalIntegrationTestIDs(content, fileStem string) []string` — extracts top-level `fn`s and emits `<fileStem>::<fn>`.
- All Step 28 tests pass.

### Step 30 — Delta-based "is this edit a test edit?" (RED)

- Create `tools/internal/speccraft/rust_delta_test.go` (table-driven over the four AC #2 fixture cases plus the L2 phantom case):
  - `Test_IsRustTestEdit_CleanInlineTest_Classified` (AC #2 (a)) — pre: prod-only file; post: same file + `#[cfg(test)] mod tests { fn it_works() {} }`. `post − pre = {foo::tests::it_works}` → returns `true`.
  - `Test_IsRustTestEdit_StringLiteralCfgTest_NotClassified` (AC #2 (b), FLIPPED from previous spec) — pre: prod-only; post: prod-only + a string literal containing the text `"#[cfg(test)] mod tests { fn it() {} }"`. Tokenizer skips the string; pre/post canonical-ID sets are both empty; delta empty → returns `false`.
  - `Test_IsRustTestEdit_MultiAttributeMod_Classified` (AC #2 (c)) — pre: prod-only; post: adds `#[cfg(test)] / #[allow(dead_code)] / mod tests { fn it() {} }`. Delta non-empty → `true`.
  - `Test_IsRustTestEdit_EditWithoutNewTestInExistingMod_NotClassified` (AC #2 (d), NEW) — pre: file already contains `#[cfg(test)] mod tests { fn old() {} }`; post: same file with re-indented body but no new `fn`. Pre and post canonical sets both `{foo::tests::old}` → delta empty → `false`.
  - `Test_IsRustTestEdit_MacroRulesPhantomFn_ClassifiedAsDocumentedLimitation` (§L2) — pre: prod-only; post: adds `#[cfg(test)] mod tests { macro_rules! m { ($n:ident) => { fn $n() {} } } }`. Tokenizer does NOT parse macro pattern bodies, so the literal `fn $n` is extracted as a phantom ID; delta non-empty → returns `true`. **This is the documented limitation.** The companion runner backstop assertion lives in Step 31.
- Tests fail: function does not exist.

Covers: AC #2 (all four fixture cases, including the flipped (b) and the new (d)), §L2 phantom-ID extraction half.

### Step 31 — Delta-based "is this edit a test edit?" (GREEN) + L2 runner-backstop assertion

- Create `tools/internal/speccraft/rust_delta.go`:
  - `func IsRustTestEdit(filePath, fileStem, preContent, postContent string) bool` — computes `pre := CanonicalInlineTestIDs(preContent, fileStem)`, `post := CanonicalInlineTestIDs(postContent, fileStem)`, returns `len(setDifference(post, pre)) > 0`. For integration files (`tests/<stem>.rs`), uses `CanonicalIntegrationTestIDs`.
- Append to `tools/internal/speccraft/rust_delta_test.go`:
  - `Test_MacroPhantomID_RunnerBackstopRejects` — table-driven: feed the phantom ID `foo::tests::n` to a fake runner returning `OutcomeAllPassed` (because `cargo test --exact foo::tests::n` finds nothing); assert that the guard's red-check logic (covered by Step 41) would reject with `"no failing test observed"`. Implemented here as a unit-level wiring test against a `runner.Result{Outcome: OutcomeAllPassed}` fixture using the same classification helper the guard uses; full integration is exercised by Step 41.
- All Step 30 + new test pass. The combination documents §L2 explicitly as a test: the phantom ID extraction is accepted as a known limitation; the runner is the authoritative backstop and the system stays sound.

Covers: AC #2 (all four cases), §L2 (documented-behavior test).

### Step 32 — Static recognition: integration stem-mapping (RED)

- Create `tools/internal/speccraft/rust_stem_test.go`:
  - `Test_RustStemMapping_TestsFooMapsToSrcFoo` — fixture with `src/foo.rs` → `RustProdForTest("tests/foo.rs", root)` returns `"src/foo.rs"`.
  - `Test_RustStemMapping_TestsFooMapsToSrcFooModRs` — fixture with `src/foo/mod.rs` only → returns `"src/foo/mod.rs"`.
  - `Test_RustStemMapping_TestsFooMapsToSrcFooDir` — fixture with both `src/foo.rs` and `src/foo/` directory → returns one (the spec accepts either; assert non-empty + path exists).
  - `Test_RustStemMapping_LibRsNotMapped` — `tests/lib.rs` → returns `""` (lib.rs is not a stem-mapping target).
  - `Test_RustStemMapping_NoMatchingProd` — `tests/orphan.rs` with no `src/orphan*` → `""`.
- Tests fail: function does not exist.

Covers: AC #3, AC #11 (lib.rs exclusion).

### Step 33 — Static recognition: integration stem-mapping (GREEN)

- Create `tools/internal/speccraft/rust_stem.go`:
  - `func RustProdForTest(testRelPath, root string) string` implementing the three precedence rules from spec §What.2.
- All Step 32 tests pass.

### Step 34 — Crate-walk discovery + just-added set-difference (RED)

- Create `tools/internal/speccraft/rust_discover_test.go`:
  - `Test_DiscoverRustTests_InlineFromSrc` — fixture `src/foo.rs` with `#[cfg(test)] mod tests { fn it_works() {} fn it_fails() {} }` → discovered IDs `["foo::tests::it_fails", "foo::tests::it_works"]` (canonical form, sorted).
  - `Test_DiscoverRustTests_IntegrationFromTests` — fixture `tests/bar.rs` with `fn alpha() {}` → `["bar::alpha"]`.
  - `Test_DiscoverRustTests_NestedModule` — `src/foo.rs` with nested test mod → nested canonical ID.
  - `Test_DiscoverRustTests_WalksLibRsForInline` — `src/lib.rs` with `#[cfg(test)] mod tests { fn x() {} }` → `["lib::tests::x"]` (lib.rs is walked for *inline* tests; the lib.rs exclusion in AC #3 is only about stem-mapping).
  - `Test_DiscoverRustTests_SkipsTargetDir` — files under `target/` are never walked.
  - `Test_JustAddedTests_SetDifference` — baseline `["a::b"]`, current `["a::b","c::d"]` → just-added `["c::d"]`.
  - `Test_JustAddedTests_EmptyBaseline_ReturnsAll` — baseline `[]`, current `["a","b"]` → `["a","b"]`.
- Tests fail: functions do not exist.

Covers: AC #8 (canonical IDs + set-difference, baseline-driven).

### Step 35 — Crate-walk discovery + just-added set-difference (GREEN)

- Create `tools/internal/speccraft/rust_discover.go`:
  - `func DiscoverRustTests(root string) ([]string, error)` — walks `src/**/*.rs` for inline tests (via `CanonicalInlineTestIDs` per file) and `tests/*.rs` for integration tests (via `CanonicalIntegrationTestIDs`); concatenates, deduplicates, sorts; skips `target/`.
  - `func JustAddedRustTests(baseline, current []string) []string` — set-difference returning sorted unique IDs in `current` not in `baseline`.
- All Step 34 tests pass.

### Step 36 — Refactor: consolidate Rust static-detection helpers (REFACTOR, optional)

- If duplication has emerged between `rust_inline.go`, `rust_canonical.go`, `rust_delta.go`, `rust_discover.go` (e.g. shared block-walk helper), extract a small internal helper. No behavior change.
- All Step 22–35 tests still pass.

### Step 37 — Crate fingerprint: pure function (RED)

- Create `tools/internal/speccraft/runner/fingerprint_test.go`:
  - `Test_ComputeCrateFingerprint_DeterministicOrder` — fixture with `src/a.rs`, `src/b.rs`, `Cargo.toml` → fingerprint is sorted-input SHA-256, independent of filesystem walk order.
  - `Test_ComputeCrateFingerprint_IncludesCargoToml` — touching `Cargo.toml`'s mtime changes the fingerprint.
  - `Test_ComputeCrateFingerprint_IncludesCargoLock` — touching `Cargo.lock` changes it.
  - `Test_ComputeCrateFingerprint_IncludesRustToolchainTomlIfPresent` — `rust-toolchain.toml` change → fingerprint change.
  - `Test_ComputeCrateFingerprint_IncludesCargoConfigTomlIfPresent` — `.cargo/config.toml` change → fingerprint change.
  - `Test_ComputeCrateFingerprint_WalksAllTrackedRoots` — `examples/x.rs`, `benches/y.rs`, `tests/z.rs` each included.
  - `Test_ComputeCrateFingerprint_ExcludesTargetDir` — touching `target/debug/foo` does not change fingerprint.
  - `Test_ComputeCrateFingerprint_UnrelatedRsChangeInvalidates` — modifying an unrelated `src/*.rs` changes fingerprint.
- Tests fail: function does not exist.

Covers: AC #10 (fingerprint definition + target exclusion).

### Step 38 — Crate fingerprint: pure function (GREEN)

- Create `tools/internal/speccraft/runner/fingerprint.go`:
  - `func ComputeCrateFingerprint(root string) (string, error)` — walks tracked roots, collects `(relpath, mtime-nanos, size)`, sorts, SHA-256s the concatenation, returns lowercase hex.
- All Step 37 tests pass.

### Step 39 — Pre-edit gate: cache-hit short-circuits subprocess (RED)

- Create `tools/internal/speccraft/runner/gate_test.go`:
  - `Test_PreEditGate_CacheHit_NoSubprocess` — fixture: write fingerprint X to state, do not change any tracked file → invoke `RunPreEditGate(root, cfg, exec)`; assert injected `exec` is not called, returns `nil` error.
  - `Test_PreEditGate_TouchedFileChange_Invalidates` — modify the touched file's mtime → exec is called with `["check", "--tests"]`.
  - `Test_PreEditGate_UnrelatedRsChange_Invalidates` — modify an unrelated `.rs` → exec called.
  - `Test_PreEditGate_CargoTomlChange_Invalidates` — modify `Cargo.toml` → exec called.
  - `Test_PreEditGate_TargetDirChange_DoesNotInvalidate` — modify `target/debug/foo` → exec NOT called.
  - `Test_PreEditGate_SuccessUpdatesFingerprint` — after a successful cache-miss run, the persisted `RustGateFingerprint` equals the newly-computed fingerprint.
- Tests fail: `RunPreEditGate` does not exist.

Covers: AC #10 (behavioral assertions).

### Step 40 — Pre-edit gate: cache-hit short-circuits subprocess (GREEN)

- Create `tools/internal/speccraft/runner/gate.go`:
  - `func RunPreEditGate(root string, cfg SpeccraftConfig, exec ExecFunc) error`:
    1. Compute current fingerprint.
    2. Load stored `RustGateFingerprint` via `speccraft.GetRustFingerprint(root)`.
    3. If equal → return `nil` (cache hit, zero subprocesses).
    4. Else invoke `exec("cargo", "check", "--tests")`. On exit 0, persist new fingerprint via `speccraft.SetRustFingerprint`. On non-zero, return error citing build failure (does NOT update fingerprint).
- All Step 39 tests pass.

### Step 41 — Baseline lifecycle: initial-capture + post-accept-update helpers (RED)

- Create `tools/internal/speccraft/rust_baseline_test.go`:
  - `Test_RustBaseline_InitialCapture_WritesWalkedIDs` (AC #12(a)+(b)) — fixture crate with three pre-existing inline test fns + one integration test fn; baseline empty in state; call `CaptureInitialRustBaseline(root)` → state's `RustTestBaseline` equals the sorted union of `DiscoverRustTests(root)`.
  - `Test_RustBaseline_InitialCapture_SkipsWhenNonEmpty` — baseline already `["x::y"]`; call `CaptureInitialRustBaseline(root)` → state unchanged, function returns a sentinel "no-op" result.
  - `Test_RustBaseline_PostAcceptUpdate_AppendsFailingJustAddedOnly` (AC #12(c)) — given just-added set `{a::b, c::d, e::f}` and runner records `[{a::b, failed}, {c::d, passed}, {e::f, failed}, {g::h, failed}]`, the appended IDs are exactly `{a::b, e::f}` — the failing tests that are also in the just-added set; passing tests (`c::d`) and out-of-set failures (`g::h`) are excluded.
  - `Test_RustBaseline_PostAcceptUpdate_DedupsAgainstExisting` — if baseline already contains `a::b`, second post-accept run does not duplicate it.
  - `Test_RustBaseline_ManualRecapture_OverwritesBaseline` (AC #12(d)) — fixture with baseline `["stale::x"]`, current walk yields `["foo::tests::a"]`; call `RecaptureRustBaseline(root)` → baseline becomes exactly `["foo::tests::a"]` (stale entries removed).
- Tests fail: functions do not exist.

Covers: AC #12 (a), (b), (c), (d).

### Step 42 — Baseline lifecycle: initial-capture + post-accept-update helpers (GREEN)

- Create `tools/internal/speccraft/rust_baseline.go`:
  - `func CaptureInitialRustBaseline(root string) (captured bool, count int, err error)` — loads current baseline; if empty, walks crate via `DiscoverRustTests`, calls `SetRustBaseline(root, ids)`, returns `(true, len(ids), nil)`; else returns `(false, 0, nil)`.
  - `func PostAcceptUpdateRustBaseline(root string, justAdded []string, records []runner.TestRecord) error` — computes `failingJustAdded := intersection(justAdded, {r.TestName | r.Status == "failed"})`, calls `AppendRustBaseline(root, failingJustAdded)`.
  - `func RecaptureRustBaseline(root string) (int, error)` — walks crate via `DiscoverRustTests`, calls `SetRustBaseline(root, ids)` (overwrite), returns `len(ids)`.
- All Step 41 tests pass.

### Step 43 — `speccraft-state rust-baseline recapture` subcommand (RED)

- Extend `tools/cmd/speccraft-state/main_test.go`:
  - `Test_StateCmd_RustBaselineRecapture_OverwritesFromWalk` — fixture crate with one inline test; baseline pre-set to `["stale::x"]`; invoke binary with `rust-baseline recapture`; assert state's `RustTestBaseline` equals the freshly-walked list; assert stdout contains `"recaptured: N tests"` for verification.
  - `Test_StateCmd_RustBaselineRecapture_EmptyCrate_ClearsBaseline` — fixture with no `.rs` files containing tests; recapture → baseline becomes `[]`.
- Tests fail: subcommand does not exist.

Covers: AC #12 (manual recapture path).

### Step 44 — `speccraft-state rust-baseline recapture` subcommand (GREEN)

- Edit `tools/cmd/speccraft-state/main.go`:
  - Add `rust-baseline recapture` subcommand that calls `speccraft.RecaptureRustBaseline(root)` and prints `"recaptured: <N> tests"`.
- All Step 43 tests pass.

### Step 45 — Workspace detection (RED)

- Create `tools/internal/speccraft/rust_workspace_test.go`:
  - `Test_DetectCargoWorkspace_NoWorkspace_Single` — `[package]` only → `IsCargoWorkspace(root)` returns `false`, no error.
  - `Test_DetectCargoWorkspace_HasWorkspaceTable` — `[workspace]` table → returns `true`.
  - `Test_DetectCargoWorkspace_BothPackageAndWorkspace` — virtual manifest hybrid → returns `true`.
  - `Test_DetectCargoWorkspace_MissingCargoToml` — no Cargo.toml → returns `false`, no error.
- Tests fail: function does not exist.

Covers: AC #5 (detection).

### Step 46 — Workspace detection (GREEN)

- Create `tools/internal/speccraft/rust_workspace.go`:
  - `func IsCargoWorkspace(root string) (bool, error)` — reads `Cargo.toml`, scans for a `[workspace]` line at column 0 (ignoring comments and string literals minimally).
- All Step 45 tests pass.

### Step 47 — Guard wiring: workspace error path (RED)

- Extend `tools/cmd/speccraft-guard/main_test.go`:
  - `Test_Guard_WorkspaceDetected_ExitsNonZeroWithRefTo0006` — fixture repo with `[workspace]` in `Cargo.toml`; invoke guard binary; assert non-zero exit, stderr contains literal `"0006"` AND literal `"workspace support"`.
- Test fails: guard does not yet check for workspaces.

Covers: AC #5 (guard error).

### Step 48 — Guard wiring: workspace error path (GREEN)

- Edit `tools/cmd/speccraft-guard/main.go`:
  - Early in the Rust dispatch branch, call `speccraft.IsCargoWorkspace(root)`. If true → write to stderr `"Cargo workspace detected. Workspace support is reserved for spec 0006 (Cargo workspace support); single-crate projects only are supported by this version."` and exit non-zero.
- All Step 47 tests pass.

### Step 49 — Guard wiring: initial-capture skip-red-check path (RED)

- Extend `tools/cmd/speccraft-guard/main_test.go`:
  - `Test_Guard_RustInitialCapture_SkipsRedCheck` (AC #12(a)) — fixture: `RustTestBaseline` empty in state, crate contains 3 pre-existing test fns; invoke guard against a Rust file edit; assert (i) exit 0 (success), (ii) the injected fake runner is NOT called (zero red-check), (iii) `speccraft-state get rust_test_baseline` afterwards yields the three IDs, (iv) stderr contains the literal log line `"rust_test_baseline captured: 3 tests"`.
  - `Test_Guard_RustInitialCapture_OnlyOnFirstInvocation` — second invocation immediately after first, with no edits in between: baseline is now non-empty, so the capture path is skipped and red-check evaluation proceeds normally (assert runner IS called this time).
- Tests fail: guard does not yet implement the initial-capture branch.

Covers: AC #12 (initial-capture branch reaches the guard).

### Step 50 — Guard wiring: initial-capture skip-red-check path (GREEN)

- Edit `tools/cmd/speccraft-guard/main.go`:
  - Before the red-check, after the workspace check and pre-edit gate, call `speccraft.CaptureInitialRustBaseline(root)`. If `captured == true`, log `"rust_test_baseline captured: <N> tests"` to stderr and return success WITHOUT invoking the runner.
- All Step 49 tests pass.

### Step 51 — Guard wiring: red-check via runner adapter + post-accept update (RED)

- Extend `tools/cmd/speccraft-guard/main_test.go`:
  - `Test_Guard_RustRedCheck_BuildFailedRejects` — fixture (baseline pre-populated to bypass initial-capture) + fake runner returning `OutcomeBuildFailed` → guard exits non-zero with stderr containing `"build failed"`.
  - `Test_Guard_RustRedCheck_AllPassedRejects` — fake returns `OutcomeAllPassed` → exits non-zero with stderr `"no failing test observed"`.
  - `Test_Guard_RustRedCheck_AtLeastOneFailedAccepts_WhenInJustAddedSet` — fake returns `OutcomeAtLeastOneFailed` with failing record `foo::tests::it_fails`; baseline pre-populated such that the failing name IS in the just-added set → guard exits 0.
  - `Test_Guard_RustRedCheck_AtLeastOneFailedRejects_WhenNotInJustAddedSet` — failing test name is already in baseline → exits non-zero.
  - `Test_Guard_RustRedCheck_IgnoredNotAFailure` — fake returns `ignored` records only and `OutcomeAllPassed` → exits non-zero with stderr `"no failing test observed"`.
  - `Test_Guard_RustRedCheck_PostAccept_AppendsFailingJustAddedToBaseline` (AC #12 post-accept) — after the accept branch fires for `{foo::tests::it_fails}`, `speccraft-state get rust_test_baseline` returns a baseline that includes `foo::tests::it_fails`.
- Tests fail: guard does not call the runner or invoke the post-accept update.

Covers: AC #4 (all three outcomes, ignored rule, just-added intersection), AC #8 (uses baseline), AC #12 (post-accept update reaches guard).

### Step 52 — Guard wiring: red-check via runner adapter + post-accept update (GREEN)

- Edit `tools/cmd/speccraft-guard/main.go`:
  - After the initial-capture short-circuit, add a red-check workflow:
    1. Compute current set via `DiscoverRustTests`.
    2. Load `RustTestBaseline` via `speccraft.GetRustBaseline`.
    3. `justAdded := JustAddedRustTests(baseline, current)`.
    4. For each just-added FQTN, build a `runner.Request`, call `AdapterFor(cfg).Run(...)`.
    5. Apply outcome rules per AC #4.
    6. On accept, call `speccraft.PostAcceptUpdateRustBaseline(root, justAdded, allRecords)`.
  - Wire a real `CargoAdapter` / `NextestAdapter` exec function in `main`; allow tests to inject a fake via an unexported package-level seam.
- All Step 51 tests pass.

### Step 53 — Guard wiring: pre-edit gate integration (RED)

- Extend `tools/cmd/speccraft-guard/main_test.go`:
  - `Test_Guard_PreEditGate_CacheHit_SkipsCargo` — fixture with matching `rust_gate_fingerprint` + PATH-prepended cargo shim that writes argv to a log; assert log is empty after guard run, exit 0.
  - `Test_Guard_PreEditGate_CacheMiss_RunsCargoCheck` — mismatched fingerprint + shim → log contains `"check --tests"`, exit 0 on shim success.
  - `Test_Guard_PreEditGate_CacheMiss_BuildFailedRejects` — shim exits non-zero → guard exits non-zero, error mentions `"pre-edit gate"` or `"cargo check"`.
- Tests fail: guard does not invoke the pre-edit gate yet.

Covers: AC #10 (cache hit + miss + invalidation reach the guard).

### Step 54 — Guard wiring: pre-edit gate integration (GREEN)

- Edit `tools/cmd/speccraft-guard/main.go`:
  - Before the initial-capture short-circuit and red-check, call `runner.RunPreEditGate(root, cfg, exec)`.
  - On error from the gate, exit non-zero with the gate's error message.
- All Step 53 tests pass.

### Step 55 — Toolchain provisioning: e2e fail-fast (RED)

- Add a bash-level smoke test of the e2e harness preamble, in `tests/e2e/rust_preamble.sh` (sourced from `tests/e2e/run.sh`):
  - `Test_E2EHarness_FailsFast_WhenCargoAbsent` — invoke `run.sh` with `PATH` scrubbed of `cargo` → exit non-zero, stderr contains literal `"cargo not found on PATH"`.
- Test fails: current `run.sh` does not perform the check.

Covers: AC #9 (e2e fail-fast).

### Step 56 — Toolchain provisioning: e2e fail-fast (GREEN)

- Edit `tests/e2e/run.sh`:
  - Add a preamble after `set -euo pipefail`: `command -v cargo >/dev/null 2>&1 || { echo "cargo not found on PATH" >&2; exit 2; }`.
- Edit `.devcontainer/setup.sh` (or `scripts/install-rust.sh`):
  - Install `rustup` + stable toolchain (idempotent: skip if `rustc --version` succeeds).
- All Step 55 tests pass.

### Step 57 — E2E: full red→green→refactor for inline + integration (RED)

- Add `tests/e2e/rust_inline_cycle.sh` and `tests/e2e/rust_integration_cycle.sh`:
  - `rust_inline_cycle.sh`:
    1. Scaffold a fresh single-crate fixture under a temp dir.
    2. **First invocation: initial-capture** — run guard once with the baseline empty; assert stderr `"rust_test_baseline captured"` log, exit 0.
    3. **Add failing inline test** — edit `src/lib.rs` to add `#[cfg(test)] mod tests { fn it_fails() { assert_eq!(1, 2); } }`; run guard → expect "accept" (red satisfied); assert post-state baseline now contains `lib::tests::it_fails`.
    4. **Make it pass** — fix the assertion; run runner directly → expect `OutcomeAllPassed`.
    5. **Post-baseline-update behavior** — assert a follow-up edit without a new test is blocked (because the test is now in the baseline and no new just-added IDs exist).
    6. **Manual recapture** — invoke `speccraft-state rust-baseline recapture`; assert baseline equals freshly-walked IDs.
  - `rust_integration_cycle.sh`:
    1. Scaffold fixture with `src/foo.rs` (no tests) and create `tests/foo.rs` with `#[test] fn alpha() { panic!() }`. Run guard → accept (after initial-capture skip).
    2. Edit `src/foo.rs` prod → ensure stem-mapping unlock.
    3. Fix `tests/foo.rs` to `assert!(true)`. Verify green.
  - Wire both into `tests/e2e/run.sh`. Add an `if [ "${SPECCRAFT_E2E_NEXTEST:-}" = "1" ]; then ... else echo "skipping nextest path (set SPECCRAFT_E2E_NEXTEST=1 to enable)"; fi` branch that re-runs `rust_inline_cycle.sh` with `runner = "nextest"`.
- Scripts fail initially because they invoke pieces that depend on Steps 1–54.

Covers: AC #6, AC #12 e2e exercise of all three lifecycle paths.

### Step 58 — E2E: full red→green→refactor for inline + integration (GREEN)

- All prior steps' implementations together make the e2e scripts pass under `bash tests/e2e/run.sh`.
- If a missing piece is discovered, it gets added here as targeted GREEN work tied back to whichever Step's contract it falls under.

### Step 59 — Docs: README "Rust" section (RED)

- Add `tests/docs/rust_readme_test.sh`:
  - `Test_README_HasRustSection` — `grep -E "^## (Rust|Language: Rust)" README.md` matches at least once.
  - `Test_README_DocumentsTddRustConfig` — `grep -F "[tdd.rust]" README.md` matches.
  - `Test_README_DocumentsRunnerInvocation` — `grep -F "runner" README.md` near the Rust section.
  - `Test_README_DocumentsBaselineLifecycle` — grep for `"rust_test_baseline"` and `"rust-baseline recapture"` in the Rust section.
- Test fails: README has no Rust section.

Covers: AC #7, AC #12 documentation.

### Step 60 — Docs: README "Rust" section (GREEN)

- Edit `README.md`:
  - Add a new "Rust" section documenting:
    - Inline (`#[cfg(test)] mod`) vs integration (`tests/<stem>.rs`) test conventions.
    - The `[tdd.rust]` config block with `runner = "cargo" | "nextest"`.
    - That the guard invokes the configured runner with a single-test filter per edit.
    - The pre-edit gate's cache behavior (one line).
    - The baseline lifecycle: initial-capture on first run, post-accept update, manual `speccraft-state rust-baseline recapture`.
    - The delta-based detection rule (per AC #2) and the §L2 macro limitation.
- Do NOT modify any file under `templates/speccraft/**`.
- All Step 59 tests pass.

### Step 61 — Docs: `.speccraft/conventions.md` `reserves-specs` (RED)

- Add `tests/docs/conventions_reserves_specs_test.sh`:
  - `Test_Conventions_DocumentsReservesSpecs` — `grep -F "reserves-specs" .speccraft/conventions.md` returns at least one match.
  - `Test_Conventions_CoversAllSixBullets` — grep for each of the six bullet keywords: `purpose`, `shape`, `allocation`, `lifecycle`, `consistency`, `lower-bound` within a 60-line window around the first `reserves-specs` match.
- Test fails: conventions.md has no such section.

Covers: AC #11.

### Step 62 — Docs: `.speccraft/conventions.md` `reserves-specs` (GREEN)

- Edit `.speccraft/conventions.md`:
  - Add a new subsection under "Spec frontmatter" titled `### Optional: reserves-specs`.
  - Cover the six bullets from spec AC #11: purpose, shape, allocation rule (advisory), lifecycle, consistency, lower-bound.
- All Step 61 tests pass.

### Step 63 — Refactor: consolidate Rust helpers, factor duplicate guard branches (REFACTOR, optional)

- If the Rust dispatch in `tools/cmd/speccraft-guard/main.go` has grown duplicate scaffolding alongside Go and Python, extract a small per-language interface (`type langDispatcher interface { Handle(ctx, edit) Outcome }`) and instantiate one per language. No behavior change.
- All tests still pass.

## AC coverage map

| AC  | Subject                                                          | Covered by steps                              |
| --- | ---------------------------------------------------------------- | --------------------------------------------- |
| 1   | `[tdd.rust]` config + runner enum validation                     | 1, 2, 3, 4, 20, 21, 18 (nextest missing)      |
| 2   | Delta-based inline detection (a/b/c/d)                           | 22, 23, 24, 25, 26, 27, 28, 29, 30, 31        |
| 3   | Integration stem-mapping                                         | 32, 33                                        |
| 4   | Runner red-check three-outcome contract                          | 10–21, 51, 52                                 |
| 5   | Workspace detection + 0006 error                                 | 45, 46, 47, 48                                |
| 6   | E2E inline + integration cycle                                   | 55, 56, 57, 58                                |
| 7   | README Rust section, templates untouched                         | 59, 60                                        |
| 8   | Canonical IDs, baseline single-writer                            | 5–9, 28, 29, 34, 35, 51 (uses baseline)       |
| 9   | Devcontainer/CI toolchain + e2e fail-fast                        | 55, 56                                        |
| 10  | Crate fingerprint + cache hit/miss behavior                      | 37–40, 53, 54                                 |
| 11  | `lib.rs` exclusion + `reserves-specs` docs                       | 32, 33, 61, 62                                |
| 12  | Baseline lifecycle (initial / post-accept / recapture)           | 5–9, 41, 42, 43, 44, 49, 50, 51, 52, 57       |

§L2 documented-behavior assertion: Step 30 (phantom-ID extracted) + Step 31 (runner backstop rejects).

## Delegation

- Steps 12, 13, 16, 17 (libtest text/JSON parsing) — delegation candidate (`codex`): pure parsing problem with concrete fixtures, well-scoped, no architectural judgment required.
- Steps 22, 23 (Rust tokenizer state machine) — keep with primary author. Reason: state-machine correctness is load-bearing for AC #2 (b) and (d); subtle bugs (e.g. nested block comments, raw-string hash counting) need careful review.
- Steps 24, 25 (`fn` extractor) — delegation candidate after Step 23 lands.
- Steps 26, 27 (inline `#[cfg(test)] mod` regex with brace-balanced body span) — delegation candidate.
- Steps 30, 31 (delta computation + L2 backstop assertion) — keep with primary author. Reason: cross-cuts tokenizer, extractor, canonical-ID extractor, and runner-result shape; the (b)/(d) flips are spec-level decisions worth careful review.
- Steps 41, 42, 43, 44 (baseline lifecycle helpers + `recapture` subcommand) — keep with primary author. Reason: integration judgment across state-package, `speccraft-state` CLI, and guard dispatch; AC #12(e)'s single-writer extension must be verified by hand.
- Steps 47–54 (guard wiring) — keep with primary author. Reason: cross-cuts state, runner, fingerprint, config, baseline lifecycle, and pre-edit gate; integration judgment required across multiple internal contracts.
- Steps 57, 58 (e2e bash) — `codex` candidate for the script bodies once the underlying binaries are stable; primary author reviews against `tests/e2e/run.sh` conventions before merge.

If no aux agents are configured, all steps remain with the primary author.

## Risk

- **Risk: tokenizer correctness for edge cases.** Nested block comments and raw-string hash counting are easy to get subtly wrong; an off-by-one means a delta could be miscomputed in either direction (false positive or false negative). Mitigation: Step 22 covers all known edge cases by name; if a real-world bug surfaces post-merge, the fix is a one-file change in `rusttok/tokenizer.go` with a regression test.
- **Risk: §L2 macro phantom-ID frequency higher than expected.** If real-world crates put `fn`-generating macros inside `#[cfg(test)] mod` blocks more often than anticipated, users will see "no failing test observed" rejections without an obvious cause. Mitigation: Step 30's documented test makes the limitation visible; Step 60 documents it in the README; the runner backstop keeps the system sound (the rejection is correct, just confusing). A future spec can add `syn`/`tree-sitter-rust` parsing if incidence is high.
- **Risk: libtest text format drift.** Future `cargo` releases may tweak the `test X ... Y` line. Mitigation: parser is isolated to `cargo_parse.go` with its own fixture-driven tests; replacing it on a format change is a one-file edit.
- **Risk: nextest libtest-json schema drift.** Same mitigation — parser is isolated to `nextest_parse.go`.
- **Risk: fingerprint walk is slow on very large crates.** Spec sets <100ms as a design target only, not a contract; AC #10 asserts the *zero-subprocess* behavior on cache hit, not wall time. Acceptable for v1.
- **Risk: `target/` exclusion bug allows cache to become stale.** Mitigation: explicit Step 37 test asserts `target/` change does NOT invalidate, and Step 39 test asserts unrelated `.rs` and `Cargo.toml` DO invalidate.
- **Risk: e2e flakiness from real `cargo` invocation under CI.** Mitigation: e2e fixture is a minimal single-file lib with no dependencies; nextest path is opt-in via `SPECCRAFT_E2E_NEXTEST=1`.
- **Risk: AC #12(a) initial-capture-skips-red-check could mask a real test failure on the very first invocation.** Mitigation: this is exactly the spec's intent — there is no prior green state to transition from, so red-check is undefined. The behavior is logged to stderr (`"rust_test_baseline captured: N tests"`) so the user knows a capture happened.
- **Risk: single-writer guardrail is grep-based and could be circumvented by reflection.** Mitigation: explicit AC #8 + AC #12(e) documentation + Step 9 grep test catches the common path. Step 9's allow-list also covers `tools/cmd/speccraft-state/main.go` so the new `rust-baseline append`/`recapture` subcommands are recognized as authorized writers.
- **Risk: guard's package-level fake-runner injection clutters production code.** Mitigation: prefer an unexported `var newAdapter = runner.AdapterFor` indirection that tests override, rather than a public seam. Refactor in Step 63 if needed.

## Concerns / spec-as-written observations

- **AC #12(a) initial-capture is invisible to first-run users beyond the stderr log line.** If a user installs speccraft on a crate, makes an edit, and is surprised to see "accept" without their test having actually been evaluated, the explanation is buried in `"rust_test_baseline captured: N tests"`. Step 60 documents this in the README; future UX work could emit a one-time banner the next time the guard fires after capture, but that's out of scope here.
- **AC #12(c) defines the post-accept update as "failing just-added IDs" — the intersection of `justAdded` with `{r.TestName | r.Status == "failed"}`.** The spec is explicit, but worth re-confirming during implementation that `r.TestName` uses the canonical form (per AC #8) when computing the intersection, not raw libtest output. Steps 12/16's parsers strip the crate prefix, so this should hold; Step 41's table-driven tests assert it directly.
- **§L2 phantom-ID documentation is split between Steps 30 (tokenizer-level extraction asserted) and 31 (runner-backstop assertion).** A reviewer reading either test in isolation might miss the other half; the test-name suffix `_AsDocumentedLimitation` should make the linkage clear. Step 60's README mention closes the loop for users.
- **Step 41's `Test_RustBaseline_PostAcceptUpdate_AppendsFailingJustAddedOnly` uses a runner-record fixture with both passing and failing tests in the same call.** Real adapters (Steps 14, 18) only invoke the runner with a single-test filter, so the records list will typically be a single record. The test still exercises the intersection logic correctly because the helper's contract is "given these records, append only the failing just-added IDs"; the singularity of real runner invocations is a guard-dispatch concern, not a baseline-helper concern.
- **Step 49's `Test_Guard_RustInitialCapture_OnlyOnFirstInvocation` requires careful fixture setup**: the second invocation must run after the first has populated the baseline via `speccraft-state`, and the fake runner must be reset between the two. Otherwise the test could pass spuriously.
- **AC #9 covers both devcontainer AND CI.** The plan addresses the devcontainer side via `setup.sh`. CI side is implied by the existing e2e job already running `tests/e2e/run.sh`; if the workflow file needs an explicit `actions-rs/toolchain` step or equivalent, that lands as part of Step 56. Worth confirming during implementation whether the existing CI image has `cargo` available.
- **Step 55/59/61 use bash-based "tests"** for e2e/docs assertions because the test surface is not Go. These run as part of `tests/e2e/run.sh` rather than `go test ./...`. The strict-TDD ordering is preserved at the bash level. Plan notes this explicitly so reviewers do not look for matching `_test.go` files for these steps.
