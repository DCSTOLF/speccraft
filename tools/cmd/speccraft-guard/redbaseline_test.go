package main

// Spec 0048 T8 (AC11, AC12, AC14, AC15) — guard-level behaviour of the
// red-candidate baseline.
//
// These drive the REAL entry point (`processToolUse`) through a JSON envelope,
// the way the harness delivers one, so they exercise the capture path rather
// than the state helper in isolation. The state-layer equivalents live in
// tools/internal/speccraft/buildrepair_test.go; both layers are pinned because
// the defect was a MISMATCH between them — the state was fine, the guard
// recomputed the wrong set and then threw the error away.

import (
	"os"
	"path/filepath"
	"runtime"
	"testing"

	"github.com/dcstolf/speccraft/tools/internal/speccraft"
	"github.com/dcstolf/speccraft/tools/internal/speccraft/runner"
)

// guardRepo lays out a repo with a Go module and .speccraft/, and returns root.
func guardRepo(t *testing.T) string {
	t.Helper()
	root := t.TempDir()
	if err := os.MkdirAll(filepath.Join(root, ".speccraft"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, "go.mod"), []byte("module probe\n\ngo 1.22\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	return root
}

// writeFile creates a file and its parents.
func writeFile(t *testing.T, path, content string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}

// AC11 — the defect at guard level. Edit 1 adds TestNew (candidate registered).
// Edit 2 changes only a comment, adding no `func Test…`. The candidate must
// SURVIVE, because the production edit that follows depends on it.
func Test_TestFileEdit_NoNewTest_PreservesCandidates(t *testing.T) {
	root := guardRepo(t)
	testFile := filepath.Join(root, "pkg", "foo_test.go")
	writeFile(t, testFile, "package pkg\n\nfunc TestOld(t *testing.T) {}\n")

	// Edit 1 — adds TestNew.
	in1 := decodeEnvelope(t, "Write", testFile,
		"package pkg\n\nfunc TestOld(t *testing.T) {}\n\nfunc TestNew(t *testing.T) {}\n", root)
	if err := processToolUse(in1, deps{}); err != nil {
		t.Fatalf("test-file edit must be allowed: %v", err)
	}
	writeFile(t, testFile, "package pkg\n\nfunc TestOld(t *testing.T) {}\n\nfunc TestNew(t *testing.T) {}\n")

	cands, _ := speccraft.GetRedCandidates(root)
	key := speccraft.NormalizeStateKey(testFile)
	if len(cands[key]) != 1 || cands[key][0] != "TestNew" {
		t.Fatalf("after edit 1 candidates = %v, want [TestNew] under key %s", cands, key)
	}

	// Edit 2 — a comment only. No new func Test.
	in2 := decodeEnvelope(t, "Write", testFile,
		"package pkg\n\n// a note\nfunc TestOld(t *testing.T) {}\n\nfunc TestNew(t *testing.T) {}\n", root)
	if err := processToolUse(in2, deps{}); err != nil {
		t.Fatalf("second test-file edit must be allowed: %v", err)
	}

	cands, _ = speccraft.GetRedCandidates(root)
	if len(cands[key]) != 1 || cands[key][0] != "TestNew" {
		t.Errorf("a no-new-test edit CLOBBERED the candidates: got %v, want [TestNew]", cands[key])
	}
}

// AC12 — the converse: deleting a test must still shrink the set, so the fix
// cannot be "pin candidates forever".
func Test_TestFileEdit_Deletion_ShrinksCandidates(t *testing.T) {
	root := guardRepo(t)
	testFile := filepath.Join(root, "pkg", "foo_test.go")
	writeFile(t, testFile, "package pkg\n\nfunc TestOld(t *testing.T) {}\n")

	in1 := decodeEnvelope(t, "Write", testFile,
		"package pkg\n\nfunc TestOld(t *testing.T) {}\n\nfunc TestA(t *testing.T) {}\n\nfunc TestB(t *testing.T) {}\n", root)
	if err := processToolUse(in1, deps{}); err != nil {
		t.Fatal(err)
	}
	writeFile(t, testFile,
		"package pkg\n\nfunc TestOld(t *testing.T) {}\n\nfunc TestA(t *testing.T) {}\n\nfunc TestB(t *testing.T) {}\n")

	// TestB is removed.
	in2 := decodeEnvelope(t, "Write", testFile,
		"package pkg\n\nfunc TestOld(t *testing.T) {}\n\nfunc TestA(t *testing.T) {}\n", root)
	if err := processToolUse(in2, deps{}); err != nil {
		t.Fatal(err)
	}

	cands, _ := speccraft.GetRedCandidates(root)
	key := speccraft.NormalizeStateKey(testFile)
	if len(cands[key]) != 1 || cands[key][0] != "TestA" {
		t.Errorf("deletion must shrink the set: got %v, want [TestA]", cands[key])
	}
}

// AC14 touch 1 — a capture failure must BLOCK the test-file edit, and must leave
// the file byte-unchanged on disk.
//
// Today the guard does `_ = speccraft.SetRedCandidates(...)`: the error is
// discarded, the edit is allowed, and the session proceeds with no registered
// candidate — so the NEXT production edit is refused for a reason that has
// nothing to do with the author's work. Blocking here turns a silent, confusing
// downstream failure into an immediate, actionable one.
func Test_TestFileEdit_CaptureFailure_BlocksEdit_AndLeavesDiskByteUnchanged(t *testing.T) {
	root := guardRepo(t)
	testFile := filepath.Join(root, "pkg", "foo_test.go")
	const original = "package pkg\n\nfunc TestOld(t *testing.T) {}\n"
	writeFile(t, testFile, original)

	// Make the state write fail by turning .speccraft into a regular file, so
	// state.json cannot be created inside it. Deterministic and uid-independent:
	// no permission bits involved.
	speccraftDir := filepath.Join(root, ".speccraft")
	if err := os.RemoveAll(speccraftDir); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(speccraftDir, []byte("not a directory\n"), 0o644); err != nil {
		t.Fatal(err)
	}

	in := decodeEnvelope(t, "Write", testFile,
		"package pkg\n\nfunc TestOld(t *testing.T) {}\n\nfunc TestNew(t *testing.T) {}\n", root)
	err := processToolUse(in, deps{})
	if err == nil {
		t.Fatal("a capture failure must BLOCK the test-file edit, not be swallowed")
	}

	// AC14: the guard runs PRE-edit, so a block must leave the file untouched.
	got, readErr := os.ReadFile(testFile)
	if readErr != nil {
		t.Fatal(readErr)
	}
	if string(got) != original {
		t.Errorf("a blocked edit must leave the file byte-unchanged:\n got %q\nwant %q", got, original)
	}
}

// AC14 touch 2 — the retry recovers. Once the cause is gone, the same edit
// captures from the UNCHANGED content and the production edit is admitted. A
// transient failure must not wedge the session.
func Test_TestFileEdit_CaptureFailure_RetryRecaptures_AndProdEditAllowed(t *testing.T) {
	root := guardRepo(t)
	testFile := filepath.Join(root, "pkg", "foo_test.go")
	const original = "package pkg\n\nfunc TestOld(t *testing.T) {}\n"
	writeFile(t, testFile, original)

	speccraftDir := filepath.Join(root, ".speccraft")
	if err := os.RemoveAll(speccraftDir); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(speccraftDir, []byte("not a directory\n"), 0o644); err != nil {
		t.Fatal(err)
	}

	post := "package pkg\n\nfunc TestOld(t *testing.T) {}\n\nfunc TestNew(t *testing.T) {}\n"
	in := decodeEnvelope(t, "Write", testFile, post, root)
	if err := processToolUse(in, deps{}); err == nil {
		t.Fatal("expected the first attempt to be blocked")
	}

	// Remove the cause and retry the identical edit.
	if err := os.Remove(speccraftDir); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(speccraftDir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := processToolUse(in, deps{}); err != nil {
		t.Fatalf("the retry must succeed: %v", err)
	}

	cands, _ := speccraft.GetRedCandidates(root)
	key := speccraft.NormalizeStateKey(testFile)
	if len(cands[key]) != 1 || cands[key][0] != "TestNew" {
		t.Errorf("retry must re-capture from the unchanged content: got %v, want [TestNew]", cands[key])
	}
}

// AC15 — the sibling lookup must find an entry written through a DIFFERENT
// spelling of the same path. Capture writes the key; the red-check reads it. If
// only one side normalizes, a symlinked repo silently registers candidates the
// lookup can never see, and every production edit is refused.
func Test_SiblingLookup_FindsEntryWrittenThroughSymlinkedPath(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("symlinks need privilege on Windows")
	}
	realRoot := guardRepo(t)
	testFile := filepath.Join(realRoot, "pkg", "foo_test.go")
	writeFile(t, testFile, "package pkg\n\nfunc TestOld(t *testing.T) {}\n")

	// A symlinked view of the same repo.
	linkRoot := filepath.Join(t.TempDir(), "link")
	if err := os.Symlink(realRoot, linkRoot); err != nil {
		t.Skipf("symlink unsupported here: %v", err)
	}

	// Capture through the SYMLINKED path.
	viaLink := filepath.Join(linkRoot, "pkg", "foo_test.go")
	in := decodeEnvelope(t, "Write", viaLink,
		"package pkg\n\nfunc TestOld(t *testing.T) {}\n\nfunc TestNew(t *testing.T) {}\n", linkRoot)
	if err := processToolUse(in, deps{}); err != nil {
		t.Fatalf("test-file edit via symlink must be allowed: %v", err)
	}

	// Read back under the REAL path's key — one normalizer means one key.
	cands, err := speccraft.GetRedCandidates(realRoot)
	if err != nil {
		t.Fatal(err)
	}
	key := speccraft.NormalizeStateKey(testFile)
	if len(cands[key]) != 1 || cands[key][0] != "TestNew" {
		t.Errorf("candidate written via symlink not found under the real key %s: %v", key, cands)
	}
}

// AC15, the READ side — and the half the symlink test above does NOT cover.
//
// That test only proves capture WRITES a normalized key. This one proves
// siblingRedCheck READS with the same normalizer: the candidate is registered
// under an unnormalized spelling, and the production red-check must still find
// it. If only the write side normalizes, state.json plainly shows the candidate
// while every production edit is refused — the most confusing possible failure.
func Test_SiblingRedCheck_FindsCandidateRegisteredUnderUnnormalizedKey(t *testing.T) {
	root := makeTestRepo(t, "0048-guard-wedge-red-candidate-clobber", "in-progress")
	dir := filepath.Join(root, "pkg")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	prodFile := filepath.Join(dir, "foo.go")
	writeFile(t, prodFile, "package pkg\n")
	sib := filepath.Join(dir, "foo_test.go")
	writeFile(t, sib, "package pkg\n")

	// Capture under the REAL path — this is what the normalizer produces.
	if _, err := speccraft.CaptureRedCandidates(root, sib, nil, []string{"TestNew"}); err != nil {
		t.Fatal(err)
	}

	// Now drive the red-check through a SYMLINKED view of the same repo, so
	// resolveSiblingTests yields the sibling's path under the link. An
	// unnormalized lookup misses the real key entirely; only normalizing the
	// read side collapses the two spellings back together. An uncleaned path
	// would NOT expose this — resolveSiblingTests already returns a cleaned
	// path, so the write-side normalizer alone happens to cover that case.
	if runtime.GOOS == "windows" {
		t.Skip("symlinks need privilege on Windows")
	}
	linkRoot := filepath.Join(t.TempDir(), "link")
	if err := os.Symlink(root, linkRoot); err != nil {
		t.Skipf("symlink unsupported here: %v", err)
	}
	prodFile = filepath.Join(linkRoot, "pkg", "foo.go")

	fake := &fakeLangRunner{result: runner.Result{
		Outcome: runner.OutcomeAtLeastOneFailed,
		Records: []runner.TestRecord{{TestName: "TestNew", Status: "failed"}},
	}}
	d := deps{runnerForLang: fixedRunnerForLang(fake, true)}

	if err := siblingRedCheck(prodFile, root, speccraft.SpeccraftConfig{}, "go", d); err != nil {
		t.Fatalf("the red-check must find the candidate through the normalizer: %v", err)
	}
	if len(fake.calls) == 0 {
		t.Error("the runner should have been invoked once a candidate was found")
	}
}
