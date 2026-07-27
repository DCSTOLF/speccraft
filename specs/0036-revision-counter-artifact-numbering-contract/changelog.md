---
spec: "0036"
closed: 2026-07-27
---

# Changelog — 0036 revision-counter & artifact-numbering contract

## What shipped vs spec

All 15 ACs implemented; version bumped 1.10.0 → 1.11.0.

- **Reconciled-state core (AC1/AC13/AC14).** `ComputeRevisionState(specDir)` →
  `RevisionState{FrontmatterRevision, MaxArchived, Effective, HasArchived}` with the
  forward-only heal `Effective = hasArchived ? max(fmRev, maxArchived+1) : fmRev`
  (`tools/internal/speccraft/revision.go`). Ordinal scan factored into
  `listArchivedOrdinals` (single source of on-disk layout). Revision-value
  classification matrix (`parseRevisionValue`): absent / non-numeric ⇒ 0;
  over-uint64 literal ⇒ error; missing-dir / unreadable-spec ⇒ error distinct from a
  malformed `revision:` line.
- **One shared frontmatter grammar (AC13).** The single unexported
  `parseFrontmatterBlock` (BOM-tolerant, per-line CR, column-0 `^key:`, first-wins)
  is the sole entrypoint both the reader (`ComputeRevisionState`,
  `currentStatusClosed`) and the writer (`setFrontmatterField`) route through, pinned
  by `Test_ReaderAndWriter…RouteThroughParseFrontmatterBlock` + a source-scan
  asserting exactly one `func parseFrontmatterBlock(` exists.
- **Byte-safe writer (AC6/AC7).** Unexported `setFrontmatterField` (first-match-only,
  per-line terminator + BOM + EOF-newline preservation, deterministic inserted-line
  terminator, skip-write no-op, no `.bak`) built on the spec-0035 `AtomicWriteFile`
  seam via `splitRawLines`/`joinRawLines`.
- **Exported boundary ops (AC8/AC9/AC14).** `SetStatus` (enum-validated) and
  `SetRevision` (monotonic-forward — refuses demotion), both enforcing closed-spec
  immutability IN the exported op (no `--force`). A local `revErr` string-error type
  avoids an `fmt` import under the guard.
- **Five `speccraft-state` subcommands (AC2/AC3/AC4/AC5/AC8/AC9/AC14)** via the
  spec-0035 `run()` seam: `effective-revision`, `set-status`, `set-revision`,
  `reconcile-revision`, `archive-artifact`. Local overflow-guarded `parseUintArg`.
- **CMD-package archive move (AC3/AC4/AC15).** `tools/cmd/speccraft-state/archive.go`
  `moveArtifactNoReplace` with injectable `linkNoReplace=os.Link` / `unlinkFile=os.Remove`
  seams (genuine no-replace: `link` EEXIST = no-clobber), and `os.SameFile`
  inode-identity interrupted-move recovery (link-ok/unlink-fail retry unlinks the
  source rather than duplicating; fails safe with no same-inode sibling) — NOT
  byte-equality.
- **Self-healing shell (AC4/AC5/§B).** `preflight_archive_collisions` DELETED;
  `archive_rename` computes `A=effective-revision` once and archives the disposable
  set under one ordinal; `bump_revision` is a thin reconcile-revision → set-status
  draft helper (fixed order archive → counter → status-LAST, no raw `sed`); `revise.md`
  drops the preflight call + N_OLD arg; `close.md` step 6 uses `set-status … closed`.
- **AC10 meta-guard.** `tests/hooks/frontmatter-writer-guard.bats` fixture-first,
  per-tool matching regime (sed/perl last-positional; awk redirect target),
  `specs/*/spec.md` glob, asserts the live `commands/` tree clean.
- **New semantics (§D).** Within-draft edits keep the same revision by design; the
  counter advances only through the archive path. The two pre-existing spec-0015
  `bump_revision`-increment tests were rewritten to the archive-driven heal.

## Deviations

1. **One planned override only** (T1 new-symbol bootstrap; AC12 budget ≤1 held).
2. **`parseFrontmatterBlock` lives IN `revision.go`, not its own file** — spec AC13
   text said "its own file"; the TESTED property (single routed entrypoint) holds.
   File split deferred to avoid a duplicate-symbol guard deadlock.
3. **T9/T10 collapsed** — the T8 writer already satisfied every byte-safety edge, so
   T9 tests pinned green and T10 was a no-op (no fake RED manufactured).
4. **Over-domain rejection for `SetRevision` is at CLI arg parse** (`parseUintArg`),
   since the Go signature is `uint64`-typed; over-domain on-disk `revision:` literal
   is a `ComputeRevisionState` error.
5. **Recurring stale-1.1.0-cached-guard friction** — REDs via Edit (fresh test-func
   as LAST sibling touch), Bash only for mechanical build-fixes (import-then-use
   deadlock + three literal-BOM-in-source breaks), a re-registered companion RED on
   the version bump (no-new-test-edit-clears-RED trap).

## Files touched

New Go: `tools/internal/speccraft/{revision.go, revision_test.go, frontmatter_test.go,
frontmatter_writer_test.go}`; `tools/cmd/speccraft-state/{archive.go,
archive_artifact_cmd_test.go, effective_revision_cmd_test.go,
reconcile_revision_cmd_test.go, set_revision_cmd_test.go, set_status_cmd_test.go}`.
New bats: `tests/hooks/{spec-revise-selfheal.bats, frontmatter-writer-guard.bats}`.
Modified: `tools/cmd/speccraft-state/main.go` (5 subcommands + `usage()`); the three
`const version` binaries + `version_test.go` siblings; `.claude-plugin/{plugin.json,
marketplace.json}` + `manifest_version_test.go`; `commands/spec/{revise.lib.sh,
revise.md, close.md}`; `tests/hooks/spec-revise-preflight.bats`.

## The 5-round cross-model review payoff

Five rounds (codex `gpt-5.6-sol` + claude-p) converged dual-verdict at round 5. Real
defects caught PRE-implementation: (1) the authority contradiction ("disk wins" vs
"frontmatter sole authority") → the forward-only Authority model; (2) the `--force`
closed-spec escape hatch = guardrail violation → removed, enforced in the exported op;
(3) archiving `spec.md` would leave nothing to counter-bump → only the disposable set
is archived; (4) the `A+1`-vs-heal contradiction (a retry minting a spurious extra
revision) → one unified rule (counter = `Effective` recomputed AFTER the moves);
(5) interrupted-move data-safety (byte-equality could delete a live source matching an
unrelated archive) → `os.SameFile` inode identity + fail-safe (AC15).

## ADR proposed for history.md

Appended as the `2026-07-27` entry (spec 0036).

## Conventions proposed

Added to `.speccraft/conventions.md`: local-error-type / manual-parse to dodge
new-import guard deadlocks; CMD-package placement of fault-injectable logic to ride
the `run()` seam at override budget 1; the shared single-parser-entrypoint +
source-scan assertion pattern; the fixture-first per-tool meta-guard matching regime;
and "within-draft edits keep the same revision (counter advances only on archive)".

## Architecture updates

Added the revision / frontmatter-writer layer, the five new `speccraft-state`
subcommands, the CMD-package archive move + inode recovery, and the
`revise.lib.sh`-delegates-to-`speccraft-state` note.
