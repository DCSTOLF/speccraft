---
spec: "0049"
contract: done-means-v1
---

# Tasks

- [x] T1 — Inventory + sweep methodology recorded in plan.md (review items 7, 8; no AC)
  - [x] T1.a — Appendix A: all 9 `SetStatus` call sites enumerated up front (review item 7)
  - [x] T1.b — Appendix B: grep pattern + the non-executed-match exclusion table (review item 8)
  - [x] T1.c — Appendix C: binary resolution order + the stale-cache hazard
  done: $ grep -q 'Appendix A — SetStatus call-site inventory' specs/0049-command-lib-portability/plan.md && grep -q 'Appendix B — GNU-form sweep methodology' specs/0049-command-lib-portability/plan.md && grep -q 'Appendix C — speccraft-state resolution' specs/0049-command-lib-portability/plan.md
- [x] T2 — RED: kind-scoped status enum + typed `ArtifactKind` + per-kind closed immutability (AC4, AC5)
  - [x] T2.a — design accepts `decided`, rejects `prioritized`; brief the mirror
  - [x] T2.b — default/spec enum unchanged, rejects both new values (no-regression)
  - [x] T2.c — `ArtifactKind("")` errors before status validation
  - [x] T2.d — closed artifact immutable for all three kinds, file byte-identical
  done: $ grep -q 'func Test_SetStatus_KindDesign_AcceptsDecided_RejectsPrioritized(' tools/internal/speccraft/revision_test.go && grep -q 'func Test_SetStatus_EmptyKind_Errors(' tools/internal/speccraft/revision_test.go && grep -q 'func Test_SetStatus_ClosedArtifact_Immutable_AllKinds(' tools/internal/speccraft/revision_test.go && cd tools && go test ./internal/speccraft/ -run 'Test_SetStatus_' -count=1
- [x] T3 — GREEN: `ArtifactKind` + `kindStatuses` + 3-arg `SetStatus`, all 9 call sites in ONE edit — **THE ONE BUDGETED OVERRIDE** (budget 3, expected spend 1; ends buildable, no compatibility wrapper, no new imports) (AC4)
  done: $ grep -q 'type ArtifactKind string' tools/internal/speccraft/revision.go && grep -qE 'KindSpec[[:space:]]+ArtifactKind[[:space:]]*=[[:space:]]*"spec"' tools/internal/speccraft/revision.go && grep -qE '^var kindStatuses' tools/internal/speccraft/revision.go && ! grep -qE '^var validStatuses' tools/internal/speccraft/revision.go && ! grep -q 'SetStatus(args\[1\], args\[2\])' tools/cmd/speccraft-state/main.go && (cd tools && go build ./... && go test ./internal/speccraft/ -count=1)
- [x] T4 — RED: `set-status --kind` flag shape and per-path stderr at the binary layer (AC4, AC2 binary layer)
  - [x] T4.a — `--kind design` and `--kind=design` both accepted, before the positionals
  - [x] T4.b — flag after the positionals is a usage error, not a silent ignore
  - [x] T4.c — no flag ⇒ exactly today's spec enum
  - [x] T4.d — `--kind design <brief.md> decided` succeeds (enum-only validation, recorded as deliberate)
  - [x] T4.e — every non-zero path writes non-empty stderr
  done: $ grep -q 'func Test_StateCmd_SetStatus_KindFlag_SpaceAndEqualsForms(' tools/cmd/speccraft-state/set_status_cmd_test.go && grep -q 'func Test_StateCmd_SetStatus_KindValidatesEnumOnly_NotPathShape(' tools/cmd/speccraft-state/set_status_cmd_test.go && grep -q 'func Test_StateCmd_SetStatus_EveryNonZeroPath_WritesStderr(' tools/cmd/speccraft-state/set_status_cmd_test.go && cd tools && go test ./cmd/speccraft-state/ -run 'Test_StateCmd_SetStatus_' -count=1
- [x] T5 — GREEN: `setStatusCmd` in `tools/cmd/speccraft-state/set_status_cmd.go`; the no-flag default maps to `KindSpec` at the flag layer ONLY (AC4)
  done: $ grep -q 'func setStatusCmd(' tools/cmd/speccraft-state/set_status_cmd.go && grep -q 'speccraft.KindSpec' tools/cmd/speccraft-state/set_status_cmd.go && (cd tools && go test ./internal/speccraft/ -run 'Test_SetStatus_EmptyKind_Errors' -count=1 && go test ./cmd/speccraft-state/ -run 'Test_StateCmd_SetStatus_' -count=1 && go vet ./...)
- [x] T6 — PIN (not RED — see plan step 6): design/brief byte-safety and the Go-layer write-failure seam (AC6, AC2 Go layer)
  - [x] T6.a — BOM + CRLF + no-EOF-newline design fixture: only the first `status:` line changes
  - [x] T6.b — injected `atomicRename` failure: error, byte-identical target, no `.tmp` remnant
  done: $ grep -q 'func Test_SetStatus_Design_BomCrlfNoEofNewline_OnlyStatusLineChanges(' tools/internal/speccraft/frontmatter_writer_test.go && grep -q 'func Test_SetStatus_RenameFailure_LeavesFileByteIdentical_NoTempLeftover(' tools/internal/speccraft/revision_test.go && cd tools && go test ./internal/speccraft/ -run 'Test_SetStatus_(Design_BomCrlf|RenameFailure)' -count=1
- [x] T7 — RED: every non-zero exit path of both helpers, split by layer (AC1, AC2 shell layer, AC3; review item 6)
  - [x] T7.a — source-scan: no `sed`/`perl -i`; `set-status --kind` invoked
  - [x] T7.b — successful transition leaves no stray sibling (`-E`, `.bak`, `.tmp`)
  - [x] T7.c — shell pre-checks (missing file, non-draft source): non-zero + non-empty stderr, before the binary is invoked
  - [x] T7.d — real binary (invalid status for kind, closed artifact): non-zero + stderr + file unchanged
  - [x] T7.e — PATH-shim stub (underlying write failure): non-zero + stderr + byte-identical target + no temp remnant
  - [x] T7.f — all six mirrored for `pm_set_status` with `--kind brief`
  done: $ grep -c '@test' tests/hooks/arch-decide.bats | grep -qv '^2$' && grep -q 'PATH shim' tests/hooks/arch-decide.bats && grep -q 'PATH shim' tests/hooks/pm-prioritize.bats && PATH="$PWD/bin:$PATH" bats tests/hooks/arch-decide.bats tests/hooks/pm-prioritize.bats
- [x] T8 — GREEN: both helpers delegate to `speccraft-state set-status --kind`; resolver per plan Appendix C; `$GITHUB_PATH` step in the `hooks` job. The four pre-existing tests pass UNMODIFIED (AC1, AC2, AC3)
  - [x] T8.a — `decide.lib.sh` line 25 removed; gates kept verbatim; `--kind design`
  - [x] T8.b — `prioritize.lib.sh` line 25 removed; `--kind brief`
  - [x] T8.c — resolver order `$SPECCRAFT_STATE_BIN` → PATH → plugin-local `bin/`; diagnostic names the resolved path
  - [x] T8.d — ci.yml `hooks` job prepends the built `bin/` to `$GITHUB_PATH`
  done: $ ! grep -qE '\bsed\b|perl -i' commands/arch/decide.lib.sh commands/pm/prioritize.lib.sh && grep -q 'set-status --kind design' commands/arch/decide.lib.sh && grep -q 'set-status --kind brief' commands/pm/prioritize.lib.sh && grep -q 'GITHUB_PATH' .github/workflows/ci.yml && grep -q 'arch_set_status: draft -> decided' tests/hooks/arch-decide.bats && grep -q 'arch_set_status: rejects non-draft source' tests/hooks/arch-decide.bats && grep -q 'pm_set_status: draft -> prioritized' tests/hooks/pm-prioritize.bats && grep -q 'pm_set_status: rejects non-draft source' tests/hooks/pm-prioritize.bats && PATH="$PWD/bin:$PATH" bats tests/hooks/arch-decide.bats tests/hooks/pm-prioritize.bats
- [x] T9 — RED: frontmatter-writer meta-guard fixtures for design/brief/variable targets, incl. the pre-fix `arch_set_status` line VERBATIM (AC7; must follow T8 — hazard 3)
  - [x] T9.a — forbidden: literal `design.md`, literal `brief.md`, `$DESIGN`, `$BRIEF`, and the verbatim pre-fix line
  - [x] T9.b — permitted: read-only `awk -F': '` on a design, `grep -E '^status:'` on a brief
  - [x] T9.c — scan root is `commands/` only; a planted `specs/` fixture is NOT seen (archive-safety)
  done: $ grep -q 'design\.md' tests/hooks/frontmatter-writer-guard.bats && grep -q 'brief\.md' tests/hooks/frontmatter-writer-guard.bats && grep -q '0,/\^status:/' tests/hooks/frontmatter-writer-guard.bats && grep -q 'excludes specs/' tests/hooks/frontmatter-writer-guard.bats && PATH="$PWD/bin:$PATH" bats tests/hooks/frontmatter-writer-guard.bats
- [x] T10 — GREEN: widen `scan_offenders()`'s path-shape filter to all three artifact kinds and non-literal targets; scan root stays `commands/`, with the never-widen-to-specs rationale in the header comment (AC7)
  done: $ grep -q 'design_md\|design\\.md' tests/hooks/frontmatter-writer-guard.bats && grep -q 'PLUGIN_DIR/commands' tests/hooks/frontmatter-writer-guard.bats && ! grep -q 'PLUGIN_DIR/specs' tests/hooks/frontmatter-writer-guard.bats && PATH="$PWD/bin:$PATH" bats tests/hooks/frontmatter-writer-guard.bats
- [x] T11 — RED: `tac`-absent ordering over a both-halves fixture + portability-guard fixtures, both polarities (AC8, AC9; review item 5)
  - [x] T11.a — `consolidate_backfill_order` with `tac` absent from PATH: history-chronological half THEN history-less half, full expected order
  - [x] T11.b — guard FLAGS all eight enumerated forms plus the commented, fenced, quoted and line-continuation variants
  - [x] T11.c — guard PASSES `sed -i.bak`, `sed -i ''`, `sed -i ""`, `sed -n '/re/p'`, `stat -f`, a `speccraft-state` redirect
  - [x] T11.d — live `hooks/ commands/ tools/ templates/ agents/ skills/` scan clean
  - [x] T11.e — scan root excludes `tests/` AND `tools/**/*_test.go` (decision: test-side, never installed; `unit-macos` is its complementary runner)
  done: $ grep -q 'tac absent from PATH' tests/hooks/spec-consolidate.bats && grep -q 'FLAGS every forbidden GNU-only fixture' tests/hooks/portability-guard.bats && grep -q 'PASSES every portable counterpart' tests/hooks/portability-guard.bats && grep -q '_test.go' tests/hooks/portability-guard.bats && PATH="$PWD/bin:$PATH" bats tests/hooks/portability-guard.bats tests/hooks/spec-consolidate.bats
- [x] T12 — GREEN: replace `tac` with the POSIX awk reversal AND land the guard with that exact string PERMITTED — **ONE TASK, ONE COMMIT, DO NOT SPLIT** (AC8, AC9; hazard 2)
  - [x] T12.a — `consolidate.lib.sh:409` uses the awk reversal; no `tac` anywhere in the lib
  - [x] T12.b — guard scanner with the two-stage prefix-safe `sed -i` rule
  - [x] T12.c — header comment: `tests/**` + `tools/**/*_test.go` exclusion rationale, and the no-escape-hatch decision
  done: $ ! grep -qE '(^|[|;&(]|[[:space:]])tac([[:space:]]|$|[|;&)])' commands/spec/consolidate.lib.sh && grep -q 'for(i=NR;i>0;i--)' commands/spec/consolidate.lib.sh && grep -q 'for(i=NR;i>0;i--)' tests/hooks/portability-guard.bats && grep -q 'no escape hatch' tests/hooks/portability-guard.bats && (PATH="$PWD/bin:$PATH" bats tests/hooks/portability-guard.bats tests/hooks/spec-consolidate.bats)
- [x] T13 — RED: executable sweep asserting no `tests/hooks/` file EXECUTES a GNU-only form, with a pinned mention-only exclusion list (AC10 condition 1; review item 8)
  done: $ grep -q 'EXECUTES a GNU-only form' tests/hooks/tests-portability-sweep.bats && grep -q 'exclusion list is exactly' tests/hooks/tests-portability-sweep.bats && PATH="$PWD/bin:$PATH" bats tests/hooks/tests-portability-sweep.bats
- [x] T14 — GREEN: port every GNU-only EXECUTION in tests/hooks — **two files, nine sites** (the plan said one/seven; T13's mechanised sweep disproved it): seven `sed -i` fixture mutations in `spec-revise-preflight.bats` via a local `sed_inplace` helper, plus two `grep -qP` calls in `init-workspace.bats:139-140` via printf-tabs + `grep -qF`. Ported, not excluded (AC10 condition 1)
  done: $ (PATH="$PWD/bin:$PATH" bats tests/hooks/tests-portability-sweep.bats tests/hooks/spec-revise-preflight.bats tests/hooks/init-workspace.bats)
- [x] T15 — RED: no-GNU-userland assertion logic, Bash-5 runtime assertion, and the ci.yml `hooks-macos` contract (AC10 conditions 2/3/4; review items 1, 2)
  - [x] T15.a — PASSES a synthetic BSD-only fixture PATH
  - [x] T15.b — FLAGS gnubin-shadowed `sed`, coreutils/libexec-shadowed `stat`, resolvable `gsed`, resolvable `tac`
  - [x] T15.c — FLAGS a GNU `sed` reached through an unusual symlink, via the behavioral `--version` probe (review item 2)
  - [x] T15.d — the LIVE assertion is a ci.yml step, NOT a bats test — pinned mechanically, because on Linux `tac` resolves and the assertion would invert (review item 1)
  - [x] T15.e — running interpreter is Bash 5+
  - [x] T15.f — ci.yml: `hooks-macos` on `macos-14`, full suite, assertion step BEFORE bats, no coreutils/gsed install, no gnubin prepend
  done: $ grep -q 'unusual symlink' tests/hooks/no-gnu-userland.bats && grep -q 'not a bats test' tests/hooks/no-gnu-userland.bats && grep -q 'BASH_VERSINFO' tests/hooks/no-gnu-userland.bats && PATH="$PWD/bin:$PATH" bats tests/hooks/no-gnu-userland.bats
- [x] T16 — GREEN: `scripts/assert-no-gnu-userland.sh` (path check + behavioral probe, PATH injectable) and the `hooks-macos` job invoking it before bats, through Homebrew Bash 5 (AC10)
  done: $ bash -n scripts/assert-no-gnu-userland.sh && grep -q 'SPECCRAFT_PROBE_PATH' scripts/assert-no-gnu-userland.sh && grep -q 'hooks-macos' .github/workflows/ci.yml && grep -q 'assert-no-gnu-userland.sh' .github/workflows/ci.yml && grep -q 'bats-core' .github/workflows/ci.yml && ! grep -qE 'brew install .*(coreutils|gnu-sed|gsed)' .github/workflows/ci.yml && ! grep -q 'gnubin' .github/workflows/ci.yml && PATH="$PWD/bin:$PATH" bats tests/hooks/no-gnu-userland.bats
- [x] T17 — RED: `verify-linux-pins.sh` contract — non-destructive by construction (AC11; review items 3, 4)
  - [x] T17.a — `--list` names exactly the three production pins
  - [x] T17.b — fingerprints the caller tree BEFORE creating the worktree (review item 3)
  - [x] T17.c — uses `git worktree add --detach`, not a temp clone (review item 4)
  - [x] T17.d — removes the worktree on every exit path, including failure
  - [x] T17.e — each mutation restarts from the same clean baseline, never layered
  - [x] T17.f — caller checkout byte-identical after a run whose pin check FAILS
  done: $ grep -q 'BEFORE creating the worktree' tests/hooks/verify-linux-pins.bats && grep -q 'worktree add --detach' tests/hooks/verify-linux-pins.bats && grep -q 'pin check FAILS' tests/hooks/verify-linux-pins.bats && PATH="$PWD/bin:$PATH" bats tests/hooks/verify-linux-pins.bats
- [x] T18 — GREEN: `scripts/verify-linux-pins.sh` — fingerprint first, detached worktree, trap cleanup, per-pin clean baseline, final self-check, non-CI-gating (AC11)
  done: $ bash -n scripts/verify-linux-pins.sh && grep -q 'git worktree add --detach' scripts/verify-linux-pins.sh && ! grep -q 'git clone' scripts/verify-linux-pins.sh && grep -q 'trap' scripts/verify-linux-pins.sh && grep -q 'SPECCRAFT_VLP_TEST_CMD' scripts/verify-linux-pins.sh && PATH="$PWD/bin:$PATH" bats tests/hooks/verify-linux-pins.bats
- [x] T19 — Author evidence run: all three pins confirmed on Linux, final line recorded in this spec's changelog.md (AC11)
  done: $ grep -q 'verify-linux-pins.sh: 3/3 pins confirmed' specs/0049-command-lib-portability/changelog.md
- [x] T20 — Confirm 0049 carries NO version bump: the six version locations still read 1.16.0 (Resolved decision 1)
  done: $ grep -q '"version": "1.16.0"' .claude-plugin/plugin.json && grep -q '"version": "1.16.0"' .claude-plugin/marketplace.json && grep -q 'const version = "1.16.0"' tools/cmd/speccraft-state/main.go && grep -q 'const version = "1.16.0"' tools/cmd/speccraft-guard/main.go && grep -q 'const version = "1.16.0"' tools/cmd/speccraft-drift/main.go
- [x] T21 — REFACTOR (optional) **SKIPPED, deliberately**: `_arch_state_bin`/`_pm_state_bin` duplicate ~15 lines, but extracting them needs a shared sourceable lib that each helper must first locate — spec 0022 T16 weighed this exact trade for these exact two files and kept them separate for independent sourcing. Duplication is bounded and both copies are covered by the PATH-shim tests. Recorded as `[x]` not `[~]`: under `contract: done-means-v1` the parser accepts only `[ ]`/`[x]`/`[X]`, so a `[~]` line parses as prose and its `done:` line would attach to the previous task and make it malformed (exit 2)
  done: $ PATH="$PWD/bin:$PATH" bats tests/hooks/arch-decide.bats tests/hooks/pm-prioritize.bats tests/hooks/frontmatter-writer-guard.bats tests/hooks/portability-guard.bats
- [x] T22 — Full green on Linux: Go suite, vet, and the whole bats suite
  done: $ cd tools && go test ./... && go vet ./... && cd .. && PATH="$PWD/bin:$PATH" bats tests/hooks/

## Bypasses

- 2026-09-15 — override: T3 GREEN, edit 1 of 2 — `tools/internal/speccraft/revision.go` introduces `ArtifactKind`, the three kind constants, `kindStatuses`, and the three-arg `SetStatus`. The tree is unbuildable from T2's RED (a compile failure, which per spec-0018 AC13 the guard cannot observe as a runtime RED), so this edit is forbidden by the guard-wedge class documented in spec 0048.
- 2026-09-15 — override: T3 GREEN, edit 2 of 3 — `tools/internal/speccraft/revision.go` `SetStatus` signature + per-kind validation. A SECOND edit to the same file was needed because the enum block (line ~182) and `SetStatus` (line ~291) are ~110 lines apart; a single Edit spanning both would have cost one override instead of two. Recorded as an avoidable cost, not a surprise.
- 2026-09-15 — override: T3 GREEN, edit 3 of 3 — `tools/cmd/speccraft-state/main.go:302` call site.

**Override accounting:** budget 3, actual spend 3 (plan.md estimated 1). The estimate did not account for `ConsumeOverride` being per-EDIT rather than per-task, and the atomic change spans two production files plus two non-adjacent regions of one of them. Budget is exhausted; any further override needs an explicit decision.
