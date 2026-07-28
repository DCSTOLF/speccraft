package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func writeLedgerFile(t *testing.T, ws, content string) {
	t.Helper()
	if err := os.WriteFile(filepath.Join(ws, ".speccraft", "ledger.md"), []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}

// writeMemberSpec writes <ws>/<memberPath>/specs/<specRef>/spec.md with a status.
func writeMemberSpec(t *testing.T, ws, memberPath, specRef, status string) {
	t.Helper()
	p := filepath.Join(ws, memberPath, "specs", specRef, "spec.md")
	if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(p, []byte("---\nstatus: "+status+"\n---\n"), 0o644); err != nil {
		t.Fatal(err)
	}
}

func Test_StateCmd_Usage_ListsLedgerSubcommands(t *testing.T) {
	ws := mkWorkspace(t, "")
	_, _, stderr := runCmd(t, ws) // no args → usage on stderr
	for _, sub := range []string{"ledger-set", "reconcile"} {
		if !strings.Contains(stderr, sub) {
			t.Errorf("usage missing %q; stderr=%q", sub, stderr)
		}
	}
}

func Test_StateCmd_Reconcile_PrintsDoneAndMemberLines(t *testing.T) {
	ws := mkWorkspace(t, "")
	writeLedgerFile(t, ws, "## design D\n\n### ./api\nspec: 0007-a\n\n### ./web\nspec: 0012-b\n")
	writeMemberSpec(t, ws, "./api", "0007-a", "closed")
	writeMemberSpec(t, ws, "./web", "0012-b", "in-progress")
	code, stdout, stderr := runCmd(t, ws, "reconcile", "D")
	if code != 0 {
		t.Fatalf("exit=%d stderr=%s", code, stderr)
	}
	for _, want := range []string{"done: false", "closed\t./api\t0007-a", "in-progress\t./web\t0012-b"} {
		if !strings.Contains(stdout, want) {
			t.Errorf("stdout missing %q; got:\n%s", want, stdout)
		}
	}
}

func Test_StateCmd_Reconcile_BlockedMemberPrintsLiteralBlocked(t *testing.T) {
	ws := mkWorkspace(t, "")
	// ./x's spec resolves in neither location → blocked.
	writeLedgerFile(t, ws, "## design D\n\n### ./x\nspec: 0099-z\n")
	code, stdout, _ := runCmd(t, ws, "reconcile", "D")
	if code != 0 {
		t.Fatalf("exit=%d", code)
	}
	if !strings.Contains(stdout, "blocked\t./x\t0099-z") || !strings.Contains(stdout, "done: false") {
		t.Errorf("want a literal 'blocked' line + done:false; got:\n%s", stdout)
	}
}

func Test_StateCmd_Reconcile_AbsentDesign_DoneTrue_NoLines(t *testing.T) {
	ws := mkWorkspace(t, "")
	writeLedgerFile(t, ws, "## design D\n\n### ./api\nspec: 0007-a\n")
	code, stdout, _ := runCmd(t, ws, "reconcile", "ZZ-absent")
	if code != 0 {
		t.Fatalf("exit=%d", code)
	}
	if strings.TrimSpace(stdout) != "done: true" {
		t.Errorf("absent design ⇒ 'done: true' with no member lines; got %q", stdout)
	}
}

func Test_StateCmd_Reconcile_MalformedLedger_NonZero_NothingOnStdout(t *testing.T) {
	ws := mkWorkspace(t, "")
	writeLedgerFile(t, ws, "### ./x\nspec: 0007-a\n") // member before design
	code, stdout, stderr := runCmd(t, ws, "reconcile", "D")
	if code == 0 {
		t.Fatal("malformed ledger must exit non-zero")
	}
	if stdout != "" {
		t.Errorf("nothing must go to stdout on failure, got %q", stdout)
	}
	if !strings.Contains(stderr, "ledger.md:") {
		t.Errorf("stderr must carry the ledger.md: prefix, got %q", stderr)
	}
}
