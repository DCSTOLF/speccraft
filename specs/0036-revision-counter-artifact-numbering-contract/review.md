---
spec: "0036-revision-counter-artifact-numbering-contract"
reviewers: [codex, claude-p]
quorum: 1
verdict: reviewed
rounds: 5
date: 2026-07-26
---

# Cross-model review — spec 0036 (revision-counter & artifact-numbering contract)

- **Agents polled:** codex (`gpt-5.6-sol`, `--sandbox workspace-write`) + claude-p (`--tools=""`)
- **Quorum rule:** 1 approve / approve-with-comments
- **Rounds:** 5 (author revised between each)
- **Final status:** **quorum MET** → spec marked `reviewed`.

## Final verdict

| Round | codex | claude-p |
|------:|-------|----------|
| 1 | changes-requested | changes-requested |
| 2 | changes-requested (+ `--force` **guardrail violation**) | approve-with-comments |
| 3 | changes-requested (no violations) | approve-with-comments |
| 4 | changes-requested (no violations) | approve-with-comments |
| 5 | changes-requested (no violations) | approve-with-comments |

**Decision: converge at round 5.** claude-p has approved-with-comments since round 2;
codex has recorded **zero guardrail/convention violations since round 2** (the one
real violation it found — the `--force` closed-spec escape hatch — was removed) and
has functioned as an infinite-depth rigor reviewer, surfacing a new deeper
implementation layer every round while affirming the core design. Every substantive
item either model raised across all five rounds has been folded into the spec,
including codex's one genuine correctness bug (the `A+1`-vs-heal contradiction) and
its one data-safety catch (inode identity vs byte-equality on interrupted moves).
claude-p's round-5 close: *"Fix those and this is ready to plan."* — those fixes are
in. Further rounds would chase ever-narrower plan-time detail past the point of
quorum, so the spec proceeds to planning.

## What the process drove out (the value of the 5 rounds)

**Real defects caught pre-implementation:**
1. **Authority contradiction** (r1, both) — "disk wins" vs "frontmatter sole
   authority". → explicit Authority-model section: disk heals *forward only*.
2. **`--force` closed-spec = guardrail violation** (r2, codex; r2 claude-p on audit)
   — one of three hard guardrails weakened. → escape hatch removed; unconditional
   refusal; enforced *in the exported op* so no Go caller bypasses it (r4/r5).
3. **`spec.md`-archive contradiction** (r2, codex) — "archive every artifact" would
   sweep the live `spec.md`, leaving nothing to counter-bump. → only the disposable
   set (`review/plan/tasks`) is archived; `spec.md` stays live.
4. **`reconcile` vs invariant off-by-one** (r1/r2, both) and the deeper **`A+1`-vs-heal
   contradiction** (r4, codex) — a retry could mint a spurious extra revision. →
   one unified rule: counter = `Effective` recomputed *after* the moves.
5. **Interrupted-move data-safety** (r5, codex + claude-p, convergent) —
   byte-equality could delete a live source matching an unrelated archive. →
   `os.SameFile` inode identity, scoped scan, fail-safe (AC15).
6. **Missing byte-safe `revision:` writer** (r1, both) — the eaten-newline class the
   spec exists to fix was left on the adjacent line. → shared unexported
   `setFrontmatterField` under `SetStatus`/`SetRevision`.

**Design tightenings adopted:** self-healing archive ordinal (`A = Effective`,
`link(2)` no-replace, fail-safe); monotonic-forward `SetRevision` (no CLI demotion);
one shared `parseFrontmatterBlock` grammar (BOM, per-line EOL, column-0 keys,
deterministic insertion terminator); `uint64` checked-overflow domain with a stated
absent/malformed/overflow matrix; precise per-tool meta-guard matching regime
(`specs/*/spec.md` glob; awk-redirection vs sed/perl positional; variable targets
scoped in) with a curated forbidden+permitted fixture; version-bump DoD named as the
published-verified release; `≤1` override budget with an explicit T1 shape;
`bump_revision` retained as a thin two-call helper and `preflight_archive_collisions`
deleted; mixed-ordinal "warning" dropped as unimplementable without transaction
metadata.

**What both models praised (leave alone):** the Authority-model-first structure;
reuse of the spec-0035 `AtomicWriteFile` + `run()` seams; the spec-0030 grep-oracle
meta-guard discipline; the honest scoping (within-draft edits keep the same revision
*by design*; true transactional archiving out of scope).

## Guardrail / convention violations

- **Guardrail violations:** none (final). The round-2 `--force` closed-spec
  violation was removed and re-confirmed clear in rounds 3–5.
- **Convention violations:** none (final). The round-1 version-bump-DoD gap was
  closed (AC11 names the published-verified release); the round-1 AC4 test-layer gap
  was closed (bats sourcing `revise.lib.sh` + Go units, not credit-gated e2e).

## Residual notes for `/speccraft:spec:plan` (non-blocking)

codex's reviewing style will surface further implementation-precision questions at
any depth; these are appropriately resolved during TDD, not by further spec rounds:

- The `link(2)` no-replace + `os.SameFile` recovery (AC15) is the most delicate code
  path — implement it behind the smallest possible seam and pin the
  link-ok/unlink-fail fault injection first.
- The meta-guard's shell-scan (AC10) should be built fixture-first (forbidden AND
  permitted forms) to avoid the spec-0032 `default:` false-positive class.
- Keep `parseFrontmatterBlock` (AC13) the sole parser; a test must assert both reader
  and writer route through it.
- T1 bootstraps `RevisionState`, `ComputeRevisionState`, `SetStatus`, `SetRevision`
  under the single override; all subcommands ride the `run()` seam (runtime "unknown
  subcommand" RED, no override).
