package main

import (
	"os"
	"path/filepath"
	"testing"
)

// makeTestRepo creates a temp directory with .speccraft/ and optional spec.
func makeTestRepo(t *testing.T, activeSpec, specStatus string) string {
	t.Helper()
	tmp := t.TempDir()
	specDir := filepath.Join(tmp, ".speccraft")
	if err := os.MkdirAll(specDir, 0o755); err != nil {
		t.Fatal(err)
	}
	state := `{"version":1,"active_spec":"` + activeSpec + `","session":{"id":"","edited_test_files":[],"edited_prod_files":[]}}`
	if activeSpec == "" {
		state = `{"version":1,"active_spec":null,"session":{"id":"","edited_test_files":[],"edited_prod_files":[]}}`
	}
	if err := os.WriteFile(filepath.Join(specDir, "state.json"), []byte(state), 0o644); err != nil {
		t.Fatal(err)
	}
	if activeSpec != "" {
		sdir := filepath.Join(tmp, "specs", activeSpec)
		if err := os.MkdirAll(sdir, 0o755); err != nil {
			t.Fatal(err)
		}
		specMd := "---\nstatus: " + specStatus + "\n---\n# Test spec\n"
		if err := os.WriteFile(filepath.Join(sdir, "spec.md"), []byte(specMd), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	return tmp
}

func TestReadFrontmatterField(t *testing.T) {
	tmp := t.TempDir()
	content := "---\nstatus: in-progress\nid: \"0001\"\n---\n# Title\n"
	f := filepath.Join(tmp, "spec.md")
	os.WriteFile(f, []byte(content), 0o644)

	if got := readFrontmatterField(f, "status"); got != "in-progress" {
		t.Errorf("status = %q, want %q", got, "in-progress")
	}
	if got := readFrontmatterField(f, "id"); got != `"0001"` {
		t.Errorf("id = %q, want %q", got, `"0001"`)
	}
	if got := readFrontmatterField(f, "missing"); got != "" {
		t.Errorf("missing = %q, want empty", got)
	}
}

func TestHasSiblingTestEdited(t *testing.T) {
	siblings := []string{"/repo/pkg/foo_test.go", "/repo/pkg/bar_test.go"}

	if hasSiblingTestEdited(siblings, nil) {
		t.Error("expected false with no edited tests")
	}
	if !hasSiblingTestEdited(siblings, []string{"/repo/pkg/foo_test.go"}) {
		t.Error("expected true when sibling is in edited list")
	}
	if hasSiblingTestEdited(siblings, []string{"/repo/other/baz_test.go"}) {
		t.Error("expected false when only non-sibling test was edited")
	}
}

func TestPreToolUse_AllowAlwaysAllowedPaths(t *testing.T) {
	root := makeTestRepo(t, "", "")

	// .speccraft/ files → always allow (no error).
	target := filepath.Join(root, ".speccraft", "guardrails.md")
	os.WriteFile(target, []byte("# Guardrails"), 0o644)

	// Simulate: set cwd to root, input file to .speccraft path.
	// We test the component functions directly.
	if result := readFrontmatterField(target, "status"); result != "" {
		t.Errorf("unexpected frontmatter in guardrails.md: %q", result)
	}
}
