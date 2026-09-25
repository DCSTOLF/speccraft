package speccraft

// Spec 0048 T4.c (AC13) — fault injection for the atomic capture.
//
// This file is `package speccraft` (INTERNAL) while its sibling
// `buildrepair_test.go` is `package speccraft_test`. Mixing the two in one
// directory is legal Go and is deliberate: the injection seam is unexported, and
// exporting a seam purely so an external test can reach it would widen the API
// for a test's convenience.
//
// The seam REUSED here is `atomicRename` from review.go — this package already
// has exactly one save-failure seam, introduced by spec 0035 for
// `WriteReviewFile`. The plan called for a new `injectSaveFailure`; reusing the
// existing one instead keeps a single fault-injection point for the whole
// package, consistent with the conventions' "one shared entrypoint" instinct.
// `saveStateLocked` routes its final rename through it for that reason.

import (
	"errors"
	"os"
	"path/filepath"
	"testing"
)

// AC13 — capture is ALL-OR-NOTHING. A save that fails must leave neither the
// baseline nor the candidates behind: a baseline written without candidates reads
// as "this file never had a red test", which would silently block the next
// production edit.
func Test_CaptureRedCandidates_SaveFailure_LeavesNeitherBaselineNorCandidates(t *testing.T) {
	root := t.TempDir()
	if err := os.MkdirAll(filepath.Join(root, ".speccraft"), 0o755); err != nil {
		t.Fatal(err)
	}
	f := filepath.Join(root, "pkg", "foo_test.go")

	orig := atomicRename
	atomicRename = func(_, _ string) error { return errors.New("injected save failure") }
	defer func() { atomicRename = orig }()

	if _, err := CaptureRedCandidates(root, f, []string{"TestOld"}, []string{"TestOld", "TestNew"}); err == nil {
		t.Error("a failed save must surface an error, never a silent partial capture")
	}

	// Restore the seam before reading back, or the read path would be poisoned too.
	atomicRename = orig

	base, err := GetRedBaseline(root)
	if err != nil {
		t.Fatal(err)
	}
	if len(base) != 0 {
		t.Errorf("baseline persisted despite a failed save: %v", base)
	}
	cands, err := GetRedCandidates(root)
	if err != nil {
		t.Fatal(err)
	}
	if len(cands) != 0 {
		t.Errorf("candidates persisted despite a failed save: %v", cands)
	}
}

// AC3 — a failed record must block, not admit. If the save fails the entry does
// not exist, so allowing the edit would produce exactly the thing "record before
// allow" forbids: an admitted edit with no audit row. The attestation must not be
// left open either, or the next probe would read a repair run that never started.
func Test_RecordBuildRepair_SaveFailure_ReturnsErrorAndWritesNoPartialEntry(t *testing.T) {
	root := t.TempDir()
	if err := os.MkdirAll(filepath.Join(root, ".speccraft"), 0o755); err != nil {
		t.Fatal(err)
	}
	f := filepath.Join(root, "pkg", "prod.go")

	orig := atomicRename
	atomicRename = func(_, _ string) error { return errors.New("injected save failure") }
	if _, err := RecordBuildRepair(root, f, "undefined: foo"); err == nil {
		atomicRename = orig
		t.Fatal("a failed save must surface an error, never a silently unlogged edit")
	}
	atomicRename = orig

	br, err := GetBuildRepair(root)
	if err != nil {
		t.Fatal(err)
	}
	if len(br.Log) != 0 {
		t.Errorf("a failed record must write no partial entry: %+v", br.Log)
	}
	if br.Attestation != nil {
		t.Errorf("a failed record must not leave the attestation open: %+v", br.Attestation)
	}
}

// AC14's state-layer half: a failed capture is recoverable. After the seam is
// restored, the same capture must succeed and record both halves — otherwise a
// transient disk error would wedge the session.
func Test_CaptureRedCandidates_RetryAfterFailure_Recovers(t *testing.T) {
	root := t.TempDir()
	if err := os.MkdirAll(filepath.Join(root, ".speccraft"), 0o755); err != nil {
		t.Fatal(err)
	}
	f := filepath.Join(root, "pkg", "foo_test.go")

	orig := atomicRename
	atomicRename = func(_, _ string) error { return errors.New("injected save failure") }
	_, _ = CaptureRedCandidates(root, f, []string{"TestOld"}, []string{"TestOld", "TestNew"})
	atomicRename = orig

	got, err := CaptureRedCandidates(root, f, []string{"TestOld"}, []string{"TestOld", "TestNew"})
	if err != nil {
		t.Fatalf("retry must recover: %v", err)
	}
	if len(got) != 1 || got[0] != "TestNew" {
		t.Errorf("candidates after retry = %v, want [TestNew]", got)
	}
	base, err := GetRedBaseline(root)
	if err != nil {
		t.Fatal(err)
	}
	if ids := base[NormalizeStateKey(f)]; len(ids) != 1 || ids[0] != "TestOld" {
		t.Errorf("baseline after retry = %v, want [TestOld]", ids)
	}
}
