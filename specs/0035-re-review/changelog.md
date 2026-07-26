---
spec: "0035"
closed: 2026-07-26
---

# Changelog — 0035 re-review

## What shipped vs spec

Diff-focused re-review shipped as `/speccraft:spec:review --diff`, version
1.9.0 → 1.10.0. When a spec is re-reviewed, reviewers now assess only the deltas
since the last review plus a regression sweep, instead of re-litigating every
already-settled section. The anchor is a review-time snapshot (`review-snapshot.md`),
not git history, because review runs while the spec is still uncommitted.

New Go in `tools/internal/speccraft`:

- `AtomicWriteFile(path, data, perm)` — same-directory temp + rename durable-write
  seam with an injectable `atomicRename` for fault-injection tests (AC1/AC2).
- `WriteReviewSnapshot(specDir)` — copies `spec.md` → `review-snapshot.md`, returns
  the sha256 of the RAW spec bytes (no CRLF/LF/BOM/trailing-newline normalization);
  true no-op (no rewrite, no mtime touch) when the on-disk snapshot is already
  byte-identical, reusing the spec-0020 robust-noop precedent (AC1).
- `ReviewDiff(specDir, promote)` — reads `spec.md` once and returns
  `ReviewEnvelope{schema:1, snapshot, changed, changed_sections, diff, fingerprint,
  base_fingerprint}`. `fingerprint` = sha256 of current spec bytes; `base_fingerprint`
  = sha256 of the OLD snapshot (nil/null on first review). With `--promote` the same
  captured bytes are frozen as the new snapshot AFTER the envelope is computed
  (read-before-overwrite) (AC3/AC4/AC6/AC11).
- `diffSections` + `parseSpecDoc`/`renderDiff` (`review_sections.go`) — the AC5
  determinism engine: structured `ChangedSection{kind, heading, ordinal, side}`,
  pure ordinal-key matching per document, byte-identical bodies NEVER emitted (even
  under ordinal shift), no blanket over-report, a rename surfaces as removed+added,
  `(frontmatter)`/`(preamble)` are reserved kinds distinct from a literal
  `## (frontmatter)` heading (which is `kind:"section"`).
- `WriteReviewFile(path, body, fingerprint)` — AC2 single atomic commit: strips any
  prior `reviewed_sha256:` lines, appends exactly one canonical line, writes the
  complete file via `AtomicWriteFile` (no intermediate fingerprint-free write).

New `speccraft-state` subcommands (via the compile-stable `run()` seam):
`review-snapshot write`, `review-diff [--promote]` (exit-code matrix; `--promote`
refused on a closed spec via a new `specStatusIsClosed` frontmatter probe), and
`review-commit` (see Deviations).

New `templates/prompts/re-review.md` (AC7a): the scoped brief carrying `{{DIFF}}` /
`{{CHANGED_SECTIONS}}` and an explicit regression-sweep instruction.

New `commands/spec/review.lib.sh` (AC7b/AC8/AC9/AC11): `review_reviewed_sha256`
(anchored `^reviewed_sha256: [0-9a-f]{64}$` usability parser), `review_classify`
(provenance gate → full-review / short-circuit / scoped, gated on prior
`review.md` reviewed_sha256 == envelope base_fingerprint — the retry-safety +
baseline-provenance fixes from review rounds 5–6), and `review_build_payload`
(sources the frozen `review-snapshot.md`, never `spec.md`). `commands/spec/review.md`
wires the `--diff` transaction and the atomic fingerprint recording (step 6).

`speccraft-drift` (`drift/rules.go` `CheckFile`) now excludes the whole `specs/**`
tree in addition to `.speccraft/`, so a snapshot byte-copying `enforce:` prose from
`spec.md` cannot trip drift (AC10).

Version bumped 1.9.0 → 1.10.0 across the three `const version` binaries (each via a
renamed sibling version test) + both JSON manifests via a grep oracle (AC12). The
published-verified release chain (auto-tag → release.yml → verify-release.sh) is the
merge-time definition of done (AC12 / T31).

New bats `tests/hooks/spec-review-diff.bats` (15 tests) covers the template grep
oracle, the usable-parser + provenance gate, and the payload/AC11 command-layer
oracle.

ACs covered: AC1–AC13 (T31's published-verified release fires on the close push).

## Deviations from spec

- **ONE `/speccraft:spec:override` (T1)** — the planned new-symbol bootstrap for the
  `review-diff`/`review-snapshot` type. AC13 budget (≤1) held.
- Implemented **in-place** in `review.go` (+ `review_sections.go`) rather than
  one-file-per-function, to avoid duplicate-symbol deadlocks with the stub bootstrap
  under the guard.
- **Skipped the optional T3 `saveStateLocked` refactor** (not AC-required) —
  `AtomicWriteFile` was added as a fresh seam; `saveStateLocked` was left as-is.
- **Added an UNPLANNED `review-commit` subcommand** so the markdown command can
  invoke AC2's atomic commit across the CLI boundary (the command layer is
  markdown/bash and cannot call `WriteReviewFile` directly).
- **Determinism switched to pure ordinal-key matching** (rounds 5–6): removed the
  earlier blanket duplicate-count over-report that contradicted the byte-identical
  rule.
- **Incidental, user-made:** `.speccraft/agents.toml` codex cmd changed from
  `--full-auto` to `--sandbox workspace-write` (unblocked codex for cross-model
  review); included in this diff.
- **Cross-model review took 9 rounds** (dual-approve at round 9). Codex's adversarial
  passes drove out 4 real correctness bugs pre-implementation: an unimplementable
  read-before-overwrite transaction, retry-safety, baseline-provenance, and AC2
  atomicity (a two-step append → a single atomic commit).
- **Stale-1.1.0-cached-guard friction (recurring):** decisive REDs were registered via
  Edit (the Write blind spot), a fresh test-func kept as the last sibling touch, and
  Bash used only for mechanical build-fixes (unused import / dead var), never to
  bypass a behaviour RED→GREEN. The no-new-test-edit-clears-standing-RED gotcha bit
  once (drift import fix), remedied by adding a fresh test func.

## Files touched

- `tools/internal/speccraft/review.go` (new)
- `tools/internal/speccraft/review_sections.go` (new)
- `tools/internal/speccraft/review_test.go` (new — bootstrap anchor)
- `tools/internal/speccraft/atomicwrite_test.go` (new)
- `tools/internal/speccraft/review_snapshot_test.go` (new)
- `tools/internal/speccraft/review_diff_test.go` (new)
- `tools/internal/speccraft/review_diff_promote_test.go` (new)
- `tools/internal/speccraft/review_diff_sections_test.go` (new)
- `tools/internal/speccraft/review_commit_test.go` (new)
- `tools/internal/speccraft/drift/rules.go` (+ `rules_test.go`)
- `tools/internal/speccraft/manifest_version_test.go`
- `tools/cmd/speccraft-state/main.go` (+ `review_snapshot_cmd_test.go`,
  `review_diff_cmd_test.go`, `review_commit_cmd_test.go`, `version_test.go`)
- `tools/cmd/speccraft-guard/main.go` (+ `version_test.go`)
- `tools/cmd/speccraft-drift/main.go` (+ `version_test.go`)
- `commands/spec/review.lib.sh` (new)
- `commands/spec/review.md`
- `templates/prompts/re-review.md` (new)
- `tests/hooks/spec-review-diff.bats` (new)
- `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`
- `.speccraft/agents.toml` (incidental, user-made)
- `.speccraft/{conventions.md,architecture.md,history.md,index.md}` (memory)

## ADR proposed for history.md

Appended as `## 2026-07-26 — Diff-focused re-review scopes reviewers to the deltas
since the last review; version 1.10.0 (spec 0035)`.

## Conventions proposed

- Extended `.speccraft/conventions.md` §"Review snapshot + diff-focused re-review"
  (author-seeded) with the `AtomicWriteFile` same-dir temp+rename shared durable-write
  seam and the `run()`-seam-for-new-subcommands note.
