---
spec: "0050"
contract: done-means-v1
---

# Tasks

- [x] **T1** — RED: pin the red-candidate state-key invariant through a symlinked ancestor (AC1, AC2, AC3)
  done: $ grep -q 'func Test_SetRedCandidates_KeysThroughTheCanonicalNormalizer(' tools/internal/speccraft/statekey_writers_test.go && grep -q 'func Test_RedCandidates_TwoSpellingsOfOneFileShareOneEntry(' tools/internal/speccraft/statekey_writers_test.go && grep -q 'func Test_CaptureRedCandidates_KeysThroughTheCanonicalNormalizer(' tools/internal/speccraft/statekey_writers_test.go
- [x] **T2** — GREEN: `SetRedCandidates` keys through `NormalizeStateKey` (AC1, AC2)
  done: $ grep -q 'key := NormalizeStateKey(file)' tools/internal/speccraft/state.go && grep -q 'RedCandidates\[key\] = deduped' tools/internal/speccraft/state.go && cd tools && go test ./internal/speccraft/ -run 'KeysThroughTheCanonicalNormalizer|TwoSpellingsOfOneFile' -count=1
- [x] **T3** — the guard's tests read the key the way production writes it (AC5)
  done: $ [ -z "$(grep -hE 'filepath\.Abs\(' tools/cmd/speccraft-guard/main_test.go tools/cmd/speccraft-guard/multiedit_e2e_test.go tools/cmd/speccraft-guard/reserved_slot_test.go | grep -vE '^[[:space:]]*//')" ] && [ "$(grep -lc 'speccraft.NormalizeStateKey(' tools/cmd/speccraft-guard/main_test.go tools/cmd/speccraft-guard/multiedit_e2e_test.go tools/cmd/speccraft-guard/reserved_slot_test.go | wc -l | tr -d ' ')" = 3 ] && grep -q 'speccraft.NormalizeStateKey(absPath)' tools/cmd/speccraft-guard/main.go
- [x] **T4** — the symlinked-TMPDIR pin: the whole Go suite green under a symlinked temp root (AC4)
  done: $ d="$(mktemp -d)" && mkdir -p "$d/real" && ln -s "$d/real" "$d/link" && cd tools && TMPDIR="$d/link" go test ./... -count=1
- [x] **T5** — RED+GREEN: the GNU probe accepts a BSD tool declaring GNU compatibility (AC6, AC7)
  done: $ grep -q 'BSD grep, GNU compatible' tests/hooks/no-gnu-userland.bats && grep -q '//GNU compatible/' scripts/assert-no-gnu-userland.sh && grep -qF '(^|\()GNU ' scripts/assert-no-gnu-userland.sh && bats tests/hooks/no-gnu-userland.bats
- [x] **T6** — the release-binary clobber cannot reach `bin/` from the suite or from CI (AC8)
  done: $ bats tests/hooks/ci-binary-stamp.bats tests/hooks/session-start.bats
- [x] **T7** — full verification: whole bats suite + Go suite + vet + drift (AC9)
  done: $ bats tests/hooks/ && cd tools && go vet ./... && go test ./... -count=1

Found by fixing AC6 — the macOS bats suite ran for the first time and failed 11
tests in two clusters, both production portability defects (AC10-AC13).

- [x] **T8** — extend both portability meta-guards to cover `realpath -m` and the GNU checksum tool, fixture-first (AC12)
  done: $ grep -q 'g14 g15' tests/hooks/portability-guard.bats && grep -q 'q14.go' tests/hooks/portability-guard.bats && grep -q 'realpath\[\[:space:\]\]+-\[A-Za-z\]\*m' tests/hooks/tests-portability-sweep.bats && bats tests/hooks/portability-guard.bats tests/hooks/tests-portability-sweep.bats
- [x] **T9** — `speccraft-state design-fingerprint <design>` exposes the Go fingerprint; usage documents every dispatched subcommand (AC11)
  done: $ grep -q 'case "design-fingerprint"' tools/cmd/speccraft-state/main.go && cd tools && go test ./cmd/speccraft-state/ -run 'Test_DesignFingerprint|Test_Usage_DocumentsEverySubcommand' -count=1
- [x] **T10** — port `hooks/pre-tool-use.sh` off `realpath -m` and pin canonicalisation through the hook's contract (AC10)
  done: $ [ -z "$(grep -nE 'realpath' hooks/pre-tool-use.sh | grep -vE '^[0-9]+:[[:space:]]*#')" ] && grep -q 'canon_path()' hooks/pre-tool-use.sh && bats tests/hooks/pre-tool-use-state-guard.bats
- [x] **T11** — port `commands/sync.lib.sh` to delegate, and the bats suite's own checksum use to a guarded probe (AC11, AC13)
  done: $ grep -q 'speccraft-state design-fingerprint' commands/sync.lib.sh && grep -q 'sha256_stdin' tests/hooks/sync-workspace.bats && bats tests/hooks/sync-workspace.bats
- [x] **T12** — full re-verification after AC10-AC13 (AC9)
  done: $ bats tests/hooks/ && cd tools && go vet ./... && go test ./... -count=1

The E2E devcontainer job failed on #87 and #88 for defect B reaching a second
consumer: run.sh loaded HEAD's commands but RELEASE binaries (AC14-AC15).

- [x] **T13** — `tests/e2e/run.sh` builds + stamps HEAD's binaries before the lifecycle, and proves `tasks-verify` answers (AC14)
  done: $ bash -n tests/e2e/run.sh && grep -q 'go build -o "$PLUGIN_DIR/bin/' tests/e2e/run.sh && grep -q 'binary-version' tests/e2e/run.sh && bats tests/hooks/e2e-head-binaries.bats
- [x] **T14** — the `[10/13]` close prompt resolves the task-completion gate without bypassing or weakening it (AC15)
  done: $ grep -q 'task-completion gate reports violations' tests/e2e/run.sh && [ -z "$(grep -n 'SKIP-TASKS-VERIFY' tests/e2e/run.sh | grep -vE '^[0-9]+:[[:space:]]*#')" ] && grep -q 'do NOT weaken a predicate' tests/e2e/run.sh
- [x] **T15** — final verification: whole bats suite + Go suite + vet + drift + the locally runnable e2e cycles (AC9)
  done: $ bats tests/hooks/ && bash tests/e2e/workspace_consolidate_cycle.sh >/dev/null && cd tools && go vet ./... && go test ./... -count=1

## Bypasses

- 2026-09-25 — override: the plugin actually running this session's hooks is the
  INSTALLED copy at `~/.claude/plugins/cache/dcstolf-tools/speccraft/1.11.0`, which
  predates spec 0048's build-repair mode. It probes the PRE-edit build, so the
  transiently-non-compiling half of a two-part rename (`key := NormalizeStateKey(file)`
  added, its use not yet switched) made it refuse the very edit that repairs the
  build — defect A of spec 0048 verbatim, arriving from a stale cache rather than
  from the code. The repo's own `bin/speccraft-guard` allows that edit silently via
  its `-overlay` probe of the POST-edit content. One override consumed to complete
  the rename.
- 2026-09-26 — override: same stale 1.11.0 plugin, its OTHER known defect. Spec
  0048 defect B: an edit to a test file that adds no new `func Test…` recomputes
  that file's red candidates as `postIDs − preIDs` = `[]`. `usage_parity_test.go`
  was created with a failing `Test_Usage_DocumentsEverySubcommand`, then edited to
  correct an overstatement in its header comment — a comment-only change, which
  cleared its candidates. The failing test is right there and fails on demand, but
  the installed guard can no longer see it. HEAD's guard computes candidates from a
  first-touch-only `red_baseline` and would still see it. One override consumed to
  add the four missing `usage()` lines.
  Both overrides in this spec were caused by the installed plugin being older than
  the fixes in this repository, not by the work bypassing a real RED.
