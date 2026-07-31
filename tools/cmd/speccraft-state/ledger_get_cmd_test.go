package main

import (
	"strings"
	"testing"
)

// Spec 0043 T1 (AC2) — `speccraft-state ledger-get [<design>]` raw-dump oracle.
// RED before implementation: the subcommand is unknown, so run() returns non-zero
// with nothing on stdout (the run()-seam contract → override budget 0).

func Test_StateCmd_LedgerGet_AbsentLedger_ZeroLinesExitZero(t *testing.T) {
	ws := mkWorkspace(t, "") // workspace root, no ledger.md written
	code, stdout, stderr := runCmd(t, ws, "ledger-get")
	if code != 0 {
		t.Fatalf("absent ledger must exit 0; code=%d stderr=%s", code, stderr)
	}
	if strings.TrimSpace(stdout) != "" {
		t.Errorf("absent ledger ⇒ zero lines; got %q", stdout)
	}
}

func Test_StateCmd_LedgerGet_DumpsRawRows_AllDesigns(t *testing.T) {
	ws := mkWorkspace(t, "")
	writeLedgerFile(t, ws,
		"# Ledger\n\n"+
			"## design D1\n\n"+
			"### ./api\nspec: 0007-a\nlast_completed_phase: planned\nin_flight: implement\nblocked:\n\n"+
			"## design D2\n\n"+
			"### ./web\nspec: 0012-b\nlast_completed_phase: reviewed\nin_flight:\nblocked: waiting-on-api\n")
	code, stdout, stderr := runCmd(t, ws, "ledger-get")
	if code != 0 {
		t.Fatalf("exit=%d stderr=%s", code, stderr)
	}
	// <design>\t<member>\t<spec>\t<last_completed_phase>\t<in_flight>\t<blocked>
	wantAPI := strings.Join([]string{"D1", "./api", "0007-a", "planned", "implement", ""}, "\t")
	wantWeb := strings.Join([]string{"D2", "./web", "0012-b", "reviewed", "", "waiting-on-api"}, "\t")
	for _, want := range []string{wantAPI, wantWeb} {
		if !lineExactlyPresent(stdout, want) {
			t.Errorf("stdout missing exact line %q; got:\n%s", want, stdout)
		}
	}
}

func Test_StateCmd_LedgerGet_DesignFilter_OnlyThatDesign(t *testing.T) {
	ws := mkWorkspace(t, "")
	writeLedgerFile(t, ws,
		"# Ledger\n\n"+
			"## design D1\n\n### ./api\nspec: 0007-a\nlast_completed_phase: planned\nin_flight:\nblocked:\n\n"+
			"## design D2\n\n### ./web\nspec: 0012-b\nlast_completed_phase: reviewed\nin_flight:\nblocked:\n")
	code, stdout, stderr := runCmd(t, ws, "ledger-get", "D2")
	if code != 0 {
		t.Fatalf("exit=%d stderr=%s", code, stderr)
	}
	if strings.Contains(stdout, "./api") {
		t.Errorf("design filter D2 must exclude D1's ./api; got:\n%s", stdout)
	}
	if !strings.Contains(stdout, "D2\t./web\t0012-b\treviewed") {
		t.Errorf("design filter D2 must emit ./web; got:\n%s", stdout)
	}
}

func Test_StateCmd_LedgerGet_MalformedLedger_NonZero_NothingOnStdout(t *testing.T) {
	ws := mkWorkspace(t, "")
	writeLedgerFile(t, ws, "### ./x\nspec: 0007-a\n") // member before any design → parse error
	code, stdout, stderr := runCmd(t, ws, "ledger-get")
	if code == 0 {
		t.Fatal("parse-corrupt ledger must exit non-zero")
	}
	if stdout != "" {
		t.Errorf("nothing on stdout on parse failure; got %q", stdout)
	}
	if !strings.Contains(stderr, "ledger.md:") {
		t.Errorf("stderr should carry the ledger parse error; got %q", stderr)
	}
}

func Test_StateCmd_Usage_ListsLedgerGet(t *testing.T) {
	ws := mkWorkspace(t, "")
	_, _, stderr := runCmd(t, ws) // no args → usage
	if !strings.Contains(stderr, "ledger-get") {
		t.Errorf("usage missing ledger-get; stderr=%q", stderr)
	}
}

// lineExactlyPresent reports whether stdout contains a line byte-equal to want
// (so an empty trailing tab-field is actually asserted, not swallowed).
func lineExactlyPresent(stdout, want string) bool {
	for _, ln := range strings.Split(stdout, "\n") {
		if ln == want {
			return true
		}
	}
	return false
}
