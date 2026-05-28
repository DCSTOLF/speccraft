# History

Append-only. Newest first.

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
