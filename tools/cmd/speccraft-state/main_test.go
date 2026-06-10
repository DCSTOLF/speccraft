package main

import (
	"bytes"
	"encoding/json"
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

// TestStateCmd_Init_CreatesCanonicalEmptyShape pins the post-init state.json
// shape, replacing the literal JSON snippet that commands/init.md used to ask
// the model to Write directly. The hook guardrail introduced by spec 0012
// will block that Write; this subcommand is the sanctioned replacement.
func TestStateCmd_Init_CreatesCanonicalEmptyShape(t *testing.T) {
	repo := makeRepo(t)
	// state.json absent at this point.

	code, _, stderr := runCmd(t, repo, "init")
	if code != 0 {
		t.Fatalf("init exit = %d; stderr=%s", code, stderr)
	}

	raw, err := os.ReadFile(filepath.Join(repo, ".speccraft", "state.json"))
	if err != nil {
		t.Fatalf("state.json not created: %v", err)
	}
	var got map[string]any
	if err := json.Unmarshal(raw, &got); err != nil {
		t.Fatalf("unmarshal: %v\nraw=%s", err, raw)
	}
	if v, ok := got["version"].(float64); !ok || v != 1 {
		t.Errorf("version = %v, want 1", got["version"])
	}
	// active_spec must be absent (omitempty) or JSON null.
	if v, ok := got["active_spec"]; ok && v != nil {
		t.Errorf("active_spec = %v, want absent or null", v)
	}
	session, ok := got["session"].(map[string]any)
	if !ok {
		t.Fatalf("session missing or not object: %v\nraw=%s", got["session"], raw)
	}
	if v, ok := session["id"].(string); !ok || v != "" {
		t.Errorf("session.id = %v, want \"\"", session["id"])
	}
	// edited_test_files and edited_prod_files must be present as empty arrays
	// (not JSON null), matching the literal currently in commands/init.md.
	if v, ok := session["edited_test_files"].([]any); !ok || len(v) != 0 {
		t.Errorf("session.edited_test_files = %v (%T), want []",
			session["edited_test_files"], session["edited_test_files"])
	}
	if v, ok := session["edited_prod_files"].([]any); !ok || len(v) != 0 {
		t.Errorf("session.edited_prod_files = %v (%T), want []",
			session["edited_prod_files"], session["edited_prod_files"])
	}
}

// TestStateCmd_Init_Idempotent_PreservesExistingState pins that re-running
// `speccraft-state init` against an existing state.json is a no-op: an
// /speccraft:init re-run cannot silently nuke session state.
func TestStateCmd_Init_Idempotent_PreservesExistingState(t *testing.T) {
	repo := makeRepo(t)
	// Seed with a real spec id so we can tell the difference between
	// "init re-ran cleanly" and "init clobbered everything".
	if code, _, stderr := runCmd(t, repo, "set", "active_spec", "0099-foo"); code != 0 {
		t.Fatalf("seed active_spec: exit=%d, stderr=%s", code, stderr)
	}
	pre, err := os.ReadFile(filepath.Join(repo, ".speccraft", "state.json"))
	if err != nil {
		t.Fatal(err)
	}

	if code, _, stderr := runCmd(t, repo, "init"); code != 0 {
		t.Fatalf("init: exit=%d, stderr=%s", code, stderr)
	}

	post, err := os.ReadFile(filepath.Join(repo, ".speccraft", "state.json"))
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(pre, post) {
		t.Errorf("init mutated existing state.json\npre=%s\npost=%s", pre, post)
	}
}
