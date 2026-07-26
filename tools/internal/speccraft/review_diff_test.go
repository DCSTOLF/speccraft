package speccraft

// Spec 0035 T8 (AC3/AC4/AC6) — ReviewDiff envelope skeleton (changed_sections
// content is T16/T17). RED against the T1 stub (returns a zero ReviewEnvelope).

import (
	"crypto/sha256"
	"encoding/hex"
	"os"
	"path/filepath"
	"testing"
)

func sha256hex(s string) string {
	sum := sha256.Sum256([]byte(s))
	return hex.EncodeToString(sum[:])
}

func Test_ReviewDiff_Identical_SnapshotTrue_ChangedFalse_BaseEqualsFingerprint(t *testing.T) {
	content := "# Spec\n\n## Why\n\nx\n"
	dir := seedSpec(t, content)
	if _, err := WriteReviewSnapshot(dir); err != nil {
		t.Fatalf("snapshot: %v", err)
	}
	env, err := ReviewDiff(dir, false)
	if err != nil {
		t.Fatalf("ReviewDiff: %v", err)
	}
	if env.Schema != 1 {
		t.Errorf("schema = %d, want 1", env.Schema)
	}
	if !env.Snapshot || env.Changed {
		t.Errorf("snapshot=%v changed=%v, want true/false", env.Snapshot, env.Changed)
	}
	if env.Diff != "" || len(env.ChangedSections) != 0 {
		t.Errorf("diff/sections not empty: %q / %v", env.Diff, env.ChangedSections)
	}
	if env.BaseFingerprint == nil || *env.BaseFingerprint != env.Fingerprint {
		t.Errorf("base_fingerprint (%v) must equal fingerprint (%q) when identical", env.BaseFingerprint, env.Fingerprint)
	}
}

func Test_ReviewDiff_NoPriorSnapshot_SnapshotFalse_BaseNull(t *testing.T) {
	dir := seedSpec(t, "# Spec\n\n## Why\n\nx\n")
	env, err := ReviewDiff(dir, false)
	if err != nil {
		t.Fatalf("ReviewDiff: %v", err)
	}
	if env.Schema != 1 {
		t.Errorf("schema = %d, want 1", env.Schema)
	}
	if env.Snapshot || env.Changed {
		t.Errorf("snapshot=%v changed=%v, want false/false", env.Snapshot, env.Changed)
	}
	if env.BaseFingerprint != nil {
		t.Errorf("base_fingerprint = %v, want nil on first review", *env.BaseFingerprint)
	}
	if len(env.ChangedSections) != 0 {
		t.Errorf("changed_sections not empty: %v", env.ChangedSections)
	}
}

func Test_ReviewDiff_Fingerprint_IsCurrentBytes_NotOldSnapshot(t *testing.T) {
	dir := seedSpec(t, "OLD\n")
	if _, err := WriteReviewSnapshot(dir); err != nil {
		t.Fatalf("snapshot: %v", err)
	}
	if err := os.WriteFile(filepath.Join(dir, "spec.md"), []byte("NEW\n"), 0o644); err != nil {
		t.Fatalf("rewrite: %v", err)
	}
	env, err := ReviewDiff(dir, false)
	if err != nil {
		t.Fatalf("ReviewDiff: %v", err)
	}
	if !env.Changed {
		t.Errorf("changed = false, want true")
	}
	if env.Fingerprint != sha256hex("NEW\n") {
		t.Errorf("fingerprint = %q, want sha256(NEW)", env.Fingerprint)
	}
	if env.BaseFingerprint == nil || *env.BaseFingerprint != sha256hex("OLD\n") {
		t.Errorf("base_fingerprint = %v, want sha256(OLD)", env.BaseFingerprint)
	}
	if env.Fingerprint == *env.BaseFingerprint {
		t.Errorf("fingerprint must differ from base when changed")
	}
}

func Test_ReviewDiff_UnreadableSpec_Errors(t *testing.T) {
	dir := t.TempDir() // no spec.md
	if _, err := ReviewDiff(dir, false); err == nil {
		t.Errorf("expected error for missing spec.md")
	}
}

func Test_ReviewDiff_SchemaAlwaysOne(t *testing.T) {
	dir := seedSpec(t, "anything\n")
	env, err := ReviewDiff(dir, false)
	if err != nil {
		t.Fatalf("ReviewDiff: %v", err)
	}
	if env.Schema != 1 {
		t.Errorf("schema = %d, want 1", env.Schema)
	}
}
