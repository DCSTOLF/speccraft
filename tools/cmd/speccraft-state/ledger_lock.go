package main

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"time"
)

// Spec 0045 — ledger write-locking. Every ledger writer (`ledger-set`,
// `ledger-archive`) serializes its ENTIRE read-modify-write behind an exclusive
// advisory lock on <root>/.speccraft/ledger.lock, so the authoritative read and
// the atomic rename(s) are one indivisible critical section on a single host.

const lockTimeoutEnv = "SPECCRAFT_LEDGER_LOCK_TIMEOUT"

// defaultLockTimeout bounds how long a writer waits for a contended lock before
// giving up with `ledger busy`. Any unset/empty/invalid/zero/negative value of
// SPECCRAFT_LEDGER_LOCK_TIMEOUT falls back to this (AC3).
const defaultLockTimeout = 10 * time.Second

// lockPollInterval is how often the LOCK_NB poll loop retries while the lock is
// held elsewhere. A poll loop (not a blocking LOCK_EX + cancellation goroutine)
// is chosen deliberately: when the deadline passes we simply stop looping and
// close the fd, so a timed-out acquisition can never leak and grab the lock
// after `ledger busy` was already returned (spec 0045 review, codex S1).
const lockPollInterval = 10 * time.Millisecond

// ledgerLockHold, when non-nil, is invoked inside withLedgerLock immediately
// after the lock is acquired and before the body runs. It exists only as a
// test seam so a contention test can provably park one writer inside the
// critical section while a second blocks on the kernel flock (AC2). Production
// leaves it nil.
var ledgerLockHold func()

// parseLockTimeout resolves the configured acquisition timeout. Only a strictly
// positive time.ParseDuration wins; unset, empty, unparseable, zero, and
// negative all fall back to defaultLockTimeout (AC3).
func parseLockTimeout(raw string) time.Duration {
	if raw == "" {
		return defaultLockTimeout
	}
	d, err := time.ParseDuration(raw)
	if err != nil || d <= 0 {
		return defaultLockTimeout
	}
	return d
}

// ledgerLockPath is the sidecar lock file guarding <root>'s ledger writes.
func ledgerLockPath(root string) string {
	return filepath.Join(root, ".speccraft", "ledger.lock")
}

// withLedgerLock acquires the exclusive advisory lock for root's ledger, runs
// body while holding it, and releases it (unlock + close) on return. body's
// exit code is propagated. On lock-acquisition timeout it writes `ledger busy`
// to stderr and returns non-zero WITHOUT running body. The lock file is created
// 0644 under an ensured .speccraft/ directory, is never parsed as ledger
// content, and — being advisory — is released by the kernel on process exit, so
// a crashed holder leaves nothing stale behind (AC1/AC3/AC4).
func withLedgerLock(root string, stderr io.Writer, body func() int) int {
	lockPath := ledgerLockPath(root)
	if err := os.MkdirAll(filepath.Dir(lockPath), 0o755); err != nil {
		fmt.Fprintln(stderr, err)
		return 1
	}
	f, err := os.OpenFile(lockPath, os.O_CREATE|os.O_RDWR, 0o644)
	if err != nil {
		fmt.Fprintln(stderr, err)
		return 1
	}
	defer f.Close()
	fd := int(f.Fd())

	deadline := time.Now().Add(parseLockTimeout(os.Getenv(lockTimeoutEnv)))
	for {
		ok, err := tryFlockExclusive(fd)
		if err != nil {
			fmt.Fprintln(stderr, err)
			return 1
		}
		if ok {
			break
		}
		if !time.Now().Before(deadline) {
			fmt.Fprintln(stderr, "ledger busy")
			return 1
		}
		time.Sleep(lockPollInterval)
	}
	defer releaseFlock(fd)

	if ledgerLockHold != nil {
		ledgerLockHold()
	}
	return body()
}
