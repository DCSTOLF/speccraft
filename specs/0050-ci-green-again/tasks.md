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
