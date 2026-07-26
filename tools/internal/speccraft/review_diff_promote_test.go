package speccraft

// Spec 0035 T10 (AC11) — the read-before-overwrite transaction. Behavioral
// oracle: after ReviewDiff(promote=true) on a CHANGED spec, base_fingerprint must
// equal the sha256 of the OLD snapshot (proving the old snapshot was read/
// fingerprinted BEFORE it was overwritten), and the on-disk snapshot must equal
// the current spec bytes (the diffed image written once). If promotion wrote the
// new snapshot before reading the old, base_fingerprint would equal the new bytes.

import (
	"os"
	"path/filepath"
	"testing"
)

func Test_ReviewDiff_Promote_ReadsOldSnapshotBeforeWritingNew(t *testing.T) {
	dir := seedSpec(t, "OLD\n")
	if _, err := WriteReviewSnapshot(dir); err != nil {
		t.Fatalf("seed snapshot: %v", err)
	}
	if err := os.WriteFile(filepath.Join(dir, "spec.md"), []byte("NEW\n"), 0o644); err != nil {
		t.Fatalf("rewrite spec: %v", err)
	}
	env, err := ReviewDiff(dir, true)
	if err != nil {
		t.Fatalf("ReviewDiff promote: %v", err)
	}
	if env.BaseFingerprint == nil || *env.BaseFingerprint != sha256hex("OLD\n") {
		t.Errorf("base_fingerprint = %v, want sha256(OLD) — old snapshot must be read before overwrite", env.BaseFingerprint)
	}
	snap, _ := os.ReadFile(filepath.Join(dir, "review-snapshot.md"))
	if string(snap) != "NEW\n" {
		t.Errorf("promoted snapshot = %q, want NEW (the diffed image)", snap)
	}
}

func Test_ReviewDiff_Promote_WritesDiffedByteImageOnce(t *testing.T) {
	content := "# Spec\n\n## Why\n\nbody\n"
	dir := seedSpec(t, content)
	if _, err := ReviewDiff(dir, true); err != nil { // first review, promote establishes baseline
		t.Fatalf("ReviewDiff promote: %v", err)
	}
	snap, err := os.ReadFile(filepath.Join(dir, "review-snapshot.md"))
	if err != nil {
		t.Fatalf("read snapshot: %v", err)
	}
	if string(snap) != content {
		t.Errorf("snapshot = %q, want %q", snap, content)
	}
	// No leftover temp files.
	entries, _ := os.ReadDir(dir)
	for _, e := range entries {
		if filepath.Ext(e.Name()) == ".tmp" {
			t.Errorf("leftover temp file: %s", e.Name())
		}
	}
}

func Test_ReviewDiff_NoPromote_DoesNotWriteSnapshot(t *testing.T) {
	dir := seedSpec(t, "OLD\n")
	if _, err := WriteReviewSnapshot(dir); err != nil {
		t.Fatalf("seed snapshot: %v", err)
	}
	if err := os.WriteFile(filepath.Join(dir, "spec.md"), []byte("NEW\n"), 0o644); err != nil {
		t.Fatalf("rewrite spec: %v", err)
	}
	if _, err := ReviewDiff(dir, false); err != nil {
		t.Fatalf("ReviewDiff: %v", err)
	}
	snap, _ := os.ReadFile(filepath.Join(dir, "review-snapshot.md"))
	if string(snap) != "OLD\n" {
		t.Errorf("read-only review-diff modified the snapshot: %q, want OLD", snap)
	}
}
