package speccraft

import (
	"os"
	"path/filepath"
	"testing"
)

func Test_ReadFrontmatterField_PresentKey_ReturnsValue(t *testing.T) {
	dir := t.TempDir()
	p := filepath.Join(dir, "spec.md")
	if err := os.WriteFile(p, []byte("---\nstatus: reviewed\n---\n# spec\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	v, ok, err := ReadFrontmatterField(p, "status")
	if err != nil {
		t.Fatalf("ReadFrontmatterField: %v", err)
	}
	if !ok || v != "reviewed" {
		t.Errorf("ReadFrontmatterField = (%q, %v), want (%q, true)", v, ok, "reviewed")
	}
}

func Test_ReadFrontmatterField_AbsentKey_FoundFalse(t *testing.T) {
	dir := t.TempDir()
	p := filepath.Join(dir, "spec.md")
	if err := os.WriteFile(p, []byte("---\nstatus: draft\n---\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	v, ok, err := ReadFrontmatterField(p, "design")
	if err != nil {
		t.Fatalf("ReadFrontmatterField: %v", err)
	}
	if ok || v != "" {
		t.Errorf("absent key = (%q, %v), want (\"\", false)", v, ok)
	}
}

func Test_ReadFrontmatterField_MissingFile_Error(t *testing.T) {
	_, _, err := ReadFrontmatterField(filepath.Join(t.TempDir(), "nope.md"), "status")
	if err == nil {
		t.Error("want error for missing file, got nil")
	}
}

// Proves the reader routes through the single spec-0036 frontmatterValue grammar
// (first-wins on duplicate keys; body lines ignored) rather than a 2nd parser.
func Test_ReadFrontmatterField_RoutesThroughSharedGrammar(t *testing.T) {
	dir := t.TempDir()
	p := filepath.Join(dir, "spec.md")
	content := []byte("---\nstatus: reviewed\nstatus: second-ignored\n---\nstatus: body-ignored\n")
	if err := os.WriteFile(p, content, 0o644); err != nil {
		t.Fatal(err)
	}
	wantVal, wantOK := frontmatterValue(content, "status")
	gotVal, gotOK, err := ReadFrontmatterField(p, "status")
	if err != nil {
		t.Fatalf("ReadFrontmatterField: %v", err)
	}
	if gotVal != wantVal || gotOK != wantOK {
		t.Errorf("ReadFrontmatterField=(%q,%v) vs frontmatterValue=(%q,%v): must share grammar", gotVal, gotOK, wantVal, wantOK)
	}
}
