package speccraft

// Spec 0035 T4 (AC1) — WriteReviewSnapshot: copy spec.md to review-snapshot.md,
// return sha256 of the raw spec.md bytes, robust no-op on byte-identical, error
// on missing spec.md. RED against the T1 stub (returns "",nil, writes nothing).

import (
	"crypto/sha256"
	"encoding/hex"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func seedSpec(t *testing.T, content string) string {
	t.Helper()
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "spec.md"), []byte(content), 0o644); err != nil {
		t.Fatalf("seed spec.md: %v", err)
	}
	return dir
}

func Test_WriteReviewSnapshot_EqualsSpecBytes(t *testing.T) {
	content := "# Spec\n\n## Why\n\nbecause.\n"
	dir := seedSpec(t, content)
	fp, err := WriteReviewSnapshot(dir)
	if err != nil {
		t.Fatalf("WriteReviewSnapshot: %v", err)
	}
	snap, err := os.ReadFile(filepath.Join(dir, "review-snapshot.md"))
	if err != nil {
		t.Fatalf("read snapshot: %v", err)
	}
	if string(snap) != content {
		t.Errorf("snapshot = %q, want %q", snap, content)
	}
	sum := sha256.Sum256([]byte(content))
	if fp != hex.EncodeToString(sum[:]) {
		t.Errorf("fingerprint = %q, want %q", fp, hex.EncodeToString(sum[:]))
	}
}

func Test_WriteReviewSnapshot_Fingerprint_IsSha256OfRawBytes_NoNormalization(t *testing.T) {
	// CRLF line endings, no trailing newline — the fingerprint must be over the
	// exact raw bytes with zero normalization.
	content := "line1\r\nline2\r\nno-trailing-newline"
	dir := seedSpec(t, content)
	fp, err := WriteReviewSnapshot(dir)
	if err != nil {
		t.Fatalf("WriteReviewSnapshot: %v", err)
	}
	sum := sha256.Sum256([]byte(content))
	if fp != hex.EncodeToString(sum[:]) {
		t.Errorf("fingerprint = %q, want raw-bytes sha256 %q", fp, hex.EncodeToString(sum[:]))
	}
}

func Test_WriteReviewSnapshot_RobustNoop_NoRewriteNoMtimeTouch(t *testing.T) {
	dir := seedSpec(t, "unchanged\n")
	fp1, err := WriteReviewSnapshot(dir)
	if err != nil {
		t.Fatalf("first: %v", err)
	}
	snapPath := filepath.Join(dir, "review-snapshot.md")
	// Backdate the snapshot mtime; a true no-op must NOT touch it.
	old := time.Now().Add(-2 * time.Hour)
	if err := os.Chtimes(snapPath, old, old); err != nil {
		t.Fatalf("chtimes: %v", err)
	}
	before, _ := os.Stat(snapPath)
	fp2, err := WriteReviewSnapshot(dir)
	if err != nil {
		t.Fatalf("second: %v", err)
	}
	after, _ := os.Stat(snapPath)
	if fp1 != fp2 {
		t.Errorf("fingerprint changed on no-op: %q -> %q", fp1, fp2)
	}
	if !before.ModTime().Equal(after.ModTime()) {
		t.Errorf("mtime touched on byte-identical no-op: %v -> %v", before.ModTime(), after.ModTime())
	}
}

func Test_WriteReviewSnapshot_MissingSpec_Errors(t *testing.T) {
	dir := t.TempDir() // no spec.md
	if _, err := WriteReviewSnapshot(dir); err == nil {
		t.Errorf("expected error for missing spec.md, got nil")
	}
}

func Test_WriteReviewSnapshot_OverwritesPriorSnapshotInPlace(t *testing.T) {
	dir := seedSpec(t, "v1\n")
	if _, err := WriteReviewSnapshot(dir); err != nil {
		t.Fatalf("first: %v", err)
	}
	// Change spec.md, snapshot again — the snapshot must reflect the new bytes,
	// overwriting in place (no *-rN proliferation).
	if err := os.WriteFile(filepath.Join(dir, "spec.md"), []byte("v2\n"), 0o644); err != nil {
		t.Fatalf("rewrite spec: %v", err)
	}
	if _, err := WriteReviewSnapshot(dir); err != nil {
		t.Fatalf("second: %v", err)
	}
	snap, _ := os.ReadFile(filepath.Join(dir, "review-snapshot.md"))
	if string(snap) != "v2\n" {
		t.Errorf("snapshot = %q, want v2", snap)
	}
	entries, _ := os.ReadDir(dir)
	for _, e := range entries {
		if e.Name() != "spec.md" && e.Name() != "review-snapshot.md" {
			t.Errorf("unexpected artifact: %s", e.Name())
		}
	}
}
