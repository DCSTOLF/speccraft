# Domain: test-runner

The language-neutral test-runner invocation primitive: interface shape, normalized records/outcomes, targeted single-test invocation, canonical test IDs, adapters.

- A language-neutral test-runner primitive lives in `tools/internal/speccraft/runner/`: an interface taking a touched file and an optional test-name filter and returning normalized `{test_name, status, scope}` records plus an outcome enum of `build_failed`, `all_passed`, or `at_least_one_failed` (spec 0005)
- Runner adapters always invoke a single targeted fully-qualified test (never a full-suite run) and own their own output parsing; the Rust adapter supports `cargo test` and `cargo nextest run`, and doctests are never invoked (spec 0005)
- The canonical Rust test ID is the fully-qualified libtest `<module-path>::<fn>` form (crate prefix stripped), used identically by static discovery, runner records, and just-added set-differencing (spec 0005)
- The runner primitive is extended beyond Rust with per-language adapters — Go (`go test`), Python (`pytest`), and one shared JS/TS adapter (`vitest`/`jest`) — each owning its own argv construction, output parsing, and outcome classification; adapter invocations are bounded by `context.WithTimeout`, a deadline overrun surfacing as a Go error rather than a new `Outcome` enum value (spec 0018)
