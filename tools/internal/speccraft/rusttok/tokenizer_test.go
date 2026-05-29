package rusttok_test

import (
	"testing"

	"github.com/dcstolf/speccraft/tools/internal/speccraft/rusttok"
)

// spansCover returns true if the spans, in order, fully cover [0,len) with
// no gaps and no overlaps. The tokenizer contract.
func spansCover(spans []rusttok.Span, srcLen int) bool {
	pos := 0
	for _, s := range spans {
		if s.Start != pos {
			return false
		}
		if s.End < s.Start {
			return false
		}
		pos = s.End
	}
	return pos == srcLen
}

// hasKindAt returns true if any span containing [start,end) has the given kind.
func hasKindAt(spans []rusttok.Span, src string, needle string, kind rusttok.Kind) bool {
	i := indexOf(src, needle)
	if i < 0 {
		return false
	}
	end := i + len(needle)
	for _, s := range spans {
		if s.Start <= i && end <= s.End && s.Kind == kind {
			return true
		}
	}
	return false
}

func indexOf(haystack, needle string) int {
	for i := 0; i+len(needle) <= len(haystack); i++ {
		if haystack[i:i+len(needle)] == needle {
			return i
		}
	}
	return -1
}

func TestTokenize_BareIdentifiers(t *testing.T) {
	src := "fn it() {}"
	spans := rusttok.Tokenize(src)
	if !spansCover(spans, len(src)) {
		t.Fatalf("spans do not cover input: %+v", spans)
	}
	if !hasKindAt(spans, src, "fn it()", rusttok.KindCode) {
		t.Errorf("expected 'fn it()' inside a Code span; spans=%+v", spans)
	}
}

func TestTokenize_SkipsLineComment(t *testing.T) {
	src := "let x = 1; // fn x()\nlet y = 2;"
	spans := rusttok.Tokenize(src)
	if !spansCover(spans, len(src)) {
		t.Fatalf("spans do not cover")
	}
	if !hasKindAt(spans, src, "// fn x()", rusttok.KindComment) {
		t.Errorf("expected '// fn x()' inside Comment; spans=%+v", spans)
	}
}

func TestTokenize_SkipsBlockComment(t *testing.T) {
	src := "let x = /* fn x() */ 1;"
	spans := rusttok.Tokenize(src)
	if !hasKindAt(spans, src, "/* fn x() */", rusttok.KindComment) {
		t.Errorf("block comment not classified; spans=%+v", spans)
	}
}

func TestTokenize_SkipsNestedBlockComment(t *testing.T) {
	src := "x; /* outer /* inner */ outer */ y;"
	spans := rusttok.Tokenize(src)
	if !hasKindAt(spans, src, "/* outer /* inner */ outer */", rusttok.KindComment) {
		t.Errorf("nested block comment not unified; spans=%+v", spans)
	}
	// Anything after the closing */ must be Code.
	if !hasKindAt(spans, src, "y;", rusttok.KindCode) {
		t.Errorf("trailing code after nested comment not Code; spans=%+v", spans)
	}
}

func TestTokenize_SkipsDoubleQuotedString(t *testing.T) {
	src := `let s = "fn x()";`
	spans := rusttok.Tokenize(src)
	if !hasKindAt(spans, src, `"fn x()"`, rusttok.KindStringLike) {
		t.Errorf("string literal not classified; spans=%+v", spans)
	}
}

func TestTokenize_SkipsEscapedQuoteInString(t *testing.T) {
	src := `let s = "a\"b"; let r = 1;`
	spans := rusttok.Tokenize(src)
	if !hasKindAt(spans, src, `"a\"b"`, rusttok.KindStringLike) {
		t.Errorf("escaped quote terminated string early; spans=%+v", spans)
	}
	if !hasKindAt(spans, src, "let r = 1;", rusttok.KindCode) {
		t.Errorf("code after string not Code; spans=%+v", spans)
	}
}

func TestTokenize_SkipsRawString_NoHash(t *testing.T) {
	src := `let s = r"fn x()";`
	spans := rusttok.Tokenize(src)
	if !hasKindAt(spans, src, `r"fn x()"`, rusttok.KindStringLike) {
		t.Errorf("raw string not classified; spans=%+v", spans)
	}
}

func TestTokenize_SkipsRawString_OneHash(t *testing.T) {
	src := `let s = r#"fn "x"()"#;`
	spans := rusttok.Tokenize(src)
	if !hasKindAt(spans, src, `r#"fn "x"()"#`, rusttok.KindStringLike) {
		t.Errorf("r#...# string not classified; spans=%+v", spans)
	}
}

func TestTokenize_SkipsRawString_MultipleHashes(t *testing.T) {
	src := `let s = r##"fn "#x()"##;`
	spans := rusttok.Tokenize(src)
	if !hasKindAt(spans, src, `r##"fn "#x()"##`, rusttok.KindStringLike) {
		t.Errorf("r##...## string not classified; spans=%+v", spans)
	}
}

func TestTokenize_SkipsByteString(t *testing.T) {
	src := `let s = b"fn x()";`
	spans := rusttok.Tokenize(src)
	if !hasKindAt(spans, src, `b"fn x()"`, rusttok.KindStringLike) {
		t.Errorf("byte string not classified; spans=%+v", spans)
	}
}

func TestTokenize_SkipsByteRawString(t *testing.T) {
	src := `let s = br#"fn x()"#;`
	spans := rusttok.Tokenize(src)
	if !hasKindAt(spans, src, `br#"fn x()"#`, rusttok.KindStringLike) {
		t.Errorf("byte raw string not classified; spans=%+v", spans)
	}
}

func TestTokenize_SkipsCharLiteral(t *testing.T) {
	src := `let c = 'x'; let n = '\n';`
	spans := rusttok.Tokenize(src)
	if !hasKindAt(spans, src, "'x'", rusttok.KindStringLike) {
		t.Errorf("char literal not classified; spans=%+v", spans)
	}
	if !hasKindAt(spans, src, `'\n'`, rusttok.KindStringLike) {
		t.Errorf("escaped char literal not classified; spans=%+v", spans)
	}
}

func TestTokenize_MixedRegions(t *testing.T) {
	src := "fn a() { let s = \"x\"; /* c */ } fn b() {}"
	spans := rusttok.Tokenize(src)
	if !spansCover(spans, len(src)) {
		t.Fatalf("spans do not cover")
	}
	if !hasKindAt(spans, src, "fn a()", rusttok.KindCode) {
		t.Error("fn a() not Code")
	}
	if !hasKindAt(spans, src, `"x"`, rusttok.KindStringLike) {
		t.Error("string literal not StringLike")
	}
	if !hasKindAt(spans, src, "/* c */", rusttok.KindComment) {
		t.Error("block comment not Comment")
	}
	if !hasKindAt(spans, src, "fn b()", rusttok.KindCode) {
		t.Error("fn b() not Code")
	}
}

func TestTokenize_EmptyInput(t *testing.T) {
	spans := rusttok.Tokenize("")
	if len(spans) != 0 {
		t.Errorf("expected no spans for empty input, got %+v", spans)
	}
}
