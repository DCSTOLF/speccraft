# Changelog — 0045 ledger write-locking

**Status:** closed · **Shipped in:** 1.16.0 · **Date:** 2026-08-04

## What shipped

The **load-bearing concurrency fix** for the workspace ledger: every writer
(`ledger-set`, `ledger-archive`) now serializes its ENTIRE read-modify-write
transaction behind an exclusive advisory `syscall.Flock(LOCK_EX)` on a sidecar
`<workspace-root>/.speccraft/ledger.lock`, and each writer's authoritative
ledger read is now taken *inside* the lock — so the read → in-memory transform →
atomic rename is one indivisible critical section on a single host. This closes
the residual concurrent-writer race that specs 0043 and 0044 both shipped
`bounded + deferred`: two writers reading the same bytes could each rename,
silently clobbering the first's change. `ledger-archive`'s two-file transaction
(both-present crash recovery → archive append+rename → live-ledger
remove+rename → every error path) is held under the **same** lock end to end.

The `--expect` compare-and-set is kept as a **semantic CAS** on the existing
`reconcile <design> | sha256sum` fingerprint — but the fingerprint is now
re-derived from the ledger bytes read *under the lock* and compared before any
write, so a caller-supplied `--expect` can never be applied to a ledger that
changed after the caller computed it. The lock closes the op's own read→rename
window through serialization; `--expect` remains the caller→op semantic guard.
No whole-ledger byte-identity claim is made (a reconcile projection cannot
establish that, and none is needed). `ledger-set` intentionally takes NO
`--expect`: it sets a single member field, so serialization plus last-writer-
wins on the same field is sufficient (deliberate asymmetry).

### Surfaces

- **`tools/cmd/speccraft-state/ledger_lock.go`** — the portable core:
  `lockTimeoutEnv` const, `defaultLockTimeout = 10s`, `parseLockTimeout(raw)`
  (unset/empty/invalid/zero/negative → 10s default; only a strictly positive
  parse wins), the `ledgerLockHold` test seam (nil in production), and
  `withLedgerLock(root, stderr, body)` — ensures `.speccraft/` exists, opens the
  lock file 0644, `LOCK_NB`-polls (10ms interval) until the deadline, fires the
  seam, defers unlock + Close, runs body; on timeout prints `ledger busy` to
  stderr and returns non-zero WITHOUT running body.
- **`tools/cmd/speccraft-state/ledger_flock_unix.go`** (`//go:build unix`) —
  `tryFlockExclusive` (`LOCK_EX|LOCK_NB`; EWOULDBLOCK/EAGAIN → false,nil) and
  `releaseFlock` (`LOCK_UN`). The **shipped linux + macOS binaries** get real
  flock.
- **`tools/cmd/speccraft-state/ledger_flock_other.go`** (`//go:build !unix`) —
  stub returning an `unsupported platform` error so a hypothetical non-unix
  build fails loudly rather than silently skipping the lock.
- **`ledger_cmds.go`** — `ledgerSetCmd` resolves the workspace root, then wraps
  the `SetLedgerField` transaction in `withLedgerLock(root, …)`.
- **`ledger_archive_cmd.go`** — `ledgerArchiveCmd` wraps its **entire**
  two-file transaction body in `withLedgerLock(root, …)`: both-present crash
  recovery, the `--expect` fingerprint re-verification (in-process — never a
  shell-out — equal to what `reconcile | sha256sum` would yield), archive
  append+rename, live-ledger remove+rename, every error path.
- **`.gitignore`** — adds `.speccraft/ledger.lock` (sibling to the existing
  `.speccraft/state.json` line); the lock is never committed and never parsed as
  ledger content.

### Contracts

- **Poll loop over cancellation goroutine** (recorded in plan.md per codex S1).
  `syscall.Flock(LOCK_EX)` has no native deadline; a `LOCK_NB` poll loop cannot
  leak a *late* acquisition — when the deadline passes we simply stop looping
  and close the fd, so there is no outstanding blocking `LOCK_EX` in a
  background goroutine that could grab-and-hold the lock after `ledger busy`
  was already returned. The AC3 contract, not the mechanism, is normative.
- **Bounded acquisition, pinned contract.** `SPECCRAFT_LEDGER_LOCK_TIMEOUT`
  (Go duration; default `10s`; unset/empty/invalid/zero/negative → 10s
  fallback). On contention beyond the timeout the writer exits non-zero and its
  stderr **contains** the substring `ledger busy` (assertions use
  `strings.Contains`, never exact-equality — plan.md claude-p S1).
- **Crash-safe, self-cleaning.** The lock is advisory and released by the
  kernel on process exit, so `on success` / `on error` (deferred unlock +
  descriptor close) and `on crash` are the SAME exit clause — a crashed writer
  leaves NO stale lock. Adversarial filesystem mutation of the lock path (e.g.
  symlinking it) is outside the cooperating-writer threat model.
- **Workspace-root scoped.** The lock always lands at the workspace root's
  `.speccraft/` (via `FindWorkspaceRoot`), never a member repo — so both
  writers are guaranteed to contend on the same sidecar.

### Tests

- **`ledger_lock_test.go`** (`//go:build unix`) — held-lock forces `ledger-set`
  down the `ledger busy` timeout path; `parseLockTimeout` table
  (`""`/`"garbage"`/`"0s"`/`"-5s"` → 10s, `"20ms"` → 20ms, `"5s"` → 5s); the
  crash-safe re-exec test (child process holds LOCK_EX, prints `locked` on
  stdout, is SIGKILL'd; direct `LOCK_EX|LOCK_NB` on the same path succeeds
  immediately AND a subsequent `ledger-set` exits 0); lock file present at
  mode 0644 under `.speccraft/` after an uncontended write and never parsed as
  ledger content; `.gitignore` contains `.speccraft/ledger.lock`.
- **`ledger_locktimeout_test.go`** — timeout-fallback contract in isolation.
- **`ledger_contention_test.go`** (`//go:build unix`) — three deterministic
  contention pairs via the `ledgerLockHold` `sync.Once`-gated barrier seam
  (writer A parks INSIDE the critical section, writer B genuinely blocks on the
  kernel flock; no wall-clock timing): `ledger-set` vs `ledger-set` on distinct
  fields (both fields persist); `ledger-set` vs `ledger-archive` on distinct
  designs (both land); `ledger-archive` vs `ledger-archive` on distinct done
  designs (both archived, neither survives live). Each test `os.Chdir`s the
  workspace ONCE and calls `ledgerSetCmd`/`ledgerArchiveCmd` directly in
  goroutines (never concurrent `runCmd`, whose per-call chdir is not
  goroutine-safe).
- **Happy-path byte-identity (AC7)** — the existing
  `ledger_archive_cmd_test.go` / `ledger_set_cmd_test.go` suites, bats hooks,
  and e2e fixtures all assert byte-identical `ledger.md` / `ledger.archive.md`;
  the lock wrapper adds no bytes to those files, so all stayed green.
- Full suite: `go test ./...` + `go vet` green; 282 bats green;
  `-race -count=5` clean; all workspace e2e pass. The only new on-disk artifact
  is the ignored `ledger.lock` sidecar. **Override budget: 0** (every RED was
  a runtime failure of an already-compiling command or a subprocess re-exec;
  the sole new production symbol tests reference, `ledgerLockHold`, was
  introduced as a passenger of the Step-2 GREEN edit and referenced by tests
  only from Step 4 onward).

## Spec vs shipped — deviations

None. Every AC landed as specified. The bound-mechanism decision (poll loop,
not cancellation goroutine — codex S1) and the timeout-fallback matrix (codex
S2) were pre-recorded in plan.md's `## Mechanism decisions`. The `--expect`
re-verification stayed in-process (per the round-3 claude-p clarification) so
the critical section never spans a shell-out.

## Cross-model review — three rounds

Three-round quorum on the spec proper (codex + claude-p, converging):
round 1 `changes-requested` (codex) / `approve-with-comments` (claude-p) drove
the load-bearing spec revisions — the `--expect` byte-CAS overclaim collapsed
into a semantic CAS re-verified under the lock (both reviewers); the
archive-transaction lock scope was extended to span the two-file sequence end
to end (codex); the timeout interface was pinned (both); the contention proof
was pinned to a real synchronization seam (both); portability was scoped to
POSIX / linux+macOS with Windows + network-fs explicitly OOS; the lock-file
lifecycle (mode 0644, ensured `.speccraft/` first, never parsed, gitignored
like `state.json`, descriptor closed) was pinned; workspace-root resolution
was named (`FindWorkspaceRoot`, never a member repo); the `ledger-set` vs
`ledger-archive` asymmetry was stated deliberately. Rounds 2–3 folded the
in-process fingerprint clarification (claude-p, load-bearing — the
`reconcile | sha256sum` shell-pipeline wording in AC5 conflicted with AC1's
no-shell-out-in-the-critical-section rule; resolved by stating the check is
an in-process computation equal to what the pipeline would yield), the
distinct-target scoping of AC2's "both land" (codex), the timeout-fallback
matrix (codex S2), and the adversarial-symlink threat-model exclusion (codex).
Zero guardrail/convention violations across all rounds. Final: **codex
approve-with-comments, claude-p approve.** Full trail in `review.md`
(`reviewed_sha256` stamped).

## Release

Minor bump 1.15.0 → **1.16.0** via the renamed-version-test technique across
the six single-source locations (3 Go `const version` → `…Const1160`/`…Is1160`,
stale-guard now rejects 1.15.0, NO override; `manifest_version_test.go` →
`…VersionIs1160`; plugin.json + marketplace.json). `go test ./...` + `go vet`
green; 282 bats green; drift clean; all workspace e2e pass; binaries rebuilt
report 1.16.0. Push + tag `v1.16.0` triggers the auto-tag → release.yml →
verify-release pipeline (spec 0021).

## Follow-ups / not done

- **`/speccraft:sync --recursive`** (per-member repo-mode fan-out) — split into
  its own spec (per this spec's Out of scope).
- **`ledger.archive.md` compaction** — split into its own spec; the append-only
  archive is off the hot path but grows unboundedly.
- **Cross-host / network-filesystem locking** — advisory `flock` is per-host;
  the workspace is assumed local, the same scope every ledger writer already
  has.
- **Windows support** — no Windows binary is shipped; the `!unix` stub errors
  loudly if that ever changes.
