package speccraft_test

import (
	"bytes"
	"os"
	"path/filepath"
	"testing"

	"github.com/dcstolf/speccraft/tools/internal/speccraft"
)

func TestFindRoot(t *testing.T) {
	tmp := t.TempDir()
	specDir := filepath.Join(tmp, ".speccraft")
	if err := os.MkdirAll(specDir, 0o755); err != nil {
		t.Fatal(err)
	}
	subdir := filepath.Join(tmp, "pkg", "foo")
	if err := os.MkdirAll(subdir, 0o755); err != nil {
		t.Fatal(err)
	}
	// Find from subdir.
	root, err := speccraft.FindRoot(subdir)
	if err != nil {
		t.Fatalf("FindRoot: %v", err)
	}
	if root != tmp {
		t.Errorf("FindRoot = %q, want %q", root, tmp)
	}
	// No .speccraft → error.
	noSpec := t.TempDir()
	_, err = speccraft.FindRoot(noSpec)
	if err == nil {
		t.Error("expected error when no .speccraft dir")
	}
}

func TestStateRoundTrip(t *testing.T) {
	tmp := t.TempDir()
	if err := os.MkdirAll(filepath.Join(tmp, ".speccraft"), 0o755); err != nil {
		t.Fatal(err)
	}
	// Load from absent file → zero state.
	s, err := speccraft.LoadState(tmp)
	if err != nil {
		t.Fatal(err)
	}
	if s.Version != 1 {
		t.Errorf("Version = %d, want 1", s.Version)
	}
	// Set and get.
	if err := speccraft.SetField(tmp, "active_spec", "0001-foo"); err != nil {
		t.Fatal(err)
	}
	val, err := speccraft.GetField(tmp, "active_spec")
	if err != nil {
		t.Fatal(err)
	}
	if val != "0001-foo" {
		t.Errorf("active_spec = %q, want %q", val, "0001-foo")
	}
}

func TestTrackEdit(t *testing.T) {
	tmp := t.TempDir()
	if err := os.MkdirAll(filepath.Join(tmp, ".speccraft"), 0o755); err != nil {
		t.Fatal(err)
	}
	testFile := filepath.Join(tmp, "pkg", "foo_test.go")
	prodFile := filepath.Join(tmp, "pkg", "foo.go")

	if err := speccraft.TrackEdit(tmp, testFile); err != nil {
		t.Fatal(err)
	}
	s, _ := speccraft.LoadState(tmp)
	if len(s.Session.EditedTestFiles) != 1 || s.Session.EditedTestFiles[0] != testFile {
		t.Errorf("EditedTestFiles = %v, want [%s]", s.Session.EditedTestFiles, testFile)
	}
	// Dedup: same file twice → still one entry.
	if err := speccraft.TrackEdit(tmp, testFile); err != nil {
		t.Fatal(err)
	}
	s, _ = speccraft.LoadState(tmp)
	if len(s.Session.EditedTestFiles) != 1 {
		t.Errorf("dedup failed: got %d entries", len(s.Session.EditedTestFiles))
	}

	if err := speccraft.TrackEdit(tmp, prodFile); err != nil {
		t.Fatal(err)
	}
	s, _ = speccraft.LoadState(tmp)
	if len(s.Session.EditedProdFiles) != 1 {
		t.Errorf("EditedProdFiles = %v", s.Session.EditedProdFiles)
	}
}

func TestResetSession(t *testing.T) {
	tmp := t.TempDir()
	if err := os.MkdirAll(filepath.Join(tmp, ".speccraft"), 0o755); err != nil {
		t.Fatal(err)
	}
	// Set active spec and some session state.
	speccraft.SetField(tmp, "active_spec", "0001-foo")
	speccraft.TrackEdit(tmp, filepath.Join(tmp, "main_test.go"))

	if err := speccraft.ResetSession(tmp); err != nil {
		t.Fatal(err)
	}
	s, _ := speccraft.LoadState(tmp)
	// Active spec must survive reset.
	if s.ActiveSpec != "0001-foo" {
		t.Errorf("active_spec cleared unexpectedly: %q", s.ActiveSpec)
	}
	// Session fields must be empty.
	if len(s.Session.EditedTestFiles) != 0 {
		t.Errorf("EditedTestFiles not cleared: %v", s.Session.EditedTestFiles)
	}
}

func TestSession_RustTestBaseline_RoundTrip(t *testing.T) {
	tmp := t.TempDir()
	if err := os.MkdirAll(filepath.Join(tmp, ".speccraft"), 0o755); err != nil {
		t.Fatal(err)
	}
	s, _ := speccraft.LoadState(tmp)
	s.Session.RustTestBaseline = []string{"foo::tests::a", "tests::bar::b"}
	if err := speccraft.SaveState(tmp, s); err != nil {
		t.Fatal(err)
	}
	got, err := speccraft.LoadState(tmp)
	if err != nil {
		t.Fatal(err)
	}
	want := []string{"foo::tests::a", "tests::bar::b"}
	if len(got.Session.RustTestBaseline) != len(want) {
		t.Fatalf("RustTestBaseline = %v, want %v", got.Session.RustTestBaseline, want)
	}
	for i, v := range want {
		if got.Session.RustTestBaseline[i] != v {
			t.Errorf("RustTestBaseline[%d] = %q, want %q", i, got.Session.RustTestBaseline[i], v)
		}
	}
}

func TestSession_RustGateFingerprint_RoundTrip(t *testing.T) {
	tmp := t.TempDir()
	if err := os.MkdirAll(filepath.Join(tmp, ".speccraft"), 0o755); err != nil {
		t.Fatal(err)
	}
	s, _ := speccraft.LoadState(tmp)
	s.Session.RustGateFingerprint = "abc123def456"
	if err := speccraft.SaveState(tmp, s); err != nil {
		t.Fatal(err)
	}
	got, err := speccraft.LoadState(tmp)
	if err != nil {
		t.Fatal(err)
	}
	if got.Session.RustGateFingerprint != "abc123def456" {
		t.Errorf("RustGateFingerprint = %q, want %q", got.Session.RustGateFingerprint, "abc123def456")
	}
}

func TestSession_RustFields_EmptyByDefault(t *testing.T) {
	tmp := t.TempDir()
	if err := os.MkdirAll(filepath.Join(tmp, ".speccraft"), 0o755); err != nil {
		t.Fatal(err)
	}
	s, err := speccraft.LoadState(tmp)
	if err != nil {
		t.Fatal(err)
	}
	if len(s.Session.RustTestBaseline) != 0 {
		t.Errorf("RustTestBaseline = %v, want empty", s.Session.RustTestBaseline)
	}
	if s.Session.RustGateFingerprint != "" {
		t.Errorf("RustGateFingerprint = %q, want empty", s.Session.RustGateFingerprint)
	}
}

func TestConsumeOverride_FlagSet_ReturnsTrueAndClears(t *testing.T) {
	tmp := t.TempDir()
	if err := os.MkdirAll(filepath.Join(tmp, ".speccraft"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := speccraft.SetField(tmp, "override_pending", "true"); err != nil {
		t.Fatal(err)
	}
	got, err := speccraft.ConsumeOverride(tmp)
	if err != nil {
		t.Fatalf("first ConsumeOverride: %v", err)
	}
	if !got {
		t.Error("first ConsumeOverride = false, want true")
	}
	got, err = speccraft.ConsumeOverride(tmp)
	if err != nil {
		t.Fatalf("second ConsumeOverride: %v", err)
	}
	if got {
		t.Error("second ConsumeOverride = true, want false (flag must be single-use)")
	}
	// Verify omitempty: key must be absent from disk after consume.
	raw, err := os.ReadFile(filepath.Join(tmp, ".speccraft", "state.json"))
	if err != nil {
		t.Fatal(err)
	}
	if bytes.Contains(raw, []byte("override_pending")) {
		t.Errorf("state.json still contains override_pending key after consume: %s", raw)
	}
}

func TestConsumeOverride_FlagUnset_ReturnsFalse(t *testing.T) {
	tmp := t.TempDir()
	if err := os.MkdirAll(filepath.Join(tmp, ".speccraft"), 0o755); err != nil {
		t.Fatal(err)
	}
	got, err := speccraft.ConsumeOverride(tmp)
	if err != nil {
		t.Fatalf("ConsumeOverride on fresh state: %v", err)
	}
	if got {
		t.Error("ConsumeOverride on unset flag = true, want false")
	}
}

func TestConsumeOverride_AbsentStateFile_ReturnsFalse(t *testing.T) {
	tmp := t.TempDir()
	if err := os.MkdirAll(filepath.Join(tmp, ".speccraft"), 0o755); err != nil {
		t.Fatal(err)
	}
	// No state.json written — mirrors loadStateLocked no-file behaviour.
	got, err := speccraft.ConsumeOverride(tmp)
	if err != nil {
		t.Fatalf("ConsumeOverride with absent state.json: %v", err)
	}
	if got {
		t.Error("ConsumeOverride with absent state file = true, want false")
	}
}

func TestSetField_OverridePending_RoundTrip(t *testing.T) {
	tmp := t.TempDir()
	if err := os.MkdirAll(filepath.Join(tmp, ".speccraft"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := speccraft.SetField(tmp, "override_pending", "true"); err != nil {
		t.Fatal(err)
	}
	s, err := speccraft.LoadState(tmp)
	if err != nil {
		t.Fatal(err)
	}
	if !s.Session.OverridePending {
		t.Error("OverridePending = false after SetField true, want true")
	}
	if err := speccraft.SetField(tmp, "override_pending", "false"); err != nil {
		t.Fatal(err)
	}
	s, err = speccraft.LoadState(tmp)
	if err != nil {
		t.Fatal(err)
	}
	if s.Session.OverridePending {
		t.Error("OverridePending = true after SetField false, want false")
	}
}

func TestGetField_OverridePending(t *testing.T) {
	cases := []struct {
		name  string
		setup func(root string)
		want  string
	}{
		{
			name:  "set true",
			setup: func(root string) { speccraft.SetField(root, "override_pending", "true") },
			want:  "true",
		},
		{
			name:  "set false",
			setup: func(root string) { speccraft.SetField(root, "override_pending", "false") },
			want:  "false",
		},
		{
			name:  "unset",
			setup: func(root string) {},
			want:  "false",
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			tmp := t.TempDir()
			if err := os.MkdirAll(filepath.Join(tmp, ".speccraft"), 0o755); err != nil {
				t.Fatal(err)
			}
			tc.setup(tmp)
			got, err := speccraft.GetField(tmp, "override_pending")
			if err != nil {
				t.Fatal(err)
			}
			if got != tc.want {
				t.Errorf("GetField(override_pending) = %q, want %q", got, tc.want)
			}
		})
	}
}

func TestTasksDonePct(t *testing.T) {
	tmp := t.TempDir()
	if err := os.MkdirAll(filepath.Join(tmp, ".speccraft"), 0o755); err != nil {
		t.Fatal(err)
	}
	speccraft.SetField(tmp, "active_spec", "0001-foo")
	specDir := filepath.Join(tmp, "specs", "0001-foo")
	if err := os.MkdirAll(specDir, 0o755); err != nil {
		t.Fatal(err)
	}
	tasks := "- [x] T1\n- [x] T2\n- [ ] T3\n- [ ] T4\n"
	if err := os.WriteFile(filepath.Join(specDir, "tasks.md"), []byte(tasks), 0o644); err != nil {
		t.Fatal(err)
	}
	pct, err := speccraft.TasksDonePct(tmp)
	if err != nil {
		t.Fatal(err)
	}
	if pct != 50 {
		t.Errorf("TasksDonePct = %d, want 50", pct)
	}
}

// --- Spec 0018: RedCandidates session field ---

func mkRoot0018(t *testing.T) string {
	t.Helper()
	tmp := t.TempDir()
	if err := os.MkdirAll(filepath.Join(tmp, ".speccraft"), 0o755); err != nil {
		t.Fatal(err)
	}
	return tmp
}

func Test_SetRedCandidates_PersistsPerFile(t *testing.T) {
	root := mkRoot0018(t)
	if err := speccraft.SetRedCandidates(root, "/repo/pkg/foo_test.go", []string{"TestNew", "TestNew"}); err != nil {
		t.Fatalf("SetRedCandidates: %v", err)
	}
	if err := speccraft.SetRedCandidates(root, "/repo/pkg/bar_test.go", []string{"TestBar"}); err != nil {
		t.Fatalf("SetRedCandidates: %v", err)
	}
	got, err := speccraft.GetRedCandidates(root)
	if err != nil {
		t.Fatalf("GetRedCandidates: %v", err)
	}
	if !eq0018(got["/repo/pkg/foo_test.go"], []string{"TestNew"}) {
		t.Errorf("foo candidates = %v, want dedup'd [TestNew]", got["/repo/pkg/foo_test.go"])
	}
	if !eq0018(got["/repo/pkg/bar_test.go"], []string{"TestBar"}) {
		t.Errorf("bar candidates = %v, want [TestBar]", got["/repo/pkg/bar_test.go"])
	}
}

func Test_SetRedCandidates_OverwritesPerFile(t *testing.T) {
	root := mkRoot0018(t)
	speccraft.SetRedCandidates(root, "/repo/pkg/foo_test.go", []string{"TestA"})
	speccraft.SetRedCandidates(root, "/repo/pkg/foo_test.go", []string{"TestB"})
	got, _ := speccraft.GetRedCandidates(root)
	if !eq0018(got["/repo/pkg/foo_test.go"], []string{"TestB"}) {
		t.Errorf("expected overwrite to [TestB], got %v", got["/repo/pkg/foo_test.go"])
	}
}

func Test_GetRedCandidates_EmptyWhenUnset(t *testing.T) {
	root := mkRoot0018(t)
	got, err := speccraft.GetRedCandidates(root)
	if err != nil {
		t.Fatalf("GetRedCandidates: %v", err)
	}
	if len(got) != 0 {
		t.Errorf("expected empty map, got %v", got)
	}
}

func Test_ResetSession_ClearsRedCandidates(t *testing.T) {
	root := mkRoot0018(t)
	speccraft.SetRedCandidates(root, "/repo/pkg/foo_test.go", []string{"TestNew"})
	if err := speccraft.ResetSession(root); err != nil {
		t.Fatalf("ResetSession: %v", err)
	}
	got, _ := speccraft.GetRedCandidates(root)
	if len(got) != 0 {
		t.Errorf("expected RedCandidates cleared after ResetSession, got %v", got)
	}
}

func eq0018(a, b []string) bool {
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
