# speccraft

A Claude Code plugin that enforces spec-first TDD via hooks, slash commands, subagents, and cross-model review.

## Stack

- Bash 5+ hooks (`hooks/`) wired through `hooks/hooks.json`
- Go helper binaries under `tools/cmd/speccraft-{state,guard,drift}` sharing `tools/internal/{speccraft,delegate}` (module `github.com/dcstolf/speccraft/tools`; `go.mod` declares Go 1.22, CI runs Go 1.26.3)
- Markdown slash commands (`commands/`) and subagents (`agents/`)
- Markdown skills (`skills/<name>/SKILL.md`)
- Stack-agnostic memory templates (`templates/speccraft/`) copied into a host repo by `/speccraft:init`
- Devcontainer-based end-to-end test (`tests/e2e/run.sh`) driven by GitHub Actions (`.github/workflows/ci.yml`)

## Architecture in one paragraph

speccraft is packaged as a Claude Code plugin (`.claude-plugin/plugin.json`, marketplace `dcstolf-tools`) and ships three execution surfaces: shell hooks that gate Edit/Write tool calls, slash commands the user invokes (`/speccraft:init`, `/speccraft:spec:*`, `/speccraft:sync`), and subagents the orchestrator dispatches (planner, critic, reviewer, delegator, memory-keeper). Hooks and commands call small Go binaries — `speccraft-state` (session/spec state in `.speccraft/state.json`), `speccraft-guard` (TDD red→green invariant), and `speccraft-drift` (regex scan of `enforce:` rules in memory files) — whose shared logic lives in `tools/internal/speccraft`. The repo dogfoods its own plugin: `.speccraft/` here is real project memory for this very codebase, not a fixture.

## Hard rules (see guardrails.md)

- Never commit built binaries from `bin/` or `tools/bin/`.
- Never bypass the TDD red→green invariant without `/speccraft:spec:override` with a recorded reason.
- Plugin templates under `templates/speccraft/` must stay stack-agnostic (no Go-, Python-, or HTTP-specific assumptions).

## Where to look

- Hooks: `hooks/` (entry: `hooks/hooks.json`)
- Slash commands: `commands/` (top-level + `commands/spec/`)
- Subagents: `agents/`
- Skills: `skills/<name>/SKILL.md`
- Go helper binaries: `tools/cmd/speccraft-*/main.go`
- Shared Go logic: `tools/internal/speccraft/`, `tools/internal/delegate/`
- Architect conductor & workspace topology: `commands/arch/orchestrate.{md,lib.sh}`, `tools/internal/speccraft/ledger.go` (`ParseLedger`/`SetLedgerField`/`Reconcile`), `FindWorkspaceRoot`/`ParseWorkspaceMembers`; the workspace ledger is `<workspace>/.speccraft/ledger.md` (a history.md-class memory file, never `state.json`)
- User-facing memory templates: `templates/speccraft/`
- E2E test harness: `tests/e2e/run.sh`
- Specs: `specs/NNNN-<slug>/`

## Active spec

specs/0055-live-smoke-defect-sweep/

## Recent decisions (last 3)

- 2026-11-26 — Two reviewer modes that need no binary on PATH, one round for all four review commands, and the zsh class nine spec reviews could not see (spec 0054, closed; **shipped in 1.19.0**): **Spec:** specs/0054-review-dispatch-modes/ (`related-specs: 0011, 0035, 0050, 0052`; `domains: external-tool-boundaries, spec-lifecycle`). `.speccraft/agents.toml` knew two ways to reach a reviewer, `cli` and `acp`, and **both are shell-outs to a standalone binary** — so the two reviewer sources now present in every Claude Code session could not be named at all. The Codex plugin (`codex@openai-codex`) carries the user's Codex auth, config, job tracking and thread persistence; reaching Codex as `cli` via `codex exec` bypasses all of it and duplicates the model/effort knobs. A same-session **subagent** needs no external binary, no auth and no argv/stdin transport, and with a distinct model is a genuine second opinion — and this spec's own review round 1 is the evidence for why that matters: `claude -p` in a non-interactive permission context **refused every hashing command**, so its spec-0052 reference digests were never computed and its verdict came back `attestation-failed`. Round 1 was inert because the only in-session Anthropic reviewer available was a subprocess with the wrong permissions. Separately, only ONE of four review commands used the registry properly: `arch:review` and `pm:review` said "the same multi-model backend `/speccraft:spec:review` uses, unchanged" with **no runbook at all**, so the model running them improvised dispatch, and `review-code` looped "each enabled agent" through `aux-delegator` with no notion of mode, budget or attestation.

- 2026-09-28 — Bounding the reviewer payload: tiered context, a pre-dispatch byte budget, and ONE byte-producing owner (spec 0052, closed; **shipped in 1.18.0**): `/speccraft:spec:review` pasted all of `.speccraft/` into every reviewer with nothing bounding it; the field report was **622 KB per reviewer**, `claude-p` on `argv` (~70 KB working limit), and reviews that **timed out at 600 s** — the least informative outcome available, and at the quorum layer indistinguishable from an agent with nothing to say. Hand-compaction reached 121 KB and **still did not fit**, which is the whole argument for the boundary being the review command's: `.speccraft/` only grows, every close appends, nothing shrinks it. Fix: an **inline tier** (spec + `guardrails.md` + `index.md`, pasted) and a **reference tier** (`architecture.md` + `conventions.md` as path + byte size + `^##`/`^###` heading index — 121,256 B versus a 3,063 B index), tier membership a FIXED TABLE by identity resolved on the full repo-relative path, and `history.md` an explicit ERROR because expanding the payload inside a spec about bounding it is scope creep. Reads are attested by a **digest the reviewer computes**, expected value withheld from the payload — round 3 correctly killed the earlier read SENTINEL, which proved only that the reviewer read the prompt. The guarantee is deliberately weak and stated: **a digest proves access, not attention**. `review.lib.sh` becomes the SOLE byte-producing owner (so `aux-delegator` had to become a pure dispatcher, or the round would compose twice and the measured bytes would not be the dispatched ones), the payload is materialized ONCE to a 0600 artifact because `x="$(compose)"` strips trailing newlines, and `responses_complete` (gates synthesis + the durable write, for ANY verdict) is split from `approval_quorum_met` (gates `status: reviewed` alone) — which forced the snapshot promote out of the round's START into finalize, since promoting first re-baselined the very anchor an inert round must leave unchanged. Measured **4.03×**: tiered 51,535 B fits under the 65,536 argv limit, a full paste of the same inputs is 207,675 B. Divergence: AC5 as written would have red-ed the tree on day one against two CORRECT `grep -E` intervals (the hazard is **mawk only**, which matches nothing silently); `trap … EXIT` in the temp-dir helper silently DESTROYED the caller's handler, which under bats makes a FAILING test report **nothing at all** — spec 0049's inert-assertion class arriving through the trap table; and round 1 hit a **FALSE QUORUM** where both reviewers wrote the same paths and one model's output came back labelled as the other's, now a convention. Override budget 0 stated, **0 actual**. bats 468 ok.

- 2026-09-26 — Release 1.17.0: the four-spec bump backlog, and why it could not ship until CI was green (spec 0051, closed; **released as v1.17.0**): carries 0047 + 0048 + 0049 + 0050. MINOR — four new subcommands (`tasks-verify`, `build-repair-log`, `design-fingerprint`, `set-status --kind`), build-repair mode, three new `state.json` session keys, no caller contract changed. `bump-before-close` exists to stop a backlog and four deferrals compounded anyway, but **the binding constraint was CI**: `auto-tag` → `release.yml` fires on push to `main`, so a bump pushed during runs #79-#86 would have tagged and published from a tree failing on three jobs — the gate was correctly closed, not ignored. Eight locations: 3 Go consts, 4 oracles whose function names ENCODE the version (so the bump renames them and registers a real red-candidate, which a bare const edit cannot) each with a NEGATIVE check advanced to reject the outgoing version, 2 manifests; `bin/` rebuilt and `.binary-version` re-stamped in the same task, since skipping that makes this repo's hooks chase a release that does not exist yet. **Bump and close are SEPARATE commits** — the close-commit invariant binds changelog+status, not the bump, and splitting let the changelog record what the pipeline ACTUALLY reported rather than an intention. Verified: `v1.17.0` at `bdefb29`, Release run 19 success, 4 tarballs + `checksums.txt`, `verify-release.sh` OK strong-form, CI **#92** green on all seven jobs, and the PUBLISHED binaries extracted and run — all report 1.17.0 and the new subcommands dispatch, which hash-only verification could not prove. Divergence, all predicates: T1/AC3 asserted the ABSENCE of `1.16.0` from files whose stale-version checks must contain it (**third time this session**; the invariant is POLARITY, not absence), and T6 depended on ambient `PATH`, failing at close having passed during implementation — spec 0050's T7/T12/T15 share that latent flaw and passed by the same accident. Both rules now in conventions.md.
