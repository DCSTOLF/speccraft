# Domain: tdd-guard

Core PreToolUse TDD enforcement: production-vs-test gating, sibling-test unlock, red-check accept/reject, and the override escape hatch.

- The `speccraft-guard pre-tool-use` TDD invariant (active spec required plus a sibling test edited in-session) applies to Python production files with the same block message used for Go (spec 0002)
- For Rust, the guard's red-check accepts an edit only when the runner reports `at_least_one_failed` for a failing test in the just-added set; `build_failed` is rejected as `"build failed"` and `all_passed` (ignored tests included) is rejected as `"no failing test observed"` (spec 0005)
- Before each guarded Rust edit the guard runs a pre-edit gate (`cargo check --tests` by default), short-circuited to zero `cargo`/`rustc` subprocesses when a whole-crate SHA-256 fingerprint of tracked files (`.rs` under `src/`,`tests/`,`examples/`,`benches/` plus `Cargo.toml`/`Cargo.lock`/toolchain configs, excluding `target/`) is unchanged in-session (spec 0005)
- The guard rejects Cargo workspaces (a root `Cargo.toml` with a `[workspace]` table) with a hard error naming the condition and referencing reserved follow-up spec 0006; only single-crate projects are supported (spec 0005)
- The Go/Python production guard consumes a single-shot override before the sibling-test check: when `override_pending` is set it allows exactly one edit and atomically clears the flag; the Rust dispatch path is not covered by override (spec 0009)
