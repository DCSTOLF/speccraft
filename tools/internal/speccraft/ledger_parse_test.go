package speccraft

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func writeLedger(t *testing.T, content string) string {
	t.Helper()
	dir := t.TempDir()
	p := filepath.Join(dir, "ledger.md")
	if err := os.WriteFile(p, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
	return p
}

func Test_ParseLedger_MultiDesignMultiMember_OrderPreserved(t *testing.T) {
	// Leading BOM + preamble, blank lines, a trailing \r, an interior-": " value,
	// and a spaceless spec:. The BOM is built from bytes to avoid a literal BOM in
	// this source file (illegal in Go source).
	bom := string([]byte{0xef, 0xbb, 0xbf})
	content := bom + "# Ledger\n\n" +
		"## design 0001-foo\n\n" +
		"### ./api\n" +
		"spec: 0007-a\r\n" +
		"last_completed_phase: reviewed\n" +
		"in_flight: {phase: plan}\n" +
		"blocked:\n" +
		"updated: 2026-07-28\n\n" +
		"### ./web\n" +
		"spec:0012-b\n" +
		"blocked: RED at validate\n\n" +
		"## design 0002-bar\n\n" +
		"### ./svc\n" +
		"spec: 0003-c\n"
	got, err := ParseLedger(writeLedger(t, content))
	if err != nil {
		t.Fatalf("ParseLedger: %v", err)
	}
	want := Ledger{Designs: []LedgerDesign{
		{ID: "0001-foo", Members: []LedgerMember{
			{Path: "./api", Spec: "0007-a", LastCompletedPhase: "reviewed", InFlight: "{phase: plan}", Blocked: "", Updated: "2026-07-28"},
			{Path: "./web", Spec: "0012-b", Blocked: "RED at validate"},
		}},
		{ID: "0002-bar", Members: []LedgerMember{
			{Path: "./svc", Spec: "0003-c"},
		}},
	}}
	if len(got.Designs) != len(want.Designs) {
		t.Fatalf("designs = %d, want %d: %+v", len(got.Designs), len(want.Designs), got)
	}
	for di := range want.Designs {
		wd, gd := want.Designs[di], got.Designs[di]
		if gd.ID != wd.ID || len(gd.Members) != len(wd.Members) {
			t.Fatalf("design[%d] = {%q, %d members}, want {%q, %d}", di, gd.ID, len(gd.Members), wd.ID, len(wd.Members))
		}
		for mi := range wd.Members {
			if gd.Members[mi] != wd.Members[mi] {
				t.Errorf("design[%d].member[%d] = %+v, want %+v", di, mi, gd.Members[mi], wd.Members[mi])
			}
		}
	}
}

func Test_ParseLedger_SingleMember_BasicFields(t *testing.T) {
	p := writeLedger(t, "## design d\n\n### ./m\nspec: 0009-x\nlast_completed_phase: planned\n")
	got, err := ParseLedger(p)
	if err != nil {
		t.Fatalf("ParseLedger: %v", err)
	}
	if len(got.Designs) != 1 || len(got.Designs[0].Members) != 1 {
		t.Fatalf("want 1 design/1 member, got %+v", got)
	}
	m := got.Designs[0].Members[0]
	if m.Path != "./m" || m.Spec != "0009-x" || m.LastCompletedPhase != "planned" {
		t.Errorf("member = %+v, want {./m, 0009-x, planned}", m)
	}
}

func Test_ParseLedger_MissingFile_EmptyLedgerNilError(t *testing.T) {
	got, err := ParseLedger(filepath.Join(t.TempDir(), "nope.md"))
	if err != nil {
		t.Fatalf("missing file must be nil error, got %v", err)
	}
	if len(got.Designs) != 0 {
		t.Errorf("missing file must be empty Ledger, got %+v", got)
	}
}

func Test_ParseLedger_FirstWinsOnDuplicateKey(t *testing.T) {
	content := "## design d\n\n### ./m\nspec: first\nspec: second\n"
	got, err := ParseLedger(writeLedger(t, content))
	if err != nil {
		t.Fatalf("ParseLedger: %v", err)
	}
	if got.Designs[0].Members[0].Spec != "first" {
		t.Errorf("Spec = %q, want first (first-wins)", got.Designs[0].Members[0].Spec)
	}
}

func Test_ParseLedger_Errors_Table(t *testing.T) {
	cases := map[string]string{
		"member_before_design":          "### ./m\nspec: x\n",
		"unknown_key":                   "## design d\n### ./m\nfoo: bar\n",
		"key_before_first_member":       "## design d\nspec: x\n",
		"junk_line_in_block":            "## design d\n### ./m\njunkline\n",
		"duplicate_design":              "## design d\n### ./m\n## design d\n### ./n\n",
		"duplicate_member":              "## design d\n### ./m\nspec: x\n### ./m\n",
		"empty_design_id":               "## design\n",
		"non_design_double_heading":     "## foo\n",
		"empty_member_path":             "## design d\n### \nspec: x\n",
		"content_before_first_design":   "notaheading\n## design d\n### ./m\n",
		"junk_between_design_and_member": "## design d\njunk here\n### ./m\n",
	}
	for name, content := range cases {
		t.Run(name, func(t *testing.T) {
			_, err := ParseLedger(writeLedger(t, content))
			if err == nil {
				t.Fatalf("expected parse error, got nil")
			}
			if !strings.Contains(err.Error(), "ledger.md:") {
				t.Errorf("error %q must carry the 'ledger.md:' prefix", err.Error())
			}
		})
	}
}
