---
id: "0036"
title: "revision-counter & artifact-numbering contract"
status: closed
created: 2026-07-26
authors: [claude]
packages: ["tools/internal/speccraft", "tools/cmd/speccraft-state", "commands/spec"]
related-specs: ["0015", "0018", "0035"]
---

# Spec 0036 — revision-counter & artifact-numbering contract

## Why

Field feedback (installed-plugin session, macOS/zsh) surfaced that speccraft has
**two uncoordinated numbering systems** and no single sanctioned frontmatter
writer:

1. **Dual numbering with no reconciliation.** The frontmatter `revision: N`
   counter (spec 0015) and the archived-artifact files `*-r<N>.md`
   (`review-rN.md`, `plan-rN.md`, `tasks-rN.md`) can drift apart. When they do,
   `preflight_archive_collisions`
   ([revise.lib.sh:147](commands/spec/revise.lib.sh#L147)) **hard-refuses**
   ("archive target … already exists; refusing to overwrite") and nothing ever
   advances `N` past the occupied slot — a **deadlock**. A single stray or
   out-of-band `review-r<N>.md` permanently blocks `/speccraft:spec:revise`.

2. **Within-draft edits are invisible to the counter.** A draft that receives
   `changes-requested` and is edited in place (the normal review→edit→re-review
   loop) never invokes `bump_revision`, so the frontmatter counter and the prose
   "rev N" narrative silently diverge. There is no declared authority that says
   which number is real.

3. **Hand-rolled frontmatter edits corrupt fields.** `bump_revision`
   ([revise.lib.sh](commands/spec/revise.lib.sh), ~L513) flips `status:` and
   increments `revision:` with `sed -i.bak -E 's/^status:…/…/'`. In the field a
   hand-rolled status flip **ate a newline** in the frontmatter. There is no
   single sanctioned, byte-safe frontmatter writer analogous to how
   `speccraft-state` is the sole writer of `state.json`. (Line numbers here are
   secondary anchors; the function names are authoritative.)

This spec defines one authoritative **revision-and-artifact-numbering contract**
and a single sanctioned, byte-safe frontmatter-field writer, making the revise
path self-healing instead of deadlock-prone.

## Authority model (read this first)

The frontmatter `revision: N` counter is the **canonical revision exposed to
users and the sole authority in steady state.** On-disk archived artifacts
(`*-r<N>.md`) are **reconciliation evidence**, never a peer authority: they can
only heal the counter **forward** (raise a lagged counter), never move it
backward and never override a counter that already leads. "Disk is truth" means
only that a counter which has fallen *behind* provable on-disk history is
repaired up to that history — it is a self-heal fallback, not dual authority.

Concretely, define for a spec dir:

- `fmRev` = the `revision:` frontmatter value (see AC7 parsing rule; absent or
  malformed ⇒ `0`).
- `maxArchived` = the greatest `N` over all existing
  `spec-r<N>.md` / `review-r<N>.md` / `plan-r<N>.md` / `tasks-r<N>.md` files
  (non-numeric `-r<x>.md` suffixes ignored); `hasArchived` = whether any exists.
  `spec-r<N>.md` is scanned only defensively for out-of-band files — **this
  contract never archives `spec.md` itself** (see §What/B); the live `spec.md`
  is always the current spec and is only ever counter-bumped in place.
- An archived ordinal `N` means "the artifacts *at* revision N were superseded",
  so the live spec must have advanced strictly past N. Hence the **invariant**:
  the live `revision:` is strictly greater than `maxArchived` whenever
  `hasArchived`.
- **Effective (canonical, reconciled) revision:**
  `Effective = hasArchived ? max(fmRev, maxArchived + 1) : fmRev`.
  This is `≥ fmRev` and, by construction, strictly greater than every archived
  ordinal — the invariant holds by definition, and `spec-r<Effective>.md` /
  `review-r<Effective>.md` / … are guaranteed free.

## What

Establish the contract in four coordinated pieces:

**A. Single revision authority (self-healing forward).** One Go core computes the
reconciled state from disk + frontmatter: `ComputeRevisionState(specDir)` returns
`RevisionState{FrontmatterRevision, MaxArchived, HasArchived, Effective}` with
`Effective` as defined above. `speccraft-state effective-revision <specDir>`
surfaces `Effective` as data. The counter never silently lags disk: any operation
can reconcile it forward, and `Effective` always reflects on-disk reality.

**B. Collision-free (self-healing) archiving.** Archiving uses ordinal
`A = Effective` (provably free) and archives each present **disposable** live
artifact — `review.md`, and for `planned` source also `plan.md` / `tasks.md`
(exactly the set spec 0015's `archive_rename` moves) — to `*-r<A>.md` with
**no-clobber** rename semantics, where `A = Effective` computed **before** the
moves. `spec.md` is NOT archived: it stays the live file and its counter is then
set to **`Effective` recomputed AFTER the moves** via the sanctioned writer
(`SetRevision`) — equivalently, the counter write IS `reconcile-revision` run after
archiving. In a fresh archive that post-value is `A + 1`; on a retry where the
artifact was already moved and none remain it is the healed `Effective` — so a
retry can never mint a spurious extra revision (see AC5). A pre-existing
`review-r<N>.md` can no longer deadlock revise: the archive lands in a free slot and
the counter advances past it. The old fail-closed `preflight_archive_collisions`
refusal is replaced by this always-progresses selection (retained only as a
post-condition no-clobber assertion at write time).

The three mutations happen in a fixed, interruption-safe **order: (1) archive the
disposable artifacts, (2) write the counter (`SetRevision` to post-archive
`Effective`), (3) flip `status` to `draft` LAST.** Because the status flip is the
final, idempotent resting mutation, any failure before it leaves the source status
(`reviewed`/`planned`) intact, so `/speccraft:spec:revise`'s normal status gate
still admits the retry; a failure after it leaves `status: draft`, a valid resting
state with steps 1–2 already done.

This contract assumes the established **single-writer** model: no concurrent
sanctioned frontmatter mutation on the same spec dir — not just `revise`, but also
`set-status` / `set-revision` / `reconcile-revision` / `close` — the same
single-session assumption speccraft already relies on for `state.json`. Atomic
whole-file replacement (the `AtomicWriteFile` seam) prevents torn files; true
lost-update / compare-and-swap protection under genuine concurrency is out of scope
(as it is for `state.json`). No-clobber renames are the backstop regardless: each
archival move uses a **genuine no-replace primitive** — `link(2)`-into-place (which
fails atomically with `EEXIST` if the target exists) followed by unlinking the
source — never a stat-then-rename (which has a check-to-rename TOCTOU and is NOT
race-safe); on a filesystem/platform where atomic no-replace is unavailable the
archive fails safe with an error rather than risk an overwrite. The move is
**idempotent by inode identity** (AC15): if `link(2)` succeeds but the subsequent
source `unlink` fails, a retry — BEFORE allocating any new ordinal — scans the
same-kind archived siblings (`review-r*.md` for a `review.md`, etc.) and, if one is
the **same inode** as the still-present live artifact (`os.SameFile`, proving an
incomplete hard-link move — byte-equality is deliberately NOT used, since unrelated
revisions can share bytes), completes the interrupted move by unlinking the source
rather than creating a second archive. If inode identity cannot be established it
fails safe rather than delete the source.

The archive path is **only invoked while `status` is non-closed** (it runs inside
`/speccraft:spec:revise`, which gates on a non-closed status), so the closed-spec
writer refusal (AC9) can never deadlock the final counter write. And that counter
write is **always performed** as the last step — even on a retry where every
disposable artifact was already moved and none remain to rename — because it heals
the live counter forward to `Effective` (AC5) idempotently; there is no state in
which artifacts are archived but the counter is left behind.

Because a mid-sequence failure can leave part of the disposable set moved at
ordinal `A` while a re-run computes a fresh `A' > A` for the rest, **archived
ordinals are per-file supersession evidence, not a guaranteed-coherent
point-in-time snapshot of the whole spec**: a crash-scattered set is tolerated, and
correctness is preserved because `Effective` is driven by `maxArchived` and
therefore stays monotonic regardless of scatter. (No mixed-ordinal "warning" is
emitted: a `review-r7.md` beside a `plan-r9.md` is observationally identical to two
ordinary successful cycles in which different disposable artifacts were present, so
without transaction metadata such a note cannot distinguish crash-scatter from
normal history and would fire during routine operation — it is therefore omitted.)
True all-or-nothing multi-artifact archiving is out of scope.

**C. Single sanctioned byte-safe frontmatter writer.** An **unexported** low-level
byte writer `setFrontmatterField(specMd, key, value)` (built on the spec-0035
`AtomicWriteFile` seam) rewrites exactly the one matching frontmatter line,
preserving every other byte — field order, body, per-line terminators, BOM, EOF
newline (AC6) — and never emitting a `.bak` sibling. It is NOT exported, so no
foreign caller can drive an arbitrary field write that bypasses the policy checks.
The only **exported** mutation ops are `SetStatus(specMd, status)` and
`SetRevision(specMd, n uint64)`, which enforce the boundary rules — status
validation (AC8), numeric domain (AC14), and closed-spec immutability (AC9) — before
delegating to the low-level writer. They back the subcommands
`speccraft-state set-status <spec.md> <status>` and
`speccraft-state set-revision <spec.md> <N>`, the ONLY sanctioned paths for mutating
`status:` / `revision:`. `bump_revision` routes BOTH its counter update and its
status flip through them; the AC10 meta-guard forbids raw in-place edits of either
field in command libs.

`SetRevision` is **monotonic-forward**: it refuses (non-zero, mutating nothing) any
`N` strictly less than the current `revision:` value, so neither a future Go caller
nor a direct `set-revision` CLI use can demote the counter below where it stands and
re-introduce a value under archived history. This is not merely policy — the
forward-only invariant is enforced *in the exported writer itself*. The two
legitimate callers never need to demote: the archive path writes post-archive
`Effective` (always ≥ the prior counter) and `reconcile-revision` heals upward only.

The three CLI ops split their argument surface by role: `effective-revision` and
`reconcile-revision` take a `<specDir>` (they read/heal against archived siblings),
while `set-status` and `set-revision` take a single `<spec.md>` (they mutate exactly
one file) — coherent, but called out here because the directory-vs-file asymmetry is
non-obvious.

**D. Writer-boundary immutability.** A spec whose current status is `closed` is
immutable: `set-status` and `set-revision` **unconditionally refuse** to mutate it
(no `--force` escape hatch — that would weaken one of the three hard guardrails;
corrections to a closed spec go in a follow-up spec, per `guardrails.md`). This
enforces the closed-spec-immutability guardrail at the writer boundary as well as
at code-review time. The close *transition* is unaffected: `/speccraft:spec:close`
sets `status: closed` via `SetStatus` while the current status is still non-closed,
so that write is permitted; only mutating an already-closed spec is refused. (The
`close.md` call site invokes `set-status` for that transition, so "the close
transition is unaffected" is verifiable at the call site, not only at the writer.)

The frontmatter `revision:` counter is the sole authority for a spec's revision
number; prose "rev N" narrative is descriptive only. **In-place draft edits
intentionally retain the same revision** — a revision corresponds to a completed
review cycle (an archive), not to every keystroke — so the review→edit→re-review
loop within one draft cycle does not advance the counter, which resolves the
"invisible within-draft edits" ambiguity by *defining* the semantics rather than
tracking edits. The counter advances only through the archive path (§B).
`speccraft-state reconcile-revision` (AC5) is a **heal-only** operation: it raises
a counter that has fallen *behind* provable on-disk archives up to `Effective`; it
is never a milestone-advance and is a no-op when the counter already leads.

## Acceptance criteria

1. **Reconciled-state core.** `ComputeRevisionState(specDir)` (new, in
   `tools/internal/speccraft`) returns
   `RevisionState{FrontmatterRevision, MaxArchived, HasArchived, Effective}` with
   the four values computed per the Authority model. `Effective` equals `fmRev`
   when no archives exist and `max(fmRev, maxArchived+1)` when they do. It errors
   when `<specDir>` is missing or not a directory, and when `<specDir>/spec.md` is
   unreadable — these are distinguished from a missing/malformed `revision:` line,
   AND from a spec.md that has **no frontmatter block at all**: both of the latter
   are NOT errors and yield `FrontmatterRevision == 0` while `maxArchived` is still
   computed from disk (the reader degrades gracefully; only the *writer* errors on
   a missing frontmatter block, AC7). Because a typo'd specDir is a
   missing-directory *error* (not a `0`), it can never be confused with a real spec
   that genuinely computes `Effective == 0`. The archived-ordinal scan is factored
   into one named helper (`listArchivedOrdinals(specDir)`) that both
   `ComputeRevisionState` and the archive path use, so on-disk layout has a single
   source of truth. A pathological on-disk state (`review-r5.md` beside
   `revision: 3`) yields `Effective == 6`, pinned by a Go unit test with that exact
   fixture shape. **Revision-value classification is an explicit matrix** (absent ⇒
   0; syntactically non-numeric ⇒ 0; a numeric literal exceeding the AC14 domain ⇒
   error, held distinct from malformed): `ComputeRevisionState` reads absent /
   non-numeric as `0` but errors on an over-domain literal; `SetRevision` errors on
   negative, non-integer, over-domain (AC14), and demotion (§C); `effective-revision`
   / `reconcile-revision` propagate that error.

2. **Effective-revision subcommand.** `speccraft-state effective-revision
   <specDir>` prints `Effective` alone on stdout and exits 0; it exits non-zero
   with a stderr message when `<specDir>/spec.md` is unreadable.

3. **Self-healing archive ordinal.** The archive path uses `A = Effective` and,
   for a spec dir where `review-r<N>.md` already exists at `revision: N`, `A` is
   strictly greater than `N`, and none of `review-rA.md` / `plan-rA.md` /
   `tasks-rA.md` exists (self-heals past the collision). `spec.md` is not among
   the archived artifacts.

4. **Revise no longer deadlocks; archiving is no-clobber.** With a spec at
   `revision: N`, source status `reviewed`, and a pre-existing `review-r<N>.md`,
   the revise archive path completes successfully — archiving live `review.md` to
   the free `review-r<A>.md` (A > N) and leaving `spec.md` live — instead of the
   current hard refusal. Each archival rename refuses to overwrite an existing
   target via a genuine no-replace primitive — `link(2)`-then-unlink, failing safe
   where atomic no-replace is unavailable, never a racy stat-then-rename (§B). The
   final counter write is always performed even on a retry where no disposable
   artifacts remain to move (§B), so there is no archived-but-counter-behind state;
   this recovery case has a named fault-injection test (fail after the last rename,
   before the counter write; re-run heals the counter to `Effective`). Under the
   single-writer assumption (§B) forward progress is guaranteed; a mid-sequence
   failure leaves already-moved files in place and a re-run recomputes a fresh free
   ordinal rather than overwriting anything, so **a partly-archived set can carry
   mixed ordinals** (per-file supersession evidence, not a coherent whole-spec
   snapshot) — an explicitly accepted consequence (no warning is emitted, §B). The
   old `preflight_archive_collisions` function ([revise.lib.sh:147](commands/spec/revise.lib.sh#L147))
   is **deleted** — its hard-refusal is obsolete under self-healing — and the
   existing bats cases that pin its refusal are removed/replaced by the deadlock
   regression here. The deadlock regression is pinned in **bats sourcing
   `revise.lib.sh`** (per the spec-0015 pairing rule), not the credit-gated e2e; the
   ordinal/state math is pinned by Go unit tests.

5. **Counter advance + reconcile (one unified rule, idempotent).** After the
   archival moves, the live `revision:` is set to **`Effective` recomputed from disk
   AFTER the moves**, written via `SetRevision` — the counter write IS
   `reconcile-revision` run post-archive. This single rule removes any `A+1`-vs-heal
   ambiguity: in a **fresh** archive (moved `review.md`→`review-r5`, `fmRev` was 5)
   post-`Effective` is `6` (= `A+1`); in a **retry** where the artifact was already
   moved and none remain, post-`Effective` is still `6` — the counter heals to `6`,
   never to a spurious `7`. `speccraft-state reconcile-revision <specDir>` is
   **heal-only**: it sets the counter to `Effective`, a no-op when `fmRev` already
   equals `Effective` (which, since `Effective ≥ fmRev`, is exactly when the counter
   already leads). The no-op is a *skip-write* (short-circuit before touching disk:
   no mtime churn, and a CRLF file already at target is untouched), and reconcile is
   idempotent — running it twice yields a file byte-identical to running it once.
   Both the fresh (`→6`) and retry (`→6`, not `7`) branches are pinned by tests.

6. **Byte-safe writer.** `setFrontmatterField` (and thus `SetStatus` /
   `SetRevision`) rewrites exactly the **first** matching frontmatter line
   (later duplicate lines for the same key are left byte-identical, consistent with
   the first-wins reader in AC7) and preserves every other byte: field order, body,
   any leading UTF-8 BOM, and **each line's own terminator** — the rewritten line
   keeps whatever terminator it had (LF or CRLF), and a mixed-EOL file (LF
   frontmatter, CRLF body, or vice versa) round-trips byte-for-byte; the
   implementation must not normalize to a single "dominant" style. The EOF newline
   (present or absent) is preserved. It writes no `.bak` sibling. Setting a field
   to its current value is a skip-write no-op yielding a byte-identical file.

7. **Field parsing + insertion + error rules.** The `revision:`/`status:` value is
   the first `^<key>:` line inside the frontmatter block only (occurrences in the
   body are ignored); duplicate frontmatter lines for the key ⇒ first wins, and the
   writer rewrites that same first line (AC6) so reader and writer never disagree.
   `revision:` parses as a non-negative base-10 integer — malformed/absent ⇒ `0`
   for computation; `set-revision` rejects a negative or non-integer argument
   non-zero, mutating nothing. When the key line is absent from the frontmatter,
   the writer inserts it as the last line before the closing `---` (preserving
   existing key order), and the **inserted line's terminator is deterministic**: it
   inherits the terminator of the line immediately above the closing `---`, falling
   back to the closing `---` line's own terminator for the degenerate empty-block
   case (`---\n---`). An LF-frontmatter file and a CRLF-frontmatter file, both
   missing `revision:`, each round-trip byte-for-byte through insertion — pinned by
   a fixture pair. A file with no frontmatter block at all is an error (the writer
   does not fabricate frontmatter), not a silent body edit.

8. **Status validation.** `set-status` accepts only
   `draft|reviewed|planned|in-progress|blocked|closed` and exits non-zero with a
   stderr message on any other value, mutating nothing.

9. **Writer-boundary closed-spec immutability, enforced in the exported op.** The
   closed-spec refusal lives in `SetStatus` / `SetRevision` themselves (the exported
   boundary), NOT only in the CLI arg-parsing — since the low-level writer is
   unexported (§C), no Go caller can reach an arbitrary field write that skips it.
   Both **unconditionally refuse** to mutate a spec whose current `status:` is
   `closed`, exiting/returning non-zero with a message and mutating nothing — there
   is no `--force` escape hatch (closed-spec corrections go in a follow-up spec, per
   `guardrails.md`). The close transition is unaffected (setting a non-closed spec
   to `closed` is permitted). A regression test pins the refusal on an
   already-closed spec, that a non-closed spec still writes, AND that the enforcement
   sits in the exported op (a direct `SetRevision` call on a closed spec is refused).
   A malformed or absent current `status:` line reads as "not closed" (AC1
   leniency), so the guard neither spuriously refuses a normal mutation nor is
   silently disabled — the refusal fires only on a well-formed `status: closed`.

10. **Regression meta-guard for raw frontmatter rewrites.** `bump_revision`
    ([revise.lib.sh](commands/spec/revise.lib.sh)) is retained as a thin helper
    that performs BOTH its `revision:` increment and its `status:` flip by calling
    `set-revision` / `set-status`, using NO raw in-place rewrite itself (so it does
    not trip the guard below). A mechanical meta-guard test fails if any
    `commands/**/*.lib.sh` or `commands/**/*.md` performs an in-place rewrite
    (`sed -i`, `perl -i` **and** `perl -pi -e`, `awk … > <file>`) whose script text
    contains a `status:` or `revision:` left-hand side in ANY form (anchored
    `^status:` or unanchored `status: draft` alike) and whose target resolves to a
    `specs/*/spec.md`-shaped path. The **matching regime is pinned concretely and
    per-tool**: for `sed -i` / `perl -i` / `perl -pi -e` the target is the last
    positional (non-flag) argument; for `awk` the target is its **output-redirection
    target** (`awk … > FILE`), not a positional argument. Either target is taken as
    literal text and matched against `specs/*/spec.md`; a variable or
    command-substituted target (e.g. `sed -i "$SPEC_MD"`) whose value is not a
    trivially-resolvable literal is **conservatively scoped IN** (treated as a
    spec.md target and thus flagged), never silently skipped. This guard is scoped
    honestly: it is a **regression guard against the enumerated raw
    in-place-rewrite forms of these two fields in command libs**, NOT a proof that
    no other mechanism (a general editor, an alias, an indirect path) can write —
    "sole sanctioned writer" is an architectural policy enforced by convention plus
    this guard, not a total runtime boundary. The guard lives at
    `tests/hooks/frontmatter-writer-guard.bats` with a curated fixture of BOTH
    forbidden forms and permitted forms (read-only `sed -n '/^status:/p'`,
    `grep -E '^status:'` as `preflight_status_gate` uses, YAML *reading*, printing
    status to stderr, redirection unrelated to those fields) so it neither
    false-positives nor no-ops — in the spirit of the spec-0030 grep-oracle.

11. **Version bump with release DoD.** The plugin version bumps `1.10.0 → 1.11.0`
    across the three `const version` binaries (`speccraft-state`,
    `speccraft-guard`, `speccraft-drift`) and both manifests
    (`.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`), each pinned
    by its renamed sibling version test / manifest grep oracle. Per
    `conventions.md`, the definition-of-done for the bump is a **published,
    verified release** — the merge-time auto-tag → `release.yml` →
    `verify-release.sh` chain producing four platform tarballs + `checksums.txt`
    for `v1.11.0` — not merely editing the manifests.

12. **Override budget with explicit T1 shape.** The implementation costs at most
    ONE recorded `/speccraft:spec:override` (the spec-0018-AC13
    new-exported-symbol bootstrap). T1 is a SINGLE edit that adds the new EXPORTED
    symbols — the `RevisionState` type, `ComputeRevisionState`, and the two writer
    ops `SetStatus` / `SetRevision` (the low-level `setFrontmatterField` is
    unexported, so it needs no bootstrap of its own) — as stubs paired with their
    first RED tests, under that one override; every later core addition rides the
    existing symbols. The new `speccraft-state` subcommands are added via the
    spec-0035 `run()` seam (they fail at runtime with "unknown subcommand" until
    wired, compiling meanwhile) and need no cmd-layer override.

13. **One shared frontmatter grammar with a named entrypoint.** A single byte-level
    grammar, implemented in ONE named Go entrypoint (`parseFrontmatterBlock`, in its
    own file), drives the reader (`ComputeRevisionState`, the closed-status check)
    AND the writer (`setFrontmatterField`) — both route through it, so the field a
    check reads and the line a write rewrites can never disagree, and a second
    parser cannot be added unnoticed (a test asserts both paths call it). The frontmatter block is delimited by the first
    line equal to `---` (after an optional leading UTF-8 BOM, which is preserved)
    and the next line equal to `---`; only lines strictly inside that block are
    considered. A key line matches `^<key>:` at column 0 (no leading whitespace);
    a `# status:`-style comment or a body occurrence does not match. Trailing CR on
    the delimiter/key line is tolerated (mixed-EOL, AC6). Insertion (AC7, absent
    key) targets the line immediately before the closing `---`, including the
    degenerate empty-block case (`---\n---`); a file with no closing `---` is the
    "no frontmatter block" error of AC7.

14. **Explicit numeric domain.** Revision values use one explicit integer domain
    (`uint64`) with checked addition: a `maxArchived + 1` or `A + 1` that would
    overflow, and a `set-revision <N>` argument or on-disk `revision:` value that
    exceeds the domain, are non-mutating errors with a stderr message — never a
    silent wrap. A table-driven test pins parse-overflow and increment-overflow.

15. **Interrupted-move recovery by inode identity.** The archive move is idempotent
    across a `link`-succeeded/`unlink`-failed interruption (§B): a retry, before
    allocating any new ordinal, scans the same-kind archived siblings for the live
    artifact's kind (`review-r*.md` for `review.md`, etc.) and, only if one is the
    **same inode** as the still-present live artifact (`os.SameFile`), completes the
    interrupted move by unlinking the source — it does NOT allocate a fresh ordinal
    and does NOT rely on byte-equality (unrelated revisions can share bytes). If no
    same-inode sibling is found the retry proceeds as a normal fresh archive; if
    inode identity cannot be established (unsupported platform) it fails safe rather
    than delete the source. A named fault-injection test pins this exact recovery
    (link succeeds, unlink fails, re-run leaves exactly one archived copy and no
    duplicate ordinal).

## Out of scope

- Auto-rewriting or auto-tracking human prose "rev N" narrative to match the
  counter, or auto-bumping the counter on every in-place draft edit (within-draft
  edits keep the same revision by design; the counter advances only via the
  archive path, and `reconcile-revision` is heal-only). Detecting prose/counter
  divergence is not in this spec.
- Changing the archived-artifact naming scheme (`*-r<N>.md` is retained).
- Retroactively renumbering or de-duplicating existing archived artifacts.
- True cross-file transactional (all-or-nothing) multi-artifact archiving; the
  contract guarantees no-clobber + forward-progress-on-retry, not a rollback of
  already-moved files on mid-sequence failure.
- Any change to `state.json`'s single-writer discipline (`speccraft-state` only).

## Open questions

_none_
