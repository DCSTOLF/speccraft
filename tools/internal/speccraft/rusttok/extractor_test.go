package rusttok_test

import (
	"testing"

	"github.com/dcstolf/speccraft/tools/internal/speccraft/rusttok"
)

func TestExtractFnNames_SingleFn(t *testing.T) {
	got := rusttok.ExtractFnNames("fn it() {}")
	if len(got) != 1 || got[0] != "it" {
		t.Errorf("got %v, want [it]", got)
	}
}

func TestExtractFnNames_MultipleFns(t *testing.T) {
	got := rusttok.ExtractFnNames("fn a() {} fn b() {}")
	want := []string{"a", "b"}
	if !sliceEqual(got, want) {
		t.Errorf("got %v, want %v", got, want)
	}
}

func TestExtractFnNames_IgnoresFnInString(t *testing.T) {
	got := rusttok.ExtractFnNames(`let s = "fn x()";`)
	if len(got) != 0 {
		t.Errorf("expected no names, got %v", got)
	}
}

func TestExtractFnNames_IgnoresFnInComment(t *testing.T) {
	got := rusttok.ExtractFnNames("// fn x()\n")
	if len(got) != 0 {
		t.Errorf("expected no names, got %v", got)
	}
}

func TestExtractFnNames_IgnoresFnInBlockComment(t *testing.T) {
	got := rusttok.ExtractFnNames("/* fn x() */")
	if len(got) != 0 {
		t.Errorf("expected no names, got %v", got)
	}
}

func TestExtractFnNames_IgnoresFnInRawString(t *testing.T) {
	got := rusttok.ExtractFnNames(`let s = r#"fn x()"#;`)
	if len(got) != 0 {
		t.Errorf("expected no names, got %v", got)
	}
}

func TestExtractFnNames_AsyncFnRecognized(t *testing.T) {
	got := rusttok.ExtractFnNames("async fn it() {}")
	if len(got) != 1 || got[0] != "it" {
		t.Errorf("got %v, want [it]", got)
	}
}

func TestExtractFnNames_PubFnRecognized(t *testing.T) {
	got := rusttok.ExtractFnNames("pub fn it() {}")
	if len(got) != 1 || got[0] != "it" {
		t.Errorf("got %v, want [it]", got)
	}
}

func TestExtractFnNames_GenericFnRecognized(t *testing.T) {
	got := rusttok.ExtractFnNames("fn it<T>(x: T) {}")
	if len(got) != 1 || got[0] != "it" {
		t.Errorf("got %v, want [it]", got)
	}
}

func TestExtractFnNames_PubCrateFnRecognized(t *testing.T) {
	got := rusttok.ExtractFnNames("pub(crate) fn it() {}")
	if len(got) != 1 || got[0] != "it" {
		t.Errorf("got %v, want [it]", got)
	}
}

func TestExtractFnNames_MixedCodeAndStrings(t *testing.T) {
	src := `
fn outer() {
    let s = "fn fake_inside()";
    // fn also_fake()
}
fn other() {}
`
	got := rusttok.ExtractFnNames(src)
	want := []string{"outer", "other"}
	if !sliceEqual(got, want) {
		t.Errorf("got %v, want %v", got, want)
	}
}

func sliceEqual(a, b []string) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}
