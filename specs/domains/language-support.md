# Domain: language-support

Per-language test-file recognition and language config: Go/Python naming heuristics, test-root search, Rust inline/integration detection, `[tdd.*]` config schema.

- `IsTestFile` recognizes Python tests by both the `test_*.py` (pytest prefix) and `*_test.py` (suffix) naming conventions, while `conftest.py` is classified as production code (spec 0002)
- `SiblingTestFiles` for a `.py` production file globs both `test_*.py` and `*_test.py` in the same directory and deduplicates results; Go sibling lookup remains `*_test.go` only (spec 0002)
- When same-directory sibling lookup finds no test for a `.py` production file, `SiblingTestFiles` searches each configured test root recursively by filename stem for `test_<stem>.py` or `<stem>_test.py`, with no path mirroring (spec 0003)
- Colocated same-directory siblings take precedence over configured test roots, which are consulted only when same-directory lookup yields nothing; test-root search never applies to `.go` files (spec 0003)
- Rust support is configured via a `[tdd.rust]` subsection in `speccraft.toml` whose `runner` selects `"cargo"` (default, assumed when absent) or `"nextest"`; unknown values are a config error and there is no PATH-based auto-detection (spec 0005)
- Rust inline tests are recognized by a delta-based, string/comment-aware classification that flags an edit as a test edit only when it adds at least one new test function inside a `#[cfg(test)] mod` block (spec 0005)
- Rust integration tests are recognized by stem-mapping `tests/<stem>.rs` to `src/<stem>.rs`, `src/<stem>/mod.rs`, or `src/<stem>/`; `src/lib.rs` is never a stem-mapping target (spec 0005)
