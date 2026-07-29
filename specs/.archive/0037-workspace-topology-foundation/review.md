---
spec: "0037"
reviewers: [codex, claude-p]
quorum: 1
verdict: approve
generated: 2026-07-28T00:00:00Z
---

# Cross-model review — 0037 Workspace topology foundation

This spec went through a self-check loop (spec-critic: 8→3→0 issues across
three rounds) before entering cross-model review with codex and claude-p
(quorum 1).

## claude-p

**Verdict:** approve-with-comments (round 1, on the pre-amendment draft)

Concerns:
- Vague stderr contracts across the new `speccraft-state` subcommands.
- Unpinned `get-status` stdout shape (no explicit success/failure I/O contract).
- `design:` and `status:` extraction risked introducing a second frontmatter
  parser alongside spec 0036's `parseFrontmatterBlock`.
- Override budget under-counted: `Config.Kind` field, the manifest parser, and
  the `design:` extractor were each a build-failure-not-RED that should be
  priced into the spec-0018-AC13 override accounting.
- "No specs at workspace root" was asserted in prose but not enforced by any
  acceptance criterion.

Suggestions:
- Pin explicit stdout/stderr contracts for every new subcommand.
- Route all frontmatter reads through the single 0036 parser.
- Consolidate the new exported symbols into one named, closed inventory
  costed against the override budget.
- Either add an enforcement AC for the workspace-root/no-specs convention or
  explicitly defer it to Spec B in "Out of scope."

## codex

**Verdict round 1:** changes-requested

Concerns (round 1):
- **Headline:** AC3 excluded a listed-but-missing member from the returned
  membership set, conflicting with Design 0001's authoritative-manifest /
  blocked-overlay model — this destroyed the topology information Spec B
  needs to render a `blocked` overlay.
- Internal-vs-cmd layering was unclear (which layer prints, which returns
  errors).
- `workspace.yml` grammar was imprecise (indent, comment handling, quoting,
  path rules all underspecified).
- `get-status`'s ref/argument shape was underspecified and diverged from
  Design 0001's literal `<spec.md>` reference without explanation.
- Frontmatter-second-parser risk (same concern as claude-p).
- Override budget mis-attributed relative to the actual new symbol surface.
- AC5 (hot-path-untouched test) referenced things by informal/shell name
  rather than exact symbols, and the scan target was vague.

**Verdict round 2 (re-review after rev 4):** changes-requested — 4 of 7
concerns resolved; 3 residual: the membership-listing subcommand was still
unnamed; the `<value>\n` grammar had gaps (notably inline-comment handling);
the override inventory was still described generically rather than as a
closed, named list.

**Verdict round 3 (re-review after rev 5):** **approve, no concerns.** All
three residual items closed: `speccraft-state list-members` is now explicitly
named; the `workspace.yml` grammar is fully pinned, with Design 0001's own
example line required as a passing fixture; the override-budget section now
names a complete, closed inventory of new exported symbols.

## Synthesis

The review loop worked as intended: the round-1 headline finding — AC3's
membership parser silently dropping a listed-but-missing entry, which
conflicts with Design 0001's authoritative-manifest model — was a genuine
correctness/consistency defect, not a style nit, and both reviewers converged
on layering, grammar precision, and override-budget accounting as secondary
but real gaps. Three amendment rounds (rev 4, rev 5) addressed every item;
codex's round-3 re-review confirms all residual concerns are closed, and
claude-p's original approve-with-comments concerns (stderr contracts,
`get-status` I/O shape, single-parser reuse, override accounting, workspace-
root enforcement) are all resolved by the same amendments. Quorum (1
approve/approve-with-comments) is met, and no agent issued a final reject.

**Key defects caught & fixed (ranked):**
1. **AC3 vs. Design 0001 authoritative-manifest conflict** — the spec now
   preserves every listed member with a `Present bool` (never drops a missing
   one), mapping `present:false` to the future `blocked` overlay in Spec B.
   This is the headline fix: without it, Spec B would have no way to recover
   the topology data it needs.
2. **Internal-vs-cmd layering** — a new "Layering & conventions" section now
   states plainly that `tools/internal/speccraft` returns errors and never
   prints, while the `speccraft-state` cmd layer owns all stdout/stderr/exit
   contracts.
3. **Override-budget accounting** — consolidated into a single named,
   closed inventory (`Config.Kind`, `FindWorkspaceRoot`,
   `ParseWorkspaceMembers` + `Member`, `ReadFrontmatterField`) costing exactly
   one `/speccraft:spec:override` (spec-0036 T1 pattern), with new
   subcommands riding the `run()` seam at zero extra cost.
4. **Grammar / I/O-contract precision** — `workspace.yml`'s accepted subset
   is now fully pinned (indent, inline-comment stripping, bare-vs-quoted
   values, absolute-path rejection), with Design 0001's own example line
   required as a passing fixture; `get-status` and `get-frontmatter` now have
   exact stdout/stderr contracts.

**Residual / carried to Spec B (intentionally out of scope):**
- Mapping `present:false` members to a `blocked` overlay (this spec only
  preserves the presence bit).
- `design:` referent resolution (existence/status/dangling checks).
- Member-path canonicalization (duplicates, overlaps, symlink-escape,
  trailing slashes).
- Enforcement of "a workspace root has no specs of its own" (asserted
  convention only; no AC rejects it here).

**Points of agreement:**
- Neither agent raised a guardrail or convention violation at any round.
- Spec-A/B scope discipline was rated strong throughout — both reviewers
  consistently treated conductor/dispatch/reconcile/canonicalization
  questions as correctly deferred rather than missing.

**Action:** No further spec changes required. Spec 0037 is ready to proceed
to implementation; Spec B should pick up the explicitly deferred items above
(blocked-overlay mapping, referent resolution, path canonicalization,
workspace-root-no-specs enforcement) as its own acceptance criteria.
