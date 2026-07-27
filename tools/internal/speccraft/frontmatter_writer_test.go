package speccraft

// Spec 0036 T9/T10 (AC6, AC7, AC13) — byte-safety edges of the sanctioned writer
// and the single-parser routing assertion. The full byte-safe writer landed in
// T8; these pin every edge and guard against a second frontmatter parser.

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func Test_SetFrontmatterField_RewritesFirstMatchOnly_LaterDupUntouched(t *testing.T) {
	p := writeSpecFile(t, "---\nrevision: 1\nrevision: 2\n---\n\n# S\n")
	if err := SetRevision(p, 9); err != nil {
		t.Fatal(err)
	}
	b, _ := os.ReadFile(p)
	want := "---\nrevision: 9\nrevision: 2\n---\n\n# S\n"
	if string(b) != want {
		t.Errorf("got %q, want %q (first match only)", b, want)
	}
}

func Test_SetFrontmatterField_MixedEOL_PreservesPerLineTerminator(t *testing.T) {
	p := writeSpecFile(t, "---\r\nstatus: draft\r\nrevision: 1\r\n---\r\nbody\n")
	if err := SetStatus(p, "reviewed"); err != nil {
		t.Fatal(err)
	}
	b, _ := os.ReadFile(p)
	want := "---\r\nstatus: reviewed\r\nrevision: 1\r\n---\r\nbody\n"
	if string(b) != want {
		t.Errorf("got %q, want %q (CRLF frontmatter + LF body preserved)", b, want)
	}
}

func Test_SetFrontmatterField_PreservesBOM_And_NoEOFNewline(t *testing.T) {
	p := writeSpecFile(t, "\ufeff---\nstatus: draft\n---\nbody-no-newline")
	if err := SetStatus(p, "planned"); err != nil {
		t.Fatal(err)
	}
	b, _ := os.ReadFile(p)
	want := "\ufeff---\nstatus: planned\n---\nbody-no-newline"
	if string(b) != want {
		t.Errorf("got %q, want %q (BOM + missing EOF newline preserved)", b, want)
	}
}

func Test_SetFrontmatterField_NoBakOrTmpSibling(t *testing.T) {
	p := writeSpecFile(t, "---\nstatus: draft\n---\n")
	if err := SetStatus(p, "reviewed"); err != nil {
		t.Fatal(err)
	}
	entries, _ := os.ReadDir(filepath.Dir(p))
	for _, e := range entries {
		if strings.HasSuffix(e.Name(), ".bak") || strings.HasSuffix(e.Name(), ".tmp") {
			t.Errorf("unexpected sibling written: %s", e.Name())
		}
	}
}

func Test_SetFrontmatterField_SameValue_SkipWrite_NoMtimeChurn(t *testing.T) {
	p := writeSpecFile(t, "---\nstatus: draft\n---\n")
	old := time.Now().Add(-2 * time.Hour)
	if err := os.Chtimes(p, old, old); err != nil {
		t.Fatal(err)
	}
	before, _ := os.Stat(p)
	if err := SetStatus(p, "draft"); err != nil {
		t.Fatal(err)
	}
	after, _ := os.Stat(p)
	if b, _ := os.ReadFile(p); string(b) != "---\nstatus: draft\n---\n" {
		t.Errorf("skip-write changed bytes: %q", b)
	}
	if !before.ModTime().Equal(after.ModTime()) {
		t.Errorf("mtime churned on a same-value skip-write: %v -> %v", before.ModTime(), after.ModTime())
	}
}

func Test_SetFrontmatterField_InsertsWhenAbsent_LF(t *testing.T) {
	p := writeSpecFile(t, "---\nstatus: draft\n---\n\n# S\n")
	if err := SetRevision(p, 3); err != nil {
		t.Fatal(err)
	}
	b, _ := os.ReadFile(p)
	want := "---\nstatus: draft\nrevision: 3\n---\n\n# S\n"
	if string(b) != want {
		t.Errorf("got %q, want %q (inserted before closing ---, LF)", b, want)
	}
}

func Test_SetFrontmatterField_InsertsWhenAbsent_CRLF(t *testing.T) {
	p := writeSpecFile(t, "---\r\nstatus: draft\r\n---\r\n")
	if err := SetRevision(p, 3); err != nil {
		t.Fatal(err)
	}
	b, _ := os.ReadFile(p)
	want := "---\r\nstatus: draft\r\nrevision: 3\r\n---\r\n"
	if string(b) != want {
		t.Errorf("got %q, want %q (inserted line inherits CRLF)", b, want)
	}
}

func Test_SetFrontmatterField_NoFrontmatterBlock_Errors(t *testing.T) {
	p := writeSpecFile(t, "# just a heading\nno frontmatter here\n")
	if err := SetStatus(p, "reviewed"); err == nil {
		t.Error("expected error mutating a file with no frontmatter block")
	}
}

func Test_ReaderAndWriter_RouteThroughParseFrontmatterBlock(t *testing.T) {
	src, err := os.ReadFile("revision.go")
	if err != nil {
		t.Fatal(err)
	}
	s := string(src)
	if n := strings.Count(s, "func parseFrontmatterBlock("); n != 1 {
		t.Errorf("want exactly one parseFrontmatterBlock definition, found %d", n)
	}
	if !strings.Contains(s, "parseFrontmatterBlock(b).found") {
		t.Error("setFrontmatterField must gate on parseFrontmatterBlock (single grammar)")
	}
}
