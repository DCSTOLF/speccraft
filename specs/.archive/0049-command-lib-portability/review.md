---
spec: "0049"
reviewers: [codex, claude-p]
quorum: 1
verdict: approve-with-comments
generated: 2026-09-15T15:21:52+00:00
rounds: 3
---

# Cross-model review — 0049

## Independence check

The orchestrator's anti-false-quorum check ran before synthesis and **passed**:
the two raw outputs are genuinely independent generations, not copies or
near-duplicates of one another.

- `codex` output: md5 `25dccc39a2fd009b6c79ccabb9bbd58b`, 4554 bytes
- `claude-p` output: md5 `d9b14039b689df5857e22a3717b927f1`, 7496 bytes

## codex

**Verdict:** changes-requested

Concerns:
- AC2's read-only-file fixture is not a reliable write-failure test — `setFrontmatterField` writes via a same-directory temp file + `rename`, and `rename(2)` succeeds into a writable parent regardless of the target's mode (and may succeed as a privileged CI user regardless).
- The macOS-test scope is internally contradictory: "What" item 4 and "Out of scope" declare `tests/**` Linux-only and permit GNU-only `sed`/`stat` forms there, while AC10 requires the *full* `tests/hooks` bats suite to pass on `macos-14`.
- AC10 does not define the macOS toolchain: macOS ships Bash 3.2 by default while the repo requires Bash 5+, and the spec does not say how Bash 5, bats, and helper binaries are installed, or how the suite is forced onto the intended Bash.
- Installing GNU utilities to make the existing `tests/hooks` suite pass on macOS could mask the very production portability defects the job exists to expose; the PATH/tool-resolution policy is unspecified.
- The `SetStatus` API evolution is underspecified — unclear whether the exported Go operation changes signature, gains a sibling operation, or how existing callers stay source-compatible.
- The portability guard's matching semantics are underspecified for shell syntax (`sed -i.bak`, `sed -i ''`, quoting, multiline commands, wrapper variables, comments, Markdown fences) and could false-positive/false-negative.
- AC8 does not specify a byte-level contract for multiline history entries, blank lines, duplicates, or missing-final-newline input when replacing `tac` — a line-reversing implementation could reverse entry *contents* rather than entry *order*. **(Orchestrator-verified and rejected — see below.)**
- The status-kind contract does not state whether `--kind` validates only the enum or also that the supplied artifact actually has that kind.

Suggestions:
- Replace AC2's fixture with a deterministic injected failure at the atomic-write/rename seam; assert non-zero status, stderr, byte-identical target, and temp cleanup.
- Split `tests/hooks` into portable and Linux-only subsets (or port the whole suite), state exactly which subset macOS runs, install Bash 5 + bats explicitly, invoke bats through Bash 5, and keep BSD userland ahead of any GNU compat tools on PATH.
- Define a concrete Go API (`SetStatus(path, kind, status)`, a typed `ArtifactKind`, or a compatibility wrapper) and pin both callers and CLI parsing with table-driven tests.
- Specify entry-aware reversal using parsed history records, preserving each record's bytes while reversing only record order.
- Define the portability guard as a fixture-driven parser or explicitly bounded lexical scanner, with fixtures covering quoting, comments, continuations, Markdown fences, variable indirection, and both GNU/BSD `sed` spellings.

## claude-p

**Verdict:** approve-with-comments

Concerns:
- Open question 1 (release sequencing) is a blocking prerequisite, not a review-time nit — per the `feedback_bump_before_close` rule, a release-carrying spec must bump the six version locations *before* `spec:close`, since closed-spec immutability blocks a post-close bump. With 0047 and 0048 already unreleased on top of 1.16.0, 0049 either owns the bump or it doesn't; needs to be pinned before `spec:plan`.
- AC2 requires a stderr diagnostic on write failure, but AC4 (invalid-status), AC5 (closed-immutability), and the implicit malformed-frontmatter case only say "non-zero." Silent-success-on-a-lie was the original bug; a silent non-zero (return 1, empty stderr) is only a partial fix. The stderr-diagnostic requirement should be uniform across every non-zero exit both helpers can produce.
- AC8's "`tac` absent from `PATH`" fixture leaves one failure mode unpinned: the POSIX-reversal fix itself will rely on `awk`/`sed`, and if AC9's portability guard lands after AC8's fix, the fix's exact form could trip the guard if that form isn't in the guard's permitted fixture set. Both should land in the same commit, with the guard's permitted set extended to the exact reversal form used.
- AC7 marks the pre-fix `arch_set_status` line as a FORBIDDEN guard fixture. Once this spec closes, spec 0025's consolidation will move it to `specs/.archive/0049-.../spec.md` verbatim. Need to confirm the frontmatter-writer meta-guard's scan roots exclude `specs/**` — otherwise the guard could flag its own spec's archived fixture quote. **(Orchestrator-verified, no action needed — see below.)**

Suggestions:
- Pin the `--kind` flag shape (position relative to positionals; whether `--kind=X` and `--kind X` are both accepted) via a bats or Go test.
- Consider a bounded, non-destructive exception to "no cleanup": `/speccraft:sync` could *report* (not delete) stray `<file>-E` / `<file>-[A-Z]` siblings in `.speccraft`-managed directories, with a recovery hint — a possible follow-up, out of scope for 0049.
- For AC8, pin the fix against a fixture with mixed-provenance history entries (backfilled + real) — `consolidate_backfill_order` composes history-chronological + history-less-appended, and the `tac` bug specifically dropped the history-chronological half; a fixture that only checks ordering on a history-only set would green a fix that still drops the history-less half.
- AC11 is a strong invariant but has no mechanical CI oracle as worded; consider demoting it to an author-facing `tasks.md` checklist item, or adding a `scripts/verify-linux-pins.sh` that reverts each of the three fixes in turn and asserts a bats failure.
- The portability guard's `stat -c` → `stat -f` mapping is macOS-specific; consider permitting a Go-helper redirect (e.g., a `speccraft-state stat` subcommand) per `conventions.md`'s precedent of pushing platform-specific work into the Go binary rather than a shell polyfill.

## Synthesis

Both reviewers converge on the spec's diagnosis and architectural direction
being correct — routing PM/Architect status writes through the sanctioned
`speccraft-state set-status` writer, rather than portability-patching the
`sed`, is the disciplined fix, and the kind-scoped status enum correctly
avoids collapsing three distinct artifact state machines into one. Where they
diverge is scope: codex focuses entirely on test-feasibility defects in the
ACs, while claude-p is more approving of the spec's shape overall but surfaces
a blocking sequencing question plus several fixture-precision gaps.

The orchestrator independently verified the load-bearing claims against the
current code before this synthesis, and two of codex's concerns are
**confirmed and blocking**:

- **AC2's fault-injection seam is broken as written.** `setFrontmatterField`
  routes through `AtomicWriteFile` (same-directory temp file + `os.Rename`).
  `rename(2)` into a writable parent directory succeeds regardless of the
  target file's mode, so a read-only-file fixture cannot induce the failure
  AC2 claims to test. Repo precedent for the correct pattern exists: spec
  0035's injectable `atomicRename` seam.
- **AC10's macOS bats suite is infeasible as written.** `tests/hooks/spec-revise-preflight.bats:695-793`
  contains seven `sed -i 's/.../'` calls that fail under BSD sed, and
  `tests/e2e/assertions/test_session_env_writable.sh` uses `stat -c`. macOS
  also ships Bash 3.2 by default against the repo's Bash 5+ requirement, and
  installing GNU coreutils/gsed to paper over this would mask the very
  production defects this CI leg exists to catch. AC10 needs a stated
  toolchain + PATH policy and an explicit portable-vs-Linux-only test subset.

One codex concern was checked and is **not valid**: the claim that AC8's
`tac`-replacement needs a multiline-entry byte contract. `history_parse_entries`
(`commands/spec/consolidate.lib.sh`, feeding the loop at line 409, function
defined at `commands/history/compact.lib.sh:31-38`) prints only matching
`^## YYYY-MM-DD` header lines — one line per entry; entry bodies are never
emitted into the stream that gets reversed. The stream is one line per entry,
so line-reversal *is* entry-reversal, and there is no multiline byte contract
at risk. This is recorded below as considered-and-rejected rather than folded
into the required spec edits.

One claude-p concern was checked and requires **no spec action**: the
frontmatter-writer meta-guard's scan (`tests/hooks/frontmatter-writer-guard.bats:56`)
targets `"$PLUGIN_DIR/commands"` only — nothing scans `specs/**` — so the
archived spec quoting the forbidden `sed -i` line verbatim after close cannot
false-positive the guard. The spec should still state this invariant
explicitly so a future contributor does not widen the scan root and
accidentally reintroduce the failure mode claude-p flagged.

Claude-p's release-sequencing concern (open question 1) is independently
corroborated by the spec's own open-questions section and by project memory
(`feedback_bump_before_close`): with 0047 and 0048 both unreleased on top of
1.16.0, this needs a decision before `spec:plan`, not deferred to
implementation time as the spec currently phrases it.

**On quorum versus honesty:** `.speccraft/agents.toml` sets `review_quorum =
1`, and claude-p's `approve-with-comments` numerically satisfies that quorum.
This synthesis deliberately does not resolve to `approve-with-comments` on
that basis. Two acceptance criteria (AC2, AC10) are verified-defective as
written — not stylistic nits, but ACs that cannot be satisfied by any
implementation as currently specified. A bare quorum count here would have
marked a spec about eliminating silent-success-on-a-lie bugs as `reviewed`
while carrying two known-broken ACs into `spec:plan` — the same failure mode
this spec exists to fix, just one level up the process. The overall verdict is
**changes-requested**.

### Must-fix before plan

1. **AC2 — fault-injection seam, not a read-only fixture.**
   Evidence: `setFrontmatterField` → `AtomicWriteFile` (temp file in the same
   directory + `os.Rename`); `rename(2)` succeeds into a writable parent
   regardless of target mode. A read-only-file fixture does not reliably
   induce a write failure.
   Proposed AC2 rewording: "When the underlying write fails, `arch_set_status`
   and `pm_set_status` return non-zero and emit a diagnostic to stderr. Pinned
   by a test that injects failure at the atomic-write/rename seam (e.g., an
   injectable rename hook, per spec 0035's `atomicRename` seam, or a
   non-writable *parent directory* rather than a read-only file) and asserts:
   non-zero exit, non-empty stderr, byte-identical target file, and no
   leftover temp file."

2. **AC10 — macOS toolchain + PATH policy, and a stated portable subset.**
   Evidence: `tests/hooks/spec-revise-preflight.bats:695-793` (seven `sed -i
   's/.../'` GNU-only calls), `tests/e2e/assertions/test_session_env_writable.sh`
   (`stat -c`), macOS's default Bash 3.2 against the repo's Bash 5+
   requirement.
   Proposed AC10 rewording: "`.github/workflows/ci.yml` runs a stated,
   explicitly-enumerated subset of `tests/hooks/` — the subset that is
   genuinely BSD/GNU-portable — on `macos-14`, with Bash 5 and bats installed
   explicitly and invoked via the installed Bash 5 (not the system Bash 3.2).
   The job does not install GNU coreutils/gsed onto PATH ahead of BSD
   userland; any test requiring GNU-only behavior is excluded from the macOS
   subset and stays Linux-only, with the exclusion list stated in the spec or
   the job's header comment. That job is green."

3. **Release sequencing (open question 1) resolved before `spec:plan`, not
   before implementation.** With 0047 and 0048 unreleased on top of 1.16.0,
   the spec must state explicitly whether 0049 is the release-carrying spec
   (and therefore owns the six-location version bump inside itself, before
   `spec:close`, per the closed-spec-immutability constraint) or whether a
   separate release spec will carry 0047/0048/0049 together. This is a
   decision, not an implementation detail — reword the open question's last
   sentence from "before implementation" to "before `spec:plan`."

### Should-fix

- Uniform stderr diagnostic across every non-zero exit of `arch_set_status`
  and `pm_set_status` (AC2, AC4, AC5, and the implicit malformed-frontmatter
  case), not just the underlying-write-fails case (claude-p).
- AC9's PASSES fixture set must include the exact POSIX reversal form used by
  the AC8 fix, landing in the same commit as AC8 — otherwise the guard could
  reject the very fix that satisfies AC8 if the two land in the wrong order
  (claude-p).
- AC8's fixture must carry both halves — history-chronological entries and
  history-less entries — so a fix that still drops the history-less half (the
  half the original `tac` bug did not touch) cannot go green on an
  ordering-only, history-only fixture (claude-p).
- Pin the `--kind` flag shape (position relative to positionals; whether
  `--kind=X` and `--kind X` are both accepted), and state whether `--kind`
  validates only the enum or also that the supplied artifact's actual kind
  matches (both agents).
- Define the portability guard's matching semantics precisely for `sed
  -i.bak` vs `sed -i`, `sed -i ''`, quoting, comments, continuations, and
  Markdown fences, so it does not false-positive/false-negative on shell
  syntax it wasn't designed to parse (codex).
- Define the `SetStatus` Go API evolution explicitly — signature change,
  sibling operation, or a typed `ArtifactKind` — and pin it with table-driven
  tests on both the Go API and the CLI parsing layer (codex).

### Considered and rejected

- **codex: "AC8's `tac` replacement needs a multiline-entry byte contract."**
  Rejected. `history_parse_entries` (`commands/history/compact.lib.sh:31-38`)
  emits only matching `^## YYYY-MM-DD` header lines into the stream consumed
  at `commands/spec/consolidate.lib.sh:409` — one line per entry, entry bodies
  are never part of the reversed stream. Line-reversal of a one-line-per-entry
  stream is entry-reversal; there is no multiline byte contract at risk. No
  spec edit follows from this concern.

### Verified, no action

- **claude-p: "verify the meta-guard's scan roots exclude `specs/**`."**
  Verified. `tests/hooks/frontmatter-writer-guard.bats:56` scans
  `"$PLUGIN_DIR/commands"` only; nothing scans `specs/`. The archived copy of
  this spec (post-close, under `specs/.archive/`) quoting the forbidden `sed
  -i` line verbatim cannot false-positive the guard. Recommend the spec state
  this invariant explicitly (e.g., alongside item 3 in "What") so a future
  contributor does not widen the scan root and reintroduce the risk claude-p
  flagged.

### Noted for the plan, not the spec

- **AC11 lacks a mechanical CI oracle.** "Reverting any one production fix
  makes at least one Linux test fail" is a coverage-topology claim, not
  something a single bats assertion checks. Claude-p's suggestion: move it to
  an author-facing `tasks.md` checklist item ("before marking done: run
  `scripts/verify-linux-pins.sh` and confirm each of the three reverts fails a
  bats test"), or add that script as a documented, non-CI-gating helper. Does
  not need to change the AC's substance, just how it's operationalized in the
  plan/tasks.
- **claude-p's non-destructive `/speccraft:sync` stray-sibling reporting
  idea.** Reporting (not deleting) `<file>-E` / `<file>-[A-Z]` siblings in
  `.speccraft`-managed directories, with a recovery hint, is a plausible
  follow-up spec. It is explicitly outside 0049's stated scope
  ("Out of scope" bullet 1) and should not be folded into this spec.

**Action:** Revise `spec.md` to fix AC2 (fault-injection seam) and AC10
(macOS toolchain/PATH policy + explicit portable test subset), and resolve
open question 1 (release sequencing) with a decision recorded in the spec
before `spec:plan` runs. Fold in the should-fix items where cheap (stderr
uniformity, AC8/AC9 commit-ordering and fixture coverage, `--kind` shape
pinning) or note them for `tasks.md` if better handled during planning.
Re-run cross-review once AC2, AC10, and open question 1 are resolved.

---

# Round 2 — scoped re-review

Scoped via `speccraft-state review-diff --promote` (branch `scoped`: the prior
`reviewed_sha256` matched the envelope's `base_fingerprint`). Changed sections
assessed: What, Acceptance criteria, Out of scope, Resolved decisions (added),
Open questions.

**Process note:** the machine-generated section diff was consumed by the
one-shot `--promote` transaction before capture (operator error — the command
body specifies a single read/diff/write). The real changed-sections list was
reused; the per-section change description supplied to the reviewers was
reconstructed by hand and labeled as such in the payload, with the frozen spec
attached as the authoritative text.

## Independence check — round 2

All four raw outputs across both rounds are distinct; no false quorum in either
round.

- round 1 `codex` `25dccc39a2fd009b6c79ccabb9bbd58b` (4554 B)
- round 1 `claude-p` `d9b14039b689df5857e22a3717b927f1` (7496 B)
- round 2 `codex` `48ef92accd9972f216eb629d713595fb` (2235 B)
- round 2 `claude-p` `5fa2ae7efec70d0bc53c65d878e6049d` (8197 B)

The two round-2 reviewers returned **disjoint** findings — no overlap at all —
which is itself corroboration that the two generations are independent.

## Verdicts

- `codex`: **changes-requested** — three narrow items. Explicitly confirms both
  round-1 blockers (AC2, AC10) resolved and reports no regression into unchanged
  ACs. Did not re-raise the orchestrator-rejected `tac` concern.
- `claude-p`: **approve-with-comments** — marks all three round-1 must-fix and
  all six should-fix items `resolved`, with a section-by-section regression sweep
  (AC1, AC3, AC5, AC6, AC7, Why, and the former Out-of-scope↔AC10 contradiction)
  finding no regressions. Recommends approval for `spec:plan` with two
  non-blocking hardenings.

## Round-2 findings — all five accepted

From `codex`:

1. **AC2's non-writable-parent oracle is permission-dependent, not a seam.**
   Accepted. Orchestrator-verified as conditional rather than absolute: a
   read-only parent *does* block uid 1000 (tested in this devcontainer, and CI
   runs non-root), so the fixture is not broken — but it is environment-dependent
   and silently degrades to a no-op under root. It is also the wrong layer: the
   shell helper invokes `speccraft-state`, so no Go seam is reachable from bats.
   Resolution: the shell-level test shims `speccraft-state` on `PATH` to a stub
   that exits non-zero with stderr — deterministic and uid-independent — and the
   Go-level write failure is pinned separately at the `atomicRename` seam.
2. **`KindSpec` described as a "zero-ish default" is ambiguous.** Accepted; the
   wording was sloppy. Resolution: `ArtifactKind` has no meaningful zero value.
   `KindSpec ArtifactKind = "spec"` is an explicit non-empty constant, `SetStatus`
   rejects the empty/unknown kind, and the no-flag CLI default maps to `KindSpec`
   at the flag-parsing layer — never inside the Go API.
3. **AC11's helper could clobber uncommitted work.** Accepted, and the sharpest
   of the three: a script that reverts production fixes in the live checkout can
   destroy the author's work, and one revert can contaminate the next.
   Resolution: it operates on a disposable copy, restarts each mutation from the
   same clean baseline, and must leave the caller's checkout byte-identical.

From `claude-p`:

4. **AC10 condition 3 is stated but not mechanically pinned.** Accepted, and
   well-argued: condition 2 (Bash 5) got a runtime assertion precisely because
   "silently the wrong thing" was the anticipated failure, and condition 3 — the
   one the spec itself calls load-bearing — has none. Resolution: a runtime
   assertion that `sed`/`stat`/`date`/`readlink`/`base64`/`tac` resolve outside
   `*/gnubin/*` and `*/coreutils/libexec/*` and that `command -v gsed` fails.
5. **AC9's flag-comments-too rule has no escape hatch.** Accepted, taking the
   simpler of the two offered options: state the cost rather than concede the
   invariant. Documentation under a scanned surface that needs to name a
   forbidden form must be relocated to `.speccraft/` or `specs/` (both outside
   the scan root) or reworded. An `allow-gnu-form` marker would make the guard
   evadable by annotation, which is the property the guard exists to deny.

Two `claude-p` items are recorded as planning detail, not spec changes: the
sweep methodology behind "one file, seven mutations" should be reproducible from
`tasks.md`, and the `SetStatus` call-site migration should be enumerated up
front rather than discovered at build time.

## Status after round 2

Every finding from both rounds is now either applied to `spec.md` or explicitly
recorded as considered-and-rejected with evidence. The verdict in this file's
frontmatter stays `changes-requested` because it records round 2's synthesis,
which preceded those five edits. `spec.md` is deliberately left at
`status: draft`: `claude-p`'s `approve-with-comments` satisfies
`review_quorum = 1`, but flipping to `reviewed` on the orchestrator's own
assessment of its own edits would be self-certification. A round-3 scoped
re-review over the five edits is the clean way to close it.

---

# Round 3 — scoped re-review (converged)

Scoped again via a single `review-diff --promote` envelope. Exactly one section
changed — `Acceptance criteria` — which matches where all five round-2 fixes
landed (AC2, AC4, AC9, AC10, AC11).

## Independence check — all three rounds

Six raw outputs, six distinct md5s. No false quorum in any round.

| Round | codex | claude-p |
|---|---|---|
| 1 | `25dccc39…` (4554 B) | `d9b14039…` (7496 B) |
| 2 | `48ef92ac…` (2235 B) | `5fa2ae7e…` (8197 B) |
| 3 | `e588f60d…` (454 B) | `9cc07b09…` (6381 B) |

## Verdicts

- `codex`: **approve** — `concerns: []`, no regressions, two non-blocking
  suggestions. Converged from `changes-requested` (r1) → `changes-requested`
  (r2) → `approve` (r3).
- `claude-p`: **approve-with-comments** — all five resolutions assessed sound
  individually, explicit pairwise regression sweep (AC1↔AC2, AC4↔AC1, AC7↔AC9,
  AC10↔AC8/AC9) finding no conflicts, no blocking concerns.

**Synthesized verdict: `approve-with-comments`.** Quorum (`review_quorum = 1`)
is met by two independent approve-class verdicts on the *edited* spec — not on
the orchestrator's own assessment of its own edits, which is why round 3 was run
rather than flipping status after round 2. `spec.md` moves to
`status: reviewed`.

One process note: `claude-p`'s free-form text asserted quorum was satisfied and
recommended flipping the status. The delegator correctly flagged that as the aux
agent's opinion rather than an authoritative determination. The quorum decision
recorded here is the orchestrator's, applying `.speccraft/agents.toml`.

## Carried to `tasks.md` — not spec revisions

These are implementation-level and were deliberately NOT folded into `spec.md`,
because editing the spec again would invalidate a clean round-3 approve for no
correctness gain. `/speccraft:spec:plan` should pick them up.

1. **AC10's no-GNU assertion must not run on Linux.** (`claude-p`, sharpest of
   the batch.) If it lands as a bats test in `tests/hooks/`, the Linux `hooks`
   job also loads it — and on Linux `tac` *does* resolve, so the assertion
   inverts and fails. It needs `$RUNNER_OS` scoping, or to run as a workflow
   step ahead of bats rather than as a bats test. Not a spec defect; a real
   implementation trap.
2. **Behavioral GNU detection alongside the path check.** (`codex`.) The
   `*/gnubin/*` path assertion misses a GNU binary exposed through an unusual
   symlink. A version probe is the stronger oracle — GNU `sed` accepts
   `--version`, BSD `sed` does not — and complements rather than replaces the
   path check.
3. **Fingerprint the caller's tree BEFORE creating the worktree.** (`codex`.)
   Otherwise `verify-linux-pins.sh`'s own setup could mutate the checkout
   without the post-run assertion noticing.
4. **Prefer `git worktree add --detach` over a temp clone** for AC11's
   disposable copy. (`claude-p`.) Same isolation, faster, and no risk of
   inheriting an unclean index from the caller.
5. **Decide whether `tools/**/*_test.go` counts as shipped or test-side** for
   AC9's scan root. (`claude-p`.) The `tests/**` exclusion does not cover Go
   test files under `tools/`, which may legitimately carry GNU-form strings as
   fixtures. Pre-existing ambiguity, not a regression from this round — but the
   fixture set should settle it before the first false positive.
6. **Split the AC2 stderr coverage by layer.** (`claude-p`.) The shell helper
   handles "missing file" and "non-draft source" *before* invoking
   `speccraft-state`, so the PATH shim exercises only the remaining three exit
   paths. The task list should separate shell-side pre-check tests from
   binary-side tests so no exit path is silently uncovered.
7. **Enumerate every two-arg `SetStatus` call site up front.** (`claude-p`,
   raised in rounds 2 and 3.) Grep-derivable, but pre-enumeration avoids a
   build-error discovery cycle mid-implementation.
8. **Record the AC10 sweep methodology.** (`claude-p`, round 2.) The "exactly
   one file, seven mutations" claim drove the port-vs-exclude decision; the grep
   pattern and the non-executed-match exclusion list should be reproducible from
   `tasks.md`.
reviewed_sha256: 1f1220874e332f88f43fd999092babf645dc49aa26d474770d97d2757f67f9a9
