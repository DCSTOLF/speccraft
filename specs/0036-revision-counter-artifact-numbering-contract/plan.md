---
spec: "0036"
status: planned
strategy: tdd
---

# Plan — 0036 revision-counter & artifact-numbering contract

## Orientation

Four coordinated pieces (spec §What A–D) land as: a reconciled-state Go core
(`ComputeRevisionState` + `listArchivedOrdinals`), one shared byte-level grammar
(`parseFrontmatterBlock`), the sanctioned writer (`setFrontmatterField` under
`SetStatus`/`SetRevision`), five new `speccraft-state` subcommands over the
spec-0035 `run()` seam (`effective-revision`, `set-status`, `set-revision`,
`reconcile-revision`, `archive-artifact`), and the self-healing shell rewrite of
`revise.lib.sh` plus two bats guards. Sequence guarantees every GREEN is preceded
by a RED, every symbol exists before it is referenced, and the build never
deadlocks on a duplicate/undefined symbol.

## Guard notes (dogfood reality — read before editing)

- **Override budget = 1 (AC12, spec-0018-AC13 trap).** The ONLY recorded
  `/speccraft:spec:override` is **T1**: a single edit adding the new EXPORTED
  symbols (`RevisionState`, `ComputeRevisionState`, `SetStatus`, `SetRevision`) as
  stubs, paired with their first RED tests. Their first test cannot COMPILE until
  the symbols exist, so the guard sees a build failure (not a runtime RED) — that
  is the one legitimate override. Every later symbol is introduced override-free:
  the unexported `parseFrontmatterBlock`/`listArchivedOrdinals` ride T1's standing
  internal runtime RED (they are added while editing `ComputeRevisionState`, whose
  `revision_test.go` siblings are already failing); `setFrontmatterField` rides
  T7's `SetStatus`/`SetRevision` runtime RED; and the archive move rides the cmd
  `run()`-seam RED (T17). Every new subcommand compiles today and fails at RUNTIME
  with "unknown subcommand" until wired — **no override**.
- **Archive move lives in the `speccraft-state` (cmd) package, not `internal`.**
  This is deliberate: it lets `moveArtifactNoReplace` + the `linkNoReplace` seam be
  introduced under the cmd `run()`-seam RED (T17) and its AC15 fault-injection unit
  test (T19) sit as a same-package sibling — override-free. (Placing it in
  `internal` would require a from-scratch internal RED that cannot compile → a
  second override. A later spec may relocate it once an internal RED anchor exists.)
- **Stale-cached-guard workarounds.** The `speccraft-guard` first on PATH may be a
  stale build with the Write blind spot. Register EVERY decisive RED via the **Edit**
  tool adding a NEW `func Test…` declaration (never a fresh Write-created test file),
  and keep that fresh test-func as the LAST sibling touch before the gated prod edit
  (a later no-new-test edit to the same test file disarms the standing RED). Use
  `Bash` only for mechanical build-fixes, never to bypass a behaviour RED→GREEN.
  Prefer implementing new symbols IN-PLACE (in the file that already carries the
  driving RED's target) to avoid duplicate-symbol build deadlocks.
- **Single atomic seam reuse.** The writer reuses the spec-0035
  `AtomicWriteFile`/`atomicRename` seam (`tools/internal/speccraft/review.go`). The
  archive move uses a genuine no-replace primitive behind NEW injectable seams
  (`var linkNoReplace = os.Link`, `var unlinkFile = os.Remove`) so AC15's
  link-ok/unlink-fail fault is unit-testable; `os.SameFile` proves inode identity.

## Test-first sequence

### T1 — Bootstrap exported core stubs (RED, under the single override) [AC1, AC12]
- Add `tools/internal/speccraft/revision.go` with STUBS only:
  - `type RevisionState struct { FrontmatterRevision, MaxArchived, Effective uint64; HasArchived bool }`
  - `func ComputeRevisionState(specDir string) (RevisionState, error)` → returns zero value, nil
  - `func SetStatus(specMd, status string) error` → returns nil
  - `func SetRevision(specMd string, n uint64) error` → returns nil
- Add `tools/internal/speccraft/revision_test.go`:
  - `Test_ComputeRevisionState_NoArchives_EffectiveEqualsFmRev` — `revision: 5`, no
    `*-r<N>.md` ⇒ `Effective==5, HasArchived==false`.
  - `Test_ComputeRevisionState_PathologicalArchive_HealsForward` — `review-r5.md`
    beside `revision: 3` ⇒ `Effective==6, MaxArchived==5` (spec AC1 exact fixture).
- Tests fail: the stub returns the zero `RevisionState`. This is the ONE override
  (the symbols cannot compile into the test until this edit lands — build-failure,
  not runtime-RED). Explicitly the spec-0018-AC13 bootstrap.

### T2 — ComputeRevisionState + shared grammar + ordinal scan (GREEN) [AC1, AC13]
- Add `tools/internal/speccraft/frontmatter.go` with unexported
  `parseFrontmatterBlock(b []byte)` returning the block bounds + per-line records
  (minimal: first `---`…next `---`, column-0 `^<key>:` scan, LF baseline).
- Add `listArchivedOrdinals(specDir string) ([]uint64, error)` (in `revision.go` or
  a sibling `archive_ordinals.go`) scanning `spec-r<N>.md`/`review-r<N>.md`/
  `plan-r<N>.md`/`tasks-r<N>.md` for numeric `<N>`.
- Implement `ComputeRevisionState` to read `revision:` via `parseFrontmatterBlock`
  and combine with `listArchivedOrdinals` per the Authority model
  (`Effective = hasArchived ? max(fmRev, maxArchived+1) : fmRev`).
- Rides T1's standing internal RED (editing `ComputeRevisionState`) — no override.
  T1 tests pass.

### T3 — Classification matrix + error surface + scan edges (RED) [AC1, AC14]
- Extend `revision_test.go` (Edit, new funcs):
  - `Test_ComputeRevisionState_MissingDir_Errors` and
    `_SpecMdUnreadable_Errors` — distinguished from a missing `revision:`.
  - `Test_ComputeRevisionState_NoFrontmatterBlock_FmRevZeroNotError` — spec.md with
    no `---` block ⇒ `FrontmatterRevision==0`, `maxArchived` still from disk.
  - `Test_ComputeRevisionState_AbsentAndNonNumericRevision_ReadAsZero`.
  - `Test_ComputeRevisionState_OverDomainLiteral_Errors` — `revision:` numeric
    literal exceeding `uint64` is an error (held distinct from malformed).
  - `Test_ListArchivedOrdinals_IgnoresNonNumericSuffix` — `review-rfoo.md` ignored.
- Symbols exist ⇒ tests compile and fail at runtime on the unhandled cases.

### T4 — Flesh state math + overflow (GREEN) [AC1, AC14]
- Harden `ComputeRevisionState`/`listArchivedOrdinals`: `os.Stat` dir/spec.md error
  distinction, graceful no-frontmatter/absent/non-numeric → 0, checked `uint64`
  parse (over-domain → error), checked `maxArchived+1`. T3 passes.

### T5 — Frontmatter grammar edge cases (RED) [AC13, AC7]
- Add `tools/internal/speccraft/frontmatter_test.go`:
  - `Test_ParseFrontmatterBlock_LeadingBOM_Preserved`.
  - `Test_ParseFrontmatterBlock_TrailingCROnDelimiterAndKey_Tolerated` (mixed EOL).
  - `Test_ParseFrontmatterBlock_Column0KeyOnly` — `# status:` comment and a body
    `status:` do NOT match; only the column-0 in-block line does.
  - `Test_ParseFrontmatterBlock_DuplicateKey_FirstWins`.
  - `Test_ParseFrontmatterBlock_EmptyBlock_And_NoClosingDelimError`.
- Compile (symbol exists from T2), fail at runtime on the edges T2 left minimal.

### T6 — Full shared grammar (GREEN) [AC13, AC7]
- Complete `parseFrontmatterBlock`: BOM handling, per-line CR tolerance, degenerate
  `---\n---`, no-closing-`---` → the AC7 "no frontmatter block" error signal. T5
  passes. This is the SOLE parser (asserted in T9).

### T7 — SetStatus/SetRevision boundary rules (RED) [AC8, AC9, AC14, §C]
- Extend `revision_test.go` (Edit, new funcs) — reference the T1 exported symbols
  (compile OK), fail at runtime:
  - `Test_SetStatus_AcceptsEnum_RejectsUnknown` (AC8).
  - `Test_SetRevision_RejectsDemotion_Monotonic` — `N` < current ⇒ non-nil error,
    file byte-unchanged (AC §C).
  - `Test_SetRevision_RejectsOverDomain` (AC14).
  - `Test_SetStatus_And_SetRevision_RefuseClosedSpec_InExportedOp` — well-formed
    `status: closed` ⇒ both refuse, file byte-unchanged (AC9 enforced IN the op).
  - `Test_SetStatus_MalformedStatus_ReadsNotClosed_StillWrites` (AC9 leniency).

### T8 — Implement writer ops + sanctioned byte writer (GREEN) [AC8, AC9, AC14, AC13]
- Add unexported `setFrontmatterField(specMd, key, value string) error` built on
  `AtomicWriteFile`, routing through `parseFrontmatterBlock` (no second parser).
- Implement `SetStatus`/`SetRevision` to enforce status-enum (AC8), `uint64` domain
  (AC14), monotonic-forward, and well-formed-`closed` refusal (AC9) BEFORE
  delegating to `setFrontmatterField`. Rides T7's RED — no override. T7 passes.

### T9 — Byte-safe writer edge cases + single-parser assertion (RED) [AC6, AC7, AC13]
- Add `tools/internal/speccraft/frontmatter_writer_test.go`:
  - `Test_SetFrontmatterField_RewritesFirstMatchOnly_LaterDupUntouched` (AC6).
  - `Test_SetFrontmatterField_PreservesPerLineTerminator_MixedEOL_RoundTrips`.
  - `Test_SetFrontmatterField_PreservesBOM_And_EOFNewline`.
  - `Test_SetFrontmatterField_NoBakSibling`.
  - `Test_SetFrontmatterField_SameValue_SkipWriteByteIdentical` (no mtime churn).
  - `Test_SetFrontmatterField_InsertsWhenAbsent_InheritsTerminator` — LF and CRLF
    fixture pair each round-trip byte-for-byte through insertion (AC7); degenerate
    `---\n---` inherits the closing-`---` terminator.
  - `Test_SetFrontmatterField_NoFrontmatterBlock_Errors`.
  - `Test_ReaderAndWriter_BothRouteThroughParseFrontmatterBlock` — static/source
    assertion that `ComputeRevisionState`, the closed-status check, and
    `setFrontmatterField` all call `parseFrontmatterBlock` (AC13; guards against a
    second parser).
- Compile (symbol exists from T8), fail at runtime on the unhandled byte edges.

### T10 — Complete byte-safe writer (GREEN) [AC6, AC7]
- Finish `setFrontmatterField`: first-match-only rewrite, per-line terminator
  retention, BOM/EOF-newline preservation, skip-write short-circuit, deterministic
  inserted-terminator, no-`.bak`. T9 passes.

### T11 — `effective-revision` subcommand (RED) [AC2]
- Add `tools/cmd/speccraft-state/effective_revision_cmd_test.go` (uses `makeRepo`/
  `mkSpecDir`/`runCmd`):
  - `Test_StateCmd_EffectiveRevision_PrintsEffectiveAloneExitZero`.
  - `Test_StateCmd_EffectiveRevision_UnreadableSpec_ExitsNonZero`.
- Drives the `run()` seam: fails at runtime "unknown subcommand".

### T12 — Wire `effective-revision` (GREEN) [AC2]
- Add the `case "effective-revision"` to `run()` in `main.go` calling
  `ComputeRevisionState` and printing `Effective`. T11 passes.

### T13 — `set-status` / `set-revision` subcommands (RED) [AC8, AC9, AC14]
- Add `set_status_cmd_test.go` + `set_revision_cmd_test.go`:
  - `Test_StateCmd_SetStatus_ValidWrites_InvalidExitsNonZero` (AC8).
  - `Test_StateCmd_SetRevision_Writes_RejectsDemotion_RejectsOverflow` (AC14/§C).
  - `Test_StateCmd_SetStatus_And_SetRevision_RefuseClosedSpec` (AC9 at CLI).
- `run()`-seam runtime RED.

### T14 — Wire `set-status` / `set-revision` (GREEN) [AC8, AC9, AC14]
- Add both `case`s taking a single `<spec.md>` (directory-vs-file asymmetry per §C),
  delegating to `SetStatus`/`SetRevision`; update `usage()`. T13 passes.

### T15 — `reconcile-revision` subcommand (RED) [AC5]
- Add `reconcile_revision_cmd_test.go`:
  - `Test_StateCmd_ReconcileRevision_HealsCounterToEffective`.
  - `Test_StateCmd_ReconcileRevision_NoOpWhenCounterLeads_SkipWrite` — file
    byte-identical, CRLF-at-target untouched, no mtime churn.
  - `Test_StateCmd_ReconcileRevision_Idempotent_TwiceEqualsOnce`.
- `run()`-seam runtime RED.

### T16 — Wire `reconcile-revision` (GREEN) [AC5]
- Add `case "reconcile-revision"` taking `<specDir>`: compute `Effective`,
  short-circuit when `fmRev == Effective` (skip-write), else `SetRevision(Effective)`
  (monotonic; never demotes). T15 passes.

### T17 — `archive-artifact` subcommand (RED) [AC3, AC4]
- Add `archive_artifact_cmd_test.go`:
  - `Test_StateCmd_ArchiveArtifact_MovesToOrdinalA_LeavesSpecMd` —
    `archive-artifact <specDir> review <A>` renames `review.md`→`review-r<A>.md`;
    `spec.md` untouched.
  - `Test_StateCmd_ArchiveArtifact_SelfHealsPastExistingReviewRN` — with
    `review-r<N>.md` at `revision: N`, `A=Effective>N` lands in a free slot (AC3).
  - `Test_StateCmd_ArchiveArtifact_RefusesClobberExistingTarget` — pre-existing
    `review-r<A>.md` ⇒ non-zero, source intact (AC4 no-clobber).
- `run()`-seam runtime RED (drives the move into the CMD package — see Guard notes).

### T18 — Wire `archive-artifact` + no-replace move seam (GREEN) [AC3, AC4]
- Add `tools/cmd/speccraft-state/archive.go` (cmd package):
  `moveArtifactNoReplace(specDir, kind string, ordinal uint64) error` using
  `var linkNoReplace = os.Link` then `var unlinkFile = os.Remove` (genuine
  no-replace: `link` fails `EEXIST` if target exists; then unlink source; fail safe
  where atomic no-replace is unavailable). Wire `case "archive-artifact"`. Rides
  T17's cmd RED — no override. T17 passes.

### T19 — Interrupted-move / no-replace fault injection (RED) [AC15, AC4]
- Extend `archive_artifact_cmd_test.go` (Edit, new funcs):
  - `Test_MoveArtifactNoReplace_LinkOkUnlinkFail_RecoversByInode` — inject
    `linkNoReplace` success + `unlinkFile` failure; the re-run, BEFORE allocating a
    new ordinal, finds the same-inode sibling via `os.SameFile` and completes the
    move by unlinking the source ⇒ exactly one archived copy, no duplicate ordinal.
  - `Test_MoveArtifactNoReplace_RefusesExistingTarget_ViaLinkEEXIST` — source intact.
  - `Test_MoveArtifactNoReplace_FailsSafeWhenNoInodeIdentity` — no same-inode
    sibling and identity unprovable ⇒ does NOT delete the source.
- Symbols exist ⇒ compile, fail at runtime.

### T20 — Inode-identity recovery (GREEN) [AC15]
- Implement the pre-ordinal same-kind sibling scan (`review-r*.md` for `review.md`,
  etc.), `os.SameFile` completion-by-unlink, EEXIST refusal, and fail-safe. Never
  byte-equality. T19 passes.

### T21 — Version-bump oracles 1.10.0→1.11.0 (RED) [AC11]
- Rename/retarget sibling version tests to assert `1.11.0`:
  - `tools/cmd/speccraft-state/version_test.go` →
    `Test_StateCmd_Version_Is1110` expecting `"1.11.0"`.
  - `tools/cmd/speccraft-guard/version_test.go` →
    `Test_GuardCmd_Version_Const1110`.
  - `tools/cmd/speccraft-drift/version_test.go` →
    `Test_DriftCmd_Version_Const1110`.
  - `tools/internal/speccraft/manifest_version_test.go` →
    `Test_Manifests_VersionIs1110` (want `"version": "1.11.0"`, stale `"1.10.0"`).
- Fail: consts/manifests still `1.10.0`.

### T22 — Perform the bump (GREEN) [AC11]
- Set `const version = "1.11.0"` in the three `main.go` files; set `"version":
  "1.11.0"` in `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`.
  T21 passes. **DoD (conventions.md): a published, verified `v1.11.0` release**
  (merge → auto-tag → `release.yml` → `verify-release.sh`), not merely edited files.

### T23 — Revise self-heal + call-order regression (RED, bats) [AC4, AC5, §B]
- Add `tests/hooks/spec-revise-selfheal.bats` (sources `revise.lib.sh`; PATH has the
  freshly built `bin/` binaries):
  - `@test "revise no longer deadlocks on a pre-existing review-rN.md"` — spec at
    `revision: N`, source `reviewed`, live `review.md`, pre-existing `review-r<N>.md`
    ⇒ archive succeeds, `review.md`→free `review-r<A>.md` (A>N), `spec.md` stays live,
    counter healed forward — NOT the old hard refusal.
  - `@test "fresh archive counter → Effective (fresh 6 / retry 6, never 7)"` (AC5).
  - `@test "bump_revision is a thin two-call helper (set-revision + set-status, no
    sed -i.bak, no .bak sibling)"`.
  - `@test "archive → counter → status:draft is the fixed order (status flip last)"`.
- Fails: `preflight_archive_collisions` still refuses; `bump_revision` still uses
  `sed -i.bak`; `archive_rename` lacks the self-healing `A=Effective` selection.

### T24 — Rewrite revise.lib.sh self-healing (GREEN) [AC4, AC5, §B]
- In `commands/spec/revise.lib.sh`: **delete** `preflight_archive_collisions`
  (revise.lib.sh:147); make `bump_revision` a thin helper calling
  `speccraft-state set-revision` + `set-status` (no raw `sed`/`.bak`); make
  `archive_rename` compute `A=$(speccraft-state effective-revision "$dir")` before
  the moves, call `speccraft-state archive-artifact` per present disposable kind,
  then `speccraft-state reconcile-revision` for the counter, then flip `status`
  LAST. Remove the seven `preflight_archive_collisions` `@test`s from
  `tests/hooks/spec-revise-preflight.bats`. T23 passes; existing preflight suite
  stays green.

### T25 — Meta-guard + close call-site (RED, bats) [AC10, AC9]
- Add `tests/hooks/frontmatter-writer-guard.bats` — **fixture-first** (spec-0030
  grep-oracle spirit): a curated fixture dir of FORBIDDEN forms (`sed -i` /
  `perl -i` / `perl -pi -e` on a `specs/*/spec.md` target with a `status:`/`revision:`
  LHS — anchored and unanchored; `awk … > specs/x/spec.md`; a variable target
  `sed -i "$SPEC_MD"` scoped-IN) and PERMITTED forms (`sed -n '/^status:/p'`,
  `grep -E '^status:'`, printing status to stderr, redirection unrelated to those
  fields). Asserts the scanner FLAGS every forbidden fixture, PASSES every permitted
  one, AND that the LIVE `commands/**/*.{lib.sh,md}` tree is clean.
  - `@test "close.md invokes speccraft-state set-status … closed at the call site"`
    (AC9 close-transition verifiable at the call site).
- Fails: scanner not yet written; `close.md` still says "Edit spec.md frontmatter".

### T26 — Implement meta-guard scanner + close call-site (GREEN) [AC10, AC9]
- Implement the scan helper with the per-tool regime: `sed -i`/`perl -i`/`perl -pi -e`
  target = last positional (non-flag) arg; `awk` target = output-redirection target;
  literal target matched against `specs/*/spec.md`; variable/command-substituted
  target conservatively scoped IN. Update `commands/spec/close.md` step 6 to run
  `speccraft-state set-status "$SPEC_MD" closed` instead of a hand edit. T25 passes.

### T27 — Refactor (optional) [—]
- Collapse any duplicated line/terminator helpers shared by reader and writer into
  `parseFrontmatterBlock`; co-locate the `linkNoReplace`/`unlinkFile` seams and the
  same-kind-sibling glob with one comment block; ensure `ensure_revision_field`'s
  awk-to-tmp insertion (not a flagged in-place form) is noted as intentionally out
  of AC10's enumerated set. All tests still pass.

## Delegation

- **T19–T20 (AC15 link/inode recovery)** → delegate to a careful Go implementer
  (reason: the `link(2)`-EEXIST + `os.SameFile` fail-safe path is the most delicate
  code in the spec; per the review's residual note, pin the link-ok/unlink-fail
  fault first behind the smallest seam).
- **T25–T26 (AC10 meta-guard)** → delegate to a bats/shell-focused implementer
  (reason: fixture-first curation of the per-tool matching regime — the spec-0032
  `default:` false-positive class is the trap to avoid).
- The Go core (T1–T16) and version bump (T21–T22) are straightforward for the
  primary implementer.

## Risk

- **Override budget breach (>1)** → mitigation: only T1 introduces from-scratch
  symbols; every later Go symbol rides an existing runtime RED (internal
  `ComputeRevisionState`/`SetStatus` REDs or the cmd `run()`-seam RED). If a build
  deadlock threatens, implement the symbol in-place in the file that already carries
  the driving RED's target — do NOT open a second override.
- **Stale cached guard blocks a legitimate GREEN** → mitigation: register each RED
  via Edit adding a new `func Test…`, keep it the LAST sibling test touch before the
  gated prod edit; use Bash only for mechanical build-fixes.
- **`link(2)` no-replace unavailable on some FS/platform** → mitigation: fail safe
  with an error rather than risk overwrite (never fall back to stat-then-rename);
  pinned by `Test_MoveArtifactNoReplace_FailsSafeWhenNoInodeIdentity`.
- **Meta-guard false-positive/no-op** → mitigation: fixture-first with BOTH forbidden
  and permitted forms; assert flags-and-passes before trusting the live-repo scan.
- **Version bump edited but not released** → mitigation: DoD is the published,
  verified `v1.11.0` release chain (auto-tag → release.yml → verify-release.sh), not
  the manifest edit.
- **revise.lib.sh sourced into zsh** → mitigation: no zsh-reserved parameter names in
  new code (`spec_status`, not `status`); `lib-zsh-safety.bats` remains the backstop.
