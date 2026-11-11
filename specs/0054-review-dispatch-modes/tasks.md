---
spec: "0054"
contract: done-means-v1
---

# Tasks

- [x] T1 — Re-verify the installed 1.0.6 companion interface and capture the pinned fixtures
  done: $ d=tests/hooks/fixtures/review-dispatch/codex && test -s "$d/printusage-1.0.6.txt" && test -s "$d/task-success-1.0.6.json" && test -x tests/hooks/stubs/stub-node.sh && grep -qF -- 'codex-companion.mjs task [--background]' "$d/printusage-1.0.6.txt" && test "$(grep -cF -- '--prompt-file' "$d/printusage-1.0.6.txt")" -eq 0 && test "$(jq -r '.storedJob.result.status' "$d/task-success-1.0.6.json")" = "0" && test -n "$(jq -r '.storedJob.result.rawOutput' "$d/task-success-1.0.6.json")" && test "$(jq -r 'has("rawOutput")' "$d/task-success-1.0.6.json")" = "false"
- [x] T2 — RED: Go mode enum, omitted-normalizes-to-cli, empty and case-variant rejection
  done: $ test "$(grep -cE '^func Test_LoadConfig_Mode_' tools/internal/delegate/mode_test.go)" -eq 4
- [x] T3 — GREEN: mode validation plus the new Agent fields in toml.go
  done: $ go test -C tools ./internal/delegate/ -run 'Test_LoadConfig_Mode_' -count=1 && grep -q 'SubagentType' tools/internal/delegate/toml.go && grep -q 'PluginRoot' tools/internal/delegate/toml.go
- [x] T4 — RED: strict keys, per-mode enums, new-field decoding and defaults
  done: $ for t in StrictKeys_RejectedOnNewModes Effort_OutsideSixValues_IsNamedError SubagentModel_OutsideFiveValues_IsNamedError NewModeFields_DecodeAndDefault; do grep -qE "^func Test_LoadConfig_$t\(" tools/internal/delegate/mode_test.go || exit 1; done
- [x] T5 — GREEN: validateAgent strict-field and enum arms
  done: $ go test -C tools ./internal/delegate/ -run 'Test_LoadConfig_(StrictKeys|Effort|SubagentModel|NewModeFields)' -count=1
- [x] T6 — RED: unknown keys rejected on new modes, permissive on cli, every real registry still loads
  done: $ for t in UnknownKey_OnNewMode_IsNamedError UnknownKey_OnCLIEntry_StillLoads KnownKey_OnLegacyEntry_IsNotEnumChecked RealRegistries_LoadUnchanged; do grep -qE "^func Test_LoadConfig_$t\(" tools/internal/delegate/mode_test.go || exit 1; done
- [x] T7 — GREEN: per-entry unknown-key scoping via agentKeySets (NOT MetaData.Undecoded — it reports "agents.install_hint" with no element index, so it cannot say which entry carried the key)
  done: $ go test -C tools ./internal/delegate/ -count=1 && grep -q 'knownAgentKeys' tools/internal/delegate/toml.go
- [x] T8 — RED: review_agent_mode rows in spec-review-dispatch.bats
  done: $ for t in 'review_agent_mode returns each of the four valid modes' 'review_agent_mode normalizes an omitted mode to cli' 'review_agent_mode names an error for an explicitly empty mode' 'review_agent_mode names an error for the case variants Subagent and CLI' 'the error names the agent and all four valid modes'; do grep -qxF -- "@test \"$t\" {" tests/hooks/spec-review-dispatch.bats || exit 1; done
- [x] T9 — GREEN: review_agent_mode in review.lib.sh — needs review_agent_keys (NOT review_agent_field, whose awk prints a value only `if (val != "")`, so `mode = ""` and an absent mode are indistinguishable; AC1 requires telling them apart)
  done: $ PATH="$PWD/bin:$PATH" bats tests/hooks/spec-review-dispatch.bats && grep -q 'review_agent_mode()' commands/spec/review.lib.sh
- [x] T10 — RED: the shared parity corpus, driven by the Go loader and the shell reader
  done: $ test -f tests/hooks/fixtures/review-dispatch/registries/expected.txt && test -f tools/internal/delegate/parity_test.go && test "$(ls tests/hooks/fixtures/review-dispatch/registries/reject/*.toml | wc -l)" -eq 11 && test "$(awk '$2 == "reject" {n++} END {print n+0}' tests/hooks/fixtures/review-dispatch/registries/expected.txt)" -eq 11
- [x] T11 — GREEN: the shell reader's strict-key and enum arms reach parity
  done: $ go test -C tools ./internal/delegate/ -run Parity -count=1 && PATH="$PWD/bin:$PATH" bats tests/hooks/spec-review-dispatch.bats
- [x] T12 — RED: review_agent_transport and the 80 KB budget rows
  done: $ for t in 'review_agent_transport returns file for codex-plugin' 'review_agent_transport returns file for subagent' 'review_agent_transport returns the registry input for cli and acp' 'an 80 KB payload is ok for codex-plugin and for subagent' 'the same 80 KB payload is refuse:argv-limit for cli plus argv' 'review_budget_check and review_dispatch_payload keep their 0052 signatures'; do grep -qxF -- "@test \"$t\" {" tests/hooks/spec-review-dispatch.bats || exit 1; done
- [x] T13 — GREEN: review_agent_transport — acp returns `acp`, NOT its absent `input` (which review_budget_check would normalize to stdin, exempting the one mode most likely to overflow argv)
  done: $ o=$(PATH="$PWD/bin:$PATH" bats tests/hooks/spec-review-dispatch.bats -f 'transport|80 KB|signatures' 2>&1) && test "$(printf '%s\n' "$o" | grep -cE '^ok ')" -ge 6 && p=$(PATH="$PWD/bin:$PATH" bats tests/hooks/spec-review-payload.bats -f budget 2>&1) && test "$(printf '%s\n' "$p" | grep -cE '^ok ')" -ge 4
- [x] T14 — RED: review_with_deadline returns 124, leaves no child, uses no timeout(1)
  done: $ test -f tests/hooks/spec-review-codex.bats && for t in 'review_with_deadline returns 124 when the deadline expires' 'review_with_deadline leaves no process from the killed tree alive' 'review_with_deadline kills the whole descendant tree, not just the job it launched' "review_with_deadline returns the command's own status when it finishes first" 'review_with_deadline names an error for a non-positive deadline' 'review_with_deadline uses no timeout(1)' 'review_with_deadline uses no wait -n, which zsh does not support' 'review_with_deadline works when EXECUTED under real zsh, not merely sourced'; do grep -qxF -- "@test \"$t\" {" tests/hooks/spec-review-codex.bats || exit 1; done
- [x] T15 — GREEN: review_with_deadline
  done: $ o=$(PATH="$PWD/bin:$PATH" bats tests/hooks/spec-review-codex.bats -f review_with_deadline 2>&1) && test "$(printf '%s\n' "$o" | grep -cE '^ok ')" -ge 14 && grep -q 'review_with_deadline()' commands/spec/review.lib.sh
- [x] T16 — RED: review_codex_plugin_root, all resolution and version rows including AC5a and AC5d
  done: $ grep -q 'claude-plugin/plugin.json' tests/hooks/spec-review-codex.bats && for t in 'review_codex_plugin_root: an explicit plugin_root wins over installed_plugins.json' 'review_codex_plugin_root: the local-scope entry whose projectPath is the repo root wins' 'review_codex_plugin_root: a local entry for a DIFFERENT project does not win' 'review_codex_plugin_root: a root without scripts/codex-companion.mjs is companion-missing' 'review_codex_plugin_root: no codex@openai-codex entry at all is not-installed' 'review_codex_plugin_root: a version below the range is unsupported-companion <version>' 'review_codex_plugin_root: an absent version is unknown-version' 'review_codex_plugin_root: an unparseable version is unknown-version' 'review_codex_plugin_root: the reason token is exactly one of the four, never concatenated' 'review_codex_plugin_root: an explicit root absent from installed_plugins.json reads its own manifest' 'review_codex_plugin_root: a root present in BOTH sources reads installed_plugins.json' 'review_codex_plugin_root: a manifest present but unparseable is unknown-version' 'review_codex_plugin_root: a companion whose help omits the flags still resolves' 'review_codex_plugin_root: resolution invokes no help or --help subcommand'; do grep -qxF -- "@test \"$t\" {" tests/hooks/spec-review-codex.bats || exit 1; done
- [x] T17 — GREEN: review_codex_plugin_root with per-resolution-path version discovery
  done: $ o=$(PATH="$PWD/bin:$PATH" bats tests/hooks/spec-review-codex.bats -f review_codex_plugin_root 2>&1) && test "$(printf '%s\n' "$o" | grep -cE '^ok ')" -ge 20 && test "$(printf '%s\n' "$o" | grep -cE '^not ok')" -eq 0 && grep -q 'review_codex_plugin_root()' commands/spec/review.lib.sh && grep -q '_review_codex_version_for_root()' commands/spec/review.lib.sh
- [x] T18 — RED: review_codex_preflight and its per-resolved-root memoization
  done: $ grep -q 'symlink' tests/hooks/spec-review-codex.bats && for t in 'review_codex_preflight: ready true returns zero' 'review_codex_preflight: ready false is non-zero and names not-ready with the reason' 'review_codex_preflight: an unready companion is codex-plugin-unavailable, never codex-output-unparseable' 'review_codex_preflight: unparseable setup output is still codex-plugin-unavailable' 'review_codex_preflight: two calls on the same root run setup ONCE' 'review_codex_preflight: two DIFFERENT roots run setup once each' 'review_codex_preflight: two spellings of one root via a symlink run setup ONCE' 'review_codex_preflight: readiness is never assumed across roots' 'review_codex_preflight: a failed preflight is memoized too, not retried' 'review_codex_preflight: setup is invoked with --json, not the rendered form'; do grep -qxF -- "@test \"$t\" {" tests/hooks/spec-review-codex.bats || exit 1; done
- [x] T19 — GREEN: review_codex_preflight, memo key formed after canonicalization
  done: $ o=$(PATH="$PWD/bin:$PATH" bats tests/hooks/spec-review-codex.bats -f review_codex_preflight 2>&1) && test "$(printf '%s\n' "$o" | grep -cE '^ok ')" -ge 11 && test "$(printf '%s\n' "$o" | grep -cE '^not ok')" -eq 0 && grep -q 'review_codex_preflight()' commands/spec/review.lib.sh && grep -q '_review_codex_memo_init()' commands/spec/review.lib.sh
- [ ] T20 — RED: review_codex_task_argv exact argv, conditional flags, three negatives, inode proof
  done: $ grep -q 'resume-last' tests/hooks/spec-review-codex.bats && grep -q -- '-ef' tests/hooks/spec-review-codex.bats
- [ ] T21 — GREEN: review_codex_task_argv
  done: $ PATH="$PWD/bin:$PATH" bats tests/hooks/spec-review-codex.bats -f task_argv
- [ ] T22 — RED: review_parse_codex_task_output, total over exit status x JSON validity x fields
  done: $ grep -q 'completed' tests/hooks/spec-review-codex.bats && grep -q 'codex-task-error' tests/hooks/spec-review-codex.bats
- [ ] T23 — GREEN: review_parse_codex_task_output with the explicit exit-status parameter
  done: $ PATH="$PWD/bin:$PATH" bats tests/hooks/spec-review-codex.bats -f parse_codex
- [ ] T24 — RED: job lifecycle, one cancel, one confirming status, codex-cancel-unconfirmed
  done: $ grep -q 'codex-cancel-unconfirmed' tests/hooks/spec-review-codex.bats
- [ ] T25 — GREEN: the four job helpers and the polling driver
  done: $ PATH="$PWD/bin:$PATH" bats tests/hooks/spec-review-codex.bats && grep -q 'review_codex_job_cancel()' commands/spec/review*.lib.sh
- [ ] T26 — RED: the unavailable round and the three router rows
  done: $ grep -q 'codex-plugin-unavailable' tests/hooks/spec-review-codex.bats && grep -q 'review_dispatch_agent' tests/hooks/spec-review-dispatch.bats
- [ ] T27 — GREEN: review_dispatch_agent and the /codex:setup message
  done: $ PATH="$PWD/bin:$PATH" bats tests/hooks/spec-review-codex.bats tests/hooks/spec-review-dispatch.bats && grep -q 'review_dispatch_agent()' commands/spec/review.lib.sh
- [ ] T28 — REFACTOR: extract commands/spec/review-codex.lib.sh
  done: $ test -f commands/spec/review-codex.lib.sh && grep -q 'BASH_SOURCE\[0\]:-\$0' commands/spec/review-codex.lib.sh && PATH="$PWD/bin:$PATH" bats tests/hooks/lib-zsh-safety.bats tests/hooks/spec-review-codex.bats
- [ ] T29 — RED: AC8 payload-end rows for the full and scoped branches
  done: $ test -f tests/hooks/spec-review-payload-boundary.bats
- [ ] T30 — GREEN: normalize both payload ends on every composer branch
  done: $ PATH="$PWD/bin:$PATH" bats tests/hooks/spec-review-payload-boundary.bats tests/hooks/spec-review-payload.bats
- [ ] T31 — RED: round dir create, publish, gitignore, cleanup refusals, AC14e expiries
  done: $ test -f tests/hooks/spec-review-round-dir.bats && test -f tests/hooks/fixtures/review-dispatch/legacy-repo/gitignore.pre0054
- [ ] T32 — GREEN: review_round_dir_create, review_round_lease_write, review_round_cleanup
  done: $ PATH="$PWD/bin:$PATH" bats tests/hooks/spec-review-round-dir.bats && grep -q 'building-' commands/spec/review*.lib.sh
- [ ] T33 — RED: lease-based sweeping, never age-based, plus the publish race
  done: $ grep -q 'max-age' tests/hooks/spec-review-round-dir.bats && grep -q 'review_round_sweep' tests/hooks/spec-review-round-dir.bats
- [ ] T34 — GREEN: review_round_sweep reading the expiry off the .building name
  done: $ PATH="$PWD/bin:$PATH" bats tests/hooks/spec-review-round-dir.bats && grep -q 'review_round_sweep()' commands/spec/review*.lib.sh
- [ ] T35 — RED: quarantine records, cleanup refusal, sweep report, per-mode resolution
  done: $ grep -q 'quarantined' tests/hooks/spec-review-round-dir.bats && grep -q 'lease-expired' tests/hooks/spec-review-round-dir.bats
- [ ] T36 — GREEN: the quarantine helpers and their sweep integration
  done: $ PATH="$PWD/bin:$PATH" bats tests/hooks/spec-review-round-dir.bats && grep -q 'review_round_quarantine()' commands/spec/review*.lib.sh
- [ ] T37 — RED: review_tree_snapshot, four required rows, four-entry closed exclusion set
  done: $ test -f tests/hooks/spec-review-tree-snapshot.bats && grep -q 'exclude-standard' tests/hooks/spec-review-tree-snapshot.bats && grep -q 'tools/bin/probe' tests/hooks/spec-review-tree-snapshot.bats
- [ ] T38 — GREEN: review_tree_snapshot, content-aware and per-file
  done: $ PATH="$PWD/bin:$PATH" bats tests/hooks/spec-review-tree-snapshot.bats tests/hooks/portability-guard.bats && grep -q 'review_tree_snapshot()' commands/spec/review*.lib.sh
- [ ] T39 — REFACTOR: extract commands/spec/review-round.lib.sh
  done: $ test -f commands/spec/review-round.lib.sh && grep -q 'BASH_SOURCE\[0\]:-\$0' commands/spec/review-round.lib.sh && PATH="$PWD/bin:$PATH" bats tests/hooks/lib-zsh-safety.bats tests/hooks/spec-review-round-dir.bats
- [ ] T40 — RED: the shared runbook and the four command files (markdown)
  done: $ test -f tests/hooks/spec-review-round-runbook.bats && ! test -f skills/review-round/SKILL.md
- [ ] T41 — GREEN: write skills/review-round/SKILL.md and point all four commands at it
  done: $ PATH="$PWD/bin:$PATH" bats tests/hooks/spec-review-round-runbook.bats && grep -q TaskStop commands/spec/review.md && grep -q TaskStop commands/arch/review.md && grep -q TaskStop commands/pm/review.md && grep -q TaskStop commands/spec/review-code.md
- [ ] T42 — RED: payload_sha256, permission_denied, and the five-template round trip
  done: $ test -f tests/hooks/spec-review-attestation.bats && grep -q 'payload_sha256' tests/hooks/spec-review-attestation.bats
- [ ] T43 — GREEN: the validator's subagent arm and the five prompt templates
  done: $ PATH="$PWD/bin:$PATH" bats tests/hooks/spec-review-attestation.bats tests/hooks/spec-review-diff.bats && grep -q 'payload_sha256' templates/prompts/review.md && test -f templates/prompts/review-code.md && test -f templates/prompts/arch-review.md && test -f templates/prompts/pm-review.md
- [ ] T44 — RED: review-code freezes ONE diff and states the untracked exclusion
  done: $ test -f tests/hooks/spec-review-code.bats && grep -q 'untracked' tests/hooks/spec-review-code.bats
- [ ] T45 — GREEN: review_freeze_diff and the review-code body
  done: $ PATH="$PWD/bin:$PATH" bats tests/hooks/spec-review-code.bats && grep -q 'review_freeze_diff()' commands/spec/review*.lib.sh
- [ ] T46 — RED: AC8 for the arch, pm and review-code branches, plus AC17 distinct artifacts
  done: $ grep -q 'arch' tests/hooks/spec-review-payload-boundary.bats && grep -q 'byte-identical' tests/hooks/spec-review-round-runbook.bats
- [ ] T47 — GREEN: composer --label and review_hash_compare_outputs
  done: $ PATH="$PWD/bin:$PATH" bats tests/hooks/spec-review-payload-boundary.bats tests/hooks/spec-review-payload.bats && grep -q 'review_hash_compare_outputs()' commands/spec/review.lib.sh
- [ ] T48 — RED: arch and pm write review.md only on a complete round
  done: $ grep -q 'byte-unchanged' tests/hooks/spec-review-round-runbook.bats
- [ ] T49 — GREEN: review_finalize_round gains an optional kind parameter
  done: $ PATH="$PWD/bin:$PATH" bats tests/hooks/spec-review-round-runbook.bats tests/hooks/spec-review-payload.bats
- [ ] T50 — RED: agents/reviewer.md shape and the reviewer-vs-synthesizer contrast (markdown)
  done: $ test -f tests/hooks/review-subagent-agent.bats && ! test -f agents/reviewer.md
- [ ] T51 — GREEN: agents/reviewer.md plus the cross-reviewer and SKILL.md amendments
  done: $ PATH="$PWD/bin:$PATH" bats tests/hooks/review-subagent-agent.bats && grep -q 'model: inherit' agents/reviewer.md
- [ ] T52 — RED: custom subagent_type lacking Write, declaring Edit, or unknown
  done: $ test -f tests/hooks/spec-review-subagent.bats && grep -q 'missing-write-tool' tests/hooks/spec-review-subagent.bats
- [ ] T53 — GREEN: review_subagent_preflight
  done: $ PATH="$PWD/bin:$PATH" bats tests/hooks/spec-review-subagent.bats -f subagent_preflight && grep -q 'review_subagent_preflight()' commands/spec/review*.lib.sh
- [ ] T54 — RED: TaskStop timeout, stop-failed, late-completion, subagent-no-output
  done: $ grep -q 'late-completion' tests/hooks/spec-review-subagent.bats && grep -q 'subagent-no-output' tests/hooks/spec-review-subagent.bats
- [ ] T55 — GREEN: the subagent record, collect and deadline helpers plus the runbook protocol
  done: $ PATH="$PWD/bin:$PATH" bats tests/hooks/spec-review-subagent.bats && grep -q 'review_subagent_collect()' commands/spec/review*.lib.sh
- [ ] T56 — RED: attribution over the snapshot interval with two concurrent subagents
  done: $ grep -q 'unattributed' tests/hooks/spec-review-subagent.bats
- [ ] T57 — GREEN: review_attribute_tree_writes
  done: $ PATH="$PWD/bin:$PATH" bats tests/hooks/spec-review-subagent.bats && grep -q 'review_attribute_tree_writes()' commands/spec/review*.lib.sh
- [ ] T58 — RED: review_agent_vendor rows, quorum rows, single_vendor_approval rows
  done: $ test -f tests/hooks/spec-review-vendor.bats && grep -q 'single_vendor_approval' tests/hooks/spec-review-vendor.bats
- [ ] T59 — GREEN: review_agent_vendor, review_single_vendor_approval, the recorded fields
  done: $ PATH="$PWD/bin:$PATH" bats tests/hooks/spec-review-vendor.bats && grep -q 'review_agent_vendor()' commands/spec/review.lib.sh && grep -q 'single_vendor_approval' agents/cross-reviewer.md
- [ ] T60 — RED: spec:delegate and aux-delegator refuse the review-only modes
  done: $ test -f tests/hooks/review-only-mode-refusal.bats && grep -q 'unsupported-mode' tests/hooks/review-only-mode-refusal.bats
- [ ] T61 — GREEN: review_refuse_review_only_mode plus the two consumer doc edits
  done: $ PATH="$PWD/bin:$PATH" bats tests/hooks/review-only-mode-refusal.bats && grep -q 'review-only dispatch mode' commands/spec/review.lib.sh && grep -q 'unsupported-mode' agents/aux-delegator.md && grep -q 'unsupported-mode' commands/spec/delegate.md
- [ ] T62 — RED: template, conventions and SKILL.md assertions (markdown/TOML)
  done: $ test -f tests/hooks/review-dispatch-docs.bats && test -f tools/internal/delegate/template_test.go
- [ ] T63 — GREEN: the shipped template, the convention clarification and the skill
  done: $ PATH="$PWD/bin:$PATH" bats tests/hooks/review-dispatch-docs.bats && go test -C tools ./internal/delegate/ -count=1 && grep -q 'codex-plugin' templates/speccraft/agents.toml && grep -q 'subagent' templates/speccraft/agents.toml
- [ ] T64 — RED: cleanup on every exit path, never while a reviewer is pending
  done: $ test -f tests/hooks/spec-review-round-lifecycle.bats && grep -q 'pending' tests/hooks/spec-review-round-lifecycle.bats
- [ ] T65 — GREEN: review_round_all_terminal plus the runbook cleanup gate
  done: $ PATH="$PWD/bin:$PATH" bats tests/hooks/spec-review-round-lifecycle.bats && grep -q 'review_round_all_terminal()' commands/spec/review-round.lib.sh
- [ ] T66 — RED: the lease expiry is byte-identical across a round, and four bounded paths survive a concurrent sweep
  done: $ grep -q 'byte-identical' tests/hooks/spec-review-round-lifecycle.bats && grep -q 'review_round_lease_renew' tests/hooks/spec-review-round-lifecycle.bats
- [ ] T67 — GREEN: lease margin arithmetic, no re-stamp on any path
  done: $ PATH="$PWD/bin:$PATH" bats tests/hooks/spec-review-round-lifecycle.bats && ! grep -q 'review_round_lease_renew()' commands/spec/review-round.lib.sh
- [ ] T68 — REFACTOR: one outcome-token table, pinned by a source-scan assertion
  done: $ PATH="$PWD/bin:$PATH" bats tests/hooks/ && grep -c '_REVIEW_OUTCOME_TOKENS' commands/spec/review.lib.sh
- [ ] T69 — RED: the gated live-smoke harness that skips by name (NON-CI)
  done: $ test -f tests/hooks/live-codex-smoke.bats && grep -q 'SPECCRAFT_LIVE_CODEX_SMOKE' tests/hooks/live-codex-smoke.bats
- [ ] T70 — GREEN: the two gated bodies plus the self-naming skip (NON-CI)
  done: $ PATH="$PWD/bin:$PATH" bats tests/hooks/live-codex-smoke.bats 2>&1 | grep -q 'skipped'
- [ ] T71 — Close gate: both suites green on Linux and macOS, the 0052 floor unedited, bin/ uncommitted, the gated skips named in the log
  done: $ PATH="$PWD/bin:$PATH" bats tests/hooks/ && go test -C tools ./... && GOOS=windows go build -C tools ./... && test -z "$(git status --porcelain bin/ tools/bin/)" && git diff --quiet HEAD -- tests/hooks/spec-review-payload.bats
