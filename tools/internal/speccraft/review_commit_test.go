package speccraft

// Spec 0035 T14 (AC2) — WriteReviewFile: single atomic commit of review.md
// carrying exactly one reviewed_sha256 line. Fault injection via the atomicRename
// seam proves the prior review.md is left byte-unchanged on failure and that no
// fingerprint-free artifact is ever observable at the target path.

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
)

var reviewedSha256Re = regexp.MustCompile(`(?m)^reviewed_sha256: [0-9a-f]{64}$`)

func Test_WriteReviewFile_SingleReviewedSha256Line(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "review.md")
	fp := sha256hex("snapshot-bytes")
	body := []byte("# Review\n\nverdict: approve\n")
	if err := WriteReviewFile(path, body, fp); err != nil {
		t.Fatalf("WriteReviewFile: %v", err)
	}
	got, _ := os.ReadFile(path)
	matches := reviewedSha256Re.FindAllString(string(got), -1)
	if len(matches) != 1 {
		t.Fatalf("reviewed_sha256 lines = %d, want 1\n%s", len(matches), got)
	}
	if matches[0] != "reviewed_sha256: "+fp {
		t.Errorf("line = %q, want carrying %q", matches[0], fp)
	}
	if !strings.Contains(string(got), "verdict: approve") {
		t.Errorf("review body not preserved:\n%s", got)
	}
}

func Test_WriteReviewFile_StripsPriorReviewedSha256(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "review.md")
	oldFp := sha256hex("old")
	newFp := sha256hex("new")
	body := []byte("# Review\n\nreviewed_sha256: " + oldFp + "\n\nverdict: approve\n")
	if err := WriteReviewFile(path, body, newFp); err != nil {
		t.Fatalf("WriteReviewFile: %v", err)
	}
	got, _ := os.ReadFile(path)
	matches := reviewedSha256Re.FindAllString(string(got), -1)
	if len(matches) != 1 || matches[0] != "reviewed_sha256: "+newFp {
		t.Errorf("want exactly one line with new fp, got %v\n%s", matches, got)
	}
}

func Test_WriteReviewFile_Sha256OverSnapshotReproducesRecorded(t *testing.T) {
	dir := seedSpec(t, "# Spec\n\n## Why\n\nx\n")
	fp, err := WriteReviewSnapshot(dir)
	if err != nil {
		t.Fatalf("snapshot: %v", err)
	}
	path := filepath.Join(dir, "review.md")
	if err := WriteReviewFile(path, []byte("# Review\n"), fp); err != nil {
		t.Fatalf("WriteReviewFile: %v", err)
	}
	got, _ := os.ReadFile(path)
	line := reviewedSha256Re.FindString(string(got))
	recorded := strings.TrimPrefix(line, "reviewed_sha256: ")
	snap, _ := os.ReadFile(filepath.Join(dir, "review-snapshot.md"))
	if recorded != fingerprintBytes(snap) {
		t.Errorf("recorded %q != sha256 over review-snapshot.md %q", recorded, fingerprintBytes(snap))
	}
}

func Test_WriteReviewFile_WritesFileWithFingerprint(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "review.md")
	fp := sha256hex("body")
	if err := WriteReviewFile(path, []byte("# R\n"), fp); err != nil {
		t.Fatalf("WriteReviewFile: %v", err)
	}
	got, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("review.md not written: %v", err)
	}
	if !strings.Contains(string(got), "reviewed_sha256: "+fp) {
		t.Errorf("review.md missing fingerprint line:\n%s", got)
	}
}

func Test_WriteReviewFile_RenameFailure_PriorReviewByteIdentical(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "review.md")
	prior := []byte("# Prior Review\n\nreviewed_sha256: " + sha256hex("prior") + "\n")
	if err := os.WriteFile(path, prior, 0o644); err != nil {
		t.Fatal(err)
	}
	orig := atomicRename
	atomicRename = func(_, _ string) error { return fmt.Errorf("injected rename failure") }
	defer func() { atomicRename = orig }()

	err := WriteReviewFile(path, []byte("# New Review\n"), sha256hex("new"))
	if err == nil {
		t.Errorf("expected error on rename failure")
	}
	after, _ := os.ReadFile(path)
	if string(after) != string(prior) {
		t.Errorf("prior review.md not byte-identical after failed commit:\n got %q\nwant %q", after, prior)
	}
}

func Test_WriteReviewFile_MidWrite_NoFingerprintFreeArtifactObserved(t *testing.T) {
	// On a failed commit the target path must never be observed in a state
	// lacking its reviewed_sha256 line: it stays the prior (fingerprint-bearing)
	// file, because the new content is assembled in a temp file and only swapped
	// in atomically.
	dir := t.TempDir()
	path := filepath.Join(dir, "review.md")
	prior := []byte("# Prior\n\nreviewed_sha256: " + sha256hex("prior") + "\n")
	if err := os.WriteFile(path, prior, 0o644); err != nil {
		t.Fatal(err)
	}
	orig := atomicRename
	atomicRename = func(_, _ string) error { return fmt.Errorf("boom") }
	defer func() { atomicRename = orig }()

	_ = WriteReviewFile(path, []byte("# New\n"), sha256hex("new"))
	got, _ := os.ReadFile(path)
	if len(reviewedSha256Re.FindAllString(string(got), -1)) != 1 {
		t.Errorf("target observed without exactly one reviewed_sha256 line:\n%s", got)
	}
	// No stray temp artifact left behind.
	entries, _ := os.ReadDir(dir)
	for _, e := range entries {
		if filepath.Ext(e.Name()) == ".tmp" {
			t.Errorf("leftover temp file: %s", e.Name())
		}
	}
}
