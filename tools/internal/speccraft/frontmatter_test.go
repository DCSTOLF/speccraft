package speccraft

// Spec 0036 T5/T6 (AC13, AC7) — the single shared frontmatter grammar
// (parseFrontmatterBlock / frontmatterValue). Characterization + edge cases.

import "testing"

func Test_ParseFrontmatterBlock_CRLF_Tolerated(t *testing.T) {
	doc := parseFrontmatterBlock([]byte("---\r\nrevision: 4\r\n---\r\n\r\n# Spec\r\n"))
	if !doc.found {
		t.Fatal("CRLF frontmatter block not found")
	}
	v, ok := frontmatterValue([]byte("---\r\nrevision: 4\r\n---\r\n"), "revision")
	if !ok || v != "4" {
		t.Errorf("revision = %q ok=%v, want 4/true", v, ok)
	}
}

func Test_ParseFrontmatterBlock_Column0KeyOnly(t *testing.T) {
	b := []byte("---\n# status: draft\n  status: indented\nstatus: reviewed\n---\nbody status: x\n")
	v, ok := frontmatterValue(b, "status")
	if !ok || v != "reviewed" {
		t.Errorf("status = %q ok=%v, want reviewed/true (column-0; comment+indent+body skipped)", v, ok)
	}
}

func Test_ParseFrontmatterBlock_DuplicateKey_FirstWins(t *testing.T) {
	v, _ := frontmatterValue([]byte("---\nrevision: 1\nrevision: 9\n---\n"), "revision")
	if v != "1" {
		t.Errorf("revision = %q, want 1 (first wins)", v)
	}
}

func Test_ParseFrontmatterBlock_EmptyBlock_FoundNoLines(t *testing.T) {
	doc := parseFrontmatterBlock([]byte("---\n---\n"))
	if !doc.found || len(doc.lines) != 0 {
		t.Errorf("empty block: found=%v lines=%v, want true/[]", doc.found, doc.lines)
	}
}

func Test_ParseFrontmatterBlock_NoClosingDelim_NotFound(t *testing.T) {
	doc := parseFrontmatterBlock([]byte("---\nrevision: 1\nno closing fence\n"))
	if doc.found {
		t.Error("no-closing-fence must not be found")
	}
}

func Test_ParseFrontmatterBlock_LeadingBOM_FoundAndValueRead(t *testing.T) {
	// A UTF-8 BOM before the opening --- must not hide the block: the reader
	// tolerates it (the writer preserves it, AC6).
	b := []byte("\ufeff---\nrevision: 7\n---\n\n# Spec\n")
	doc := parseFrontmatterBlock(b)
	if !doc.found {
		t.Fatal("BOM-prefixed frontmatter block not found")
	}
	v, ok := frontmatterValue(b, "revision")
	if !ok || v != "7" {
		t.Errorf("revision = %q ok=%v, want 7/true through a leading BOM", v, ok)
	}
}
