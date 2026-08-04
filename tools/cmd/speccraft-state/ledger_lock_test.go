//go:build unix

package main

import (
	"bufio"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"testing"
	"time"
)

// crashChildEnv gates the re-exec helper below: only a child spawned with this
// env var set actually acquires-and-blocks; under a normal `go test` run the
// helper returns immediately so it never wedges the suite.
const crashChildEnv = "SPECCRAFT_LEDGER_LOCK_CRASH_CHILD"
const crashPathEnv = "SPECCRAFT_LEDGER_LOCK_CRASH_PATH"

// Test_LedgerLockCrashHelper is a re-exec target, NOT a normal unit test. When
// the parent spawns it with crashChildEnv=1 it opens the lock path, takes an
// exclusive flock, prints `locked`, and blocks forever — modelling a writer
// that dies while holding the lock. With the env unset it is a no-op.
func Test_LedgerLockCrashHelper(t *testing.T) {
	if os.Getenv(crashChildEnv) != "1" {
		return
	}
	fd, err := os.OpenFile(os.Getenv(crashPathEnv), os.O_CREATE|os.O_RDWR, 0o644)
	if err != nil {
		os.Exit(3)
	}
	if err := syscall.Flock(int(fd.Fd()), syscall.LOCK_EX); err != nil {
		os.Exit(4)
	}
	os.Stdout.WriteString("locked\n")
	os.Stdout.Sync()
	select {} // block until the parent SIGKILLs us
}

// A writer that dies holding the lock must leave nothing stale behind: the
// kernel releases an advisory flock on process exit, so the next acquisition
// succeeds. (AC4)
func Test_LedgerLock_CrashedHolder_NextAcquireSucceeds(t *testing.T) {
	ws := mkWorkspace(t, "")
	lockPath := filepath.Join(ws, ".speccraft", "ledger.lock")

	cmd := exec.Command(os.Args[0], "-test.run=Test_LedgerLockCrashHelper")
	cmd.Env = append(os.Environ(), crashChildEnv+"=1", crashPathEnv+"="+lockPath)
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		t.Fatal(err)
	}
	if err := cmd.Start(); err != nil {
		t.Fatal(err)
	}
	// Ensure the child is reaped even if an assertion fails early.
	killed := false
	t.Cleanup(func() {
		if !killed {
			cmd.Process.Kill()
		}
		cmd.Wait()
	})

	// Wait for the handshake proving the child actually holds the lock.
	sc := bufio.NewScanner(stdout)
	gotLock := false
	for sc.Scan() {
		if strings.TrimSpace(sc.Text()) == "locked" {
			gotLock = true
			break
		}
	}
	if !gotLock {
		t.Fatal("child never reported holding the lock")
	}

	// Sanity: while the child holds it, a non-blocking acquire must fail.
	if got := tryAcquire(t, lockPath); got {
		t.Fatal("lock should be held by the child before it is killed")
	}

	// Kill the holder; the kernel must release its flock.
	if err := cmd.Process.Signal(syscall.SIGKILL); err != nil {
		t.Fatalf("SIGKILL: %v", err)
	}
	killed = true
	cmd.Wait()

	// (a) A direct non-blocking acquire now succeeds — no stale lock.
	deadline := time.Now().Add(5 * time.Second)
	acquired := false
	for time.Now().Before(deadline) {
		if tryAcquire(t, lockPath) {
			acquired = true
			break
		}
		time.Sleep(10 * time.Millisecond)
	}
	if !acquired {
		t.Fatal("stale lock wedged the next acquisition after the holder was killed")
	}

	// (b) The next real writer proceeds.
	t.Setenv("SPECCRAFT_LEDGER_LOCK_TIMEOUT", "5s")
	if code, _, stderr := runCmd(t, ws, "ledger-set", "D", "./api", "spec", "0007-a"); code != 0 {
		t.Fatalf("ledger-set must proceed after the crashed holder released; code=%d stderr=%s", code, stderr)
	}
}

// tryAcquire opens the lock path and attempts a single non-blocking exclusive
// flock, releasing immediately on success. Returns whether it was acquired.
func tryAcquire(t *testing.T, lockPath string) bool {
	t.Helper()
	fd, err := os.OpenFile(lockPath, os.O_CREATE|os.O_RDWR, 0o644)
	if err != nil {
		t.Fatalf("open lock: %v", err)
	}
	defer fd.Close()
	if err := syscall.Flock(int(fd.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); err != nil {
		return false
	}
	syscall.Flock(int(fd.Fd()), syscall.LOCK_UN)
	return true
}

// The lock file is created 0644 under .speccraft/ and is never ledger content. (AC4)
func Test_LedgerLock_FileCreated0644UnderSpeccraft(t *testing.T) {
	ws := mkWorkspace(t, "")
	if code, _, stderr := runCmd(t, ws, "ledger-set", "D", "./api", "spec", "0007-a"); code != 0 {
		t.Fatalf("ledger-set: code=%d stderr=%s", code, stderr)
	}
	fi, err := os.Stat(filepath.Join(ws, ".speccraft", "ledger.lock"))
	if err != nil {
		t.Fatalf("lock file must exist after a write: %v", err)
	}
	if fi.Mode().Perm() != 0o644 {
		t.Errorf("lock mode = %v, want 0644", fi.Mode().Perm())
	}
}

// Spec 0045 — ledger write-locking.
//
// T1 (RED before the lock exists): a writer must acquire an exclusive advisory
// lock on <root>/.speccraft/ledger.lock before its first authoritative write.
// When another process already holds that lock, the writer must bound its wait
// by SPECCRAFT_LEDGER_LOCK_TIMEOUT and, on timeout, exit non-zero with `ledger
// busy` on stderr. Before implementation `ledger-set` ignores the held flock,
// writes anyway, and exits 0 — a runtime failure, not a build failure.
func Test_LedgerLock_HeldByOther_TimesOutBusy(t *testing.T) {
	ws := mkWorkspace(t, "")
	lockPath := filepath.Join(ws, ".speccraft", "ledger.lock")

	// This test process holds the lock the way a concurrent writer would.
	fd, err := os.OpenFile(lockPath, os.O_CREATE|os.O_RDWR, 0o644)
	if err != nil {
		t.Fatalf("open lock: %v", err)
	}
	t.Cleanup(func() { fd.Close() })
	if err := syscall.Flock(int(fd.Fd()), syscall.LOCK_EX); err != nil {
		t.Fatalf("flock LOCK_EX: %v", err)
	}
	t.Cleanup(func() { syscall.Flock(int(fd.Fd()), syscall.LOCK_UN) })

	t.Setenv("SPECCRAFT_LEDGER_LOCK_TIMEOUT", "20ms")
	code, _, stderr := runCmd(t, ws, "ledger-set", "D", "./api", "spec", "0007-a")
	if code == 0 {
		t.Fatalf("ledger-set must not succeed while the lock is held; got exit 0")
	}
	if !strings.Contains(stderr, "ledger busy") {
		t.Errorf("stderr must contain %q; got %q", "ledger busy", stderr)
	}
}

// The archive writer's whole two-file transaction is under the same lock. With
// a done design that WOULD archive successfully, a held lock must still force
// the bounded `ledger busy` timeout — before wiring, ledger-archive ignores the
// lock, archives, and exits 0 (runtime RED).
func Test_LedgerArchive_HeldByOther_TimesOutBusy(t *testing.T) {
	ws := mkWorkspace(t, "")
	writeLedgerFile(t, ws, "# Ledger\n\n## design D\n\n### ./api\nspec: 0007-a\nlast_completed_phase: validated\nin_flight:\nblocked:\n")
	writeMemberSpec(t, ws, "./api", "0007-a", "closed")

	lockPath := filepath.Join(ws, ".speccraft", "ledger.lock")
	fd, err := os.OpenFile(lockPath, os.O_CREATE|os.O_RDWR, 0o644)
	if err != nil {
		t.Fatalf("open lock: %v", err)
	}
	t.Cleanup(func() { fd.Close() })
	if err := syscall.Flock(int(fd.Fd()), syscall.LOCK_EX); err != nil {
		t.Fatalf("flock LOCK_EX: %v", err)
	}
	t.Cleanup(func() { syscall.Flock(int(fd.Fd()), syscall.LOCK_UN) })

	t.Setenv("SPECCRAFT_LEDGER_LOCK_TIMEOUT", "20ms")
	code, _, stderr := runCmd(t, ws, "ledger-archive", "D")
	if code == 0 {
		t.Fatalf("ledger-archive must not succeed while the lock is held; got exit 0")
	}
	if !strings.Contains(stderr, "ledger busy") {
		t.Errorf("stderr must contain %q; got %q", "ledger busy", stderr)
	}
	// And it must NOT have archived while blocked.
	if strings.Contains(archiveLedger(t, ws), "## design D") {
		t.Error("ledger-archive must not have moved design D while lock-blocked")
	}
}
