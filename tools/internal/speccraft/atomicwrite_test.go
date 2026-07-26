package speccraft

// Spec 0035 T2 (AC1/AC2 shared seam) — AtomicWriteFile: same-directory temp +
// atomic rename. RED against the T1 stub (which writes nothing), failing at
// runtime on the read-back assertions.

import (
	"os"
	"path/filepath"
	"testing"
)

func Test_AtomicWriteFile_WritesBytesAndPerm(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "out.txt")
	want := []byte("hello\nworld\n")
	if err := AtomicWriteFile(path, want, 0o644); err != nil {
		t.Fatalf("AtomicWriteFile: %v", err)
	}
	got, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read back: %v", err)
	}
	if string(got) != string(want) {
		t.Errorf("content = %q, want %q", got, want)
	}
	fi, err := os.Stat(path)
	if err != nil {
		t.Fatalf("stat: %v", err)
	}
	if fi.Mode().Perm() != 0o644 {
		t.Errorf("perm = %v, want 0644", fi.Mode().Perm())
	}
}

func Test_AtomicWriteFile_EmptyData_CreatesEmptyFile(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "empty.txt")
	if err := AtomicWriteFile(path, []byte{}, 0o644); err != nil {
		t.Fatalf("AtomicWriteFile: %v", err)
	}
	fi, err := os.Stat(path)
	if err != nil {
		t.Fatalf("stat: %v", err)
	}
	if fi.Size() != 0 {
		t.Errorf("size = %d, want 0", fi.Size())
	}
}

func Test_AtomicWriteFile_TempIsSameDir_RenameReplaces(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "out.txt")
	if err := os.WriteFile(path, []byte("OLD"), 0o644); err != nil {
		t.Fatalf("seed: %v", err)
	}
	if err := AtomicWriteFile(path, []byte("NEW"), 0o644); err != nil {
		t.Fatalf("AtomicWriteFile: %v", err)
	}
	got, _ := os.ReadFile(path)
	if string(got) != "NEW" {
		t.Errorf("content = %q, want NEW", got)
	}
	// No leftover temp files in the directory.
	entries, _ := os.ReadDir(dir)
	for _, e := range entries {
		if filepath.Ext(e.Name()) == ".tmp" {
			t.Errorf("leftover temp file: %s", e.Name())
		}
	}
}
