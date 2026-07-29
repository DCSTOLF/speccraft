---
spec: "0037"
---

# Tasks

- [x] T1 — Bootstrap: four exported stubs (Kind, FindWorkspaceRoot, ParseWorkspaceMembers+Member, ReadFrontmatterField) + first REDs (single /speccraft:spec:override)
- [x] T2 — RED: AC1 config divergence table (kind parsed / unknown coerces repo / strict errors)
- [x] T3 — GREEN: AC1 kind parse + default + non-strict coerce + strict validate
- [x] T4 — RED: AC2 FindWorkspaceRoot resolution table (self/lone/no-speccraft/nested/malformed-kind)
- [x] T5 — GREEN: AC2 FindWorkspaceRoot (nearest workspace ancestor, else exact FindRoot)
- [x] T6 — RED: AC3 workspace.yml grammar fixture table (incl. Design-0001 line; both polarities)
- [x] T7 — GREEN: AC3 ParseWorkspaceMembers (constrained hand-rolled parser + Present bit)
- [x] T8 — RED: AC3 list-members cmd (presence lines / missing warning / empty / no-yml / malformed) + usage
- [x] T9 — GREEN: AC3 list-members subcommand via run() seam
- [x] T10 — RED: AC4/AC6 ReadFrontmatterField behaviour (absent-key / missing-file / shared-grammar)
- [x] T11 — GREEN: ReadFrontmatterField wraps frontmatterValue (single parseFrontmatterBlock grammar)
- [x] T12 — RED: AC4 get-status cmd (bare-value / live-wins / archive-fallback / not-found / no-status-field)
- [x] T13 — GREEN: AC4 get-status subcommand (dual live/archive resolution) via run() seam
- [x] T14 — RED: AC6 get-frontmatter design cmd (value / absent-empty-line-exit0 / missing-file)
- [x] T15 — GREEN: AC6 get-frontmatter subcommand via run() seam
- [x] T16 — AC5 hot-path source guard (hooks/ + speccraft-guard/ use only FindRoot; green-on-arrival, must stay green)
- [x] T17 — REFACTOR (optional): confirm single frontmatter grammar; leave shipped specStatusIsClosed untouched

## Bypasses

- 2026-07-28 — override: T1 bootstrap — add `SpeccraftConfig.Kind` field (new exported struct field; first test cannot compile until it exists — build-failure ≠ runtime RED, spec-0018-AC13).
- 2026-07-28 — override: T1 bootstrap — create `workspace_topology.go` with stubs `FindWorkspaceRoot`, `Member`/`ParseWorkspaceMembers`, `ReadFrontmatterField` (new exported symbols; same build-failure barrier). NOTE: the plan estimated ONE override; Go requires TWO because `Config.Kind` must live in config.go's struct, a separate build-barrier from the new-symbols file. All four internal symbols are consolidated into these two edits — no further overrides in this spec.
