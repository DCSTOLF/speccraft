---
spec: "0025"
status: planned
strategy: tdd
---

# Plan — 0025 Spec consolidation into current domain specs on close

This is a pure plugin spec: **no production code in the Go binaries**. The whole
feature is shell + Markdown + bats + a SOURCED credit-gated e2e fixture, exactly
like sibling spec 0024. The deterministic mechanics (spec ACs 1–6) live in a new
pure-shell sourceable helper `commands/spec/consolidate.lib.sh` (the spec-0015
`commands/<group>/<name>.lib.sh` colocation convention), pinned by
`tests/hooks/spec-consolidate.bats`. The model-behavior tier (ACs 7–12) is pinned
by a new SOURCED credit-gated e2e fixture `tests/e2e/spec_consolidate.sh`, plus the
command-body wiring in `commands/spec/close.md` (inline-at-close) and
`commands/sync.md` (backfill loop), plus the `memory-keeper` `# Mode: consolidate`
doc. Doc/contract invariants are pinned by a `verify.sh` grep oracle.

The helper is SOURCED by BOTH `commands/spec/close.md` (inline-at-close) and
`commands/sync.md` (backfill). There is NO new top-level slash command (the
inline-at-close trigger deliberately diverges from 0024's manual command, per
Decisions) and NO new Go binary.

**Override needs: NONE.** `.sh` / `.md` / `.bats` / e2e fixtures are not gated by
`speccraft-guard` (only Go production code under guard-gated packages is), so this
feature never needs `/speccraft:spec:override` — no new Go binary is added, so the
red→green/override path is not in play. This is stated explicitly per Decision N3.

## Test-first sequence

Ordering rationale: helper-mechanics RED→GREEN first (cheap, deterministic,
zero-credit), then the shared-parser coupling pin, then command-body / agent-doc
wiring, then the doc-contract `verify.sh` oracle, then the credit-gated e2e fixture
LAST (it needs API credits and only runs in the lifecycle job).

Tier legend per task: **[det-bats]** = deterministic, pinned by
`tests/hooks/spec-consolidate.bats`; **[doc-verify]** = pinned by
`specs/0025-spec-consolidation-on-close/verify.sh`; **[model-e2e]** = credit-gated,
pinned by `tests/e2e/spec_consolidate.sh` (structural predicates only).

---

### Step 1 — Delta-block parse/validate, locator-required (RED) — AC1 [det-bats]
- Add `tests/hooks/spec-consolidate.bats` (suite header + `setup()` that resolves
  `PLUGIN_DIR`, `LIB="$PLUGIN_DIR/commands/spec/consolidate.lib.sh"`, a `mktemp -d`
  repo, and writes a domain-file fixture; mirrors `history-compact.bats`'s pure
  `source "$LIB"` in each test). Tests for `consolidate_parse_delta`:
  - `@test "consolidate_parse_delta: well-formed block parses ordered ADD/MODIFY/REMOVE"`
  - `@test "consolidate_parse_delta: ADD entry carries no locator"`
  - `@test "consolidate_parse_delta: MODIFY without a locator is a malformed-block rejection"`
  - `@test "consolidate_parse_delta: REMOVE without a locator is a malformed-block rejection"`
  - `@test "consolidate_parse_delta: malformed block rejected with diagnostic, no merge output"`
  - `@test "consolidate_parse_delta: a suffix-less requirement line still parses (empty provenance, not an error)"`
- Tests fail: `consolidate.lib.sh` / `consolidate_parse_delta` does not exist —
  `source "$LIB"` errors (file absent), so every `@test` fails.

### Step 2 — Implement delta parse/validate (GREEN) — AC1 [det-bats]
- Create `commands/spec/consolidate.lib.sh` with the standard header (`set -euo
  pipefail`, "pure functions, no top-level side effects", the spec-0015 colocation
  note, sourced by `close.md` + `sync.md` + the bats suite). Implement
  `consolidate_parse_delta <spec.md>`: extract the `delta:` block, emit ordered
  `ADD|MODIFY|REMOVE\t<locator>\t<text>` records; reject (stderr diagnostic,
  non-zero, no stdout) a MODIFY/REMOVE missing a non-empty locator or any malformed
  shape. Reuse the `_revise_extract_frontmatter` awk idiom for block extraction.
- All step-1 tests pass.

### Step 3 — Exact-normalized locator match (RED) — AC1 [det-bats]
- Extend `tests/hooks/spec-consolidate.bats` with tests for
  `consolidate_locator_match` (the deterministic SEED of the model heuristic — the
  0024 "expose the deterministic seed at the cheap layer" convention):
  - `@test "consolidate_locator_match: unique match ignores trailing (spec NNNN) suffix + surrounding whitespace"`
  - `@test "consolidate_locator_match: zero matches → conflict signal (no apply)"`
  - `@test "consolidate_locator_match: >1 matches → conflict signal (no apply)"`
  - `@test "consolidate_locator_match: match is requirement-text only; the provenance suffix is never the key"`
- Tests fail: `consolidate_locator_match` undefined.

### Step 4 — Implement locator match (GREEN) — AC1 [det-bats]
- Add `consolidate_locator_match <domain.md> <locator>`: normalize each domain
  requirement line (strip trailing `(spec NNNN)` / `(specs N, M)` suffix + trim
  whitespace) and the locator the same way; emit the matched line on exactly one
  match (exit 0), else emit nothing + a `conflict` signal (the no-unique-match →
  conflict-path seed). Reuse the suffix grammar regex shared with the provenance
  helper (Step 10).
- All step-3 tests pass.

### Step 5 — Routing-seed key, deterministic (RED) — AC2 [det-bats]
- Add tests for `consolidate_routing_seed`:
  - `@test "consolidate_routing_seed: stable key from path/title across runs (same input → same key)"`
  - `@test "consolidate_routing_seed: explicit frontmatter domains: are authoritative (returned verbatim)"`
  - `@test "consolidate_routing_seed: absent domains: → a deterministic seeded area key"`
- Tests fail: `consolidate_routing_seed` undefined.

### Step 6 — Implement routing-seed key (GREEN) — AC2 [det-bats]
- Add `consolidate_routing_seed <spec.md>`: if frontmatter `domains: [...]` present,
  echo each area (authoritative); else derive a deterministic, run-stable seed key
  from the slug/title (e.g. lowercased, normalized token). No randomness, no
  timestamps — identical across runs.
- All step-5 tests pass.

### Step 7 — Archive-B writer + full-entry byte-dedup (RED) — AC3 [det-bats]
- Add tests for `consolidate_archiveB_append` (the analogue of 0024's
  `history_archive_append`):
  - `@test "consolidate_archiveB_append: writes self-describing header (area + spec id(s) + op MODIFY|REMOVE) then verbatim superseded text WITH its (spec NNNN) suffix"`
  - `@test "consolidate_archiveB_append: full-entry byte-match dedup — identical re-run is a no-op"`
  - `@test "consolidate_archiveB_append: two distinct events with byte-identical payloads but different headers both persist"`
  - `@test "consolidate_archiveB_append: creates specs/domains/.archive/<area>.md folder/file on first write; append-only"`
  - `@test "consolidate_archiveB_append: nothing to archive writes no file (blast radius)"`
- Tests fail: `consolidate_archiveB_append` undefined.

### Step 8 — Implement archive-B writer (GREEN) — AC3 [det-bats]
- Add `consolidate_archiveB_append <archive.md>` reading entries on stdin: prepend a
  deterministic header line, append verbatim superseded text (suffix intact), dedup
  on a FULL-ENTRY (header+text) byte-match, create the
  `specs/domains/.archive/<area>.md` file with a one-time preamble if absent, never
  rewrite/delete existing content. Mirror `history_archive_append`'s
  encode/dedup/append structure.
- All step-7 tests pass.

### Step 9 — Idempotent domain writes + pinned per-delta write order (RED) — AC6 / CF-1 [det-bats]
- Add tests for `consolidate_apply_delta` (ADD/MODIFY/REMOVE against a domain file,
  driving archive-B):
  - `@test "consolidate_apply_delta: ADD appends with (spec NNNN) suffix; ADD dedups by (locator-normalized text + provenance)"`
  - `@test "consolidate_apply_delta: MODIFY replaces unique line, appends modifying id to suffix list, archives superseded text to archive-B"`
  - `@test "consolidate_apply_delta: REMOVE deletes unique line and archives its text to archive-B"`
  - `@test "consolidate_apply_delta: MODIFY/REMOVE whose locator is already absent/applied is a no-op"`
  - `@test "consolidate_apply_delta: per-delta write order is archive-B FIRST then domain mutation (CF-1)"`
  - `@test "CF-1 crash window (a): re-run after archive-B append but before domain mutation → exactly one archive-B entry + mutation applied once"`
  - `@test "CF-1 crash window (b): re-run after domain mutation but before dir-move → exactly one archive-B entry + no-op mutation (locator already absent)"`
- Tests fail: `consolidate_apply_delta` undefined. The two crash-window tests
  simulate the interruption by invoking the archive step then re-running the whole
  apply, asserting archive-B `grep -c` stays 1 and the domain line is mutated
  exactly once.

### Step 10 — Implement idempotent apply + write order (GREEN) — AC6 / CF-1 / AC5 [det-bats]
- Add `consolidate_apply_delta` and the shared `consolidate_provenance_ids` /
  suffix-grammar helper (the `(spec NNNN)` / `(specs N, M)` regex, reused by Step 4
  and Step 12). Enforce the fixed per-MODIFY/REMOVE order: **archive-B append FIRST →
  destructive domain mutation SECOND** (dir-move is the caller's LAST step, Step 14);
  ADD dedups by (locator-normalized text + provenance); already-applied MODIFY/REMOVE
  is a no-op; on the suffix list, MODIFY appends the modifying id.
- All step-9 tests pass.

### Step 11 — Blast-radius / path allow-list (RED) — AC4 [det-bats]
- Add tests for `consolidate_blast_radius_ok` (path allow-list predicate) and a
  blast-radius integration check:
  - `@test "consolidate_blast_radius_ok: accepts specs/domains/<area>.md, specs/domains/.archive/<area>.md, specs/.archive/NNNN-slug/, the two marker files"`
  - `@test "consolidate_blast_radius_ok: rejects history.md / conventions.md / architecture.md / any other spec dir"`
  - `@test "consolidate run leaves history.md, conventions.md, architecture.md, and a sibling spec dir byte-unchanged"` (snapshot + `cmp -s`, mirroring `history_archive_append: blast radius`)
- Tests fail: `consolidate_blast_radius_ok` undefined.

### Step 12 — Implement blast-radius enforcement (GREEN) — AC4 [det-bats]
- Add `consolidate_blast_radius_ok <path>`: return 0 only for the allow-listed
  targets (`specs/domains/<area>.md`, `specs/domains/.archive/<area>.md`,
  `specs/.archive/NNNN-slug/`, `specs/NNNN-slug/consolidation-conflicts.md`,
  `specs/NNNN-slug/consolidation-skip`), reject everything else. Apply functions
  refuse to write outside the allow-list.
- All step-11 tests pass.

### Step 13 — Domain-file structural invariants (RED) — AC5 [det-bats]
- Add tests for `consolidate_assert_domain_invariants`:
  - `@test "consolidate_assert_domain_invariants: every merged line carries a (spec NNNN) / (specs N, M) suffix; a MODIFY-appended list is well-formed"`
  - `@test "consolidate_assert_domain_invariants: neither specs/.archive/ nor specs/domains/.archive/ appears in the speccraft-context load list"`
- Tests fail: `consolidate_assert_domain_invariants` undefined.

### Step 14 — Implement domain invariants + conflict-file + dir-move (GREEN) — AC5 / AC6 / AC8 / CF-2 [det-bats]
- Add `consolidate_assert_domain_invariants <domain.md>` (suffix-grammar assertion +
  the two-archive load-list absence check). Add the conflict-sink and dir-move
  primitives:
  - `consolidate_record_conflict <spec_dir>` — write/append
    `specs/NNNN-slug/consolidation-conflicts.md` inside the spec dir (CF-2 seed).
  - `consolidate_clear_conflict <spec_dir>` — DELETE
    `consolidation-conflicts.md` once every recorded conflict is resolved; its
    ABSENCE is the zero-conflict precondition the dir-move gates on (CF-2).
  - `consolidate_archive_dir_move <specs_dir> <archive_dir>` — MOVE (never delete)
    `specs/NNNN-slug/ → specs/.archive/NNNN-slug/` ONLY when zero conflicts remain,
    as the LAST step; frontmatter `status` stays `closed` (location, not status).
- Add bats for these (within Step 13's RED block extended in the same suite):
  - `@test "consolidate_record_conflict: writes consolidation-conflicts.md inside the spec dir; domain line byte-unchanged"`
  - `@test "consolidate_clear_conflict: removes consolidation-conflicts.md once resolved; absence is the dir-move precondition"`
  - `@test "consolidate_archive_dir_move: is a MOVE not a delete; fires only with zero conflicts; status stays closed; is the last step"`
  - `@test "consolidate_archive_dir_move: refuses while consolidation-conflicts.md exists"`
- All these tests pass.

### Step 15 — Backfill candidate predicate + shared history-parser coupling (RED) — AC11 / CF-3 [det-bats]
- Add tests for `consolidate_backfill_candidates` and the shared-parser pin:
  - `@test "consolidate_backfill_candidates: candidate iff status==closed AND under specs/ (not .archive) AND no consolidation-skip marker"`
  - `@test "consolidate_backfill_candidates: an already-archived spec is excluded; a consolidation-skip spec is excluded"`
  - `@test "consolidate_backfill_order: replays in history.md oldest-first using spec 0024's history_parse_entries (no second chronology source)"`
  - `@test "consolidate_backfill_order: a history-less / compacted-out spec falls to created:-then-ID, ordered AFTER all history-ordered specs (CF-3)"`
  - `@test "consolidate marker state machine: moved=.archive⇒consolidated, conflicts.md⇒conflict-open, consolidation-skip⇒declined, none⇒pending"`
- The order test SOURCES BOTH libs and calls 0024's `history_parse_entries` /
  `history_provenance_ids` from `commands/history/compact.lib.sh` — pinning the
  cross-spec coupling so a future 0024 signature change breaks here loudly (Risk).
- Tests fail: `consolidate_backfill_candidates` / `consolidate_backfill_order` /
  `consolidate_marker_state` undefined.

### Step 16 — Implement backfill predicate + ordering + marker state (GREEN) — AC11 / CF-3 [det-bats]
- Add `consolidate_backfill_candidates <repo_root>` (location-based, clock-free
  predicate), `consolidate_backfill_order <repo_root>` (REUSE 0024's
  `history_parse_entries` + `history_provenance_ids` for oldest-first chronology,
  with the `created:`-then-ID fallback bucket appended last), and
  `consolidate_marker_state <spec_dir>` (the moved/conflict/skip/pending state
  machine). Source `compact.lib.sh` at the top of the new lib for the shared parser
  (explicit coupling).
- All step-15 tests pass.

### Step 17 — REFACTOR: collapse shared suffix-grammar + encode/dedup helpers (optional)
- Factor the duplicated `(spec NNNN)` suffix regex and the encode/full-byte-dedup
  idiom (introduced across Steps 4, 8, 10, 12) into internal `_consolidate_*`
  helpers; keep the shared-parser reuse of `compact.lib.sh` rather than copying it.
- All tests still pass (`bats tests/hooks/spec-consolidate.bats`).

### Step 18 — close.md inline consolidation wiring (RED, doc-verify) — AC9 [doc-verify]
- Add to `specs/0025-spec-consolidation-on-close/verify.sh` (new grep oracle,
  per spec 0011: every absence check paired with a presence check) checks that
  `commands/spec/close.md`:
  - sources `commands/spec/consolidate.lib.sh`,
  - runs consolidation INLINE AFTER the existing close steps (state/index/history),
    confirm-gated, and references the entry function.
- Fails: close.md has no consolidation wiring yet.

### Step 19 — Wire inline consolidation into close.md (GREEN) — AC9 / AC7 / AC10 [doc-verify + model-e2e]
- Edit `commands/spec/close.md`: after step 8 (the existing history-compaction
  nudge), add a confirm-gated consolidation step that sources
  `consolidate.lib.sh`, computes routing (Step 6) → delta (Steps 2/4) → split,
  presents routing + split + merge + archive plan, writes/moves NOTHING until
  confirm, applies via Steps 10/14 on confirm, and never gates close (declined or
  open-conflict ⇒ nothing moves, close still completes).
- verify.sh step-18 checks pass; the model-tier behavior is exercised by the e2e
  fixture (Step 24).

### Step 20 — sync.md backfill loop wiring (RED, doc-verify) — AC11 [doc-verify]
- Add verify.sh checks that `commands/sync.md` sources
  `commands/spec/consolidate.lib.sh` and adds a confirm-gated per-spec backfill
  propose loop (candidate predicate + presented replay order).
- Fails: sync.md has no backfill loop yet.

### Step 21 — Wire backfill loop into sync.md (GREEN) — AC11 [doc-verify + model-e2e]
- Edit `commands/sync.md`: add a step that sources the lib, enumerates
  `consolidate_backfill_candidates`, presents the `consolidate_backfill_order`
  replay (oldest-first; history-less last), proposes routing→delta→merge→archive
  per spec under confirmation, writes a `consolidation-skip` marker on decline
  (across-run skip-permanence), and dedups within a run.
- verify.sh step-20 checks pass.

### Step 22 — memory-keeper `# Mode: consolidate` doc (RED, doc-verify) — AC7/AC8/AC9/AC11 [doc-verify]
- Add verify.sh checks (mirroring 0024's `# Mode: compact` checks) that
  `agents/memory-keeper.md` documents a `# Mode: consolidate` section mentioning
  propose / merge / route / conflict under confirmation, and the context-skill
  invariants: `skills/speccraft-context/SKILL.md` allows lazy `specs/domains/<area>.md`
  loading AND never lists `specs/.archive/` or `specs/domains/.archive/`. Also
  pin template purity: `templates/speccraft/**` carries no domain-file-shape grammar
  (`(spec NNNN)` suffix) or `.archive` layout leak.
- Fails: those docs/markers absent.

### Step 23 — Add memory-keeper mode + skill load-list + template-purity (GREEN) — AC7/AC8/AC9/AC11/AC5 [doc-verify]
- Edit `agents/memory-keeper.md`: add `# Mode: consolidate` (triggered by
  `/speccraft:spec:close` consolidation step and `/speccraft:sync` backfill) —
  documents the responsibility expansion to propose/route/merge domain requirements
  and surface conflicts under confirmation. Edit
  `skills/speccraft-context/SKILL.md`: add lazy `specs/domains/<area>.md` loading by
  area (NEVER eager; NEVER the two `.archive` trees). Confirm
  `templates/speccraft/**` purity (no edit needed beyond the verify pin if already
  clean).
- All step-22 verify.sh checks pass.

### Step 24 — Credit-gated e2e fixture + run.sh wiring (RED→GREEN, model-e2e) — AC7–AC12 [model-e2e]
- Add `tests/e2e/spec_consolidate.sh` (SOURCED fixture, ONE entry function
  `spec_consolidate`, structural predicates only, guards
  `command -v run_claude`, mirrors `history_compact.sh`). Assert structurally:
  - **AC9 decline:** domain files + `specs/` layout byte-identical after a declined
    consolidation; spec dir NOT moved; close still completed.
  - **AC7 confirm:** routed `specs/domains/<area>.md` line count increased and the
    `(spec NNNN)` / `(specs N, M)` regex matches a merged line; for a MODIFY,
    `specs/domains/.archive/<area>.md` exists and is non-empty.
  - **AC8 conflict:** `specs/NNNN-slug/consolidation-conflicts.md` exists on decline,
    domain line byte-unchanged, spec still closes, dir NOT moved; on resolution the
    file is deleted and the dir moves.
  - **AC10 routing:** seeded target presented; multi-domain split shown.
  - **AC11 backfill:** `/speccraft:sync` proposes per candidate, dir moved on accept,
    `consolidation-skip` written on decline; already-archived skipped.
  - **AC12 provenance:** archive-B header shape present + file non-empty + moved dir
    exists under `specs/.archive/NNNN-slug/`.
- Wire into `tests/e2e/run.sh`: `source "$E2E_DIR/spec_consolidate.sh"` beside the
  other 0022/0024 fixtures, and call `spec_consolidate` as a new `[10e/13]`-style
  step AFTER `[10/13] /speccraft:spec:close` (and after `[10d/13] history_compact`).
  Bump the human-readable step counter labels accordingly.
- RED: until the fixture + wiring land, the lifecycle has no consolidation coverage;
  GREEN is verified deterministically meanwhile via `bash -n tests/e2e/spec_consolidate.sh`
  and `bash -n tests/e2e/run.sh` (a full credit run is deferred to a real lifecycle
  job — see Risk).

---

## Delegation

- Steps 1–17 (pure-shell helper + bats) → keep with **tdd-implementer** (strength
  match: deterministic shell + bats, the 0024/0015 precedent is directly reusable).
- Steps 18–23 (command-body + agent-doc + skill wiring, verify.sh oracle) →
  **tdd-implementer** with `memory-keeper`/doc-contract awareness (doc-layer edits,
  no logic).
- Step 24 (credit-gated e2e fixture + run.sh counter bump) → **tdd-implementer**;
  the actual credit run is deferred to the lifecycle CI job (no local credits).

## Risk

- **0024 ↔ 0025 history-parser coupling.** Backfill reuses 0024's
  `history_parse_entries` / `history_provenance_ids` from
  `commands/history/compact.lib.sh` as its sole chronology source. If 0024's parser
  signature or output shape changes, backfill ordering silently breaks. → Mitigation:
  Step 15's `consolidate_backfill_order` bats test SOURCES both libs and asserts on
  the shared parser's output directly, so a 0024 change fails this suite loudly
  rather than corrupting replay order.
- **Crash-window write-order correctness (CF-1).** A wrong order (mutate-then-archive)
  loses the suffix-bearing preimage irrecoverably on a crash. → Mitigation: Steps
  9/10 pin the fixed order (archive-B FIRST → mutation SECOND → dir-move LAST) with
  both crash-window bats cases (re-run after archive-B; re-run after mutation),
  asserting exactly-one archive-B entry and a single/no-op mutation.
- **Model-tier ACs are credit-gated.** ACs 7–12 can only be exercised by really
  driving close/sync through `claude -p`, so the full e2e run is deferred to a real
  lifecycle job. → Mitigation: meanwhile verify deterministically via
  `bash -n` (syntax) on the fixture + `run.sh`, the `verify.sh` oracle for all
  doc/wiring contracts, and the full `spec-consolidate.bats` suite for every
  deterministic seed of each model heuristic.
- **run.sh step-counter / wiring drift.** Adding the `[10e/13]` step and bumping
  labels can desync counters. → Mitigation: Step 24 keeps the fixture SOURCED (no
  subshell), guarded by `command -v run_claude`, placed immediately after the
  existing 0024 fixture, matching the established 0022/0024 pattern exactly.

## Notes (folded in by close, not by this plan)

- `tests/e2e/run.sh` human-readable step counter gets a new `[10e/13]`-style step
  (memory-keeper at close will reconcile the `/N` labels).
- A new conventions.md entry is likely — "a shared consolidation lib sourced by both
  `close` and `sync`" — and an architecture.md touch-up noting the
  `specs/domains/` + dual-`.archive` layout. These are memory-keeper's job at
  `/speccraft:spec:close`, flagged here only.
- Override needs: NONE (`.sh`/`.md`/`.bats`/e2e are not guard-gated; no Go binary
  added).
