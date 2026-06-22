---
id: "0022"
title: "Optional PM and Architect workflows upstream of specs"
status: in-progress
created: 2026-06-20
authors: [claude]
packages: []
related-specs: []
---

# Spec 0022 — Optional PM and Architect workflows upstream of specs

## Why

Speccraft today captures *buildable intent* (specs) and enforces TDD, but the
reasoning that precedes a spec — the product case (why/who/what success looks
like) and the technical design (how/feasibility/non-functional constraints) —
lives nowhere durable. We want to add two optional upstream workflows, **PM**
and **Architect**, that sit above specs in a pipeline: PM (problem, users,
evidence, success metrics, scope) → Architect (feasibility, components, data
model, NFRs, trade-offs) → Spec (the existing lifecycle) → implement. The
non-negotiable constraint: specs must remain a fully standalone workflow. A user
who only ever wants specs+TDD must see zero behavioral change and must never be
required to touch PM or Architect.

## What

Add two new command namespaces that parallel `spec:*`:
`/speccraft:pm:{new,review,prioritize,close}` and
`/speccraft:arch:{new,review,decide,close}`.

- PM artifacts live under a new top-level `product/NNNN-slug/` tree (`brief.md`,
  `review.md`, optional `roadmap.md`); Architect artifacts under
  `design/NNNN-slug/` (`design.md`, `review.md`, ADRs).
- Reuse existing machinery wherever possible: the `cross-reviewer` agent backs
  both `pm:review` and `arch:review` unchanged, and `arch:close` does **not**
  invent a new store — it routes through the existing `memory-keeper` to update
  `.speccraft/architecture.md` and append ADRs to `history.md`.
- Add four new agents: authoring agents `pm-author` and `arch-author` (mirroring
  `spec-author` with their own interview scripts), and critic agents `pm-critic`
  and `arch-critic` (mirroring `spec-critic`) that self-check a brief/design
  before `*:review` (see Decisions / OQ3). `cross-reviewer` still backs the
  cross-model `pm:review`/`arch:review` step unchanged.
- Generalize the `speccraft-state` binary to three independent active lanes using
  **additive sibling keys** (see Decisions / OQ2): the existing top-level
  `active_spec` key stays byte-identical, and two new sibling top-level keys
  `active_product` and `active_design` are added with the same `,omitempty`
  clear-to-empty semantics. `speccraft-state` remains the only writer of state.
- Linkage between stages is **pull, not push**: a spec may carry an optional
  `informed-by: [product/0003, design/0007]` frontmatter field, but `spec:new`
  and `spec-author` must never require, assume, or block on it.

## Decisions

- **OQ1 — Packaging: ship in core speccraft (not an opt-in module / flag).** The
  README's "deliberately small scope" story refers to excluding graph / roadmap
  *management*, not to gating workflow surfaces behind flags. PM and Architect
  ship as first-class core command namespaces. The standalone-specs guarantee
  (AC1) is upheld by the lanes being independent and the upstream artifacts being
  advisory — not by hiding the commands behind a flag.
- **OQ2 — State shape: additive sibling keys.** `active_spec` stays byte-identical
  (top-level key, `,omitempty`, cleared on `set active_spec null`/`""`). Two new
  sibling top-level keys, `active_product` and `active_design`, are added with the
  same `,omitempty` clear semantics. *Rejected:* a nested
  `active.{product,design,spec}` record and a single `active` record with a `kind`
  discriminator — both move `active_spec` out of the top level, which silently
  defeats the `tests/e2e/run.sh` close-gate `jq -r '.active_spec // "null"'`,
  hard-breaks the raw-`jq` consumers (`commands/spec/revise.lib.sh`
  `preflight_active_spec_set`, `commands/spec/revise.md`), and forces rewrites of
  the four e2e fixture `state.json` literals — i.e. it breaks AC1. The additive
  shape is also the smallest Go change (two struct fields + two getter/setter
  cases mirroring `active_spec`'s clear semantics). Adding the fields requires
  extending the single-writer regression allow-list
  (`tools/internal/speccraft/state_single_writer_test.go`).
- **OQ3 — Critic agents: add `pm-critic` and `arch-critic`.** Mirror
  `spec-critic`: each is a cheap single-model self-check on a draft brief/design
  (ambiguity, missing sections, untestable success metrics / unstated NFRs +
  trade-offs) run before the cross-model `*:review`. `cross-reviewer` remains the
  multi-model backend for `pm:review`/`arch:review`. Rationale: PM briefs and
  Architect designs have stage-specific failure modes a generic cross-review pass
  catches less reliably than a tailored critic, and the critic is the same
  low-cost pattern already proven on the spec side.

## Lifecycle

PM and Architect artifacts mirror the spec lifecycle; the contract below is what
the plan turns into structural predicates.

- **Status & immutability.** Each `brief.md` / `design.md` carries a `status`
  frontmatter field and moves `draft → reviewed → closed` (PM may pass through
  `prioritized`, Architect through `decided`). A `closed` artifact is immutable
  **by convention** — corrections go in a follow-up artifact. This is the same
  advisory treatment closed specs already get: closed-spec immutability is a
  `guardrails.md` rule checked at review, **not** a hook-enforced gate, and the
  `product/`/`design/` doc-zone stays always-allowed — nothing mechanically
  blocks the edit. (Enforcing it for either artifacts or specs would be net-new
  status-aware-guard machinery, deliberately out of scope here.)
- **Lane clearing on close (per-lane only).** `pm:close` clears `active_product`,
  `arch:close` clears `active_design`, `spec:close` clears `active_spec`
  (unchanged). A close NEVER touches another lane — this is the mechanism behind
  AC6's independence.
- **ID allocation.** `product/` and `design/` ids are allocated independently as
  highest-`NNNN` + 1 within their own tree, zero-padded four digits, never
  reused — abandoned or deleted ids are not reclaimed (same rule as specs).
- **`--from` accepts any extant artifact, including `closed`.** A `closed` brief
  is in fact the ideal `--from` source (it is finalized); `spec:new --from` does
  not require the referenced artifact to be the active one.
- **`informed-by` is advisory and pull-only.** A missing, deleted, or `closed`
  referent NEVER blocks `spec:new`, `spec-author`, or any `spec:*` command; an
  unresolvable reference surfaces a non-fatal note and the command proceeds — the
  standalone-specs guarantee (AC1) extended to dangling links.

## Acceptance criteria

1. With no `product/` or `design/` directories present, every existing `spec:*`
   command and the TDD hooks behave byte-for-byte as they do today (existing e2e
   suite passes unmodified).
2. `pm:new "<title>"` and `arch:new "<title>"` each allocate the next NNNN id in
   their own tree, scaffold the artifact, and set their own state lane
   (`active_product` / `active_design`) — without disturbing `active_spec`.
3. Writing files under `product/` or `design/` is exempt from the TDD PreToolUse
   guard (treated as a doc-zone, like tests/docs/scratch), so authoring a brief
   or design doc is never blocked for lacking a failing test.
4. `arch:close` produces a proposed diff to `architecture.md` and a new ADR entry
   in `history.md` via `memory-keeper`, and applies it only on confirmation.
5. `spec:new --from product/<id>` (or equivalent bridge) pre-populates the spec's
   Why/What from the referenced brief and sets `informed-by`, while plain
   `spec:new "<title>"` with no `--from` still works identically to today.
6. The three state lanes are independent: closing a spec does not clear an active
   PM brief or design, and vice versa.
7. `active_spec` is byte-for-byte unchanged on disk after this change: it remains
   a top-level `,omitempty` string cleared on close, the `run.sh` close-gate
   `jq -r '.active_spec // "null"'` still yields `null` after `spec:close`, and
   `commands/spec/revise.lib.sh::preflight_active_spec_set` still reads it
   correctly. `active_product` / `active_design` are independent sibling keys
   (makes AC6 assertable at the serialization layer).
8. `spec:new --from product/<id>` accepts a `closed` brief, and a missing or
   deleted `informed-by` referent never blocks `spec:new` / `spec-author` or any
   `spec:*` command (non-fatal note, command proceeds).

## Out of scope

- No roadmap visualization or external PM-tool sync (Jira/Linear/etc.).
- No automated enforcement that a spec *must* have an upstream brief or design —
  the pipeline is advisory.
- No changes to the TDD model for code itself.
- No new helper binaries beyond extending `speccraft-state`.
- No hook-enforced closed-artifact immutability (for specs *or* briefs/designs).
  Closed-artifact immutability stays advisory/by-convention, as it already is for
  specs; a status-aware PreToolUse guard is net-new machinery left for a
  follow-up if ever warranted.

## Open questions

_none — OQ1 (packaging), OQ2 (state shape), and OQ3 (critic agents) resolved; see Decisions._
