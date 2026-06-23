---
id: "0024"
spec: "0024"
status: planned
strategy: tdd
---

# Plan — 0024 Bounded, reviewable history.md compaction

## Architecture decision (resolves the spec's "Go/bats" ambiguity)

The deterministic tier (AC1–6) is implemented as a PURE BASH command-helper lib —
`commands/history/compact.lib.sh` + `tests/hooks/history-compact.bats` — mirroring
`commands/spec/revise.lib.sh` (the "Sourceable command helpers" convention). This is
the command-mechanic surface for a new slash command, exactly like revise. We do NOT
add a 4th Go binary and do NOT extend the Go state/guard/drift binaries: this is
command-driven file shaping, not session-state or guard logic, and Go gives no
testability advantage over pure bash here while breaking the established convention
that command mechanism shell lives in a colocated `.lib.sh`.

Tier-to-layer assignment (cheapest layer per AC), per the spec's two-tier AC split:

- **Deterministic tier (AC1–6) → `compact.lib.sh` + `history-compact.bats`** (pure
  bash helpers, zero credit). Parsing/window-split/archive-append+dedup/idempotence/
  blast-radius/nudge-predicate. PLUS the deterministic supersession SEED (AC9 support):
  the cheap, deterministic part of the supersession heuristic is pinned at the bats
  layer; only the thematic grouping/prose is left to the model.
- **Model-behavior tier (AC7–12) → `tests/e2e/history_compact.sh`** (SOURCED
  credit-gated fixture, structural predicates only). Confirm-gate, summary schema,
  proposed supersession, provenance reachability, re-compaction merge, nudge surface.
- **Doc/agent contracts → `specs/0024-history-compaction/verify.sh`** (grep oracle):
  command frontmatter; memory-keeper's documented "compact" mode; the context-skill
  invariant that `history-archive/` is NOT in the skill's load list.

## Gate notes — NONE of this needs /speccraft:spec:override

Every artifact in this plan is `.sh` / `.md` / `.bats` / e2e-fixture. Per the
conventions ("`scripts/*.sh` and their sibling shell tests are NOT gated by
speccraft-guard" — generalized: the guard's TDD red→green invariant classifies only
Go/Python/Rust/JS-TS as production code), none of these file types trip the TDD gate.
The RED state for the deterministic tier is therefore simply a failing `bats` run
against a not-yet-created lib (sourcing a nonexistent file fails) — no override, no
red-candidate dance. The e2e fixture is credit-gated: it is verified deterministically
(`bash -n` + its pure sub-helpers unit-checked) at plan time; the full `claude -p`
run is pending user e2e, exactly as spec 0022's P3 (T19/T20) handled it.

## Helper inventory (compact.lib.sh) — names are load-bearing

- `history_parse_entries <history.md>` — emit, one record per line, the byte offset /
  header text of every entry whose header matches the ADR date shape; split body ONLY
  on the next `## YYYY-MM-DD` header OR the `## Compacted` sentinel (CF-6).
- `history_window_split <history.md> <N>` — first N date-keyed entries = window;
  remainder = "older". The `## Compacted …` section and its `###` themes are never
  counted (CF-1). Default N = 10.
- `history_provenance_ids <entry-text>` — list-valued: emit `NNNN` per id for
  `(spec NNNN)` / `(specs A, B)`, emit nothing for a suffix-less entry (CF-1).
- `history_archive_append <entry-text> <archive.md>` — append-only to
  `.speccraft/history-archive/history.md`, full-entry byte-match dedup (CF-3),
  creates the folder/file if absent.
- `history_nudge_predicate <count> <bytes> <N>` — pure: true iff `count > N` AND
  (`count > 15` OR `bytes > 40960`) (CF-4); stdout `nudge`/`quiet`, exit 0.
- `history_compacted_section_themes <history.md>` — extract existing `###` theme
  groups (title + `Specs:`/`Archive:`/`Supersedes:` lines) as durable re-compaction
  input so a later run merges rather than regenerates (CF-2 / AC11).
- `history_supersession_seed <history.md> <N>` — over the OUT-OF-WINDOW entries ONLY,
  emit candidate `older→newer` supersession pairs from DETERMINISTIC signals: explicit
  `supersedes:` markers when present, and `(spec NNNN)` cross-references in an entry
  body that point at another out-of-window entry's id. Degrades gracefully (suffix-less
  entries contribute no id-based seed). Window entries are NEVER emitted as either side
  (preserves the AC2/AC9 out-of-window-only invariant). Emits nothing when no
  deterministic signal exists — the model may still propose collapses, but the seed is
  empty. This pins the deterministic part of the supersession heuristic at the cheap
  bats layer (codex round-1's "deterministic test surface" ask); the model owns only
  the final thematic grouping/summary prose. [AC9-deterministic-support, CF-1]

Constants (N=10, count-bound 15, byte-bound 40960) live as readonly vars in the lib
per OQ3 ("config = constants in the command's helper lib").

## Test-first sequence

### Phase P1 — Deterministic bash lib + bats (AC1–6 + AC9 seed support)

#### Step 1 — Capture green baseline (no test change)
- Run `go test ./...`, the existing `tests/hooks/*.bats`, and
  `tests/e2e/contains_adr_assertion_test.sh` to confirm a clean start.
- This pins that Go and the existing suites are untouched-green before P1 lands —
  the regression anchor for the final verify step (AC1-style "Go untouched").

#### Step 2 — Window split + parse + provenance (RED)
- Add `tests/hooks/history-compact.bats` (sources `commands/history/compact.lib.sh`
  in `setup()`, which does not yet exist → RED). Seed a `$TEST_REPO/.speccraft/`
  fixture history.md whose entries cover the real corpus shapes: a `(spec NNNN)`
  entry, a suffix-less entry, a plural `(specs 0002, 0003)` entry, and a pre-existing
  `## Compacted` section with one `###` theme.
  - `test_window_split_first_N_date_keyed` — `history_window_split <fx> 10` selects
    the first 10 `## YYYY-MM-DD` entries in file order; the rest are "older". [AC1]
  - `test_window_count_ignores_compacted_section` — the `## Compacted` header and its
    `###` themes are NOT counted toward N. [AC1]
  - `test_parse_splits_only_on_date_or_compacted` — an entry body containing an
    interior `## Context` heading is NOT split into a new entry. [AC1, CF-6]
  - `test_provenance_ids_singular_plural_absent` — `(spec 0021)`→`0021`;
    `(specs 0002, 0003)`→`0002`,`0003`; suffix-less→empty. [AC1, CF-1]
- Tests fail: `compact.lib.sh` does not exist, so `setup()`'s `source` fails.

#### Step 3 — Parse/window/provenance helpers (GREEN)
- Implement `commands/history/compact.lib.sh` (`#!/usr/bin/env bash`,
  `set -euo pipefail`, pure functions, errors→stderr, structured stdout, readonly
  constants, no source-time side effects) with `history_parse_entries`,
  `history_window_split`, `history_provenance_ids`. [AC1]
- All Step-2 tests pass.

#### Step 4 — Archive append + dedup + blast radius (RED)
- Extend `history-compact.bats`:
  - `test_archive_append_creates_folder_verbatim` — appending a demoted entry creates
    `.speccraft/history-archive/history.md` with the original `## YYYY-MM-DD …` header
    byte-intact. [AC3]
  - `test_archive_dedup_full_byte_match` — appending an entry already byte-present
    (header + body) is a no-op; a content-differing same-id entry IS appended. [AC3,
    CF-3]
  - `test_archive_append_is_pure_blast_radius` — `history_archive_append` writes ONLY
    under `.speccraft/history-archive/`; a seeded `architecture.md`/`conventions.md`/
    `index.md`/spec file in `$TEST_REPO` are byte-unchanged (`cmp -s`). [AC5]
- Tests fail: `history_archive_append` is undefined.

#### Step 5 — Archive append helper (GREEN)
- Implement `history_archive_append` in `compact.lib.sh`. [AC3, AC5]
- All Step-4 tests pass.

#### Step 6 — Idempotent no-op + nudge predicate (RED)
- Extend `history-compact.bats`:
  - `test_nothing_to_compact_writes_no_files` — when entry-count ≤ N,
    `history_window_split` reports an empty "older" set and the caller's no-op path
    writes nothing (assert archive file absent + history.md byte-unchanged). [AC4]
  - `test_nudge_true_count_gt_15` — `history_nudge_predicate 16 1000 10` → `nudge`.
    [AC6]
  - `test_nudge_true_bytes_over_40k_with_overflow` — `42000` bytes AND `count 11`
    (>N) → `nudge`. [AC6, CF-4]
  - `test_nudge_false_bytes_over_40k_but_nothing_below_window` — `count 10` (==N) with
    `50000` bytes → `quiet` (CF-4: byte arm gated on count>N). [AC6, CF-4]
  - `test_nudge_false_small` — `count 5`, `1000` bytes → `quiet`. [AC6]
- Tests fail: `history_nudge_predicate` (and the no-op contract) undefined.

#### Step 7 — Nudge predicate + no-op contract (GREEN)
- Implement `history_nudge_predicate` and the empty-"older" no-op signal. [AC4, AC6]
- All Step-6 tests pass.

#### Step 8 — Re-compaction merge input helper (RED → GREEN)
- RED: add `test_existing_compacted_themes_preserved` — `history_compacted_section_themes`
  extracts the seeded `### <theme>` with its `Specs:`/`Archive:`/`Supersedes:` lines
  verbatim, so a later run can fold new entries in without regenerating prior groups.
  [AC11-deterministic-support, CF-2]
- GREEN: implement `history_compacted_section_themes`. All P1 bats green.

#### Step 9 — Deterministic supersession seed (RED → GREEN)
- RED: extend `history-compact.bats` (fixture grows two out-of-window entries that
  carry a deterministic link, plus a suffix-less out-of-window entry, plus a window
  entry that also looks linkable as a negative control):
  - `test_supersession_seed_from_explicit_marker` — an explicit `supersedes:` marker
    on the newer of two OUT-OF-WINDOW entries yields exactly one `older→newer` seed
    pair pointing at the referenced id. [AC9-deterministic-support, CF-1]
  - `test_supersession_seed_from_in_body_xref` — an in-body `(spec NNNN)`
    cross-reference between two OUT-OF-WINDOW entries (no explicit marker) yields one
    `older→newer` seed pair from the id link. [AC9-deterministic-support, CF-1]
  - `test_supersession_seed_window_entries_never_emitted` — a deterministic link whose
    either side is INSIDE the window (first N date-keyed entries) emits NO pair; a
    suffix-less out-of-window entry contributes no id-based seed (graceful degrade).
    [AC9-deterministic-support, AC2, CF-1]
  - `test_supersession_seed_empty_without_signal` — a corpus with out-of-window entries
    but no `supersedes:`/no resolvable `(spec NNNN)` xref emits nothing (empty seed;
    model may still propose). [AC9-deterministic-support]
- GREEN: implement `history_supersession_seed <history.md> <N>` in `compact.lib.sh` —
  compute the out-of-window set via the same window-split path, scan ONLY those entries
  for explicit `supersedes:` markers and for `(spec NNNN)` body xrefs resolving to
  another out-of-window entry id (reuse `history_provenance_ids`), emit `older→newer`
  pairs, never emit a window-side id, emit nothing on no signal. All P1 bats green.

#### Step 10 — Refactor (optional)
- Factor the shared date-header regex and the awk frontmatter/section scanner into one
  internal `_history_*` helper if Steps 3/5/8/9 duplicated the matcher (the seed scan
  reuses the window-split and provenance internals). All bats green.

### Phase P2 — Command body + memory-keeper mode + verify.sh oracle (doc contracts)

#### Step 11 — verify.sh grep oracle (RED)
- Add `specs/0024-history-compaction/verify.sh` (mirrors spec 0022's oracle:
  `fails` counter, paired present/absent checks, resolves repo root from
  `BASH_SOURCE`, exit non-zero on any fail). Checks:
  - `commands/history/compact.md` exists and carries `description:` /
    `argument-hint:` / `allowed-tools:` frontmatter. [doc contract]
  - `agents/memory-keeper.md` documents a "compact" mode (present: a
    `# Mode: compact`-style header AND the words propose/summarize/merge; this is the
    expanded responsibility CF non-blocking suggestion #2). [AC8/AC11 contract]
  - PAIRED context-skill invariant: `skills/speccraft-context/SKILL.md` still loads
    `history.md` by name (present check) AND does NOT mention `history-archive`
    (absent check) — so the absence can't be satisfied by deleting the load list.
  - `commands/spec/close.md` references `/speccraft:history:compact` (the nudge
    wiring is present). [AC12 doc-wiring]
- Run it against current `main`: it FAILS (none of those files/sections exist) — RED.

#### Step 12 — Command body + memory-keeper expansion + close nudge wiring (GREEN)
- Add `commands/history/compact.md` (frontmatter triple; sources
  `compact.lib.sh`; thin driver: window_split → propose merged summary + archive list
  + proposed collapses (seeded by `history_supersession_seed`) → CONFIRM → apply;
  delegates prose summarization to memory-keeper; declares blast radius limited to
  history.md + history-archive/).
- Expand `agents/memory-keeper.md` with a documented `# Mode: compact` section:
  inputs (below-window entries + existing `## Compacted` themes + the deterministic
  supersession seed), outputs (merged `###` thematic summary conforming to the schema;
  proposed supersession collapses, out-of-window only; never mutates a verbatim window
  entry), and the explicit note that this expands the agent from append-only to
  propose/summarize/merge under confirmation. The seed is deterministic; only the final
  grouping/summary is model work. [AC7, AC8, AC9, AC11]
- Wire the nudge into `commands/spec/close.md`: after the close steps, source
  `compact.lib.sh`, call `history_nudge_predicate` on the post-close history, and
  echo the non-blocking suggestion to run `/speccraft:history:compact` iff `nudge`.
  Edits nothing. [AC12]
- `verify.sh` now passes — GREEN.

### Phase P3 — Credit-gated e2e fixture (AC7–12) + final verify

#### Step 13 — e2e fixture (RED, deterministically verified)
- Add `tests/e2e/history_compact.sh`: `#!/usr/bin/env bash` + `set -euo pipefail`,
  defines ONE entry function `history_compact` (+ pure sub-helpers), guards
  `command -v run_claude || fail …`, reuses `$TEST_ROOT`, no source-time side effects.
  Reuses the `ADR_HEADER_RE` dated-header shape and the `cmp -s` byte-unchanged idiom
  from `arch_close_memory.sh`. Structural predicates only — never grep model prose.
  Asserts:
  - DECLINE path: history.md AND history-archive/ byte-identical before/after
    (`cmp -s`). [AC7]
  - CONFIRM path: a `## Compacted (older than the active window)` header appears; each
    `###` theme group carries `Specs:` + `Archive:` lines (structural schema check, no
    prose match). [AC8]
  - CONFIRM path: the window's first N `## YYYY-MM-DD` headers are byte-identical to a
    pre-snapshot (AC2 cross-check) and `.speccraft/history-archive/history.md` exists
    with at least one dated header (provenance reachable). [AC2, AC10]
  - RE-COMPACTION: a second confirm preserves the prior `###` theme line(s)
    byte-present (grep the snapshotted theme title is still present). [AC11]
  - SUPERSESSION (seeded, structural): because the fixture corpus now carries a
    deterministic supersession seed (an out-of-window `supersedes:`/`(spec NNNN)` link),
    assert that the confirm-path merged summary contains a `Supersedes:` line — i.e. a
    real proposed collapse, not just the schema shape. Structural only (no prose grep);
    the seed makes this a deterministic e2e expectation rather than best-effort. [AC9]
  - NUDGE: after a `spec:close` whose post-state trips the predicate, the close output
    surfaces the `/speccraft:history:compact` suggestion (structural: the command
    string appears in the close log). [AC12]
- Register in `tests/e2e/run.sh`: `source "$E2E_DIR/history_compact.sh"` near the top
  (after the other fixture sources) and call `history_compact` in the credit-gated
  lifecycle AFTER `[10c/13] arch:close` (new step `[10d/13]`); bump the step labels.
- RED is structural: `bash -n tests/e2e/history_compact.sh` clean, pure sub-helpers
  unit-checked, but the command body it drives must exist (P2) for a real run. Full
  `claude -p` run is credit-gated → pending user e2e, exactly like spec 0022's P3.

#### Step 14 — Final regression / verify gate
- `bats tests/hooks/` — all green (P1 + existing suites).
- `go test ./...` — green and byte-shape-unchanged (this spec added no Go).
- `bash specs/0024-history-compaction/verify.sh` — all checks pass.
- `bash -n` on every new/edited shell: `commands/history/compact.lib.sh`,
  `commands/spec/close.md`'s embedded shell (via the lib it sources),
  `tests/e2e/history_compact.sh`, `specs/0024-history-compaction/verify.sh`.
- `bash tests/e2e/run.sh --help` (or `--language-only` short-circuit) source-integrity:
  sourcing the new fixture defines symbols only, no side effects, harness still parses.
- The credit-gated full lifecycle (the actual `history_compact` claude -p run) is
  noted as pending user e2e — verified deterministically here.

## Delegation

- Step 12 prose summarization contract → delegate to `memory-keeper` (reason: it is
  the existing memory-writing agent; this spec expands its documented mode rather than
  adding a new agent, per OQ1 / "reuse, no new store"). The deterministic supersession
  seed (Step 9) is the contract boundary: the lib hands memory-keeper the seed pairs;
  the agent owns only the thematic grouping/prose.
- Steps 2–9 (bash helpers + bats, incl. the supersession seed) → delegate to the
  general implementer following the `revise.lib.sh` template (reason: pure-shell
  mechanics, the canonical convention reference is in-repo).
- Step 13 e2e fixture authoring → mirror `arch_close_memory.sh` (reason: same
  sourced-fixture, byte-unchanged + dated-ADR-shape idiom).

## Risk

- **Window/parse regex drift vs. real corpus** (suffix-less + plural + interior `##`)
  → mitigation: the Step-2/Step-4 bats fixture seeds ALL four real-corpus shapes; the
  split-only-on-date-or-Compacted rule (CF-6) is its own named test.
- **Nudge false-alarm when nothing is below the window** (CF-4) → mitigation: the
  byte-arm-gated-on-count>N case is an explicit RED test
  (`test_nudge_false_bytes_over_40k_but_nothing_below_window`).
- **Re-compaction silently regenerating prior themes** (CF-2) → mitigation:
  `history_compacted_section_themes` is bats-pinned (Step 8) and the e2e re-compaction
  assertion (Step 13) checks a prior theme title survives a second run.
- **Supersession seed over-matches** → mitigation: out-of-window-only emission plus the
  human-confirm gate makes a bad seed harmless (a wrong pair is just a rejected
  proposal); the Step-9 bats tests pin the seed extraction (window entries never
  emitted, suffix-less yields no id-seed, empty on no signal).
- **Context re-bloat via the archive folder** → mitigation: verify.sh paired
  present/absent check pins that `history-archive` is absent from the skill load list.
- **memory-keeper responsibility expansion hidden** → mitigation: verify.sh asserts
  the documented `# Mode: compact` section exists; the prompt change is reviewable, not
  a silent rewrite.
- **e2e is credit-gated** → mitigation: deterministic verification (`bash -n` + pure
  sub-helper unit checks + run.sh source integrity) at plan time; full run flagged
  pending user e2e, the established spec-0022 P3 posture.
