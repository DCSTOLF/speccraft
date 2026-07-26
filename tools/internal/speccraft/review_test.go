package speccraft

// Spec 0035 T1 — bootstrap anchor. This test exists only to reference every
// brand-new exported symbol so the package compiles once the T1 stubs land; it
// is NOT a behaviour RED (behaviour is driven test-first in T2+). Introduced
// under the single recorded /speccraft:spec:override.

import (
	"os"
	"path/filepath"
	"testing"
)

func Test_Review_Bootstrap_SymbolsExist(t *testing.T) {
	// Reference each symbol so the compiler proves they exist. Behaviour is
	// exercised by the dedicated per-symbol tests (T2+); this only pins symbol
	// existence, using valid arguments now that the stubs have real bodies.
	_ = ChangedSection{Kind: "section", Heading: "Why", Ordinal: 1, Side: "modified"}
	_ = ReviewEnvelope{Schema: 1}
	path := filepath.Join(t.TempDir(), "anchor.txt")
	if err := AtomicWriteFile(path, []byte("ok"), os.FileMode(0o644)); err != nil {
		t.Fatalf("AtomicWriteFile: %v", err)
	}
	_ = WriteReviewSnapshot
	_ = ReviewDiff
	_ = WriteReviewFile
}
