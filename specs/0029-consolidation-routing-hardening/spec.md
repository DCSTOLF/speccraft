---
id: "0029"
title: "Consolidation routing hardening + zsh portability fix"
status: in-progress
created: 2026-06-26
authors: [claude]
packages: []
related-specs: ["0025", "0024"]
---

# Spec 0029 — Consolidation routing hardening + zsh portability fix

## Why

Spec 0025 shipped inline-at-close consolidation: a closed spec's requirements fold
into per-domain files `specs/domains/<area>.md`, with `.speccraft/architecture.md`,
`conventions.md`, and `history.md` explicitly OUT of consolidation's blast radius
(0025 AC4). In real first-use on another project, an agent did three wrong things,
and the root causes are in speccraft, not the user:

1. **A hard portability bug stopped consolidation from running at all.**
   `commands/spec/consolidate.lib.sh:24` resolves its own dir with
   `"$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"`. The lib is `set -euo pipefail`;
   under zsh (a common interactive/agent shell) `${BASH_SOURCE[0]}` is unset, so
   `set -u` aborts the `source` with `BASH_SOURCE[0]: parameter not set`. Because that
   line then sources `compact.lib.sh`, the WHOLE helper fails to load — every
   consolidate function and the `/speccraft:sync` backfill break. The agent, unable to
   run the helper, skipped consolidation and rationalized it.

2. **The agent treated the `Mode: close` memory updates as a substitute for `Mode:
   consolidate`.** It folded "durable knowledge" into `.speccraft/architecture.md` /
   `conventions.md` and called consolidation satisfied — the exact files 0025 forbids
   consolidation from touching. The close flow has two DISTINCT mechanisms (step 4
   memory-keeper `Mode: close` → `.speccraft/` general decisions; step 9 `Mode:
   consolidate` → `specs/domains/<area>.md` requirements). The command/agent docs do
   not state forcefully enough that these are not interchangeable and that the
   no-`delta:` fallback still routes to `specs/domains/`, never to `.speccraft/`.

3. **Routing can't reason about existing domains.** `consolidate_routing_seed` only
   slugifies the spec title; it never inspects existing `specs/domains/*.md`. So it
   cannot prefer a good existing domain when one fits, nor deliberately propose a NEW
   domain when none fit — it emits a title-slug and leans entirely on the developer to
   correct. New-domain creation works mechanically (open-set: writing `<area>.md`
   creates it) but the *proposal* that would lead there is ungrounded.

The goal is to make consolidation actually run in a host project, route sensibly,
and be impossible to confuse with the `.speccraft/` memory updates.

## What

Three fixes, all within the existing spec-0025 surfaces — no new command, no new Go
binary, no new store.

- **Fix A — zsh-safe lib sourcing (deterministic), with a regression guard across
  ALL libs.** Today only `commands/spec/consolidate.lib.sh:24` uses the
  dir-resolution idiom (it is the only `*.lib.sh` that sources a sibling —
  `compact.lib.sh` for the history parser); the other seven `*.lib.sh` are pure
  function libs that never reference `BASH_SOURCE`. So the proactive sweep is:
  - **(1) Fix the one offender** to resolve its dir without assuming `BASH_SOURCE`
    is set, using the **single canonical idiom `${BASH_SOURCE[0]:-$0}`** (no "or
    equivalent" — one exact form, so the guard below can be an exact grep). It carries
    an in-code comment explaining why it is correct cross-shell (bash always populates
    `BASH_SOURCE`, so the fallback never fires there; zsh sets `$0` to the sourced file
    path, so `$0` is the right value exactly where the fallback fires) — so a future
    maintainer does not "simplify" it back to the broken form.
  - **(2) Regression guard across all libs** — a bats test asserting that **no**
    `commands/**/*.lib.sh` contains a `${BASH_SOURCE[0]}` reference that is not exactly
    `${BASH_SOURCE[0]:-$0}` (i.e. no bare unguarded use). Exact predicate, so it can
    neither false-positive on a valid alternative nor be loosened until it stops
    catching the real bug.
  - **(3) Faithful red-pinning test — REAL zsh, not a bash simulation.** A bash
    "simulated-unset" harness does NOT reproduce the bug: bash auto-repopulates
    `BASH_SOURCE[0]` to the sourced file path *during* `source`, so such a harness
    passes even against the broken code (empirically confirmed in review). The pin
    MUST invoke real zsh: `zsh -uc 'source commands/spec/consolidate.lib.sh'` exits 0
    and the lib's functions are defined. This also exercises the WHOLE file under zsh
    (not just the `BASH_SOURCE` expansion), subsuming the "is the rest zsh-parseable"
    concern. **zsh is a declared test prerequisite** (zsh 5.8.1 is present in the
    devcontainer); the bats test asserts zsh is available rather than silently
    skipping to an unfaithful fallback (a skip that hid the regression would be a
    hollow pin) — see Open question OQ-CI on the CI bats runner.

- **Fix B — routing that knows the existing domains (deterministic seed + grounded
  proposal).** Add a deterministic helper that enumerates the current domain set —
  `consolidate_existing_domains <repo-root>` lists the `<area>` names of every live
  `specs/domains/*.md` (excluding `specs/domains/.archive/`). Feed that list into the
  routing proposal so `memory-keeper Mode: consolidate` can: (i) prefer a good
  existing-domain match when one fits, (ii) propose a clearly-named NEW domain when
  none fit, and (iii) always present the choice for confirm/correct. Explicit
  frontmatter `domains:` stays authoritative; the title-slug seed remains the
  fallback when there are no existing domains. New-domain creation stays open-set (a
  confirmed new `<area>` is created by writing the file).
  **Deterministic vs model split (no conflict with AC3):** `consolidate_routing_seed`
  is BYTE-UNCHANGED from 0025 (it still slugifies the title; AC3 pins this). The
  existing-domain awareness is a SEPARATE new deterministic helper,
  `consolidate_existing_domains`, whose output is **sorted bytewise** for stable
  prompts/tests. The two deterministic helpers (seed + domain list) are the inputs;
  the "prefer-existing-else-propose-new" judgment is the model tier and is always
  confirm-gated. So nothing about routing becomes automatic, and the seed's contract
  does not change.

- **Fix C — un-confusable docs (the conflation hardening).** `commands/spec/close.md`
  step 9 and `agents/memory-keeper.md` `Mode: consolidate` must state explicitly that:
  (1) consolidation routes ONLY to `specs/domains/<area>.md` and NEVER writes
  `.speccraft/architecture.md` / `conventions.md` / `history.md` (restating 0025's
  blast radius at the point of use); (2) the no-`delta:`/no-`domains:` path is NOT a
  reason to skip — it falls back to a confirm-gated model-proposed
  routing + ADD/MODIFY/REMOVE classification into the domain file; and (3) the step-4
  `Mode: close` memory updates are a SEPARATE concern and are NEVER a substitute for
  step-9 consolidation. `Mode: close` similarly gets a one-line "does not perform
  consolidation; see Mode: consolidate" disambiguator.
  **Residual risk (named, not closed):** Fix C is MITIGATION, not enforcement. A grep
  oracle pins the *presence* of the disambiguating wording, but no deterministic guard
  can *prevent* an agent from writing requirements into `.speccraft/` during
  consolidation — a PreToolUse hook cannot distinguish a (wrong) consolidation write
  to `.speccraft/conventions.md` from a legitimate `Mode: close` write to the same
  file. Stronger enforcement (e.g. a phase marker the hook could key on) is a possible
  future hardening, deliberately out of scope here.

The deterministic mechanics (the sourcing fix, `consolidate_existing_domains`) live
in the pure-shell `commands/spec/consolidate.lib.sh` with bats coverage (spec-0015
colocation; no Go, no `/speccraft:spec:override`). The routing/merge proposal and the
prose remain `memory-keeper` model steps. Doc contracts are pinned by the existing
`specs/0025-.../verify.sh`-style grep oracle (a `specs/0029-.../verify.sh`).

## Decisions

- **Fix the libs in place, don't fork the idiom.** `${BASH_SOURCE[0]:-$0}` is the
  minimal cross-shell change; sweep the sibling `*.lib.sh` that copy the idiom so the
  bug can't resurface in `compact.lib.sh`/others.
- **Routing stays heuristic-seed-then-confirm (0025's model).** Fix B GROUNDS the
  proposal with the real domain list; it does NOT make routing automatic. Explicit
  `domains:` remains authoritative; new domains remain open-set and confirm-gated.
- **No behavioral change to the merge/archive/dir-move engine.** This spec only
  touches sourcing robustness, the routing seed's inputs, and documentation — the
  delta/locator/archive/dir-move mechanics from 0025 are unchanged.
- **Reuse `memory-keeper` (no new agent/store)** — only the `Mode: consolidate` and
  `Mode: close` prose is hardened.

## Lifecycle / behavior contract

- **Sourcing.** `source commands/spec/consolidate.lib.sh` succeeds under bash AND
  real zsh with `set -u` (verified via `zsh -uc`, not a bash simulation — bash
  re-populates `BASH_SOURCE` during `source` and so cannot reproduce the failure);
  the lib still locates and sources `commands/history/compact.lib.sh` relative to its
  own path from any CWD.
- **Routing.** When `domains:` is present it is authoritative (unchanged). When
  absent, the proposal is computed from the title-slug seed AND the existing-domain
  list: an existing area that matches is preferred; if none match, a new named area is
  proposed; the developer confirms/corrects before any write. Routing is never silent.
- **Blast radius (restated, unchanged from 0025).** Consolidation writes/moves only
  `specs/domains/<area>.md`, `specs/domains/.archive/<area>.md`,
  `specs/.archive/NNNN-slug/`, and the spec-dir marker files — NEVER
  `.speccraft/architecture.md`, `conventions.md`, or `history.md`.
- **Doc disambiguation.** `close.md` and `memory-keeper.md` make the two close-time
  mechanisms non-interchangeable in wording (see Fix C).

## Acceptance criteria

### Deterministic tier — pinned by `consolidate.lib.sh` + bats

1. **zsh-safe sourcing (real zsh) + exact regression guard.** (a) `zsh -uc 'source
   commands/spec/consolidate.lib.sh'` exits 0 and the lib's functions are defined,
   and the transitive `source` of `commands/history/compact.lib.sh` resolves from any
   CWD; sourcing under bash is unchanged. The test uses REAL zsh (a declared
   prerequisite) — NOT a bash simulated-unset harness, which cannot reproduce the
   failure (bash re-populates `BASH_SOURCE` during `source`) and would pass against the
   broken code; the test asserts zsh is available rather than silently skipping. (b) A
   guard test fails if ANY `commands/**/*.lib.sh` contains a `${BASH_SOURCE[0]}`
   occurrence that is not exactly the canonical `${BASH_SOURCE[0]:-$0}` (exact-form
   grep, no "or equivalent") — covering all eight current libs and any future one.
2. **`consolidate_existing_domains` enumerates live domains, bytewise-sorted.** Given
   a repo with `specs/domains/{billing,auth}.md` and `specs/domains/.archive/auth.md`,
   the helper emits exactly `auth` then `billing` (live areas only; `.archive`
   excluded; **output sorted bytewise** for stable prompts/tests; empty output when
   `specs/domains/` is absent).
3. **Routing seed BYTE-UNCHANGED + frontmatter-authoritative (no conflict with Fix
   B).** `consolidate_routing_seed` is byte-identical to 0025: `domains:` when present
   yields exactly its listed areas; when absent the title-slug seed is unchanged and
   stable across runs (regression pin for 0025 AC2). Existing-domain awareness is the
   SEPARATE `consolidate_existing_domains` helper (AC2), never a change to the seed.
3b. **Routing-proposal corpus pinned at the bats layer.** The "matches an existing
   domain" vs "no match → new domain" precondition is pinned deterministically:
   `consolidate_existing_domains` returns the expected set for the AC6 fixture corpus,
   so a fixture-seeding regression fails on every bats job (credit-free), not only on
   the credit-gated e2e run (per the 0025→0027→0028 fixture-flakiness lineage).

### Doc/model tier — pinned by `specs/0029-.../verify.sh` (grep oracle) + e2e

4. **No-substitute disambiguation present.** `commands/spec/close.md` and
   `agents/memory-keeper.md` each state that consolidation routes ONLY to
   `specs/domains/` and NEVER to `.speccraft/architecture.md`/`conventions.md`/
   `history.md`, and that `Mode: close` memory updates are not a substitute for
   `Mode: consolidate`. (Paired grep: the routing/never-`.speccraft` wording is
   PRESENT in `Mode: consolidate`; an absent-substitute disambiguator is present in
   `Mode: close`.)
5. **No-`delta`/no-`domains` is documented as fallback-not-skip.** `close.md` step 9
   and `memory-keeper Mode: consolidate` state that a missing `delta:`/`domains:`
   triggers a confirm-gated model-proposed routing + ADD/MODIFY/REMOVE into the
   domain file — never a skip and never a write to `.speccraft/`.
6. **Existing-domain-aware routing proposal (model tier, structural e2e).** Concrete
   corpus: a repo seeded with ONE existing domain (`specs/domains/<existing>.md`),
   then two closes — (i) a spec whose title does NOT match the existing domain
   proposes and (on confirm) CREATES a new `specs/domains/<new>.md`; (ii) a spec whose
   title DOES fit routes into the existing `specs/domains/<existing>.md`. Asserted
   structurally only: the routed/created domain file exists and gained lines, AND
   `.speccraft/architecture.md`/`conventions.md`/`history.md` are byte-unchanged
   across both closes (no prose/keyword assertion).

## Out of scope

- Any change to the delta-block grammar, exact-locator matching, archive-B dedup,
  conflict sink, or dir-move sequencing (spec 0025 — unchanged).
- Automatic (non-confirmed) routing or semantic domain classification — routing stays
  seed-then-confirm.
- A `[domains]` config/registry — domains remain open-set (file presence = existence).
- Porting the whole hook/lib suite to be POSIX-sh — only the `BASH_SOURCE` sourcing
  idiom is fixed (the libs remain bash, just safe to `source` from zsh under `set -u`).

## Open questions

- **OQ-CI — does the CI bats job provide zsh?** AC1(a)'s faithful pin needs real zsh.
  zsh 5.8.1 is present in the devcontainer, but the `Hook tests (bats)` CI job's
  environment must be confirmed to have zsh (or have it installed in setup). If it is
  ever absent, AC1(a) must FAIL LOUD (assert-zsh-available), never silently skip to an
  unfaithful pass — the credit-free AC1(b) exact-grep guard still runs everywhere
  regardless. Resolve during `/speccraft:spec:plan` (inspect `.github/workflows/ci.yml`
  + the devcontainer setup).
