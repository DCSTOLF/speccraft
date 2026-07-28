package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func Test_StateCmd_LedgerSet_UpsertsLedgerMd_ExitZero(t *testing.T) {
	ws := mkWorkspace(t, "")
	code, _, stderr := runCmd(t, ws, "ledger-set", "D", "./api", "spec", "0007-a")
	if code != 0 {
		t.Fatalf("exit=%d stderr=%s", code, stderr)
	}
	b, err := os.ReadFile(filepath.Join(ws, ".speccraft", "ledger.md"))
	if err != nil {
		t.Fatalf("ledger.md must be written: %v", err)
	}
	if !strings.Contains(string(b), "spec: 0007-a") {
		t.Errorf("ledger.md missing the upserted field; got:\n%s", b)
	}
}

func Test_StateCmd_LedgerSet_InvalidField_NonZero_NothingWritten(t *testing.T) {
	ws := mkWorkspace(t, "")
	code, _, stderr := runCmd(t, ws, "ledger-set", "D", "./api", "updated", "2020-01-01")
	if code == 0 {
		t.Fatal("setting conductor-managed 'updated' must exit non-zero")
	}
	if stderr == "" {
		t.Error("want a stderr message")
	}
	if _, err := os.Stat(filepath.Join(ws, ".speccraft", "ledger.md")); !os.IsNotExist(err) {
		t.Error("invalid field must write nothing (ledger.md not created)")
	}
}
