# Domain: state-and-config

Durable persistence: `state.json` schema and single-writer rule via `speccraft-state`, `speccraft.toml` config loading, baselines/fingerprints/override flag.

- `.speccraft/speccraft.toml` defines a `[tdd] test_roots` list of repo-root-relative directories searched for Python tests, parsed by `speccraft-state`, defaulting to empty (same-directory-only) when the file is absent (spec 0003)
- `/speccraft:init` auto-detects `tests/` and `test/` at the repo root and proposes adding them to `speccraft.toml` for user approval rather than injecting silently; declining or absence leaves no `speccraft.toml` created (spec 0003)
- `state.json` carries a `rust_test_baseline` (list of canonical Rust test IDs) and a `rust_gate_fingerprint` (crate fingerprint), both read and written exclusively through `speccraft-state`, preserving the single-writer rule for `state.json` (spec 0005)
- The `rust_test_baseline` is maintained by exactly three mutations: initial capture (writes the baseline and skips the red-check on first run), post-accept append of the failing just-added IDs, and a `speccraft-state rust-baseline recapture` subcommand (spec 0005)
- `state.json` carries a `Session.OverridePending` field (`override_pending,omitempty`) exposed through `speccraft-state get/set` with `"true"`/`"false"` values, plus a `ConsumeOverride` atomic read-and-clear that returns true exactly once and then persists false (spec 0009)
