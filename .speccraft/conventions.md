# Conventions

## Go (`tools/`)

- Module path: `github.com/dcstolf/speccraft/tools`. Go 1.22 in `go.mod` (CI runs 1.26.3).
- One binary per subdirectory of `tools/cmd/`. Each has its own `main.go`; no shared `main` package.
- Shared logic lives in `tools/internal/speccraft/` (general) or `tools/internal/delegate/` (aux-agent dispatch). `tools/internal/` packages must not import `tools/cmd/`.
- Errors: wrap with `fmt.Errorf("...: %w", err)`. Sentinel errors live in the package that returns them.
- Logging from `tools/internal/`: return errors, do not print. CLI output (human-readable status, JSON results) belongs in `tools/cmd/*/main.go`. (Advisory — the drift tool can't distinguish real `fmt.Print*` calls from test fixtures that embed the string, so this is checked at code review rather than enforced via regex.)
- Tests: `_test.go` files colocated with the code under test; table-driven for >2 cases; function names start with `Test`. <!-- enforce: regex pattern="^func Test[A-Z]" scope="tools/**/*_test.go" -->

## Bash (`hooks/`, `tests/e2e/`, `scripts/`)

- Every script starts with `#!/usr/bin/env bash` and `set -euo pipefail`.
- Use absolute paths derived from `${BASH_SOURCE[0]}`; never assume CWD.
- All filesystem writes to `.speccraft/` go through the `speccraft-state` binary — hooks do not edit `state.json` directly.
- Hooks emit Claude Code hook-protocol JSON on stdout and exit non-zero on guardrail violations.

## Markdown frontmatter

- **Slash commands (`commands/**.md`):** YAML frontmatter with at minimum `description:`. Fully qualified command names live in the filename path (e.g. `commands/spec/new.md` becomes `/speccraft:spec:new`).
- **Subagents (`agents/*.md`):** YAML frontmatter with `name:`, `description:`, and `tools:`.
- **Skills (`skills/<name>/SKILL.md`):** YAML frontmatter with `name:` and `description:`.
- **Specs (`specs/NNNN-<slug>/spec.md`):** YAML frontmatter with `id`, `title`, `status`, `created`. `plan.md` and `tasks.md` mirror `id`. `changelog.md` is appended by `/speccraft:spec:close`.

### Optional: `reserves-specs`

Introduced by spec 0005. An optional spec-frontmatter field that lets a spec reserve one or more future spec IDs so that error messages and stderr assertions can name a stable id before the follow-up exists.

```yaml
reserves-specs: ["0006"]
```

- **Purpose.** Reserving spec IDs for follow-up work referenced by acceptance criteria in the reserving spec. Spec 0005 is the first concrete use — its workspace-detection error names spec `0006` (Cargo workspace support) by id, so the assertion stays meaningful even before `0006` exists on disk.
- **Shape.** A YAML list of zero-padded four-digit ID strings (e.g. `["0006"]`, `["0006", "0007"]`). Optional; absent on most specs.
- **Allocation rule.** `/speccraft:spec:new` should skip reserved IDs when computing the next available ID. Enforcement in the tool is **advisory** for now — current `/speccraft:spec:new` does not implement reservation-aware allocation. Tooling implementation is deferred to a follow-up spec; this convention entry exists so reviewers and authors can apply the rule manually until enforcement lands.
- **Lifecycle.** The reservation entry is removed from the reserving spec's frontmatter when the reserved spec is filed (its `spec.md` appears under `specs/`). Removal happens during `/speccraft:spec:close` of the reserving spec or as part of the follow-up's first commit, whichever is sooner.
- **Consistency.** A reserved ID has no `spec.md` on disk and must not be flagged by drift or consistency checks as missing.
- **Lower-bound rule.** A spec may not reserve an ID lower than its own.

## Spec lifecycle

- Spec IDs are zero-padded four-digit (`0001`, `0002`, …) and never reused.
- Closed specs (`status: closed`) are immutable. Corrections go in a follow-up spec.

## Rust (`tools/internal/speccraft/`)

Introduced by spec 0005. Conventions for any future Rust-touching code in this repo (not for host-project Rust code — that lives behind the guard).

- **Canonical Rust test ID form.** `<file-stem>::<module-path>::<fn>` for inline tests (e.g. `foo::tests::it_works`) and `<file-stem>::<fn>` for integration tests (e.g. `bar::alpha`). The `<crate-name>::` prefix is stripped by both runner adapters and is never part of the canonical ID. Static discovery (`DiscoverRustTests`) and runner records (parsed by `runner/cargo_parse.go` and `runner/nextest_parse.go`) emit the same form so set-difference is well-defined. New code dealing with Rust test names must use this form end-to-end.
- **Single-writer rule for Rust state fields.** `rust_test_baseline` and `rust_gate_fingerprint` in `.speccraft/state.json` are written **only** by `tools/cmd/speccraft-state/main.go` and the helpers in `tools/internal/speccraft/state.go`. A grep-based regression test (`tools/internal/speccraft/state_single_writer_test.go`) enforces this. Adding a new Rust state field requires extending the allow-list in that test.
- **Rust static recognition split.** Tokenization (string/comment/raw-string awareness) lives in `tools/internal/speccraft/rusttok/`. Domain-specific recognition (canonical IDs, inline `#[cfg(test)] mod` blocks, stem-mapping, crate-walk discovery, baseline lifecycle) lives in `tools/internal/speccraft/rust_*.go`. Keep the boundary: any new tokenizer-level edge case (e.g. new string-literal form) goes in `rusttok/`; any new test-recognition rule goes in `rust_*.go`.
- **Documented limitations.** §L2 (macro `fn` phantom-ID extraction) is a known false-positive that the runner backstop catches. Do not "fix" it by adding ad-hoc macro detection in the tokenizer — that path leads to a half-parser. The proper fix is `syn`/`tree-sitter-rust`, deferred until incidence warrants it.

## Language extensibility in `speccraft-guard`

Introduced by spec 0005.

- **Dispatch by language.** `tools/cmd/speccraft-guard/main.go` routes through `dispatchByLanguage(input, deps)`. Adding a new language is a localized change: implement a `<lang>Dispatch` function (following the `rustDispatch` template), inject any new dependencies through the `deps` struct, and add a case to `dispatchByLanguage`. Do not introduce parallel codepaths inside `processToolUse`.
- **Production wiring goes through `productionDeps()`.** The testability seam in `processToolUse(input, deps)` accepts injected fakes for `exec` and `runnerFor`. The production caller must use `productionDeps()` to wire the real `exec.Command` and `runner.AdapterFor` — constructing `deps{}` inline silently disables the real runner and gate, a bug we hit and fixed during spec 0005 implementation.
- **Runner-primitive adapter contract.** Per-language test runners implement `runner.Runner` (`Run(ctx, Request) (Result, error)`). Argv construction, output parsing, and outcome classification live entirely inside the adapter. No language-specific code in `tools/cmd/speccraft-guard`.

## Templates (`templates/speccraft/`)

- Must remain stack-agnostic. No language- or framework-specific examples in default templates.
- Mirror the schema of the live `.speccraft/` files at the repo root, but with placeholder content.
