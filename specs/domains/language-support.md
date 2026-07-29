# Domain: language-support

Per-language test-file recognition and language config: Go/Python naming heuristics, test-root search, Rust inline/integration detection, `[tdd.*]` config schema.

- `IsTestFile` recognizes Python tests by both the `test_*.py` (pytest prefix) and `*_test.py` (suffix) naming conventions, while `conftest.py` is classified as production code (spec 0002)
- `SiblingTestFiles` for a `.py` production file globs both `test_*.py` and `*_test.py` in the same directory and deduplicates results; Go sibling lookup remains `*_test.go` only (spec 0002)
- When same-directory sibling lookup finds no test for a `.py` production file, `SiblingTestFiles` searches each configured test root recursively by filename stem for `test_<stem>.py` or `<stem>_test.py`, with no path mirroring (spec 0003)
- Colocated same-directory siblings take precedence over configured test roots, which are consulted only when same-directory lookup yields nothing; test-root search never applies to `.go` files (spec 0003)
- Rust support is configured via a `[tdd.rust]` subsection in `speccraft.toml` whose `runner` selects `"cargo"` (default, assumed when absent) or `"nextest"`; unknown values are a config error and there is no PATH-based auto-detection (spec 0005)
- Rust inline tests are recognized by a delta-based, string/comment-aware classification that flags an edit as a test edit only when it adds at least one new test function inside a `#[cfg(test)] mod` block (spec 0005)
- Rust integration tests are recognized by stem-mapping `tests/<stem>.rs` to `src/<stem>.rs`, `src/<stem>/mod.rs`, or `src/<stem>/`; `src/lib.rs` is never a stem-mapping target (spec 0005)
- `IsJSTSTestFile` recognizes JS/TS tests by `*.test.*`/`*.spec.*` suffixes across the eight extensions `{js,ts,jsx,tsx,mjs,cjs,mts,cts}` and any file under a `__tests__/` path segment, and is wired into the top-level `IsTestFile` (spec 0010)
- Both JS/TS classifiers exclude any path containing `node_modules` or `dist` as an exact slash-segment (`filepath.Clean` semantics), and `.d.ts`/`.d.mts`/`.d.cts` declaration files are classified as neither test nor production (spec 0010)
- JS/TS sibling resolution for a production `<dir>/<stem>.<ext>` matches a same-directory `<stem>.test/.spec.<any-ext>` or an immediate `<dir>/__tests__/` counterpart only (no ancestor walk), with candidate and stored paths compared in `filepath.Clean` form (spec 0010)
- `speccraft.toml` gains `[tdd.go]`, `[tdd.python]`, `[tdd.javascript]`, and `[tdd.typescript]` runner keys mirroring `[tdd.rust]`; Go/Python default to `go test`/`pytest`, while JS/TS have no safe default and must be configured (config-only resolution, no `package.json` inference) (spec 0018)
