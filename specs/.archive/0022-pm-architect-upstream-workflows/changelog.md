---
spec: "0022"
closed: 2026-06-22
---

# Changelog — 0022 Optional PM and Architect workflows upstream of specs

## What shipped vs spec

All eight acceptance criteria are satisfied. PM and Architect ship as first-class
core command namespaces above the spec lifecycle, and specs remain a fully
standalone workflow (AC1) — the upstream lanes are additive and advisory, never
gated behind a flag.

- **AC2 / AC3 / AC6 / AC7 — state lanes + doc-zone (P1).** `tools/internal/speccraft/state.go`
  gains two additive sibling lanes `active_product` / `active_design` with the
  same `,omitempty` clear-to-empty semantics as `active_spec`, which stays
  byte-identical on disk (the `run.sh` close-gate `jq -r '.active_spec // "null"'`
  and `revise.lib.sh::preflight_active_spec_set` are untouched). Lane
  independence is proven at the serialization layer
  (`state_lane_independence_test.go`: clear-one-preserves-other-two, all three
  directions). The single-writer rule is extended to the new lanes
  (`state_single_writer_test.go`). AC3 is a **markdown-scoped regression pin**,
  not a directory prefix: `files_test.go` adds rows asserting `product/`/`design/`
  `*.md` are always-allowed via the existing `ext==".md"` rule while a SOURCE
  file under those trees stays gated — deliberately NO `product/`/`design/` entry
  in the `prefix()` chain (adding one would reopen the broad bypass).
- **AC2 — trees + helpers (P1).** `commands/{pm,arch}/new.lib.sh` provide pure
  `<pm|arch>_next_id` (highest-NNNN+1, never reused, 0001 base) and scaffold
  helpers, covered by `tests/hooks/{pm,arch}-new-preflight.bats`.
- **Authoring + critics (P2).** Four agents — `agents/{pm,arch}-author.md`
  (mirror `spec-author`) and `agents/{pm,arch}-critic.md` (mirror `spec-critic`,
  narrow stage-specific self-check, NOT a second quorum). Eight command bodies
  `commands/{pm,arch}/{new,review,prioritize|decide,close}.md` invoke the lib
  helpers, run the critic before `cross-reviewer` in `*:review`, and set/clear
  their own lane. `pm:prioritize` / `arch:decide` status-transition helpers
  (`*.lib.sh` + bats) gate `draft`-only transitions. Doc frontmatter contracts
  are pinned by `specs/0022-.../verify.sh` (grep oracle; also pins
  cross-reviewer/memory-keeper reused-unchanged + critic-before-review wording).
- **AC5 / AC8 — the `--from` / `informed-by` bridge (P3).**
  `commands/spec/new.lib.sh` (`spec_new_scaffold`, `spec_referent_artifact`,
  `spec_extract_section`) pulls a referent's Why/What into the new spec and writes
  a non-empty `informed-by: [<referent>]` key; plain `spec:new` writes NO key
  (byte-shape parity). The bridge is pull-only and advisory: a dangling, deleted,
  or `closed` referent is non-fatal (note to stderr, spec still generated, the
  advisory link still recorded). Wired into `commands/spec/new.md`; covered by
  `tests/hooks/spec-new-from.bats` (4 tests, RED→GREEN).
- **AC4 / AC6 — arch:close memory routing (P3).** `commands/arch/close.md`
  routes durable decisions through the existing `memory-keeper` (no new store):
  propose a diff to `architecture.md` + a dated ADR for `history.md`, apply only
  on confirm, and clear ONLY `active_design`.

## Test coverage

- `go test ./...` green; `bats tests/hooks` 77/77 green; `specs/0022-.../verify.sh`
  oracle green.
- Two credit-gated e2e fixtures — `tests/e2e/pm_to_spec_bridge.sh` (AC5) and
  `tests/e2e/arch_close_memory.sh` (AC4/AC6) — authored as **sourced functions**
  (not subshells) so they share `run.sh`'s `run_claude` / `LOG_DIR` / lib
  predicates; registered after `[10/13] spec:close` as `[10b/13]`/`[10c/13]`.
  Structural predicates only (never grep model prose). `bash -n` clean and the
  pure helper `section_nonempty` is unit-checked, but the full `claude -p`
  lifecycle is credit-gated and **pending user e2e verification** — consistent
  with prior credit-gated specs (0017/0018).

## Deviations

- **One `/speccraft:spec:override` used (T3, P1.2)**, logged in `tasks.md`
  `## Bypasses`. Adding the `ActiveProduct`/`ActiveDesign` struct fields is a
  brand-new Go symbol whose just-added sibling test (`state_lanes_test.go`,
  Write-created) could not be observed as a runtime RED — `applyEdit` in
  `tools/cmd/speccraft-guard/main.go` models the `Edit` tool's `new_string` but
  NOT the `Write` tool's `content`, so `red_candidates` was empty. This is a
  genuine guard limitation worth a follow-up spec, not a one-off.
- **Two optional refactors skipped (T10, T16)** — `pm`/`arch` `next_id`
  duplication (~15 lines) and the `pm_set_status`/`arch_set_status` shared logic
  are left in separate libs for independent sourcing; not extracted.
- **`roadmap.md` deferred** — `pm:new` scaffolds only `brief.md`; roadmap
  management stays out of scope (a future spec owns it if ever).

## Follow-ups

- Run the full credit-gated `tests/e2e/run.sh` lifecycle to exercise the two new
  bridge/memory fixtures end-to-end.
- A spec to teach `speccraft-guard`'s `applyEdit` to model the `Write` tool's
  `content` (would have removed the T3 override).
