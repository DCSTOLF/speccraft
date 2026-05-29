---
id: "0005"
title: "Rust language support"
status: closed
created: 2026-05-28
closed: 2026-05-29
authors: [claude]
packages: ["tools/internal/speccraft", "tools/cmd/speccraft-guard", "tools/cmd/speccraft-state", "tests/e2e", ".speccraft"]
related-specs: ["0002", "0003"]
reserves-specs: ["0006"]
---

# Spec 0005 — Rust language support

## Why

speccraft today supports Go (spec 0001) and Python (specs 0002 and 0003). Rust is
the next most-requested target language from users adopting speccraft for
multi-language projects, and adding it keeps the project's positioning as a
language-pluggable TDD guard rather than a Go/Python-only tool.

The architectural precedent for plugging in a new language without forking the
guard binary was established by spec 0002 (Python): configuration-driven
recognition of test files and a single shared `speccraft-guard` binary that
dispatches per-language behavior.

Rust does, however, introduce a *new* precedent that this spec must call out
explicitly: it is the first supported language whose TDD model cannot be served
by sibling-file edit detection alone. Idiomatic Rust places unit tests inline,
inside a `#[cfg(test)] mod tests` block within the same `.rs` file as the
production code under test. From the guard's perspective, a single file edit may
add a test, change prod code, or both, and there is no syntactic shortcut that
reliably distinguishes the three without parsing or compiling.

The decision in this spec is therefore to introduce a generalized **test-runner
invocation primitive** as the source of truth for whether a real, failing test
exists. The primitive lives in `tools/internal/speccraft/runner/` as a
language-neutral interface (one Go interface returning normalized
`{test_name, status, scope}` records, one adapter per language), with Rust
providing the first concrete implementation. The static file-classification
step (existing for Go and Python; extended here for Rust) answers the
"did this edit add a test?" question via a delta-based walk that is
accurate within the tokenizer's coverage (see §What.2 and §Limitations
§L2); the runner is the source of truth for the separate question
"did the just-added test actually fail?", which only execution can
answer.

The interface shape is chosen with the *intent* of supporting later runner
adapters for other languages, but it has been validated only against the
Rust adapter built in this spec. Concrete cross-language validation is
deferred to whichever future spec wires up the next adapter (Go's
package-level `go test ./...` model and Python's name-pattern `pytest -k`
model both differ from Rust's per-test filter contract). A future adapter
may reveal that the interface needs a small extension — an additional
optional field on the input or record — and that is expected and acceptable.
**Retroactive adoption by Go/Python is explicitly a non-goal of this spec**
(see Out of scope), which is why no cross-language guarantee is asserted
here.

## What

Scope of this change:

1. **Config schema.** Extend `speccraft.toml` with a `[tdd.rust]` subsection.
   The subsection form is decided (not open): it gives forward symmetry with
   anticipated `[tdd.go]` and `[tdd.python]` and is the shape downstream
   language additions will inherit.

   The subsection has one user-facing field in this spec:

   ```toml
   [tdd.rust]
   runner = "cargo"   # one of: "cargo" (default) | "nextest"
   ```

   - `runner = "cargo"` is the default and is assumed when `[tdd.rust]` is
     absent or `runner` is unset.
   - `runner = "nextest"` opts into the `cargo nextest run` adapter.
   - Unknown values (e.g. `runner = "auto"`, `runner = "foo"`) are a
     configuration error: the config loader rejects them and the guard
     exits with a clear message naming the file, key, and the allowed
     values.
   - **No PATH-based auto-detection.** The selection is explicit because
     auto-detect would make guard behavior depend on whatever happened to
     be installed in the environment, which defeats reproducibility
     across machines and CI.
   - **Missing-binary behavior.** If `runner = "nextest"` is configured
     but `cargo-nextest` is not on PATH at runtime, the guard exits with
     an error naming the missing binary and the config key that selected
     it. It does not silently fall back to `cargo test`.

2. **Test-file recognition.** Extend `speccraft-guard` to recognize Rust test
   edits in both of Rust's idiomatic locations:
   - **inline tests** — recognized via a **delta-based classification**
     that asks the precise question "did this edit add at least one
     new test function?" rather than "does the file now contain a
     `#[cfg(test)]` token?" This avoids the string-literal and comment
     false positives that a pure regex would produce.

     The detection algorithm:

     1. Read the pre-edit content of the touched file (current disk
        state).
     2. Apply the proposed Edit/Write in memory to produce post-edit
        content.
     3. Walk both contents to extract the set of **canonical test IDs**
        (per §What.3) currently declared. The walk uses a regex that
        matches `#[cfg(test)]` (or `#[cfg(any(test, ...))]`) followed,
        optionally through zero or more additional outer-attribute
        items (e.g. `#[allow(...)]`, `#[doc(...)]`, `pub`) on
        intervening lines, by a `mod <ident> {` item at the same
        leading-whitespace column. Inside each matched block, a
        tokenizer-aware extractor identifies `fn <name>(` declarations
        and emits their canonical IDs.
     4. The tokenizer skips Rust string literals (`"..."`, raw strings
        `r"..."`/`r#"..."#`/`r##"..."##`/..., byte strings `b"..."`),
        character literals (`'x'`), line comments (`//...`), and
        block comments (`/* ... */`). Regex matches and `fn`
        extractions inside these regions are discarded.
     5. The edit is classified as a "test edit" iff
        `post_ids − pre_ids` is non-empty.

     Static detection now correctly answers the "did this edit add a
     test function?" question for code that is not inside `macro_rules!`
     pattern bodies or token-rewriting macros (see §Limitations §L2).
     The runner (criterion #4) remains the authoritative oracle for
     the separate question "did the just-added test actually fail?",
     since only execution can answer that.
   - **integration tests** — files at `tests/<stem>.rs` matched against
     `src/<stem>.rs` (Rust 2015/2018 single-file submodule), or
     `src/<stem>/mod.rs` (Rust 2015 directory submodule), or
     `src/<stem>.rs` paired with `src/<stem>/` (Rust 2018+ path form).
     `lib.rs` is the library crate root, not a submodule pattern, and is
     not part of the stem-mapping.

3. **Test-runner invocation primitive.** Introduce
   `tools/internal/speccraft/runner/` with a language-neutral Go interface
   that takes the touched file and an optional test-name filter and returns
   normalized `{test_name, status, scope}` records plus an outcome enum
   (`build_failed`, `all_passed`, `at_least_one_failed`).

   **Canonical Rust test ID.** `test_name` is the fully-qualified libtest
   path emitted by `cargo test` text output, e.g. `foo::tests::it_works`
   for an inline `#[cfg(test)] mod tests` inside `src/foo.rs`, or
   `<file-stem>::it_works` for an integration test function `it_works` in
   `tests/<file-stem>.rs`. This is the single identifier form used
   end-to-end: static discovery (criterion #8) produces names in this form,
   runner records contain names in this form, and the just-added set
   (criterion #4 accept branch) is computed as a set-difference of strings
   in this form. Two crates may legitimately contain identically-named
   test functions; the qualified prefix disambiguates them.

   The `<crate_name>::` prefix is *not* part of the canonical ID — it is
   stripped by both adapters before matching. `cargo test`'s libtest
   output reports lib-target tests without the crate prefix and
   integration-target tests as `<file-stem>::<fn>`; static discovery
   produces the same forms. Both sides therefore compare strings of the
   form `<module-path>::<fn>` for lib/binary inline tests and
   `<file-stem>::<fn>` for integration tests.

   **`scope` field.** `scope` is the test's containing module path —
   `crate::<module>::<...>` (e.g. `crate::foo::tests`) for inline tests,
   or `tests::<file-stem>` for integration tests. It is metadata used by
   the guard to attribute records to source locations; AC #8's
   set-difference uses `test_name`, not `scope`. The `status` field is
   one of `passed`, `failed`, `ignored`.

   **Targeted single-test invocation only.** Both adapters always
   invoke the runner with a filter that selects *one* fully-qualified
   test name — never a full-suite run. This is what keeps the speccraft
   guard cheap regardless of suite size, and it removes any need for
   speccraft to compete with the developer's own full-suite workflow
   (`cargo test`, `cargo nextest run`, `cargo test --doc`, etc.).
   Suite-runtime differences between `cargo test` and `cargo nextest`
   are therefore not part of the speccraft surface.

   The Rust adapter implements this interface against `cargo test`
   (default) and `cargo nextest run` (opt-in). The exact invocations are:

   - **cargo:**
     `cargo test --no-fail-fast --quiet -- --exact <fqtn>`.
     Parses libtest's text output (lines matching
     `^test (?P<name>.+) \.\.\. (?P<status>ok|FAILED|ignored)$`, where
     `<name>` is already the fully-qualified form).
   - **nextest:**
     `cargo nextest run --no-fail-fast --message-format libtest-json -E 'test(=<fqtn>)'`.
     Parses the structured event stream, normalizing nextest's
     per-binary record into the same fully-qualified
     `<module-path>::<fn>` form.

   The adapter, not `speccraft-guard`, owns the parsing.

   **Doctests are not invoked by either adapter.** Doctests are out of
   scope for this spec; static discovery never identifies them as test
   edits and the runner is never asked to evaluate them. Developers who
   rely on doctests for TDD must run `cargo test --doc` themselves
   outside of speccraft's red-check loop.

4. **Pre-edit gate.** `cargo check --tests` (or `cargo test --no-run`)
   runs on every Edit/Write hook firing covered by the guard. On a cold
   target cache or a large crate this is multi-second; on a warm
   incremental cache it is typically 1-5 seconds.

   The guard short-circuits the gate to a no-op when the **crate
   fingerprint** has not changed since the last successful gate run in
   the current session. The fingerprint is the SHA-256 hash of the
   sorted set of `(relative-path, mtime-nanos, size-bytes)` tuples for
   every tracked file. Tracked files are:
   - all `.rs` files under `src/`, `tests/`, `examples/`, `benches/`
   - `Cargo.toml`, `Cargo.lock`, and (if present) `rust-toolchain.toml`,
     `.cargo/config.toml`

   The `target/` directory is excluded.

   The fingerprint (one SHA-256 string) is persisted in
   `.speccraft/state.json` via `speccraft-state` (see §What.5). The
   cache-hit path performs a directory walk + `stat` per tracked file
   and an in-memory hash compare; this is typically well under 100ms
   for crates with a few thousand files on a warm inode cache. The
   <100ms latency is a design target, not a contract — AC #10 asserts
   the *behavior* (zero `cargo`/`rustc` subprocesses on a hit), not
   wall-clock time.

   **Whole-crate (not per-file) fingerprinting is chosen for
   soundness.** A per-file cache key would let cross-file breakage
   (e.g. file B introduces a compile error between two successive
   edits of file A) escape the gate until a later red-check, because
   A's hash would still match. The whole-crate fingerprint invalidates
   on any tracked-file change, catching such breakage immediately.

5. **Cross-invocation state.** Two new fields are added to the session
   struct in `.speccraft/state.json`, both read and written exclusively
   through `speccraft-state` (matching the existing single-writer rule
   for state.json):
   - `rust_test_baseline` — a list of canonical Rust test IDs (per
     §What.3) that the guard treats as already-known when computing
     the just-added set (criterion #8). The lifecycle (initial
     capture, post-accept update, manual recapture) is defined by
     criterion #12. Used by criterion #4's accept branch.
   - `rust_gate_fingerprint` — a single SHA-256 string: the crate
     fingerprint defined in §What.4. Updated to the new fingerprint
     after every successful cache-miss gate run (cargo exit 0).

   No code path outside `speccraft-state` mutates either field. That
   constraint is load-bearing for the single-writer guardrail on
   `.speccraft/state.json`.

6. **Workspace handling.** Detect Cargo workspaces by reading `Cargo.toml`
   at the repo root and inspecting for a `[workspace]` table. If found, the
   guard errors out with a clear, actionable message referencing the
   pre-allocated follow-up spec **0006 (Cargo workspace support)**.
   Single-crate projects (a `Cargo.toml` with `[package]` and no
   `[workspace]`) are the only supported shape in this spec. Spec id 0006
   is reserved for the workspace follow-up; this spec's `reserves-specs`
   frontmatter records that reservation.

## Limitations

The following are deliberate design choices, surfaced here so reviewers
and users see them without having to read between the lines of the
acceptance criteria.

### L1 — Inline-tests-only files do not unlock prod edits elsewhere

A `.rs` file containing only inline tests — for example a hypothetical
`src/foo_tests.rs` whose entire contents sit inside a
`#[cfg(test)] mod tests` block — is treated as an ordinary source file.
Adding a new failing test inside it unlocks subsequent edits to *that
same file only*. There is no cross-file unlock from `src/foo_tests.rs`
to `src/foo.rs`; the only cross-file unlock mechanism is stem-mapping
via `tests/<stem>.rs` → `src/<stem>.rs` (criterion #3).

**Practical impact: low.** Cargo's default scaffold — `cargo new`,
`cargo new --lib`, and the `#[test]`-generating templates — places
tests *inside* the existing `src/lib.rs` or `src/main.rs` via an inline
`#[cfg(test)] mod tests` block. The standalone `src/foo_tests.rs`
pattern is a custom convention, not an idiomatic one. The vast majority
of cargo crates therefore never hit this limitation: their tests are
either inline alongside production code (covered by criterion #2) or
in `tests/<stem>.rs` integration files (covered by criterion #3).
Projects that have adopted a sibling-file convention can either move
tests inline or relocate them under `tests/`; a more flexible unlock
model is deferred to a follow-up spec.

### L2 — Test detection inside macro bodies is not authoritative

The delta-based detection in §What.2 uses a string/comment-aware
tokenizer to skip non-code regions when extracting `fn <name>(`
declarations. The tokenizer does **not** parse `macro_rules!` pattern
bodies or token-rewriting macros (e.g. `quote!{}`, `paste!{}`,
custom procedural macros). Tokens inside these macro bodies look like
ordinary Rust code to the tokenizer, so a `fn it_works()` declaration
inside a `macro_rules!` pattern would be extracted as if it were a
real test function.

**Failure mode.** Adding a `#[cfg(test)] mod tests { macro_rules! m { ($n:ident) => { fn $n() {} } } }`
block could be classified as a test edit if the tokenizer sees a
literal `fn <ident>` inside the macro pattern. The post-edit ID set
then contains a phantom test ID that does not exist after macro
expansion.

**Practical impact: very low.** Tests rarely sit inside
`macro_rules!` bodies or token-rewriting macros. When the failure
does occur, the runner (criterion #4) is the backstop: the phantom
ID won't appear in `cargo test --exact <fqtn>` output, the runner
will report `all_passed` (or report a build failure if the macro
itself is broken), and the guard rejects the transition with
`"no failing test observed"`. The user is blocked but the system
remains sound.

**Why not fix it.** Eliminating this requires a real Rust parser
(tree-sitter-rust or `syn`) and adds a build dependency. Given the
runner backstop and the rarity of the failure mode, the cost is not
justified at this scope. A follow-up spec may revisit if real-world
incidence is higher than expected.

## Acceptance criteria

1. Given a `speccraft.toml` containing a `[tdd.rust]` subsection with
   `runner = "cargo"`, the existing config-loader unit tests in
   `tools/internal/speccraft` parse the file without error and expose the
   parsed Rust settings on the loaded config struct. A test asserting the
   parsed `runner` value equals `"cargo"` passes.

2. Given a single-crate Rust fixture where `src/foo.rs` exists with only
   production code, an edit that adds a `#[cfg(test)] mod <ident> { ... }`
   block containing at least one new `fn <name>()` declaration to
   `src/foo.rs` is classified by the guard's delta-based detection (per
   §What.2) as a "test edit" and unlocks subsequent prod-code edits to
   the non-test portion of that same file. The guard unit test must
   cover four fixture cases:

   (a) **clean inline test** — a fixture starting with prod-only
   content; the edit adds `#[cfg(test)] mod tests { fn it_works() {} }`.
   Pre-edit ID set is empty; post-edit ID set is
   `{foo::tests::it_works}`; delta is non-empty → classified as a test
   edit.

   (b) **string-literal `#[cfg(test)]`** — the edit changes a string
   literal to contain the text
   `"#[cfg(test)] mod tests { fn it() {} }"`. The tokenizer skips the
   string region; the `fn` extractor finds zero new IDs in either pre-
   or post-edit content; delta is empty → **not classified as a test
   edit**. (This is the round-3 false positive that the delta-based
   classification eliminates.)

   (c) **multi-attribute mod** — the edit adds a `mod` item with
   intervening attributes, e.g.
   `#[cfg(test)] / #[allow(dead_code)] / mod tests { fn it() {} }`.
   The §What.2 regex tolerates the intervening attributes; delta is
   non-empty → classified as a test edit.

   (d) **edit-without-new-test inside an existing test mod** — a
   fixture with a pre-existing `#[cfg(test)] mod tests { fn old() {} }`;
   the edit reorders or comments existing code inside the block but
   adds no new `fn` declaration. Pre-edit and post-edit ID sets are
   equal; delta is empty → **not classified as a test edit**. This
   prevents formatting/refactoring edits inside a test block from
   spuriously unlocking prod-code edits elsewhere.

   The runner (criterion #4) remains the authoritative oracle for
   whether the just-added test actually failed.

3. Given a single-crate Rust fixture where `src/foo.rs` exists, creating a
   new file `tests/foo.rs` is classified by the guard as a "test edit" that
   unlocks prod edits to `src/foo.rs` via stem-mapping. The same applies
   when `src/foo/mod.rs` exists (Rust 2015 directory submodule) or when
   `src/foo.rs` is paired with a `src/foo/` directory (Rust 2018+ path
   form). `src/lib.rs` is *not* a stem-mapping target. Guard tests assert
   each mapping case.

4. The guard's red-check step invokes the configured runner via the
   `tools/internal/speccraft/runner/` adapter, using the targeted
   single-test invocation defined in §What.3, and produces one of three
   outcomes:
   - `build_failed` (runner exited non-zero, output contains compile errors)
     → reject with `"build failed"`. **Compile failure is not a valid red
     state.**
   - `all_passed` (runner exited zero, no failures in normalized records)
     → reject with `"no failing test observed"`. Records with
     `status == "ignored"` count as "ran-and-passed" for unlock purposes
     and do **not** satisfy the accept branch.
   - `at_least_one_failed` (runner exited non-zero, at least one record
     with `status == "failed"` whose `test_name` — in the canonical
     fully-qualified libtest form defined in §What.3 — is in the
     just-added set defined by criterion #8) → accept.

   All three branches are covered by automated tests for both the
   `cargo` and `nextest` adapter modes. **Adapter tests use canned
   fixture output** (libtest text strings for `cargo`, libtest-json
   event streams for `nextest`) fed to the parser; no real
   `cargo-nextest` binary is required by the test suite. The end-to-end
   test (criterion #6) exercises only the `runner = "cargo"` path for
   reproducibility, because `cargo` is always available wherever a
   Rust toolchain is installed. An additional nextest e2e run is
   optional and gated behind a `SPECCRAFT_E2E_NEXTEST=1` environment
   variable; when unset (the default), the nextest e2e path is skipped
   with a notice, not a failure.

5. Given a `Cargo.toml` at the repo root containing a `[workspace]` table,
   the guard exits with a non-zero status and prints a message that (a)
   names the unsupported condition as a Cargo workspace and (b) references
   the reserved follow-up spec id **0006 (Cargo workspace support)** by id
   *and* title. A test asserts the exit status, that stderr contains the
   literal string `"0006"`, and that stderr contains the literal string
   `"workspace support"`.

6. An end-to-end test under `tests/e2e/` runs a Rust fixture project
   through a full red→green→refactor cycle covering both the inline-test
   path (criterion #2) and the integration-test path (criterion #3), using
   the real `speccraft-guard` binary and a real runner invocation. The
   e2e test passes in CI.

7. A new "Rust" section is added to the project README documenting the
   inline-vs-integration test convention, the `[tdd.rust]` config shape,
   and the runner-invocation guard step. `templates/speccraft/**` is
   **not** modified — the template tree remains stack-agnostic per
   guardrail. The PR description states that the README path was taken.

8. The "just-added test" set used in criterion #4 is defined as the set
   of canonical Rust test IDs (per §What.3 — fully-qualified libtest
   `<module-path>::<fn>` form) discovered after the edit by walking
   `src/**/*.rs` for inline tests (functions inside `#[cfg(test)]` scopes
   identified by the §What.2 regex) and `tests/*.rs` for integration
   tests, minus the contents of `rust_test_baseline` as maintained per
   criterion #12. Both the baseline and the post-edit set use the same canonical
   ID form so set-difference is well-defined. The baseline is stored in
   `.speccraft/state.json` under a `rust_test_baseline` field (a list of
   canonical test ID strings) and is read and written **exclusively**
   through `speccraft-state` (matching the existing single-writer
   convention for state.json). A guard test asserts that no code path
   outside `speccraft-state` mutates the baseline.

9. The devcontainer image and the CI e2e job provide a working Rust
   toolchain (`rustc`, `cargo`). The e2e harness in `tests/e2e/run.sh`
   fails fast with a clear error message (`"cargo not found on PATH"`) if
   `cargo` is absent. The devcontainer setup script (`scripts/` or
   `.devcontainer/setup.sh`) installs `rustup` and the stable toolchain.

10. The pre-edit gate (§What.4) maintains a **crate fingerprint** equal
    to the SHA-256 of the sorted set of
    `(relative-path, mtime-nanos, size-bytes)` tuples covering every
    tracked file:
    - all `.rs` files under `src/`, `tests/`, `examples/`, `benches/`;
    - `Cargo.toml`, `Cargo.lock`, and (if present)
      `rust-toolchain.toml`, `.cargo/config.toml`.

    `target/` is excluded. The fingerprint is stored under
    `rust_gate_fingerprint` in `.speccraft/state.json` and is read and
    written **exclusively** through `speccraft-state` (per §What.5).

    Two behavioral assertions cover correctness, both implemented by
    prepending a recording shim for `cargo` (and `rustc`) to `PATH` in
    the test fixture, where the shim writes its argv to a log file and
    exits 0:

    - **Cache hit:** when the freshly-computed crate fingerprint
      matches `rust_gate_fingerprint`, the guard invokes zero `cargo`
      and zero `rustc` subprocesses. Asserted by verifying the shim's
      invocation log is empty after the gate runs.

    - **Cache invalidation:** when any tracked file's `(mtime, size)`
      changes — including a file *other than* the touched file — the
      freshly-computed fingerprint differs from `rust_gate_fingerprint`,
      and the configured pre-edit-gate command (`cargo check --tests`
      by default) is invoked. Asserted by verifying the shim's log
      contains the expected argv. The test must cover three
      invalidation cases: (a) the touched file itself changing,
      (b) an unrelated `.rs` file in the crate changing,
      (c) `Cargo.toml` changing.

    A `target/` directory whose contents change between gate runs must
    **not** trigger a cache miss; a dedicated test asserts this.

    Cache-miss latency is bounded by `cargo check --tests`; this spec
    imposes no additional bound, but the e2e test (criterion #6) must
    complete within the existing CI job timeout.

11. `.speccraft/conventions.md` is extended with a documented convention
    for the `reserves-specs` frontmatter field introduced by this spec
    (this spec is the first concrete use, reserving `0006` for the
    Cargo workspace follow-up per criterion #5). The new conventions
    text — added under the existing Spec frontmatter subsection —
    covers, at minimum:

    - **Purpose.** Reserving spec IDs for follow-up work referenced by
      acceptance criteria in the reserving spec, so error messages and
      stderr assertions can name a stable id before the follow-up
      exists.
    - **Shape.** A YAML list of zero-padded four-digit ID strings, e.g.
      `reserves-specs: ["0006"]`. Optional; absent on most specs.
    - **Allocation rule.** `/speccraft:spec:new` should skip reserved
      IDs when computing the next available ID. Enforcement in the
      tool is **advisory** for now — current `/speccraft:spec:new`
      does not implement reservation-aware allocation. Tooling
      implementation is deferred to a follow-up spec; the conventions
      entry documents the rule so reviewers and authors can apply it
      manually until enforcement lands.
    - **Lifecycle.** The reservation entry is removed from the
      reserving spec's frontmatter when the reserved spec is filed
      (its `spec.md` appears under `specs/`). Removal happens during
      `/speccraft:spec:close` of the reserving spec or as part of the
      follow-up's first commit, whichever is sooner.
    - **Consistency.** A reserved ID has no `spec.md` on disk and is
      not flagged by drift or consistency checks as missing.
    - **Lower-bound rule.** A spec may not reserve an ID lower than
      its own.

    Verification: a grep of `.speccraft/conventions.md` for the literal
    string `reserves-specs` returns at least one match in the new
    documentation block.

12. **Baseline lifecycle.** The `rust_test_baseline` field defined in
    §What.5 is maintained by three explicit mutation rules; no other
    code path writes it.

    - **Initial capture.** On a guard invocation against a Rust crate
      (per §What.1 config) where `rust_test_baseline` is empty or
      unset, the guard walks the crate per §What.2/§What.3 to discover
      all canonical Rust test IDs currently present, writes them as
      the baseline via `speccraft-state`, logs
      `"rust_test_baseline captured: N tests"` to stderr, and returns
      success **without evaluating a red-check transition**. There is
      no transition to evaluate on the first invocation — the baseline
      is the *prior* green state, and on first run there is none. The
      next invocation runs normally.

    - **Post-accept update.** When AC #4's `at_least_one_failed`
      accept branch fires, the canonical IDs of the failing tests
      that satisfied the accept (i.e. the intersection of the
      just-added set with `{r | r.status == "failed"}` in the runner
      output) are appended to `rust_test_baseline` via
      `speccraft-state`. Without this update, the same test would
      keep counting as just-added on every subsequent red-check.

    - **Manual recapture.** `tools/cmd/speccraft-state/` exposes a
      `rust-baseline recapture` subcommand that overwrites
      `rust_test_baseline` with a freshly-walked snapshot of current
      canonical test IDs. Intended use case: a user installs speccraft
      on a crate that already has pre-existing failing tests; the
      initial-capture bakes them into the baseline, and after
      resolving them the user runs `recapture` to clear the staleness.

    Tests assert: (a) initial capture writes the baseline and skips
    red-check when the baseline is empty; (b) the captured set equals
    the result of the §What.2/§What.3 walk against a fixture crate;
    (c) post-accept update appends only the failing just-added IDs
    (not other tests, not passing tests); (d) `recapture` overwrites
    the baseline with the current walk; (e) all three mutations route
    through `speccraft-state` (extending AC #8's single-writer
    assertion).

## Out of scope

- **Cargo workspaces.** Deferred to spec 0006 (reserved). This spec handles
  single-crate projects only; workspace detection produces a hard error.
- **Retroactive runner-invocation adoption by Go and Python.** The primitive
  is designed to be language-neutral, but Go (0001) and Python (0002, 0003)
  continue to use sibling-file edit detection exclusively. Adoption by
  those languages is a separate spec.
- **Non-Cargo build systems.** Buck2, Bazel, and any other Rust build
  system are not supported. The guard assumes Cargo.
- **Doctests.** `/// # Examples` doctests are neither recognized as test
  edits nor invoked by the red-check runner.
- **Proc-macro crates.** Crates with `proc-macro = true` in their `[lib]`
  table have different build and test semantics; not supported here.
- **Benchmarks.** `#[bench]` functions and criterion-based benchmarks are
  not recognized as tests.
- **Cross-file unlock for inline-tests-only files.** See §Limitations §L1
  for the rule and its practical impact. More flexible unlock rules are a
  follow-up spec.

## Open questions

_none_
