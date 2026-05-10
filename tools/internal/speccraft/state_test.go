package speccraft_test

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/dcstolf/speccraft/tools/internal/speccraft"
)

func TestFindRoot(t *testing.T) {
	tmp := t.TempDir()
	specDir := filepath.Join(tmp, ".speccraft")
	if err := os.MkdirAll(specDir, 0o755); err != nil {
		t.Fatal(err)
	}
	subdir := filepath.Join(tmp, "pkg", "foo")
	if err := os.MkdirAll(subdir, 0o755); err != nil {
		t.Fatal(err)
	}
	// Find from subdir.
	root, err := speccraft.FindRoot(subdir)
	if err != nil {
		t.Fatalf("FindRoot: %v", err)
	}
	if root != tmp {
		t.Errorf("FindRoot = %q, want %q", root, tmp)
	}
	// No .speccraft → error.
	noSpec := t.TempDir()
	_, err = speccraft.FindRoot(noSpec)
	if err == nil {
		t.Error("expected error when no .speccraft dir")
	}
}

func TestStateRoundTrip(t *testing.T) {
	tmp := t.TempDir()
	if err := os.MkdirAll(filepath.Join(tmp, ".speccraft"), 0o755); err != nil {
		t.Fatal(err)
	}
	// Load from absent file → zero state.
	s, err := speccraft.LoadState(tmp)
	if err != nil {
		t.Fatal(err)
	}
	if s.Version != 1 {
		t.Errorf("Version = %d, want 1", s.Version)
	}
	// Set and get.
	if err := speccraft.SetField(tmp, "active_spec", "0001-foo"); err != nil {
		t.Fatal(err)
	}
	val, err := speccraft.GetField(tmp, "active_spec")
	if err != nil {
		t.Fatal(err)
	}
	if val != "0001-foo" {
		t.Errorf("active_spec = %q, want %q", val, "0001-foo")
	}
}

func TestTrackEdit(t *testing.T) {
	tmp := t.TempDir()
	if err := os.MkdirAll(filepath.Join(tmp, ".speccraft"), 0o755); err != nil {
		t.Fatal(err)
	}
	testFile := filepath.Join(tmp, "pkg", "foo_test.go")
	prodFile := filepath.Join(tmp, "pkg", "foo.go")

	if err := speccraft.TrackEdit(tmp, testFile); err != nil {
		t.Fatal(err)
	}
	s, _ := speccraft.LoadState(tmp)
	if len(s.Session.EditedTestFiles) != 1 || s.Session.EditedTestFiles[0] != testFile {
		t.Errorf("EditedTestFiles = %v, want [%s]", s.Session.EditedTestFiles, testFile)
	}
	// Dedup: same file twice → still one entry.
	if err := speccraft.TrackEdit(tmp, testFile); err != nil {
		t.Fatal(err)
	}
	s, _ = speccraft.LoadState(tmp)
	if len(s.Session.EditedTestFiles) != 1 {
		t.Errorf("dedup failed: got %d entries", len(s.Session.EditedTestFiles))
	}

	if err := speccraft.TrackEdit(tmp, prodFile); err != nil {
		t.Fatal(err)
	}
	s, _ = speccraft.LoadState(tmp)
	if len(s.Session.EditedProdFiles) != 1 {
		t.Errorf("EditedProdFiles = %v", s.Session.EditedProdFiles)
	}
}

func TestResetSession(t *testing.T) {
	tmp := t.TempDir()
	if err := os.MkdirAll(filepath.Join(tmp, ".speccraft"), 0o755); err != nil {
		t.Fatal(err)
	}
	// Set active spec and some session state.
	speccraft.SetField(tmp, "active_spec", "0001-foo")
	speccraft.TrackEdit(tmp, filepath.Join(tmp, "main_test.go"))

	if err := speccraft.ResetSession(tmp); err != nil {
		t.Fatal(err)
	}
	s, _ := speccraft.LoadState(tmp)
	// Active spec must survive reset.
	if s.ActiveSpec != "0001-foo" {
		t.Errorf("active_spec cleared unexpectedly: %q", s.ActiveSpec)
	}
	// Session fields must be empty.
	if len(s.Session.EditedTestFiles) != 0 {
		t.Errorf("EditedTestFiles not cleared: %v", s.Session.EditedTestFiles)
	}
}

func TestTasksDonePct(t *testing.T) {
	tmp := t.TempDir()
	if err := os.MkdirAll(filepath.Join(tmp, ".speccraft"), 0o755); err != nil {
		t.Fatal(err)
	}
	speccraft.SetField(tmp, "active_spec", "0001-foo")
	specDir := filepath.Join(tmp, "specs", "0001-foo")
	if err := os.MkdirAll(specDir, 0o755); err != nil {
		t.Fatal(err)
	}
	tasks := "- [x] T1\n- [x] T2\n- [ ] T3\n- [ ] T4\n"
	if err := os.WriteFile(filepath.Join(specDir, "tasks.md"), []byte(tasks), 0o644); err != nil {
		t.Fatal(err)
	}
	pct, err := speccraft.TasksDonePct(tmp)
	if err != nil {
		t.Fatal(err)
	}
	if pct != 50 {
		t.Errorf("TasksDonePct = %d, want 50", pct)
	}
}
