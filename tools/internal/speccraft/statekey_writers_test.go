package speccraft_test

// Spec 0048 AC15 said NormalizeStateKey is "the single canonical path normalizer
// for every state key this package writes". `SetRedCandidates` did not apply it —
// it stored `s.Session.RedCandidates[file]` verbatim, trusting every caller to
// have normalized first. `siblingRedCheck` reads that map through
// `NormalizeStateKey(sib)`, so a caller that passed a merely-absolute path wrote a
// key the reader can never find, and the guard reported "No test was added this
// session" for a session that had added one.
//
// This was invisible on Linux CI and fired on macOS, where `t.TempDir()` hands
// back `/var/folders/…` — a symlink to `/private/var/folders/…`. 25 guard tests
// failed there while passing here. The whole class is reproducible on any
// platform with `TMPDIR` pointed at a symlink, which is what these tests do
// directly.
//
// Pinned at the WRITER, not in the guard: the guard is one caller among several
// and a per-caller fix leaves the trap armed for the next one.

import (
	"os"
	"path/filepath"
	"runtime"
	"testing"

	"github.com/dcstolf/speccraft/tools/internal/speccraft"
)

// symlinkedRepo returns (accessPath, realPath) for a state root reached through a
// symlinked ancestor — the shape macOS hands every test via TMPDIR.
func symlinkedRepo(t *testing.T) (string, string) {
	t.Helper()
	if runtime.GOOS == "windows" {
		t.Skip("symlinks need privilege on Windows")
	}
	// Resolve the base FIRST. `t.TempDir()` is itself reached through a symlink
	// whenever TMPDIR is one — which is the condition AC4 deliberately runs the
	// suite under — and an unresolved base would make `real` non-canonical, so the
	// asymmetric assertion below would fail for the tester's own reason rather
	// than the code's.
	base, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	real := filepath.Join(base, "real")
	if err := os.MkdirAll(filepath.Join(real, ".speccraft"), 0o755); err != nil {
		t.Fatal(err)
	}
	link := filepath.Join(base, "link")
	if err := os.Symlink(real, link); err != nil {
		t.Fatal(err)
	}
	return link, real
}

// The writer must key by the normalized path even when handed the symlinked
// spelling. Asserted asymmetrically: `want` is built from the REAL path with no
// call to NormalizeStateKey, so a regression that made the normalizer a no-op
// cannot satisfy it.
func Test_SetRedCandidates_KeysThroughTheCanonicalNormalizer(t *testing.T) {
	link, real := symlinkedRepo(t)

	viaLink := filepath.Join(link, "pkg", "foo_test.go")
	if err := os.MkdirAll(filepath.Dir(viaLink), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(viaLink, []byte("package p\n"), 0o644); err != nil {
		t.Fatal(err)
	}

	if err := speccraft.SetRedCandidates(link, viaLink, []string{"TestNew"}); err != nil {
		t.Fatal(err)
	}

	rc, err := speccraft.GetRedCandidates(link)
	if err != nil {
		t.Fatal(err)
	}

	want := filepath.Join(real, "pkg", "foo_test.go")
	if got := rc[want]; len(got) != 1 || got[0] != "TestNew" {
		t.Errorf("SetRedCandidates must key by the resolved path %q, got map %v", want, rc)
	}
	if _, ok := rc[viaLink]; ok {
		t.Errorf("the symlinked spelling %q must not appear as a second key: %v", viaLink, rc)
	}
}

// The consequence that actually bit: the same file reached by two spellings must
// resolve to ONE entry. Two keys for one file is how a registered red candidate
// becomes unfindable.
func Test_RedCandidates_TwoSpellingsOfOneFileShareOneEntry(t *testing.T) {
	link, real := symlinkedRepo(t)

	dir := filepath.Join(real, "pkg")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "foo_test.go"), []byte("package p\n"), 0o644); err != nil {
		t.Fatal(err)
	}

	if err := speccraft.SetRedCandidates(link, filepath.Join(link, "pkg", "foo_test.go"), []string{"TestA"}); err != nil {
		t.Fatal(err)
	}
	if err := speccraft.SetRedCandidates(link, filepath.Join(real, "pkg", "foo_test.go"), []string{"TestA", "TestB"}); err != nil {
		t.Fatal(err)
	}

	rc, err := speccraft.GetRedCandidates(link)
	if err != nil {
		t.Fatal(err)
	}
	if len(rc) != 1 {
		t.Fatalf("one file reached by two spellings must occupy one key, got %d: %v", len(rc), rc)
	}
}

// CaptureRedCandidates already normalized; this is the both-polarity partner, so
// a regression that removed normalization from the capture path is caught here
// rather than only on macOS.
func Test_CaptureRedCandidates_KeysThroughTheCanonicalNormalizer(t *testing.T) {
	link, real := symlinkedRepo(t)

	viaLink := filepath.Join(link, "pkg", "bar_test.go")
	if err := os.MkdirAll(filepath.Dir(viaLink), 0o755); err != nil {
		t.Fatal(err)
	}

	if _, err := speccraft.CaptureRedCandidates(link, viaLink, nil, []string{"TestCap"}); err != nil {
		t.Fatal(err)
	}

	rc, err := speccraft.GetRedCandidates(link)
	if err != nil {
		t.Fatal(err)
	}
	want := filepath.Join(real, "pkg", "bar_test.go")
	if got := rc[want]; len(got) != 1 || got[0] != "TestCap" {
		t.Errorf("CaptureRedCandidates must key by the resolved path %q, got map %v", want, rc)
	}
}
