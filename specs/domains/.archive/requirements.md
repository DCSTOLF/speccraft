# Domain requirement archive

Verbatim superseded requirement text demoted from a domain file by spec consolidation. Append-only.

## state-and-config | spec 0049 | MODIFY
- `speccraft-state` is the sole sanctioned frontmatter-field writer: an unexported byte-safe `setFrontmatterField` (preserving field order, BOM, per-line LF/CRLF terminators, and EOF newline; no `.bak`) backs the only exported ops `SetStatus`/`SetRevision` (subcommands `set-status`/`set-revision`), with `SetRevision` monotonic-forward (refuses demotion) and both unconditionally refusing to mutate a `closed` spec (no `--force`); a single `parseFrontmatterBlock` grammar drives both reader and writer, and a meta-guard forbids raw `sed -i`/`perl -i`/`awk >` rewrites of `status:`/`revision:` in command libs (spec 0036)

