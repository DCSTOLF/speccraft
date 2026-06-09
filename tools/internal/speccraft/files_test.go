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

func TestIsJSTSTestFile_SuffixPatterns(t *testing.T) {
	cases := []struct {
		path string
		want bool
	}{
		// .test.* variants
		{"src/foo.test.js", true},
		{"src/foo.test.ts", true},
		{"src/foo.test.jsx", true},
		{"src/foo.test.tsx", true},
		{"src/foo.test.mjs", true},
		{"src/foo.test.cjs", true},
		{"src/foo.test.mts", true},
		{"src/foo.test.cts", true},
		// .spec.* variants
		{"src/foo.spec.js", true},
		{"src/foo.spec.ts", true},
		{"src/foo.spec.jsx", true},
		{"src/foo.spec.tsx", true},
		{"src/foo.spec.mjs", true},
		{"src/foo.spec.cjs", true},
		{"src/foo.spec.mts", true},
		{"src/foo.spec.cts", true},
		// negative: production files
		{"src/foo.ts", false},
		{"src/foo.js", false},
		{"src/foo.tsx", false},
		// negative: close misses
		{"src/foo.specs.ts", false},  // .specs.ts ≠ .spec.ts
		{"src/types.d.ts", false},    // declaration file
		{"src/types.d.mts", false},   // declaration file
		{"src/types.d.cts", false},   // declaration file
	}
	for _, c := range cases {
		got := speccraft.IsJSTSTestFile(c.path)
		if got != c.want {
			t.Errorf("IsJSTSTestFile(%q) = %v, want %v", c.path, got, c.want)
		}
	}
}

func TestIsJSTSTestFile_TestsDirectorySegment(t *testing.T) {
	cases := []struct {
		path string
		want bool
	}{
		{"src/__tests__/foo.test.ts", true},
		{"__tests__/bar.js", true},
		{"lib/__tests__/baz.mts", true},
		{"pkg/__tests__/sub/q.tsx", true},
		// negative: filename contains __tests__ but is not a segment
		{"__tests__.ts", false},
		// negative: directory name contains __tests__ but is not exact
		{"src/my__tests__dir/foo.ts", false},
	}
	for _, c := range cases {
		got := speccraft.IsJSTSTestFile(c.path)
		if got != c.want {
			t.Errorf("IsJSTSTestFile(%q) = %v, want %v", c.path, got, c.want)
		}
	}
}

func TestIsJSTSTestFile_NodeModulesDistExcluded(t *testing.T) {
	cases := []struct {
		path string
		want bool
	}{
		// excluded
		{"node_modules/jest/build/index.js", false},
		{"node_modules/pkg/__tests__/foo.test.ts", false},
		{"dist/bundle.test.js", false},
		{"pkg/dist/foo.test.ts", false},
		// NOT excluded (non-exact segment)
		{"src/distribution/foo.test.ts", true},
		{"src/distutils/__tests__/foo.ts", true},
	}
	for _, c := range cases {
		got := speccraft.IsJSTSTestFile(c.path)
		if got != c.want {
			t.Errorf("IsJSTSTestFile(%q) = %v, want %v", c.path, got, c.want)
		}
	}
}

func TestIsProductionJSTSFile_AcceptsProductionExtensions(t *testing.T) {
	cases := []struct {
		path string
		want bool
	}{
		// positive
		{"src/index.ts", true},
		{"src/utils.mjs", true},
		{"lib/helpers.cts", true},
		{"app/main.jsx", true},
		{"src/foo.cjs", true},
		{"src/foo.mts", true},
		{"src/foo.js", true},
		{"src/foo.tsx", true},
		// negative: test files
		{"src/foo.test.ts", false},
		{"src/__tests__/foo.ts", false},
		// negative: excluded paths
		{"node_modules/x/index.js", false},
		{"dist/bundle.js", false},
		// negative: declaration files
		{"src/types.d.ts", false},
		{"src/types.d.mts", false},
		{"src/types.d.cts", false},
		// negative: non-JS/TS
		{"src/README.md", false},
	}
	for _, c := range cases {
		got := speccraft.IsProductionJSTSFile(c.path)
		if got != c.want {
			t.Errorf("IsProductionJSTSFile(%q) = %v, want %v", c.path, got, c.want)
		}
	}
}

func TestIsTestFile_DelegatesToJSTS(t *testing.T) {
	cases := []struct {
		path string
		want bool
	}{
		// JS/TS test files now recognized
		{"src/foo.test.ts", true},
		{"src/foo.spec.js", true},
		{"src/__tests__/bar.tsx", true},
		// existing Go/Python still work
		{"pkg/foo/bar_test.go", true},
		{"pkg/foo/test_bar.py", true},
		// negative
		{"src/foo.ts", false},
		{"src/types.d.ts", false},
	}
	for _, c := range cases {
		got := speccraft.IsTestFile(c.path)
		if got != c.want {
			t.Errorf("IsTestFile(%q) = %v, want %v", c.path, got, c.want)
		}
	}
}

func TestIsJSTSTestFile_NonTestEdgeCases(t *testing.T) {
	// AC #11 edge cases
	testCases := []struct {
		path       string
		wantIsTest bool
		wantIsProd bool
	}{
		{"src/foo.specs.ts", false, true},   // .specs.ts ≠ .spec.ts → production
		{"src/types.d.ts", false, false},    // declaration → neither
		{"src/types.d.mts", false, false},   // declaration → neither
		{"src/types.d.cts", false, false},   // declaration → neither
		{"__tests__.ts", false, true},       // filename, not segment → production
	}
	for _, c := range testCases {
		gotTest := speccraft.IsJSTSTestFile(c.path)
		gotProd := speccraft.IsProductionJSTSFile(c.path)
		if gotTest != c.wantIsTest {
			t.Errorf("IsJSTSTestFile(%q) = %v, want %v", c.path, gotTest, c.wantIsTest)
		}
		if gotProd != c.wantIsProd {
			t.Errorf("IsProductionJSTSFile(%q) = %v, want %v", c.path, gotProd, c.wantIsProd)
		}
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
