package speccraft_test

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/dcstolf/speccraft/tools/internal/speccraft"
)

// AC3: the ledger is a history.md-class memory file — SetLedgerField writes only
// ledger.md and never state.json, so the spec-0012 single-writer rule holds.
func Test_SetLedgerField_WritesOnlyLedgerMd_NeverStateJson(t *testing.T) {
	root := t.TempDir()
	sd := filepath.Join(root, ".speccraft")
	if err := os.MkdirAll(sd, 0o755); err != nil {
		t.Fatal(err)
	}
	ledger := filepath.Join(sd, "ledger.md")
	if err := speccraft.SetLedgerField(ledger, "d", "./m", "spec", "0009-x"); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(ledger); err != nil {
		t.Errorf("ledger.md must be written: %v", err)
	}
	if _, err := os.Stat(filepath.Join(sd, "state.json")); !os.IsNotExist(err) {
		t.Error("SetLedgerField must never create state.json")
	}
}

// Source-scan sibling to state_single_writer_test.go: the ledger write path must
// not reference state.json at all.
func Test_LedgerWritePath_NeverReferencesStateJson(t *testing.T) {
	toolsDir := findRepoRoot(t)
	src, err := os.ReadFile(filepath.Join(toolsDir, "internal", "speccraft", "ledger.go"))
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(src), "state.json") {
		t.Error("ledger.go must not reference state.json (the ledger is a separate memory file)")
	}
}
