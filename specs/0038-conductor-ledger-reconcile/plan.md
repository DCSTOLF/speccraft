---
spec: "0038"
status: planned
strategy: tdd
---

# Plan — 0038 Conductor primitives: ledger.md + reconcile rollup

All new internal logic lands in one new file `tools/internal/speccraft/ledger.go`
(package `speccraft`); its sibling `*_test.go` files sit in the same directory. All
new cmd surface lands in `tools/cmd/speccraft-state/` (package `main`) and rides the
compile-stable `run()` seam. `go test ./...` verifies every step.

Whitebox note: any internal test that overrides the unexported `ledgerNow` clock seam
must be declared `package speccraft` (not `speccraft_test`). For uniformity the three
new internal ledger test files are all `package speccraft`; source-scan meta-tests read
files from disk so their package is immaterial.

## Test-first sequence

### Step 1 — Bootstrap the complete exported-symbol inventory as stubs (T1) — the ONE OVERRIDE
- Add `tools/internal/speccraft/ledger.go` (package `speccraft`) with minimal COMPILING stubs:
  - Types `Ledger{Designs []LedgerDesign}`, `LedgerDesign{ID string; Members []LedgerMember}`,
    `LedgerMember{Path, Spec, LastCompletedPhase, InFlight, Blocked, Updated string}`,
    `Rollup{DesignID string; Members []MemberStatus; Total, Closed, Blocked, InProgress int; Done bool}`,
    `MemberStatus{Member, Spec, Class, Status string}`.
  - `func ParseLedger(path string) (Ledger, error) { return Ledger{}, nil }`
  - `func SetLedgerField(path, designID, memberPath, field, value string) error { return nil }`
  - `func Reconcile(ws Ledger, designID string, resolve func(memberRoot, specRef string) (string, bool)) Rollup { return Rollup{} }`
  - `var ledgerNow = time.Now` (unexported clock seam; only `time` imported/used).
- This edit is a brand-new-EXPORTED-symbol introduction: the first test referencing any of
  these cannot compile until the symbol exists → a BUILD failure, which the guard cannot
  observe as a runtime RED (spec-0018-AC13). It is therefore the SINGLE
  `/speccraft:spec:override` for this spec.
- **Why exactly one:** the stub file declares the COMPLETE inventory of new *exported*
  `internal/speccraft` symbols in a single edit, so every later internal test compiles and
  fails at RUNTIME against a stub (a clean RED), and every later production edit only *fills
  in* an already-declared symbol. No subsequent step introduces a new exported internal
  symbol — `resolveSpecStatus`, `reconcileCmd`, `ledgerSetCmd` are all `package main` and ride
  the `run()` seam (unknown-subcommand = runtime RED), costing zero override.

### Step 2 — ParseLedger grammar (RED)
- Add `tools/internal/speccraft/ledger_parse_test.go` (package `speccraft`):
  - `Test_ParseLedger_MultiDesignMultiMember_OrderPreserved` — multi-design/multi-member
    fixture into ordered structs; unset fields `""`; ignores a leading `# Ledger` preamble +
    blank lines; tolerates a trailing `\r` and a leading BOM; an interior-`: ` value
    (`in_flight: {phase: plan}`) and a spaceless `spec:0007-x` both parse. (AC1)
  - `Test_ParseLedger_MissingFile_EmptyLedgerNilError` — missing file ⇒ empty `Ledger`, nil error. (AC1)
  - `Test_ParseLedger_FirstWinsOnDuplicateKey` — duplicate key inside a block: first value wins. (AC1)
  - `Test_ParseLedger_Errors_Table` — one row per parse-error class, each asserting a
    `ledger.md: ` prefix on the message: `###` before any `## design`; unknown `<key>:`;
    a `<key>:` before the first `### member`; a junk line in a block; a duplicate
    `## design <id>`; a duplicate `### <member>`; an empty design id; an empty member path;
    a non-`design` `##` heading (`## foo`); non-blank content before the first `## design`;
    a bare junk line between a `## design` heading and its first `### member`. (AC1)
- Tests fail: the T1 stub returns `Ledger{}, nil` — happy-path field assertions mismatch and
  every error row gets a nil error. Compiles against T1 → runtime RED.

### Step 3 — ParseLedger grammar (GREEN)
- Implement the real grammar in `ledger.go`: per-line read after trimming a trailing `\r`
  and a leading UTF-8 BOM (mirroring `parseFrontmatterBlock`); column-0 `## design <id>` /
  `### <member-path>` openers; first-`:` split with one optional leading-space strip;
  fixed key set `{spec,last_completed_phase,in_flight,blocked,updated}`; first-wins; every
  error carries a `ledger.md: <class>` message (a local `ledgerErr string` type or
  `fmt.Errorf` — add the import in this same edit alongside its first use, never as a
  standalone import edit).
- All Step-2 tests pass.

### Step 4 — SetLedgerField + canonical writer (RED)
- Add `tools/internal/speccraft/ledger_set_test.go` (package `speccraft` — it overrides
  `ledgerNow` and restores it with `t.Cleanup`):
  - `Test_SetLedgerField_CreatesAndRoundTrips` — creates file/design/member, sets exactly
    `field`, stamps `updated` via the pinned `ledgerNow`; other fields/members/designs
    survive parse→set→parse, including an interior-`: ` value. (AC2)
  - `Test_SetLedgerField_CanonicalLayout_Golden` — pins the exact serialization of a fresh
    single-member write: `# Ledger\n\n`, `## design <id>\n\n`, `### <path>\n`, the five
    fields in fixed order `spec,last_completed_phase,in_flight,blocked,updated`
    (`<key>: <value>` or bare `<key>:` when empty), one trailing blank line, single final `\n`. (AC2)
  - `Test_SetLedgerField_ByteStable_ParseWriteParseWrite` — parse→write→parse→write is byte-identical. (AC2)
  - `Test_SetLedgerField_ResetSameValue_ByteIdenticalNoop` — re-setting a field to its current
    value is a byte-identical no-op with `updated` unchanged. (AC2)
  - `Test_SetLedgerField_InvalidField_LeavesFileUnchanged` — a `field` outside the settable set
    `{spec,last_completed_phase,in_flight,blocked}`, INCLUDING `updated`, returns an error and
    leaves the file unchanged (or uncreated if absent), asserted by bytes/existence. (AC2)
- Tests fail: the T1 stub returns nil and writes nothing → no file / wrong bytes / no error on
  invalid field. Runtime RED.

### Step 5 — SetLedgerField + canonical writer (GREEN)
- Implement `SetLedgerField` in `ledger.go` plus an unexported deterministic serializer
  (e.g. `serializeLedger`): idempotent upsert, validate `field` against the settable set
  (reject `updated` and unknown, writing nothing), stamp `updated` via `ledgerNow`, no-op when
  the field already equals `value`, and persist through the shared **`AtomicWriteFile`** seam
  (in-package; no new import). The writer emits its own canonical `# Ledger` header (a
  pre-existing preamble is not preserved — machine-owned file).
- All Step-4 tests pass.

### Step 6 — Ledger is not state.json (AC3) — meta + behavioral (no production edit)
- Add `tools/internal/speccraft/ledger_not_statejson_test.go`:
  - `Test_SetLedgerField_WritesOnlyLedgerMd_NeverStateJson` — call `SetLedgerField` against a
    temp ledger path and assert only that path is written and no `state.json` is created. (AC3)
  - `Test_LedgerWritePath_NeverReferencesStateJson` — source-scan sibling to
    `state_single_writer_test.go`: assert no ledger write path in `ledger.go` references
    `state.json`. (AC3)
- Both pass against the Step-5 implementation. Test-only step (no production edit) → no guard gate.

### Step 7 — Reconcile aggregation + classification/precedence (RED)
- Add `tools/internal/speccraft/reconcile_test.go` (package `speccraft`):
  - `Test_Reconcile_KeysOnResolver_NotLastCompletedPhase` — with a fake resolver whose returned
    status disagrees with the member's `last_completed_phase`, the Rollup reports the RESOLVER's
    value. (AC4)
  - `Test_Reconcile_Classification_Table` — table over: Blocked when ledger `blocked` non-empty
    OR resolver `found==false`; a non-empty `blocked` overlay WINS over a resolved-`closed`;
    non-Blocked → Closed when status is `closed`/`archived`, else InProgress;
    `MemberStatus.Status` carries the resolved status (`""` when unresolved); mutual exclusivity
    Blocked→Closed→InProgress; `Done==true` iff every member classifies Closed. (AC5)
  - `Test_Reconcile_OrderPreserved_Counts` — ordered `MemberStatus` and correct
    `Total/Closed/Blocked/InProgress`. (AC5)
  - `Test_Reconcile_EmptyDesign_DoneTrue` — zero members ⇒ `Done`, never errors on a member. (AC5)
- Tests fail: the T1 stub returns a zero `Rollup{}`. Runtime RED.

### Step 8 — Reconcile aggregation (GREEN) + no-pointer source scan (AC4)
- Implement `Reconcile` in `ledger.go`: pure aggregation over `ws`'s matching `designID`,
  calling the injected `resolve` per member, reading ONLY the member's `Blocked` overlay from
  the ledger (never `LastCompletedPhase`), classifying Blocked→Closed→InProgress and rolling up
  counts + `Done`.
- Add the belt-and-suspenders meta-test (same or new sibling file):
  - `Test_ReconcileImpl_NoLastCompletedPhaseReference` — source-scan the body of `Reconcile`
    (anchor on `func Reconcile(` and scan within) and assert it contains no
    `LastCompletedPhase` / `last_completed_phase` reference. (AC4)
- All Step-7 tests + the scan pass. The production edit is gated by the Step-7 failing sibling
  REDs in the same directory.

### Step 9 — Cmd REDs: reconcile + ledger-set (RED) — authored FIRST, kept STANDING
- Add `tools/cmd/speccraft-state/ledger_set_cmd_test.go` (package `main`; reuse the spec-0037
  `mkWorkspace` helper + write a `ledger.md`):
  - `Test_StateCmd_LedgerSet_UpsertsLedgerMd_ExitZero` — `ledger-set <design> <member> <field> <value>`
    resolves the workspace root, upserts `<root>/.speccraft/ledger.md`, exit 0. (AC6)
  - `Test_StateCmd_LedgerSet_InvalidField_NonZero_NothingWritten` — an invalid `field`
    (including `updated`) ⇒ non-zero + stderr, nothing written. (AC6)
- Add `tools/cmd/speccraft-state/reconcile_cmd_test.go` (package `main`; workspace fixture +
  member spec dirs with `spec.md` frontmatter):
  - `Test_StateCmd_Reconcile_PrintsDoneAndMemberLines` — prints `done: true|false`, then in
    ledger order one `<status>\t<member>\t<spec-ref>` line per member, `<status>` =
    `MemberStatus.Status` or the literal `blocked`; exit 0. (AC6)
  - `Test_StateCmd_Reconcile_BlockedMemberPrintsLiteralBlocked` — a `blocked`-overlay or
    unresolved member prints the literal `blocked`. (AC6)
  - `Test_StateCmd_Reconcile_EmptyOrAbsentDesign_DoneTrue_NoLines` — empty/absent design ⇒
    `done: true`, zero member lines. (AC6)
  - `Test_StateCmd_Reconcile_MalformedLedger_NonZero_NothingOnStdout` — a malformed ledger ⇒
    non-zero + the `ledger.md: `-prefixed ParseLedger error on stderr, nothing on stdout. (AC6)
- Tests fail: `reconcile` / `ledger-set` are unknown subcommands → `run()` default returns 1
  → runtime RED (zero override, the `run()`-seam pattern).

### Step 10 — Extract resolveSpecStatus, refactor get-status, implement subcommands (GREEN) — RIDES the Step-9 REDs
- **Sequencing obligation (guard):** land this edit while the Step-9 cmd REDs are STILL FAILING.
  The `get-status` refactor is a pure refactor with no RED of its own; the guard authorizes the
  whole `package main` (single-directory) edit from the standing failing reconcile/ledger-set
  siblings. Do NOT green Step-9 first. Zero override.
- `tools/cmd/speccraft-state/topology_cmds.go`: extract
  `resolveSpecStatus(root, ref string) (status string, outcome resolveOutcome)` from `getStatus`,
  distinguishing `resolved` / `notFound` / `noStatus` (dual `specs/<ref>` → `specs/.archive/<ref>`
  via `ReadFrontmatterField`, live wins). Refactor `getStatus` to switch on `outcome` so its
  `not found` and `no status field` messages are byte-for-byte preserved.
- Add `tools/cmd/speccraft-state/ledger_cmds.go`:
  - `reconcileCmd(designID string, stdout, stderr)` — resolve the workspace root with
    `FindWorkspaceRoot("")`, `ParseLedger(<root>/.speccraft/ledger.md)` (a `ledger.md:`-prefixed
    parse error ⇒ non-zero + stderr, nothing on stdout), build the resolver closure
    `func(memberRoot, specRef string) (string, bool)` that calls
    `resolveSpecStatus(filepath.Join(root, member.Path), member.Spec)` mapping BOTH `notFound`
    and `noStatus` (and any read error) to `found==false`, call `Reconcile`, print `done:` +
    `<status>\t<member>\t<spec-ref>` lines in ledger order.
  - `ledgerSetCmd(designID, memberPath, field, value string, stdout, stderr)` — resolve the root,
    `SetLedgerField(<root>/.speccraft/ledger.md, …)`, surface an invalid-field error non-zero.
- `tools/cmd/speccraft-state/main.go`: add `case "reconcile"` and `case "ledger-set"` to `run()`
  (with arg-count usage guards) and matching `usage()` lines.
- All Step-9 tests pass.

### Step 11 — get-status regression + resolveSpecStatus unit pin (verification)
- The existing `tools/cmd/speccraft-state/get_status_cmd_test.go` table
  (`Test_StateCmd_GetStatus_PrintsBareValueNewline`, `_LiveWinsOverArchive`, `_ArchiveFallback`,
  `_NotFound_NonZero`, `_NoStatusField_NonZero`) is the 0037 regression oracle: assert it stays
  green after the Step-10 extraction. (AC6)
- Optionally add `Test_ResolveSpecStatus_TriState_ResolvedNotFoundNoStatus` in the cmd package to
  pin the extracted helper's three outcomes directly (passes immediately; test-only).
- No production edit; `go test ./...` green is the gate.

## Override budget
- **Total `/speccraft:spec:override` = 1**, spent entirely on **Step 1**.
- Justification: only Step 1 introduces brand-new *exported* `internal/speccraft` symbols
  (`Ledger`/`LedgerDesign`/`LedgerMember`/`Rollup`/`MemberStatus`, `ParseLedger`,
  `SetLedgerField`, `Reconcile`) whose first reference cannot compile pre-existence. Bundling the
  COMPLETE inventory into one stub file makes Steps 3/5/8 fill-in edits gated by runtime REDs, and
  keeps every cmd-side symbol (`resolveSpecStatus`, `reconcileCmd`, `ledgerSetCmd`) in `package
  main` behind the `run()` seam — zero further overrides.

## Delegation
- All steps → in-house `/speccraft:spec:implement` (Go table-tests + tight interaction with the
  TDD guard's override budget and the run()-seam sequencing). No aux-agent delegation: the value is
  in the guard/sequencing discipline, which the aux-delegator's stateless CLIs cannot honor.
- Step 1 additionally requires `/speccraft:spec:override` (the single sanctioned bootstrap).

## Risk
- **get-status refactor guard-block (highest).** If Step-9's reconcile/ledger-set REDs are greened
  before the Step-10 edit lands, the pure `get-status`/`resolveSpecStatus` refactor has no failing
  sibling in `package main` and the guard blocks it → tempting a second override. Mitigation:
  author Step 9 and confirm both cmd REDs FAIL (unknown subcommand) immediately before the Step-10
  edit; implement `resolveSpecStatus` + both subcommands + the get-status refactor in the SAME
  edit-batch while the REDs stand; only then run `go test`.
- **Per-file red-candidate disarm (spec 0031/0032).** `SetRedCandidates` replaces the captured set
  per file, so a no-new-test touch to a RED's sibling file just before a gated prod edit disarms it.
  Mitigation: each RED step adds NEW test functions in a NEW file as the last test-file touch before
  its GREEN; never follow a RED with an assertion-only/import-only edit to that same file pre-GREEN.
- **Import-then-use deadlock (spec 0036).** Adding a bare `import` to `ledger.go` while it carries a
  standing RED is a build-failing edit the guard misreads. Mitigation: add every import in the same
  GREEN edit as its first use; prefer a local `type ledgerErr string` over pulling `fmt`/`errors`
  solely for the `ledger.md:`-prefixed messages if a standalone import edit would otherwise be needed.
- **ledgerNow whitebox reach.** Overriding the unexported clock requires `package speccraft` (not
  `speccraft_test`). Mitigation: declare the internal ledger test files `package speccraft`.
- **Golden/byte-stability brittleness.** The canonical layout and no-op invariants are byte-exact.
  Mitigation: the serializer emits only `\n` terminators and a single trailing `\n`; the golden test
  pins the literal string, and byte-stable/no-op tests compare raw bytes.
- **./bin rebuild.** Not required by any AC — all cmd ACs are exercised in-process via `runCmd`
  (`run(args, &stdout, &stderr)`). Rebuild `./bin/speccraft-state` only for an optional manual shell
  smoke-test; never commit it.
