package speccraft

// Spec 0036 T1 (AC1/AC12) — bootstrap anchor: RED against the T1 stubs. These
// first tests reference the brand-new exported symbols so the package compiles
// once the stubs land, and assert the Effective math, so they FAIL at RUNTIME
// until T2/T4 implement ComputeRevisionState. Introduced under the single
// recorded /speccraft:spec:override.

import (
	"bytes"
	"os"
	"path/filepath"
	"testing"
)

// writeSpecFile writes spec.md with the given full content and returns its path
// (SetStatus/SetRevision operate on the spec.md path, not the dir).
func writeSpecFile(t *testing.T, content string) string {
	t.Helper()
	p := filepath.Join(t.TempDir(), "spec.md")
	if err := os.WriteFile(p, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
	return p
}

// seedSpecDir writes a spec.md with the given revision line (empty ⇒ omit) and
// any named archive artifacts, returning the spec dir.
func seedSpecDir(t *testing.T, revisionLine string, archived ...string) string {
	t.Helper()
	dir := t.TempDir()
	fm := "---\nid: \"0001\"\n"
	if revisionLine != "" {
		fm += revisionLine + "\n"
	}
	fm += "status: reviewed\n---\n\n# Spec\n\n## Why\n\nx\n"
	if err := os.WriteFile(filepath.Join(dir, "spec.md"), []byte(fm), 0o644); err != nil {
		t.Fatal(err)
	}
	for _, name := range archived {
		if err := os.WriteFile(filepath.Join(dir, name), []byte("x\n"), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	return dir
}

func Test_ComputeRevisionState_NoArchives_EffectiveEqualsFmRev(t *testing.T) {
	dir := seedSpecDir(t, "revision: 5")
	st, err := ComputeRevisionState(dir)
	if err != nil {
		t.Fatalf("ComputeRevisionState: %v", err)
	}
	if st.HasArchived {
		t.Errorf("HasArchived = true, want false (no *-rN.md)")
	}
	if st.FrontmatterRevision != 5 || st.Effective != 5 {
		t.Errorf("fmRev=%d effective=%d, want 5/5", st.FrontmatterRevision, st.Effective)
	}
}

func Test_ComputeRevisionState_ArchiveBelowFmRev_KeepsFmRev(t *testing.T) {
	// fmRev already leads the archives: Effective stays fmRev, but HasArchived is
	// true and MaxArchived reflects disk.
	dir := seedSpecDir(t, "revision: 8", "review-r5.md")
	st, err := ComputeRevisionState(dir)
	if err != nil {
		t.Fatalf("ComputeRevisionState: %v", err)
	}
	if !st.HasArchived || st.MaxArchived != 5 {
		t.Errorf("hasArchived=%v maxArchived=%d, want true/5", st.HasArchived, st.MaxArchived)
	}
	if st.Effective != 8 {
		t.Errorf("Effective = %d, want 8 (max(8,5+1))", st.Effective)
	}
}

func Test_ComputeRevisionState_MissingDir_Errors(t *testing.T) {
	if _, err := ComputeRevisionState(filepath.Join(t.TempDir(), "nope")); err == nil {
		t.Errorf("expected error for missing specDir")
	}
}

func Test_ComputeRevisionState_NoFrontmatterBlock_FmRevZeroNotError(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "spec.md"), []byte("# Spec\n\nno frontmatter here\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "review-r4.md"), []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	st, err := ComputeRevisionState(dir)
	if err != nil {
		t.Fatalf("no-frontmatter must not error: %v", err)
	}
	if st.FrontmatterRevision != 0 {
		t.Errorf("fmRev = %d, want 0", st.FrontmatterRevision)
	}
	if st.Effective != 5 {
		t.Errorf("Effective = %d, want 5 (maxArchived 4 + 1, healed from disk)", st.Effective)
	}
}

func Test_ComputeRevisionState_NonNumericRevision_ReadAsZero(t *testing.T) {
	dir := seedSpecDir(t, "revision: abc")
	st, err := ComputeRevisionState(dir)
	if err != nil {
		t.Fatalf("non-numeric revision must not error: %v", err)
	}
	if st.FrontmatterRevision != 0 {
		t.Errorf("fmRev = %d, want 0 for non-numeric", st.FrontmatterRevision)
	}
}

func Test_ComputeRevisionState_OverDomainLiteral_Errors(t *testing.T) {
	dir := seedSpecDir(t, "revision: 99999999999999999999999999")
	if _, err := ComputeRevisionState(dir); err == nil {
		t.Errorf("expected error for a numeric revision literal exceeding uint64")
	}
}

func Test_ListArchivedOrdinals_IgnoresNonNumericSuffix(t *testing.T) {
	dir := seedSpecDir(t, "revision: 1", "review-rfoo.md", "plan-r2.md")
	ords, err := listArchivedOrdinals(dir)
	if err != nil {
		t.Fatalf("listArchivedOrdinals: %v", err)
	}
	if len(ords) != 1 || ords[0] != 2 {
		t.Errorf("ords = %v, want [2] (review-rfoo.md ignored)", ords)
	}
}

func Test_SetStatus_AcceptsEnum_RejectsUnknown(t *testing.T) {
	p := writeSpecFile(t, "---\nstatus: draft\nrevision: 1\n---\n\n# S\n")
	if err := SetStatus(p, "reviewed"); err != nil {
		t.Fatalf("valid status: %v", err)
	}
	b, _ := os.ReadFile(p)
	if v, _ := frontmatterValue(b, "status"); v != "reviewed" {
		t.Errorf("status = %q, want reviewed after write", v)
	}
	before, _ := os.ReadFile(p)
	if err := SetStatus(p, "bogus"); err == nil {
		t.Error("expected error for unknown status value")
	}
	after, _ := os.ReadFile(p)
	if !bytes.Equal(before, after) {
		t.Error("a rejected status must not mutate the file")
	}
}

func Test_SetRevision_RejectsDemotion_Monotonic(t *testing.T) {
	p := writeSpecFile(t, "---\nstatus: draft\nrevision: 5\n---\n\n# S\n")
	before, _ := os.ReadFile(p)
	if err := SetRevision(p, 3); err == nil {
		t.Error("expected error demoting revision 5→3")
	}
	if after, _ := os.ReadFile(p); !bytes.Equal(before, after) {
		t.Error("a rejected demotion must not mutate the file")
	}
	if err := SetRevision(p, 7); err != nil {
		t.Fatalf("forward 5→7 must succeed: %v", err)
	}
	b, _ := os.ReadFile(p)
	if v, _ := frontmatterValue(b, "revision"); v != "7" {
		t.Errorf("revision = %q, want 7", v)
	}
}

func Test_SetStatus_And_SetRevision_RefuseClosedSpec(t *testing.T) {
	p := writeSpecFile(t, "---\nstatus: closed\nrevision: 4\n---\n\n# S\n")
	before, _ := os.ReadFile(p)
	if err := SetStatus(p, "draft"); err == nil {
		t.Error("SetStatus must refuse an already-closed spec")
	}
	if err := SetRevision(p, 9); err == nil {
		t.Error("SetRevision must refuse an already-closed spec")
	}
	if after, _ := os.ReadFile(p); !bytes.Equal(before, after) {
		t.Error("a closed spec must be left byte-unchanged")
	}
}

func Test_SetRevision_MalformedStatus_ReadsNotClosed_StillWrites(t *testing.T) {
	// No status line at all ⇒ "not closed" ⇒ the mutation proceeds (AC9 leniency).
	p := writeSpecFile(t, "---\nrevision: 2\n---\n\n# S\n")
	if err := SetRevision(p, 5); err != nil {
		t.Fatalf("non-closed (malformed/absent status) must still write: %v", err)
	}
	b, _ := os.ReadFile(p)
	if v, _ := frontmatterValue(b, "revision"); v != "5" {
		t.Errorf("revision = %q, want 5", v)
	}
}

func Test_ComputeRevisionState_PathologicalArchive_HealsForward(t *testing.T) {
	dir := seedSpecDir(t, "revision: 3", "review-r5.md")
	st, err := ComputeRevisionState(dir)
	if err != nil {
		t.Fatalf("ComputeRevisionState: %v", err)
	}
	if !st.HasArchived {
		t.Errorf("HasArchived = false, want true")
	}
	if st.MaxArchived != 5 {
		t.Errorf("MaxArchived = %d, want 5", st.MaxArchived)
	}
	if st.Effective != 6 {
		t.Errorf("Effective = %d, want 6 (max(3,5+1))", st.Effective)
	}
}
