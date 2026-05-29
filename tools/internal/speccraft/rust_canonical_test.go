package speccraft_test

import (
	"testing"

	"github.com/dcstolf/speccraft/tools/internal/speccraft"
)

func TestCanonicalInlineTestIDs_SingleMod(t *testing.T) {
	src := "#[cfg(test)]\nmod tests {\n    fn it_works() {}\n}\n"
	got := speccraft.CanonicalInlineTestIDs(src, "foo")
	want := []string{"foo::tests::it_works"}
	if !ssEq(got, want) {
		t.Errorf("got %v, want %v", got, want)
	}
}

func TestCanonicalInlineTestIDs_MultipleFns(t *testing.T) {
	src := "#[cfg(test)]\nmod tests {\n    fn a() {}\n    fn b() {}\n}\n"
	got := speccraft.CanonicalInlineTestIDs(src, "foo")
	want := []string{"foo::tests::a", "foo::tests::b"}
	if !ssEq(got, want) {
		t.Errorf("got %v, want %v", got, want)
	}
}

func TestCanonicalInlineTestIDs_NestedMod(t *testing.T) {
	src := "#[cfg(test)]\nmod tests {\n    mod inner {\n        fn x() {}\n    }\n}\n"
	got := speccraft.CanonicalInlineTestIDs(src, "foo")
	want := []string{"foo::tests::inner::x"}
	if !ssEq(got, want) {
		t.Errorf("got %v, want %v", got, want)
	}
}

func TestCanonicalInlineTestIDs_IgnoresStringLiteralFn(t *testing.T) {
	src := `#[cfg(test)]
mod tests {
    let s = "fn fake() {}";
    fn real() {}
}
`
	got := speccraft.CanonicalInlineTestIDs(src, "foo")
	want := []string{"foo::tests::real"}
	if !ssEq(got, want) {
		t.Errorf("got %v, want %v", got, want)
	}
}

func TestCanonicalInlineTestIDs_NoCfgTest_NoIDs(t *testing.T) {
	src := "mod something {\n    fn x() {}\n}\n"
	got := speccraft.CanonicalInlineTestIDs(src, "foo")
	if len(got) != 0 {
		t.Errorf("got %v, want []", got)
	}
}

func TestCanonicalIntegrationTestIDs_TopLevelFns(t *testing.T) {
	src := "fn alpha() {}\nfn beta() {}\n"
	got := speccraft.CanonicalIntegrationTestIDs(src, "bar")
	want := []string{"bar::alpha", "bar::beta"}
	if !ssEq(got, want) {
		t.Errorf("got %v, want %v", got, want)
	}
}

func TestCanonicalIntegrationTestIDs_IgnoresStringLiterals(t *testing.T) {
	src := `let s = "fn fake() {}";
fn real() {}
`
	got := speccraft.CanonicalIntegrationTestIDs(src, "bar")
	want := []string{"bar::real"}
	if !ssEq(got, want) {
		t.Errorf("got %v, want %v", got, want)
	}
}

func ssEq(a, b []string) bool {
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
