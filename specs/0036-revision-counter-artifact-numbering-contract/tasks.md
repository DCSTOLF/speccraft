---
spec: "0036"
---

# Tasks

- [x] T1 — Bootstrap exported core stubs + first RED tests (RED, single override) [AC1, AC12]
- [x] T2 — ComputeRevisionState + parseFrontmatterBlock + listArchivedOrdinals (GREEN) [AC1, AC13]
- [x] T3 — Classification matrix + error surface + scan edges (RED) [AC1, AC14]
- [x] T4 — Flesh state math + checked overflow (GREEN) [AC1, AC14]
- [x] T5 — Frontmatter grammar edge cases (RED) [AC13, AC7]
- [x] T6 — Full shared parseFrontmatterBlock grammar (GREEN) [AC13, AC7]
- [x] T7 — SetStatus/SetRevision boundary rules (RED) [AC8, AC9, AC14]
- [x] T8 — Implement writer ops + setFrontmatterField (GREEN) [AC8, AC9, AC14, AC13]
- [x] T9 — Byte-safe writer edges + single-parser assertion (RED) [AC6, AC7, AC13]
- [x] T10 — Complete byte-safe writer (GREEN) [AC6, AC7]
- [x] T11 — effective-revision subcommand (RED, run() seam) [AC2]
- [x] T12 — Wire effective-revision (GREEN) [AC2]
- [x] T13 — set-status / set-revision subcommands (RED) [AC8, AC9, AC14]
- [x] T14 — Wire set-status / set-revision (GREEN) [AC8, AC9, AC14]
- [x] T15 — reconcile-revision subcommand (RED) [AC5]
- [x] T16 — Wire reconcile-revision (GREEN) [AC5]
- [x] T17 — archive-artifact subcommand (RED, run() seam) [AC3, AC4]
- [x] T18 — Wire archive-artifact + no-replace move seam (GREEN) [AC3, AC4]
- [x] T19 — Interrupted-move / no-replace fault injection (RED) [AC15, AC4]
- [x] T20 — Inode-identity recovery (GREEN) [AC15]
- [x] T21 — Version-bump oracles 1.10.0→1.11.0 (RED) [AC11]
- [x] T22 — Perform the bump; DoD = published verified v1.11.0 release (GREEN) [AC11]
- [x] T23 — Revise self-heal + call-order regression (RED, bats) [AC4, AC5]
- [x] T24 — Rewrite revise.lib.sh self-healing; drop preflight_archive_collisions (GREEN) [AC4, AC5]
- [x] T25 — Meta-guard fixtures + close.md call-site (RED, bats) [AC10, AC9]
- [x] T26 — Implement meta-guard scanner + close.md set-status (GREEN) [AC10, AC9]
- [x] T27 — Refactor: consolidate grammar/writer helpers + seam comments (optional)

## Bypasses

- 2026-07-27 — override: T1 bootstrap of the brand-new EXPORTED symbols
  (`RevisionState`, `ComputeRevisionState`, `SetStatus`, `SetRevision`) in a single
  edit paired with their first RED tests. Per spec-0018-AC13, their first test
  cannot compile until the symbols exist (build-failure, not a runtime RED), so the
  guard cannot observe a valid RED — the one legitimate override (AC12 budget = 1).
