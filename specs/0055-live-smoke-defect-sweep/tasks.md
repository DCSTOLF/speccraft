---
spec: "0055"
contract: done-means-v1
---

# Tasks

- [x] T1 — RED: the live smoke's launch cwd and the AC26a pass condition (AC1, AC2)
  done: $ grep -qF '@test "live_launch derives its cwd from the workspace root, not a temp dir"' tests/hooks/live-codex-smoke.bats && grep -qF '@test "the launch-cwd row rejects a /tmp cwd, so it is not vacuous"' tests/hooks/live-codex-smoke.bats && grep -qF '@test "the AC26a body requires a non-terminal status before the cancel and cancelled after"' tests/hooks/live-codex-smoke.bats

- [x] T2 — GREEN: launch at the workspace root, and make the cancel row prove a cancel (AC1, AC2)
  - [x] T2.a — `live_launch` derives its cwd from `speccraft-state find-root`
  - [x] T2.b — the AC26a body requires non-terminal before and `cancelled` after
  done: $ grep -qF 'speccraft-state find-root' tests/hooks/live-codex-smoke.bats && o=$(PATH="$PWD/bin:$PATH" bats tests/hooks/live-codex-smoke.bats 2>&1) && test "$(printf '%s\n' "$o" | grep -cE '^not ok')" -eq 0 && test "$(printf '%s\n' "$o" | grep -cE '^ok ')" -ge 11 && test "$(printf '%s\n' "$o" | grep -c '# skip')" -eq 2

- [x] T3 — RED: one cwd for task, status, result and cancel (AC3)
  done: $ grep -qF '@test "task status result and cancel all carry the dispatcher'"'"'s cwd"' tests/hooks/spec-review-codex.bats && grep -qF '@test "a dispatch given a cwd outside the repo still resolves its own job"' tests/hooks/spec-review-codex.bats && grep -qF '@test "dropping the cwd from any one post-launch codex helper fails the lifecycle row"' tests/hooks/spec-review-codex.bats

- [x] T4 — GREEN: thread the cwd through every post-launch codex helper (AC3)
  - [x] T4.a — `review_codex_job_status` / `_result` / `_cancel` / `_review_codex_poll` take a required cwd and emit `--cwd`
  - [x] T4.b — each helper's `# <fn> <args…>` doc header updated in lockstep (the arity guard reads them)
  - [x] T4.c — `_review_codex_dispatch` passes its own cwd to poll, result and cancel
  - [x] T4.d — the existing two-argument call sites in the two bats files updated
  done: $ test "$(grep -c -- '--cwd' commands/spec/review-codex.lib.sh)" -ge 5 && grep -qF '# review_codex_job_status <root> <job-id> <cwd>' commands/spec/review-codex.lib.sh && grep -qF '# review_codex_job_result <root> <job-id> <out-file> <cwd>' commands/spec/review-codex.lib.sh && grep -qF '# review_codex_job_cancel <root> <job-id> <cwd>' commands/spec/review-codex.lib.sh && o=$(PATH="$PWD/bin:$PATH" bats tests/hooks/spec-review-codex.bats tests/hooks/live-codex-smoke.bats 2>&1) && test "$(printf '%s\n' "$o" | grep -cE '^not ok')" -eq 0 && test "$(printf '%s\n' "$o" | grep -cE '^ok ')" -ge 119

- [ ] T5 — RED: quarantine records its cwd, and the sweep says why a block survived (AC3a)
  done: $ grep -qF '@test "a codex-plugin quarantine records the job-store cwd beside the root"' tests/hooks/spec-review-round-lifecycle.bats && grep -qF '@test "quarantine recovery probes the recorded cwd from an unrelated cwd"' tests/hooks/spec-review-round-lifecycle.bats && grep -qF '@test "a legacy quarantine block with no cwd line is retained with a named diagnostic"' tests/hooks/spec-review-round-lifecycle.bats && grep -qF '@test "the sweep reports the missing-cwd block by name and clears only the new-format one"' tests/hooks/spec-review-round-lifecycle.bats && grep -qF '@test "the sweep'"'"'s missing-cwd report fails when the resolver output is suppressed"' tests/hooks/spec-review-round-lifecycle.bats

- [ ] T6 — GREEN: record the cwd, probe with it, and surface the refusal through the sweep (AC3a)
  - [ ] T6.a — `review_round_quarantine` writes a `cwd ` line (required for codex-plugin, refused for subagent)
  - [ ] T6.b — the resolver probes with the recorded cwd; a block with no `cwd ` is retained with a named diagnostic
  - [ ] T6.c — `review_round_sweep` stops discarding the resolver's output and names the retained block
  done: $ grep -qF "printf 'cwd %s" commands/spec/review-round.lib.sh && grep -qF 'quarantine-missing-cwd' commands/spec/review-round.lib.sh && test "$(grep -c 'review_round_quarantine_resolve "$entry" >/dev/null 2>&1' commands/spec/review-round.lib.sh)" -eq 0 && o=$(PATH="$PWD/bin:$PATH" bats tests/hooks/spec-review-round-lifecycle.bats 2>&1) && test "$(printf '%s\n' "$o" | grep -cE '^not ok')" -eq 0 && test "$(printf '%s\n' "$o" | grep -cE '^ok ')" -ge 51

- [ ] T7 — RED: the 0052 corpus arm's three defects, pinned from a sibling file (AC4, AC5, AC9, AC10)
  done: $ test -f tests/hooks/spec-review-payload-floor.bats && grep -qF '@test "no comment in the 0052 corpus arm claims an archive entry cannot red it"' tests/hooks/spec-review-payload-floor.bats && grep -qF '@test "the superseded-claim row bites when the sentence is restored"' tests/hooks/spec-review-payload-floor.bats && grep -qF '@test "the corpus arm branches on the effective argv limit, not the compiled default"' tests/hooks/spec-review-payload-floor.bats && grep -qF '@test "the pre-fix corpus-arm branch misclassifies under an exported REVIEW_MAX_ARGV_BYTES"' tests/hooks/spec-review-payload-floor.bats && grep -qF '@test "no @test name in the 0052 floor claims an argv bound while its body asserts the payload limit"' tests/hooks/spec-review-payload-floor.bats && grep -qF '@test "the 0052 floor is 119 identical names plus exactly one rename"' tests/hooks/spec-review-payload-floor.bats

- [ ] T8 — GREEN: the corpus arm's comment says what actually bounds it (AC4)
  done: $ test "$(grep -cF 'neither can a new archive entry' tests/hooks/spec-review-payload.bats)" -eq 0 && grep -qF 'a new archive entry CAN push the tiered size over the argv limit' tests/hooks/spec-review-payload.bats && o=$(PATH="$PWD/bin:$PATH" bats tests/hooks/spec-review-payload-floor.bats 2>&1) && test "$(printf '%s\n' "$o" | grep -cE '^not ok')" -eq 0

- [ ] T9 — GREEN: the arm's disposition is pinned by name at both override values (AC5)
  done: $ grep -qF 'review_effective_limit argv' tests/hooks/spec-review-payload.bats && grep -qF 'refuse:argv-limit' tests/hooks/spec-review-payload.bats && test "$(grep -c 'REVIEW_MAX_PAYLOAD_BYTES=' tests/hooks/spec-review-payload.bats)" -ge 1 && o=$(PATH="$PWD/bin:$PATH" bats tests/hooks/spec-review-payload.bats tests/hooks/spec-review-payload-floor.bats 2>&1) && test "$(printf '%s\n' "$o" | grep -cE '^not ok')" -eq 0 && test "$(printf '%s\n' "$o" | grep -cE '^ok ')" -ge 128

- [ ] T10 — GREEN: the corpus test name matches its assertion, and the floor is 119+1 (AC9, AC10)
  done: $ grep -qF '@test "the live .speccraft plus the largest archived spec composes under the payload limit while a full paste exceeds the argv limit by more than 2x"' tests/hooks/spec-review-payload.bats && T="$(mktemp)" && git show 19317e5:tests/hooks/spec-review-payload.bats | grep '^@test' > "$T" && test "$(grep '^@test' tests/hooks/spec-review-payload.bats | grep -Fxv -f "$T" | wc -l | tr -d ' ')" -eq 1 && test "$(grep -c '^@test' tests/hooks/spec-review-payload.bats)" -eq 120 && rm -f "$T"

- [ ] T11 — RED: the false reproducibility claim (AC6)
  done: $ grep -qF '@test "spec-lifecycle.md no longer claims git diff HEAD is reproducible from HEAD"' tests/hooks/spec-review-code.bats && grep -qF '@test "the reproducibility-claim row bites when the old phrasing is restored"' tests/hooks/spec-review-code.bats && grep -qF '@test "the corrected bullet names the frozen artifact, pinned endpoints and the round lifetime"' tests/hooks/spec-review-code.bats

- [ ] T12 — GREEN: the corrected bullet says all three things (AC6)
  done: $ test "$(grep -cF 'is exactly reproducible from the recorded' specs/domains/spec-lifecycle.md)" -eq 0 && grep -qF 'the frozen artifact is the reproducible record' specs/domains/spec-lifecycle.md && grep -qF 'both endpoints pinned to commits' specs/domains/spec-lifecycle.md && grep -qF 'for the lifetime of the round' specs/domains/spec-lifecycle.md && o=$(PATH="$PWD/bin:$PATH" bats tests/hooks/spec-review-code.bats 2>&1) && test "$(printf '%s\n' "$o" | grep -cE '^not ok')" -eq 0 && test "$(printf '%s\n' "$o" | grep -cE '^ok ')" -ge 20

- [ ] T13 — RED: every hook command must be space-safe (AC7)
  done: $ test -f tests/hooks/hooks-json-quoting.bats && grep -qF '@test "no hook command field carries a bare unquoted CLAUDE_PLUGIN_ROOT"' tests/hooks/hooks-json-quoting.bats && grep -qF '@test "the quoting row bites on any single re-introduced bare placeholder"' tests/hooks/hooks-json-quoting.bats && grep -qF '@test "all five hooks execute from a plugin root containing a space"' tests/hooks/hooks-json-quoting.bats && grep -qF '@test "the spaced-path row fails on the pre-fix unquoted command"' tests/hooks/hooks-json-quoting.bats

- [ ] T14 — GREEN: quote the placeholder in all five hook entries (AC7)
  done: $ test "$(grep -c '"command": "\\"' hooks/hooks.json)" -eq 5 && test "$(grep -c '"command": "\${CLAUDE' hooks/hooks.json)" -eq 0 && jq -e . hooks/hooks.json >/dev/null && o=$(PATH="$PWD/bin:$PATH" bats tests/hooks/hooks-json-quoting.bats 2>&1) && test "$(printf '%s\n' "$o" | grep -cE '^not ok')" -eq 0 && test "$(printf '%s\n' "$o" | grep -cE '^ok ')" -ge 4

- [ ] T15 — RED: archive-aware, reservation-honouring id allocation (AC8)
  done: $ test -f tests/hooks/spec-new-id-allocation.bats && grep -qF '@test "spec_new_next_id returns 0056 for this repo'"'"'s live tree"' tests/hooks/spec-new-id-allocation.bats && grep -qF '@test "spec_new_next_id returns 0001 for an empty fixture"' tests/hooks/spec-new-id-allocation.bats && grep -qF '@test "spec_new_next_id returns max+1 when every id lives only under .archive"' tests/hooks/spec-new-id-allocation.bats && grep -qF '@test "spec_new_next_id skips an id reserved by reserves-specs at max+1"' tests/hooks/spec-new-id-allocation.bats && grep -qF '@test "reserves-specs is read from frontmatter only, never from prose"' tests/hooks/spec-new-id-allocation.bats && grep -qF '@test "an allocator that scans only specs slash returns a colliding id on the archived fixture"' tests/hooks/spec-new-id-allocation.bats && grep -qF '@test "an allocator that ignores reserves-specs returns the reserved id"' tests/hooks/spec-new-id-allocation.bats

- [ ] T16 — GREEN: `spec_new_next_id` in `commands/spec/new.lib.sh` (AC8)
  done: $ grep -q '^spec_new_next_id()' commands/spec/new.lib.sh && test "$(bash -c '. ./commands/spec/new.lib.sh && spec_new_next_id "$PWD"')" = 0056 && o=$(PATH="$PWD/bin:$PATH" bats tests/hooks/spec-new-id-allocation.bats 2>&1) && test "$(printf '%s\n' "$o" | grep -cE '^not ok')" -eq 0 && test "$(printf '%s\n' "$o" | grep -cE '^ok ')" -ge 7

- [ ] T17 — RED: no two specs may share an id (AC8a)
  done: $ grep -qF '@test "no spec id appears twice across specs and specs archive"' tests/hooks/spec-new-id-allocation.bats && grep -qF '@test "the duplicate-id row fails on a fixture holding one id in specs and the same id archived"' tests/hooks/spec-new-id-allocation.bats

- [ ] T18 — GREEN: the standing duplicate-id collector, proven to bite (AC8a)
  done: $ test "$({ ls specs/ specs/.archive/ 2>/dev/null; } | grep -oE '^[0-9]{4}' | sort | uniq -d | wc -l | tr -d ' ')" -eq 0 && o=$(PATH="$PWD/bin:$PATH" bats tests/hooks/spec-new-id-allocation.bats 2>&1) && test "$(printf '%s\n' "$o" | grep -cE '^not ok')" -eq 0 && test "$(printf '%s\n' "$o" | grep -cE '^ok ')" -ge 9

- [ ] T19 — RED: the shipped command must call the helper, reachably (AC8b)
  done: $ grep -qF '@test "new.md sources the lib before it allocates an id"' tests/hooks/spec-new-id-allocation.bats && grep -qF '@test "the shipped step-4 invocation, extracted and run, allocates on a fixture with archived ids and a reservation"' tests/hooks/spec-new-id-allocation.bats && grep -qF '@test "the extracted invocation fails when given the wrong repo root"' tests/hooks/spec-new-id-allocation.bats && grep -qF '@test "the extracted invocation fails when its return value is discarded"' tests/hooks/spec-new-id-allocation.bats && grep -qF '@test "new.md no longer tells the model to run ls specs"' tests/hooks/spec-new-id-allocation.bats && grep -qF '@test "the ls-specs absence row bites when the instruction is restored"' tests/hooks/spec-new-id-allocation.bats

- [ ] T20 — GREEN: bootstrap moves ahead of allocation, and step 4 calls the helper (AC8b)
  - [ ] T20.a — the `source` of `new.lib.sh` precedes the allocation step
  - [ ] T20.b — step 4 is `NEXT_ID="$(spec_new_next_id "$REPO_ROOT")"` and downstream steps use `$NEXT_ID`
  - [ ] T20.c — the `ls specs/` instruction is gone
  done: $ test "$(grep -n 'commands/spec/new.lib.sh' commands/spec/new.md | grep source | head -1 | cut -d: -f1)" -lt "$(grep -n 'spec_new_next_id' commands/spec/new.md | head -1 | cut -d: -f1)" && grep -qF 'NEXT_ID="$(spec_new_next_id "$REPO_ROOT")"' commands/spec/new.md && test "$(grep -c 'ls specs/' commands/spec/new.md)" -eq 0 && o=$(PATH="$PWD/bin:$PATH" bats tests/hooks/spec-new-id-allocation.bats 2>&1) && test "$(printf '%s\n' "$o" | grep -cE '^not ok')" -eq 0 && test "$(printf '%s\n' "$o" | grep -cE '^ok ')" -ge 15

- [ ] T21 — RED: a rejected synthesis must stop the whole publish sequence (AC9a, AC9b)
  done: $ grep -qF '@test "a staged synthesis with no Reviewers section is refused and nothing is published"' tests/hooks/spec-review-round-runbook.bats && grep -qF '@test "a staged synthesis whose Reviewers table has no Vendor column is refused"' tests/hooks/spec-review-round-runbook.bats && grep -qF '@test "a well-formed staged synthesis is published"' tests/hooks/spec-review-round-runbook.bats && grep -qF '@test "a refused synthesis leaves review.md and review-snapshot.md byte-identical"' tests/hooks/spec-review-round-runbook.bats && grep -qF '@test "a refused synthesis stamps no fingerprint and does not promote status"' tests/hooks/spec-review-round-runbook.bats && grep -qF '@test "a refused synthesis reports the same quorum result as a well-formed one"' tests/hooks/spec-review-round-runbook.bats && grep -qF '@test "removing the table validation lets the omitted-section case through"' tests/hooks/spec-review-round-runbook.bats && grep -qF '@test "restoring the publish-then-finalize order lets the snapshot advance"' tests/hooks/spec-review-round-runbook.bats

- [ ] T22 — GREEN: stage, validate, then publish (AC9a, AC9b)
  - [ ] T22.a — `review_reviewers_table_valid` emits `ok` or one named reason as data
  - [ ] T22.b — `review_finalize_round` takes an optional staged candidate, validates before any durable write, and on failure leaves `review.md` + `review-snapshot.md` byte-identical, stamps no fingerprint, promotes no status, and leaves the quorum calculation unchanged
  - [ ] T22.c — `skills/review-round/SKILL.md` stages `$ROUND_DIR/review.candidate.md` instead of writing `review.md`
  - [ ] T22.d — all four review command bodies pass the staged candidate
  done: $ grep -q '^review_reviewers_table_valid()' commands/spec/review.lib.sh && grep -qF 'reviewers-table-missing' commands/spec/review.lib.sh && test "$(grep -c 'review_reviewers_table_valid' commands/spec/review.lib.sh)" -ge 2 && grep -qF 'review.candidate.md' skills/review-round/SKILL.md && test "$(grep -c 'review.candidate.md' commands/spec/review.md commands/spec/review-code.md commands/arch/review.md commands/pm/review.md | grep -c ':0')" -eq 0 && o=$(PATH="$PWD/bin:$PATH" bats tests/hooks/spec-review-round-runbook.bats 2>&1) && test "$(printf '%s\n' "$o" | grep -cE '^not ok')" -eq 0 && test "$(printf '%s\n' "$o" | grep -cE '^ok ')" -ge 72

- [ ] T23 — RED: the changed helper BODIES run under bash and zsh (AC10)
  done: $ grep -qF 'parity_lib' tests/hooks/spec-review-shell-parity.bats && grep -qF '@test "the parity harness detects a difference in an extra lib too"' tests/hooks/spec-review-shell-parity.bats && grep -qF '@test "spec_new_next_id agrees across shells"' tests/hooks/spec-review-shell-parity.bats && grep -qF '@test "review_round_quarantine agrees across shells"' tests/hooks/spec-review-shell-parity.bats && grep -qF '@test "review_round_quarantine_resolve agrees across shells on a legacy block"' tests/hooks/spec-review-shell-parity.bats && grep -qF '@test "the sweep'"'"'s missing-cwd diagnostic agrees across shells"' tests/hooks/spec-review-shell-parity.bats

- [ ] T24 — GREEN: the new and changed helpers behave identically in zsh (AC10)
  done: $ o=$(PATH="$PWD/bin:$PATH" bats tests/hooks/spec-review-shell-parity.bats 2>&1) && test "$(printf '%s\n' "$o" | grep -cE '^not ok')" -eq 0 && test "$(printf '%s\n' "$o" | grep -cE '^ok ')" -ge 24 && test "$(printf '%s\n' "$o" | grep -c '# skip')" -eq 0

- [ ] T25 — REFACTOR: one shared cwd-recording stub `node` for the three lifecycle files
  done: $ test -f tests/hooks/stubs/codex-companion-cwd-stub.sh && test "$(grep -c 'codex-companion-cwd-stub' tests/hooks/live-codex-smoke.bats tests/hooks/spec-review-codex.bats tests/hooks/spec-review-round-lifecycle.bats | grep -c ':0')" -eq 0 && o=$(PATH="$PWD/bin:$PATH" bats tests/hooks/live-codex-smoke.bats tests/hooks/spec-review-codex.bats tests/hooks/spec-review-round-lifecycle.bats 2>&1) && test "$(printf '%s\n' "$o" | grep -cE '^not ok')" -eq 0

- [ ] T26 — Close gate: the whole bats suite, the Go suite, drift, task structure, `bin/` uncommitted (AC10)
  - [ ] T26.a — full `tests/hooks/` suite green, no `not ok`
  - [ ] T26.b — `go test -C tools -count=1 ./...` green
  - [ ] T26.c — `speccraft-drift scan-all` clean and `bin/` / `tools/bin/` uncommitted
  done: $ o=$(PATH="$PWD/bin:$PATH" bats tests/hooks/ 2>&1) && test "$(printf '%s\n' "$o" | grep -cE '^not ok')" -eq 0 && test "$(printf '%s\n' "$o" | grep -cE '^ok ')" -ge 1140 && go test -C tools -count=1 ./... >/dev/null && PATH="$PWD/bin:$PATH" speccraft-drift scan-all >/dev/null && PATH="$PWD/bin:$PATH" speccraft-state tasks-verify specs/0055-live-smoke-defect-sweep/tasks.md && test -z "$(git status --porcelain bin/ tools/bin/)"

- [ ] T27 — MANUAL, credit-spending: the gated live smoke, `claude plugin validate`, and the macOS CI leg (AC2, AC7, AC10)
  - [ ] T27.a — `SPECCRAFT_LIVE_CODEX_SMOKE=1 bats tests/hooks/live-codex-smoke.bats` on a credentialed host: both AC26 and AC26a pass, and AC26a observes a non-terminal status before the cancel and `cancelled` after
  - [ ] T27.b — `claude plugin validate` reports no unquoted-placeholder warning
  - [ ] T27.c — the macOS CI jobs green on the branch
  done: $ grep -qE '^- AC26 live smoke:' specs/0055-live-smoke-defect-sweep/changelog.md && grep -qE 'pre-cancel status: (queued|running)' specs/0055-live-smoke-defect-sweep/changelog.md && grep -qE 'post-cancel status: cancelled' specs/0055-live-smoke-defect-sweep/changelog.md && grep -qE '^- claude plugin validate: no unquoted-placeholder warning' specs/0055-live-smoke-defect-sweep/changelog.md && grep -qE '^- macOS CI run:' specs/0055-live-smoke-defect-sweep/changelog.md
