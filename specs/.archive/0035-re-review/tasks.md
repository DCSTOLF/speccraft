---
spec: "0035"
---

# Tasks

## P0 — bootstrap (the ONE override)
- [x] T1: BOOTSTRAP — stub `AtomicWriteFile`, `ReviewEnvelope`/`ChangedSection`, `ReviewDiff`, `WriteReviewSnapshot`, `WriteReviewFile` in `tools/internal/speccraft/review.go`; anchor `Test_Review_Bootstrap_SymbolsExist` (single recorded `/speccraft:spec:override`) [AC13]

## P1 — snapshot + envelope core
- [x] T2: RED — `atomicwrite_test.go` (writes bytes+perm; same-dir temp rename replaces; rename-failure leaves prior byte-identical)
- [x] T3: GREEN+REFACTOR — implement `AtomicWriteFile`; refactor `saveStateLocked` to call it
- [x] T4: RED — `review_snapshot_test.go` (snapshot==spec bytes; sha256 raw no-normalization; robust no-op; missing spec.md errors) [AC1]
- [x] T5: GREEN — implement `WriteReviewSnapshot` + fingerprint [AC1]
- [x] T6: RED — `review_snapshot_cmd_test.go` via `run()` seam (writes+prints fingerprint; missing spec non-zero; usage lists it) [AC1]
- [x] T7: GREEN — wire `review-snapshot write` in `speccraft-state/main.go` [AC1]
- [x] T8: RED — `review_diff_test.go` (identical→snapshot:true/changed:false/base==fingerprint; no-snapshot→snapshot:false/base:null; fingerprint=current bytes) [AC3,AC4,AC6]
- [x] T9: GREEN — implement `ReviewDiff` envelope skeleton [AC3,AC4,AC6]
- [x] T10: RED — `review_diff_promote_test.go` injected seam: old snapshot read BEFORE new written; diffed image written once [AC11]
- [x] T11: GREEN — implement `--promote` write-from-frozen-image path [AC11]
- [x] T12: RED — `review_diff_cmd_test.go` via `run()` seam (schema=1 envelope; read-only exit0 for closed + no-snapshot; unreadable spec/snapshot non-zero; promote-on-closed refused writes nothing) [AC3,AC4,AC6]
- [x] T13: GREEN — wire `review-diff [--promote]` + exit-code matrix + closed refusal [AC3]

## P2 — provenance atomic commit
- [x] T14: RED — `review_commit_test.go` (single `reviewed_sha256:` line; sha256 over snapshot reproduces; rename-failure→prior review.md byte-identical; mid-write→no fingerprint-free artifact) [AC2]
- [x] T15: GREEN — implement `WriteReviewFile` single atomic commit via `AtomicWriteFile` [AC2]

## P3 — anchor-scheme determinism
- [x] T16: RED — `review_diff_sections_test.go` table (unique-modify; frontmatter; preamble; rename removed+added; duplicate-heading ordinal; byte-identical-body-under-ordinal-shift NEVER emitted; added=new-idx; removed=old-idx; literal `## (frontmatter)` is kind:section no-alias; heading-key whitespace-trimmed) [AC5]
- [x] T17: GREEN — implement section/frontmatter/preamble parse + ordinal-aligned matching + per-pair byte-compare determinism rule [AC5]
- [x] T18: REFACTOR (optional) — extract pure section splitter to `review_sections.go`

## P4 — template + command --diff
- [x] T19: RED — `tests/hooks/spec-review-diff.bats` template grep (positive `{{DIFF}}`/`{{CHANGED_SECTIONS}}`/`assess ONLY the deltas since last review + regressions`; negative whole-spec language scoped to the template only) [AC7a]
- [x] T20: GREEN — author `templates/prompts/re-review.md` [AC7a]
- [x] T21: RED — bats: `review_reviewed_sha256` usable parser + `review_classify` provenance gate [AC8,AC9]
- [x] T22: GREEN — implement `review.lib.sh` classify helpers [AC8,AC9]
- [x] T23: RED — bats: scoped payload embeds prior review.md + frozen-snapshot content; payload still builds after spec.md removed between promote and payload [AC7b,AC11]
- [x] T24: GREEN — implement `review_build_payload` + wire `--diff` flow in `review.md` [AC7b,AC8,AC9,AC11]

## P5 — drift scope
- [x] T25: RED — `drift/rules_test.go` `Test_CheckAll_ExcludesSpecsTree_*`/`Test_CheckFile_SpecsPath_Excluded` via `LoadRules`+`CheckAll`/`CheckFile` [AC10]
- [x] T26: GREEN — exclude `specs/**` in `CheckFile`/`CheckAll`; document snapshot + `--diff` + exclusion in `.speccraft/conventions.md` [AC10]

## P6 — version bump + release
- [x] T27: RED→GREEN — rename `Test_StateCmd_Version_Is190`→`_Is1100` ("1.10.0"); bump `speccraft-state` const [AC12]
- [x] T28: RED→GREEN — rename `Test_GuardCmd_Version_Const190`→`_Const1100`; bump `speccraft-guard` const [AC12]
- [x] T29: RED→GREEN — rename `Test_DriftCmd_Version_Const190`→`_Const1100`; bump `speccraft-drift` const [AC12]
- [x] T30: RED→GREEN — rename `Test_Manifests_VersionIs190`→`_Is1100` (positive "1.10.0", negative "1.9.0"); bump `.claude-plugin/{plugin,marketplace}.json` [AC12]
- [~] T31: RELEASE (merge-time DoD — auto-tag→release.yml→verify-release.sh fires on push at close) — merge-time auto-tag → release.yml → verify-release.sh for v1.10.0 (definition of done) [AC12]

## Bypasses

- 2026-07-26 — T1 — ONE planned `/speccraft:spec:override`. Reason: new-symbol
  bootstrap for the review-diff/review-snapshot type (`AtomicWriteFile`,
  `ReviewEnvelope`/`ChangedSection`, `ReviewDiff`, `WriteReviewSnapshot`,
  `WriteReviewFile` in package `speccraft`). Their first test cannot compile until
  the symbols exist (spec-0018-AC13 build-failure-is-not-RED limitation), so a
  single override introduces minimal zero-value stubs. Budget = 1 (AC13); no
  second override permitted absent a spec amendment.
