package speccraft_test

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/dcstolf/speccraft/tools/internal/speccraft"
)

func writeConfig(t *testing.T, root, content string) {
	t.Helper()
	dir := filepath.Join(root, ".speccraft")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "speccraft.toml"), []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}

func TestReadConfig_Missing(t *testing.T) {
	cfg := speccraft.ReadConfig(t.TempDir())
	if len(cfg.TDD.TestRoots) != 0 {
		t.Errorf("expected empty TestRoots, got %v", cfg.TDD.TestRoots)
	}
}

func TestReadConfig_SingleRoot(t *testing.T) {
	root := t.TempDir()
	writeConfig(t, root, "[tdd]\ntest_roots = [\"tests\"]\n")
	cfg := speccraft.ReadConfig(root)
	if len(cfg.TDD.TestRoots) != 1 || cfg.TDD.TestRoots[0] != "tests" {
		t.Errorf("TestRoots = %v, want [tests]", cfg.TDD.TestRoots)
	}
}

func TestReadConfig_MultipleRoots(t *testing.T) {
	root := t.TempDir()
	writeConfig(t, root, "[tdd]\ntest_roots = [\"tests\", \"test\"]\n")
	cfg := speccraft.ReadConfig(root)
	want := []string{"tests", "test"}
	if len(cfg.TDD.TestRoots) != len(want) {
		t.Fatalf("TestRoots = %v, want %v", cfg.TDD.TestRoots, want)
	}
	for i, v := range want {
		if cfg.TDD.TestRoots[i] != v {
			t.Errorf("TestRoots[%d] = %q, want %q", i, cfg.TDD.TestRoots[i], v)
		}
	}
}

func TestReadConfig_CommentsAndBlanks(t *testing.T) {
	root := t.TempDir()
	writeConfig(t, root, "# speccraft config\n\n[tdd]\n# roots\ntest_roots = [\"tests\"]\n")
	cfg := speccraft.ReadConfig(root)
	if len(cfg.TDD.TestRoots) != 1 || cfg.TDD.TestRoots[0] != "tests" {
		t.Errorf("TestRoots = %v, want [tests]", cfg.TDD.TestRoots)
	}
}

func TestReadConfig_WrongSection(t *testing.T) {
	root := t.TempDir()
	writeConfig(t, root, "[other]\ntest_roots = [\"tests\"]\n")
	cfg := speccraft.ReadConfig(root)
	if len(cfg.TDD.TestRoots) != 0 {
		t.Errorf("expected empty TestRoots outside [tdd], got %v", cfg.TDD.TestRoots)
	}
}
