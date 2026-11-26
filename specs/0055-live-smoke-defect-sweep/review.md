---
spec: "0055"
reviewers: [codex-plugin]
quorum: 1
verdict: changes-requested
generated: 2026-11-26T00:00:00Z
---

# Cross-model review — 0055

## Reviewers

| Agent | Verdict | Mode | Model | Vendor |
|---|---|---|---|---|
| codex-plugin | changes-requested | codex-plugin | inherit | openai |

## codex-plugin

Round-report fields: mode=codex-plugin, model=inherit, vendor=openai

**Verdict:** changes-requested

Concerns:
- AC3 fixes dispatch through cancellation, but quarantine recovery still looks up jobs using the resolver's ambient cwd. A job launched outside the repo can remain quarantined after it stops because the resolver queries the wrong store.
- AC8a promises continuing ID uniqueness, but AC8 separates computing the next ID from creating the spec. Concurrent spec:new calls can choose the same ID and create different slugs with that prefix. The standing check detects the collision only after creation.
- AC5 leaves "same verdict" ambiguous. The corpus test should pass at both override values, while the adapter should return refuse:argv-limit below the payload size and ok above it. The specified branch can skip checking the second outcome altogether.
- AC2 can report confirmed cancellation for a job that completed or failed before cancel ran. The helper accepts any terminal status, and the smoke prints a reminder to verify the outcome without making that verification part of the pass condition.

Suggestions:
- For AC1 and AC3, pin the job-store cwd across launch, completion, timeout, cancellation confirmation, and quarantine recovery. Run the live harness from an unrelated directory in the stub test and assert what the companion receives at every stage.
- For AC8, serialize allocation and spec creation per repository, or recheck and retry on contention. Add a two-creator fixture with distinct slugs and define what happens when 9999 is already occupied.
- For AC5, exercise the same predicate used by the live corpus row at both override values and assert the disposition for each. Control the effective payload limit in the fixture because payload refusal takes precedence.
- For AC6, qualify reproducibility on fixed base and HEAD commits. A movable ref can change the merge base, and round cleanup removes the frozen artifact, so describe its lifetime explicitly.

Guardrail violations: none.

Convention violations:
- "A sourced lib must behave identically under bash and zsh, pinned by executing the function bodies in both." Location: ACs 3, 8, and 10. The regression floor names operating systems but does not require executing the changed helper bodies in both shells.
- "A behavioral contract added to a command runbook gets a bats pin against the real function." Location: AC8. The helper test and the absence check for `ls specs/` can both pass if step 4 drops or miscalls the helper.
- "The reserves-specs convention requires spec:new to skip reserved IDs, with manual enforcement until tooling lands." Location: AC8. The unconditional highest-ID-plus-one rule omits the existing reservation check.
- "Prove every negative assertion bites by restoring the forbidden behavior and observing failure." Location: ACs 4, 6, 8 (runbook check), and 9. These absence assertions lack the restoration checks specified for other criteria.

Reviewer prose notes:
- Job ownership: `review_round_quarantine_resolve` already uses the companion installation recorded in each quarantine block. It needs the same treatment for the job-store cwd, with defined behavior for existing blocks that lack that field. Exercise recovery from a different cwd and confirm the correct block is retained while its job is active and cleared when the same job becomes terminal. (commands/spec/review-round.lib.sh:594)
- Allocation: the command already sources `new.lib.sh` for scaffolding. Pin the shipped allocation call along with the scanner, and keep the standing duplicate check as a backstop for manually created or merged specs. The current tree has no duplicate four-digit directory prefixes across the active and archived spec directories. (commands/spec/new.md:43)
- Cancellation evidence: for the credentialed run, record that the job was active before cancellation and that the companion subsequently reported it cancelled. If broker exit is part of the claim, make that observation part of the manual acceptance evidence. The existing terminal-status check also succeeds for ordinary completion. (commands/spec/review-codex.lib.sh:831)

Reference access: `.speccraft/architecture.md` and `.speccraft/conventions.md` read, no failures. payload_sha256 0275f306340faf695f28d6ff99172a44942807f042ea20e29b8762fb89c3f13a.

## Synthesis

Only one reviewer took part, so there is no cross-agent agreement or disagreement to weigh. The orchestrator checked four of the reviewer's claims against the repo, and all four hold.

1. **The `reserves-specs` convention is real.** It is at `.speccraft/conventions.md:1197`, and "spec IDs are never reused" is at :1212. It has been used twice: `0005` reserves `0006`, which is still unused, and `0031` reserves `0032`. An allocator that takes highest-ID-plus-one must therefore skip reserved ids. The AC8 convention violation stands and the spec must fix it.
2. **The quarantine-recovery gap is real (AC3).** `review_round_quarantine_resolve` records and probes a per-block companion `root` but records no job-store cwd. `review_codex_job_status` takes no cwd, so recovery queries the ambient cwd's store. Fixing dispatch through cancellation does not fix recovery. The spec must record the job-store cwd in the quarantine block, pass it to the status call, and define what happens to older blocks that lack the field. It must also test recovery from a different cwd.
3. **The current tree has no duplicate four-digit prefixes** across `specs/` and `specs/.archive/`, which matches the reviewer's statement. Gaps exist at `0006` and `0053`. The gap at `0006` is a reservation, so an allocator that fills gaps would break the convention. The standing duplicate check should stay as a backstop for manually created or merged specs.
4. **"Confirmed cancellation" is weaker than it sounds (AC2).** `review_codex_job_cancel` accepts any terminal status (`completed|failed|cancelled`), so a job that finished normally before cancel ran still passes. The credentialed run must record that the job was active before cancellation and that the companion then reported `cancelled`. If broker exit is part of the claim, that observation must be recorded too.

**Out of scope.** The concern that concurrent `spec:new` invocations could race on an id (AC8a, and the matching suggestion to serialize allocation) is the one finding the orchestrator considers out of scope. `spec:new` is an interactive slash command and has no concurrent invocation path. The spec does not need a lock or a two-creator fixture for it. It is recorded here so it is not silently dropped. The spec may add a one-line non-goal. The reviewer's related point about defining behavior when 9999 is occupied is a cheap edge case and is not covered by this exclusion.

Remaining items for the spec author:
- AC5: define "same verdict" as `refuse:argv-limit` below the payload size and `ok` above it. Run the live corpus predicate at both override values, and control the effective payload limit in the fixture.
- AC6: qualify reproducibility on fixed base and HEAD commits, and state the lifetime of the frozen artifact.
- Convention violations to fix:
  - Execute the changed helper bodies in both bash and zsh (ACs 3, 8, 10).
  - Pin the AC8 runbook step 4 against the real allocation call, not only the helper and an `ls specs/` absence check.
  - Add restoration checks for the absence assertions in ACs 4, 6, 8, and 9.

**Action:** Revise spec 0055 and re-run review. The changes are:
1. In AC3, add the job-store cwd to quarantine blocks and to the recovery path. Define the legacy-block behavior and test recovery from an unrelated cwd.
2. In AC2, add active-before-cancel and reported-cancelled evidence to the manual acceptance record.
3. In AC8, make the allocator skip `reserves-specs` ids, pin the shipped `new.md` allocation call, and keep the duplicate check as a backstop.
4. Tighten AC5 and AC6 as described above.
5. Add the bash and zsh execution pins, and the restoration checks for the negative assertions.
6. Do not add concurrency handling for `spec:new`.
reviewed_sha256: 6db30f13acd27b089bb73496532d710c9c8be91d3676fd043715f1c5bfae1403
