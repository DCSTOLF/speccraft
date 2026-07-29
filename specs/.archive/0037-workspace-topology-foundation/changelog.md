# Changelog — Spec 0037 Workspace topology foundation

Closed 2026-07-28. Spec A of design 0001 (architect-as-conductor). Implemented
test-first: 44 new test cases, full `go test ./...` green, `go vet` clean.

## What shipped (vs spec)

- **AC1 — `SpeccraftConfig.Kind`** (`repo` | `workspace`), absent ⇒ `repo`.
  Non-strict `ReadConfig` coerces an unknown value to `repo`; `ReadConfigStrict`
  errors on it (raw-value split via a new `readConfigRaw`, so strict validates
  the raw value while non-strict coerces). `config.go`.
- **AC2 — `FindWorkspaceRoot(dir)`**: nearest `kind = workspace` ancestor, else
  exactly `FindRoot(dir)` (value AND error parity). Consumed only by `arch:*` /
  the conductor. `workspace_topology.go`.
- **AC3 — `ParseWorkspaceMembers`** (authoritative, presence-preserving — a
  listed-but-missing path is kept with `Present:false`, never dropped) via a
  constrained hand-rolled grammar (no YAML dep): inline-comment stripping
  (Design 0001's own example line is a fixture), bare/double-quoted values,
  absolute-path rejection. Plus `speccraft-state list-members`
  (`<present|missing>\t<path>`; empty ⇒ exit 0; absent/malformed ⇒ non-zero).
- **AC4 — `speccraft-state get-status <spec-ref>`**: dual `specs/<ref>` →
  `specs/.archive/<ref>` resolution (live wins); `<value>\n` on stdout;
  `not found` / `no status field` non-zero with empty stdout.
- **AC5 — hot-path source guard** (`hotpath_findroot_test.go`, sibling to the
  spec-0012 single-writer test): `hooks/` + `speccraft-guard` reference only
  `FindRoot`, never `FindWorkspaceRoot`/`find-workspace-root`.
- **AC6 — `ReadFrontmatterField`** wrapping the single spec-0036
  `parseFrontmatterBlock` grammar (no 2nd parser) + `speccraft-state
  get-frontmatter <spec.md> <key>` (empty line on absent key, exit 0; never
  errors on the key — only an unreadable file errors).

## Deviations from plan

- **Override budget: 2, not 1.** The plan estimated one `/speccraft:spec:override`;
  Go requires two — `Config.Kind` must live in config.go's struct, a build-barrier
  separate from the new-symbols file. Both are logged in tasks.md `## Bypasses`.
  Every other step rode a runtime RED at zero override (the three subcommands via
  the `run()` "unknown subcommand" seam).
- **Consolidation deferred.** No `specs/domains/` exists yet; folding 0037's
  requirements into a domain file is left to a later `/speccraft:sync`
  (close step 9 is non-gating).
- **No version bump.** This is the foundation slice; the conductor (Spec B)
  completes the feature. Not released.

## Verified against the real repo (beyond unit tests)

`get-status 0036` → `closed`, resolved from `specs/.archive/` — the spec-0025
dual-location fallback proven against an actually-consolidated spec.
`get-frontmatter … design` → `0001-architect-lifecycle-orchestration`.
