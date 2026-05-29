package speccraft_test

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/dcstolf/speccraft/tools/internal/speccraft"
)

// writeFile creates a file and any missing parent dirs in root.
func writeFile(t *testing.T, root, relPath, content string) {
	t.Helper()
	full := filepath.Join(root, filepath.FromSlash(relPath))
	if err := os.MkdirAll(filepath.Dir(full), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(full, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}

func mkDir(t *testing.T, root, relPath string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Join(root, filepath.FromSlash(relPath)), 0o755); err != nil {
		t.Fatal(err)
	}
}

func TestRustStemMapping_TestsFooMapsToSrcFoo(t *testing.T) {
	root := t.TempDir()
	writeFile(t, root, "src/foo.rs", "// prod\n")
	got := speccraft.RustProdForTest("tests/foo.rs", root)
	if got != "src/foo.rs" {
		t.Errorf("got %q, want %q", got, "src/foo.rs")
	}
}

func TestRustStemMapping_TestsFooMapsToSrcFooModRs(t *testing.T) {
	root := t.TempDir()
	writeFile(t, root, "src/foo/mod.rs", "// prod\n")
	got := speccraft.RustProdForTest("tests/foo.rs", root)
	if got != "src/foo/mod.rs" {
		t.Errorf("got %q, want %q", got, "src/foo/mod.rs")
	}
}

func TestRustStemMapping_TestsFooMapsToSrcFooDir(t *testing.T) {
	root := t.TempDir()
	writeFile(t, root, "src/foo.rs", "// prod\n")
	mkDir(t, root, "src/foo")
	got := speccraft.RustProdForTest("tests/foo.rs", root)
	if got == "" {
		t.Fatalf("got empty; expected a valid mapping")
	}
	if _, err := os.Stat(filepath.Join(root, got)); err != nil {
		t.Errorf("mapped path %q does not exist", got)
	}
}

func TestRustStemMapping_LibRsNotMapped(t *testing.T) {
	root := t.TempDir()
	writeFile(t, root, "src/lib.rs", "// crate root\n")
	got := speccraft.RustProdForTest("tests/lib.rs", root)
	if got != "" {
		t.Errorf("got %q, want empty (lib.rs is not a stem-mapping target)", got)
	}
}

func TestRustStemMapping_NoMatchingProd(t *testing.T) {
	root := t.TempDir()
	mkDir(t, root, "src")
	got := speccraft.RustProdForTest("tests/orphan.rs", root)
	if got != "" {
		t.Errorf("got %q, want empty", got)
	}
}

func TestRustStemMapping_NonTestsPath_ReturnsEmpty(t *testing.T) {
	root := t.TempDir()
	writeFile(t, root, "src/foo.rs", "// prod\n")
	got := speccraft.RustProdForTest("src/foo.rs", root)
	if got != "" {
		t.Errorf("got %q, want empty (only tests/<stem>.rs is mapped)", got)
	}
}
