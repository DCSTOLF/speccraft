package speccraft_test

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/dcstolf/speccraft/tools/internal/speccraft"
)

func TestIsTestFile(t *testing.T) {
	cases := []struct {
		path string
		want bool
	}{
		// Go
		{"pkg/foo/bar_test.go", true},
		{"pkg/foo/bar.go", false},
		{"pkg/foo/bar.go.bak", false},
		{"/abs/path/handler_test.go", true},
		// Python
		{"pkg/foo/test_bar.py", true},
		{"pkg/foo/bar_test.py", true},
		{"pkg/foo/bar.py", false},
		{"/abs/path/test_handler.py", true},
		{"/abs/path/conftest.py", false},
	}
	for _, c := range cases {
		got := speccraft.IsTestFile(c.path)
		if got != c.want {
			t.Errorf("IsTestFile(%q) = %v, want %v", c.path, got, c.want)
		}
	}
}

func TestIsProductionPythonFile(t *testing.T) {
	cases := []struct {
		path string
		want bool
	}{
		{"src/foo/bar.py", true},
		{"src/foo/conftest.py", true},
		{"src/foo/test_bar.py", false},
		{"src/foo/bar_test.py", false},
		{"src/foo/bar.go", false},
		{"src/foo/bar.js", false},
	}
	for _, c := range cases {
		got := speccraft.IsProductionPythonFile(c.path)
		if got != c.want {
			t.Errorf("IsProductionPythonFile(%q) = %v, want %v", c.path, got, c.want)
		}
	}
}

func touch(t *testing.T, path string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, nil, 0o644); err != nil {
		t.Fatal(err)
	}
}

func TestSiblingTestFiles_GoUnchanged(t *testing.T) {
	root := t.TempDir()
	touch(t, filepath.Join(root, "pkg", "foo", "bar_test.go"))
	touch(t, filepath.Join(root, "pkg", "foo", "other_test.go"))

	got, err := speccraft.SiblingTestFiles(filepath.Join(root, "pkg", "foo", "bar.go"), root, nil)
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 2 {
		t.Errorf("expected 2 Go siblings, got %d: %v", len(got), got)
	}
}

func TestSiblingTestFiles_PythonSameDirFound(t *testing.T) {
	root := t.TempDir()
	sibling := filepath.Join(root, "src", "foo", "test_bar.py")
	touch(t, sibling)

	got, err := speccraft.SiblingTestFiles(filepath.Join(root, "src", "foo", "bar.py"), root, []string{"tests"})
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 1 || got[0] != sibling {
		t.Errorf("got %v, want [%s]", got, sibling)
	}
}

func TestSiblingTestFiles_PythonRootFallback(t *testing.T) {
	root := t.TempDir()
	// No same-dir sibling; test file lives in tests/ tree.
	deep := filepath.Join(root, "tests", "foo", "test_bar.py")
	touch(t, deep)

	got, err := speccraft.SiblingTestFiles(filepath.Join(root, "src", "foo", "bar.py"), root, []string{"tests"})
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 1 || got[0] != deep {
		t.Errorf("got %v, want [%s]", got, deep)
	}
}

func TestSiblingTestFiles_PythonSameDirTakesPrecedence(t *testing.T) {
	root := t.TempDir()
	samedir := filepath.Join(root, "src", "foo", "test_bar.py")
	touch(t, samedir)
	touch(t, filepath.Join(root, "tests", "test_bar.py")) // should be ignored

	got, err := speccraft.SiblingTestFiles(filepath.Join(root, "src", "foo", "bar.py"), root, []string{"tests"})
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 1 || got[0] != samedir {
		t.Errorf("got %v, want same-dir sibling only [%s]", got, samedir)
	}
}

func TestSiblingTestFiles_PythonNoRoots(t *testing.T) {
	root := t.TempDir()
	touch(t, filepath.Join(root, "tests", "test_bar.py"))

	got, err := speccraft.SiblingTestFiles(filepath.Join(root, "src", "foo", "bar.py"), root, nil)
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 0 {
		t.Errorf("expected empty without testRoots, got %v", got)
	}
}

func TestSiblingTestFiles_PythonRootMissingDir(t *testing.T) {
	root := t.TempDir()
	// "tests" dir doesn't exist — should not error.
	got, err := speccraft.SiblingTestFiles(filepath.Join(root, "src", "foo", "bar.py"), root, []string{"tests"})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(got) != 0 {
		t.Errorf("expected empty for missing root, got %v", got)
	}
}

func TestIsAlwaysAllowed(t *testing.T) {
	root := "/repo"
	cases := []struct {
		path string
		want bool
	}{
		{"/repo/.speccraft/guardrails.md", true},
		{"/repo/specs/0001-foo/spec.md", true},
		{"/repo/docs/README.md", true},
		{"/repo/scratch/exp.go", true},
		{"/repo/README.md", true},
		{"/repo/internal/foo/bar.go", false},
		{"/other/path/file.go", true}, // outside root → always allow
	}
	for _, c := range cases {
		got := speccraft.IsAlwaysAllowed(root, c.path)
		if got != c.want {
			t.Errorf("IsAlwaysAllowed(%q) = %v, want %v", c.path, got, c.want)
		}
	}
}
