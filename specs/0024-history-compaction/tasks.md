---
id: "0024"
spec: "0024"
---

# Tasks

## Phase P1 — Deterministic bash lib + bats (AC1–6 + AC9 seed support)

- [x] T1 — P1.0 Capture green baseline (go test ./..., tests/hooks/*.bats, contains_adr_assertion_test.sh) [regression anchor]
- [x] T2 — P1.1 (RED) Add tests/hooks/history-compact.bats + corpus-shaped fixture; window-split/parse/provenance tests fail (lib absent) [AC1, CF-1, CF-6]
- [x] T3 — P1.2 (GREEN) Implement commands/history/compact.lib.sh: history_parse_entries / history_window_split / history_provenance_ids + readonly N/15/40960 consts [AC1]
- [x] T4 — P1.3 (RED) Add archive append/dedup/blast-radius tests to history-compact.bats [AC3, AC5, CF-3]
- [x] T5 — P1.4 (GREEN) Implement history_archive_append (folder-create, verbatim header, full-byte dedup, pure blast radius) [AC3, AC5]
- [x] T6 — P1.5 (RED) Add idempotent-no-op + nudge-predicate tests (incl. byte-arm-gated-on-count>N false case) [AC4, AC6, CF-4]
- [x] T7 — P1.6 (GREEN) Implement history_nudge_predicate + empty-older no-op signal [AC4, AC6]
- [x] T8 — P1.7 (RED→GREEN) Add + implement history_compacted_section_themes (durable re-compaction input) [AC11-support, CF-2]
- [x] T9 — P1.8 (RED→GREEN) Add + implement history_supersession_seed: out-of-window-only older→newer pairs from explicit supersedes: markers + in-body (spec NNNN) xrefs; window entries never emitted, suffix-less yields no id-seed, empty on no signal [AC9-deterministic-support, CF-1]
- [~] T10 — P1.R (REFACTOR, optional) SKIPPED — the date-header pattern lives in `_HISTORY_DATE_RE` for shell, but the per-function awk programs embed the literal pattern (awk can't read the shell var inside `/.../`); extracting would add a templating layer for ~no gain. Duplication is one regex, acceptable.

## Phase P2 — Command body + memory-keeper compact mode + verify.sh oracle

- [x] T11 — P2.1 (RED) Add specs/0024-history-compaction/verify.sh grep-oracle (command frontmatter, memory-keeper compact mode, paired skill-load-list invariant, close.md nudge ref); fails on main [doc contracts]
- [x] T12 — P2.2 (GREEN) Add commands/history/compact.md (frontmatter + propose→confirm→apply driver, collapses seeded by history_supersession_seed) + expand agents/memory-keeper.md with # Mode: compact (seed in, grouping/prose out) + wire nudge into commands/spec/close.md [AC7, AC8, AC9, AC11, AC12]

## Phase P3 — Credit-gated e2e fixture (AC7–12) + final verify

- [x] T13 — P3.1 (RED, deterministically verified) Add tests/e2e/history_compact.sh (sourced fixture, structural predicates: decline byte-unchanged, Compacted+###/Specs:/Archive: schema, window byte-identical, archive reachable, re-compaction theme survives, seeded confirm-path Supersedes: line, nudge surfaces) + register [10d/13] in run.sh; bash -n clean + sub-helpers unit-checked; full claude -p run credit-gated (pending user e2e) [AC7, AC8, AC9, AC10, AC11, AC12]
- [x] T14 — P3.2 (VERIFY) Final gate: bats green, go test ./... untouched-green, verify.sh green, bash -n on all new shell, run.sh source-integrity; credit-gated lifecycle run noted pending user e2e [AC1, AC4, AC5, AC6]

## Gate note

NONE of these tasks needs /speccraft:spec:override — every artifact is .sh / .md /
.bats / e2e-fixture, all ungated by speccraft-guard. RED for the deterministic tier is
a failing bats run against the not-yet-created lib. The e2e fixture is credit-gated:
verified deterministically (bash -n + pure sub-helpers + run.sh source integrity) at
implement time; full lifecycle run is pending user e2e (spec 0022 P3 posture).
