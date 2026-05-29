package speccraft_test

import (
	"testing"

	"github.com/dcstolf/speccraft/tools/internal/speccraft"
)

func TestDiscoverRustTests_InlineFromSrc(t *testing.T) {
	root := t.TempDir()
	writeFile(t, root, "src/foo.rs", "#[cfg(test)]\nmod tests {\n    fn it_works() {}\n    fn it_fails() {}\n}\n")
	ids, err := speccraft.DiscoverRustTests(root)
	if err != nil {
		t.Fatal(err)
	}
	want := []string{"foo::tests::it_fails", "foo::tests::it_works"}
	if !ssEq(ids, want) {
		t.Errorf("got %v, want %v", ids, want)
	}
}

func TestDiscoverRustTests_IntegrationFromTests(t *testing.T) {
	root := t.TempDir()
	writeFile(t, root, "tests/bar.rs", "fn alpha() {}\n")
	ids, err := speccraft.DiscoverRustTests(root)
	if err != nil {
		t.Fatal(err)
	}
	want := []string{"bar::alpha"}
	if !ssEq(ids, want) {
		t.Errorf("got %v, want %v", ids, want)
	}
}

func TestDiscoverRustTests_NestedModule(t *testing.T) {
	root := t.TempDir()
	writeFile(t, root, "src/foo.rs", "#[cfg(test)]\nmod tests {\n    mod inner {\n        fn x() {}\n    }\n}\n")
	ids, err := speccraft.DiscoverRustTests(root)
	if err != nil {
		t.Fatal(err)
	}
	want := []string{"foo::tests::inner::x"}
	if !ssEq(ids, want) {
		t.Errorf("got %v, want %v", ids, want)
	}
}

func TestDiscoverRustTests_WalksLibRsForInline(t *testing.T) {
	root := t.TempDir()
	writeFile(t, root, "src/lib.rs", "#[cfg(test)]\nmod tests {\n    fn x() {}\n}\n")
	ids, err := speccraft.DiscoverRustTests(root)
	if err != nil {
		t.Fatal(err)
	}
	want := []string{"lib::tests::x"}
	if !ssEq(ids, want) {
		t.Errorf("got %v, want %v", ids, want)
	}
}

func TestDiscoverRustTests_SkipsTargetDir(t *testing.T) {
	root := t.TempDir()
	writeFile(t, root, "src/foo.rs", "#[cfg(test)]\nmod tests {\n    fn real() {}\n}\n")
	// A file under target/ that would otherwise look like a test fixture.
	writeFile(t, root, "target/debug/build/somecrate/out.rs", "#[cfg(test)]\nmod tests {\n    fn phantom() {}\n}\n")
	ids, err := speccraft.DiscoverRustTests(root)
	if err != nil {
		t.Fatal(err)
	}
	for _, id := range ids {
		if id == "out::tests::phantom" {
			t.Errorf("discovered ID under target/: %v", ids)
		}
	}
	if !contains(ids, "foo::tests::real") {
		t.Errorf("missed real ID: %v", ids)
	}
}

func TestDiscoverRustTests_Empty(t *testing.T) {
	root := t.TempDir()
	ids, err := speccraft.DiscoverRustTests(root)
	if err != nil {
		t.Fatal(err)
	}
	if len(ids) != 0 {
		t.Errorf("got %v, want empty", ids)
	}
}

func TestJustAddedRustTests_SetDifference(t *testing.T) {
	got := speccraft.JustAddedRustTests([]string{"a::b"}, []string{"a::b", "c::d"})
	want := []string{"c::d"}
	if !ssEq(got, want) {
		t.Errorf("got %v, want %v", got, want)
	}
}

func TestJustAddedRustTests_EmptyBaseline_ReturnsAll(t *testing.T) {
	got := speccraft.JustAddedRustTests(nil, []string{"a", "b"})
	want := []string{"a", "b"}
	if !ssEq(got, want) {
		t.Errorf("got %v, want %v", got, want)
	}
}

func TestJustAddedRustTests_NothingNew(t *testing.T) {
	got := speccraft.JustAddedRustTests([]string{"a", "b"}, []string{"a", "b"})
	if len(got) != 0 {
		t.Errorf("got %v, want empty", got)
	}
}

func TestJustAddedRustTests_Dedup(t *testing.T) {
	got := speccraft.JustAddedRustTests([]string{"a"}, []string{"a", "b", "b", "c"})
	want := []string{"b", "c"}
	if !ssEq(got, want) {
		t.Errorf("got %v, want %v", got, want)
	}
}

func contains(s []string, v string) bool {
	for _, x := range s {
		if x == v {
			return true
		}
	}
	return false
}
