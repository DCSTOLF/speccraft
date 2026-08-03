# History

Append-only. Newest first.

## 2026-08-03 — Release 1.15.0: workspace sync — design-level consolidation & ledger-row archival (spec 0044)

**Spec:** specs/0044-workspace-sync-design-consolidation/ (status: closed; `informed-by: design/0001`). Completes the workspace-sync arc (A+B in 0043, **C** here). 0043 reconciled the ledger but it only ever *grows* — every design the conductor drives leaves a permanent per-member section in `.speccraft/ledger.md` long after it is fully `done`.
**Decision:** Add a confirm-gated **design-consolidation pass (`W4`)** to `/speccraft:sync`'s workspace branch: for every design `reconcile` reports `done`, fold it into a durable colocated `design/<id>-<slug>/outcome.md` rollup and **archive its ledger rows** out of the live ledger into a sibling `.speccraft/ledger.archive.md` (same grammar, `ParseLedger`-valid) — bounding the live ledger as designs accumulate (workspace analog of spec consolidation). Three flagged OQs resolved with the user (colocated outcome.md via a `sync_resolve_design_dir` glob resolver, sibling archive file, `W4`-in-sync not a separate command). New sanctioned Go op **`speccraft-state ledger-archive <design> [--expect <fp>]`** — the single-read atomic authority: four-case contract on a **text-level presence check** (so `Reconcile`'s vacuous-done-for-absent never leaks — present+done→archive, present+not-done→refuse+name members, absent-live+in-archive→idempotent no-op, absent-both→`unknown design`), a byte-level **section splice** (untouched designs byte-identical, not a re-serialize), transactional **append-archive-first/remove-live-second** with both-present crash recovery, and an **`--expect` compare-and-set** closing the caller→op handoff. Lives in the cmd package (rides the `run()` seam) → **override budget 0**; `reconcileCmd` refactored onto a shared `reconcileOutput` so the fingerprint = `reconcile | sha256sum`. Five pure `sync.lib.sh` helpers (`sync_resolve_design_dir`/`sync_design_fingerprint`/`sync_design_rollup_body`/`sync_done_live_designs`/`sync_consolidate_design`) + the `W4` runbook. **Crash-safety** via a fingerprinted `consolidated:` marker: `outcome.md` written before archival; recorded iff its marker fingerprint equals the current per-design fingerprint (missing/stale → atomic rewrite), so the durable record never describes an older snapshot than the archived rows.
**Review.** Four-round cross-model (codex + claude-p, converging): codex drove the vacuous-done→four-case contract, the non-transactional move→append-first/remove-second state machine, the byte-identity overclaim→section splice, cross-run skew→fingerprinted marker, and the caller→op TOCTOU→`--expect` atomic CAS. The residual concurrent-writer race (op read→rename is not a filesystem CAS) is **bounded + deferred** — the identical single-writer limitation every ledger writer has, and 0043's ratified scope; a workspace-wide lock / `--expect-bytes` CAS across all writers is the follow-up. claude-p approve-with-comments.
**Release.** Minor bump 1.14.0 → 1.15.0 via the renamed-version-test technique (six single-source locations, NO override); `go test ./...`+`go vet` green, 282 bats green, drift clean, all four workspace e2e pass (new `workspace_consolidate_cycle.sh`), binaries report 1.15.0. Push + tag `v1.15.0` triggers the release pipeline (spec 0021).

## 2026-07-31 — Release 1.14.0: workspace sync — ledger + membership drift reconciliation (spec 0043)

**Spec:** specs/0043-workspace-sync/ (status: closed; `informed-by: design/0001-architect-lifecycle-orchestration`). `/speccraft:init --workspace` (0042) *creates* a workspace and `/speccraft:arch:orchestrate` (0039/0040) *drives* it, keeping the ledger current only while it runs. But a developer who closes a member spec by hand, runs `spec:implement` directly in a member, or adds/removes a child repo leaves the workspace's own memory (`.speccraft/ledger.md` + `workspace.yml`) silently wrong — there was no out-of-band "make belief match reality" pass, the workspace analog of `/speccraft:sync`.
**Decision:** Give `/speccraft:sync` a **kind-branch** (auto-detected via the 0042 `config-kind` oracle): `repo` runs the unchanged repo flow; `workspace` reconciles **ledger drift (class B)** + **membership drift (class A)**. The core insight — **ledger drift is out-of-band re-entry**: spec 0040's `orch_reentry` already answers "does the member's live status prove this phase completed?", so sync asks it for every member of every design and an `adopt` verdict means the ledger is behind reality. The MVP reuses the tested token machine (`orch_reentry`/`orch_status_token`/`orch_next_phase`) + `ws_detect_members` wholesale, adding one read-only Go oracle **`speccraft-state ledger-get [<design>]`** (raw stored pointer fields — `reconcile` only exposes *computed* status; rides the `run()` seam → **override budget 0**), a pure `commands/sync.lib.sh` (`sync_status_ahead`/`sync_stale_in_flight`/`sync_ledger_drift`/`sync_membership_audit`/`sync_apply_member_plan`), and a `commands/sync.md` branch with `<!-- speccraft:sync:repo|workspace -->` anchors. Contracts: tool-managed ledger fixes are auto-applied (via `ledger-set`) while curated `workspace.yml` + dangling spec refs are **advisory only**; live-run-**conservative** (clear an `in_flight` only when `orch_reentry` says `adopt`, never a not-yet-reflected marker); a conflict-safe per-member **plan** re-reads + byte-compares the row once before applying (row changed since detection → `conflict`, no write; residual TOCTOU window + true CAS deferred); structured 6-field findings parsed with `awk -F '\t'` (never `IFS=$'\t' read`, which drops the meaningful empty columns); parse-level ledger corruption fails `ledger-get` globally while a *parsed* bad-token row is a per-member `malformed-row` advisory (row isolated).
**Review.** Three-round cross-model (codex + claude-p, both converging on the top issues): codex opened `changes-requested` and drove real hardening — the detect→apply race → the AC10 per-member-plan conflict guard; findings-as-rendered-commands → a structured argv-safe record (apply passes field/value as argv, never `eval`s `<detail>`); the AC8+AC10 self-conflict → captured-snapshot batch apply with no precondition re-derivation; TSV empty-field parsing pinned to `awk -F '\t'`; parse-vs-semantic malformation split; bounded live-run claim. claude-p approved-with-comments throughout. Full trail in review.md (`reviewed_sha256` stamped).
**Release.** Minor bump 1.13.0 → 1.14.0 via the renamed-version-test technique across the six single-source locations (3 Go `const version` → `…Is1140`, stale-guard now rejects 1.13.0, NO override; manifest version test → `…VersionIs1140`; plugin.json + marketplace.json). `go test ./...` + `go vet` green; 270 bats green; drift clean; both hermetic workspace e2e (`workspace_init_cycle.sh` regression + new `workspace_sync_cycle.sh`) pass; binaries rebuilt report 1.14.0. Push + tag `v1.14.0` triggers the auto-tag → release.yml → verify-release pipeline (spec 0021). Follow-ups: class C (design-level consolidation/rollup) is the next spec; `--recursive` fan-out and a true `ledger-set --expect` CAS are deferred.

## 2026-07-29 — Release 1.13.0: init --workspace scaffolds a workspace root (spec 0042)

**Spec:** specs/0042-init-workspace/ (status: closed; `informed-by: design/0001-architect-lifecycle-orchestration`). Closes the last gap in the conductor arc: 0037–0041 taught the tooling to *read/drive* a workspace (`kind = "workspace"`, `workspace.yml`, `ledger.md`), but nothing *created* one — `/speccraft:init` only ever produced a `repo`-kind bootstrap.
**Decision:** Add a `--workspace` mode to `/speccraft:init` that WRITES the two artifacts the existing readers already parse — a `speccraft.toml` with `kind = "workspace"` and a canonical `workspace.yml` manifest — plus a workspace-flavored `.speccraft/` set. Readers (`config.go`/`workspace_topology.go`/`ledger.go`) are untouched. Deterministic mechanics are five pure `commands/init.lib.sh` helpers (`ws_arg_parse`, `ws_toml_body`, `ws_manifest_body`, `ws_detect_members`, `ws_write_root`) backed by 26 bats; the model-driven per-candidate approval prompt lives in `commands/init.md` and is fenced by a source-scan + the hermetic `tests/e2e/workspace_init_cycle.sh`. Two new `speccraft-state` oracle subcommands — `config-kind` (strict kind, gated on `.speccraft/` presence) and `find-workspace-root` — were required because `list-members` can't discriminate a workspace root from a repo root; both ride the `run()` seam so the whole spec shipped with **override budget 0**. Key contracts: lazy ledger (never created by init), manifest-before-toml write ordering (no orphan `kind = "workspace"`), curated `workspace.yml` preserved on `--force`, and an explicit `repo → workspace` migration refusal (out of scope).
**Review.** Two-round cross-model (codex + claude-p): round 1 `changes-requested` → 8 fixes (per-file `--force` matrix, AC3a/AC3b tier split, structural AC5 marker, pinned canonical `workspace.yml`, narrowed AC8, argument parsing, named helpers); round 2 confirmed all resolved and caught the AC9 two-file-atomicity overclaim (reworded to the honest one-directional invariant).
**Release.** Minor bump 1.12.0 → 1.13.0 via the renamed-version-test technique across the six single-source locations (3 Go `const version` → `…Const1130`/`…Is1130`, stale-guard now rejects 1.12.0, NO override; `manifest_version_test.go` → `…VersionIs1130`; plugin.json + marketplace.json). `go test ./...` + `go vet` green; 241 bats green; drift clean; binaries rebuilt report 1.13.0. Push + tag `v1.13.0` triggers the auto-tag → release.yml → verify-release.sh pipeline (spec 0021).

## 2026-07-29 — Release 1.12.0: bundle the design-0001 conductor arc (spec 0041)

**Spec:** specs/0041-release-1-12-0/ (status: closed). Minor version bump 1.11.0 → 1.12.0 packaging specs 0037–0040 (workspace topology, ledger+reconcile, the arch:orchestrate conductor, crash-safe re-entry), each of which closed without a bump by design. Six locations via the established single-source pattern: 3 Go `const version` (state/guard/drift) each bumped through the **renamed-version-test** TDD technique (`…Const1120`/`…Is1120`, stale-guard now rejects 1.11.0 — NO override), `manifest_version_test.go` → `…VersionIs1120`, and the two JSON manifests (plugin.json + marketplace.json). `go test ./...` + `go vet` green; binaries rebuilt report 1.12.0. Pushing + tagging `v1.12.0` triggers the auto-tag → release.yml → verify-release.sh publish pipeline (spec 0021) — not done here (nothing pushed).

## 2026-07-29 — Retroactively closed the genesis spec 0001 (speccraft v1)

**Spec:** specs/0001-speccraft-v1/ (status: in-progress → closed; status reconciliation, no code change). The project-genesis spec that bootstrapped the plugin (hooks, the three Go binaries, commands, subagents, `.speccraft/` memory, e2e harness) had sat at `in-progress` since 2026-05-09 with 58/69 tasks done — the 11 open ones all manual-verification / early-phase-e2e placeholders, long since superseded by the shipped `tests/e2e/run.sh` harness, the release/verify pipeline (spec 0021), and the mock-agent e2e. Closed to reflect reality (`active_spec` was already null; v1 shipped and was hardened by the 40 specs through 0040). Retrospective changelog at specs/0001-speccraft-v1/changelog.md.

## 2026-07-29 — Crash-safe conductor re-entry completes the design-0001 arc (spec 0040)

**Spec:** specs/0040-conductor-crash-safe-reentry/ (crash-safety follow-up to the 0039 MVP; status: closed). Additive shell + markdown (extends orchestrate.lib.sh/.md + the hermetic e2e). ZERO `/speccraft:spec:override`; full `tests/hooks/` (215) + `go test ./...` green.
**Decision:** Close the crash window design 0001 named — a phase whose delegated command SUCCEEDED but crashed before the ledger advanced — so re-entry never double-allocates a spec or re-closes a closed one. On resume, before re-dispatching an `in_flight` member, inspect the member's real `spec.md` status and **adopt** (jump the pointer to the artifact's token) or **reattempt**. Six new pure lib helpers: `orch_status_ordinal`/`orch_status_token`/`orch_phase_completion_status` (the status↔ordinal↔token maps), `orch_reentry` (adopt iff member-ordinal ≥ phase-completion-ordinal; `""`/`blocked` never adopt; adopt jumps to `orch_status_token(status)` so an out-of-band `review`+`closed` lands on `validated`, not a partial replay), `orch_find_member_spec` (crash-safe `new` adoption keyed on the **`informed-by: [design/<id>]`** frontmatter `spec:new` actually writes — NOT a `design:` field; ≥2 matches or a get-frontmatter read failure → error, never a false zero), and `orch_in_flight_phase` (bare 0039 token or first `phase=<p>`; malformed → error). Runbook gains create-if-absent seeding (never re-`spec ""` on an existing row — the restart-clobber fix), a `new`-first re-entry resolution, and structured `phase=review iteration=<n>`. Three hermetic e2e crash legs (each a fresh workspace) prove it DIRECTLY: no-re-close (validate-mock dispatch sentinel == 0), no-double-allocate (`new`-mock sentinel == 0 + dir-count + non-empty ledger spec), restart-safety.

**Divergence (honest).** Literal spec-id-BEFORE-dispatch is infeasible without changing `spec:new`'s allocation contract (member repos number independently); superseded by post-hoc `orch_find_member_spec` adoption + write-ref-asap. This closes the crash window; it does not deliver id-before-dispatch.

**Review.** Cross-model (codex changes-requested → resolved; claude-p approve-with-comments; both invoked cleanly after the agents.toml fix) caught the load-bearing `design:`→`informed-by` key error, the seeding-clobbers-ref-on-restart bug, and the missing `new`-dispatch sentinel; the self-check caught the adopt-by-one multi-phase bug (→ jump to artifact token) and the `in_flight=new` ref-drop (→ `new`-first precedence).

**Arc complete.** 0037 topology → 0038 ledger+reconcile → 0039 orchestrate command → 0040 crash-safe re-entry. The design-0001 conductor is buildable, resumable, failure-isolated, and crash-idempotent. Deferred: concurrent-conductor locking; a release bump can now bundle 0037–0040.

## 2026-07-29 — Architect conductor ships: /speccraft:arch:orchestrate drives the per-member lifecycle (spec 0039)

**Spec:** specs/0039-arch-orchestrate-conductor/ (Spec B orchestration surface of design 0001; status: closed). Shell + markdown (not Go): a pure `commands/arch/orchestrate.lib.sh` + a `commands/arch/orchestrate.md` runbook. 28 new bats tests (`tests/hooks/arch-orchestrate.bats`); full `tests/hooks/` (192) + `go test ./...` green. **ZERO `/speccraft:spec:override`** — shell/markdown are ungated by the TDD guard; bats supplied RED-before-GREEN.
**Decision:** Ship the conductor that *sequences* the existing `/speccraft:spec:*` commands across a `kind: workspace`'s member repos, cwd-scoped per member (never `--root`), resuming from the ledger pointer and rolling up via 0038's `reconcile`. Deterministic core = bats-tested lib helpers: `orch_next_phase`/`orch_completed_token` (the token machine `new→reviewed→planned→implemented→validated`, `revise` loops within `review` and never advances), `orch_should_pause` (checkpoint a: after `planned`, before `implement`; suppressed by `--straight-through`), `orch_review_verdict` (pass/revise/escalate — checkpoint b), `orch_parse_decomposition` (first-tab split, indented-`#` comments, safe member-path charset `^[A-Za-z0-9._/-]+$` rejecting a literal `'`), `orch_dispatch` (`(cd '<m>' && /speccraft:spec:<...>)`, six pinned commands incl. `validate→spec:close`, single-quoted, never `--root`), `orch_validate` (`sh -c` tests gate), and `orch_apply_result` (failure-isolated ledger transition via `ledger-set`). The runbook seeds member ROWS only (no double-`new`), resumes, dispatches, gates validate→`spec:close`, reconciles.

**Design fold + scope honesty.** `answer-questions` is folded into `spec:new` (so tokens are five, not six); `validate` culminates in `/speccraft:spec:close` (the step that writes the `closed` status 0038's reconcile keys `Done` on — the self-check's critical catch). Cross-model review reframed this from "final slice" to the orchestration **MVP**: it ships resume-at-pointer + `in_flight` visibility (cleared on EVERY completed attempt) + blocked-set/clear, and **explicitly defers full crash-window idempotency to a follow-up (0040)** — design 0001 itself lists crash-safety as mechanism spikes #1/#4, not a settled contract.

**Dogfood.** No guard gymnastics (not Go) — bats is the RED oracle; behavioral AC6 tests build `./bin/speccraft-state` and drive a real `kind=workspace` ledger. The zsh/bats-reserved `status` name is never assigned in the lib. Two aux-config nits logged (agents.toml: codex `--sandbox workspace-write` one-token; claude-p argv payload overflow → use stdin).

**Deferred.** Full crash-safety → spec 0040; real-subagent e2e (mock-agent harness) + spike #1 runtime FindRoot → follow-up e2e; consolidation → `/speccraft:sync`; no version bump (a release step can now bundle 0037–0039, the whole design-0001 arc).

## 2026-07-28 — Conductor primitives ship: ledger.md read/write + reconcile rollup (spec 0038)

**Spec:** specs/0038-conductor-ledger-reconcile/ (Spec B slice 1 of design 0001; status: closed). Test-first — 22 new test cases, full `go test ./...` green, `go vet` clean, ONE `/speccraft:spec:override`.
**Decision:** Ship the Go/testable core the conductor (Spec 0039, `/speccraft:arch:orchestrate`) will stand on, before any orchestration — mirroring how 0037 shipped the topology primitives. New `tools/internal/speccraft/ledger.go`: `ParseLedger`/`SetLedgerField` over a constrained `## design`/`### member` block grammar (first-`:` split preserving interior `: `, BOM/CRLF tolerance, `# Ledger` preamble, first-wins, 11 `ledger.md:`-prefixed parse-error classes); a **canonical writer** on `AtomicWriteFile` with an injectable `ledgerNow` clock seam (same-value set = byte-identical no-op; `updated` is conductor-managed, never a settable field); and a **pure `Reconcile`** taking an INJECTED status resolver so it keys on the member's `spec.md` frontmatter (proven by a disagreement test AND a source-scan that the impl never references `last_completed_phase`) — classifying Blocked→Closed→InProgress with `blocked`-overlay precedence, `Done` iff all Closed. Two `run()`-seam subcommands (`ledger-set`, `reconcile`) at zero override; the ledger is a history.md-class memory file, NEVER `state.json` (behavioral + source-scan guards).

**Override budget.** ONE (T1 bootstrap of the exported inventory), exactly as planned. The load-bearing move: a shared `resolveSpecStatus` (dual live/`.archive`, tri-state outcome) was extracted from 0037's `get-status` and `get-status` refactored onto it at ZERO override — the pure refactor rode the standing failing `reconcile`/`ledger-set` cmd REDs (author cmd REDs first, land the refactor while they stand). 0037's get-status regression stayed green.

**Dogfood friction (anticipated by the plan).** (1) A second Write of a test file with unchanged test names disarmed its red-candidates (`SetRedCandidates` replaces per file) → re-armed via an Edit adding a fresh RED. (2) A literal BOM in Go source (from a `﻿` fixture) was fixed mechanically via Bash `perl` — the sanctioned path for a build-break the guard misreads. (3) The AC3 source-scan first caught `state.json` in a ledger.go comment; reworded.

**Deferred.** Consolidation → `/speccraft:sync`; no version bump (Spec 0039 — the orchestrate command — completes Spec B and carries the release). Aux-config nit logged in the spec's review.md: `.speccraft/agents.toml` codex `cmd` should split `--sandbox workspace-write` into two tokens.

## 2026-07-28 — Workspace topology foundation ships: kind field, FindWorkspaceRoot, workspace.yml membership, and the get-status/get-frontmatter/list-members readers (spec 0037)

**Spec:** specs/0037-workspace-topology-foundation/ (Spec A of design 0001; status: closed). Implemented test-first — 44 new test cases, full `go test ./...` green, `go vet` clean.
**Decision:** Ship the topology primitives design 0001 requires *before* the conductor (Spec B) can exist, gated behind an absent-means-`repo` default so existing single repos are unaffected. `.speccraft/speccraft.toml` gains a top-level `kind = "repo" | "workspace"` (realized as a TOML key via `parseSpeccraftTOML`, NOT frontmatter — there is no YAML/frontmatter reader in `tools/`); absent ⇒ `repo`, and a `readConfigRaw` split makes non-strict `ReadConfig` COERCE an unknown value to `repo` while `ReadConfigStrict` ERRORS on it, so a bad value can never silently promote a repo to a workspace. `FindWorkspaceRoot(dir)` is a peer of `FindRoot` (nearest `kind=workspace` ancestor, else exact `FindRoot` value+error parity) consumed only by `arch:*`/the conductor — a source-scan guard test (`hotpath_findroot_test.go`, sibling to the spec-0012 single-writer test) keeps it off the Edit/Write hot path. `ParseWorkspaceMembers` parses a constrained hand-rolled `workspace.yml` subset (no YAML dependency) and is **authoritative + presence-preserving**: a listed-but-missing path is kept as `Member{Present:false}`, never dropped, so Spec B can render it as a `blocked` overlay. Three new `speccraft-state` subcommands ride the `run()` seam at zero override: `list-members`, `get-status <spec-ref>` (dual `specs/` → `specs/.archive/` resolution, live-wins — the spec-0025 relocation), and `get-frontmatter <spec.md> <key>`; the two frontmatter readers route through the single spec-0036 `parseFrontmatterBlock` grammar via a new `ReadFrontmatterField` (no second parser).

**Override budget.** Cost TWO `/speccraft:spec:override`s, not the plan's estimated one: `Config.Kind` must live in config.go's struct — a build-failure-≠-RED barrier (spec-0018-AC13) separate from the new-symbols file. Both logged in the spec's tasks.md `## Bypasses`; every other step rode a runtime RED at zero override.

**Deferred.** Consolidation into `specs/domains/` (none exists yet) left to a later `/speccraft:sync`; no version bump (foundation slice — Spec B, the conductor, completes the feature and would carry the release).

## 2026-07-28 — Architect becomes a lifecycle conductor across single- and multi-repo workspaces (design 0001, DECIDED)

**Design:** design/0001-architect-lifecycle-orchestration/design.md (status: decided — a design decision, NOT yet an implemented spec; the two implementing specs A/B are not yet opened)
**Decision:** Graduate the architect from an advisory design-writer into a **conductor** that sequences the existing per-spec lifecycle (`new → answer-questions → (review → revise)* → plan → implement → validate`) for one spec in a single repo OR fanned out across N member repos — never *bypassing* the per-spec commands or the TDD red→green guard, only *sequencing* them one member at a time and tracking progress in a ledger. Chosen by composition over new primitives, and **advisory over blocking** (consistent with today's architect; preserves member autonomy and leaves single-repo behavior untouched). Two alternatives were rejected: a hub-repo pointing at siblings (asymmetric, pollutes one repo's memory, diverges monorepo vs multi-repo) and an advisory-only linking convention with no orchestration (drops the requested orchestration) — the latter retained only as the forward-compatible **stage-1** that de-risks the topology work.

**Topology.** `.speccraft/` frontmatter gains `kind: repo | workspace` (absent ⇒ `repo` ⇒ full backward compatibility; a monorepo is a single `repo`-kind member with one repo-wide spec stream, NOT per-package roots). A `kind: workspace` root is a parent dir over ≥2 repos holding the `design/` tree + the ledger but **no specs of its own**; its `workspace.yml` `members:` list is the **authoritative membership** — filesystem ancestry only resolves WHICH workspace root you are under, never membership (an unlisted repo under the dir is ignored; a listed-but-missing `path:` is a `blocked` overlay, not a hard error). A new resolver **`find-workspace-root`** (nearest `kind: workspace` ancestor, else fall back to repo-root — a lone repo is "a workspace of one", zero manifest ceremony) is a **peer of `FindRoot`, layered ABOVE it and consumed ONLY by the `arch:*` commands and the conductor**. Hooks and `speccraft-guard` keep calling `FindRoot` exclusively, so the "no change to the Edit/Write hot path" invariant holds by construction.

**Conductor & dispatch.** A new `/speccraft:arch:orchestrate` command (peer of `arch:decide`/`arch:close`) drives the state machine with two mandatory human-in-the-loop checkpoints — (a) max `review→revise` iterations exhausted without a critic `pass` (the conductor summarizes sticking points, then restarts the loop after human input), and (b) after `plan`, before `implement` — plus a `--straight-through` flag to run past both. Each phase spawns the existing subagent with **cwd scoped to the member repo** (the `aux-delegator` precedent), so each member's own `FindRoot` lands artifacts in its own `.speccraft/` and nothing threads an explicit `--root`. Fan-out is seeded from a `decomposition:` mapping (member-path → brief) the architect drafts and the **human confirms**, stamping one member spec per brief with a `design: <design-id>` back-reference. Resumable/idempotent per member via a single `last_completed_phase` pointer + `in_flight`; `spec-id` is allocated before first dispatch and each phase re-inspects its authoritative artifact before re-attempting (closes the "delegated command succeeded but ledger write failed" window). `blocked` is an overlay flag (a failed phase or a missing member path), not a lifecycle phase; siblings proceed and a clean re-attempt clears it.

**Ledger & reconcile — the load-bearing boundary decision.** `ledger.md` is a markdown **history.md-class memory file** at the workspace `.speccraft/`, DELIBERATELY OUTSIDE the `state.json` single-writer rule — written directly by the conductor (like `history.md`), holding only conductor-owned fields (`last_completed_phase`, `in_flight`, `blocked`) and NOT caching spec `status`. `arch:close`/`sync` are the **sole authority for the design ROLLUP status** (read-only; a member's own status is written only by its `spec:close`): they read each child spec's real status from its **`spec.md` frontmatter**, never from `state.json` (which holds only the active-spec pointer + TDD session state) and never from the ledger pointer — with **dual live/archive location resolution** (`specs/NNNN-slug/spec.md` OR `specs/.archive/NNNN-slug/spec.md`, per spec 0025's consolidation move). A design is done when every child is `closed` (or the out-of-band `archived`). Because status is read from the authoritative artifact each time, a member closed/archived out-of-band is observed with no ledger divergence, and the conductor's `validated` pointer (its private progress marker) never conflicts with the member's `closed` (the authority's view). This **requires a new read-only `speccraft-state get-status <spec.md>` reader** — the counterpart to the existing `set-status` writer, honoring the same "status is written solely by `speccraft-state`" guardrail.

**Two-stage delivery.** Ships as **two specs, not one arc**: Spec A — workspace topology foundation (`kind:` field, `workspace.yml` parsing, `find-workspace-root`, the `get-status` reader, the `design:` linking convention — all Go/table-testable, fully backward-compatible), validating BEFORE any orchestration exists; Spec B — the conductor (lifecycle state machine, `ledger.md`, decomposition/dispatch, reconcile, `/speccraft:arch:orchestrate`) built on Spec A's foundation.

**Status:** design decided; four mechanism spikes (cwd-scoped dispatch confirmation, decomposition→member authoring heuristic, the "plan ACs checked" verification surface, Q&A resume granularity) are deferred to Spec B planning and are non-blocking. No code shipped, no version bump — this is a design decision record only.

## 2026-07-27 — One revision-and-artifact-numbering contract + a single sanctioned byte-safe frontmatter writer; version 1.11.0 (spec 0036)

**Spec:** specs/0036-revision-counter-artifact-numbering-contract/
**Decision:** Close the field finding that speccraft had TWO uncoordinated numbering
systems and no sanctioned frontmatter writer. The frontmatter `revision: N` counter
(spec 0015) and the archived `*-r<N>.md` files could drift, and when they did the old
`preflight_archive_collisions` HARD-REFUSED ("archive target … already exists") with
nothing ever advancing `N` past the occupied slot — a permanent deadlock a single
stray `review-r<N>.md` could trigger. Within-draft edits were invisible to the
counter, and `bump_revision`'s hand-rolled `sed -i.bak 's/^status:…/'` ate a newline
in the field. Establish one **Authority model** — the counter is canonical; archived
artifacts are forward-only reconciliation evidence, never a peer authority — with
`Effective = hasArchived ? max(fmRev, maxArchived+1) : fmRev`, and one sanctioned
byte-safe frontmatter-field writer analogous to how `speccraft-state` is the sole
writer of `state.json`. The revise path is now self-healing (archive lands in the
provably-free `A = Effective` slot and the counter advances past the collision)
instead of deadlock-prone. **New declared semantics:** within-draft edits keep the
same revision by design (a revision = a completed review cycle / an archive, not a
keystroke); the counter advances ONLY via the archive path, and `reconcile-revision`
is heal-only.

**Layering.** New Go core in `tools/internal/speccraft/revision.go`:
`ComputeRevisionState(specDir)` → `RevisionState{FrontmatterRevision, MaxArchived,
Effective, HasArchived}` (ordinal scan factored into `listArchivedOrdinals`, the
single source of on-disk layout; classification matrix in `parseRevisionValue` —
absent/non-numeric ⇒ 0, over-uint64 ⇒ error, missing-dir/unreadable-spec ⇒ error held
distinct from a malformed `revision:` line). The SINGLE unexported
`parseFrontmatterBlock` grammar (BOM-tolerant, per-line CR, column-0 `^key:`,
first-wins) is the sole entrypoint BOTH the reader (`ComputeRevisionState`,
`currentStatusClosed`) and the writer (`setFrontmatterField`) route through — pinned
by a source-scan asserting exactly one `func parseFrontmatterBlock(`. The unexported
byte-safe `setFrontmatterField` (first-match-only, per-line terminator + BOM +
EOF-newline preservation via `splitRawLines`/`joinRawLines`, deterministic
inserted-line terminator, skip-write no-op, no `.bak`) rides the spec-0035
`AtomicWriteFile` seam. The ONLY exported ops are `SetStatus` (enum-validated, AC8)
and `SetRevision` (monotonic-forward — REFUSES demotion, AC14/§C), both enforcing
closed-spec immutability IN the exported op (AC9 — no `--force` escape hatch; a local
`revErr` string-error type avoids an `fmt` import under the guard). Five new
`speccraft-state` subcommands via the spec-0035 `run()` seam: `effective-revision`,
`set-status`, `set-revision`, `reconcile-revision`, `archive-artifact`. The archive
move lives DELIBERATELY in the `speccraft-state` (cmd) package
(`tools/cmd/speccraft-state/archive.go`), not `internal` — so `moveArtifactNoReplace`
+ its `linkNoReplace`/`unlinkFile` seams and the AC15 fault-injection unit test ride
the cmd `run()`-seam RED and keep the override budget at 1. The move is a genuine
no-replace primitive (`os.Link` fails EEXIST if the target exists, then unlink source
— never a racy stat-then-rename) with `os.SameFile` inode-identity recovery on an
interrupted link-ok/unlink-fail move (retry unlinks the source instead of duplicating;
fails safe with no same-inode sibling) — NOT byte-equality. `commands/spec/revise.lib.sh`
now delegates: `preflight_archive_collisions` DELETED; `archive_rename` computes
`A=effective-revision` once and archives the disposable set (`review`, plus
`plan`/`tasks` for `planned` source) under one ordinal via `archive-artifact`;
`bump_revision` is a thin `reconcile-revision` → `set-status draft` helper in the fixed
order archive → counter → status-LAST; `close.md` step 6 uses `set-status … closed`.
AC10 meta-guard `tests/hooks/frontmatter-writer-guard.bats` is fixture-first with a
per-tool matching regime (sed/perl last positional; awk redirect target) forbidding
raw in-place `status:`/`revision:` rewrites in command libs. Version 1.10.0 → 1.11.0
across the three `const version` binaries + both manifests (renamed sibling oracles).

**The 5-round cross-model review payoff.** Five rounds (codex `gpt-5.6-sol` +
claude-p) converged dual-verdict at round 5, driving out real defects
PRE-implementation: (1) the authority contradiction ("disk wins" vs "frontmatter sole
authority") → the forward-only Authority model; (2) the `--force` closed-spec escape
hatch flagged as a **guardrail violation** → removed, enforced in the exported op so no
Go caller bypasses it; (3) archiving `spec.md` would leave nothing to counter-bump →
only the disposable `review`/`plan`/`tasks` set is archived, `spec.md` stays live;
(4) the `A+1`-vs-heal contradiction (a retry minting a spurious extra revision) → one
unified rule (counter = `Effective` recomputed AFTER the moves, so fresh and retry both
land on the same value); (5) interrupted-move data-safety (byte-equality could delete
a live source matching an unrelated archive) → `os.SameFile` inode identity + fail-safe
(AC15).

**Deviations:** ONE `/speccraft:spec:override` (T1, the AC12 new-symbol bootstrap —
budget ≤1 held). `parseFrontmatterBlock` lives IN `revision.go`, not its own file (AC13
text said "its own file"); the TESTED single-routed-entrypoint property holds and the
split was deferred to avoid a duplicate-symbol guard deadlock. T9/T10 collapsed — the
T8 writer already satisfied every byte-safety edge, so T9 pinned green with no fake RED
manufactured. `SetRevision` over-domain rejection sits at the CLI arg parse
(`parseUintArg`) since the Go signature is `uint64`; over-domain on-disk `revision:` is
a `ComputeRevisionState` error. Recurring stale-1.1.0-cached-guard friction (the
0030/0032/0034/0035 lineage): decisive REDs via Edit with a fresh test-func as the LAST
sibling touch, Bash only for mechanical build-fixes (import-then-use deadlock + three
literal-BOM-in-source breaks), and a re-registered companion RED on the version bump
(the no-new-test-edit-clears-standing-RED trap bit once). Cross-links:
[[dogfood-stale-cached-guard-on-path]]. 0036's own close ran NO consolidation (no
`domains:`/`delta:`, no `specs/domains/` tree yet — non-blocking decline).

## 2026-07-26 — Diff-focused re-review scopes reviewers to the deltas since the last review; version 1.10.0 (spec 0035)

**Spec:** specs/0035-re-review/
**Decision:** Close the field finding that a re-run `/speccraft:spec:review`
re-litigates already-settled sections every round, ballooning the round count (a
field session took 4 rounds; a hand-built "only assess what changed + check
regressions" brief cut it to 2). Add a `--diff` path that reviewers still receive
the full current spec as regression context but are instructed to assess ONLY the
deltas and sweep the unchanged, previously-approved criteria for regressions. The
value is **re-litigation avoidance**, not merely "not reading the whole spec." The
anchor is a **review-time snapshot** (`specs/<id>/review-snapshot.md`), NOT git
history — review → revise → re-review all precede the first commit, so a git-diff
anchor has nothing to compare in the common case; a self-contained snapshot is
deterministic and reuses spec-0020's robust-noop precedent (a byte-identical
snapshot short-circuits instead of dispatching reviewers).

**Layering.** `speccraft-state` OWNS change DETECTION; the `/speccraft:spec:review`
command OWNS the UX response + provenance gate. New Go in `tools/internal/speccraft`:
`AtomicWriteFile(path,data,perm)` (same-directory temp + `os.Rename`, with an
injectable package-level `atomicRename` seam for the AC2 rename-failure
fault-injection RED — the shared durable-write primitive behind both AC1 and AC2);
`WriteReviewSnapshot(specDir)` (copies spec.md → review-snapshot.md, returns the
sha256 of the RAW bytes with NO CRLF/LF/BOM/trailing-newline normalization, true
no-op — no rewrite, no mtime touch — when the on-disk snapshot is already
byte-identical); `ReviewDiff(specDir,promote)` returning the versioned
`ReviewEnvelope{schema:1, snapshot, changed, changed_sections, diff, fingerprint,
base_fingerprint}` (reads spec.md ONCE; `fingerprint`=sha256 of current bytes,
`base_fingerprint`=sha256 of the OLD snapshot or JSON `null` on first review via a
`*string`; with `--promote` the SAME captured bytes are frozen as the new snapshot
AFTER the envelope is computed — read-before-overwrite, AC11); `diffSections` +
`parseSpecDoc`/`renderDiff` (`review_sections.go`) the AC5 determinism engine —
structured `ChangedSection{kind,heading,ordinal,side}`, sections keyed
per-document by (trimmed heading, 1-based ordinal), matched ordinal-aligned, a pair
emitted `modified` only when bodies DIFFER, an unmatched occurrence emitted
`added` (new-doc ordinal) / `removed` (old-doc ordinal), a byte-identical body
NEVER emitted even under an ordinal shift, no blanket over-report, a rename =
removed+added, `frontmatter`/`preamble` reserved kinds distinct from a literal
`## (frontmatter)` heading (which is `kind:"section"` and never aliases);
`WriteReviewFile(path,body,fingerprint)` the AC2 SINGLE atomic commit (strip any
prior `reviewed_sha256:` lines, append exactly one canonical line, write the
COMPLETE file via `AtomicWriteFile` — never an intermediate fingerprint-free write;
on any failure the prior review.md is byte-unchanged).

Three new `speccraft-state` subcommands are wired through the compile-stable
`run()` seam (so every cmd RED is a runtime "unknown subcommand", never a build
error): `review-snapshot write <spec-dir>`; `review-diff <spec-dir> [--promote]`
with the AC3 exit-code matrix (read-only exits 0 whenever spec.md resolves —
including no-snapshot AND a closed spec — non-zero only when spec.md, or a
present-but-unreadable snapshot, cannot be read; `--promote` adds the ONE exception,
refused non-zero on a closed spec via a new `specStatusIsClosed` frontmatter
probe, honoring closed-spec immutability); and an UNPLANNED `review-commit
<review-file> <fingerprint>` so the markdown/bash command can invoke AC2's atomic
commit across the CLI boundary. New `templates/prompts/re-review.md` (AC7a) carries
`{{DIFF}}`/`{{CHANGED_SECTIONS}}` + the regression-sweep instruction, with a
both-polarity grep oracle scoped to the template only. New `commands/spec/review.lib.sh`
(spec-0015 colocation): `review_reviewed_sha256` (anchored `^reviewed_sha256:
[0-9a-f]{64}$` usability parser — zero/multiple/malformed → not usable),
`review_classify` (the provenance gate → full-review / short-circuit / scoped),
`review_build_payload` (sources the FROZEN review-snapshot.md, never spec.md).
`review.md` wires the `--diff` transaction + the step-6 atomic fingerprint
recording. `speccraft-drift` `CheckFile` now excludes the whole `specs/**` tree
(AC10), pinned by a test calling the same `CheckFile` the drift hook invokes.

**The load-bearing correctness pins (all from cross-model review, which took 9
rounds to dual-approve — codex's adversarial passes drove out 4 real bugs
PRE-implementation).** (1) **Baseline provenance.** The envelope exposes
`base_fingerprint` (the OLD snapshot's sha256), and the command gates BOTH the
scoped and short-circuit branches on the prior `review.md`'s `reviewed_sha256`
equalling it — so a promoted-but-unreviewed baseline (a prior run that promoted
then died before writing review.md) forces a FULL review instead of letting the
un-reviewed delta escape. This is what makes promote-before-dispatch correct in ALL
cases, not just the no-change retry: an edit layered on an unreviewed promoted
snapshot cannot smuggle its earlier delta past review. (2) **Retry-safety.** Any
`changed:false` run lacking a matching review falls back to a full review, so a
failed promoted run is safely retryable. (3) **AC2 as a single atomic commit**, not
a two-step append — the reviewed_sha256 line is composed in the temp file before the
rename; success == rename succeeds. (4) **Determinism = pure ordinal-key matching**,
replacing an earlier blanket duplicate-count over-report that contradicted the
byte-identical rule. Version bumped 1.9.0 → 1.10.0 across the three `const version`
binaries (each a renamed sibling version test) + both manifests (grep oracle); the
published-verified release (auto-tag → release.yml → verify-release.sh) is the
merge-time DoD (T31).

**Deviations:** ONE `/speccraft:spec:override` (T1), the planned new-symbol
bootstrap — AC13 budget (≤1) held. Implemented IN-PLACE in `review.go` (+
`review_sections.go`) rather than one-file-per-function, to avoid duplicate-symbol
deadlocks with the stub bootstrap under the guard. The optional T3 `saveStateLocked`
refactor was SKIPPED (not AC-required) — `AtomicWriteFile` is a fresh seam and
`saveStateLocked` was left as-is. The `review-commit` subcommand is unplanned (added
for the CLI-boundary atomic commit). Incidental, USER-made: `.speccraft/agents.toml`
codex cmd changed `--full-auto` → `--sandbox workspace-write` (unblocked codex for
cross-model review), included in this diff. **Stale-1.1.0-cached-guard friction
(recurring, the 0030/0032/0034 lineage):** decisive REDs registered via Edit (the
Write blind spot), a fresh test-func kept as the LAST sibling touch, Bash used only
for mechanical build-fixes (unused import / dead var), never to bypass a behaviour
RED→GREEN; the no-new-test-edit-clears-standing-RED gotcha bit once (drift import
fix), remedied by a fresh test func. 0035's own close ran NO consolidation (no
`domains:`/`delta:`, no `specs/domains/` tree yet — non-blocking decline).

## 2026-07-25 — MultiEdit/NotebookEdit payload modeling closes spec 0031's reserved slot, override-free; version 1.9.0 (spec 0032)

**Spec:** specs/0032-payloads/
**Decision:** Close the reserved slot spec 0031 left behind. Spec 0031 switched
`speccraft-guard`'s red-candidate capture (`applyEdit`) on tool IDENTITY rather than
payload shape, but modeled only `Write` (→ `content`) and `Edit` (→ in-place replace);
`MultiEdit` and `NotebookEdit` fell to a `default:` fallback that returned pre-edit
content unchanged and carried a "reserved for spec 0032" comment plus two
characterization tests. So a test file authored via either tool captured ZERO
red-candidates, and the sibling production edit was wrongly blocked with "no failing
test observed" — the exact class 0031 fixed for Write. This spec models both:
a NEW named type `MultiEditEntry{OldString,NewString}` (named, not anonymous, for
test/future referenceability); two NEW `ToolInput` fields `Edits []MultiEditEntry`
(`json:"edits"`) + `NewSource string` (`json:"new_source"`); and a NEW helper
`applyMultiEdit(pre, edits)` that folds each entry as a FIRST-occurrence
`strings.Replace` over the RUNNING content (a later entry sees the earlier entry's
output), SKIPS an entry whose `OldString==""` (Go's `strings.Replace` would otherwise
prepend), and no-ops on an absent target (best-effort; NOT the real tool's hard error).
`applyEdit` gains explicit `case "MultiEdit"` (→ `applyMultiEdit`) and
`case "NotebookEdit"` (→ `ti.NewSource`, empty string INCLUDED, mirroring Write's
`Content`). The switch keys on `ti.ToolName`, so the empty-vs-absent `new_source`
zero-value ambiguity is moot — a plain `string`, not `*string`, is deliberate.
NotebookEdit models the modified cell's `new_source` only; `.ipynb` JSON is NOT parsed,
so other cells' test IDs are unobserved (accepted, pinned limitation). The two 0031
characterization tests were INVERTED + RENAMED (`…CapturesNoRedCandidates` →
`…CapturesRedCandidate`) so the test NAME is itself a recurrence signal; a new
`reserved_slot_test.go` adds a case-insensitive/whitespace-tolerant recurrence grep
(needles from concatenated fragments, self-excluded) forbidding any surviving
"reserved spec 0032"/"unmodeled" language, plus a `FutureEdit` fallback pin, the two
dispatch-injection PINs (AC8 — `dispatchByLanguage` already injects ToolName, so it is a
regression pin, not a driver), and `Test_ApplyEditDefaultComment_OmitsModeledTools`.
Version bumped 1.8.0 → 1.9.0 across the three `const version` binaries (each via a
renamed sibling version test) + both manifests (grep oracle). The published-verified-
release half of AC10 is the merge-time obligation (auto-tag → release.yml →
verify-release.sh), same as specs 0031/0034.

**The meta-payoff — shipped OVERRIDE-FREE.** Every driving RED touching the new
`Edits`/`NewSource` fields was authored at the `json.Unmarshal` envelope boundary: an
unknown JSON key parses to the zero value, so the test COMPILES against the old struct
and fails only on BEHAVIOR (a runtime RED), dodging the spec-0018-AC13
build-failed-≠-RED trap that cost spec 0034 a bootstrap override. This confirms spec
0031's envelope-boundary technique GENERALIZES from the single `Content` field to a
struct-FIELD extension (two fields + a named nested type), not just a one-field add —
the technique's reach is any additive JSON-decoded surface, not a special case.

**Two environmental findings.** (1) **Stale-cached-guard recurrence** (the 0034
stale-`1.1.0`-cache-on-PATH lineage): the hook ran the STALE 1.1.0 cached guard. When
scrubbing main.go's `default:` comment (a gated comment-only prod edit), the sibling
RED had been CLEARED by a prior NO-NEW-TEST Edit to `reserved_slot_test.go` (adding the
`strings` import) — the documented "SetRedCandidates replaces per-file; a no-new-test
edit clears a standing RED" behavior (spec 0031's brittleness note (a)). Remedy: a
GENUINE fresh companion RED (`Test_ApplyEditDefaultComment_OmitsModeledTools`) was
registered via the Edit tool, unblocking the scrub with NO override. Codified as a
convention: keep the decisive fresh RED as the LAST sibling test-file touch before a
gated prod edit. (2) **A source-scanning meta-test scoping bug, caught + fixed
in-session:** the companion test's first `strings.Index(src,"default:")` matched an
EARLIER `default:` (main.go:93), sweeping the new MultiEdit/NotebookEdit case labels
into the scanned segment → false positive. Fixed by anchoring the scan to the
`func applyEdit(` body FIRST, then locating `default:` within it — a source-scanning
meta-test must scope to its TARGET function, not the first textual match.

**Deviations:** none material. `tasks.md §Bypasses` is empty — ZERO
`/speccraft:spec:override`. `go test ./...` green. AC8 and the AC9 unknown-tool fallback
were green-on-arrival PINs (the injection line already existed), ridden in the Phase-3
RED step kept red by the recurrence grep, so RED→GREEN framing held without a
passing-only GREEN. 0032's own close ran NO consolidation (no `domains:`/`delta:`, no
`specs/domains/` tree yet — non-blocking decline).

## 2026-07-25 — Stack-agnostic planning & execution: surface the config-backed test command to the authoring layer; version 1.8.0 (spec 0034)

**Spec:** specs/0034-stack-agnostic-planning-execution/
**Decision:** Close field finding #5 from the installed-plugin engagement (the same
Python-repo run behind specs 0030/0031): the planning/execution PROSE was Go-shaped
(`tdd-planner.md` rules 3/7, `plan.md`'s `find … -name '*_test.go'`,
`implement.md`/`delegate.md`'s bare `go test ./...`) and the shipped
`templates/speccraft/conventions.md` copied Go idioms (a `^func Test[A-Z]`
enforce-regex, `fmt.Errorf`, `slog`, `cmd/`) into every host repo — a direct
violation of the standing "templates stay stack-agnostic" guardrail. Crucially the
EXECUTION substrate was already stack-aware (go/python/js/ts via
`runner.AdapterForLanguage`+`cfg.TDD.<Lang>.Command`; rust via the SEPARATE
`runner.AdapterFor`+`cfg.TDD.Rust.Runner`); the gap was entirely in the authoring
layer. The fix READS those same config-backed commands and surfaces them: a new
`DetectStack(root, cfg) Stack{Language, TestCommand, TestPatterns []string,
InlineTests bool}` (`tools/internal/speccraft/detect.go`) probing ONLY exact
repo-root manifests, with polyglot precedence encoded as ordered data
(`manifestOrder`) `go > rust > python > ts > js` (compiled-lang manifests rank
above `package.json`, which is often mere tooling; ts refines js within the
package.json case); two `speccraft-state` subcommands (`detect-stack`, versioned
`{"schema":1,…}` JSON, exit 0 incl. `unknown`, non-zero only outside a repo; and
`test-command`, the effective command as raw data, non-zero when empty); a
single-line `<!-- speccraft:test-command = "cmd" -->` conventions.md marker
(quoted-string body regex, per-line, first-of-duplicates wins, empty/malformed →
detection fallback, emitted verbatim never shell-evaluated) that OVERRIDES
detection and is the editable source of truth; `/speccraft:init` seeding
(`commands/init.lib.sh::seed_conventions` copies the neutral template and fills the
marker from `detect-stack`, PRESERVES an existing conventions.md byte-for-byte, and
writes a TODO + empty marker on `unknown`); the four authoring docs rewritten to
reference the project's command; and TWO mechanical meta-guards promoting the
guardrails template-purity rule from advisory to executable —
`authoring_prose_test.go` (a concrete test-command must sit under an
`^\s*(#+|>|-|\*)?\s*example\b` label OR invoke `speccraft-state test-command`) and
`template_purity_test.go` (shipped template free of Go idioms). Version bumped
1.7.1 → 1.8.0 (new user-facing subcommands + changed shipped command/template
behavior); the published-verified-release half is inherited as a merge-time
obligation (spec 0030 AC11). Two-round cross-model review converged at revision 2
(all 10 interface-contract items folded before planning).

**Two environmental findings — the honest story of this run.**
(1) **ONE `/speccraft:spec:override` (T1), pre-authorized.** The brand-new
`DetectStack`/`Stack` symbol hit the guardrails §AC13 new-symbol limitation: the
Step-2 sibling `detect_test.go` cannot compile until `detect.go` exists, so the
guard's pre-edit red-check sees `OutcomeBuildFailed`, not a valid RED. This is the
SAME single-symbol-bootstrap spec 0031's history predicted; the JSON-envelope-
boundary trick that gave 0031 a zero-override run does NOT apply to a wholly-new
type. Every other step was strict RED→GREEN — including the marker parser, which
was deliberately placed in `package main` (`testcommand.go`, reached only via the
CLI) rather than as a SECOND new internal/speccraft symbol, precisely to avoid a
second bootstrap.
(2) **The hook ran the STALE 1.1.0 cached guard** — the pre-0031 Write
blind-spot: it reads `new_string` but the Write tool sends `content`, so any test
file CREATED via the Write tool captured ZERO red-candidates and the sibling
production edit was wrongly blocked with "no failing test observed." Workaround
used throughout: introduce each decisive failing test via the **Edit** tool (whose
replace-path the old guard models correctly), NOT a fresh Write. This is the same
stale-cache-on-PATH class spec 0030 flagged for `speccraft-state`; the SHIPPED
1.8.0 guard is correct and its tests pass — the blind spot was only in the cached
copy first on PATH during this dogfood session.

**Deviations:** init seeding landed at the TOP-LEVEL `commands/init.md` +
`commands/init.lib.sh` (spec/plan named `commands/spec/init.*` — `/speccraft:init`
is not a spec-lifecycle command); `seed_conventions <root> <template_path>` takes
the template path explicitly (init.md already resolves `$PLUGIN_ROOT`) so the
helper needs no plugin-root resolution; the marker parser is unexported in
`package main`, not a planned exported `internal/speccraft.EffectiveTestCommand`;
the Go `TestCommand` surfaces a SUITE form (`go test ./...`, appending ` ./...` to
the bare per-test `cfg.TDD.Go.Command`) distinct from the guard's per-test command.
`go test ./...` and `tests/hooks/*.bats` green; scope contained to the AC8 file
list plus the new detection/subcommand/meta-test/bats/init files. 0034's own close
ran NO consolidation (no `specs/domains/` tree yet — non-blocking decline). 0032
remains reserved by spec 0031.

## 2026-07-25 — Post-0030/0031 CI regression hardening: three fixes + a shell-fixture recurrence guard, test/fixture/prompt-only (spec 0033)

**Spec:** specs/0033-ci-regression-hardening/
**Decision:** Fix three CI failures that surfaced after shipping specs 0030 (v1.7.0)
and 0031 (v1.7.1), and add a recurrence guard for the class that let one through —
entirely in test files and e2e shell fixtures, with NO product code, NO version bump,
and ZERO `/speccraft:spec:override` (all changed file classes are ungated). The
shipped 0030/0031 behavior is correct; this spec only aligns tests/fixtures/prompts
with it. **(1) macOS-only Go test.** `Test_ResolvePluginRoot_SymlinkedExe_ResolvesRealInstall`
compared the resolver's `got` against a raw `filepath.Abs(t.TempDir())` root; on macOS
`/var`→`/private/var` is a symlink and the resolver correctly `EvalSymlinks`-normalizes
the exe (spec 0030 AC4), so `got != want` — red on macOS, green on Linux (`/tmp`
unsymlinked). Fixed with an **asymmetric** assertion: normalize only the EXPECTED value
(`want = filepath.EvalSymlinks(root)`), leave `got` untouched. Normalizing both sides
would let a resolver that STOPPED calling `EvalSymlinks` pass — masking exactly the
regression the test exists to catch; the through-symlink exe path preserves that
sensitivity. **(2) `rust_integration_cycle.sh` Write payload.** The fixture sent a
`{"tool_name":"Write"}` envelope with content in `new_string` — the exact 0031
mis-simulation, now in a shell fixture. Spec 0031's `applyEdit` reads `content` for a
Write, which was absent → empty post-edit content → no just-added test → no rejection →
leg failed. Fixed by using `"content"`. **(3) `spec_consolidate.sh [cons 1/3]` decline
leg** (NOT a 0030/0031 regression — a pre-existing 0025→0027→0028→0029 consolidation-
lineage flake, bundled only because it blocks the same e2e gate): the non-imperative
prompt let the credit-gated model propose-and-wait instead of writing the
`consolidation-skip` marker. Fixed with an imperative prompt (write the marker, do NOT
move the dir, act without asking, keep the memory-audit proposals separate).

**The recurrence guard.** New Go test `tools/internal/speccraft/e2e_fixture_shape_test.go`.
`Test_E2EFixtures_NoWritePayloadUsesNewString` scans every `tests/e2e/*.sh`
per-envelope (segmenting on `"tool_name"`, associating fields within one block, not a
repo-wide proximity grep) for the forbidden Write+`new_string` shape — extending spec
0031's Go-ONLY AC5 static guard to SHELL fixtures, which is the exact gap that let (2)
through. Plus `Test_ConsolidateDeclineLeg_ImperativePrompt`, a credit-free meta-test
that reads the LIVE `[cons 1/3]` prompt (anchored on `cons-01-decline.log`) and pins its
three terminal-action phrases, making the wording requirement deterministic without a
model run (the credit-gated marker-exists/dir-unmoved post-condition stays the
behavioral backstop). This is the spec-0014/0020 "meta-test reads run.sh's live
predicate" lesson applied to a credit-gated prompt's wording.

**Lessons codified as conventions.** (a) When a test pins a normalization the PRODUCT
performs (EvalSymlinks, path cleaning), normalize only the EXPECTED value — normalizing
both sides masks a stopped-normalizing regression. (b) A Write payload in ANY fixture
(Go or `tests/e2e/*.sh`) must carry content in `content`, never `new_string` — the
generalization of 0031's Go-only guard, pinned by the per-envelope Go scanner.

**Deviations:** No version bump — nothing shipped in a binary, manifest, command doc,
hook, or user-facing prompt (the `[cons 1/3]` string is test-driver input inside
`tests/e2e/`, not a user-facing prompt); the §Version bumps trigger is behavior/API
change, none here. AC1 is NOT reproducible on the Linux dev host — the local oracle was
Linux `go test` staying green plus the assertion being provably macOS-correct by
construction; real confirmation is the next macOS CI unit run. Exactly four files
changed (`pluginroot_test.go`, `rust_integration_cycle.sh`, `spec_consolidate.sh`, new
`e2e_fixture_shape_test.go`) plus the `.speccraft/index.md` pointer; `go test ./...` and
`tests/hooks/*.bats` green. 0032 remains RESERVED by spec 0031; 0033 intentionally skips
it and does NOT self-reserve (a reservation cannot name an ID below the reserving spec's
own). 0033's own close ran no consolidation.

## 2026-07-24 — TDD guard Write-tool red-candidate blind spot fixed override-free; version 1.7.1 (spec 0031)

**Spec:** specs/0031-guard-write-tool-red-candidate-blindspot/
**Decision:** Fix the exact guard limitation that cost spec 0030 three
`/speccraft:spec:override`. `speccraft-guard`'s red-candidate capture modeled a
write-tool call's post-edit content by payload *shape*: `applyEdit` treated an empty
`old_string` as "Write → `new_string` is the whole file." But the **Write** tool sends
`content`, not `new_string`, and `ToolInput` had no `content` field — so a test file
CREATED or OVERWRITTEN with Write extracted zero test IDs and captured zero
red-candidates, after which the sibling production edit was blocked with "no failing test
observed" despite a real RED on disk. It stayed invisible because the fixture
(`captureCase`) mis-simulated Write via `NewString`, encoding the same wrong assumption as
the bug — a green suite over a broken path. The fix discriminates on **tool identity, not
payload shape**: add `ToolInput.Content` (`json:"content"`) and a `ToolName` field
(`json:"-"`) injected once from `HookInput.ToolName` in `dispatchByLanguage`; `applyEdit`
now switches on `ti.ToolName` — `Write` → `Content` (incl. the empty string; `new_string`
ignored); `Edit` → `strings.Replace(pre, old, new, 1)` preserved even when `old_string`
is empty (an Edit is never reclassified as a Write); `default` (MultiEdit/NotebookEdit/any
other) → pre-edit content unchanged (empty just-added set), reserved for spec 0032.
`captureCase` was corrected to the real `ToolName:"Write"`+`Content` shape, so the
pre-existing `Test_TestFileEdit_CapturesRedCandidates_*` become AC5's behavioral proof.

**The meta-payoff — the fix for the override-forcing bug shipped with ZERO overrides.**
The change mutates an EXISTING gated package's in-package surface, so a RED that referenced
the new `Content` field would fail to COMPILE → `OutcomeBuildFailed` → not a valid RED →
an override (the precise trap this spec removes; contrast spec 0030's fresh-package escape).
The plan's load-bearing move was to author every driving RED at the **JSON-envelope
boundary**: each `json.Unmarshal`s a real `{"tool_name":"Write",...,"content":...}`
envelope and calls `processToolUse`, so it compiles against current code (no `Content`
token, no new signature) and fails on BEHAVIOR (the `content` key is silently dropped →
zero candidates → assertion fails). The signature/field-referencing AC1/AC2 pins were added
in the same GREEN edit, after the field existed, in the never-TDD-gated test file.

Verification (two-tier, established pattern): 7 JSON-boundary capture tests (Write
create+overwrite Go/Python + one JS/TS as the shared-extractor representative), two
two-ordered-call E2E tests (`Test_WriteThenEditProd_NoOverride_Allows_{Go,Python}`) with a
fake runner asserting the runner is invoked exactly once with the captured ID, returns
`OutcomeAtLeastOneFailed` for it, and the prod edit returns nil with no override
provisioned; AC1(a–d)+AC2 `applyEdit` unit pins (incl. `NewString`-ignored-on-Write and
empty-`old_string`-still-replaces); AC5 static guard
(`Test_NoWriteHelperSetsNewStringWithoutContent`); AC7 MultiEdit/NotebookEdit
characterization (native envelope → zero red-candidates). `go test ./...` green, bats
0-fail, `specs/0031-.../verify.sh` green. Version bumped `1.7.0 → 1.7.1` (guard behavior
fix; patch) across the three `const version` + two `.claude-plugin/*.json`, sibling version
tests renamed to `…171`/`…Const171`. Two-round cross-model review (codex + claude-p)
converged in 2 rounds; the sole round-2 residual was a one-line `reserves-specs: ["0032"]`
frontmatter add.

**Deviations:** `applyEdit`'s SIGNATURE was NOT changed — the plan proposed a new
`applyEdit(pre, toolName, ti)`; the shipped fix carries the tool name on
`ToolInput.ToolName` (`json:"-"`, injected once at dispatch), a strictly smaller edit
touching no call-site signature. The switch's empty-`ToolName` case is folded into `Edit`
(`case "Edit", ""`), not the `default`, so older in-package fixtures omitting `ToolName`
keep working; production Edit envelopes always carry `tool_name`. TWO red-candidate
tracking brittleness notes surfaced (both resolved WITHOUT override): (a) a two-step edit
to `speccraft-state/version_test.go` had its second, assertion-only edit OVERWRITE the
file's red-candidates with empty — `SetRedCandidates` replaces per-file, and an edit adding
no new test name clears the just-added RED — briefly blocking the const bump; fixed by a
single-edit rename that re-registered the test; (b) one stale doc comment in
`computeJustAddedForEdit` was left un-updated because the guard correctly refuses a
comment-only production edit with no failing test behind it (guard behaving as designed).
MultiEdit/NotebookEdit payload modeling is out of scope and reserved as **spec 0032**. AC6's
published-release half is deferred to merge-time (`auto-tag → release.yml →
verify-release.sh` on `main`); source bump + version tests + manifest oracle done. 0031's
own close ran NO consolidation (no `domains:`/`delta:`, no `specs/domains/` tree yet —
non-blocking decline).

## 2026-07-24 — Cross-environment command execution hardening; version 1.7.0 (spec 0030)

**Spec:** specs/0030-cross-env-command-hardening/
**Decision:** Fix two coupled command-execution defects surfaced running speccraft
as an *installed* plugin (not dogfooded) in another project — macOS default `zsh`,
a Python codebase — the natural sequel to spec 0029's first-use-in-another-repo
portability lineage. (A) **Plugin-root resolution was unreliable for slash-command
bash.** Command docs dereferenced `"$CLAUDE_PLUGIN_ROOT/{bin,commands,templates}"`,
but `CLAUDE_PLUGIN_ROOT` is only contractually exported to **hook** subprocesses,
not to the bash a slash command runs; in the field it resolved to the plugins
*parent* directory, so every `bin/`/`commands/`/`templates/` path failed across
`revise`/`review`/`plan` and, by inspection, most other commands. (B)
**`revise.lib.sh` was not zsh-safe:** a bare `status` local (zsh reserves `status`
read-only, aliasing `$?`) aborted the first `preflight_status_gate` call with
`read-only variable: status` when the lib is sourced into zsh. The fix adds a new
`speccraft-state plugin-root` subcommand (pure core
`ResolvePluginRootFrom(speccraftRoot, claudeRoot, exePath)` +
`IsValidPluginRoot` predicate in `tools/internal/speccraft/pluginroot.go`) with
precedence `SPECCRAFT_PLUGIN_ROOT` (must validate or hard-error) → validated
`CLAUDE_PLUGIN_ROOT` (the parent-dir field bug fails validation and is skipped, not
fatal) → self-derivation (`os.Executable()` → `EvalSymlinks` → ascend to the
nearest ancestor holding `.claude-plugin/plugin.json` + `bin/`+`commands/`+
`templates/`, handling both `<root>/bin/` and dogfood `<root>/tools/bin/`). The 15
command docs migrated to `PLUGIN_ROOT="$(speccraft-state plugin-root)"` (bare
binary calls go on `PATH`); `init.md`'s empty-var fallback removed; the bare
`status` renamed `spec_status`; version bumped `1.6.1 → 1.7.0` (additive
subcommand = minor).

Two-tier verification per the established pattern: 11 Go table tests (precedence
a–f, symlinked-exe via a real tmp symlink, none-resolvable error naming every
source, manifest-identity negative, subcommand wiring) + three sibling version
tests at 1.7.0; a REAL-zsh `tests/hooks/lib-zsh-safety.bats` (`zsh -uc "source
<lib>"` over every `commands/**/*.lib.sh`, the authoritative backstop for the
curated reserved-name set, plus both `preflight_status_gate` fixtures and a
bash no-regression loop); and `specs/0030-.../verify.sh` (forbidden-pattern
absence + positive resolve idiom + convention lockstep + static reserved-id guard
+ manifest + devcontainer). `.devcontainer` exports
`SPECCRAFT_PLUGIN_ROOT="${containerWorkspaceFolder}"` so dogfood sessions never
self-derive to the stale `~/.claude/plugins/cache/.../1.1.0` copy first on `PATH`
(a live, verified footgun). `go test ./...` green, bats 142/0, verify.sh green.
Two-round cross-model review (codex + claude-p) converged in 2 rounds — the
diff-focused re-review kept round 2 scoped to deltas.

**Deviations:** THREE `/speccraft:spec:override` (the plan predicted ZERO) —
create `pluginroot.go`, wire `case "plugin-root"`, add the `usage()` line. Root
cause is a real guard limitation newly pinpointed: the red-candidate capture reads
the Edit tool's `tool_input.new_string` but the RED tests were authored via the
**Write** tool (which sends `content`), so they registered zero red-candidates —
compounded for the new package by the compiled-language bootstrap (a brand-new
symbol's test can't compile → `OutcomeBuildFailed`, not a valid RED). Logged as a
new action-plan finding (guard **Write-tool blind spot**), joining the deferred
apply-edit-in-memory red-check as the durable fix. AC11's *published-release* half
is intentionally deferred to merge-time: the `v1.7.0` GitHub Release is produced
automatically by `auto-tag` → `release.yml` → `verify-release.sh` when the bump
lands on `main` (§Version bumps); source-level bump + sibling tests are done. 0030's
own close ran NO consolidation (no `domains:`/`delta:`, no `specs/domains/` tree
yet — non-blocking decline).

## 2026-06-27 — Consolidation routing hardening + zsh portability fix; released 1.6.1 (spec 0029)

**Spec:** specs/0029-consolidation-routing-hardening/
**Decision:** Fix three first-use defects in spec 0025's inline-at-close
consolidation, surfaced when speccraft was run from scratch in another project, and
patch-release them as 1.6.1. (A) **zsh portability:** `consolidate.lib.sh` resolved
its own dir with a bare `${BASH_SOURCE[0]}` — under zsh + `set -u` that aborts the
`source` (`BASH_SOURCE[0]: parameter not set`, exit 127), which took down EVERY
consolidate function and the `/speccraft:sync` backfill, so an agent silently
skipped consolidation. Fixed with the canonical `${BASH_SOURCE[0]:-$0}` (bash always
populates `BASH_SOURCE` so the fallback never fires there; zsh sets `$0` to the
sourced file, so `$0` is right exactly where it fires). (B) **routing couldn't see
existing domains:** `consolidate_routing_seed` only slugified the title, so it could
neither prefer a good existing domain nor deliberately propose a new one — it leaned
entirely on the developer to correct. Added a SEPARATE deterministic
`consolidate_existing_domains` (live-only, `.archive`-excluded, bytewise-sorted) to
ground the proposal; the seed is byte-unchanged. (C) **docs let an agent conflate
the two close-time mechanisms:** the observed failure was an agent folding
requirements into `.speccraft/architecture.md`/`conventions.md` (the `Mode: close`
memory files) and calling consolidation done — the exact files 0025's blast radius
forbids consolidation from touching. Hardened `close.md` step 9 + `memory-keeper`
(`Mode: consolidate` and `Mode: close`) to state consolidation routes ONLY to
`specs/domains/`, never `.speccraft/`; that a missing `delta:`/`domains:` is a
fallback, not a skip; and that `Mode: close` updates are not a substitute for
consolidation.

Two-tier per the established pattern: deterministic helpers + bats (a REAL-zsh
source pin — a bash simulated-unset harness can't reproduce the bug because bash
re-populates `BASH_SOURCE` during `source` — plus an exact-form `${BASH_SOURCE[0]:-$0}`
guard across all 8 `*.lib.sh`); doc contracts via `specs/0029-.../verify.sh`; and a
credit-gated AC6 e2e leg. Two new conventions codified: the cross-shell lib-sourcing
idiom + its guard, and "a credit-gated e2e leg must instruct the model to APPLY, not
propose-and-wait" (the AC6 leg first failed in CI because proposal-style prompt
wording made non-interactive `claude -p` stop at "Confirm?"). `ci.yml` hooks job now
installs `zsh`. Version bumped 1.6.0 → 1.6.1 across the five surfaces.

**Deviations:** no `/speccraft:spec:override` (all ungated file types). 0029's own
close ran NO consolidation — it has no `domains:`/`delta:` and the repo has no
`specs/domains/` yet, a non-blocking decline. Tests: bats 138/0, go test green,
verify.sh 0025+0029 green. Landed `0d595d7` + `ddf38da`; tag `v1.6.1`.

## 2026-06-25 — Pin the e2e consolidation fixture's load-bearing corpus precondition at the credit-free layer (spec 0028)

**Spec:** specs/0028-e2e-consolidation-fixture-isolation/
**Decision:** The THIRD test-harness-only fix in the 0025 → 0027 → 0028 lineage, and the
one that BREAKS THE CYCLE. The spec-0025 consolidation e2e fixture
(`tests/e2e/spec_consolidate.sh`) failed on its first real run: its DECLINE and CONFIRM
legs shared one seeded spec (0089), and a `/speccraft:sync` decline writes a PERMANENT
`consolidation-skip` marker (across-run skip-permanence, spec 0025 AC11), so once the
DECLINE leg declined 0089 the CONFIRM leg could never consolidate it — `[cons 2/3]`'s
`contains "$DOM" "(spec 0089)"` correctly failed. Two further isolation gaps from the same
run: `/speccraft:sync` enumerates the WHOLE candidate corpus (so the conflict spec 0088 was
eligible early), and the lifecycle spec `0001-add-farewell-function` leaked in (spec 0027
made `[10/13]` decline consolidation INLINE, and an inline-close decline writes NO skip —
only a sync decline does). The feature behaved exactly as specified; this is a
FIXTURE-DESIGN error ("decline X then confirm X" is self-contradictory under sticky-skip),
not a feature defect — spec-0025 feature code (`consolidate.lib.sh`, `close.md`, `sync.md`,
`memory-keeper.md`, `SKILL.md`) is BYTE-UNCHANGED. The fix has three parts. (1) The part
that broke all three times is the candidate-set / corpus-arrangement logic, which is PURE
SHELL and deterministically testable WITHOUT the model, so it was promoted to FOUR
credit-free `tests/hooks/spec-consolidate.bats` cases (suite 31 → 35): one per leg that
RECONSTRUCTS that leg's exact corpus per the spec's corpus-state table and asserts
`consolidate_backfill_candidates` returns exactly the intended singleton (decline→0090,
confirm→0089, conflict→0088), plus the `skip-excludes-target` regression — the original
0089 bug reproduced at zero credits. The three arrangement cases ARE the corpus-state table
(CF-B), so a fixture-SEEDING regression, not just library drift, now fails on every CI bats
job. (2) The fixture was reworked to LAZY per-leg seeding (chosen over pre-mark-and-clear):
a new `0090-decline-source`, `0001` skip-marked ONCE at entry as a set-and-never-cleared
isolation artifact, each source seeded immediately before its own sync, and NO marker ever
cleared — eliminating the fragile between-legs skip-CLEAR step where a 4th latent bug would
hide. A LOAD-BEARING per-leg AC3 guard sources `consolidate.lib.sh` and asserts
`consolidate_backfill_candidates "$PWD"` == the leg's singleton via a DIRECT invocation
(not log parsing) before each `run_claude`. (3) `run.sh [10/13]` now asserts an
inline-close decline writes NO skip on 0001 — symmetric to the sync-decline-writes-skip
leg — pinning the exact skip-semantics contrast that produced the original bug, ordered
before `[10e/13]`'s set-once isolation skip-mark so the two never conflict.
**Why:** The fixture's load-bearing premise — its per-leg corpus arrangement — was never
pinned at a cheap layer, so it surfaced only on a credit-gated lifecycle run that specs
0025 and 0027 had both deferred. This is the spec-0024 "expose the deterministic seed of a
model heuristic at the cheap layer" lesson and the spec-0014/0020 "assertion meta-test
reads run.sh's live predicate" lesson applied to a credit-gated fixture's PRECONDITION
rather than its assertion: the candidate-set/corpus-arrangement that broke three times is
pure shell, so it belongs in bats, not in a once-a-push credit-gated run. AC3's in-fixture
direct invocation complements it — a synthetic bats arrangement cannot prove the LIVE
fixture builds that arrangement, so the runtime guard reduces any live seeding/order drift
to a fast, NAMED candidate-set failure at the top of the offending leg instead of a
confusing downstream `state.md`/`contains` failure (claude-p's round-2 caveat). Two-round
cross-model review: round 2 quorum met (claude-p approve-with-comments; codex's lone
remaining concern was the AC8 wording contradiction, not a design flaw); four
carry-forwards (CF-A AC8 reconciliation, CF-B executable corpus table, CF-C AC3 marked
load-bearing-not-redundant, CF-D bats-path consistency) folded pre-flip per the
0016/0025 precedent.
**Consequence:**
- New convention codified in `conventions.md` (§Bash → E2E): a credit-gated e2e fixture
  whose correctness hinges on a deterministic precondition (the backfill candidate set /
  corpus arrangement) must pin that precondition with a credit-free bats meta-test that
  reconstructs the exact arrangement and asserts the helper's output, PAIRED with an
  in-fixture direct-invocation runtime guard (load-bearing, NOT redundant). This is the
  distilled lesson of the 0025 → 0027 → 0028 lineage.
- No architecture change — a three-test-file harness edit; no new package, layer, or
  boundary. The consolidation surface (spec 0025) and the SOURCED-fixture pattern (spec
  0022, used at `[10e/13]`) are unchanged.
- No `/speccraft:spec:override` needed (`.sh`/`.bats` are not guard-gated; no Go, no
  feature change). Local gate: bats 35/35 green (4 new), Go untouched-green, `bash -n`
  clean, `git diff --name-only` lists exactly the three test files.
- Close gate is GREEN, not deferred (unlike specs 0025/0027): the credit-gated
  `e2e-devcontainer` CI run 28071351196 (push of commit `91e7835`) completed SUCCESS — the
  full lifecycle went green through `[10/13]` → `[10e/13]`. The 3-patch cycle is broken:
  the candidate-set/corpus-arrangement logic is now pinned on every CI bats job, not only
  on a credit-gated lifecycle run.
- **Follow-ups (deferred, own specs):** RCA option (3) — a distinct consolidation
  confirm-gate / opt-out so a generic "approve all" never silently relocates a spec dir;
  and genuine inline-at-close e2e coverage (a real `/speccraft:spec:close` driving
  `close.md` step 9 inside the fixture). The CONFIRM leg stays sync-driven by recorded
  decision — a real inline close would double the most expensive credit-gated step and
  reintroduce the sticky-skip collision; the close-command WIRING is pinned by
  `specs/0025-.../verify.sh` and the lib MECHANICS by `tests/hooks/spec-consolidate.bats`.

## 2026-06-24 — Decline-vs-confirm: separate e2e paths for the inline-at-close consolidation gate (spec 0027)

**Spec:** specs/0027-e2e-inline-consolidation-fix/
**Decision:** A test-harness-only fix for a regression spec 0025 introduced. Spec
0025's inline, confirm-gated consolidation at `commands/spec/close.md` step 9 was
swept into the `[10/13]` "Approve all proposed memory updates" blanket approval in the
credit-gated e2e lifecycle; with the throwaway spec `0001-add-farewell-function`
hitting zero conflicts, consolidation ran and — by design — moved its dir to
`specs/.archive/`, so the pre-0025 assertion `tests/e2e/run.sh:367`
`exists "$SPEC_DIR/changelog.md"` failed (the changelog rode along via the wholesale
`mv`). The feature behaved exactly as specified; the break was a pre-0025 lifecycle
assertion never updated for the dir-relocating close. The fix tests the two close
confirm-gates on SEPARATE paths: `[10/13]`'s prompt now explicitly DECLINES
consolidation (dir stays under `specs/`, legacy line-367/368 assertions hold) with a
new structural non-move guard `[ ! -d specs/.archive/0001-add-farewell-function ]`
that turns a model slip into an immediate, named failure at `[10/13]` rather than the
confusing downstream changelog-path failure; and `[cons 2/3]` in
`tests/e2e/spec_consolidate.sh` is documented as the inline-at-close-EQUIVALENT
CONFIRM coverage — it drives `/speccraft:sync` but exercises the SAME
`consolidate.lib.sh` route → apply_delta → dir-move path `close.md` step 9 drives
inline, with the close-command WIRING pinned by `specs/0025-.../verify.sh` and the lib
MECHANICS (incl. the changelog-rides-along `mv`) by `tests/hooks/spec-consolidate.bats`.
**Why:** It escaped the merge gate because the bats tier and `verify.sh` exercise the
helpers/doc-contracts in isolation, and the model-tier lifecycle was credit-gated and
deferred — exactly where it surfaced (CI run 28057150956, the spec-0026 1.6.0 push).
This is the spec-0014 "structural over content" lesson at the level of a command's
post-conditions: a feature that relocates a spec dir on close must be matched by the
e2e lifecycle assertion that depended on the old post-condition, updated in lockstep.
**Consequence:**
- No new convention codified — the spec-0014 structural-over-content entry and the
  spec-0025 dir-move semantics already cover the lesson; the decline-vs-confirm
  separate-paths discipline lives in this ADR rather than as a standalone rule.
- No `/speccraft:spec:override` needed (both files are `tests/e2e/*.sh`, ungated by
  speccraft-guard); no Go, no bats, no new file. The spec-0025 feature files
  (`consolidate.lib.sh`, `close.md`, `sync.md`, `memory-keeper.md`, `SKILL.md`) are
  byte-unchanged (AC4, `git diff --name-only`). "Changelog rides along" needed no new
  e2e assertion — it is a consequence of the wholesale `mv` already pinned by the bats
  `consolidate_archive_dir_move` test.
- RED→GREEN was at the credit-gated model tier (no locally-runnable test): RED = the
  observed CI failure; GREEN = the two edits; deterministic gate now is `bash -n` +
  structural inspection. AC3 (full lifecycle green through `[10e/13]`) is deferred to
  the in-flight `e2e-devcontainer` CI run 28066411890 — same deferral as spec 0025's
  model tier.
- **Follow-up:** RCA option (3) — a distinct consolidation confirm-gate / opt-out so a
  generic "approve all" never silently relocates a spec dir — is a real-user UX sharp
  edge (not just a test concern) and is deferred to its own spec. A spec-0014/0020-style
  credit-free meta-test reading `run.sh`'s live decline/non-move predicate was
  deliberately not taken (AC4 scopes this to two files); flagged as future hardening.

## 2026-06-23 — Version bump to 1.6.0 (spec 0026)

**Spec:** specs/0026-bump-version-1.6.0/
**Decision:** Coordinated `1.5.0` → `1.6.0` bump across all five live version
surfaces — the two manifests (`plugin.json`, `marketplace.json`) and the three
binary `const version` declarations (`speccraft-{state,guard,drift}`) — same
hardcoded, lockstep mechanism as specs 0019/0023; only the value moves. Each const
pinned RED→GREEN by its sibling `version_test.go` (asserts the NEW value, fails
pre-edit); manifests are plain JSON (unguarded). Marks the **README/docs
restructure** release: README slimmed to a hero + four differentiators, detail split
into `INSTALL.md`, `docs/commands.md`, `docs/architecture.md`, `CONTRIBUTING.md`, and
docs paths added to the CI `paths-ignore` lists. Pushing the bumped `plugin.json` to
`main` triggers the `auto-tag` CI job (spec 0021) → `v1.6.0` → `release.yml`. Done as
its own in-progress spec because production edits (the Go consts) require an active
spec — the guard's active-spec gate fires before anything else. No deviations beyond
skipping the plan/implement loop for a mechanical bump.

## 2026-06-23 — Closed specs consolidate into current domain specs at close (spec 0025)

**Spec:** specs/0025-spec-consolidation-on-close/
**Decision:** Closing a spec now folds its final requirements into a consolidated,
*current* domain spec at `specs/domains/<area>.md` instead of leaving N permanent
per-feature directories the reader must diff to learn "what does this area do now."
The domain set is open (a domain exists iff its file exists; no enum, no registry).
Merge vocabulary is ADD/MODIFY/REMOVE per requirement, modeled on delta-spec; an
explicit frontmatter `domains:`/`delta:` is authoritative, otherwise a path/title
heuristic SEEDS a proposed routing + classification the developer confirms — routing
is never silent. Consolidation runs INLINE at `/speccraft:spec:close` (step 9),
confirm-gated, and NEVER blocks close: decline or an open conflict still completes
close. `/speccraft:sync` (step 4) gains a confirm-gated retroactive backfill loop.
This is the same unbounded-growth / signal-decay fix spec 0024 made for `history.md`,
applied to the spec corpus itself.

Several load-bearing pins came out of two review rounds (codex + claude-p). (1) Every
MODIFY/REMOVE carries a REQUIRED verbatim target locator, matched by exact normalized
comparison with the trailing `(spec NNNN)` provenance suffix STRIPPED (provenance is
list-valued, not identity — same fact 0024 hit); a 0-or->1 match falls through to the
non-blocking conflict path, never applied to a guessed line, and a locator-less
MODIFY/REMOVE is a malformed-block rejection. This exact-locator match is the
DETERMINISTIC SEED of the model heuristic (the 0024 convention), so only genuine
ambiguity ever reaches the model. (2) TWO clock-free archives: the closed spec
DIRECTORY is MOVED wholesale to `specs/.archive/NNNN-slug/` as the LAST step, only at
ZERO open conflicts, with frontmatter `status` left `closed` — LOCATION (not a new
`status: consolidated` value) signals "already consolidated," and relocation is not
content-modification so the closed-spec-immutability guardrail is not violated;
superseded requirement TEXT is appended to `specs/domains/.archive/<area>.md` with a
self-describing header (area + spec + op) under FULL-ENTRY byte-dedup (the analogue of
0024's `history-archive/`). (3) The per-delta write order is PINNED archive-B append
FIRST → domain mutation → dir-move LAST, so a crash between the two writes can't lose
the suffix-bearing preimage; both crash windows are bats-pinned (CF-1, codex). (4) The
open-conflict sink is `consolidation-conflicts.md` inside the spec dir — not
`state.json` (would entangle the single-writer rule) and not the domain file (would
break byte-unchanged); it is DELETED on resolution and its absence is exactly the
zero-conflict precondition the dir-move gates on (CF-2, claude-p). (5) Backfill's
candidate predicate is location-based + clock-free (`status==closed` AND under
`specs/` AND no `consolidation-skip` marker), subsuming pre-feature and
declined-at-close specs; replay order is `.speccraft/history.md` chronology
(oldest-first), NOT ascending spec ID — spec ID is not closure order (history.md
proves it: spec 0001 dated 2026-05-28 vs 0002/0003 dated 2026-05-15). A spec whose
history entry was compacted out by spec 0024 falls to a `created:`-then-ID fallback
bucket, which is the dominant path for the oldest specs; it is presentation ordering
only and fails safe via the confirm-gated conflict path (CF-3 + the developer's
backfill-predicate reconciliation, claude-p).

Implemented per the spec 0022 two-tier AC split: a pure-bash
`commands/spec/consolidate.lib.sh` (the spec-0015 colocation convention) +
`tests/hooks/spec-consolidate.bats` (31 tests, all green) for the deterministic tier
(delta parse/locator-match, routing-seed key, dir-move-last + full-entry dedup, blast
radius, structural invariants, the two crash-window re-run idempotence cases); the
model-behavior tier (AC7–AC12) in a SOURCED credit-gated `tests/e2e/spec_consolidate.sh`
(`[10e/13]`, structural predicates only); and a `verify.sh` grep oracle for the doc
contracts — including the paired invariant that neither `specs/.archive/` nor
`specs/domains/.archive/` is ever added to the context-skill load list. The helper is
sourced by both `close.md` and `sync.md` and itself `source`s
`commands/history/compact.lib.sh` to REUSE spec 0024's
`history_parse_entries`/`history_provenance_ids` for the backfill chronology rather
than maintaining a second parser — an explicit cross-spec coupling pinned by a bats
test that sources both libs. `memory-keeper` is REUSED (no new agent/store): it gains
a documented `# Mode: consolidate` expanding it from append-only to propose/merge
domain requirements under confirmation, mirroring 0024's `# Mode: compact`.

A deliberate divergence from spec 0024: consolidation is INLINE at close, not a
separate `/speccraft:spec:consolidate` command. The divergence is trigger-driven —
consolidation has a natural close-time trigger (requirements are final exactly at
close), whereas 0024's compaction is periodic size-keyed maintenance with no such
trigger, so a separate explicit command was right there. New convention codified: a
shared deterministic helper sourced by more than one command may itself `source`
another command's `.lib.sh` to reuse a parser rather than duplicating it, pinned by a
bats test that sources both libs.

**Deviations:** the MODIFY new-line text is written AUTHOR-AUTHORITATIVE — the helper
does NOT mechanically re-merge the old provenance ids into the new suffix; the author
writes the merged suffix in the delta text (AC5's suffix-grammar invariant still
holds; a mechanical suffix-merge is a follow-up). No `/speccraft:spec:override` needed
(all `.sh`/`.md`/`.bats`/e2e — ungated by speccraft-guard; no Go binary added). The
e2e model tier is credit-gated, verified deterministically meanwhile (`bash -n` + 31
bats + `verify.sh`); full lifecycle run pending a real credit-gated CI run.

## 2026-06-23 — Bounded, reviewable history.md compaction (spec 0024)

**Spec:** specs/0024-history-compaction/
**Decision:** Make `.speccraft/history.md` bounded instead of unbounded
append-only (it had reached 22 entries / ~60KB, bloating the context the
`speccraft-context` skill loads). Add an explicit, confirm-gated
`/speccraft:history:compact`: keep the newest N entries (default 10) verbatim,
fold everything older into a merged thematic `## Compacted` section, and move the
originals VERBATIM into a new append-only `.speccraft/history-archive/` folder —
double provenance (archive file + git), never a deletion. A non-blocking nudge at
`spec:close` suggests it once the file is past bound. Compaction is the ONLY thing
that rewrites history.md and it never rewrites without confirmation.

Three design pins came out of two review rounds (codex + claude-p). (1) The
window is POSITIONAL — first N by `## YYYY-MM-DD` date header in file order, NOT a
date sort (the live file is genuinely not date-ordered) and NOT keyed on the
`(spec NNNN)` suffix (the real corpus has suffix-less and plural `(specs 0002,
0003)` entries, so provenance is OPTIONAL and list-valued). (2) Everything is
CLOCK-FREE: nudge by entry-count/byte-size (count>N AND (count>15 OR >40KB) — the
count>N arm kills false alarms when nothing is compactable), and a fixed-path
append-only archive (no date-stamped filenames → no same-day collisions, byte-match
dedup). (3) Supersession collapse is restricted to OUT-OF-WINDOW entries with the
pointer on the archived/summarized side — never mutating a byte-identical window
entry — which resolves the AC2/AC5 contradiction the first review caught.

Implemented per the spec's two-tier AC split (the spec 0022 precedent): a pure-bash
`commands/history/compact.lib.sh` + `tests/hooks/history-compact.bats` (19 tests)
for the deterministic tier (parse/window/provenance/archive/dedup/nudge/themes/
seed), the model-behavior tier in a SOURCED credit-gated `tests/e2e/history_compact.sh`
(structural predicates only), and a `verify.sh` grep oracle for the doc contracts —
including the load-bearing paired invariant that `history-archive/` is NEVER added
to the context-skill load list (so archiving can't silently re-bloat context).
`memory-keeper` is REUSED (no new store): it gains a documented `# Mode: compact`
that expands it from append-only to propose/summarize/merge under confirmation.

A deliberate enhancement beyond the reviewed spec: `history_supersession_seed`
pins the DETERMINISTIC core of the supersession heuristic at the bats layer
(explicit `supersedes:` markers + in-body `spec NNNN` xrefs, out-of-window only),
leaving only the thematic grouping/prose to the model — answering codex's "give the
proposal a deterministic test surface" ask. New convention codified: expose the
deterministic seed of a model heuristic at the cheap layer; let the model do only
the fuzzy part.

**Deviations:** no `/speccraft:spec:override` needed (all .sh/.md/.bats/e2e —
ungated by speccraft-guard); the e2e fixture is credit-gated, verified
deterministically (bash -n + seed-corpus-vs-lib cross-check), full lifecycle
pending user e2e; one optional refactor (T10) skipped. Tests: bats 96/96, go test
untouched-green, verify.sh 10/10.

## 2026-06-22 — Milestone version bump to 1.5.0 (spec 0023)

**Spec:** specs/0023-milestone-version-1.5.0/
**Decision:** Mark the spec-0022 milestone (PM + Architect upstream workflows)
with a coordinated 1.1.0 → 1.5.0 bump across all five live version surfaces —
the two manifests (`plugin.json`, `marketplace.json`) and the three binary
`const version` declarations (`speccraft-{state,guard,drift}`) — identical
mechanism to spec 0019, only the value moves. Each const bump pinned RED→GREEN by
its sibling version test (asserts the NEW value, fails pre-edit); manifests
verified by a grep oracle (positive `1.5.0` + no stray `1.1.0`), since they
aren't assertable from `package main`. Pushing the bumped `plugin.json` to `main`
triggers the `auto-tag` CI job (spec 0021) → pushes `v1.5.0` → fires
`release.yml`. No deviations. `-ldflags` injection (deferred since 0018) remains
a future option.

## 2026-06-22 — Optional PM and Architect workflows ship upstream of specs (spec 0022)

**Spec:** specs/0022-pm-architect-upstream-workflows/
**Decision:** Add two optional, advisory upstream workflows — PM
(`/speccraft:pm:{new,review,prioritize,close}`) and Architect
(`/speccraft:arch:{new,review,decide,close}`) — that sit above the spec
lifecycle (PM → Architect → Spec → implement), WITHOUT changing the
standalone-specs guarantee: a user who only ever wants specs+TDD sees zero
behavioral change (AC1). PM artifacts live under `product/NNNN-slug/` (`brief.md`),
Architect under `design/NNNN-slug/` (`design.md`); both reuse existing machinery
(`cross-reviewer` backs both `*:review` unchanged; `arch:close` routes durable
decisions through the existing `memory-keeper` — no new store).

Three load-bearing design choices, all driven by AC1/AC7. (1) **State shape:
additive sibling keys, not a nested record.** `state.go` gains `active_product`
and `active_design` as top-level `,omitempty` siblings of `active_spec`, which
stays byte-identical on disk. A nested `active.{product,design,spec}` or a
`kind`-discriminated record was REJECTED: it moves `active_spec` off the top
level, silently defeating the `run.sh` close-gate `jq -r '.active_spec // "null"'`,
the raw-`jq` revise preflight, and the four e2e fixture `state.json` literals —
i.e. it breaks AC1. Lane independence (close-one-preserves-others, all three
directions) is asserted at the serialization layer; the single-writer regression
lock is extended to the new lanes. (2) **AC3 doc-zone is a markdown-scoped
regression pin, NOT a `prefix()` entry.** `product/`/`design/` `*.md` are
always-allowed via the pre-existing `ext==".md"` rule; `files_test.go` adds
POSITIVE rows for the markdown plus NEGATIVE rows proving a SOURCE file under
those trees stays TDD-gated. Adding `product/`/`design/` to the `prefix()` chain
was deliberately refused — it would flip the negative rows and reopen the broad
bypass. (3) **Cross-stage linkage is pull-only and advisory.**
`spec:new --from product/<id>|design/<id>` (`commands/spec/new.lib.sh`) pulls the
referent's Why/What and writes a non-empty `informed-by: [<referent>]` key; plain
`spec:new` writes NO key (byte-shape parity). A missing, deleted, or `closed`
referent NEVER blocks spec:new — non-fatal note, command proceeds (AC8). A
`closed` brief is in fact the ideal `--from` source.

Closed-artifact immutability stays **advisory/by-convention** (same treatment
closed specs get) — NO status-aware PreToolUse guard, explicitly out of scope.
Four agents added: `pm-author`/`arch-author` (mirror spec-author) and
`pm-critic`/`arch-critic` (mirror spec-critic — narrow stage-specific self-check,
not a second quorum).

**Tests:** go test green; bats 77/77; `specs/0022-.../verify.sh` frontmatter
oracle green. Two credit-gated e2e fixtures (`pm_to_spec_bridge.sh`,
`arch_close_memory.sh`) are authored as SOURCED functions sharing `run.sh`'s
`run_claude` (a new convention — credit-gated fixtures can't subshell);
structural predicates only; `bash -n` clean but full lifecycle pending user e2e.

**Deviations:** ONE `/speccraft:spec:override` (T3) — adding the new state-lane
struct fields is a brand-new Go symbol whose Write-created sibling test can't be
observed as a runtime RED, because `applyEdit` in `speccraft-guard/main.go`
models the `Edit` tool's `new_string` but NOT the `Write` tool's `content`
(`red_candidates` empty). A real guard limitation → follow-up spec. Two optional
refactors (T10/T16) skipped; `roadmap.md` deferred (roadmap management out of
scope). Landed in commit `daaa251` (fast-forward to `main`).

## 2026-06-18 — Release pipeline self-verifies and auto-tags on version bump; the source-build fallback is no longer silent (spec 0021)

**Spec:** specs/0021-publish-release-binaries-on-version-tag/
**Decision:** Close the "plugin compiles from source at runtime instead of downloading
release assets" defect at its root: no `vX.Y.Z` tag had ever been pushed, so the
tag-triggered `release.yml` never ran, every release-asset URL 404'd, and
`install-binaries.sh`'s `curl … 2>/dev/null && …` chain masked it by falling through to
`go build`. The fix has three load-bearing parts. (1) A new `auto-tag` CI job
(`ci.yml`, `push` to `main`, gated `if github.event_name == 'push' && github.ref ==
'refs/heads/main'`) runs the pure `scripts/auto-tag.sh should_tag` and, when
`plugin.json`'s version is untagged, creates+pushes `vX.Y.Z` via
`secrets.RELEASE_TAG_PAT` — **NOT** the built-in `GITHUB_TOKEN`, because GitHub
intentionally suppresses `on: push: tags` re-triggers for events caused by the built-in
token (its infinite-loop guard); pushing with `GITHUB_TOKEN` would leave `release.yml`
silently never firing, reproducing this very bug class. (2) A new
`scripts/verify-release.sh` is a **strong-form** release-completeness oracle: it
downloads each of the four platform tarballs + `checksums.txt`, recomputes SHA-256, and
fails loudly+named on any missing asset/entry or hash mismatch. It is wired as
`release.yml`'s final self-verify step, keyed to `github.ref_name` so it can only ever
run against an existing tag — never a bare `plugin.json` value (the deadlock-free
invariant: bump→main → auto-tag pushes tag → release.yml builds+publishes+self-verifies;
no CI check fails on an unreleased version). (3) `install-binaries.sh` replaces the
silent `&&`/`2>/dev/null` chain with an explicit `if ! curl …; then warn-naming-URL;
download_ok=false; fi` (set -e safe) and writes a gitignored `.binary-provenance` marker
(`download`|`source`); `doctor.sh` reads it and reports a distinct "built from source
(download unavailable)" WARN state. The producer/consumer asset-name contract is fixed:
`release.yml` publishes `checksums.txt` (was `checksums-merged.txt`), and the file is
regenerated `sha256sum *.tar.gz > checksums.txt` over all tarballs in the release job
(fixing a per-arch checksum collision under `merge-multiple` that was beyond the named
name-mismatch scope but required for the strong-form verify to pass). All four scripts
are exercised hermetically via `SPECCRAFT_RELEASE_BASE` `file://` fixtures by sibling
shell tests wired into `run_helper_unit_tests()` (specs 0014/0020 pattern), so they gate
close credit-free.
**Why:** The documented "download a tarball on first use, no Go required" experience did
not exist for any user — every version 404'd, and the fallback succeeded quietly wherever
Go happened to be installed, so the broken pipeline was invisible. Spec 0019's
1.0.0→1.1.0 bump made it acute by invalidating cached `.binary-version` stamps. Making "a
version bump produces a release" mechanical (rather than a manual checklist step that had
never once been performed) is the durable fix; making the fallback loud + provenance-
marked ensures a future regression of this class surfaces instead of hiding. Two-round
cross-model review: revision 1 changes-requested (codex+claude-p) on the AC4/AC5 ordering
deadlock and missing oracles; revision 2 quorum met with four carry-forwards folded into
the spec before planning — CF-1 (PAT-not-`GITHUB_TOKEN`, claude-p's highest-priority
latent-correctness catch), CF-2 (both new CI surfaces are cheap-hermetic/`GITHUB_TOKEN`-
only per the spec-0008 job-split convention), CF-3 (AC5 reworded to "cannot remain
untagged after the main-push workflow succeeds"), CF-4 (strong-form checksums).
**Consequence:**
- New convention material codified in `conventions.md`: auto-tag-on-bump must push via a
  PAT/deploy key not `GITHUB_TOKEN` (§Version bumps); release completeness is verified by
  `verify-release.sh` strong-form against a `SPECCRAFT_RELEASE_BASE` `file://` fixture
  (§Version bumps); and — a previously-unwritten fact made explicit — `scripts/*.sh` and
  their sibling shell tests are NOT gated by `speccraft-guard` (only the four source
  languages are), so shell-only work needs no `/speccraft:spec:override` (§Bash). This
  last point is a documented **plan deviation**: the plan's "which steps need override"
  section assumed each new-script create-file edit would hit the build-failure-is-not-RED
  case (guardrails AC13) and need a one-shot override; in fact none did, because the guard
  ignores `.sh`.
- The `auto-tag` job is the third cheap-hermetic CI surface alongside `e2e-language-only`
  and the bats `hooks` job (§CI). It needs `RELEASE_TAG_PAT` in addition to the implicit
  `GITHUB_TOKEN`; no `ANTHROPIC_API_KEY`.
- `architecture.md` updated: the packaging layer (item 1) now records that release-asset
  delivery is automated and self-verifying, and a new §Key-boundaries entry documents the
  release/distribution pipeline (tag → build → publish → self-verify; provenance marker).
- Orthogonal CI hygiene tweak folded in (agreed with user): `ci.yml` `paths-ignore`
  extended to also skip CI for doc-only edits to `LICENSE`,
  `speccraft-technical-review.md`, `speccraft-v1-spec.md` — a deliberate *denylist*
  extension (an allowlist fails dangerous; `.claude-plugin/plugin.json` must keep
  triggering CI or auto-tag never fires).
- Outstanding ops (not unit-gated, tracked in changelog): `RELEASE_TAG_PAT` secret DONE
  by user; T14 (the push landing this work auto-tags `v1.1.0` and triggers the first real
  release) verified in CI run history. Watch-item: the verify step runs immediately after
  release creation — a transient asset-propagation 404 on the first run would be a
  one-line retry/sleep follow-up. T15 (DRY four-tarball-name emitter) deferred.

**Follow-up (2026-06-18, hotfix to `ci.yml`):** the first real run of the `auto-tag`
job failed — `git push` for `v1.1.0` was denied as `github-actions[bot]` (403 on this
*private* repo), i.e. the PAT was never used. Root cause: `actions/checkout` persists the
built-in `GITHUB_TOKEN` as an `http.extraheader`, which **takes precedence over inline URL
userinfo** — so the `git remote set-url origin https://x-access-token:${PAT}@…` approach
silently authenticated as the bot. Fix: pass the PAT to checkout itself
(`token: ${{ secrets.RELEASE_TAG_PAT }}`) so the *persisted* credential is the PAT, and
push plainly (dropped the `set-url` + `env:` block). New gotcha to remember: **to push from
CI with a non-default identity, set checkout's `token:`, never `git remote set-url`.**

## 2026-06-15 — Tolerant regex for the e2e revise no-op assertion; meta-test reads run.sh's live predicate (spec 0020)

**Spec:** specs/0020-robust-e2e-revise-noop-assertion/
**Decision:** The `[6/13] revise no-op` step in `tests/e2e/run.sh` grepped the live `claude -p`
final-message log with fixed-string `contains "...06-revise-noop.log" "no changes"`. The command's
no-op branch emits a deterministic marker (`no changes — spec unchanged`), but the model paraphrased
it ("no-op", "byte-identical"), so the fixed-string grep missed — a phrasing flake, not a defect.
Swapped to `contains_regex "[Nn]o.?op|[Nn]o changes|byte-identical|unchanged"`; the structural
`^revision: 1` check stays unchanged and load-bearing. Did NOT touch `revise.md` / `revise.lib.sh`
(per spec 0017, hardening model-output compliance isn't durable). RED→GREEN on a shell-only change
was achieved via a new meta-test, `tests/e2e/revise_noop_assertion_test.sh`, mirroring spec 0014's
`contains_adr_assertion_test.sh`: it reads run.sh's *live* assertion line and pattern at runtime
(rather than hardcoding a copy) so the two cannot silently diverge, and is wired into
`run_helper_unit_tests()`. Planned with `--skip-review`.
**Why:** The third spec in the lineage (0014 structural-over-content, 0017 don't-harden-model-output,
now 0020) treating model phrasing as untrustworthy at the assertion layer. The marker the command
emits is deterministic, but the model's surrounding final-message paraphrase is not; the assertion
must tolerate the model's word choice while still pinning a real signal.
**Consequence:** The no-op step no longer flakes on phrasing. Because `run_helper_unit_tests()` runs
in BOTH the credit-free `--language-only` path and the full lifecycle path, the new meta-test is a
real close gate that needs no API credits — contrast spec 0017/0018, whose model-behaviour e2e steps
are credit-gated and nondeterministic. The "meta-test reads run.sh's live predicate" pattern now has
its second use and is codified as a named convention.

## 2026-06-15 — Bump version to 1.1.0 across all live surfaces (spec 0019)

**Spec:** specs/0019-bump-version-to-1-1-0/
**Decision:** Bump 1.0.0 → 1.1.0 on every live version surface in one coherent release cut:
the two packaging manifests (`.claude-plugin/plugin.json`, `marketplace.json`) and the three
binary `const version` declarations (speccraft-state/guard/drift). The hardcoded `const version`
mechanism is unchanged — only its value. Each const bump was gated by a real RED→GREEN version
test (the test asserts the NEW value, so it fails before the edit), and manifests were verified
by a grep oracle (positive 1.1.0 matches plus a negative check for stray 1.0.0), since manifests
aren't assertable from `package main`. Planned with `--skip-review`.
**Why:** Feature work had accumulated past 1.0.0 (latest = spec 0018) while every `--version`
surface still reported 1.0.0. A single coordinated bump keeps the manifests and binaries telling
one story for the next release.
**Consequence:** `--version` parity across the three binaries is now pinned by tests — a regression
on any one binary's reported version fails CI. The drift binary gained its first test file as a
result. Build-time `-ldflags` version injection (P2-5, deferred from the spec 0018 technical
review) remains a follow-up; until then version is a hand-edited const and future bumps must touch
all five surfaces.

## 2026-06-13 — Real red→green TDD check for Go/Python/JS-TS; runner primitive generalized beyond Rust (spec 0018)

**Spec:** specs/0018-technical-review/
**Decision:** Close technical-review finding P0-1: the marketed "red→green invariant" was a
true observed-failure check only for Rust, while Go/Python/JS-TS merely verified that *a*
sibling test file was *touched* this session (`hasSiblingTestEdited`, `main.go:390`; the
JS/TS session-membership loop, `main.go:446-452`). A blank line in any matching test file
unlocked every production file in its directory. Spec 0018 makes all four languages run the
session's just-added sibling test through a real runner and require an observed failure. The
spec-0005 test-runner invocation primitive — explicitly scoped to Rust at the time, with
"retroactive adoption by Go/Python is a non-goal" written into `architecture.md` — was
generalized: new `GoAdapter`/`PytestAdapter`/`JSTSAdapter` (one shared JS/TS adapter, JS and
TS differing only by configured command) reuse `classifyOutcome`, and a new
`runner.AdapterForLanguage(lang, cfg) (Runner, bool)` factory resolves them. The
"which test failed" rule mirrors Rust's just-added model via a new capture mechanism:
`Session.RedCandidates map[string][]string` (JSON `red_candidates,omitempty`,
single-writer, cleared on `SessionStart`) is populated in the `IsTestFile` dispatch branch
by `captureRedCandidates`, which diffs pre-edit disk content against the `applyEdit`-modelled
post-edit content through the per-language regex extractors `GoTestIDs`/`PythonTestIDs`/`JSTSTestIDs`.
A shared `siblingRedCheck` (used by both the Go/Python guard and the JS/TS dispatcher)
unions those candidates over the resolved siblings, runs the adapter under a 30s
`context.WithTimeout`, and accepts only when a `failed` record's id is in the just-added set.
**Why:** This was the project's highest-impact correctness gap — speccraft sold one guarantee
and enforced it for one of four supported languages. The decided direction (over the
honest-rename alternative the review also offered) was to make the red→green name *true*. Two
deliberate, load-bearing divergences from the Rust reference were required. First, the empty
just-added set **blocks** for Go/Python/JS-TS (Rust *allows* on empty because its persisted
`rust_test_baseline` already attests a prior RED; these languages have no such baseline, so
allowing-on-empty would reopen P0-1 via a blank-line touch — claude-p caught that an
implementer copying Rust's `if len(justAdded)==0 { return nil }` would silently regress).
Second, an unresolved/uninvocable runner **fails closed** (BLOCK "no test runner available"),
never falling back to the touch-check, because a fallback would let an arranged-absent runner
re-open the exact bypass. The 30s deadline (AC9) closes a real hang vector: a runtime runner
called with `context.Background()` could wedge the interactive hook indefinitely; a timeout
surfaces as a Go error (the `Outcome` taxonomy does not grow) and blocks.
**Consequence:**
- New convention codified: the **capture-at-test-edit RedCandidates model** for
  runtime-runner languages that lack a persisted baseline. When a language's red-check has no
  equivalent of `rust_test_baseline`, the just-added test set is captured at *test-edit* time
  (post-edit minus pre-edit ids via a per-language extractor) into a single-writer `Session`
  map, and an empty just-added set must BLOCK, not allow.
- `architecture.md` layer-8 and §Key-decisions were rewritten in this spec to record the
  generalization and scrub the spec-0005 "non-goal" sentence at both sites (AC11). A new
  Go-test oracle `tools/internal/speccraft/docs_parity_test.go` greps `architecture.md`/
  `index.md`/`guardrails.md`/`speccraft-technical-review.md` so the parity claims cannot
  silently drift back.
- `Session` gains `red_candidates`; the single-writer grep allow-list
  (`state_single_writer_test.go`) was extended per the existing "adding a `Session` field
  requires extending the allow-list" rule.
- A documented limitation (AC13), added via the spec-0013 mid-implementation amendment
  convention (its fourth use, after 0013 T6, 0015 T18, 0017): introducing a brand-new
  production symbol whose just-added test cannot compile until the symbol exists is a build
  failure, which AC6 refuses to treat as RED — and the gated production edit is the one that
  would make it compile. The sanctioned path is a one-shot `/speccraft:spec:override`,
  identical to Rust today; `run.sh` step 9 was rewritten to test-edit → override → production
  edit. The amendment also corrected stale `/spec:override` strings to the fully-qualified
  `/speccraft:spec:override`. Deferred follow-up: an apply-edit-in-memory red-check that runs
  against the post-edit package so a new symbol's test compiles and fails at runtime,
  eliminating the override step.
- The hermetic e2e fixtures `python_cycle.sh` and `javascript_cycle.sh` were rewritten to the
  red-check model using a *configured-stub* runner (no real pytest/node), still running in
  the cheap `e2e-language-only` job with no API key.
- This closes P0-1 only. The other review findings (P0-2 fail-open on corrupt state, P1
  MultiEdit/NotebookEdit parsing, e2e-on-PR, quorum/verdict hardening, CI static analysis,
  the P2 cleanups) remain tracked for follow-up specs.
- Close gate: PR #1 merged to `main` (merge `ddc1136`, feature `8c74168`); CI green
  (`unit`/`hooks`/`e2e-language-only` on the PR), with the credit-gated `e2e-devcontainer`
  lifecycle job — which exercises AC13 at step 9 — running on push to `main`.

## 2026-06-12 — Pin the e2e harness model explicitly; Sonnet default reverted after it failed the validation gate (spec 0017)

**Spec:** specs/0017-e2e-default-model/
**Decision:** `run_claude()` in `tests/e2e/run.sh` now passes
`--model "${CLAUDE_MODEL:-claude-opus-4-8}"` as the first argument after
`-p`, so every `claude -p` lifecycle call selects an explicit, pinned
model that is overridable via the `CLAUDE_MODEL` env var. The `--help`
usage block gained an `env:` section documenting `CLAUDE_MODEL` and
`CLAUDE_BIN`, and the spec-0008 capture probe
`tests/e2e/assertions/test_run_claude_capture.sh` gained check #4 pinning
the `--model` line via `grep -qE` on the extracted `run_claude` body. The
spec was reviewed and approved with a `claude-sonnet-4-6` default (the
cost-optimization thesis); a same-cycle amendment (2026-06-12) reverted
the default to `claude-opus-4-8`. The override var, the docs, and probe
check #4 were retained — only the default string changed.
**Why:** Before this spec the harness passed no `--model`, silently
inheriting whatever the account/CLI default happened to be — a mutable,
invisible dependency for the only CI job that actually drives Claude. The
original motivation was to cut CI cost by defaulting the credit-gated
`e2e-devcontainer` lifecycle to Sonnet 4.6. Both cross-model reviewers
(codex, claude-p) returned approve-with-comments and explicitly flagged
the risk: switching the default tier changes the model under test, with no
evidence Sonnet passes the ~10-call lifecycle. claude-p named the next
`e2e-devcontainer` run as the validation gate. That gate run
[27367642623](https://github.com/DCSTOLF/speccraft/actions/runs/27367642623)
(commit `537b769`) failed at `[9/13] TDD invariant` with a genuine
assertion failure and **no** `ENVIRONMENT_FAILURE` tag: on Sonnet 4.6 the
model invoked `/speccraft:spec:override` on the GREEN step — unnecessary,
since the test was already written and the TDD guard would have allowed
the edit — then stalled without writing `farewell()`, so `contains
main.go: farewell` failed. For contrast, the prior commit `4529323`'s
Opus-default run [27348320071](https://github.com/DCSTOLF/speccraft/actions/runs/27348320071)
failed the same step only with `ENVIRONMENT_FAILURE: credit_exhausted` —
an env issue, not a defect. The Sonnet failure was a real model-behaviour
regression, so the cost-optimization thesis was abandoned and the default
reverted.
**Consequence:**
- The cost-optimization goal was **not** achieved. The durable win that
  remains: the e2e harness's model selection is now explicit and pinned in
  `run.sh` (not silently inherited from a mutable account/CLI default) and
  overridable via `CLAUDE_MODEL` — codex's stronger framing in review.
  Anyone wanting Sonnet (or any model) for a local run sets `CLAUDE_MODEL=...`.
- The mid-implementation amendment convention (spec 0013) was reused: the
  revert is a strictly bounded one-line default change plus its paired
  probe check, the spec's own validation gate kept CI red until it landed,
  and the theme is identical (this spec's subject *is* the e2e default
  model). AC1/AC3 were updated in place to name `claude-opus-4-8`; AC2/AC4
  unchanged. This is the third use of the amendment pattern after specs
  0013 (T6) and 0015 (T18).
- The Sonnet `[9/13]` failure is a concrete instance of the spec-0014
  "structural over content" lesson generalised one level: the e2e
  lifecycle's *behaviour* (not just its assertion phrasing) varies by
  model. A model-behaviour failure in the credit-gated `e2e-devcontainer`
  run — the model reaching for `/speccraft:spec:override` on a GREEN step
  — is a legitimate close/no-close signal, and the spec-0008
  `ENVIRONMENT_FAILURE:` classifier is exactly what let CI distinguish it
  from the prior commit's `credit_exhausted` env flake. No new convention
  codified; the existing 0014 and 0008 entries are canonical.
- No architecture change. `tests/e2e/run.sh` and its assertion fixtures are
  already the documented e2e surface in architecture.md §Layering item 12;
  the `--model` flag is a behavioural pin within that surface, not a new
  layer or boundary.
- Close gate: CI run
  [27386675522](https://github.com/DCSTOLF/speccraft/actions/runs/27386675522)
  on commit `a016dae` (Opus default) is fully green including
  `e2e-devcontainer`.

## 2026-06-11 — Scrub README + v1-spec CodeGraphContext routing prose (spec 0016)

**Spec:** specs/0016-scrub-readme-v1-spec-cgc-routing/
**Decision:** Doc-only scrub applying spec 0011's
"External-tool boundaries" principle to the two human-facing
prose surfaces spec 0011 explicitly deferred: `README.md`
(3 edit sites at lines 355, 365, 383) and `speccraft-v1-spec.md`
(5 edit sites at lines 33, 697, 1132, 1369, 1792). Eight
prescriptive routing phrases — "prefer X", "should install X",
"X is the recommended way" — replaced with neutral factual
descriptions and example framing ("such as CodeGraphContext").
The neutral anchors `Recommended companions` (README section
header) and `**Recommended companion:**` (v1-spec §13 bolded
label, line 1369) were preserved as the surviving discovery
prose. A new `specs/0016-scrub-readme-v1-spec-cgc-routing/verify.sh`
(108 lines, 12 labelled `grep -F` checks: 5+1 README, 5+1
v1-spec) is the AC oracle — every check is file-scoped to
`README.md` or `speccraft-v1-spec.md` by name (AC3); repo-wide
`grep -r` is forbidden because the absence-target strings
literally appear inside this spec's own `spec.md`. A defensive
paraphrase pin (check #5, `prefer CodeGraphContext for structural
queries`) is trivially green in this cycle — its job is to fail
RED if a future rewrite reintroduces a near-variant of the
banned wording.
**Why:** Spec 0011 codified the External-tool boundaries
principle in `templates/speccraft/conventions.md` and scrubbed
the three model-loaded surfaces it identified
(`skills/speccraft-context/SKILL.md`, `commands/init.md`,
`templates/speccraft/architecture.md`) but explicitly deferred
the two human-facing prose surfaces. The deferred work was
queued as a follow-up across specs 0011 → 0013 → 0014 → 0015;
this spec closes that gap before the stale prose drifts further
or new contributors absorb it as the convention. The
prescriptive prose at README:365 (`It's the recommended way to
answer`) was an exact match for the conventions.md banned
phrasing pattern — the most acute violation among the eight,
caught by claude-p in round 1 and pinned as AC1 absence check
#3. Two-round review caught real gaps round 1 missed: round 1
returned `changes-requested` from both reviewers; the author
applied five edits between rounds (AC1 expanded from 2→5 README
pins, AC2 expanded from 2→5 v1-spec pins, AC2 presence anchor
added, AC3 file-scoped grep rule added, an Out-of-scope
contradiction resolved). Round 2 both `approve-with-comments`,
quorum met. claude-p's round-2 catch — that the spec body
itself misattributed the `**Recommended companion:**` bolded
label to §20.1 when it actually lives at §13 line 1369 — was
fixed pre-commit, before flipping `status: reviewed`. The
README:544 borderline-prescriptive sentence was explicitly
disclosed in §Out-of-scope and intentionally left in place
under the AC1 narrowing — future-reader signal, not a missed
scrub.
**Consequence:**
- Spec 0011's queued "README + `speccraft-v1-spec.md`
  CodeGraphContext cleanup" follow-up is **resolved** by this
  spec. Combined with spec 0015 resolving the
  `/speccraft:spec:revise` follow-up, every queued item from
  spec 0011's §Out-of-scope is now closed except the
  closed-spec residual in `specs/0001-speccraft-v1/spec.md`,
  which spec 0011's history.md entry already accepted as
  historical record.
- The "Grep-assertion oracle for doc-only specs" convention
  from spec 0011 has now been used a second time (after spec
  0011 itself). The pattern generalised cleanly — file-scoped
  greps, labelled checks, paired absence/presence per file, a
  defensive paraphrase pin for forward-protection — without
  needing refinement. No new convention codified; the existing
  rule in `.speccraft/conventions.md` is canonical.
- The codex round-2 implementation note (label presence checks
  as explicitly as absence checks so failure messages
  distinguish over-deletion from missed scrub) was folded into
  `verify.sh` directly via labels like `[presence: README
  "Recommended companions" section header]`. Future doc-only
  specs that copy this `verify.sh` as a template will inherit
  the labelling discipline implicitly.
- No architecture change. README.md and `speccraft-v1-spec.md`
  are top-level repo prose, not part of any execution surface
  in `.speccraft/architecture.md` §Layering. The eight edits
  preserved descriptive content (factual MCP-server capability
  descriptions, factual roadmap mentions) and only removed
  prescriptive verb/phrasing — `verify.sh` checks plus the T4
  semantic-drift refactor pass guard against half-sentence
  artefacts.
- AC4 closed-spec immutability held: `git diff cf0d094..HEAD --
  specs/0001-speccraft-v1/spec.md` is empty, confirming the
  spec-immutability rule from spec 0011's close was respected.

## 2026-06-11 — /speccraft:spec:revise + commands/<group>/<name>.lib.sh colocation (spec 0015)

**Spec:** specs/0015-spec-revise-command/
**Decision:** Add `/speccraft:spec:revise` as a first-class sibling
under `commands/spec/` for pre-implementation spec revision.
Mechanism: a new `agents/spec-reviser.md` subagent
(tools `[Read, Write, Edit, Bash]` — no `Agent`, per spec 0011)
re-runs a Socratic interview against the existing spec body, while
the command body owns all command-only frontmatter mutations
(`revision:`, `status:`, `id:`, `created:`). The command's
preflight + cross-check + diff + archive logic is extracted into
**`commands/spec/revise.lib.sh`** — the first sourceable Bash
helper under `commands/spec/`, sourced both by the `.md` body at
runtime and by `tests/hooks/spec-revise-preflight.bats` at test
time. Drift items surfaced by the optional `packages[]` cross-check
are emitted by the subagent with the load-bearing `^Q-DRIFT:`
prefix anchored at column 0 — pinned in the agent prompt body so
the e2e grep is a structural anchor, not a content guess
(per spec 0014). After the agent runs, the command re-checks the
four command-owned frontmatter fields against a pre-agent snapshot
(`frontmatter_integrity_check`) and refuses the run if the agent
ignored the forbidden-edits contract. T18 mid-implementation
amendment (2026-06-11) reworded AC3/AC4 from "state.json
byte-identical" to "`active_spec` field unchanged" — the original
predicate was over-specified, since the PostToolUse hook
correctly updates `session.edited_prod_files` when the agent
issues `Edit spec.md`.
**Why:** Pre-implementation revision had been an unowned gap
since the 2026-06-09 `/speccraft:spec:new` session that
improvised the flow — the issue was deferred across specs 0011,
0013, 0014 as queued follow-up. The two existing repair paths
were inadequate: hand-editing spec.md + re-running `/spec:review`
left no audit trail, and the spec-0013 "mid-implementation
amendment" convention applies only to `in-progress` specs.
Pre-implementation revision needed the same Socratic rigor as
`/spec:new` plus a structural audit trail (revision counter,
archived `review-r<N>.md` / `plan-r<N>.md` / `tasks-r<N>.md`).
Extracting the Bash mechanism into `revise.lib.sh` was the only
test-layer choice that kept AC1/AC2/AC9/AC10 (preflight error
paths, no model in the loop) out of the credit-gated lifecycle
job — they live in bats at zero credit cost, while AC3–AC8/AC13
(agent-dependent) live in `tests/e2e/run.sh` `[5/13]`–`[7/13]`.
T18's AC3/AC4 rework was triggered by the false positive on CI
run 27314550595's first attempt (commit `0c063ed`): the byte-
compare assertion treated normal hook session-tracking as a
contract violation. The contract revise actually needs is
single-writer discipline + `active_spec` stability, not whole-file
byte equality.
**Consequence:**
- New convention codified under §Bash → "Sourceable command
  helpers: `commands/<group>/<name>.lib.sh` colocation". Helper
  Bash backing a slash command lives next to the `.md` body;
  sourced by both runtime and tests; pure functions only (no
  top-level side effects) so bats can source the file without
  triggering work. Canonical reference is
  `commands/spec/revise.lib.sh` + `tests/hooks/spec-revise-preflight.bats`.
  This pattern is sibling to the `tools/cmd/speccraft-*` Go binary
  pattern, distinct in that `.lib.sh` runs in-process inside the
  command's shell rather than as a separately invoked binary.
- §"Markdown frontmatter" contract tightened to match the
  de-facto convention already observed across the codebase:
  subagent contract is `name/description/tools/model` (6/6 files
  under `agents/` already carry `model:`); slash command contract
  is `description/argument-hint/allowed-tools` (8/8 files under
  `commands/spec/` already carry all three). The pre-tightening
  conventions.md text understated what speccraft itself had been
  shipping since spec 0005.
- §Layering bullet 3 in architecture.md updated to call out the
  new sourceable-helper colocation pattern under `commands/`.
- Spec 0011's queued `/speccraft:spec:revise` follow-up is
  resolved by this spec. The remaining queued follow-ups (README
  + `speccraft-v1-spec.md` CodeGraphContext cleanup) are carried
  forward — neither was touched here.
- Mid-implementation amendment convention (spec 0013) reused
  cleanly: T18 added a dated `## Amendment (2026-06-11)` section
  to spec.md, a T18 entry to tasks.md, and reworded AC3/AC4 in
  place. The three conditions held (bounded edit, CI-blocking,
  theme overlap). This is the second use of the pattern after
  spec 0013's own T6.
- New e2e step trio `[5/13]` / `[6/13]` / `[7/13]` introduced in
  `tests/e2e/run.sh`; downstream `[N/M]` markers renumbered to a
  unified `/13` scheme, resolving the pre-existing `[N/9]` vs
  `[N/11]` inconsistency carried over from spec 0014.
- CI close gate: run 27314550595 on commit `0c824f9` green
  across all jobs, including the new `[5-7/13]` revise lifecycle
  and the 53 new bats tests under `spec-revise-preflight.bats`.

## 2026-06-10 — E2E contracts encode structural predicates, not model-chosen content (spec 0014)

**Spec:** specs/0014-tighten-e2e-history-assertion/
**Decision:** When an e2e assertion verifies that a model-driven
step happened (memory-keeper applied an ADR, spec-author wrote a
plan, planner emitted a `## Risk` section, etc.), the predicate
must target a STRUCTURAL signal the agent's contract guarantees,
not a CONTENT signal the agent's free-text choice happens to
produce. Concretely: `tests/e2e/run.sh`'s `[7/9]
/speccraft:spec:close` assertion at line 278 now matches the
dated ADR-header shape `^## 20[0-9]{2}-[0-9]{2}-[0-9]{2}` (via a
new `contains_regex` helper, `grep -qE`) rather than the literal
word `farewell` from the test-spec title. Helpers are extracted
to a new `tests/e2e/lib.sh` that both `run.sh` and a new fixture
(`tests/e2e/contains_adr_assertion_test.sh`) source, so the
predicate is provably identical between production harness and
fixture.
**Why:** CI run 27276707529 on commit `ed3fe24` failed identically
across attempts 2 and 3 (attempt 1 was
`ENVIRONMENT_FAILURE: credit_exhausted`). Both failed attempts
produced model-chosen ADR titles like *"Defer stdout-capture
testing for main()"* — design-rationale phrasings that never
mention the feature. The previous green run on `9c1330d`
(27275588005) was the same flake getting lucky; plugin code was
identical between the two commits, only the model's random seed
differed. The principle generalises: agent-driven artefacts have
free-text surfaces the e2e harness cannot pin without making the
agent's prompt deterministic, which is a much larger surface to
change than the assertion. Tightening the assertion is the
correct layer of fix; CI run 27287309940 on the post-spec push
(`b535629`) is the first run in which the structural assertion
fires deterministically.
**Consequence:**
- New convention: e2e assertions verifying model-driven steps
  target structural signals (header shape, exit code, field
  presence) not content signals (specific words, titles, free-
  text choices). Codified under §Bash → "E2E assertion
  predicates: structural over content".
- New convention: shared assertion helpers used by both
  `tests/e2e/run.sh` and any sibling fixture live in
  `tests/e2e/lib.sh` (sourced, not duplicated). The "exact
  predicate" invariant — that a fixture testing the production
  harness's predicate must use the *same* helper implementation,
  not a copy — is load-bearing. Naive `source run.sh` from a
  fixture executes the entire harness; helper duplication
  invites silent drift between fixture and production. Codified
  under §Bash → "Shared assertion helpers via tests/e2e/lib.sh".
- New `contains_regex` helper (in `lib.sh`) is sibling to the
  existing `contains` (fixed-string `grep -qF`). Pick fixed-
  string vs regex explicitly at the call site rather than
  overloading `contains` with a flag.
- New `run_helper_unit_tests()` in `run.sh` is sibling to
  `run_language_fixtures()` and runs first in both the
  `--language-only` short-circuit and the full lifecycle path —
  helper regressions fail fast before the language cycles or
  `claude -p` steps run.
- Step-counter `[N/M]` in `run.sh` bumped from `/10` to `/11`
  for the lifecycle path. The plan literally specified the new
  helper-test echo as `[11/11]` placed above the existing
  `[8/10]` line; the executor's variant placement at `[8/11]`
  (first, sequential) is cosmetic-only and functionally
  equivalent.

## 2026-06-10 — Post-0012 dead-code cleanup + amendment precedent (spec 0013)

**Spec:** specs/0013-remove-dead-active-spec-null-checks/
**Decision:** Post-0012 cleanup completed: the two defensive
`ActiveSpec == "null"` reads at
`tools/internal/speccraft/root.go:45` and
`tools/cmd/speccraft-guard/main.go:353` were removed under
sibling-test pins (one classical RED→GREEN, one
assertion-pinning refactor). The `omitempty` + clear-semantics
work from spec 0012 made both clauses unreachable; this spec
flips the in-process behavior so future readers see one truth
("`null` is an ordinary string id; the cleared shape is key
absent") instead of two false-positive fallbacks. A
mid-implementation amendment (T6) added a Go setup +
helper-binary build step to the CI `hooks:` job; without it,
spec 0012's new `pre-tool-use-state-guard.bats` reject cases
were silently no-op'ing because `speccraft-state` was not on
`$PATH` in CI.
**Why:** The dead clauses themselves were harmless but corrosive
— leaving them invited future readers to invent nonexistent
semantics for the literal string `"null"`. The CI miss was the
real teaching moment: spec 0012 closed against a green
`e2e-devcontainer` run that never actually exercised the new
bats guard, because the bats job lacked the binaries the hook
depends on. CI run 27275588005 (on commit 9c1330d) is the first
run in which both spec 0012's AC5 close gate and spec 0013's
AC5 close gate were truly satisfied.
**Consequence:**
- Mid-implementation amendment precedent codified in
  `conventions.md` § Spec lifecycle. When CI surfaces a bounded
  issue between push and close that shares the active spec's
  theme and (a) is a strictly one-file edit, (b) keeps main CI
  red until it lands, and (c) does not require any AC change
  other than additive, the issue MAY be folded into the active
  spec as a new task + new AC + a dated `## Amendment` section
  in `spec.md`, rather than filed as a follow-up spec.
- Close-gate-pending workaround formalised. When a spec closes
  with a `<!-- TODO: <github-actions-run-url> -->` marker in its
  changelog (close gate not yet green at close time), and a
  subsequent spec's CI run satisfies the gate, the URL is
  recorded in the **subsequent** spec's changelog with an
  explicit cross-reference to the predecessor. The predecessor's
  TODO marker is left in place per the "No post-close edits"
  rule. A post-close backfill exception was evaluated this
  close batch and explicitly rejected in favor of strict
  immutability.
- The two defensive `== "null"` clauses flagged in 0012's ADR
  are gone. No further dead-code follow-up is queued from the
  0012 era.
- T6 reinforces an existing convention rather than creating a
  new one: the spec-0008 CI job-split convention already implies
  "build what each job needs" — the bats job was missing the
  binaries the hook depends on at runtime. No fresh CI
  convention is proposed.

## 2026-06-10 — Runtime single-writer enforcement for .speccraft/state.json (spec 0012)

**Spec:** specs/0012-clear-active-spec-correctly-on-close/
**Decision:** Single-writer rules for files speccraft owns are now enforced
at two layers — source-level grep (existing `state_single_writer_test.go`)
plus a runtime PreToolUse hook check that rejects any
`Edit`/`Write`/`MultiEdit`/`NotebookEdit` whose `file_path` canonicalises
to `<root>/.speccraft/state.json`. Source-level enforcement alone is
insufficient because a `claude -p` lifecycle session can write through a
tool call the grep test never sees. Adjacent: `State.ActiveSpec` carries
`,omitempty` so the cleared shape on disk is "key absent" rather than a
sentinel string, and a new `speccraft-state init` subcommand replaces the
old Write-the-canonical-JSON path in `commands/init.md` so the new hook
cannot break first-run `/speccraft:init`.
**Why:** Triggered by CI run 27178536892 on 2026-06-09. The
`e2e-devcontainer` job's step `[7/9] /speccraft:spec:close` failed the
assertion `jq -r '.active_spec // "null"' state.json` because a tooling
bug (`speccraft-state set active_spec null` wrote the literal string
`"null"`) induced a model workaround — a direct `Edit` of `state.json`
to clean up the artifact. The source-layer grep test caught no
source-tree regression; the violation lived in a runtime tool call.
Source + runtime enforcement together close that gap.
**Consequence:**
- New `speccraft-state init` subcommand is now the only sanctioned
  creation path for `.speccraft/state.json`. Idempotent: silently no-ops
  if the file already exists, so `/speccraft:init` re-runs cannot nuke
  session state. Both behaviors pinned by
  `tools/cmd/speccraft-state/main_test.go`.
- `hooks/pre-tool-use.sh` gates on the full set of Claude Code write
  tools via a `GATED_TOOLS` enumeration; `hooks/hooks.json` matchers
  must be extended in lockstep when a new write-tool name is added.
  Codified as a convention so the next write-tool name is a paired
  one-line change, not a hidden gap. Six new bats cases under
  `tests/hooks/pre-tool-use-state-guard.bats` cover the reject path
  for each gated tool plus an allow case for sibling memory files.
- `State.ActiveSpec` is now serialised with `,omitempty`. Two
  defensive reads for the literal `"null"` string at
  `tools/cmd/speccraft-guard/main.go:353` and
  `tools/internal/speccraft/root.go:45` became dead code; left in
  place under the TDD-hook constraint and queued for a follow-up spec.
- §What item 4's test-naming clarification landed concurrently: both
  `Test<UpperCamel>` and `Test_<Subject>_<Scenario>` are documented as
  acceptable in `.speccraft/conventions.md`. The enforce regex
  `^func Test[A-Z]` is unchanged — tightening would force a global
  rename, which is out of scope.

## 2026-06-09 — Defer code-intel routing to user globals (spec 0011)

**Spec:** specs/0011-code-intel/
**Decision:** Speccraft does not duplicate routing authority for external
code-intelligence tools it does not own. The `speccraft-context` skill,
the `init` command, and the `architecture.md` template no longer name
CodeGraphContext (or any other code-intel tool) as the way to answer
structural queries; instead they defer to whatever the user's installed
tool has registered in the environment, typically via global CLAUDE.md
or the MCP server's own instructions. One example mention of
CodeGraphContext survives in the conditional install-suggestion in
`commands/init.md`, framed as "such as CodeGraphContext" — examples
allowed, brand endorsements not.
**Why:** Triggered by a real `/speccraft:spec:new` session on 2026-06-09
where speccraft's skill ("prefer codegraph MCP tools") and the user's
global CLAUDE.md (written by `codegraphcontext mcp setup`, encoding the
heavy/lightweight tool distinction and Explore-subagent quarantine
rule) gave conflicting routing guidance for the same tool family. The
model resolved the conflict in favor of the more specific global rule,
but the conflict itself was wasted attention and would silently drift
further as cgc's rules evolved. Speccraft owns spec lifecycle, TDD
gate, and project memory — it does not own how to call other people's
MCP servers.
**Consequence:**
- New principle codified in conventions.md under "External-tool
  boundaries": when an external tool writes routing rules into the
  user's environment, speccraft defers rather than maintaining a
  parallel copy.
- Doc-only specs now have a documented oracle pattern: a committed
  `verify.sh` grep-assertion script that fails RED on current main and
  passes GREEN after the edits. Sibling to the E2E language-fixture
  pattern; codified in conventions.md.
- README.md and `speccraft-v1-spec.md` retain stale CodeGraphContext
  copy (out of scope here); follow-up cleanup pass is queued.
- `specs/0001-speccraft-v1/spec.md` also retains the original
  CodeGraphContext integration claim. Spec is closed and immutable;
  residual reference is accepted as historical record.

## 2026-06-09 — JavaScript and TypeScript support (spec 0010)
**Spec:** specs/0010-javascript-typescript-support/
**Decision:** Add JS/TS as a first-class language in `speccraft-guard` via pure file classification plus session-state sibling lookup. No Node/npm/Jest/Vitest is invoked. Test recognition uses 16 suffix variants (`.test`/`.spec` × `.js/.ts/.jsx/.tsx/.mjs/.cjs/.mts/.cts`) plus the `__tests__/` immediate-directory convention. Production recognition uses the same extension set minus declaration files and test files. Both classifiers apply a segment-exact exclusion for `node_modules` and `dist`. Before adding `jsTsDispatch`, the shared red-phase preamble in `goPythonProdGuard` was lifted into a tri-state `prodGuardPrologue` helper returning `prologueAllow` / `prologueBlock` / `prologueContinue`.
**Why:** JS/TS is the largest active language ecosystem and a foreseeable adoption blocker. Keeping the guard runtime-free preserves the "no real runner in the hook" invariant established in 0002/0005 and avoids dragging a Node toolchain into every speccraft install. Extracting the prologue first kept the new dispatcher honest about gate symmetry with Go/Python and prevented subtle drift between languages.
**Consequence:** Adding the next language (e.g., Ruby, C#) is now a smaller change: implement `<lang>Dispatch` reusing `prodGuardPrologue`, add a case in `dispatchByLanguage`, extend `IsTestFile`, ship a `tests/e2e/<lang>_cycle.sh` fixture, and bump the run.sh step counter. Four rounds of spec review were needed to reach this shape — reviewers pushed back on real-Jest invocation, runtime sibling resolution, and test/production extension asymmetry, all of which would have broken the existing language model. `--language-only` CI now runs 10 language fixtures.

## 2026-06-08 — fix override no-op (spec 0009)

**Spec:** specs/0009-override/
**Decision:** The Go/Python production-edit guard now consults a persisted, single-shot `OverridePending` flag on `Session` (in `.speccraft/state.json`). The flag is consumed atomically by a new `ConsumeOverride(root) (bool, error)` API that reads-and-clears under a single `mu.Lock()` via `loadStateLocked` / `saveStateLocked`. The flag is owned exclusively by `speccraft-state` (enforced by the single-writer grep test).
**Why:** The previous override mechanism was a no-op for the guard — toggling it had no effect on the production-edit-without-sibling-test rule, so users had no working escape hatch. The fix needed to be (a) single-shot so an override can't silently persist, (b) crash-safe so a half-applied override can't leave the repo in a permissive state, and (c) consistent with the existing single-writer invariant for state fields.
**Consequence:**
- Override is now genuinely single-shot and atomic: a single edit is allowed, the next is blocked again.
- Pattern established for "consume-on-use" state fields: lock once, load-locked, mutate, save-locked, return. Future single-shot flags should follow `ConsumeOverride` rather than the read-then-separately-write pattern.
- `commands/spec/override.md` documentation is stale (still says edit `state.json` directly) — known gap, deferred.
- The single-writer allow-list is no longer Rust-specific; any new field added to `Session` must be added to `state_single_writer_test.go`'s grep patterns.

## 2026-05-29 — CI hardening (spec 0008)

**Spec:** specs/0008-ci-hardening/
**Decision:** Split the e2e workflow into two CI jobs with different cost and credential profiles: `e2e-language-only` (cheap, hermetic, no `ANTHROPIC_API_KEY`, runs on every push and PR) executes the language-dispatch fixtures via a new `tests/e2e/run.sh --language-only` flag; `e2e-devcontainer` (expensive, requires API credits, gated to `push` on `main`) continues to run the full `claude -p`-driven lifecycle. Layer in an `ENVIRONMENT_FAILURE:` annotation model so the lifecycle job's failure logs distinguish environmental issues (credit exhaustion, auth, transient upstream) from real assertion failures. Defensive idempotent ownership fix for `~/.claude/session-env` in `.devcontainer/setup.sh`. Record the pre-close gate (first green `e2e-language-only` run on `main`) verbatim in the spec's `changelog.md` as the first concrete enforcement of the §Post-merge verification convention.
**Why:** The single-job e2e pipeline conflated three failure modes — credit exhaustion, authentication, transient API — with real code defects, and the upstream `EACCES` on `~/.claude/session-env` blocked the `/speccraft:spec:review` step entirely. The combined effect: spec 0005's Rust fixtures and spec 0007's Python fixture, both wired into `run.sh`, had never actually run green in CI. Splitting cheap signals from expensive ones gives PR signal on language dispatch without burning API credits; the `ENVIRONMENT_FAILURE:` tag makes log triage cheap; the pre-close gate prevents closing on optimism.
**Consequence:**
- Future expensive e2e steps (anything calling `claude -p`) belong in the lifecycle job; future cheap dispatch-style e2e belongs in `e2e-language-only` via `run_language_fixtures()`. New `<lang>_cycle.sh` fixtures get picked up automatically when added to that helper. Codified in `.speccraft/conventions.md`.
- The `ENVIRONMENT_FAILURE:` annotation is now the canonical pattern for environmental-failure observability. Categories are `credit_exhausted`, `auth`, `transient_api`; ordering is credit → auth → transient. Exit code stays non-zero. Future env failure modes extend this list, not create parallel mechanisms.
- The §Post-merge verification "pre-close gate" convention now has its first concrete enforcement in the codebase. Spec 0007's deferred T10 was retroactively satisfied by the first green `e2e-language-only` run (https://github.com/DCSTOLF/speccraft/actions/runs/26658905606) without editing spec 0007's files — the closed-spec-immutability rule held.
- Integration surfaced a latent mock-stdin bug: `claude -p`-launched subagent CLIs never EOF child stdin, so mocks doing `INPUT="$(cat)"` block forever. The fix — `exec </dev/null` at the top of every mock aux-agent script — is now a convention for any future mock CLI invoked through the aux-delegator path.
- AC #1's exact CI-side root cause was not reproduced locally; the defensive idempotent ownership fix in `.devcontainer/setup.sh` covers both the named-volume-on-first-create race and any base-image ownership oddity. Recorded in 0008's changelog.

## 2026-05-29 — Python e2e fixture (spec 0007)

**Spec:** specs/0007-python-e2e-fixture/
**Decision:** Add an end-to-end fixture for Python (`tests/e2e/python_cycle.sh`) modeled structurally on `rust_inline_cycle.sh` and wire it into `tests/e2e/run.sh` as step `[9/9]`. The fixture exercises the sibling-test resolver (spec 0002) and the separate-tree resolver (spec 0003) through the full PreToolUse hook flow, asserting both rejection messages and acceptance-after-`track-edit`. No Go code changed.
**Why:** Until this spec, Python TDD support had unit coverage in `tools/internal/speccraft/files_test.go` but no end-to-end test that drove `speccraft-guard` against a real Python project layout. The asymmetry surfaced during spec 0005's CI hardening when wiring the Rust e2e step into `run.sh` — Go has e2e via the throwaway Go module in step 1, Rust now has it in step 8, and Python had none. This spec is the smallest possible follow-up that restores parity across all three supported languages.
**Consequence:**
- Every supported language (Go, Python, Rust) now has an end-to-end fixture in `tests/e2e/`. Future language additions are expected to ship with their own `<lang>_cycle.sh` modeled on the same template (codified in `.speccraft/conventions.md`).
- The fixture surfaced a real subtle bug in the spec body: AC #3 originally colocated `bar.py` with the AC #2 sibling pair, but tier-1 of `SiblingTestFiles` is a directory glob and would have hidden the tier-2 behavior. Implementation moved `bar.py` to `src/pkg/` and `orphan.py` to `src/loners/`. Documented in the spec's changelog as a deviation. Reinforces the convention that each AC scenario in a multi-scenario fixture should isolate its directory layout.
- Planning was performed with `/speccraft:spec:plan --skip-review` against a `status: draft` spec at user direction. Cross-model review was bypassed; spec+plan are a paired artifact for PR review. Future reviewers should be aware when reading 0007 that the normal review gate did not run.
- T10 (CI green) is deferred. Two pre-existing infrastructure failures upstream of step `[9/9]` (devcontainer `EACCES` on `~/.claude/session-env` during `/speccraft:spec:review`; `"Credit balance is too low"` during `/speccraft:spec:plan`) prevent the new step from being reached in CI. A follow-up spec (`0008`, CI hardening) will be filed immediately after this closure to fix the upstream issues and retroactively verify T10.

## 2026-05-29 — Rust language support (spec 0005)

**Spec:** specs/0005-rust-language-support/
**Decision:** Add Rust as a first-class supported language with three architectural extensions: (1) a new shared **test-runner invocation primitive** in `tools/internal/speccraft/runner/` (language-neutral interface, per-language adapters); (2) a **dispatch-by-language pattern** in `speccraft-guard` (`dispatchByLanguage` + `rustDispatch`, preserving the existing Go/Python codepath unchanged); (3) a **`reserves-specs` spec-frontmatter field** for forward-referencing follow-up specs by stable ID before they exist on disk.
**Why:** Rust's idiomatic unit tests live inline inside `#[cfg(test)] mod tests` blocks within the same `.rs` file as the production code under test. Sibling-edit detection (the basis for Go and Python support) cannot distinguish "added a test" from "edited prod" within a single file edit. The runner becomes the authoritative oracle for "did the just-added test actually fail?", while a delta-based static classifier handles "did this edit add a test?" — making the system sound even with the inline-tests model. The dispatch-by-language pattern keeps the new wiring isolated from the proven Go/Python paths. The `reserves-specs` field lets AC #5's workspace-detection error name spec `0006` by stable ID before `0006` exists.
**Consequence:**
- `tools/internal/speccraft/runner/` is now shared infrastructure intended for future per-language adapters; the interface has been validated against Rust only. Retroactive adoption by Go/Python is **explicitly a non-goal** and is deferred to a separate spec if ever pursued.
- Adding a new language to `speccraft-guard` is now a localized change: implement a `<lang>Dispatch` function and add a case to `dispatchByLanguage`. The previous open-coded switch is gone.
- The `reserves-specs` field is documented in `.speccraft/conventions.md` as advisory — `/speccraft:spec:new` does not yet implement reservation-aware ID allocation. Tooling support is deferred.
- `.speccraft/state.json` gains `rust_test_baseline` (list) and `rust_gate_fingerprint` (string). The single-writer rule for state.json is extended to cover both, asserted by a grep-based regression test.
- Cargo workspaces are explicitly unsupported in this release; spec id `0006` is reserved for the follow-up.

## 2026-05-22 — Slash-command names fully qualified to `/speccraft:spec:*`

**Spec:** none (maintenance; commits 697c868, 5041bc6, a4ff4db)
**Decision:** Migrate all slash commands from bare names (`/spec:new`) to the fully qualified plugin form (`/speccraft:spec:new`) in README, e2e tests, and every command file's "next steps" hints.
**Why:** Bare names collide with host-repo commands once the plugin is installed via marketplace. Fully qualified names are unambiguous and match Claude Code's plugin command namespacing.
**Consequence:** All user-facing documentation, e2e assertions, and inter-command references must use the qualified form. Any new command added under `commands/spec/` is invoked as `/speccraft:spec:<name>`.

## 2026-05-15 — Python TDD support (specs 0002, 0003)

**Spec:** specs/0002-python-tdd-support/, specs/0003-python-separate-test-roots/
**Decision:** Extend `speccraft-guard`'s red→green detection to Python projects via a `speccraft.toml` config that declares language, test command, and test-file discovery strategy (sibling vs separate tree).
**Why:** First non-Go host-repo adopter needed pytest-driven TDD enforcement without forking the guard binary.
**Consequence:** Guard logic is now language-pluggable through config rather than hard-coded. Future languages add a config recipe, not a new binary. Spec immutability rule still applies: 0002 and 0003 are closed.

## 2026-05-10 — Plugin packaged via `dcstolf-tools` marketplace

**Spec:** none (packaging work, pre-0001 closure; commit 6950511)
**Decision:** Ship speccraft as a single-plugin entry inside the `dcstolf-tools` Claude Code marketplace (`.claude-plugin/plugin.json` + root `marketplace.json`).
**Why:** Distribution channel for Claude Code plugins; lets users install with one command and pins versioning.
**Consequence:** The plugin's install path is now load-bearing — do not introduce a second entrypoint. `marketplace.json` schema must validate against the upstream JSON Schema.

## 2026-05-28 — speccraft adopted

**Spec:** specs/0001-speccraft-v1/
**Decision:** Adopt speccraft for spec-first TDD workflow.
**Why:** Establish disciplined spec-first development from day one.
**Consequence:** All future code changes go through `/speccraft:spec:new`.
