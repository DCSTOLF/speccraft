package speccraft

import (
	"bytes"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func fixLedgerNow(t *testing.T, date string) {
	t.Helper()
	prev := ledgerNow
	ledgerNow = func() time.Time {
		tm, _ := time.Parse("2006-01-02", date)
		return tm
	}
	t.Cleanup(func() { ledgerNow = prev })
}

func Test_SetLedgerField_CreatesAndRoundTrips(t *testing.T) {
	fixLedgerNow(t, "2026-07-28")
	p := filepath.Join(t.TempDir(), "ledger.md")
	for _, s := range [][4]string{
		{"d1", "./api", "spec", "0007-a"},
		{"d1", "./api", "in_flight", "{phase: plan}"}, // interior ": "
		{"d1", "./web", "blocked", "RED at validate"},
	} {
		if err := SetLedgerField(p, s[0], s[1], s[2], s[3]); err != nil {
			t.Fatalf("SetLedgerField(%v): %v", s, err)
		}
	}
	l, err := ParseLedger(p)
	if err != nil {
		t.Fatalf("ParseLedger: %v", err)
	}
	if len(l.Designs) != 1 || l.Designs[0].ID != "d1" || len(l.Designs[0].Members) != 2 {
		t.Fatalf("ledger = %+v", l)
	}
	api := l.Designs[0].Members[0]
	if api.Spec != "0007-a" || api.InFlight != "{phase: plan}" || api.Updated != "2026-07-28" {
		t.Errorf("api = %+v", api)
	}
	web := l.Designs[0].Members[1]
	if web.Blocked != "RED at validate" || web.Updated != "2026-07-28" {
		t.Errorf("web = %+v", web)
	}
}

func Test_SetLedgerField_CanonicalLayout_Golden(t *testing.T) {
	fixLedgerNow(t, "2026-07-28")
	p := filepath.Join(t.TempDir(), "ledger.md")
	if err := SetLedgerField(p, "d", "./m", "spec", "0009-x"); err != nil {
		t.Fatal(err)
	}
	got, _ := os.ReadFile(p)
	want := "# Ledger\n\n## design d\n\n### ./m\nspec: 0009-x\nlast_completed_phase:\nin_flight:\nblocked:\nupdated: 2026-07-28\n"
	if string(got) != want {
		t.Errorf("golden mismatch:\n got=%q\nwant=%q", got, want)
	}
}

func Test_SetLedgerField_ByteStable_XtoYtoX(t *testing.T) {
	fixLedgerNow(t, "2026-07-28")
	p := filepath.Join(t.TempDir(), "ledger.md")
	SetLedgerField(p, "d", "./m", "spec", "0009-x")
	first, _ := os.ReadFile(p)
	SetLedgerField(p, "d", "./m", "spec", "0009-y")
	SetLedgerField(p, "d", "./m", "spec", "0009-x")
	third, _ := os.ReadFile(p)
	if !bytes.Equal(first, third) {
		t.Errorf("equivalent states must be byte-identical:\n first=%q\n third=%q", first, third)
	}
}

func Test_SetLedgerField_ResetSameValue_ByteIdenticalNoop(t *testing.T) {
	fixLedgerNow(t, "2026-07-28")
	p := filepath.Join(t.TempDir(), "ledger.md")
	SetLedgerField(p, "d", "./m", "spec", "0009-x")
	before, _ := os.ReadFile(p)
	if err := SetLedgerField(p, "d", "./m", "spec", "0009-x"); err != nil {
		t.Fatal(err)
	}
	after, _ := os.ReadFile(p)
	if !bytes.Equal(before, after) {
		t.Errorf("re-setting same value must be a byte-identical no-op")
	}
}

func Test_SetLedgerField_InvalidField_LeavesFileUnchanged(t *testing.T) {
	fixLedgerNow(t, "2026-07-28")
	p := filepath.Join(t.TempDir(), "ledger.md")
	// Absent file: 'updated' (conductor-managed) and an unknown field must error and NOT create it.
	if err := SetLedgerField(p, "d", "./m", "updated", "2020-01-01"); err == nil {
		t.Error("want error setting conductor-managed 'updated'")
	}
	if err := SetLedgerField(p, "d", "./m", "bogus", "x"); err == nil {
		t.Error("want error for unknown field")
	}
	if _, err := os.Stat(p); !os.IsNotExist(err) {
		t.Error("file must not be created on an invalid field")
	}
	// Existing file: an invalid field leaves bytes unchanged.
	SetLedgerField(p, "d", "./m", "spec", "0009-x")
	before, _ := os.ReadFile(p)
	SetLedgerField(p, "d", "./m", "updated", "2020-01-01")
	after, _ := os.ReadFile(p)
	if !bytes.Equal(before, after) {
		t.Error("invalid field must leave an existing file unchanged")
	}
}
