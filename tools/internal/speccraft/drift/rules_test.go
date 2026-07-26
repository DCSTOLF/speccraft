package drift_test

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/dcstolf/speccraft/tools/internal/speccraft/drift"
)

func makeRepo(t *testing.T, guardrails string) string {
	t.Helper()
	tmp := t.TempDir()
	dir := filepath.Join(tmp, ".speccraft")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	if guardrails != "" {
		if err := os.WriteFile(filepath.Join(dir, "guardrails.md"), []byte(guardrails), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	return tmp
}

// Spec 0035 AC10 — a review-snapshot.md under specs/ byte-copies spec.md prose
// (possibly including `enforce:` directives) and must NOT trip drift. The scan
// scope excludes specs/**, verified via the same LoadRules+CheckAll/CheckFile the
// speccraft-drift hook invokes.

func Test_CheckFile_SpecsPath_Excluded(t *testing.T) {
	root := makeRepo(t, `# Guardrails
## X
<!-- enforce: regex pattern="FORBIDDEN_TOKEN" -->
`)
	rules, err := drift.LoadRules(root)
	if err != nil {
		t.Fatal(err)
	}
	specFile := filepath.Join(root, "specs", "0035-re-review", "review-snapshot.md")
	if err := os.MkdirAll(filepath.Dir(specFile), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(specFile, []byte("a snapshot line with FORBIDDEN_TOKEN inside\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	v, err := drift.CheckFile(specFile, root, rules)
	if err != nil {
		t.Fatal(err)
	}
	if len(v) != 0 {
		t.Errorf("specs/ file scanned by drift: got %d violations, want 0", len(v))
	}
	// Control: the same content OUTSIDE specs/ is still flagged.
	ctrl := filepath.Join(root, "src.md")
	if err := os.WriteFile(ctrl, []byte("FORBIDDEN_TOKEN\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	vc, _ := drift.CheckFile(ctrl, root, rules)
	if len(vc) == 0 {
		t.Errorf("control file outside specs/ should be flagged")
	}
}

func Test_CheckAll_ExcludesSpecsTree_SnapshotEnforceProseDoesNotTrip(t *testing.T) {
	root := makeRepo(t, `# Guardrails
## X
<!-- enforce: regex pattern="FORBIDDEN_TOKEN" -->
`)
	specFile := filepath.Join(root, "specs", "0035-re-review", "review-snapshot.md")
	if err := os.MkdirAll(filepath.Dir(specFile), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(specFile, []byte("FORBIDDEN_TOKEN copied from spec prose\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	rules, err := drift.LoadRules(root)
	if err != nil {
		t.Fatal(err)
	}
	vs, err := drift.CheckAll(root, rules)
	if err != nil {
		t.Fatal(err)
	}
	for _, v := range vs {
		if strings.Contains(filepath.ToSlash(v.File), "/specs/") {
			t.Errorf("drift scanned the specs/ tree: %s", v.File)
		}
	}
}

func Test_CheckFile_SpecsPrefix_NoViolations(t *testing.T) {
	root := makeRepo(t, "# G\n## X\n<!-- enforce: regex pattern=\"NOPE\" -->\n")
	rules, _ := drift.LoadRules(root)
	f := filepath.Join(root, "specs", "0001-a", "review-snapshot.md")
	_ = os.MkdirAll(filepath.Dir(f), 0o755)
	_ = os.WriteFile(f, []byte("NOPE here\n"), 0o644)
	v, err := drift.CheckFile(f, root, rules)
	if err != nil {
		t.Fatal(err)
	}
	if len(v) != 0 {
		t.Errorf("specs/ excluded: got %d, want 0", len(v))
	}
}

func TestParseRules_BasicPattern(t *testing.T) {
	root := makeRepo(t, `# Guardrails

## Security
- No secrets. <!-- enforce: regex pattern="api_key\s*=" -->
`)
	rules, err := drift.LoadRules(root)
	if err != nil {
		t.Fatal(err)
	}
	if len(rules) != 1 {
		t.Fatalf("got %d rules, want 1", len(rules))
	}
	if rules[0].Pattern.String() != `api_key\s*=` {
		t.Errorf("pattern = %q", rules[0].Pattern.String())
	}
	if rules[0].Scope != "" {
		t.Errorf("scope = %q, want empty", rules[0].Scope)
	}
}

func TestParseRules_WithScope(t *testing.T) {
	root := makeRepo(t, `# Guardrails

## Data
- No SQL outside store. <!-- enforce: regex pattern="SELECT" scope="!internal/store/" -->
`)
	rules, err := drift.LoadRules(root)
	if err != nil {
		t.Fatal(err)
	}
	if len(rules) != 1 {
		t.Fatalf("got %d rules, want 1", len(rules))
	}
	if rules[0].Scope != "!internal/store/" {
		t.Errorf("scope = %q", rules[0].Scope)
	}
}

func TestCheckFile_Match(t *testing.T) {
	root := makeRepo(t, `# Guardrails

## Logging
<!-- enforce: regex pattern="fmt\\.Print" scope="!cmd/" -->
`)
	rules, err := drift.LoadRules(root)
	if err != nil {
		t.Fatal(err)
	}

	// File outside cmd/ with fmt.Print → violation.
	badFile := filepath.Join(root, "internal", "foo.go")
	os.MkdirAll(filepath.Dir(badFile), 0o755)
	os.WriteFile(badFile, []byte("package foo\nfunc x() { fmt.Println(\"hi\") }\n"), 0o644)

	vs, err := drift.CheckFile(badFile, root, rules)
	if err != nil {
		t.Fatal(err)
	}
	if len(vs) != 1 {
		t.Errorf("got %d violations, want 1", len(vs))
	}

	// File inside cmd/ → no violation.
	goodFile := filepath.Join(root, "cmd", "main.go")
	os.MkdirAll(filepath.Dir(goodFile), 0o755)
	os.WriteFile(goodFile, []byte("package main\nfmt.Println(\"hi\")\n"), 0o644)

	vs, err = drift.CheckFile(goodFile, root, rules)
	if err != nil {
		t.Fatal(err)
	}
	if len(vs) != 0 {
		t.Errorf("got %d violations in cmd/, want 0", len(vs))
	}
}

func TestCheckFile_NoMatch(t *testing.T) {
	root := makeRepo(t, `# Guardrails

## Security
<!-- enforce: regex pattern="api_key\s*=" -->
`)
	rules, err := drift.LoadRules(root)
	if err != nil {
		t.Fatal(err)
	}

	cleanFile := filepath.Join(root, "main.go")
	os.WriteFile(cleanFile, []byte("package main\nfunc main() {}\n"), 0o644)

	vs, err := drift.CheckFile(cleanFile, root, rules)
	if err != nil {
		t.Fatal(err)
	}
	if len(vs) != 0 {
		t.Errorf("got %d violations, want 0", len(vs))
	}
}
