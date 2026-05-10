package drift_test

import (
	"os"
	"path/filepath"
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
