# Domain requirement archive

Verbatim superseded requirement text demoted from a domain file by spec consolidation. Append-only.

## state-and-config | spec 0049 | MODIFY
- `speccraft-state` is the sole sanctioned frontmatter-field writer: an unexported byte-safe `setFrontmatterField` (preserving field order, BOM, per-line LF/CRLF terminators, and EOF newline; no `.bak`) backs the only exported ops `SetStatus`/`SetRevision` (subcommands `set-status`/`set-revision`), with `SetRevision` monotonic-forward (refuses demotion) and both unconditionally refusing to mutate a `closed` spec (no `--force`); a single `parseFrontmatterBlock` grammar drives both reader and writer, and a meta-guard forbids raw `sed -i`/`perl -i`/`awk >` rewrites of `status:`/`revision:` in command libs (spec 0036)

## tdd-guard | spec 0048 | MODIFY
- The Go/Python/JS-TS production guard performs a real red-check, not a touch-check: it runs the just-added sibling test(s) through the runner primitive and allows the edit only when a test in the session's just-added set is observed to fail; `all_passed`, `build_failed`, a failure outside the just-added set, an empty just-added set, timeout, and runner error all block (spec 0018)

## tdd-guard | spec 0048 | MODIFY
- Unlike Rust (which has a persisted baseline), Go/Python/JS-TS block on an empty just-added set rather than allowing it; introducing a brand-new production symbol whose just-added test cannot compile pre-edit is the single sanctioned `/speccraft:spec:override` case (spec 0018)

