---
spec: "0034"
closed: 2026-07-25
---

# Changelog — 0034 Stack-agnostic planning & execution

## What shipped vs spec

- **Detection core** — `DetectStack(root, cfg) Stack{Language, TestCommand,
  TestPatterns []string, InlineTests bool}` in
  `tools/internal/speccraft/detect.go`. Probes ONLY exact repo-root manifests;
  precedence encoded as ordered data (`manifestOrder`) `go > rust > python >
  ts > js` (compiled-lang manifests rank above `package.json`, which is often
  mere tooling); rust routes via `cfg.TDD.Rust.Runner` (cargo/nextest), the other
  four via `cfg.TDD.<Lang>.Command`; go surfaces a SUITE command
  (`strings.TrimSpace(cfg.TDD.Go.Command) + " ./..."`); no manifest → explicit
  `unknown`/`""` with `TestPatterns: []`.
- **Two subcommands** — `speccraft-state detect-stack` (versioned
  `{"schema":1,…}` JSON, exit 0 incl. unknown, non-zero only when no `.speccraft/`
  root) and `speccraft-state test-command` (effective command; conventions.md
  marker wins over detection; prints nothing + exits non-zero when empty).
- **Marker grammar** — single-line `<!-- speccraft:test-command = "cmd" -->`,
  regex body `((?:\\.|[^"\\\n])*)` (proper quoted string; unescaped interior quote
  → malformed → detection fallback), first-of-duplicates wins, `\"`/`\\` unescape,
  value emitted as DATA (never shell-evaluated).
- **init seeding** — `commands/init.lib.sh::seed_conventions` PRESERVES an
  existing conventions.md byte-for-byte (idempotent), else copies the neutral
  template and fills the marker + detected-stack note from `detect-stack`
  (unknown → TODO placeholder + empty marker). Wired into `commands/init.md`
  step 5a; conventions.md is no longer verbatim-copied at step 5.
- **Stack-neutral prose + template** — rewrote `agents/tdd-planner.md` (rules 3/7)
  and `commands/spec/{plan,implement,delegate}.md` to reference `speccraft-state
  detect-stack`/`test-command` instead of `go test ./...`/`find … -name
  '*_test.go'`; stripped `templates/speccraft/conventions.md` of Go idioms.
- **Two mechanical meta-guards** — `authoring_prose_test.go` (a concrete
  test-command in the four docs must sit under an `^\s*(#+|>|-|\*)?\s*example\b`
  label OR invoke `speccraft-state test-command`) and `template_purity_test.go`
  (shipped template free of `fmt.Errorf`/`slog`/`^func Test`/`*_test.go`/
  PascalCase idioms) — promoting the guardrails template-purity rule from advisory
  to executable.
- **Version 1.7.1 → 1.8.0** across the three binaries' `const version` +
  `plugin.json` + `marketplace.json` (const tests + a `manifest_version_test.go`
  grep oracle). Published-verified-release inherited as a merge-time obligation
  (spec 0030 AC11 precedent).

## Deviations

- **init wiring landed at the TOP-LEVEL command, not under `spec/`.** Spec §What/§8
  and the plan named `commands/spec/init.md` + `commands/spec/init.lib.sh`, but
  `/speccraft:init` is a top-level command — the real files are
  `commands/init.md` + `commands/init.lib.sh`. Functionally identical; only the
  path differs.
- **`seed_conventions` takes `<root> <template_path>`**, not the plan's bare
  `<root>` — the template path is passed explicitly from `init.md` (which already
  resolves `$PLUGIN_ROOT`), keeping the helper free of plugin-root resolution.
- **Marker parser placed in `package main`, not a new internal/speccraft symbol.**
  The plan proposed `tools/internal/speccraft/marker.go` with an exported
  `EffectiveTestCommand`. Shipped as `tools/cmd/speccraft-state/testcommand.go`
  (`effectiveTestCommand`/`readTestCommandMarker`/`markerRe`, unexported) because
  it is only ever reached via the CLI — this avoided introducing a SECOND
  brand-new internal symbol (and its new-symbol bootstrap cost). Subcommand +
  marker tests are in `tools/cmd/speccraft-state/detect_cmd_test.go` (package
  main).
- **Go `TestCommand` surfaces a SUITE form.** `cfg.TDD.Go.Command` defaults to the
  bare `go test` (the guard's per-test-targeted command); DetectStack appends
  ` ./...` so the authoring layer sees `go test ./...`. Deliberate: a suite
  command for planner/docs, distinct from the guard's bare per-test command.

## Overrides used

- ONE `/speccraft:spec:override` (T1) — the pre-authorized bootstrap of the
  brand-new `DetectStack`/`Stack` symbol (sibling test build-fails pre-edit →
  `OutcomeBuildFailed`, the guardrails §AC13 new-symbol limitation). Every other
  step was strict RED→GREEN. Recorded in tasks.md §Bypasses.

## Environmental findings

1. See override above (AC13 new-symbol bootstrap).
2. **Stale cached guard on PATH.** The hook ran the pre-0031 `1.1.0` cached guard
   (Write blind spot: reads `new_string`, but the Write tool sends `content`), so
   test files CREATED via the Write tool captured zero red-candidates. Workaround:
   register each decisive RED via the Edit tool (add/rename a test), never a fresh
   Write. The SHIPPED 1.8.0 guard is correct; the blind spot was only in the cached
   copy first on PATH during this dogfood session. Same class as spec 0030's
   stale-`speccraft-state`-on-PATH finding.
