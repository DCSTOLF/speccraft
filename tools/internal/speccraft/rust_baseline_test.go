package speccraft_test

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/dcstolf/speccraft/tools/internal/speccraft"
)

// mkBaselineRepo creates a temp repo with .speccraft/ and writes the
// given files relative to root.
func mkBaselineRepo(t *testing.T, files map[string]string) string {
	t.Helper()
	root := t.TempDir()
	if err := os.MkdirAll(filepath.Join(root, ".speccraft"), 0o755); err != nil {
		t.Fatal(err)
	}
	for rel, content := range files {
		writeFile(t, root, rel, content)
	}
	return root
}

func TestRustBaseline_InitialCapture_WritesWalkedIDs(t *testing.T) {
	root := mkBaselineRepo(t, map[string]string{
		"src/foo.rs": "#[cfg(test)]\nmod tests {\n    fn a() {}\n    fn b() {}\n}\n",
		"tests/bar.rs": "fn alpha() {}\n",
	})
	// Baseline empty by default.
	captured, count, err := speccraft.CaptureInitialRustBaseline(root)
	if err != nil {
		t.Fatal(err)
	}
	if !captured {
		t.Error("expected captured=true on empty baseline")
	}
	if count != 3 {
		t.Errorf("count=%d, want 3", count)
	}
	got, _ := speccraft.GetRustBaseline(root)
	want := []string{"bar::alpha", "foo::tests::a", "foo::tests::b"}
	if !ssEq(got, want) {
		t.Errorf("baseline = %v, want %v", got, want)
	}
}

func TestRustBaseline_InitialCapture_SkipsWhenNonEmpty(t *testing.T) {
	root := mkBaselineRepo(t, map[string]string{
		"src/foo.rs": "#[cfg(test)]\nmod tests {\n    fn a() {}\n}\n",
	})
	speccraft.SetRustBaseline(root, []string{"x::y"})
	captured, count, err := speccraft.CaptureInitialRustBaseline(root)
	if err != nil {
		t.Fatal(err)
	}
	if captured {
		t.Error("expected captured=false when baseline non-empty")
	}
	if count != 0 {
		t.Errorf("count=%d, want 0", count)
	}
	got, _ := speccraft.GetRustBaseline(root)
	if !ssEq(got, []string{"x::y"}) {
		t.Errorf("baseline mutated unexpectedly: %v", got)
	}
}

func TestRustBaseline_PostAcceptUpdate_AppendsFailingJustAddedOnly(t *testing.T) {
	root := mkBaselineRepo(t, nil)
	// just-added: {a::b, c::d, e::f}; failed runner records: {a::b, e::f, g::h}.
	// Expected appended: {a::b, e::f} — failed AND in just-added; c::d (passed) and g::h (not just-added) excluded.
	justAdded := []string{"a::b", "c::d", "e::f"}
	failedTestNames := []string{"a::b", "e::f", "g::h"}
	if err := speccraft.PostAcceptUpdateRustBaseline(root, justAdded, failedTestNames); err != nil {
		t.Fatal(err)
	}
	got, _ := speccraft.GetRustBaseline(root)
	want := []string{"a::b", "e::f"}
	if !ssEq(got, want) {
		t.Errorf("baseline = %v, want %v", got, want)
	}
}

func TestRustBaseline_PostAcceptUpdate_DedupsAgainstExisting(t *testing.T) {
	root := mkBaselineRepo(t, nil)
	speccraft.SetRustBaseline(root, []string{"a::b"})
	if err := speccraft.PostAcceptUpdateRustBaseline(root,
		[]string{"a::b", "c::d"}, []string{"a::b", "c::d"}); err != nil {
		t.Fatal(err)
	}
	got, _ := speccraft.GetRustBaseline(root)
	want := []string{"a::b", "c::d"}
	if !ssEq(got, want) {
		t.Errorf("baseline = %v, want %v (deduped)", got, want)
	}
}

func TestRustBaseline_PostAcceptUpdate_NoFailingInSet_NoOp(t *testing.T) {
	root := mkBaselineRepo(t, nil)
	speccraft.SetRustBaseline(root, []string{"existing::id"})
	// Failed set has nothing in common with just-added.
	if err := speccraft.PostAcceptUpdateRustBaseline(root,
		[]string{"a::b"}, []string{"g::h"}); err != nil {
		t.Fatal(err)
	}
	got, _ := speccraft.GetRustBaseline(root)
	if !ssEq(got, []string{"existing::id"}) {
		t.Errorf("baseline = %v, want unchanged", got)
	}
}

func TestRustBaseline_ManualRecapture_OverwritesBaseline(t *testing.T) {
	root := mkBaselineRepo(t, map[string]string{
		"src/foo.rs": "#[cfg(test)]\nmod tests {\n    fn a() {}\n}\n",
	})
	speccraft.SetRustBaseline(root, []string{"stale::x"})
	count, err := speccraft.RecaptureRustBaseline(root)
	if err != nil {
		t.Fatal(err)
	}
	if count != 1 {
		t.Errorf("count=%d, want 1", count)
	}
	got, _ := speccraft.GetRustBaseline(root)
	want := []string{"foo::tests::a"}
	if !ssEq(got, want) {
		t.Errorf("baseline = %v, want %v (stale entries removed)", got, want)
	}
}

func TestRustBaseline_ManualRecapture_EmptyCrate_ClearsBaseline(t *testing.T) {
	root := mkBaselineRepo(t, nil)
	speccraft.SetRustBaseline(root, []string{"stale::x"})
	count, err := speccraft.RecaptureRustBaseline(root)
	if err != nil {
		t.Fatal(err)
	}
	if count != 0 {
		t.Errorf("count=%d, want 0", count)
	}
	got, _ := speccraft.GetRustBaseline(root)
	if len(got) != 0 {
		t.Errorf("baseline = %v, want empty", got)
	}
}
