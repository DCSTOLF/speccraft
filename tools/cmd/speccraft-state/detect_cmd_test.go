package main

// Spec 0034 — `speccraft-state detect-stack` subcommand (AC3).
//
// Drives the existing run() seam (compile-stable): the assertions fail on
// BEHAVIOR (currently "unknown subcommand") until the case is wired, never on a
// build error. detect-stack prints a versioned JSON envelope and exits 0 for any
// resolvable repo root INCLUDING "unknown"; it exits non-zero only when no
// .speccraft/ root can be resolved (run outside a repo).

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

type detectEnvelope struct {
	Schema       int      `json:"schema"`
	Language     string   `json:"language"`
	TestCommand  string   `json:"test_command"`
	TestPatterns []string `json:"test_patterns"`
	InlineTests  bool     `json:"inline_tests"`
}

// writeManifest drops an empty root-level manifest into the repo.
func writeManifest(t *testing.T, repo, name string) {
	t.Helper()
	if err := os.WriteFile(filepath.Join(repo, name), []byte(""), 0o644); err != nil {
		t.Fatal(err)
	}
}

func decodeDetect(t *testing.T, stdout string) detectEnvelope {
	t.Helper()
	var env detectEnvelope
	if err := json.Unmarshal([]byte(strings.TrimSpace(stdout)), &env); err != nil {
		t.Fatalf("detect-stack stdout is not JSON: %v\nstdout=%q", err, stdout)
	}
	return env
}

func Test_StateCmd_DetectStack_GoFixture_TestCommandIsGoTest(t *testing.T) {
	repo := makeRepo(t)
	writeManifest(t, repo, "go.mod")
	code, stdout, stderr := runCmd(t, repo, "detect-stack")
	if code != 0 {
		t.Fatalf("exit = %d, want 0; stderr=%s", code, stderr)
	}
	env := decodeDetect(t, stdout)
	if env.Schema != 1 {
		t.Errorf("schema = %d, want 1", env.Schema)
	}
	if env.Language != "go" {
		t.Errorf("language = %q, want go", env.Language)
	}
	if env.TestCommand != "go test ./..." {
		t.Errorf("test_command = %q, want %q", env.TestCommand, "go test ./...")
	}
}

func Test_StateCmd_DetectStack_PythonFixture_TestCommandIsPytest_NotGoTest(t *testing.T) {
	repo := makeRepo(t)
	writeManifest(t, repo, "pyproject.toml")
	code, stdout, stderr := runCmd(t, repo, "detect-stack")
	if code != 0 {
		t.Fatalf("exit = %d, want 0; stderr=%s", code, stderr)
	}
	env := decodeDetect(t, stdout)
	if env.Language != "python" {
		t.Errorf("language = %q, want python", env.Language)
	}
	if !strings.Contains(env.TestCommand, "pytest") {
		t.Errorf("test_command = %q, want it to contain pytest", env.TestCommand)
	}
	if env.TestCommand == "go test ./..." {
		t.Errorf("test_command = %q, must NOT be the Go command in a Python repo", env.TestCommand)
	}
}

func Test_StateCmd_DetectStack_Unknown_Exit0_SchemaJSON(t *testing.T) {
	repo := makeRepo(t) // .speccraft/ exists, but no manifest
	code, stdout, stderr := runCmd(t, repo, "detect-stack")
	if code != 0 {
		t.Fatalf("exit = %d, want 0 (unknown is a valid resolvable answer); stderr=%s", code, stderr)
	}
	env := decodeDetect(t, stdout)
	if env.Language != "unknown" {
		t.Errorf("language = %q, want unknown", env.Language)
	}
	if env.TestCommand != "" {
		t.Errorf("test_command = %q, want empty", env.TestCommand)
	}
	if env.TestPatterns == nil || len(env.TestPatterns) != 0 {
		t.Errorf("test_patterns = %#v, want [] (non-null empty array)", env.TestPatterns)
	}
	// The raw JSON must carry [] not null for test_patterns.
	if !strings.Contains(stdout, `"test_patterns":[]`) {
		t.Errorf("raw stdout should encode test_patterns as [], got: %s", strings.TrimSpace(stdout))
	}
}

func Test_StateCmd_Usage_ListsDetectStack(t *testing.T) {
	repo := makeRepo(t)
	code, _, stderr := runCmd(t, repo) // no args → usage on stderr, exit 1
	if code == 0 {
		t.Fatalf("exit = 0, want non-zero for no-args usage")
	}
	if !strings.Contains(stderr, "detect-stack") {
		t.Errorf("usage must list the detect-stack subcommand:\n%s", stderr)
	}
}

func Test_StateCmd_DetectStack_RustFixture_InlineTrue(t *testing.T) {
	repo := makeRepo(t)
	writeManifest(t, repo, "Cargo.toml")
	code, stdout, stderr := runCmd(t, repo, "detect-stack")
	if code != 0 {
		t.Fatalf("exit = %d, want 0; stderr=%s", code, stderr)
	}
	env := decodeDetect(t, stdout)
	if env.Language != "rust" {
		t.Errorf("language = %q, want rust", env.Language)
	}
	if !env.InlineTests {
		t.Errorf("inline_tests = false, want true for rust")
	}
}

func Test_StateCmd_DetectStack_OutsideRepo_ExitsNonZero(t *testing.T) {
	// A dir with no .speccraft/ ancestor → FindRoot fails → non-zero, no stdout.
	outside := t.TempDir()
	code, stdout, stderr := runCmd(t, outside, "detect-stack")
	if code == 0 {
		t.Fatalf("exit = 0, want non-zero when run outside a speccraft repo; stdout=%s", stdout)
	}
	if strings.TrimSpace(stdout) != "" {
		t.Errorf("stdout = %q, want empty on error", stdout)
	}
	_ = stderr
}

// --- test-command subcommand (AC4): effective command = conventions.md marker
// (when present & non-empty) else detect-stack fallback. Marker grammar is a
// single-line HTML comment; the value is data, not shell-evaluated. ---

// writeConventions writes .speccraft/conventions.md with the given body.
func writeConventions(t *testing.T, repo, body string) {
	t.Helper()
	if err := os.WriteFile(filepath.Join(repo, ".speccraft", "conventions.md"), []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
}

func Test_StateCmd_TestCommand_MarkerOverridesDetection(t *testing.T) {
	repo := makeRepo(t)
	writeManifest(t, repo, "go.mod") // detection would say "go test ./..."
	writeConventions(t, repo, "# Conventions\n\n<!-- speccraft:test-command = \"pytest -q\" -->\n")
	code, stdout, stderr := runCmd(t, repo, "test-command")
	if code != 0 {
		t.Fatalf("exit = %d, want 0; stderr=%s", code, stderr)
	}
	if got := strings.TrimSpace(stdout); got != "pytest -q" {
		t.Errorf("test-command = %q, want %q (marker overrides detection)", got, "pytest -q")
	}
}

func Test_StateCmd_TestCommand_RoundTripsShellOperatorAndEscapedQuote(t *testing.T) {
	repo := makeRepo(t)
	writeManifest(t, repo, "go.mod")
	// Marker body contains a shell operator and an escaped quote; it must emit
	// verbatim (unescaped), proving it is data, not evaluated.
	writeConventions(t, repo, "<!-- speccraft:test-command = \"go build && go test -run \\\"X\\\" ./...\" -->\n")
	code, stdout, stderr := runCmd(t, repo, "test-command")
	if code != 0 {
		t.Fatalf("exit = %d, want 0; stderr=%s", code, stderr)
	}
	want := `go build && go test -run "X" ./...`
	if got := strings.TrimSpace(stdout); got != want {
		t.Errorf("test-command = %q, want %q", got, want)
	}
}

func Test_StateCmd_TestCommand_EmptyMarker_FallsBackToDetection(t *testing.T) {
	repo := makeRepo(t)
	writeManifest(t, repo, "go.mod")
	writeConventions(t, repo, "<!-- speccraft:test-command = \"\" -->\n")
	code, stdout, stderr := runCmd(t, repo, "test-command")
	if code != 0 {
		t.Fatalf("exit = %d, want 0; stderr=%s", code, stderr)
	}
	if got := strings.TrimSpace(stdout); got != "go test ./..." {
		t.Errorf("test-command = %q, want detection fallback %q", got, "go test ./...")
	}
}

func Test_StateCmd_TestCommand_MalformedMarker_FallsBackToDetection(t *testing.T) {
	repo := makeRepo(t)
	writeManifest(t, repo, "go.mod")
	// Unescaped interior quote → the quoted-string body regex cannot match → malformed → fallback.
	writeConventions(t, repo, "<!-- speccraft:test-command = \"pytest \"oops\" -q\" -->\n")
	code, stdout, stderr := runCmd(t, repo, "test-command")
	if code != 0 {
		t.Fatalf("exit = %d, want 0; stderr=%s", code, stderr)
	}
	if got := strings.TrimSpace(stdout); got != "go test ./..." {
		t.Errorf("test-command = %q, want detection fallback on malformed marker", got)
	}
}

func Test_StateCmd_TestCommand_DuplicateMarkers_FirstWins(t *testing.T) {
	repo := makeRepo(t)
	writeManifest(t, repo, "go.mod")
	writeConventions(t, repo,
		"<!-- speccraft:test-command = \"first -q\" -->\n<!-- speccraft:test-command = \"second -q\" -->\n")
	code, stdout, stderr := runCmd(t, repo, "test-command")
	if code != 0 {
		t.Fatalf("exit = %d, want 0; stderr=%s", code, stderr)
	}
	if got := strings.TrimSpace(stdout); got != "first -q" {
		t.Errorf("test-command = %q, want first marker to win", got)
	}
}

func Test_StateCmd_TestCommand_UnknownStack_NoMarker_ExitsNonZeroPrintsNothing(t *testing.T) {
	repo := makeRepo(t) // no manifest, no marker → effective command empty
	code, stdout, stderr := runCmd(t, repo, "test-command")
	if code == 0 {
		t.Fatalf("exit = 0, want non-zero when effective command is empty; stdout=%q", stdout)
	}
	if strings.TrimSpace(stdout) != "" {
		t.Errorf("stdout = %q, want empty when no command resolves", stdout)
	}
	_ = stderr
}

func Test_StateCmd_Usage_ListsTestCommand(t *testing.T) {
	repo := makeRepo(t)
	code, _, stderr := runCmd(t, repo)
	if code == 0 {
		t.Fatalf("exit = 0, want non-zero for no-args usage")
	}
	if !strings.Contains(stderr, "test-command") {
		t.Errorf("usage must list the test-command subcommand:\n%s", stderr)
	}
}
