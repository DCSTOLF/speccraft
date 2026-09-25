---
id: "0048"
title: "Guard wedge and red-candidate clobber"
status: in-progress
created: 2026-08-07
authors: [claude]
packages: ["tools/cmd/speccraft-guard", "tools/internal/speccraft", "commands/spec"]
related-specs: ["0018", "0031", "0032", "0047"]
started_at_sha: "9f7329d7cdb22bda17d6dc7433e0fefe8ce965cc"
---

# Spec 0048 — Guard wedge and red-candidate clobber

## Why

Two defects in `speccraft-guard` surfaced while implementing spec 0047. Both are in
the Go/Python/JS-TS red-check path introduced by spec 0018; both make the guard block
edits it has no business blocking; and both already have named workarounds recorded in
`.speccraft/conventions.md`, which is the tell that they are product defects and not
user error.

### Defect A — a broken build makes the guard forbid its own repair

`siblingRedCheck` (`tools/cmd/speccraft-guard/main.go:513-582`) runs the resolved
language adapter once per just-added test id. At `main.go:561-566` an adapter result of
`runner.OutcomeBuildFailed` returns an error, which blocks the edit:

```
red-check: build/collection failed (not a valid RED state):
%s

Fix the build error so the just-added test can run and fail.
```

This is spec 0018's "a build failure is not a valid RED" rule, and the rule itself is
right. The failure is in its blast radius. When the build break is **in the production
code**, *every* subsequent production edit in that package hits `OutcomeBuildFailed`
— including the edit that repairs the break. The tree is unbuildable and the guard
forbids making it buildable. The only exit is `/speccraft:spec:override`.

This is not hypothetical. Spec 0047 stated an override budget of **0** and spent
**5**, all on one self-inflicted forward-reference build break (a call to
`runPredicates` written before the function existed) that took five sequential repair
edits to resolve.

The pressure this defect creates is already visible in the conventions file, as
avoidance advice rather than as a fix:

- `.speccraft/conventions.md:89-110` — *"Avoid a NEW import to dodge the
  import-then-use guard deadlock"*: adding an import is a build-failing edit until the
  using code lands, so authors are told to hand-roll `revErr`/`isAllDigits` instead of
  importing `fmt`/`strconv`.
- `.speccraft/conventions.md:112-134` — *"Budget discipline"*: concentrate all
  from-scratch exported-symbol bootstrapping into ONE override edit, because each
  such edit is a guaranteed build break.

**The language asymmetry is load-bearing.** Rust does not have this problem in the
same shape: `rustDispatch` calls `runner.RunPreEditGate` at `main.go:224`
(`tools/internal/speccraft/runner/gate.go:33`), a fingerprint-cached `cargo check
--tests` that compile-checks **before** the edit is evaluated. Go, Python and JS/TS
have no pre-edit gate at all; they discover a broken tree only through the adapter,
at `main.go:561`, at which point the only available verb is "block".

### Defect B — the guard clobbers its own `red_candidates`

`captureRedCandidates` (`main.go:369-385`) computes `added = postIDs − preIDs`, where
`preIDs` comes from the touched file's **current disk content**. It then calls
`speccraft.SetRedCandidates` (`tools/internal/speccraft/state.go:335-356`), whose doc
comment at `state.go:332-334` states the semantics plainly: it records the ids
*"overwriting any prior entry for that file."*

So any edit to a test file that adds no new test identifier — adding an import, fixing
an assertion, editing a test body, adding a comment — yields `added = []` and
**overwrites** that file's previously registered candidates with the empty set.
`siblingRedCheck` then finds an empty just-added set at `main.go:529-536` and blocks a
production edit that is backed by a genuinely failing test on disk.

The known workaround is a documented convention rather than a fix
(`.speccraft/conventions.md:64-87`): order your edits so the last touch to the test
file adds or **renames** a test, purely so the `func Test…` line counts as newly added.
The same recurrence is logged in `.speccraft/history.md` for spec 0038.

Both defects share a root cause: the guard reasons about a single edit against the
current disk state, when the invariant it enforces is about the **session**.

## What

Two independent fixes to `speccraft-guard`, plus the session state they need and the
one surface that consumes it.

### A. Bounded build-repair mode, gated by a post-edit build probe (Go only)

#### A.1 The probe

When `siblingRedCheck` receives `runner.OutcomeBuildFailed`, the guard applies the
**proposed** edit in memory via the existing `applyEdit` (`main.go:406-434`, which
already models Edit / Write / MultiEdit / NotebookEdit per specs 0031 and 0032) and
builds that content against a **scratch overlay**, using Go's native
`go build -overlay <json>`: a JSON file mapping the real file path to a temp file
holding the post-edit content. No file inside the repository is written, moved, or
truncated.

Pinned invocation parameters — all three were open questions in the prior draft and are
now settled, because AC1/AC2/AC3/AC5 have no oracle without them:

- **Package pattern: `./...`, rooted at the module containing the edited file.**
  Building only the edited file's package answers the wrong question — a break can
  surface only in a dependent package, and a narrow build would then report a false
  "clean" and allow the edit with no `build-repair` record at all. Correctness beats
  latency here; the probe only ever runs on an already-broken tree.
- **`GOCACHE` is pinned to a fixed directory outside the repository root**
  (`<os.TempDir()>/speccraft-build-probe-cache`). Fixed, not per-invocation: a fresh
  cache per probe would force a cold build every time. This is also what makes AC6's
  no-mutation guarantee achievable.
- **Deadline: its own constant, 30s, overridable by `SPECCRAFT_BUILD_PROBE_TIMEOUT`**
  (Go duration; unset / empty / invalid / zero / negative → default), following the
  `SPECCRAFT_TASKS_VERIFY_TIMEOUT` precedent of spec 0047. It does **not** share
  `redCheckTimeout` (`main.go:74`): a shared budget already consumed by a slow adapter
  would leave the probe milliseconds, time out, and rebuild the very wedge this spec
  removes.

**An error-count heuristic is explicitly rejected.** An earlier sketch allowed the edit
when the compiler's error count strictly dropped. That rule is unsound: in Go,
repairing one error routinely reveals several that were previously masked, so a genuine
repair can *raise* the count. It must not be implemented.

#### A.2 Repair mode is bounded and self-closing

The prior draft allowed the edit unconditionally whenever the overlay stayed broken.
Both reviewers independently rejected that, and they were right: it disarms the guard
for the remainder of the session, admitting any Go production edit — related to the
repair or not — with no observed RED and no override. That is a bypass of the
`.speccraft/guardrails.md` red→green rule, not a narrowing of it.

The allowance is therefore bounded by the **mode**, not by guessing which edit is a
"repair". Deciding relatedness by blaming files named in compiler diagnostics was
considered and rejected: a break in file A is routinely repaired in file B.

- **Enter.** The first `OutcomeBuildFailed` of a session records a build-repair
  attestation: the entry timestamp and a `sha256` over the **raw** pre-edit error bytes
  (no normalization — see below). Repair mode is now active.
- **Admit, against a session-wide budget.** While active, an edit may be admitted on the
  still-broken branch only while the session's build-repair log holds fewer than
  `buildRepairMaxEdits` = **10** entries. Each admission is recorded **atomically
  before** the allowance is returned; if the record cannot be durably written, the edit
  is **blocked** (an exception that is not auditable is not an exception, it is a hole).
- **Exit.** The first probe that builds clean clears the attestation and ends repair
  mode. The ordinary red-check re-arms immediately, so the next production edit again
  requires an observed RED.
- **Exhaustion.** Once the log reaches 10 entries, the guard blocks and names
  `/speccraft:spec:override` as the remaining path.

**The ceiling is per session, not per episode, and a clean probe does not refund it.**
Ending repair mode clears the *attestation*; it does not shrink the log. A later break
starts a fresh attestation but continues to draw down the same 10. Otherwise the
allowance is unbounded in aggregate — break, spend the budget, repair, break again,
repeat — which is the same hole in slower motion. Only `ResetSession` resets the count.

**What this does and does not claim.** It would be false to say feature work cannot pass
through repair mode: relatedness is deliberately not inferred (§A.2 rejects blaming
files named in diagnostics, because a break in A is routinely repaired in B), so an
unrelated edit *is* admitted — AC6 pins exactly that. Nor does reaching a clean build
retroactively establish that the admitted edits participated in a red→green cycle. The
claim is narrower and is the whole of the argument: **at most 10 such edits can exist in
a session, every one is recorded before it is allowed, and the log is surfaced at
close.** That is a bounded, audited allowance, not an open door.

**The fingerprint is audit metadata and gates nothing.** It is not compared against
later failures and does not constrain which break is being repaired; recording it lets a
reader of the log tell one break from another. It is a `sha256` over the raw error bytes
precisely so there is no undefined "normalization" contract to get wrong. If a future
spec wants fingerprint continuity to bound repair mode, it must define that comparison
then.

#### A.3 Fail-closed everywhere else

- **Unsupported languages.** The prober resolves through a seam named
  **`deps.proberForLang(lang string) (BuildProber, bool)`**, shaped like the existing
  `deps.runnerForLang` (`main.go:66`). **Go is the only language with a prober.**
  Python, JS/TS and Rust resolve `ok == false` and fall back to today's behaviour. This
  is Go-only **by mechanism, not merely by scope**: `go build -overlay` has no direct
  analogue elsewhere, so each follow-up must supply its own (Python: `compileall` or an
  import probe; TS: `tsc --noEmit`; Rust: `cargo check` — and Rust already has
  `RunPreEditGate`).
- **Probe infrastructure failure.** If a prober is resolved but cannot complete — the
  overlay temp file or JSON cannot be written, the toolchain is absent, the deadline
  expires — the edit is **blocked**, naming both the original build error and the probe
  failure. Otherwise an arranged-broken probe is itself a bypass.
- **Blast radius.** `OutcomeBuildFailed` at `main.go:561` is the **only** entry point.
  The prober must not be constructed, resolved, or invoked on any other path, and no
  error text, control flow, or state write on the ordinary red-check path may change.

#### A.4 The records have a consumer

`/speccraft:spec:close` reports the session's build-repair log alongside the spec-0047
`tasks-verify` gate. Without a consumer this spec would ship state that nothing reads;
with one, an allowed-while-broken edit is visible at close rather than write-only. The
report is informational — it does not gate the close.

#### A.5 This is a guardrail amendment, and it says so

`.speccraft/guardrails.md` currently reads that the red→green invariant is never
bypassed except via `/speccraft:spec:override` with a recorded reason. Repair mode is a
**second** allowance class. Pretending otherwise — arguing that an unobservable signal
is not really a bypass — is how a guardrail erodes without anyone deciding to erode it.

So this spec amends the guardrail explicitly rather than quietly widening it. The rule
becomes: bypasses are `/speccraft:spec:override`, **or** bounded build-repair mode,
which is capped at 10 edits per session, records every admission before granting it,
ends at the first clean build, and is reported at close. A future reader must be able to
find the exception written down next to the rule, with its bound attached. If that
carve-out is not acceptable as policy, this spec is not acceptable either, and the
right outcome is to reject it here rather than discover the widening later in code.

**`.speccraft/conventions.md` is amended in the same pass.** Its existing entry states
that `OutcomeBuildFailed` is not a valid RED, that the known build-failure limitation is
handled by `/speccraft:spec:override`, and that the rule must not be relaxed. After this
spec that text is simply false, and a stale prohibition sitting next to a sanctioned
exception is worse than either alone — the next author has to guess which one is live.
Both files are amended together or neither is.

### B. Per-file session baseline for red candidates

On the **first** touch of a test file within a session, snapshot that file's **pre-edit**
test identifiers as a per-file baseline. On every touch, including the first, candidates
are `postIDs − baseline[file]` rather than `postIDs − preIDs`.

Correct by construction: a later edit that adds no test still reports every test added
since the session began, and genuinely deleting a test correctly shrinks the set.

- **One atomic operation.** Baseline establishment and candidate replacement happen in a
  single exported state call that receives *both* the pre-edit and post-edit id sets and
  performs "set baseline iff absent, then recompute candidates" under one `mu.Lock()`
  with one save — following the single-writer discipline `SetRedCandidates` and
  `ConsumeOverride` already use. A partial write is impossible.
- **A failed capture blocks the test-file edit itself.** This is the one case where a
  test-file edit is refused, and it is a deliberate departure from today's
  always-allow-and-swallow behaviour (`main.go:176-181`). The reason is that the guard
  runs in `PreToolUse`, **before** the edit is applied: refusing the edit leaves disk
  byte-unchanged and the baseline absent, which is a *consistent* state, and the natural
  retry re-captures from exactly the same pre-edit content and succeeds.

  The alternative — allow the edit and mark the file poisoned — cannot actually recover.
  Once the edit lands, disk holds the new test, so any later capture baselines that test
  away and the candidate is lost for the session no matter what marker was set. There is
  no repair, only a nicer error. Blocking is what makes recovery real, so no
  capture-failed marker is needed and none is specified.

  The failure is reported on guard stderr, and the returned error names the file and the
  retry. A lost candidate must never become a spurious allow, and must never become an
  unrecoverable session either.
- **Session-scoped.** Cleared by `ResetSession` (`state.go:388-397`) together with
  `red_candidates`, i.e. on `SessionStart`. A test file created in-session (absent from
  disk at first touch) gets an empty baseline.

### Path identity

One canonical normalizer is applied to every state key and to the overlay mapping:
`red_candidates`, the baseline map, `build_repair` entry paths, and the overlay's real-
path key. Both sides of the existing lookup must go through it — the keys written by
`captureRedCandidates` and the sibling paths `siblingRedCheck` resolves at
`main.go:519-526`. Absent this, two spellings of one file (uncleaned, or via a symlink)
produce two entries and the "iff absent" baseline rule double-writes.

### New session state

Fields added to `Session` (`state.go:60-68`), all with `,omitempty` matching
`RedCandidates`: the per-file baseline map (absolute normalized path → ids); the active
repair-mode attestation (cleared on a clean probe); and an append-only build-repair log
for the session, which is the budget counter of §A.2 and is cleared **only** by
`ResetSession` — never by a clean probe.

Each log entry carries a sequence number, the normalized file path, a **`sha256`**
digest computed over the **full** error bytes **before** truncation, and a summary
capped at 4 KiB with a visible truncation marker — the convention spec 0047 established
for captured subprocess output. The digest algorithm is named here rather than left to
the implementation so that "digest" cannot silently mean something different per call
site; it matches the attestation fingerprint's `sha256`, and both are over raw bytes.

### Bootstrap honesty — a stated, non-zero override budget

These fixes live in the binary that gates the edits implementing them. The budget is
**1 override, not 0**: the from-scratch exported bootstrap in `tools/internal/speccraft`
(the atomic capture call plus the build-repair accessors), landed as stubs in a single
edit paired with their first REDs, per `.speccraft/conventions.md:112-134`.

The prober adds **0** to that budget: it lands in the `speccraft-guard` cmd package on
the compile-stable `processToolUse` seam, not as a new `runner` export. This is a
**decision, not an implementation choice** — both reviewers independently recommended
it, and leaving it open is exactly how spec 0047's 0→5 overshoot began. Every override
actually spent is recorded in `changelog.md` with its reason and reported against this
budget at close.

## Acceptance criteria

1. **Clean overlay build allows the edit silently and ends repair mode.** Given a Go
   production edit whose adapter returns `runner.OutcomeBuildFailed` and whose overlay
   build of the `applyEdit`-derived content exits 0: `siblingRedCheck` returns `nil`, no
   new build-repair entry is written, and any active repair-mode attestation is cleared.
   A subsequent production edit is once again subject to the ordinary red-check.

2. **Still-broken overlay allows the edit and records it atomically.** Same
   preconditions, overlay exits non-zero: `siblingRedCheck` returns `nil`, repair mode
   is active with a fingerprint of the pre-edit error, and the log gains one entry
   carrying a sequence number, the normalized absolute path, a digest over the full
   pre-truncation error bytes, and a ≤4 KiB summary ending in the truncation marker when
   capped. N such edits yield N entries in sequence order.

3. **A failed record blocks the edit.** With the state write injected to fail, the
   still-broken branch returns an **error** rather than `nil`, and no partial entry is
   observable. An unauditable allowance is never granted.

4. **The repair budget is session-wide and a clean probe does not refund it.** The 11th
   still-broken edit in one session (`buildRepairMaxEdits` = 10) is blocked with a
   message naming `/speccraft:spec:override`. Pinned by the interleaved sequence, not
   just a straight run of 11: break → 6 admitted edits → a clean probe (repair mode
   ends, attestation cleared, log still holds 6) → a second break → a fresh attestation
   → only **4** further admissions, with the 5th blocked. A `ResetSession` between
   episodes, and only that, restores the full budget.

5. **The sequential-repair scenario needs zero overrides.** A fixture reproducing spec
   0047's shape — a Go production file broken by a forward reference, then five
   sequential repair edits of which the first four leave the tree broken and the fifth
   builds clean — is allowed end to end at **zero** overrides, producing four log
   entries and one silent allow, with repair mode inactive at the end.

6. **An unrelated edit while broken is admitted but recorded, and cannot outlast the
   budget.** Editing a Go production file unrelated to the break is admitted (relatedness
   is deliberately not inferred) but consumes budget and produces a log entry, and the
   sequence of such edits terminates at AC4's bound. Pinned so the bounded-mode trade-off
   is explicit rather than accidental.

7. **An unsupported language falls back to today's blocking behaviour.** For Python, JS,
   TS and Rust, `OutcomeBuildFailed` returns an error whose text matches the current
   `main.go:562-566` **format** — identical modulo the interpolated `res.Stderr`, which
   varies per invocation and so cannot be byte-compared. No prober is constructed, no
   overlay artifact is created, no session-state write occurs. Pinned per language.

8. **A prober that cannot complete blocks, and says why.** With a Go prober resolved but
   its overlay write, toolchain invocation, or deadline failing, the edit is blocked, the
   error carries both the original build error and the probe failure, and no log entry is
   written. The deadline is read from `SPECCRAFT_BUILD_PROBE_TIMEOUT`, with unset, empty,
   invalid, zero and negative all falling back to the 30s default.

9. **The probe never mutates the working tree.** Across clean, still-broken and
   infrastructure-failure runs, every file under the repository root is byte-identical
   before and after and no file is created or removed under the root; the overlay JSON,
   its referenced content file, and `GOCACHE` all resolve to paths outside the root.
   Asserted by a recursive pre/post snapshot of the root, not by inspecting the edited
   file alone.

10. **The prober fires for every modeled write tool, and the tool set is pinned by
    paired enumeration.** Edit, Write, MultiEdit and NotebookEdit each reach the prober
    with the correctly-derived post-edit content. Exercising four known tools cannot by
    itself prove a *future* tool is covered, so coverage is pinned structurally instead:
    a single enumeration of gated write tools is the one source consulted by the hook
    matcher (`hooks/hooks.json`), `applyEdit`'s switch, and this test, and a source-scan
    asserts the three agree. Adding a write tool without extending the probe fails that
    assertion rather than silently bypassing the guard.

11. **A no-new-test re-edit preserves the standing red candidates.** In one session:
    first touch of `foo_test.go` baselines it; edit 1 adds `TestAlpha` →
    `red_candidates` for that file is `["TestAlpha"]`; edit 2 adds only an import line →
    it is still `["TestAlpha"]`, and a `foo.go` production edit backed by a failing
    `TestAlpha` is allowed. This is the case `.speccraft/conventions.md:64-87` currently
    works around by renaming a test.

12. **Genuine deletion shrinks the candidate set.** Continuing that session: edit 3
    removes `TestAlpha` → the candidate set no longer contains it. Deletion is not
    disguised as addition.

13. **Baselines are first-touch-only and atomic.** The baseline is written on first touch
    from the **pre-edit** ids and is not rewritten on any later touch (proven by mutating
    the file between touches and asserting the stored baseline is unchanged);
    establishment and candidate replacement occur in one state call under one lock, so an
    injected save failure leaves neither applied. `ResetSession` clears baselines,
    candidates, the repair attestation **and** the build-repair log together, and the
    next touch re-baselines from then-current disk.

14. **A failed capture blocks the test-file edit, and the retry recovers.** Pinned as a
    sequence: touch 1 of `foo_test.go` adding `TestAlpha` with the state save injected to
    fail returns an **error** — the test-file edit is refused, `foo_test.go` is
    byte-unchanged on disk, no baseline and no candidates are recorded, and stderr
    reports the capture failure. Touch 2 with the save working then captures from that
    same unchanged content: the baseline is established from the pre-edit ids,
    `TestAlpha` becomes a candidate, and a `foo.go` production edit backed by a failing
    `TestAlpha` is allowed. The assertion that disk is unchanged after touch 1 is the
    load-bearing half — it is what makes touch 2 a genuine retry rather than a capture of
    already-poisoned content.

15. **Path normalization is shared and pinned.** An uncleaned path and a symlinked path
    denoting the same file resolve to one key across `red_candidates`, the baseline map
    and the build-repair log, and the sibling lookup at `main.go:519-526` finds the entry
    written by `captureRedCandidates`. Pinned by a source-scan asserting every state-key
    construction routes through the single normalizer.

16. **The ordinary red-check path is behaviourally unchanged.** For every
    non-`OutcomeBuildFailed` path — `OutcomeAllPassed`, `OutcomeAtLeastOneFailed`, a
    non-nil adapter error, an empty just-added set (`main.go:529-536`), a nil
    `runnerForLang` (`main.go:538-540`), and an unresolved runner (`main.go:541-548`) —
    the return value and every error string are unchanged, and an instrumented
    `proberForLang` records **zero** invocations. Pinned by a table over all of these
    cases plus a source-scan asserting the prober is reached from exactly one call site.

17. **`/speccraft:spec:close` reports the build-repair log.** With a non-empty log, the
    close output lists each entry's sequence, path and summary; with an empty log it says
    so; and in neither case does the report gate the close. Pinned durably by a `bats`
    fixture rather than a spec-local predicate, per spec 0047's close-gate lesson.

18. **The policy files name the carve-out, and the bound cannot drift from the code.**
    After this spec, `.speccraft/guardrails.md` states that the red→green invariant is
    bypassed only by `/speccraft:spec:override` **or** bounded build-repair mode, naming
    the per-session cap, the record-before-allow rule, and the close-time report; and
    `.speccraft/conventions.md`'s "build failure is not a valid RED" entry no longer
    claims the rule is never relaxed, instead pointing at the carve-out.

    The anti-drift pin is **bidirectional and mechanical**, not a prose grep: the test
    reads the compiled value of `buildRepairMaxEdits` and asserts that exact number
    appears in the guardrail's carve-out sentence, matched by a regex anchored on that
    sentence rather than on the bare numeral. Changing the constant without updating the
    guardrail fails; deleting the bound from the guardrail while leaving stale prose
    elsewhere also fails. A test that merely checks "10 appears somewhere" would pass
    against text that no longer says anything true.

## Out of scope

- **Probers for Python, JS/TS, or Rust.** Each needs its own mechanism and overlay
  equivalent (§What A.3 names them); each is a follow-up. Until then those languages keep
  today's exact blocking behaviour per AC7.
- **A Go or Python pre-edit gate mirroring Rust's `RunPreEditGate`.** Closing the
  asymmetry in §Why by compile-checking *before* the edit needs a per-language
  fingerprint/cache story to avoid a subprocess on every edit. This spec only makes the
  post-edit path non-wedging.
- **Gating anything on the build-repair log.** AC17 reports; it does not block. Whether a
  session that never reaches a clean probe should fail its close is a policy question for
  a later spec.
- **The aux-delegator false-quorum follow-up** filed from spec 0047. Unrelated surface.
- **Removing the workaround conventions** at `.speccraft/conventions.md:64-87` and
  `:89-110`. Retiring them once these defects are fixed is a documentation pass.
- **Any change to `/speccraft:spec:override`** or `ConsumeOverride` semantics.
- **A release / version bump.** Ships unbumped unless a later release spec bundles it.

## Open questions

_none_
