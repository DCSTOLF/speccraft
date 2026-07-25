---
spec: "0034"
status: planned
strategy: tdd
---

# Plan — 0034 Stack-agnostic planning & execution

Shape: a Go detection core + two `speccraft-state` subcommands
(`tools/internal/speccraft`, `tools/cmd/speccraft-state`), init seeding wiring
(`commands/spec/init.md` + a pure bash helper), two repo-structural meta-tests
(AC6 prose scan, AC7 template scan), four authoring-doc rewrites + one shipped
template strip, and a `1.7.1 → 1.8.0` version bump across the three binaries and
two JSON manifests. Every RED that must hold is authored as a SINGLE edit
introducing one fresh failing test id; the driving REDs for the subcommands and
the meta-tests all COMPILE against current code and fail on BEHAVIOR (spec 0031
technique), so no `/speccraft:spec:override` is implicated. The one genuine
new-symbol boundary (`DetectStack`) is bootstrapped stub-first so its substantive
GREEN is unlocked by a real observed failure, not a build error — see §Risk.

## RED preconditions confirmed at plan time (on `main`)

- `tools/internal/speccraft/detect.go` does not exist; there is no `Stack` type
  or `DetectStack` symbol anywhere in the package.
- `tools/cmd/speccraft-state/main.go` `run()` `switch` has no `detect-stack` or
  `test-command` case → both currently exit 1 with `unknown subcommand`.
- `cfg.TDD.Go.Command` default is the bare `"go test"` (config.go
  `applyDefaults`); AC1/AC3 require the surfaced go command to be `go test ./...`
  → DetectStack must append the package selector.
- `agents/tdd-planner.md` rule 3/7 + example paths are Go; `commands/spec/plan.md`
  line 21 greps `find <pkg> -name '*_test.go'`; `implement.md` line 21c and
  `delegate.md` line 23 mandate a bare `go test ./...`.
- `templates/speccraft/conventions.md` ships `enforce: pattern="^func Test[A-Z]"
  scope="**/*_test.go"`, `fmt.Errorf`, `slog`, `cmd/` idioms.
- `const version = "1.7.1"` in all three `tools/cmd/*/main.go`; `"version":
  "1.7.1"` in `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`.
  Sibling version tests assert `1.7.1` (`Test_StateCmd_Version_Is171` +
  guard/drift `version_test.go`).

## Test-first sequence

### Phase 1 — Detection core (`tools/internal/speccraft`)

#### Step 1 — `DetectStack` stub bootstrap (BOOTSTRAP)
- Add `tools/internal/speccraft/detect.go` with ONLY the public contract as a
  compiling stub:
  - `type Stack struct { Language string; TestCommand string; TestPatterns []string; InlineTests bool }`
  - `func DetectStack(root string, cfg SpeccraftConfig) Stack { return Stack{Language: "unknown", TestPatterns: []string{}} }`
- No manifest probing yet. This introduces the symbol on a compiling surface so
  the Step-2 table test can reference `DetectStack`/`Stack`, COMPILE, and fail on
  behavior (stub always returns `unknown`) rather than fail to build. See §Risk
  for why this ordering keeps the substantive detection GREEN override-free.

#### Step 2 — Detection table + polyglot + unknown (RED) — AC1, AC2
- Add `tools/internal/speccraft/detect_test.go` (package `speccraft_test`,
  mirrors `config_test.go`/`root_test.go`). A `newManifestRoot(t, files...)`
  helper writes the named empty manifest files under `t.TempDir()`; a
  `cfgWithRust(runner)` helper builds a `SpeccraftConfig` with an explicit
  `TDD.Rust.Runner`. Table cases (single-manifest, per §What table):
  - `Test_DetectStack_GoMod_ReturnsGo` — `go.mod` → `Language:"go"`,
    `TestCommand:"go test ./..."`, `TestPatterns:["*_test.go"]`, `InlineTests:false`.
  - `Test_DetectStack_CargoToml_Cargo_ReturnsRustInlineTrue` — `Cargo.toml` +
    `Runner:"cargo"` → `"rust"`, `TestCommand:"cargo test"`,
    `TestPatterns:["tests/*.rs"]`, `InlineTests:true`.
  - `Test_DetectStack_CargoToml_Nextest_ReturnsCargoNextestRun` — `Runner:"nextest"`
    → `TestCommand:"cargo nextest run"`, `InlineTests:true` (both Rust runner
    values asserted per AC1).
  - `Test_DetectStack_Pyproject_ReturnsPython`, `_SetupPy_`, `_SetupCfg_`,
    `_Requirements_` — each Python manifest alone → `"python"`, pytest command,
    `TestPatterns:["test_*.py","*_test.py"]`, `InlineTests:false`.
  - `Test_DetectStack_PackageJSON_ReturnsJS` — `package.json` only → `"js"`,
    `TestPatterns:["*.test.js","*.spec.js"]`.
  - `Test_DetectStack_PackageJSONWithTsconfig_ReturnsTS` — `package.json` +
    `tsconfig.json` → `"ts"`, `TestPatterns:["*.test.ts","*.spec.ts"]`.
  - `Test_DetectStack_NoManifest_ReturnsUnknown` — empty root → `Language:"unknown"`,
    `TestCommand:""`, `TestPatterns:[]` asserted DIRECTLY (not by absence) — AC2.
  - Polyglot adjacency (each pins one boundary of `go > rust > python > ts > js`
    so the order cannot silently reorder — AC2):
    `Test_DetectStack_Polyglot_GoBeatsRust` (`go.mod`+`Cargo.toml`→`"go"`),
    `Test_DetectStack_Polyglot_RustBeatsPython` (`Cargo.toml`+`pyproject.toml`→`"rust"`),
    `Test_DetectStack_Polyglot_PythonBeatsTS` (`pyproject.toml`+`package.json`+`tsconfig.json`→`"python"`),
    `Test_DetectStack_Polyglot_TSBeatsJS` (`package.json`+`tsconfig.json`→`"ts"`).
- Tests fail: every non-`unknown` case fails because the Step-1 stub returns
  `unknown` — a genuine OBSERVED failure (the file compiles against the stub).

#### Step 3 — Implement `DetectStack` (GREEN) — AC1, AC2
- Replace the stub body in `detect.go`. Probe ONLY exact repo-root manifest paths
  (`filepath.Join(root, "<manifest>")`, never a walk). Encode the precedence as
  ORDERED data in one place (a `var manifestOrder = []langProbe{…}` from `go` down
  to `js`) and return the first match, so precedence is not
  filesystem-iteration-order dependent. Compose commands from `cfg`:
  go → `strings.TrimSpace(cfg.TDD.Go.Command) + " ./..."`; rust → `cargo test` /
  `cargo nextest run` by `cfg.TDD.Rust.Runner`; python/js/ts → the matching
  `cfg.TDD.<Lang>.Command`. Rust sets `InlineTests:true`. Unknown returns the
  zero-value shape with `TestPatterns: []string{}`.
- All Step-2 tests pass.

### Phase 2 — `speccraft-state` subcommands (`tools/cmd/speccraft-state`)

#### Step 4 — `detect-stack` subcommand (RED) — AC3
- Add to `tools/cmd/speccraft-state/main_test.go` (package `main`; reuses
  `makeRepo`/`runCmd`; a `writeManifest(t, repo, name)` helper seeds a root
  manifest under the repo's `.speccraft`-bearing dir). All drive `run()` — the
  EXISTING seam — so they compile against current code:
  - `Test_StateCmd_DetectStack_GoFixture_TestCommandIsGoTest` — go.mod fixture →
    exit 0, stdout is `{"schema":1,…}` with `"language":"go"` and
    `"test_command":"go test ./..."`.
  - `Test_StateCmd_DetectStack_PythonFixture_TestCommandIsPytest_NotGoTest` —
    pyproject fixture → `"language":"python"`, `test_command` contains `pytest`
    and is NOT `go test ./...` (AC3 anti-Go pin).
  - `Test_StateCmd_DetectStack_Unknown_Exit0_SchemaJSON` — no manifest → exit 0,
    `"language":"unknown"`, `"test_command":""`, `"test_patterns":[]`.
  - `Test_StateCmd_DetectStack_OutsideRepo_ExitsNonZero` — run in a dir with no
    `.speccraft/` ancestor → non-zero exit, nothing on stdout.
- Tests fail: `detect-stack` is an unknown subcommand → exit 1 / `unknown
  subcommand` on stderr → assertions fail on BEHAVIOR (compile-stable).

#### Step 5 — Wire `detect-stack` (GREEN) — AC3
- Add a `case "detect-stack":` to `run()`: `FindRoot("")` (non-zero on error),
  `ReadConfig(root)`, `DetectStack(root, cfg)`, marshal a versioned envelope
  `{"schema":1,"language":…,"test_command":…,"test_patterns":[…],"inline_tests":…}`
  (a local anonymous struct with fixed JSON tags; `test_patterns` marshals `[]`
  not `null` for unknown), print + exit 0. Extend `usage()`.
- All Step-4 tests pass.

#### Step 6 — `test-command` precedence + marker grammar (RED) — AC4
- Add to `main_test.go`, all driving `run(["test-command"])` (compile-stable);
  a `writeConventions(t, repo, body)` helper writes `.speccraft/conventions.md`:
  - `Test_StateCmd_TestCommand_MarkerOverridesDetection` — go.mod fixture but a
    marker `<!-- speccraft:test-command = "pytest -q" -->` → stdout `pytest -q`
    (marker wins over detection).
  - `Test_StateCmd_TestCommand_RoundTripsShellOperatorAndEscapedQuote` — marker
    body `go build && go test -run \"X\" ./...` → emitted verbatim (unescaped),
    proving it is data, not evaluated.
  - `Test_StateCmd_TestCommand_EmptyMarker_FallsBackToDetection` — marker `""` →
    the detected command.
  - `Test_StateCmd_TestCommand_MalformedMarker_FallsBackToDetection` — an
    unescaped interior quote / no regex match → detection, never an error.
  - `Test_StateCmd_TestCommand_DuplicateMarkers_FirstWins`.
  - `Test_StateCmd_TestCommand_UnknownStack_NoMarker_ExitsNonZeroPrintsNothing`.
- Tests fail: `test-command` is an unknown subcommand (behavioral RED).

#### Step 7 — Wire `test-command` + marker parser (GREEN) — AC4
- Add `tools/internal/speccraft/marker.go` with
  `func EffectiveTestCommand(root string, cfg SpeccraftConfig) (string, bool)`:
  read `.speccraft/conventions.md`, scan PER LINE with
  `<!--\s*speccraft:test-command\s*=\s*"((?:\\.|[^"\\])*)"\s*-->`, first match
  wins, unescape `\"`→`"` / `\\`→`\`; empty/malformed → fall through to
  `DetectStack(...).TestCommand`; return `(cmd, cmd != "")`. Add a `case
  "test-command":` to `run()` that prints `cmd`+exit 0 when ok, else nothing +
  exit non-zero. In the SAME edit add characterization pins referencing the now-
  existing symbol: `Test_ParseTestCommandMarker_UnescapesEscapes`,
  `Test_ParseTestCommandMarker_RejectsUnescapedInteriorQuote` in
  `marker_test.go` (test file — always allowed).
- All Step-6 tests pass.

### Phase 3 — init seeding (`commands/spec/init.md`)

#### Step 8 — init seeds conventions.md, preserves existing (RED) — AC5
- Add `tests/hooks/init-seed-conventions.bats` sourcing a new pure helper
  `commands/spec/init.lib.sh::seed_conventions <root>` (colocation convention,
  spec 0015; `${BASH_SOURCE[0]:-$0}` self-location, spec 0029):
  - `@test fresh Python repo → conventions.md carries the detected pytest command,
    the naming section, and a non-empty `<!-- speccraft:test-command = … -->`
    marker`.
  - `@test fresh repo → conventions.md does NOT contain `scope="**/*_test.go"`,
    `fmt.Errorf`, or `slog``.
  - `@test existing conventions.md → byte-identical after seed (`cmp -s`)` — the
    preserve-existing idempotence.
  - `@test unknown stack → a `TODO` placeholder + an empty-value marker, not a Go
    default`.
- Tests fail: `seed_conventions` / `init.lib.sh` do not exist (bash/bats is NOT
  guard-gated — no override implicated, per conventions §Bash).

#### Step 9 — Implement seeding + wire init.md (GREEN) — AC5
- Add `commands/spec/init.lib.sh` with the pure `seed_conventions` helper: if
  `.speccraft/conventions.md` exists → return (preserve); else copy the neutral
  `templates/speccraft/conventions.md`, run `speccraft-state detect-stack`, fill
  the testing section + marker (`unknown` → `TODO` + empty marker). Wire
  `commands/spec/init.md` to source it via `PLUGIN_ROOT="$(speccraft-state
  plugin-root)"` and call it (spec 0030 idiom). All Step-8 tests pass.

### Phase 4 — stack-neutral prose + template (repo-structural meta-tests)

#### Step 10 — Authoring-prose recurrence guard (RED) — AC6
- Add `tools/internal/speccraft/authoring_prose_test.go` (package
  `speccraft_test`, models the repo-walk in `e2e_fixture_shape_test.go`).
  `Test_AuthoringProse_NoUnlabeledConcreteTestCommand` locates the repo root,
  reads `agents/tdd-planner.md` and `commands/spec/{plan,implement,delegate}.md`,
  extracts fenced code blocks, and flags any block containing a concrete test
  command (`go test`, `cargo test`/`cargo nextest`, `pytest`, `npm test`/`npm
  run`, `jest`, `find … -name '*_test.go'`) UNLESS the nearest non-blank line
  above matches `^\s*(#+\s*|>\s*)?example\b` (case-insensitive) OR the block
  invokes `speccraft-state test-command`. Compile-stable (stdlib + `readFile`
  only); fails on the current Go-shaped prose → observed RED, no override.

#### Step 11 — Rewrite authoring prose (GREEN) — AC6
- Rewrite `agents/tdd-planner.md` (rules 3/7 + examples), `commands/spec/plan.md`
  (line-21 `find`), `commands/spec/implement.md` and `delegate.md` (the bare `go
  test ./...`) to reference `speccraft-state test-command` / the conventions.md
  value, keeping any language name only inside a clearly-labeled `Example` block.
  `.md` files are not guard-gated. Step-10 test passes.

#### Step 12 — Shipped-template purity guard (RED) — AC7
- Add `tools/internal/speccraft/template_purity_test.go`
  `Test_ShippedTemplate_ConventionsIsStackAgnostic`: read
  `templates/speccraft/conventions.md` and fail on any of `fmt.Errorf`, `slog`,
  `^func Test`, `*_test.go`, or an `enforce:` regex bound to a language file glob
  (`scope="**/*_test.go"` / `scope="!cmd/"`). Compile-stable; fails against the
  current template → observed RED. Promotes the guardrails §Template purity rule
  to an executable check.

#### Step 13 — Strip Go idioms from the shipped template (GREEN) — AC7
- Rewrite `templates/speccraft/conventions.md` to a stack-agnostic skeleton
  (neutral naming/tests/errors sections, no language-bound `enforce:` rule, no
  `fmt.Errorf`/`slog`). Step-12 test passes.

### Phase 5 — version bump + green suite (AC8)

#### Step 14 — Version assertions → 1.8.0 (RED) — AC8
- Single-edit-per-file (memory item 4: register a fresh test id, do not two-step):
  rename+retarget `Test_StateCmd_Version_Is171`→`Test_StateCmd_Version_Is180`
  (asserts `1.8.0`) in `tools/cmd/speccraft-state/version_test.go`; the sibling
  `_Is180` retarget in `tools/cmd/speccraft-guard/version_test.go` and
  `tools/cmd/speccraft-drift/version_test.go`. Add
  `Test_Manifests_VersionIs180` (a package-`speccraft_test` grep oracle: positive
  `1.8.0` match + negative stale-`1.7.1` check over `.claude-plugin/plugin.json`
  and `marketplace.json`). All fail against the current `1.7.1`.

#### Step 15 — Bump version + final VERIFY (GREEN) — AC8
- Bump `const version = "1.8.0"` in all three `tools/cmd/*/main.go`, and
  `"version": "1.8.0"` in `.claude-plugin/plugin.json` +
  `.claude-plugin/marketplace.json`. Run the whole suite: `go test ./...` and
  `tests/hooks/*.bats` green; scope contained to the AC8 file list. (Per AC8 the
  published-verified-release half is a merge-time obligation, not a pre-close
  gate.)

### Optional refactor
- After Step 3, if the manifest→`Stack` mapping and the subcommand JSON encoder
  share literals (patterns, language ids), hoist them to package-level `var`s in
  `detect.go` so the precedence order and pattern lists live in exactly one place.
  All tests stay green.

## Delegation

- Steps 1–7 (Go detection core + subcommands) → `/speccraft:spec:implement`
  executor (reason: pure-Go, table-driven TDD in an existing package — the
  strongest match for the standard implement flow; the run()-seam REDs are the
  load-bearing sequencing this planner has pinned).
- Steps 8–9 (bash helper + init wiring) → same executor, bats tier (reason:
  pure-function shell + colocation convention, zero-credit bats coverage).
- Steps 10–13 (meta-tests + doc/template rewrites) → same executor (reason:
  RED is a mechanical Go scanner, GREEN is a bounded prose edit; keep the scanner
  and its target rewrite in one hand so the label/exception rule is honored).
- Steps 14–15 (version bump) → same executor (reason: mechanical, follows the
  §Version bumps single-edit convention).

## Risk

- **Override-free bootstrap of the brand-new `DetectStack` symbol (TOP RISK).**
  AC1 requires `DetectStack` to be table-tested DIRECTLY in Go, and the guardrails
  §TDD-invariant AC13 limitation is that a just-added test which cannot COMPILE
  until the symbol exists is a build failure, not an observed RED — which would
  otherwise force a `/speccraft:spec:override` on the symbol-introduction edit.
  Mitigation (mirrors spec 0031's zero-override run): Step 1 introduces `Stack` +
  a `DetectStack` STUB returning `Stack{Language:"unknown"}` FIRST, so the Step-2
  table test COMPILES against the stub and FAILS on behavior (stub returns
  `unknown` for every real manifest) — a genuine observed RED. Step 3's
  substantive detection GREEN is therefore unlocked by a real failing test, not a
  build error. The subcommand and meta-test REDs (Steps 4, 6, 10, 12) all drive
  the EXISTING `run()` seam or scan files with stdlib only, so they compile
  against current code and fail on behavior — no new-symbol trap there. If the
  Step-1 stub-creation edit itself is blocked by the AC13 build-failure-is-not-RED
  limitation, that SINGLE edit (and only that one) takes a one-shot
  `/speccraft:spec:override "bootstrap DetectStack stub (AC13 new-symbol
  limitation)"` recorded in `changelog.md` — every other step stays strict
  RED→GREEN. The plan is authored to make even that one edit unnecessary by
  keeping the stub body trivial and the first failing assertion behavioral.

- **RED that silently goes empty.** Splitting a RED into a second assertion-only
  edit clears `RedCandidates` (spec 0031 history). Mitigation: each RED above is a
  SINGLE edit introducing one fresh failing test id; the version-bump RED (Step
  14) renames to a fresh `_Is180` id in one edit rather than editing then
  re-asserting.

- **Go command surfacing mismatch.** `cfg.TDD.Go.Command` defaults to the bare
  `"go test"`, but AC1/AC3 require `go test ./...`. Mitigation: DetectStack
  appends the ` ./...` selector for go (Step 3), pinned by
  `Test_DetectStack_GoMod_ReturnsGo` and the `detect-stack` Go-fixture test. This
  surfaces a *suite* command (planner/docs semantics), distinct from the guard's
  bare per-test-targeted `cfg.TDD.Go.Command`.

- **AC6 false-positive on a legitimate example.** The label rule
  (`^\s*(#+\s*|>\s*)?example\b`, nearest-non-blank-line-above) must accept a real
  `Example` heading but reject prose ending in "…for example:". Mitigation: the
  Step-10 scanner encodes exactly that regex + a `speccraft-state test-command`
  escape hatch, and Step 11 rewrites every retained language mention to sit under
  a labeled `Example` block.

- **Marker grammar edge cases.** Unescaped interior quotes, duplicate markers,
  shell operators. Mitigation: the single-line `((?:\\.|[^"\\])*)` body regex +
  first-wins + verbatim-emit are each pinned by a Step-6 case before Step-7
  implements them.
