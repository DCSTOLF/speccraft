# History

Append-only. Newest first.

## 2026-05-29 — Rust language support (spec 0005)

**Spec:** specs/0005-rust-language-support/
**Decision:** Add Rust as a first-class supported language with three architectural extensions: (1) a new shared **test-runner invocation primitive** in `tools/internal/speccraft/runner/` (language-neutral interface, per-language adapters); (2) a **dispatch-by-language pattern** in `speccraft-guard` (`dispatchByLanguage` + `rustDispatch`, preserving the existing Go/Python codepath unchanged); (3) a **`reserves-specs` spec-frontmatter field** for forward-referencing follow-up specs by stable ID before they exist on disk.
**Why:** Rust's idiomatic unit tests live inline inside `#[cfg(test)] mod tests` blocks within the same `.rs` file as the production code under test. Sibling-edit detection (the basis for Go and Python support) cannot distinguish "added a test" from "edited prod" within a single file edit. The runner becomes the authoritative oracle for "did the just-added test actually fail?", while a delta-based static classifier handles "did this edit add a test?" — making the system sound even with the inline-tests model. The dispatch-by-language pattern keeps the new wiring isolated from the proven Go/Python paths. The `reserves-specs` field lets AC #5's workspace-detection error name spec `0006` by stable ID before `0006` exists.
**Consequence:**
- `tools/internal/speccraft/runner/` is now shared infrastructure intended for future per-language adapters; the interface has been validated against Rust only. Retroactive adoption by Go/Python is **explicitly a non-goal** and is deferred to a separate spec if ever pursued.
- Adding a new language to `speccraft-guard` is now a localized change: implement a `<lang>Dispatch` function and add a case to `dispatchByLanguage`. The previous open-coded switch is gone.
- The `reserves-specs` field is documented in `.speccraft/conventions.md` as advisory — `/speccraft:spec:new` does not yet implement reservation-aware ID allocation. Tooling support is deferred.
- `.speccraft/state.json` gains `rust_test_baseline` (list) and `rust_gate_fingerprint` (string). The single-writer rule for state.json is extended to cover both, asserted by a grep-based regression test.
- Cargo workspaces are explicitly unsupported in this release; spec id `0006` is reserved for the follow-up.

## 2026-05-22 — Slash-command names fully qualified to `/speccraft:spec:*`

**Spec:** none (maintenance; commits 697c868, 5041bc6, a4ff4db)
**Decision:** Migrate all slash commands from bare names (`/spec:new`) to the fully qualified plugin form (`/speccraft:spec:new`) in README, e2e tests, and every command file's "next steps" hints.
**Why:** Bare names collide with host-repo commands once the plugin is installed via marketplace. Fully qualified names are unambiguous and match Claude Code's plugin command namespacing.
**Consequence:** All user-facing documentation, e2e assertions, and inter-command references must use the qualified form. Any new command added under `commands/spec/` is invoked as `/speccraft:spec:<name>`.

## 2026-05-15 — Python TDD support (specs 0002, 0003)

**Spec:** specs/0002-python-tdd-support/, specs/0003-python-separate-test-roots/
**Decision:** Extend `speccraft-guard`'s red→green detection to Python projects via a `speccraft.toml` config that declares language, test command, and test-file discovery strategy (sibling vs separate tree).
**Why:** First non-Go host-repo adopter needed pytest-driven TDD enforcement without forking the guard binary.
**Consequence:** Guard logic is now language-pluggable through config rather than hard-coded. Future languages add a config recipe, not a new binary. Spec immutability rule still applies: 0002 and 0003 are closed.

## 2026-05-10 — Plugin packaged via `dcstolf-tools` marketplace

**Spec:** none (packaging work, pre-0001 closure; commit 6950511)
**Decision:** Ship speccraft as a single-plugin entry inside the `dcstolf-tools` Claude Code marketplace (`.claude-plugin/plugin.json` + root `marketplace.json`).
**Why:** Distribution channel for Claude Code plugins; lets users install with one command and pins versioning.
**Consequence:** The plugin's install path is now load-bearing — do not introduce a second entrypoint. `marketplace.json` schema must validate against the upstream JSON Schema.

## 2026-05-28 — speccraft adopted

**Spec:** specs/0001-speccraft-v1/
**Decision:** Adopt speccraft for spec-first TDD workflow.
**Why:** Establish disciplined spec-first development from day one.
**Consequence:** All future code changes go through `/speccraft:spec:new`.
