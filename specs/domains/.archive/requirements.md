# Domain requirement archive

Verbatim superseded requirement text demoted from a domain file by spec consolidation. Append-only.

## state-and-config | spec 0049 | MODIFY
- `speccraft-state` is the sole sanctioned frontmatter-field writer: an unexported byte-safe `setFrontmatterField` (preserving field order, BOM, per-line LF/CRLF terminators, and EOF newline; no `.bak`) backs the only exported ops `SetStatus`/`SetRevision` (subcommands `set-status`/`set-revision`), with `SetRevision` monotonic-forward (refuses demotion) and both unconditionally refusing to mutate a `closed` spec (no `--force`); a single `parseFrontmatterBlock` grammar drives both reader and writer, and a meta-guard forbids raw `sed -i`/`perl -i`/`awk >` rewrites of `status:`/`revision:` in command libs (spec 0036)

## tdd-guard | spec 0048 | MODIFY
- The Go/Python/JS-TS production guard performs a real red-check, not a touch-check: it runs the just-added sibling test(s) through the runner primitive and allows the edit only when a test in the session's just-added set is observed to fail; `all_passed`, `build_failed`, a failure outside the just-added set, an empty just-added set, timeout, and runner error all block (spec 0018)

## tdd-guard | spec 0048 | MODIFY
- Unlike Rust (which has a persisted baseline), Go/Python/JS-TS block on an empty just-added set rather than allowing it; introducing a brand-new production symbol whose just-added test cannot compile pre-edit is the single sanctioned `/speccraft:spec:override` case (spec 0018)

## cross-env-portability | spec 0050 | MODIFY
- The full `tests/hooks/` bats suite runs on `macos-14` (`hooks-macos`) through Homebrew Bash 5 — macOS ships 3.2, so a runtime `BASH_VERSINFO[0] >= 5` assertion keeps a silently-3.2 job from passing for the wrong reason — and `scripts/assert-no-gnu-userland.sh` runs as a workflow step BEFORE bats (path-shape rejection of `*/gnubin/*` and `*/coreutils/libexec/*` plus a behavioural `--version` probe for a GNU binary reached through an unusual symlink), because a job greened by installing GNU userland passes while testing nothing; it is deliberately NOT a bats test since on Linux `tac` resolves legitimately and the assertion would invert (spec 0049)

## cross-env-portability | spec 0050 | MODIFY
- The shipped shell surfaces (`hooks/`, `commands/`, `tools/`, `templates/`, `agents/`, `skills/`) target BSD/macOS userland as well as GNU, enforced by a fixture-first portability meta-guard forbidding eight GNU-only forms (`sed -i` with no backup suffix, the `0,/re/` address, `tac`, `readlink -f`, `grep -P`, `stat -c`, `date -d`, `base64 -w`); matching is prefix-safe so `sed -i` never matches `sed -i.bak` or `sed -i ''`, is comment- and fence-blind with NO suppression marker (a guard silenceable by annotation is evadable by annotation), and `tests/**` plus `tools/**/*_test.go` are excluded as test-side, never installed (spec 0049)

## tdd-guard | spec 0050 | MODIFY
- One canonical `NormalizeStateKey` keys red candidates, baselines and build-repair log paths (abs → `EvalSymlinks` of the deepest EXISTING ancestor → rejoin the non-existent tail → `Clean`, so a file created in-session still gets a key), applied on BOTH sides of the sibling lookup. Two normalizers that disagree register a candidate under a key the lookup can never see — state.json plainly shows it while every production edit is refused. Pinned by a single-DEFINITION assertion plus PER-PACKAGE anchored routing scans, because the red-check is package-scoped and a structural RED cannot authorise an edit in another package (spec 0048)

