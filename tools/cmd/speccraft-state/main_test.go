package main

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// makeRepo creates a temp dir with an empty .speccraft/.
func makeRepo(t *testing.T) string {
	t.Helper()
	tmp := t.TempDir()
	if err := os.MkdirAll(filepath.Join(tmp, ".speccraft"), 0o755); err != nil {
		t.Fatal(err)
	}
	return tmp
}

func runCmd(t *testing.T, repo string, args ...string) (int, string, string) {
	t.Helper()
	cwd, _ := os.Getwd()
	if err := os.Chdir(repo); err != nil {
		t.Fatal(err)
	}
	defer os.Chdir(cwd)
	var stdout, stderr bytes.Buffer
	code := run(args, &stdout, &stderr)
	return code, stdout.String(), stderr.String()
}

func TestStateCmd_GetRustTestBaseline_EmptyByDefault(t *testing.T) {
	repo := makeRepo(t)
	code, stdout, stderr := runCmd(t, repo, "get", "rust_test_baseline")
	if code != 0 {
		t.Fatalf("exit = %d, want 0; stderr=%s", code, stderr)
	}
	got := strings.TrimSpace(stdout)
	if got != "[]" {
		t.Errorf("stdout = %q, want %q", got, "[]")
	}
}

func TestStateCmd_SetRustTestBaseline_PersistsList(t *testing.T) {
	repo := makeRepo(t)
	if code, _, stderr := runCmd(t, repo, "set", "rust_test_baseline", `["a::b","c::d"]`); code != 0 {
		t.Fatalf("set exit = %d; stderr=%s", code, stderr)
	}
	code, stdout, stderr := runCmd(t, repo, "get", "rust_test_baseline")
	if code != 0 {
		t.Fatalf("get exit = %d; stderr=%s", code, stderr)
	}
	got := strings.TrimSpace(stdout)
	if got != `["a::b","c::d"]` {
		t.Errorf("stdout = %q, want %q", got, `["a::b","c::d"]`)
	}
}

func TestStateCmd_AppendRustBaseline_DedupsAndSorts(t *testing.T) {
	repo := makeRepo(t)
	if code, _, stderr := runCmd(t, repo, "set", "rust_test_baseline", `["a::b"]`); code != 0 {
		t.Fatalf("set exit = %d; stderr=%s", code, stderr)
	}
	// Append a new ID + a duplicate of the existing one → union, sorted.
	if code, _, stderr := runCmd(t, repo, "rust-baseline", "append", `["c::d","a::b"]`); code != 0 {
		t.Fatalf("append exit = %d; stderr=%s", code, stderr)
	}
	code, stdout, stderr := runCmd(t, repo, "get", "rust_test_baseline")
	if code != 0 {
		t.Fatalf("get exit = %d; stderr=%s", code, stderr)
	}
	got := strings.TrimSpace(stdout)
	if got != `["a::b","c::d"]` {
		t.Errorf("stdout = %q, want %q (sorted, deduped union)", got, `["a::b","c::d"]`)
	}
}

func TestStateCmd_AppendRustBaseline_FromEmpty(t *testing.T) {
	repo := makeRepo(t)
	if code, _, stderr := runCmd(t, repo, "rust-baseline", "append", `["a::b","c::d"]`); code != 0 {
		t.Fatalf("append exit = %d; stderr=%s", code, stderr)
	}
	_, stdout, _ := runCmd(t, repo, "get", "rust_test_baseline")
	got := strings.TrimSpace(stdout)
	if got != `["a::b","c::d"]` {
		t.Errorf("stdout = %q, want %q", got, `["a::b","c::d"]`)
	}
}

func TestStateCmd_GetRustGateFingerprint_EmptyByDefault(t *testing.T) {
	repo := makeRepo(t)
	code, stdout, stderr := runCmd(t, repo, "get", "rust_gate_fingerprint")
	if code != 0 {
		t.Fatalf("exit = %d, want 0; stderr=%s", code, stderr)
	}
	got := strings.TrimSpace(stdout)
	if got != "" && got != "null" {
		t.Errorf("stdout = %q, want empty or \"null\"", got)
	}
}

func TestStateCmd_SetRustGateFingerprint_Persists(t *testing.T) {
	repo := makeRepo(t)
	if code, _, stderr := runCmd(t, repo, "set", "rust_gate_fingerprint", "deadbeef"); code != 0 {
		t.Fatalf("set exit = %d; stderr=%s", code, stderr)
	}
	code, stdout, stderr := runCmd(t, repo, "get", "rust_gate_fingerprint")
	if code != 0 {
		t.Fatalf("get exit = %d; stderr=%s", code, stderr)
	}
	got := strings.TrimSpace(stdout)
	if got != "deadbeef" {
		t.Errorf("stdout = %q, want %q", got, "deadbeef")
	}
}

func TestStateCmd_SetRustTestBaseline_RejectsInvalidJSON(t *testing.T) {
	repo := makeRepo(t)
	code, _, stderr := runCmd(t, repo, "set", "rust_test_baseline", `not json`)
	if code == 0 {
		t.Fatal("expected non-zero exit for invalid JSON")
	}
	if !strings.Contains(stderr, "rust_test_baseline") && !strings.Contains(stderr, "json") {
		t.Errorf("stderr does not mention field or json: %q", stderr)
	}
}

func TestStateCmd_RustBaselineRecapture_OverwritesFromWalk(t *testing.T) {
	repo := makeRepo(t)
	// Seed a stale baseline + a real Rust fixture.
	if code, _, stderr := runCmd(t, repo, "set", "rust_test_baseline", `["stale::x"]`); code != 0 {
		t.Fatalf("seed: exit=%d, stderr=%s", code, stderr)
	}
	if err := os.MkdirAll(filepath.Join(repo, "src"), 0o755); err != nil {
		t.Fatal(err)
	}
	src := "#[cfg(test)]\nmod tests {\n    fn a() {}\n}\n"
	if err := os.WriteFile(filepath.Join(repo, "src", "foo.rs"), []byte(src), 0o644); err != nil {
		t.Fatal(err)
	}
	code, stdout, stderr := runCmd(t, repo, "rust-baseline", "recapture")
	if code != 0 {
		t.Fatalf("recapture: exit=%d, stderr=%s", code, stderr)
	}
	if !strings.Contains(stdout, "recaptured") {
		t.Errorf("stdout does not announce recapture: %q", stdout)
	}
	// Confirm baseline is now the freshly-walked list.
	_, getOut, _ := runCmd(t, repo, "get", "rust_test_baseline")
	got := strings.TrimSpace(getOut)
	if got != `["foo::tests::a"]` {
		t.Errorf("baseline = %q, want %q", got, `["foo::tests::a"]`)
	}
}

func TestStateCmd_RustBaselineRecapture_EmptyCrate_ClearsBaseline(t *testing.T) {
	repo := makeRepo(t)
	if code, _, stderr := runCmd(t, repo, "set", "rust_test_baseline", `["stale::x","more::stale"]`); code != 0 {
		t.Fatalf("seed: %d %s", code, stderr)
	}
	code, _, stderr := runCmd(t, repo, "rust-baseline", "recapture")
	if code != 0 {
		t.Fatalf("recapture: %d %s", code, stderr)
	}
	_, getOut, _ := runCmd(t, repo, "get", "rust_test_baseline")
	if got := strings.TrimSpace(getOut); got != "[]" {
		t.Errorf("baseline = %q, want %q", got, "[]")
	}
}
