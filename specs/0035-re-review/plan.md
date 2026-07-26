---
spec: "0035"
status: planned
strategy: tdd
---

# Plan — 0035 re-review

Test-first sequence for the diff-focused re-review path. Every GREEN is preceded
by a RED that fails at RUNTIME, except the single P0 bootstrap
(`/speccraft:spec:override`) that introduces the first brand-new exported symbols
in package `speccraft` (spec-0018-AC13 build-failure-is-not-RED limitation).

## Layer map (who owns what)

- **`tools/internal/speccraft` (Go)** — `AtomicWriteFile`, `WriteReviewSnapshot`
  + fingerprint (AC1), `ReviewDiff` envelope + `changed_sections` determinism
  (AC3/AC4/AC5/AC6/AC11-seam), `WriteReviewFile` atomic commit (AC2). Pure
  mechanics; returns errors, never prints.
- **`tools/cmd/speccraft-state` `run()` seam** — `review-snapshot write` and
  `review-diff [--promote]` subcommands (AC1/AC3/AC4/AC6). Driven in tests via
  the compile-stable `run()` seam (the `detect_cmd_test.go` technique) so every
  cmd RED is a runtime "unknown subcommand", never a build error.
- **`tools/internal/speccraft/drift`** — AC10 scope regression (calls
  `LoadRules`+`CheckAll`, the exact functions `speccraft-drift` invokes).
- **`templates/prompts/re-review.md`** — AC7 prompt template (grep oracle).
- **`commands/spec/review.lib.sh` + `review.md`** — AC7(b)/AC8/AC9 provenance
  gate + payload construction (UX layer, pure-shell helpers per the spec-0015
  `.lib.sh` colocation convention), plus the AC11 command-layer bash oracle.
- **version consts + JSON manifests** — AC12/AC13.

## The atomic-write seam (reused by AC1 + AC2)

The temp+rename pattern in `state.go:113-117` (`saveStateLocked`) is extracted to
an exported `speccraft.AtomicWriteFile(path string, data []byte, perm os.FileMode)
error` (same-directory temp + rename). `saveStateLocked` is refactored to call it
(REFACTOR, T3). Both the AC1 snapshot write and the AC2 review.md commit reuse it,
and both expose an injectable temp-write/rename seam so the fault-injection REDs
(rename failure → prior file byte-unchanged; mid-write → no fingerprint-free
artifact ever observed) and the AC11 read-before-write call-order oracle are
deterministic.

## Test-first sequence

### Phase 0 — bootstrap (the ONE override)

| Step | Kind | File / symbols | Detail |
|---|---|---|---|
| T1 | BOOTSTRAP (override) | `tools/internal/speccraft/review.go` + `tools/internal/speccraft/review_test.go` :: `Test_Review_Bootstrap_SymbolsExist` | First test references the brand-new exported symbols `AtomicWriteFile`, `ReviewEnvelope`/`ChangedSection`, `ReviewDiff`, `WriteReviewSnapshot`, `WriteReviewFile`; cannot compile until they exist → build failure, NOT a runtime RED → requires one `/speccraft:spec:override`. GREEN = minimal stubs returning zero values. This is the single recorded override (2026-07-26). Every later RED references these now-existing stubs and fails at RUNTIME on behaviour. |

### Phase 1 — snapshot + envelope core (AC1, AC3, AC4, AC6, AC11-Go-seam)

| Step | Kind | File / test funcs | Detail |
|---|---|---|---|
| T2 | RED | `tools/internal/speccraft/atomicwrite_test.go` :: `Test_AtomicWriteFile_WritesBytesAndPerm`, `Test_AtomicWriteFile_TempIsSameDir_RenameReplaces`, `Test_AtomicWriteFile_RenameFailure_LeavesPriorByteIdentical` | Stub returns nil without writing → file absent / prior unchanged assertions fail at runtime. |
| T3 | GREEN + REFACTOR | `tools/internal/speccraft/atomicwrite.go` | Implement `AtomicWriteFile` (same-dir `*.tmp` + `os.Rename`, injectable rename seam). Refactor `saveStateLocked` (state.go:113-117) to call it — all existing state tests still pass. |
| T4 | RED | `tools/internal/speccraft/review_snapshot_test.go` :: `Test_WriteReviewSnapshot_EqualsSpecBytes`, `Test_Fingerprint_IsSha256OfRawBytes_NoNormalization`, `Test_WriteReviewSnapshot_RobustNoop_NoRewriteNoMtimeTouch`, `Test_WriteReviewSnapshot_MissingSpec_Errors` | AC1: snapshot == spec.md bytes; fingerprint = sha256 of raw file bytes (no CRLF/LF/BOM/trailing-newline normalization); byte-identical on-disk snapshot → true no-op (mtime unchanged); no readable spec.md → error. Stub fails all. |
| T5 | GREEN | `tools/internal/speccraft/review_snapshot.go` | Implement `WriteReviewSnapshot` (read spec.md → sha256 → no-op guard via byte-compare → `AtomicWriteFile`). |
| T6 | RED | `tools/cmd/speccraft-state/review_snapshot_cmd_test.go` :: `Test_StateCmd_ReviewSnapshotWrite_WritesAndPrintsFingerprint`, `Test_StateCmd_ReviewSnapshotWrite_MissingSpec_ExitsNonZero`, `Test_StateCmd_Usage_ListsReviewSnapshot` | Drives `run([]string{"review-snapshot","write",dir})` — compiles today, fails at runtime with "unknown subcommand". |
| T7 | GREEN | `tools/cmd/speccraft-state/main.go` | Wire `review-snapshot write` case → `WriteReviewSnapshot`; add to usage. |
| T8 | RED | `tools/internal/speccraft/review_diff_test.go` :: `Test_ReviewDiff_Identical_SnapshotTrue_ChangedFalse_BaseEqualsFingerprint` (AC4), `Test_ReviewDiff_NoPriorSnapshot_SnapshotFalse_BaseNull` (AC6), `Test_ReviewDiff_Fingerprint_IsCurrentBytes_NotOldSnapshot` (AC3) | Stub `ReviewEnvelope{}` zero values fail the shape assertions at runtime. |
| T9 | GREEN | `tools/internal/speccraft/review_diff.go` | Implement `ReviewDiff` envelope skeleton: `schema:1`, snapshot/changed bools, `fingerprint`=sha256(current bytes), `base_fingerprint`=sha256(old snapshot) or null; identical → empty diff/sections; changed_sections deferred to P3 (returns empty for the identical/no-snapshot cases these tests cover). |
| T10 | RED | `tools/internal/speccraft/review_diff_promote_test.go` :: `Test_ReviewDiff_Promote_ReadsOldSnapshotBeforeWritingNew_SeamOrder`, `Test_ReviewDiff_Promote_WritesDiffedByteImageOnce` (AC11 Go seam) | Injected reader/writer double captures call order; stub does no I/O → order assertion fails at runtime. |
| T11 | GREEN | `tools/internal/speccraft/review_diff.go` | `--promote` path: after computing envelope, write the SAME in-memory spec bytes as the new snapshot via `AtomicWriteFile`; old snapshot read+fingerprinted before overwrite. |
| T12 | RED | `tools/cmd/speccraft-state/review_diff_cmd_test.go` :: `Test_StateCmd_ReviewDiff_EmitsSchema1Envelope`, `Test_StateCmd_ReviewDiff_ReadOnly_ClosedSpec_Exit0`, `Test_StateCmd_ReviewDiff_ReadOnly_NoSnapshot_Exit0`, `Test_StateCmd_ReviewDiff_UnreadableSpec_ExitsNonZero`, `Test_StateCmd_ReviewDiff_UnreadableSnapshot_ExitsNonZero`, `Test_StateCmd_ReviewDiff_PromoteClosedSpec_Refused_WritesNothing` (AC3) | Local `reviewEnvelope` struct unmarshalled from stdout (compiles today, `detect_cmd` technique); runtime "unknown subcommand" until wired. |
| T13 | GREEN | `tools/cmd/speccraft-state/main.go` | Wire `review-diff <dir> [--promote]` case + exit-code matrix + closed-spec `--promote` refusal; add to usage. |

### Phase 2 — provenance atomic commit (AC2)

| Step | Kind | File / test funcs | Detail |
|---|---|---|---|
| T14 | RED | `tools/internal/speccraft/review_commit_test.go` :: `Test_WriteReviewFile_SingleReviewedSha256Line`, `Test_WriteReviewFile_Sha256OverSnapshotReproducesRecorded`, `Test_WriteReviewFile_RenameFailure_PriorReviewByteIdentical`, `Test_WriteReviewFile_MidWrite_NoFingerprintFreeArtifactObserved` | AC2 single atomic commit: complete review.md (incl one `^reviewed_sha256: <64hex>$` line) built in temp then renamed. Fault injection via the AtomicWriteFile rename/temp seam: force rename error → prior review.md `cmp`-identical + its reviewed_sha256 unchanged; observe the target path throughout a mid-write → never a fingerprint-free review.md. Stub fails all. |
| T15 | GREEN | `tools/internal/speccraft/review_commit.go` | Implement `WriteReviewFile` via `AtomicWriteFile` (same-dir temp, no intermediate write); reviewed_sha256 line composed BEFORE rename. |

### Phase 3 — anchor-scheme determinism (AC5)

| Step | Kind | File / test funcs | Detail |
|---|---|---|---|
| T16 | RED | `tools/internal/speccraft/review_diff_sections_test.go` :: table-driven `Test_ChangedSections` cases — `UniqueHeadingModify`, `FrontmatterChange`, `PreambleChange`, `Rename_RemovedPlusAdded`, `DuplicateHeading_OrdinalDistinguishes`, `ByteIdenticalBody_UnderOrdinalShift_NeverEmitted`, `AddedSide_NewDocumentOrdinal`, `RemovedSide_OldDocumentOrdinal`, `LiteralFrontmatterHeading_IsKindSection_NoAlias`, `HeadingKey_WhitespaceTrimmed` | Structured entries `{kind,heading,ordinal,side}`; ordinal document-side pinned (removed=old idx, added=new idx, modified=shared k); byte-identical body NEVER emitted even under ordinal shift; changed region ALWAYS ≥1 entry; no blanket over-report. `ReviewDiff` currently emits empty sections → cases fail at runtime. |
| T17 | GREEN | `tools/internal/speccraft/review_diff.go` (+ `review_sections.go`) | Implement section/frontmatter/preamble parse + ordinal-aligned matching + byte-compare-per-pair determinism rule. |
| T18 | REFACTOR (opt) | `tools/internal/speccraft/review_sections.go` | Extract the `## `/frontmatter/preamble splitter into one pure helper; all P1+P3 tests stay green. |

### Phase 4 — template + command --diff (AC7, AC8, AC9, AC11-cmd)

| Step | Kind | File / test funcs | Detail |
|---|---|---|---|
| T19 | RED | `tests/hooks/spec-review-diff.bats` :: `@test re-review template carries markers and forbids whole-spec language` | Grep oracle scoped to `templates/prompts/re-review.md` ONLY: POSITIVE `assess ONLY the deltas since last review + regressions` and `{{CHANGED_SECTIONS}}` (and `{{DIFF}}`); NEGATIVE `read the whole spec` / `from scratch` / `review the entire spec` absent. File does not exist → RED. |
| T20 | GREEN | `templates/prompts/re-review.md` | Author the brief: `{{DIFF}}`, `{{CHANGED_SECTIONS}}`, explicit regression-sweep instruction over previously-approved criteria; no whole-spec-review language. |
| T21 | RED | `tests/hooks/spec-review-diff.bats` :: `@test usable review.md parser`, `@test provenance gate classify` | `review.lib.sh` `review_reviewed_sha256` (exactly one `^reviewed_sha256: [0-9a-f]{64}$`; zero/multiple/fenced → not usable) + `review_classify` returning full-review / short-circuit / scoped from (snapshot, changed, base_fingerprint, prior reviewed_sha256) per the Provenance gate (AC8/AC9). Sourcing missing lib / undefined funcs → RED. |
| T22 | GREEN | `commands/spec/review.lib.sh` | Implement pure `review_reviewed_sha256` + `review_classify` (spec-0015 pure-function, `${BASH_SOURCE[0]:-$0}`, no zsh-reserved names). |
| T23 | RED | `tests/hooks/spec-review-diff.bats` :: `@test scoped payload contains prior review.md and frozen snapshot content` (AC7b), `@test command builds payload after spec.md removed between promote and payload` (AC11 cmd oracle) | Payload builder must embed prior `review.md` body + current spec sourced from the frozen `review-snapshot.md`; second test `rm`s spec.md after promote and asserts payload still builds → proves command never re-reads spec.md. RED until helper exists. |
| T24 | GREEN | `commands/spec/review.lib.sh` + `commands/spec/review.md` | Implement `review_build_payload` (prepends populated re-review brief, appends prior review.md + frozen snapshot); wire the `--diff` flow into `review.md` (single `review-diff --promote`, gate, dispatch/short-circuit/fallback — all sourced from the frozen snapshot). |

### Phase 5 — drift scope (AC10)

| Step | Kind | File / test funcs | Detail |
|---|---|---|---|
| T25 | RED | `tools/internal/speccraft/drift/rules_test.go` :: `Test_CheckAll_ExcludesSpecsTree_SnapshotEnforceProseDoesNotTrip`, `Test_CheckFile_SpecsPath_Excluded` | Seeds a `specs/0035-re-review/review-snapshot.md` byte-copying an `enforce:`-matching line, calls the SAME `LoadRules`+`CheckAll`/`CheckFile` the hook invokes; asserts zero violations under `specs/**`. Currently `CheckFile` only skips `.speccraft/` → snapshot trips → RED. |
| T26 | GREEN | `tools/internal/speccraft/drift/rules.go` + `.speccraft/conventions.md` | Exclude `specs/**` in `CheckFile`/`CheckAll`; document the snapshot + `--diff` behavior and the `specs/**` drift exclusion in `.speccraft/conventions.md`. |

### Phase 6 — version bump + release (AC12, AC13)

| Step | Kind | File / test funcs | Detail |
|---|---|---|---|
| T27 | RED→GREEN | `tools/cmd/speccraft-state/version_test.go` (rename via Edit `Test_StateCmd_Version_Is190`→`Test_StateCmd_Version_Is1100`, assert "1.10.0") → bump `const version` in `main.go`. | Rename (not fresh Write) registers the RED under a possibly-stale cached guard. |
| T28 | RED→GREEN | `tools/cmd/speccraft-guard/version_test.go` (`Test_GuardCmd_Version_Const190`→`_Const1100`, "1.10.0") → bump guard `main.go` const. | Lockstep no-op bump. |
| T29 | RED→GREEN | `tools/cmd/speccraft-drift/version_test.go` (`Test_DriftCmd_Version_Const190`→`_Const1100`, "1.10.0") → bump drift `main.go` const. | Lockstep no-op bump. |
| T30 | RED→GREEN | `tools/internal/speccraft/manifest_version_test.go` (`Test_Manifests_VersionIs190`→`Test_Manifests_VersionIs1100`; positive `"version": "1.10.0"`, negative stale "1.9.0") → bump `.claude-plugin/{plugin.json,marketplace.json}`. | Grep oracle. |
| T31 | RELEASE (DoD) | merge-time chain | auto-tag (`ci.yml`, `RELEASE_TAG_PAT`) → `release.yml` → `verify-release.sh` strong-form self-verify for `v1.10.0`. The published-verified release is the definition of done. |

## Delegation

- T1 (bootstrap override) → keep on the primary implementer; it is the sole
  `/speccraft:spec:override` and must be recorded, not delegated blindly.
- T2–T18 (Go internal + `speccraft-state` cmd) → `tdd-implementer` (strength:
  Go table-driven tests, `run()`-seam cmd wiring, atomic-write fault injection).
- T19–T24 (template + `review.lib.sh` + `review.md`) → `tdd-implementer` (shell
  `.lib.sh` pure-function + bats; not guard-gated, author-enforced RED→GREEN).
- T25–T26 (drift) → `tdd-implementer`.
- T31 (release) → merge-time pipeline, no agent.

## Risk

- **AC13 override budget = ≤1.** Consolidating ALL new package-`speccraft`
  symbols into the single T1 bootstrap is the only thing that keeps the budget
  at 1. Any later RED that references a NOT-YET-STUBBED new exported symbol would
  force a 2nd override → hard AC13 failure. Mitigation: T1 stubs every symbol
  (`AtomicWriteFile`, `ReviewEnvelope`/`ChangedSection`, `ReviewDiff`,
  `WriteReviewSnapshot`, `WriteReviewFile`) up front; every later test drives an
  existing stub via behaviour or the `run()` seam.
- **Cmd RED as build error.** A cmd test that referenced a new exported symbol
  directly would build-fail. Mitigation: all cmd REDs go through the compile-stable
  `run()` seam with a LOCAL envelope struct (the `detect_cmd_test.go` pattern) →
  runtime "unknown subcommand".
- **AC1 no-op portability.** mtime is not a portable sub-second oracle.
  Mitigation: assert the no-op by byte-compare + fingerprint stability (and, where
  feasible, an unchanged mtime captured pre/post) rather than sub-second timing.
- **AC5 aliasing / over-report.** The byte-identical-under-ordinal-shift and
  literal-`## (frontmatter)` cases are the traps. Mitigation: the T16 table pins
  both the must-emit and must-NOT-emit sides, plus the explicit-`kind` no-alias
  case.
- **Stale cached guard on PATH.** Register each decisive RED via an Edit
  rename/add as the LAST test-file touch before the gated prod edit (conventions
  §"Registering a RED under a stale cached guard").
