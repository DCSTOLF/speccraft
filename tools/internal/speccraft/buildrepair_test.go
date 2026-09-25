package speccraft_test

// Spec 0048 T4 (AC11, AC12, AC13, AC15) — the normalizer and the atomic
// baseline-capture semantics that fix defect B: an edit to a test file adding no
// new `func Test…` reset that file's registered red candidates to `[]`, blocking
// a legitimately-RED production edit.
//
// The fix is a per-file baseline written on FIRST TOUCH ONLY. Candidates are
// always recomputed as postIDs − baseline, so a no-new-test edit recomputes the
// same set instead of clearing it, while a genuine deletion still shrinks it.

import (
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"

	"github.com/dcstolf/speccraft/tools/internal/speccraft"
)

func repoRoot(t *testing.T) string {
	t.Helper()
	root := t.TempDir()
	if err := os.MkdirAll(filepath.Join(root, ".speccraft"), 0o755); err != nil {
		t.Fatal(err)
	}
	return root
}

func Test_NormalizeStateKey_UncleanedPathCollapsesToSameKey(t *testing.T) {
	root := repoRoot(t)
	clean := filepath.Join(root, "pkg", "foo_test.go")
	if err := os.MkdirAll(filepath.Dir(clean), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(clean, []byte("package p\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	unclean := filepath.Join(root, "pkg", "..", "pkg", ".", "foo_test.go")

	if got, want := speccraft.NormalizeStateKey(unclean), speccraft.NormalizeStateKey(clean); got != want {
		t.Errorf("uncleaned path must collapse to the same key:\n got %q\nwant %q", got, want)
	}
}

// Asserted ASYMMETRICALLY per conventions.md §"Assert asymmetrically": the
// expected value is normalized, `got` is compared untouched. Normalizing both
// sides would pass even if the function did nothing.
func Test_NormalizeStateKey_SymlinkedPathCollapsesToSameKey(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("symlinks need privilege on Windows")
	}
	root := repoRoot(t)
	real := filepath.Join(root, "real")
	if err := os.MkdirAll(real, 0o755); err != nil {
		t.Fatal(err)
	}
	target := filepath.Join(real, "foo_test.go")
	if err := os.WriteFile(target, []byte("package p\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	link := filepath.Join(root, "link")
	if err := os.Symlink(real, link); err != nil {
		t.Skipf("symlink unsupported here: %v", err)
	}

	got := speccraft.NormalizeStateKey(filepath.Join(link, "foo_test.go"))
	want := speccraft.NormalizeStateKey(target)
	if got != want {
		t.Errorf("symlinked path must collapse to the real key:\n got %q\nwant %q", got, want)
	}
}

// A test file CREATED IN-SESSION is absent from disk at capture time, so the
// normalizer must still produce a key rather than an error — otherwise the very
// first touch of a brand-new test file has nowhere to record its baseline.
func Test_NormalizeStateKey_NonexistentFile_StillNormalizes(t *testing.T) {
	root := repoRoot(t)
	missing := filepath.Join(root, "nope", "deeper", "new_test.go")
	got := speccraft.NormalizeStateKey(missing)
	if got == "" {
		t.Fatal("normalizer returned empty for a not-yet-existing file")
	}
	if !filepath.IsAbs(got) {
		t.Errorf("key must be absolute; got %q", got)
	}
	if filepath.Base(got) != "new_test.go" {
		t.Errorf("key lost the filename; got %q", got)
	}
}

func Test_CaptureRedCandidates_FirstTouch_SetsBaselineFromPreIDs(t *testing.T) {
	root := repoRoot(t)
	f := filepath.Join(root, "pkg", "foo_test.go")

	got, err := speccraft.CaptureRedCandidates(root, f, []string{"TestOld"}, []string{"TestOld", "TestNew"})
	if err != nil {
		t.Fatalf("CaptureRedCandidates: %v", err)
	}
	if len(got) != 1 || got[0] != "TestNew" {
		t.Errorf("candidates = %v, want [TestNew] (postIDs − baseline)", got)
	}
	base, err := speccraft.GetRedBaseline(root)
	if err != nil {
		t.Fatalf("GetRedBaseline: %v", err)
	}
	key := speccraft.NormalizeStateKey(f)
	if ids := base[key]; len(ids) != 1 || ids[0] != "TestOld" {
		t.Errorf("baseline[%s] = %v, want [TestOld]", key, ids)
	}
}

// AC13 — the baseline is FIRST-TOUCH-ONLY. A second capture must not rewrite it,
// even though preIDs now legitimately include the test added on the first touch.
// If the baseline moved, the just-added set would empty out and the production
// edit would be refused: defect B.
func Test_CaptureRedCandidates_LaterTouch_DoesNotRewriteBaseline(t *testing.T) {
	root := repoRoot(t)
	f := filepath.Join(root, "pkg", "foo_test.go")
	key := speccraft.NormalizeStateKey(f)

	if _, err := speccraft.CaptureRedCandidates(root, f, []string{"TestOld"}, []string{"TestOld", "TestNew"}); err != nil {
		t.Fatal(err)
	}
	// Second touch: the file now HAS TestNew, so preIDs reflect that.
	if _, err := speccraft.CaptureRedCandidates(root, f, []string{"TestOld", "TestNew"}, []string{"TestOld", "TestNew"}); err != nil {
		t.Fatal(err)
	}
	base, err := speccraft.GetRedBaseline(root)
	if err != nil {
		t.Fatal(err)
	}
	if ids := base[key]; len(ids) != 1 || ids[0] != "TestOld" {
		t.Errorf("baseline must stay first-touch: got %v, want [TestOld]", ids)
	}
}

// AC11 — the defect, directly. A re-edit that adds no new test must PRESERVE the
// standing candidates, not clear them.
func Test_CaptureRedCandidates_NoNewTest_PreservesStandingCandidates(t *testing.T) {
	root := repoRoot(t)
	f := filepath.Join(root, "pkg", "foo_test.go")

	if _, err := speccraft.CaptureRedCandidates(root, f, []string{"TestOld"}, []string{"TestOld", "TestNew"}); err != nil {
		t.Fatal(err)
	}
	// A whitespace-only edit: same ids before and after, nothing added.
	got, err := speccraft.CaptureRedCandidates(root, f, []string{"TestOld", "TestNew"}, []string{"TestOld", "TestNew"})
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 1 || got[0] != "TestNew" {
		t.Errorf("a no-new-test edit must preserve candidates: got %v, want [TestNew]", got)
	}
}

// AC12 — the other half: a genuine deletion must still shrink the set, or the
// fix would just pin candidates forever.
func Test_CaptureRedCandidates_Deletion_ShrinksCandidateSet(t *testing.T) {
	root := repoRoot(t)
	f := filepath.Join(root, "pkg", "foo_test.go")

	if _, err := speccraft.CaptureRedCandidates(root, f, []string{"TestOld"}, []string{"TestOld", "TestA", "TestB"}); err != nil {
		t.Fatal(err)
	}
	// TestB is deleted.
	got, err := speccraft.CaptureRedCandidates(root, f, []string{"TestOld", "TestA", "TestB"}, []string{"TestOld", "TestA"})
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 1 || got[0] != "TestA" {
		t.Errorf("deletion must shrink the set: got %v, want [TestA]", got)
	}
}

// AC13 — ResetSession clears the baseline, the candidates, the attestation AND
// the log together. They are one session's worth of state; clearing a subset
// would leave a baseline with no candidates, which reads as "never had a red
// test", or a refunded repair budget.
func Test_ResetSession_ClearsBaselineCandidatesAttestationAndLog(t *testing.T) {
	root := repoRoot(t)
	f := filepath.Join(root, "pkg", "foo_test.go")

	if _, err := speccraft.CaptureRedCandidates(root, f, []string{"TestOld"}, []string{"TestOld", "TestNew"}); err != nil {
		t.Fatal(err)
	}
	if _, err := speccraft.RecordBuildRepair(root, filepath.Join(root, "pkg", "prod.go"), "undefined: foo"); err != nil {
		t.Fatal(err)
	}
	if err := speccraft.ResetSession(root); err != nil {
		t.Fatalf("ResetSession: %v", err)
	}

	base, err := speccraft.GetRedBaseline(root)
	if err != nil {
		t.Fatal(err)
	}
	if len(base) != 0 {
		t.Errorf("baseline not cleared: %v", base)
	}
	cands, err := speccraft.GetRedCandidates(root)
	if err != nil {
		t.Fatal(err)
	}
	if len(cands) != 0 {
		t.Errorf("candidates not cleared: %v", cands)
	}
	br, err := speccraft.GetBuildRepair(root)
	if err != nil {
		t.Fatal(err)
	}
	if br.Attestation != nil {
		t.Errorf("attestation not cleared: %+v", br.Attestation)
	}
	if len(br.Log) != 0 {
		t.Errorf("log not cleared: %v", br.Log)
	}
}

// --- Spec 0048 T6 (AC2, AC3, AC4, AC15) — the build-repair ledger ------------
//
// The log is the audit trail for defect A: edits admitted while the build was
// broken. An entry is recorded BEFORE the guard allows the edit, and the log's
// LENGTH is the sole source of the repair budget — so a clean probe can end
// repair mode without refunding anything already spent.

func Test_RecordBuildRepair_FirstEntry_OpensAttestationAndLogsSeq1(t *testing.T) {
	root := repoRoot(t)
	f := filepath.Join(root, "pkg", "prod.go")

	e, err := speccraft.RecordBuildRepair(root, f, "undefined: foo")
	if err != nil {
		t.Fatalf("RecordBuildRepair: %v", err)
	}
	if e.Seq != 1 {
		t.Errorf("first entry Seq = %d, want 1", e.Seq)
	}
	br, err := speccraft.GetBuildRepair(root)
	if err != nil {
		t.Fatal(err)
	}
	if br.Attestation == nil {
		t.Fatal("first entry must OPEN the attestation")
	}
	if br.Attestation.At == "" || br.Attestation.Fingerprint == "" {
		t.Errorf("attestation missing metadata: %+v", br.Attestation)
	}
	if len(br.Log) != 1 {
		t.Fatalf("log len = %d, want 1", len(br.Log))
	}
}

func Test_RecordBuildRepair_NEntries_AreSequenceOrdered(t *testing.T) {
	root := repoRoot(t)
	f := filepath.Join(root, "pkg", "prod.go")
	for i := 1; i <= 4; i++ {
		e, err := speccraft.RecordBuildRepair(root, f, "err")
		if err != nil {
			t.Fatalf("record %d: %v", i, err)
		}
		if e.Seq != i {
			t.Errorf("entry %d has Seq %d", i, e.Seq)
		}
	}
	br, _ := speccraft.GetBuildRepair(root)
	if len(br.Log) != 4 {
		t.Fatalf("log len = %d, want 4", len(br.Log))
	}
	for i, e := range br.Log {
		if e.Seq != i+1 {
			t.Errorf("log[%d].Seq = %d, want %d", i, e.Seq, i+1)
		}
	}
}

// AC-level: truncating the stored summary must never weaken the audit trail, so
// the digest is taken over the FULL bytes before any capping.
func Test_RecordBuildRepair_DigestIsSHA256OfFullPreTruncationBytes(t *testing.T) {
	root := repoRoot(t)
	f := filepath.Join(root, "pkg", "prod.go")
	big := strings.Repeat("E", (4<<10)+512) // comfortably over the 4 KiB cap

	e, err := speccraft.RecordBuildRepair(root, f, big)
	if err != nil {
		t.Fatal(err)
	}
	sum := sha256.Sum256([]byte(big))
	if want := hex.EncodeToString(sum[:]); e.Digest != want {
		t.Errorf("Digest = %q, want sha256 of the FULL bytes %q", e.Digest, want)
	}
	if len(e.Summary) >= len(big) {
		t.Errorf("Summary was not capped: len %d vs input %d", len(e.Summary), len(big))
	}
}

func Test_RecordBuildRepair_SummaryCappedAt4KiBWithVisibleMarker(t *testing.T) {
	root := repoRoot(t)
	f := filepath.Join(root, "pkg", "prod.go")
	big := strings.Repeat("E", (4<<10)+512)

	e, err := speccraft.RecordBuildRepair(root, f, big)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(e.Summary, "truncated") {
		t.Errorf("truncation must be VISIBLE, or a clipped message reads as the whole failure: %q",
			e.Summary[max(0, len(e.Summary)-40):])
	}
	// Short text is stored untouched.
	e2, err := speccraft.RecordBuildRepair(root, f, "short error")
	if err != nil {
		t.Fatal(err)
	}
	if e2.Summary != "short error" {
		t.Errorf("short summary must be verbatim; got %q", e2.Summary)
	}
}

// AC4, interleaved — the sequence that matters: a clean probe ends repair mode
// but must NOT refund spent budget, or a caller could alternate break/fix
// forever and never exhaust the bound.
func Test_RecordBuildRepair_BudgetIsSessionWide_CleanProbeDoesNotRefund(t *testing.T) {
	root := repoRoot(t)
	f := filepath.Join(root, "pkg", "prod.go")

	for i := 0; i < 6; i++ {
		if _, err := speccraft.RecordBuildRepair(root, f, "err"); err != nil {
			t.Fatalf("record %d: %v", i, err)
		}
	}
	if err := speccraft.ClearBuildRepairAttestation(root); err != nil {
		t.Fatalf("ClearBuildRepairAttestation: %v", err)
	}
	br, _ := speccraft.GetBuildRepair(root)
	if br.Attestation != nil {
		t.Error("a clean probe must close the attestation")
	}
	if len(br.Log) != 6 {
		t.Fatalf("a clean probe must NOT clear the log: len = %d, want 6", len(br.Log))
	}

	// 4 more take the log to 10 (the cap); the next must be refused.
	for i := 0; i < 4; i++ {
		if _, err := speccraft.RecordBuildRepair(root, f, "err"); err != nil {
			t.Fatalf("record %d after probe: %v", i, err)
		}
	}
	if _, err := speccraft.RecordBuildRepair(root, f, "err"); !errors.Is(err, speccraft.ErrBuildRepairBudgetExhausted) {
		t.Errorf("11th record err = %v, want ErrBuildRepairBudgetExhausted", err)
	}
	br, _ = speccraft.GetBuildRepair(root)
	if len(br.Log) != 10 {
		t.Errorf("a refused record must append nothing: log len = %d, want 10", len(br.Log))
	}
}

func Test_RecordBuildRepair_ResetSession_RestoresFullBudget(t *testing.T) {
	root := repoRoot(t)
	f := filepath.Join(root, "pkg", "prod.go")
	for i := 0; i < 10; i++ {
		if _, err := speccraft.RecordBuildRepair(root, f, "err"); err != nil {
			t.Fatal(err)
		}
	}
	if _, err := speccraft.RecordBuildRepair(root, f, "err"); err == nil {
		t.Fatal("expected the budget to be exhausted at 10")
	}
	if err := speccraft.ResetSession(root); err != nil {
		t.Fatal(err)
	}
	e, err := speccraft.RecordBuildRepair(root, f, "err")
	if err != nil {
		t.Fatalf("a new session must start with a full budget: %v", err)
	}
	if e.Seq != 1 {
		t.Errorf("Seq after reset = %d, want 1", e.Seq)
	}
}

// AC15 — the log key goes through the same normalizer as everything else, so one
// file cannot occupy two rows.
func Test_RecordBuildRepair_PathKeyIsNormalized(t *testing.T) {
	root := repoRoot(t)
	clean := filepath.Join(root, "pkg", "prod.go")
	if err := os.MkdirAll(filepath.Dir(clean), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(clean, []byte("package p\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	unclean := filepath.Join(root, "pkg", "..", "pkg", ".", "prod.go")

	e, err := speccraft.RecordBuildRepair(root, unclean, "err")
	if err != nil {
		t.Fatal(err)
	}
	if want := speccraft.NormalizeStateKey(clean); e.Path != want {
		t.Errorf("entry Path = %q, want the normalized key %q", e.Path, want)
	}
}

func Test_ClearBuildRepairAttestation_KeepsLog(t *testing.T) {
	root := repoRoot(t)
	f := filepath.Join(root, "pkg", "prod.go")
	if _, err := speccraft.RecordBuildRepair(root, f, "err"); err != nil {
		t.Fatal(err)
	}
	if err := speccraft.ClearBuildRepairAttestation(root); err != nil {
		t.Fatal(err)
	}
	br, _ := speccraft.GetBuildRepair(root)
	if br.Attestation != nil {
		t.Error("attestation must be cleared")
	}
	if len(br.Log) != 1 {
		t.Errorf("log must survive: len = %d, want 1", len(br.Log))
	}
	// Idempotent: clearing again is not an error.
	if err := speccraft.ClearBuildRepairAttestation(root); err != nil {
		t.Errorf("clearing an already-closed attestation must be a no-op: %v", err)
	}
}
