package main

import (
	"crypto/sha256"
	"encoding/hex"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// Spec 0044 — `speccraft-state ledger-archive <design> [--expect <fp>]`.
// RED before implementation: the subcommand is unknown, so run() returns non-zero
// (the run()-seam contract → override budget 0).

func liveLedger(t *testing.T, ws string) string {
	t.Helper()
	b, _ := os.ReadFile(filepath.Join(ws, ".speccraft", "ledger.md"))
	return string(b)
}
func archiveLedger(t *testing.T, ws string) string {
	t.Helper()
	b, _ := os.ReadFile(filepath.Join(ws, ".speccraft", "ledger.archive.md"))
	return string(b)
}
func writeArchive(t *testing.T, ws, content string) {
	t.Helper()
	if err := os.WriteFile(filepath.Join(ws, ".speccraft", "ledger.archive.md"), []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}
func reconcileFP(t *testing.T, ws, design string) string {
	t.Helper()
	code, stdout, stderr := runCmd(t, ws, "reconcile", design)
	if code != 0 {
		t.Fatalf("reconcile %s failed: %s", design, stderr)
	}
	sum := sha256.Sum256([]byte(stdout))
	return hex.EncodeToString(sum[:])
}

func Test_LedgerArchive_PresentDone_Archives(t *testing.T) {
	ws := mkWorkspace(t, "")
	writeLedgerFile(t, ws, "# Ledger\n\n## design D\n\n### ./api\nspec: 0007-a\nlast_completed_phase: validated\nin_flight:\nblocked:\n")
	writeMemberSpec(t, ws, "./api", "0007-a", "closed")
	code, _, stderr := runCmd(t, ws, "ledger-archive", "D")
	if code != 0 {
		t.Fatalf("done design should archive; code=%d stderr=%s", code, stderr)
	}
	if strings.Contains(liveLedger(t, ws), "## design D") {
		t.Error("design D must be gone from the live ledger")
	}
	if !strings.Contains(archiveLedger(t, ws), "## design D") {
		t.Error("design D must be in the archive")
	}
	if !strings.HasPrefix(archiveLedger(t, ws), "# Ledger") {
		t.Error("archive must carry the # Ledger preamble (ParseLedger-valid)")
	}
}

func Test_LedgerArchive_PresentNotDone_Refuses(t *testing.T) {
	ws := mkWorkspace(t, "")
	before := "# Ledger\n\n## design D\n\n### ./api\nspec: 0007-a\nlast_completed_phase: planned\nin_flight:\nblocked:\n"
	writeLedgerFile(t, ws, before)
	writeMemberSpec(t, ws, "./api", "0007-a", "in-progress")
	code, _, stderr := runCmd(t, ws, "ledger-archive", "D")
	if code == 0 {
		t.Fatal("not-done design must be refused")
	}
	if !strings.Contains(stderr, "design not done") {
		t.Errorf("stderr should say 'design not done'; got %q", stderr)
	}
	if liveLedger(t, ws) != before {
		t.Error("live ledger must be byte-unchanged on refuse")
	}
}

func Test_LedgerArchive_AbsentLivePresentArchive_Noop(t *testing.T) {
	ws := mkWorkspace(t, "")
	writeLedgerFile(t, ws, "# Ledger\n\n## design E\n\n### ./web\nspec: 0012-b\nlast_completed_phase: validated\nin_flight:\nblocked:\n")
	writeArchive(t, ws, "# Ledger\n\n## design D\n\n### ./api\nspec: 0007-a\nlast_completed_phase: validated\nin_flight:\nblocked:\n")
	beforeLive := liveLedger(t, ws)
	beforeArch := archiveLedger(t, ws)
	code, _, stderr := runCmd(t, ws, "ledger-archive", "D")
	if code != 0 {
		t.Fatalf("already-archived design must be an idempotent no-op exit 0; stderr=%s", stderr)
	}
	if liveLedger(t, ws) != beforeLive || archiveLedger(t, ws) != beforeArch {
		t.Error("no-op must leave both files byte-unchanged")
	}
}

func Test_LedgerArchive_AbsentBoth_UnknownDesign(t *testing.T) {
	ws := mkWorkspace(t, "")
	writeLedgerFile(t, ws, "# Ledger\n\n## design E\n\n### ./web\nspec: 0012-b\nlast_completed_phase: validated\nin_flight:\nblocked:\n")
	code, _, stderr := runCmd(t, ws, "ledger-archive", "ZZ")
	if code == 0 {
		t.Fatal("absent-from-both must be refused")
	}
	if !strings.Contains(stderr, "unknown design") {
		t.Errorf("stderr should say 'unknown design'; got %q", stderr)
	}
}

func Test_LedgerArchive_ExpectMismatch_Conflict(t *testing.T) {
	ws := mkWorkspace(t, "")
	before := "# Ledger\n\n## design D\n\n### ./api\nspec: 0007-a\nlast_completed_phase: validated\nin_flight:\nblocked:\n"
	writeLedgerFile(t, ws, before)
	writeMemberSpec(t, ws, "./api", "0007-a", "closed")
	code, _, stderr := runCmd(t, ws, "ledger-archive", "D", "--expect", "deadbeef")
	if code == 0 {
		t.Fatal("--expect mismatch must conflict")
	}
	if !strings.Contains(stderr, "conflict") {
		t.Errorf("stderr should say 'conflict'; got %q", stderr)
	}
	if liveLedger(t, ws) != before {
		t.Error("conflict must leave the live ledger byte-unchanged")
	}
}

func Test_LedgerArchive_ExpectMatch_Archives(t *testing.T) {
	ws := mkWorkspace(t, "")
	writeLedgerFile(t, ws, "# Ledger\n\n## design D\n\n### ./api\nspec: 0007-a\nlast_completed_phase: validated\nin_flight:\nblocked:\n")
	writeMemberSpec(t, ws, "./api", "0007-a", "closed")
	fp := reconcileFP(t, ws, "D")
	code, _, stderr := runCmd(t, ws, "ledger-archive", "D", "--expect", fp)
	if code != 0 {
		t.Fatalf("--expect match should archive; code=%d stderr=%s", code, stderr)
	}
	if strings.Contains(liveLedger(t, ws), "## design D") {
		t.Error("design D must be archived")
	}
}

func Test_LedgerArchive_OtherDesignsByteIdentical(t *testing.T) {
	ws := mkWorkspace(t, "")
	writeLedgerFile(t, ws,
		"# Ledger\n\n"+
			"## design D1\n\n### ./api\nspec: 0007-a\nlast_completed_phase: validated\nin_flight:\nblocked:\n\n"+
			"## design D2\n\n### ./web\nspec: 0012-b\nlast_completed_phase: planned\nin_flight:\nblocked:\n")
	writeMemberSpec(t, ws, "./api", "0007-a", "closed")
	writeMemberSpec(t, ws, "./web", "0012-b", "in-progress")
	code, _, stderr := runCmd(t, ws, "ledger-archive", "D1")
	if code != 0 {
		t.Fatalf("archive D1 failed: %s", stderr)
	}
	live := liveLedger(t, ws)
	if strings.Contains(live, "## design D1") {
		t.Error("D1 must be gone")
	}
	// D2's section must survive verbatim (splice, not re-serialize).
	if !strings.Contains(live, "## design D2\n\n### ./web\nspec: 0012-b\nlast_completed_phase: planned\nin_flight:\nblocked:\n") {
		t.Errorf("D2 section must be byte-identical; got:\n%s", live)
	}
}

func Test_LedgerArchive_BothPresentEqual_CompletesRemovingLive(t *testing.T) {
	ws := mkWorkspace(t, "")
	section := "# Ledger\n\n## design D\n\n### ./api\nspec: 0007-a\nlast_completed_phase: validated\nin_flight:\nblocked:\n"
	writeLedgerFile(t, ws, section)       // crash residue: present in BOTH
	writeArchive(t, ws, section)
	writeMemberSpec(t, ws, "./api", "0007-a", "closed")
	code, _, stderr := runCmd(t, ws, "ledger-archive", "D")
	if code != 0 {
		t.Fatalf("both-present recovery must complete exit 0; stderr=%s", stderr)
	}
	if strings.Contains(liveLedger(t, ws), "## design D") {
		t.Error("recovery must remove the live copy")
	}
}

func Test_LedgerArchive_CorruptArchive_Refuses(t *testing.T) {
	ws := mkWorkspace(t, "")
	before := "# Ledger\n\n## design D\n\n### ./api\nspec: 0007-a\nlast_completed_phase: validated\nin_flight:\nblocked:\n"
	writeLedgerFile(t, ws, before)
	writeMemberSpec(t, ws, "./api", "0007-a", "closed")
	writeArchive(t, ws, "### ./x\nspec: 0001-a\n") // member before design → parse error
	code, _, stderr := runCmd(t, ws, "ledger-archive", "D")
	if code == 0 {
		t.Fatal("a parse-corrupt archive must make ledger-archive refuse")
	}
	if !strings.Contains(stderr, "ledger.archive.md") && !strings.Contains(stderr, "ledger.md:") {
		t.Errorf("stderr should carry the archive parse error; got %q", stderr)
	}
	if liveLedger(t, ws) != before {
		t.Error("refuse must leave the live ledger byte-unchanged")
	}
}

func Test_LedgerArchive_SoleDesign_ArchiveRoundTrips(t *testing.T) {
	ws := mkWorkspace(t, "")
	writeLedgerFile(t, ws, "# Ledger\n\n## design D\n\n### ./api\nspec: 0007-a\nlast_completed_phase: validated\nin_flight:\nblocked:\n")
	writeMemberSpec(t, ws, "./api", "0007-a", "closed")
	if code, _, se := runCmd(t, ws, "ledger-archive", "D"); code != 0 {
		t.Fatalf("sole-design archive failed: %s", se)
	}
	// Live ledger now has no design section; ledger-get returns zero rows.
	_, out, _ := runCmd(t, ws, "ledger-get")
	if strings.TrimSpace(out) != "" {
		t.Errorf("after archiving the sole design, ledger-get must be empty; got %q", out)
	}
}

func Test_StateCmd_Usage_ListsLedgerArchive(t *testing.T) {
	ws := mkWorkspace(t, "")
	_, _, stderr := runCmd(t, ws)
	if !strings.Contains(stderr, "ledger-archive") {
		t.Errorf("usage missing ledger-archive; stderr=%q", stderr)
	}
}
