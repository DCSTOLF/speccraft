---
spec: "0037"
status: planned
strategy: tdd
---

# Plan — 0037 Workspace topology foundation

All work is Go table-test work in the existing `github.com/dcstolf/speccraft/tools`
module; every step is verifiable with `go test ./...`. Cmd-level tests drive the
`speccraft-state` subcommands **in-process** through the `run()` seam (the
`runCmd(t, repo, …)` helper in `tools/cmd/speccraft-state/main_test.go`), so a plain
`go test ./...` needs **no `./bin/` rebuild**. Rebuild the binaries to `./bin/`
(never commit them) only when smoke-testing the new subcommands from a shell or hook.

## Override budget

The complete inventory of NEW **exported** `tools/internal/speccraft` symbols this
spec adds is exactly four:

- `SpeccraftConfig.Kind` (struct field) — AC1
- `FindWorkspaceRoot(dir string) (string, error)` — AC2
- `ParseWorkspaceMembers(path string) ([]Member, error)` + `type Member{ Path string; Present bool }` — AC3
- `ReadFrontmatterField(specMd, key string) (value string, found bool, err error)` — AC4/AC6

Each one's first test references a brand-new exported symbol that **cannot compile
until the symbol exists** — a build failure, which the guard does NOT treat as a
runtime RED (spec-0018-AC13). Per the spec-0036 T1 pattern, **all four are
introduced as minimal stubs in ONE consolidated bootstrap edit (T1), costing a
single `/speccraft:spec:override`.** After T1 every later test compiles against an
existing symbol and fails at **runtime** (behavioural) — a valid RED at **zero**
extra override. Every new `speccraft-state` subcommand (`list-members`,
`get-status`, `get-frontmatter`) rides the `run()` seam: its first test hits the
`default:` "unknown subcommand" branch — a runtime RED — so subcommands add **zero**
override.

Dogfooding note (memory: stale-cached-guard): when registering the runtime REDs
against an in-repo guard, add each decisive failing test via an **Edit** that
adds/renames a test (the last touch to a sibling test file before a gated prod
edit), not a fresh **Write** — a pre-0031 cached guard on `PATH` mismodels Write's
`content`.

## Test-first sequence

### T1 — Consolidated bootstrap: four exported stubs + first REDs (OVERRIDE) — AC1,AC2,AC3,AC4,AC6
One edit, recorded via a single `/speccraft:spec:override` (build-failure ≠ runtime RED).

- Production stubs:
  - `tools/internal/speccraft/config.go`: add `Kind string` field to `SpeccraftConfig` (NO parse/default/validate yet).
  - `tools/internal/speccraft/root.go`: add `func FindWorkspaceRoot(dir string) (string, error) { return FindRoot(dir) }` (always-fallback stub).
  - `tools/internal/speccraft/workspace.go` (NEW): `type Member struct { Path string; Present bool }` and `func ParseWorkspaceMembers(path string) ([]Member, error) { return nil, nil }`.
  - `tools/internal/speccraft/frontmatter_reader.go` (NEW): `func ReadFrontmatterField(specMd, key string) (string, bool, error) { return "", false, nil }`.
- First REDs (one per symbol; each can only be observed as a build-failure pre-stub, hence the override):
  - `config_test.go` (`package speccraft_test`): `Test_ReadConfig_KindAbsent_DefaultsRepo` — asserts `ReadConfig(root).Kind == "repo"` when `speccraft.toml` has no `kind`. Fails: stub applies no default (empty string).
  - `root_test.go` (`package speccraft_test`): `Test_FindWorkspaceRoot_RepoUnderWorkspace_ReturnsWorkspace` — repo dir nested under a `kind = workspace` root resolves to the workspace. Fails: stub returns `FindRoot` (the repo, not the workspace).
  - `workspace_test.go` (NEW, `package speccraft_test`): `Test_ParseWorkspaceMembers_ListedAndMissing_PreservesPresence` — `members:`/`- path: ./api`/`- path: ./web` with only `./api` on disk ⇒ exactly `[{./api,true},{./web,false}]`. Fails: stub returns `nil`.
  - `frontmatter_reader_test.go` (NEW, `package speccraft`): `Test_ReadFrontmatterField_PresentKey_ReturnsValue` — reads `status: reviewed` from a written spec.md. Fails: stub returns `"",false,nil`.
- Tests fail: the four symbols do not exist before this edit (build failure), so this is the ONE budgeted override.

### T2 — AC1 config divergence table (RED) — AC1
- Extend `tools/internal/speccraft/config_test.go`:
  - `Test_ReadConfig_KindWorkspace_Parsed` — top-level `kind = "workspace"` ⇒ `Kind == "workspace"`.
  - `Test_ReadConfig_UnknownKind_CoercesRepo` — `kind = "bogus"` ⇒ non-strict `ReadConfig` coerces `Kind == "repo"` (a bad value can NEVER silently promote a repo to a workspace).
  - `Test_ReadConfigStrict_UnknownKind_ReturnsError` — the adjacent pair: `ReadConfigStrict` returns a validation error (wraps `ErrInvalidConfig`) naming the file/key/value for the same `kind = "bogus"`.
- Tests fail: `kind` is never parsed/defaulted/validated yet.

### T3 — AC1 kind parse + default + coerce + validate (GREEN) — AC1
- `tools/internal/speccraft/config.go`:
  - `parseSpeccraftTOML`: add a `case "":` (top-level, pre-section) reading `kind` via `parseTOMLStringValue`.
  - `applyDefaults`: `if cfg.Kind == "" { cfg.Kind = "repo" }` (empty ⇒ repo only; a bogus value is left intact here).
  - Extract `readConfigRaw(root)` = current parse+`applyDefaults` body. `ReadConfig` = `readConfigRaw` **then** coerce-unknown (`if Kind != "repo" && Kind != "workspace" { Kind = "repo" }`). `ReadConfigStrict` = `readConfigRaw` **then** `validate` — so strict validates the RAW value (unknown ⇒ error) while non-strict coerces. (This split is why validate must NOT run on the coerced value.)
  - `validate`: append a `kind` check returning `fmt.Errorf("... : %w", ErrInvalidConfig)` for a value outside `{repo, workspace}`.
- All T1(config) + T2 tests pass. Existing `config_test.go`/hook/state/guard suite still green (absent ⇒ repo).

### T4 — AC2 root-resolution table (RED) — AC2
- Extend `tools/internal/speccraft/root_test.go` with `Test_FindWorkspaceRoot_Cases` (table, one subtest per stated expected return):
  - `WorkspaceRootItself_ReturnsItself` — the workspace root resolves to itself.
  - `LoneRepo_FallsBackToFindRoot` — a `kind=repo` (or default) repo ⇒ exactly `FindRoot(dir)`.
  - `NoSpeccraft_ReturnsFindRootError` — a dir with no `.speccraft/` anywhere up-tree ⇒ the SAME error `FindRoot` returns (error-parity).
  - `NestedWorkspaces_ReturnsNearest` — workspace-in-workspace ⇒ the nearest ancestor.
  - `MalformedKindAncestor_NotTreatedAsWorkspace` — an ancestor whose `kind` is a bogus value is NOT a workspace (non-strict coercion, per AC1); resolution falls through it.
- Tests fail: stub always returns `FindRoot(dir)`.

### T5 — AC2 FindWorkspaceRoot (GREEN) — AC2
- `tools/internal/speccraft/root.go`: implement `FindWorkspaceRoot(dir)` — normalise `dir` (mirroring `FindRoot`), walk ancestors; at each ancestor containing `.speccraft/`, read `speccraft.ReadConfig(ancestor)` (non-strict, so a malformed `kind` coerces to `repo` ⇒ not a workspace) and return that ancestor when `Kind == "workspace"` (nearest wins). If no workspace ancestor is found, **`return FindRoot(dir)`** as the tail (exact value AND error on a no-`.speccraft` dir).
- All T1(root) + T4 tests pass.

### T6 — AC3 workspace.yml grammar fixture table (RED) — AC3
- Extend `tools/internal/speccraft/workspace_test.go` with `Test_ParseWorkspaceMembers_Grammar` (fixture-first table; each case writes `workspace.yml` into a temp dir, optionally creates member dirs, calls `ParseWorkspaceMembers(join(dir,"workspace.yml"))`, asserts members-or-error). Both polarities:
  - PASSING: `members:` + `  - path: ./api` + `  - path: ./web`.
  - PASSING (Design 0001's own line — REQUIRED): `  - path: ./api      # each has its own .speccraft/` ⇒ value `./api` (trailing ` # …` inline comment stripped, then trimmed).
  - PASSING: double-quoted `  - path: "./a b"` ⇒ literal `./a b` (interior space allowed only when quoted; no escape processing).
  - PASSING: blank lines and full-line `#` comments ignored.
  - PARSE ERROR: leading `/` (`  - path: /abs`) — POSIX-absolute rejection.
  - PARSE ERROR: empty value after trim (`  - path:`).
  - PARSE ERROR: bare value with interior whitespace; bare value with an unescaped `#`.
  - PARSE ERROR: any other top-level key; a `- path:` entry bearing extra keys; a duplicate `members:` key; flow style `members: [a, b]`.
- Tests fail: stub returns `nil` for everything (no errors, no members).

### T7 — AC3 ParseWorkspaceMembers (GREEN) — AC3
- `tools/internal/speccraft/workspace.go`: implement the constrained hand-rolled parser (NO YAML dependency) exactly per the spec grammar — `members:` at column 0; each entry `␣␣- path: <value>`; strip a trailing `␣#␣…` inline comment then trim; bare (no unescaped `#`, no interior whitespace) OR double-quoted literal; reject leading `/`, empty value, extra/other keys, duplicate `members:`, flow style. For each valid entry, set `Present` via `os.Stat(filepath.Join(filepath.Dir(path), value))`. Return a typed parse error (a local string-error type à la `revErr` — avoid a fresh `fmt`/`errors` import under the guard) on any out-of-subset construct. **Never drop** a syntactically valid listed member (authoritative membership).
- All T1(workspace) + T6 tests pass.

### T8 — AC3 list-members cmd + usage (RED) — AC3
- NEW `tools/cmd/speccraft-state/list_members_cmd_test.go` (`package main`) with a local `mkWorkspace(t)` helper (writes `.speccraft/speccraft.toml` `kind = "workspace"` + a `workspace.yml`):
  - `Test_StateCmd_ListMembers_EmitsPresenceLines` — one line per member on stdout as `<present|missing>\t<path>`; a `present:false` member also emits a stderr warning containing `missing member` and the path; **exit 0**.
  - `Test_StateCmd_ListMembers_EmptyMembership_ExitZero` — `members:` with zero entries ⇒ empty stdout, **exit 0**.
  - `Test_StateCmd_ListMembers_ManifestAbsent_NonZero` — `kind=workspace` root, no `workspace.yml` ⇒ non-zero, stderr contains `no workspace.yml`.
  - `Test_StateCmd_ListMembers_MalformedManifest_NonZero` — out-of-grammar manifest ⇒ non-zero, stderr contains `malformed workspace.yml`.
  - `Test_StateCmd_Usage_ListsTopologySubcommands` — bare-invocation usage lists `list-members`, `get-status`, `get-frontmatter`.
- Tests fail: `list-members` hits `default:` ("unknown subcommand") — a runtime RED, zero override.

### T9 — AC3 list-members cmd (GREEN) — AC3
- `tools/cmd/speccraft-state/main.go`: add `case "list-members":` to `run()`, delegating to a new `tools/cmd/speccraft-state/members.go` helper: resolve the workspace root via `speccraft.FindWorkspaceRoot("")`; if `root/workspace.yml` is absent ⇒ stderr `no workspace.yml`, non-zero; else `speccraft.ParseWorkspaceMembers(root/workspace.yml)` — on parse error ⇒ stderr `malformed workspace.yml`, non-zero; print `<present|missing>\t<path>` per member; for each `Present:false` print a `missing member <path>` warning to stderr; exit 0. Update `usage()`.
- All T8 tests pass. AC5 hot-path guard stays green (this is `speccraft-state`, not `hooks/` or `speccraft-guard`).

### T10 — AC4/AC6 ReadFrontmatterField behaviour (RED) — AC4,AC6
- Extend `tools/internal/speccraft/frontmatter_reader_test.go`:
  - `Test_ReadFrontmatterField_AbsentKey_FoundFalse` — key not in frontmatter ⇒ `found == false`, no error.
  - `Test_ReadFrontmatterField_MissingFile_Error` — unreadable/missing file ⇒ error.
  - `Test_ReadFrontmatterField_RoutesThroughSharedGrammar` — first-wins / column-0 / body-ignored behaviour matches `frontmatterValue` (proves it reuses the single spec-0036 grammar, no second parser).
- Tests fail: stub returns `"",false,nil` unconditionally.

### T11 — AC4/AC6 ReadFrontmatterField (GREEN) — AC4,AC6
- `tools/internal/speccraft/frontmatter_reader.go`: implement as a thin exported wrapper — `os.ReadFile(specMd)` (return the error on failure), then `v, ok := frontmatterValue(b, key)` (the existing unexported reader over the single `parseFrontmatterBlock` grammar); return `v, ok, nil`. No new parser.
- All T1(reader) + T10 tests pass.

### T12 — AC4 get-status cmd (RED) — AC4
- NEW `tools/cmd/speccraft-state/get_status_cmd_test.go` (`package main`, reuse `makeRepo`/`mkSpecDir`; create an archive spec under `specs/.archive/<ref>/spec.md` inline):
  - `Test_StateCmd_GetStatus_PrintsBareValueNewline` — live `specs/<ref>/spec.md` ⇒ stdout exactly `<value>\n`.
  - `Test_StateCmd_GetStatus_LiveWinsOverArchive` — both live and archive exist ⇒ the LIVE status is printed.
  - `Test_StateCmd_GetStatus_ArchiveFallback` — only `specs/.archive/<ref>/spec.md` exists ⇒ its status is printed.
  - `Test_StateCmd_GetStatus_NotFound_NonZero` — neither location resolves ⇒ non-zero, nothing on stdout, stderr contains `not found`.
  - `Test_StateCmd_GetStatus_NoStatusField_NonZero` — resolved file lacks `status:` ⇒ non-zero, nothing on stdout, stderr contains `no status field`.
- Tests fail: `get-status` hits `default:` (runtime RED).

### T13 — AC4 get-status cmd (GREEN) — AC4
- `tools/cmd/speccraft-state/main.go`: add `case "get-status":` → new `tools/cmd/speccraft-state/getstatus.go` helper taking a bare `<spec-ref>` (`NNNN-slug`): `speccraft.FindRoot("")`; resolve `specs/<ref>/spec.md`, else `specs/.archive/<ref>/spec.md` (**live wins**); neither ⇒ stderr `not found`, non-zero, nothing on stdout. Read via `speccraft.ReadFrontmatterField(path, "status")`; `found == false` ⇒ stderr `no status field`, non-zero; else print `value + "\n"` to stdout. Update `usage()`.
- All T12 tests pass.

### T14 — AC6 get-frontmatter (design) cmd (RED) — AC6
- NEW `tools/cmd/speccraft-state/get_frontmatter_cmd_test.go` (`package main`):
  - `Test_StateCmd_GetFrontmatter_Design_PrintsValue` — `get-frontmatter <spec.md> design` with `design: 0001-…` ⇒ stdout `<value>\n`.
  - `Test_StateCmd_GetFrontmatter_Design_AbsentPrintsEmptyLineExitZero` — key absent ⇒ prints an empty line, **exit 0** (never errors on absent value; no referent resolution).
  - `Test_StateCmd_GetFrontmatter_MissingFile_NonZero` — unreadable/missing spec.md ⇒ non-zero (the normal file error, unrelated to the key).
- Tests fail: `get-frontmatter` hits `default:` (runtime RED).

### T15 — AC6 get-frontmatter cmd (GREEN) — AC6
- `tools/cmd/speccraft-state/main.go`: add `case "get-frontmatter":` → new `tools/cmd/speccraft-state/getfrontmatter.go` helper taking a literal `<spec.md>` path + `<key>`: `speccraft.ReadFrontmatterField(path, key)` — on error (unreadable file) ⇒ stderr err, non-zero; otherwise print `value + "\n"` (an absent key yields the empty value ⇒ an empty line) and exit 0. Update `usage()`.
- All T14 tests pass.

### T16 — AC5 hot-path source guard (guard-test; green-on-arrival) — AC5
- NEW `tools/internal/speccraft/hotpath_findroot_test.go` (`package speccraft_test`), sibling to `state_single_writer_test.go`, `Test_HotPath_UsesOnlyFindRoot_Grep`: scan every `hooks/*.sh` and every non-test `tools/cmd/speccraft-guard/*.go`, and assert **none** contain the token `FindWorkspaceRoot` or the subcommand string `find-workspace-root`; positively assert the Edit/Write hot path still references `FindRoot`.
- This is a **negative-invariant guard test, green on arrival** (nothing on the hot path ever references the new resolver — `FindWorkspaceRoot` lives in `internal` and is consumed only by `speccraft-state` cmd helpers; the new subcommands live in `speccraft-state`, not `speccraft-guard`). It is a **test-only** file: it triggers no TDD production gate and needs no override, exactly like the existing single-writer grep test. It **must stay green throughout** T5/T9/T13/T15.

### T17 — Refactor: single-grammar consolidation (optional) — AC4,AC6
- Confirm `ReadFrontmatterField` delegates to `frontmatterValue`/`parseFrontmatterBlock` (no second frontmatter parser accreted), keeping `frontmatter_writer_test.go`'s `strings.Count(src,"func parseFrontmatterBlock(") == 1` assertion green. The pre-existing `specStatusIsClosed` cmd-local scan (spec 0035) is intentionally left untouched here — rerouting a shipped path is out of scope for this foundation (candidate for a later spec).
- All tests still pass.

## Delegation

- All steps are Go table-test work on existing extension points; execute directly (no aux-agent dispatch needed — nothing here matches an aux delegate's stack strength better than the primary Go implementer).
- T6 (grammar fixture table, both polarities incl. the Design-0001 line) and T16 (negative-invariant meta-test) → if a second reviewer is used, route to a critic strong at fixture-first / source-scan discipline; otherwise self-review against the spec's grammar block.

## Risk

- **Override budget blows past 1.** Mitigation: T1 lands ALL FOUR exported symbols as stubs in one override edit; every later test references an existing symbol (runtime RED) and every new subcommand rides the `run()` "unknown subcommand" seam (runtime RED) — zero further override.
- **Strict/non-strict `kind` divergence collapses** (coercion hiding the error from strict validate). Mitigation: T3 splits `readConfigRaw` so `ReadConfigStrict` validates the RAW value while only `ReadConfig` coerces unknown⇒repo; the adjacent T2 table pair pins both directions.
- **`FindWorkspaceRoot` diverges from `FindRoot` on the fallback path.** Mitigation: implement the no-workspace tail as a literal `return FindRoot(dir)`; T4 asserts exact value AND error-parity.
- **Grammar over-/under-acceptance** (inline-comment strip, quoted vs bare, absolute reject, duplicate/flow/extra-key). Mitigation: fixture-first T6 table drives both polarities and includes Design 0001's own `- path: ./api      # each has its own .speccraft/` as a passing case.
- **AC5 silently breaks** if a later edit wires `FindWorkspaceRoot`/`find-workspace-root` into a hook or the guard. Mitigation: resolver stays in `internal`, consumed only by `speccraft-state`; T16 scans `hooks/` + `speccraft-guard/` and must stay green after every cmd step.
- **Build-failure-not-RED trap** on a brand-new exported symbol. Mitigation: consolidated T1 override (documented).
- **Stale cached guard on `PATH` / Write-vs-Edit blind spot** when dogfooding in-repo. Mitigation: register each decisive RED via an **Edit** that adds/renames a test as the LAST touch to its sibling test file before the gated prod edit; build binaries only to `./bin/`, never `git add -f` them.
