---
spec: "0045"
status: planned
strategy: tdd
---

# Plan — 0045 ledger write-locking

## Mechanism decisions (recorded per review "Carried to plan.md")

- **Bound mechanism = `LOCK_NB` poll loop, NOT a cancellation goroutine**
  (claude-p S2, codex S1). `withLedgerLock` opens the lock fd once, then loops
  `syscall.Flock(fd, LOCK_EX|LOCK_NB)`: on `EWOULDBLOCK`/`EAGAIN` it sleeps a
  short poll interval (10ms) and retries until `time.Now()` passes the deadline;
  any other errno is a hard failure. This is chosen consciously over a
  `LOCK_EX` + cancellation goroutine because **the poll loop cannot leak a late
  acquisition** — when the deadline passes we simply stop looping and close the
  fd; there is no outstanding blocking `LOCK_EX` call in a background goroutine
  that could grab-and-hold the lock *after* `ledger busy` was already returned
  (codex S1 satisfied by construction, not by cancellation bookkeeping).
- **Timeout contract (AC3).** `parseLockTimeout(os.Getenv("SPECCRAFT_LEDGER_LOCK_TIMEOUT"))`
  → a `time.Duration`. Unset, empty, invalid (`time.ParseDuration` error), zero,
  or negative all fall back to the `10s` default (codex S2). Only a strictly
  positive parse wins. On deadline the writer returns non-zero and its stderr
  **contains** the substring `ledger busy` (claude-p S1: assertions use
  `strings.Contains`, never exact-equality).
- **Deterministic contention seam (AC2).** An unexported package var
  `var ledgerLockHold func()` is invoked inside `withLedgerLock` immediately
  after the flock is acquired and before `body()` runs. Tests set it (with
  `t.Cleanup` restore) to a `sync.Once`-gated hook that signals "entered the
  critical section" and blocks on a release channel, so two writers are
  *provably* both in the contested interval (writer A parked inside the lock,
  writer B genuinely blocked on the kernel flock) — no wall-clock timing.
- **Platform scope (AC6).** Flock primitive lives in `ledger_flock_unix.go`
  (`//go:build unix`), covering the shipped linux+darwin binaries; a
  `ledger_flock_other.go` (`//go:build !unix`) stub returns an
  "unsupported platform" error so a hypothetical non-unix build fails loudly
  rather than silently skipping the lock. `EWOULDBLOCK` and `EAGAIN` are treated
  as the same "still held" signal (they alias on linux; both handled for macOS).

## Override budget

Target **0**. Every RED below is a *runtime* failure of an already-compiling
command (`ledger-set` / `ledger-archive` via `runCmd`, or the existing
`ledgerSetCmd`/`ledgerArchiveCmd` funcs) or of a subprocess re-exec — never a
build-failure-of-a-new-symbol. The one genuinely new production symbol that a
test must reference (`ledgerLockHold`) is introduced as a **passenger of the
Step-2 GREEN edit**, which is itself authorized by Step-1's seam-free runtime
RED; the seam is not referenced by any test until Step 4, after it exists. No
`/speccraft:spec:override` is required.

## Test-first sequence

### Step 1 — Held lock forces the busy path (RED)
- Add `tools/cmd/speccraft-state/ledger_lock_test.go` (`//go:build unix`):
  - `Test_LedgerLock_HeldByOther_TimesOutBusy` — creates a workspace, opens
    `<ws>/.speccraft/ledger.lock` itself and holds `syscall.Flock(fd, LOCK_EX)`,
    sets `SPECCRAFT_LEDGER_LOCK_TIMEOUT=20ms`, then
    `runCmd(t, ws, "ledger-set", "D", "./api", "spec", "0007-a")`. Asserts exit
    is non-zero AND `strings.Contains(stderr, "ledger busy")`. Releases the
    flock in `t.Cleanup`.
- Tests fail: `ledger-set` currently takes no lock, ignores the held flock,
  writes, and exits 0 — a runtime failure (wrong exit code, no `ledger busy`),
  not a build failure. **Covers AC1 (lock before first write), AC3 (bounded
  acquisition + `ledger busy`).**

### Step 2 — Introduce the lock and wrap both writers (GREEN)
- Add `tools/cmd/speccraft-state/ledger_lock.go` (portable): `lockTimeoutEnv`
  const, `defaultLockTimeout = 10*time.Second`, `parseLockTimeout(raw string)
  time.Duration`, `var ledgerLockHold func()`, and
  `withLedgerLock(root string, body func() int) int` — ensures `<root>/.speccraft/`
  exists, `os.OpenFile(lockPath, O_CREATE|O_RDWR, 0o644)`, poll-acquires within
  the timeout, fires `ledgerLockHold` if non-nil, `defer` unlock + `Close`, runs
  `body`; on timeout prints `ledger busy` to stderr and returns non-zero.
- Add `tools/cmd/speccraft-state/ledger_flock_unix.go` (`//go:build unix`):
  `tryFlockExclusive(fd int) (bool, error)` (LOCK_EX|LOCK_NB; EWOULDBLOCK/EAGAIN
  → `false,nil`) and `releaseFlock(fd int) error` (LOCK_UN).
- Add `tools/cmd/speccraft-state/ledger_flock_other.go` (`//go:build !unix`):
  stub returning an "unsupported platform" error.
- Edit `ledger_cmds.go`: `ledgerSetCmd` resolves root, then returns
  `withLedgerLock(root, func() int { … SetLedgerField … })`.
- Edit `ledger_archive_cmd.go`: `ledgerArchiveCmd` resolves root, then wraps its
  **entire** transaction body (both-present recovery, `--expect` re-verify,
  archive append + rename, live remove + rename, every error path) in
  `withLedgerLock(root, func() int { … })`.
- Step-1 test passes. **Covers AC1 (whole-transaction critical section, incl.
  archive's two-file sequence), AC3, AC6 (build-tagged primitive).**

### Step 3 — Timeout fallback contract (RED → GREEN)
- Extend `ledger_lock_test.go` with `Test_ParseLockTimeout_FallsBackTo10s`
  (table-driven): `""`, `"garbage"`, `"0s"`, `"-5s"` → `10s`; `"20ms"` → `20ms`;
  `"5s"` → `5s`.
- Tests fail if `parseLockTimeout` does not yet special-case zero/negative/empty.
  **Covers AC3 (codex S2: empty/invalid/zero/negative → 10s default).**

### Step 4 — No lost update under real contention (RED → GREEN)
- Add `tools/cmd/speccraft-state/ledger_contention_test.go` (`//go:build unix`).
  Each test `os.Chdir(ws)` **once** (restored via `t.Cleanup`) — never
  concurrent `runCmd` (its per-call chdir is not goroutine-safe) — installs a
  `sync.Once`-gated `ledgerLockHold` that parks the *first* writer inside the
  critical section, then launches two writers as goroutines calling
  `ledgerSetCmd` / `ledgerArchiveCmd` directly:
  - `Test_LedgerContention_SetVsSet_BothFieldsPersist` — two `ledger-set` on
    **distinct fields** of the same member; assert both fields present.
  - `Test_LedgerContention_SetVsArchive_BothLand` — `ledger-set` on design D2
    concurrent with `ledger-archive` of a done design D1; assert D2's field
    landed AND D1 moved to `ledger.archive.md`.
  - `Test_LedgerContention_ArchiveVsArchive_BothDesignsArchived` — two
    `ledger-archive` on **distinct** done designs; assert both end up in the
    archive and neither survives in the live ledger.
- RED against seam-present-but-lock-absent code (writer A parks in the seam, B
  reads the same bytes and writes, A releases and clobbers B) and GREEN once
  Step-2's lock serializes them; the seam already exists (Step 2) so the file
  compiles — a runtime RED, not a build failure. **Covers AC2 (distinct-target
  "both land", three pair combos via the barrier seam), AC5 (asymmetry:
  `ledger-set` takes no `--expect`, serialization suffices).**

### Step 5 — Crash-safe, self-cleaning lock (RED → GREEN)
- Extend `ledger_lock_test.go`:
  - `Test_LedgerLockCrashHelper` — a re-exec helper gated on env
    `SPECCRAFT_LEDGER_LOCK_CRASH_CHILD=1`: opens the lock file, `Flock(LOCK_EX)`,
    prints `locked\n` to stdout, then blocks forever. (No-op under `go test`
    when the env flag is unset.)
  - `Test_LedgerLock_CrashedHolder_NextAcquireSucceeds` — `exec.Command(os.Args[0],
    "-test.run=Test_LedgerLockCrashHelper")` with the child env + a temp
    workspace path; waits for `locked` on the child's stdout, sends `SIGKILL`,
    `Wait`s, then asserts (a) a direct `Flock(LOCK_EX|LOCK_NB)` on the same lock
    path succeeds immediately, and (b) `runCmd(t, ws, "ledger-set", …)` exits 0
    within a short timeout — proving no stale lock wedges the next writer.
  - `Test_LedgerLock_FileCreated0644UnderSpeccraft` — after an uncontended
    `ledger-set`, assert `<ws>/.speccraft/ledger.lock` exists with mode `0644`
    and is never `ParseLedger`-parsed as ledger content.
- **Covers AC4 (kernel-released advisory lock, mode 0644, ensured `.speccraft/`,
  descriptor closed, never parsed).**

### Step 6 — Git-ignore the lock sidecar (config + proof)
- Edit `.gitignore`: add `.speccraft/ledger.lock` (sibling to the existing
  `.speccraft/state.json` line). Config file, not guard-gated.
- Extend `ledger_lock_test.go` with `Test_Gitignore_IgnoresLedgerLock` — reads
  the repo-root `.gitignore` and asserts it contains `.speccraft/ledger.lock`.
  **Covers AC4 (git-ignored like `state.json`), AC7 (only new artifact is the
  ignored lock).**

### Step 7 — Happy-path byte-identity is already pinned (verification, AC7)
- No new test needed: the existing `ledger_archive_cmd_test.go` /
  `ledger_set_cmd_test.go` suites, the bats hooks, and the e2e fixtures assert
  byte-identical `ledger.md` / `ledger.archive.md` output. The lock wrapper adds
  no bytes to those files, so all stay green. This step is the guard against an
  accidental output change.

### Step 8 — Refactor (optional)
- Extract a single `ledgerLockPath(root string) string` helper if the path
  literal appears in more than one production site. All tests still pass. No
  behavior change.

### Step 9 — Full verification
- `cd tools && go test ./... && go vet ./...`
- Full bats: `tests/hooks/*.bats`.
- Hermetic e2e: `tests/e2e/run.sh`. Confirm no snapshot/byte-identity regression
  and that `ledger.lock` is the only new on-disk artifact.

## Delegation

All steps → primary Go implementer. Stdlib-only (`syscall.Flock`, build tags,
`os/exec` re-exec) inside the `speccraft-state` cmd package; no aux-agent
strength match justifies a handoff. Step 2's build-tag split and Step 5's crash
re-exec are the only subtle parts and are best kept with the author who holds
the whole lock-lifecycle context.

## Risk

- **Concurrent `runCmd` chdir race** → the AC2 contention test chdirs once and
  calls `ledgerSetCmd`/`ledgerArchiveCmd` directly in goroutines; never two
  `runCmd` in parallel.
- **macOS `EAGAIN` vs linux `EWOULDBLOCK`** → `tryFlockExclusive` treats both
  errnos as "still held"; unix build tag keeps it off Windows.
- **Crash-test flakiness** → parent blocks on the child's `locked\n` stdout
  handshake before `SIGKILL`; generous post-kill acquire timeout.
- **Poll interval vs test timeout** → 10ms poll against a 20ms test timeout
  leaves margin; the busy test asserts only the *outcome* (`ledger busy` +
  non-zero), never a wall-clock duration.
- **Network-filesystem flock semantics** → out of scope per AC6 (advisory,
  per-host; workspace assumed local); stated, not defended.
- **Late-acquisition leak after timeout** → eliminated by the poll-loop choice
  (no background blocking `LOCK_EX`); recorded above (codex S1).
