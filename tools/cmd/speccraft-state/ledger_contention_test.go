//go:build unix

package main

import (
	"io"
	"os"
	"strings"
	"sync"
	"testing"
	"time"
)

// Spec 0045 AC2 — no lost update under real contention. Each test parks the
// first writer INSIDE the critical section via the ledgerLockHold seam (so it
// provably holds the kernel flock) while a second writer is launched and must
// block on that same lock; the correctness assertion (both writes land) is
// serialization proof and does not depend on wall-clock timing. Cases target
// DISTINCT ledger targets so "both land" is well-defined regardless of order.
//
// runCmd's per-call os.Chdir is not goroutine-safe, so these chdir ONCE and
// call ledgerSetCmd / ledgerArchiveCmd directly in goroutines.

func chdirOnce(t *testing.T, dir string) {
	t.Helper()
	cwd, _ := os.Getwd()
	if err := os.Chdir(dir); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { os.Chdir(cwd) })
}

// parkFirstWriter installs a ledgerLockHold seam that parks the first writer to
// enter the critical section until the returned release func is called. It
// returns an `entered` channel (closed once the first writer is parked) and a
// release func. Restores the prior seam via t.Cleanup.
func parkFirstWriter(t *testing.T) (entered <-chan struct{}, release func()) {
	t.Helper()
	ent := make(chan struct{})
	rel := make(chan struct{})
	var once sync.Once
	var relOnce sync.Once
	prev := ledgerLockHold
	ledgerLockHold = func() {
		once.Do(func() {
			close(ent)
			<-rel
		})
	}
	t.Cleanup(func() { ledgerLockHold = prev })
	return ent, func() { relOnce.Do(func() { close(rel) }) }
}

func Test_LedgerContention_SetVsSet_BothFieldsPersist(t *testing.T) {
	ws := mkWorkspace(t, "")
	chdirOnce(t, ws)
	t.Setenv("SPECCRAFT_LEDGER_LOCK_TIMEOUT", "10s")
	entered, release := parkFirstWriter(t)

	var wg sync.WaitGroup
	wg.Add(2)
	go func() { defer wg.Done(); ledgerSetCmd("D", "./api", "spec", "0007-a", io.Discard, io.Discard) }()
	<-entered // first writer holds the lock, parked
	go func() {
		defer wg.Done()
		ledgerSetCmd("D", "./api", "last_completed_phase", "planned", io.Discard, io.Discard)
	}()
	time.Sleep(50 * time.Millisecond) // let the second writer reach + block on the flock
	release()
	wg.Wait()

	got := liveLedger(t, ws)
	if !strings.Contains(got, "spec: 0007-a") {
		t.Errorf("lost 'spec' field under contention:\n%s", got)
	}
	if !strings.Contains(got, "last_completed_phase: planned") {
		t.Errorf("lost 'last_completed_phase' field under contention:\n%s", got)
	}
}

func Test_LedgerContention_SetVsArchive_BothLand(t *testing.T) {
	ws := mkWorkspace(t, "")
	// D1 is a done design ready to archive; the concurrent ledger-set adds D2.
	writeLedgerFile(t, ws, "# Ledger\n\n## design D1\n\n### ./api\nspec: 0007-a\nlast_completed_phase: validated\nin_flight:\nblocked:\n")
	writeMemberSpec(t, ws, "./api", "0007-a", "closed")
	chdirOnce(t, ws)
	t.Setenv("SPECCRAFT_LEDGER_LOCK_TIMEOUT", "10s")
	entered, release := parkFirstWriter(t)

	var wg sync.WaitGroup
	wg.Add(2)
	go func() { defer wg.Done(); ledgerArchiveCmd("D1", "", false, io.Discard, io.Discard) }()
	<-entered
	go func() { defer wg.Done(); ledgerSetCmd("D2", "./web", "spec", "0009-b", io.Discard, io.Discard) }()
	time.Sleep(50 * time.Millisecond)
	release()
	wg.Wait()

	live := liveLedger(t, ws)
	if strings.Contains(live, "## design D1") {
		t.Errorf("D1 must be archived out of the live ledger:\n%s", live)
	}
	if !strings.Contains(live, "## design D2") || !strings.Contains(live, "spec: 0009-b") {
		t.Errorf("D2's ledger-set was lost under contention:\n%s", live)
	}
	if !strings.Contains(archiveLedger(t, ws), "## design D1") {
		t.Errorf("D1 must be in the archive:\n%s", archiveLedger(t, ws))
	}
}

func Test_LedgerContention_ArchiveVsArchive_BothDesignsArchived(t *testing.T) {
	ws := mkWorkspace(t, "")
	writeLedgerFile(t, ws, "# Ledger\n\n## design D1\n\n### ./api\nspec: 0007-a\nlast_completed_phase: validated\nin_flight:\nblocked:\n\n## design D2\n\n### ./web\nspec: 0009-b\nlast_completed_phase: validated\nin_flight:\nblocked:\n")
	writeMemberSpec(t, ws, "./api", "0007-a", "closed")
	writeMemberSpec(t, ws, "./web", "0009-b", "closed")
	chdirOnce(t, ws)
	t.Setenv("SPECCRAFT_LEDGER_LOCK_TIMEOUT", "10s")
	entered, release := parkFirstWriter(t)

	var wg sync.WaitGroup
	wg.Add(2)
	go func() { defer wg.Done(); ledgerArchiveCmd("D1", "", false, io.Discard, io.Discard) }()
	<-entered
	go func() { defer wg.Done(); ledgerArchiveCmd("D2", "", false, io.Discard, io.Discard) }()
	time.Sleep(50 * time.Millisecond)
	release()
	wg.Wait()

	live := liveLedger(t, ws)
	if strings.Contains(live, "## design D1") || strings.Contains(live, "## design D2") {
		t.Errorf("both designs must be gone from the live ledger; lost-removal race:\n%s", live)
	}
	arch := archiveLedger(t, ws)
	if !strings.Contains(arch, "## design D1") || !strings.Contains(arch, "## design D2") {
		t.Errorf("both designs must be in the archive:\n%s", arch)
	}
}
