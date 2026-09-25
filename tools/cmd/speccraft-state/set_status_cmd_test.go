package main

// Spec 0036 T13 (AC8, AC9) — `speccraft-state set-status <spec.md> <status>`.

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func Test_StateCmd_SetStatus_ValidWrites_InvalidNonZero(t *testing.T) {
	repo := makeRepo(t)
	specDir := mkSpecDir(t, repo, "0001-x", "---\nstatus: draft\n---\n# S\n")
	spec := filepath.Join(specDir, "spec.md")
	if code, _, se := runCmd(t, repo, "set-status", spec, "reviewed"); code != 0 {
		t.Fatalf("valid status exit=%d stderr=%s", code, se)
	}
	b, _ := os.ReadFile(spec)
	if !strings.Contains(string(b), "status: reviewed") {
		t.Errorf("status not written: %s", b)
	}
	if code, _, _ := runCmd(t, repo, "set-status", spec, "bogus"); code == 0 {
		t.Error("invalid status must exit non-zero")
	}
}

func Test_StateCmd_SetStatus_RefusesClosed(t *testing.T) {
	repo := makeRepo(t)
	specDir := mkSpecDir(t, repo, "0001-x", "---\nstatus: closed\n---\n# S\n")
	spec := filepath.Join(specDir, "spec.md")
	if code, _, _ := runCmd(t, repo, "set-status", spec, "draft"); code == 0 {
		t.Error("mutating a closed spec must exit non-zero")
	}
}

// --- spec 0049: the --kind flag shape at the CLI boundary (AC4, AC2) ---

// Test_StateCmd_SetStatus_KindFlag_SpaceAndEqualsForms — both spellings are
// accepted, and the flag comes BEFORE the positionals.
func Test_StateCmd_SetStatus_KindFlag_SpaceAndEqualsForms(t *testing.T) {
	for _, form := range [][]string{
		{"--kind", "design"},
		{"--kind=design"},
	} {
		repo := makeRepo(t)
		dir := mkSpecDir(t, repo, "0001-d", "---\nstatus: draft\n---\n# D\n")
		art := filepath.Join(dir, "spec.md")
		args := append(append([]string{"set-status"}, form...), art, "decided")
		code, _, se := runCmd(t, repo, args...)
		if code != 0 {
			t.Fatalf("form %v: exit=%d stderr=%s", form, code, se)
		}
		b, _ := os.ReadFile(art)
		if !strings.Contains(string(b), "status: decided") {
			t.Errorf("form %v: status not written: %s", form, b)
		}
	}
}

// Test_StateCmd_SetStatus_KindFlag_AfterPositionals_IsUsageError — a flag after
// the positionals is a usage error, NEVER a silent ignore. A silent ignore would
// write the spec enum against a design and re-create this spec's own bug class.
func Test_StateCmd_SetStatus_KindFlag_AfterPositionals_IsUsageError(t *testing.T) {
	repo := makeRepo(t)
	dir := mkSpecDir(t, repo, "0001-d", "---\nstatus: draft\n---\n# D\n")
	art := filepath.Join(dir, "spec.md")
	before, _ := os.ReadFile(art)
	// "draft" is VALID for the spec enum, so the only thing that can make this
	// fail is the trailing flag itself. Using an invalid status here would let
	// the test pass against the pre-0049 positional parser for the wrong reason.
	code, _, se := runCmd(t, repo, "set-status", art, "draft", "--kind", "design")
	if code == 0 {
		t.Error("a --kind flag after the positionals must be a usage error")
	}
	if !strings.Contains(strings.ToLower(se), "kind") {
		t.Errorf("stderr must name the misplaced flag; got %q", se)
	}
	if after, _ := os.ReadFile(art); string(before) != string(after) {
		t.Error("a usage error must not mutate the artifact")
	}
}

// Test_StateCmd_SetStatus_NoKindFlag_DefaultsToSpecEnum — no flag means exactly
// today's behavior; the two new values do not leak into the spec enum.
func Test_StateCmd_SetStatus_NoKindFlag_DefaultsToSpecEnum(t *testing.T) {
	repo := makeRepo(t)
	dir := mkSpecDir(t, repo, "0001-x", "---\nstatus: draft\n---\n# S\n")
	spec := filepath.Join(dir, "spec.md")
	if code, _, se := runCmd(t, repo, "set-status", spec, "reviewed"); code != 0 {
		t.Fatalf("no-flag spec status: exit=%d stderr=%s", code, se)
	}
	for _, bad := range []string{"decided", "prioritized"} {
		if code, _, _ := runCmd(t, repo, "set-status", spec, bad); code == 0 {
			t.Errorf("no-flag %q must be rejected (spec enum)", bad)
		}
	}
}

// Test_StateCmd_SetStatus_KindValidatesEnumOnly_NotPathShape — AC4 requires this
// be recorded as DELIBERATE: --kind validates the status enum only, and does not
// verify the target path is really an artifact of that kind. Path-sniffing would
// be a second, weaker authority over artifact identity; the caller knows the kind.
func Test_StateCmd_SetStatus_KindValidatesEnumOnly_NotPathShape(t *testing.T) {
	repo := makeRepo(t)
	dir := mkSpecDir(t, repo, "0001-b", "---\nstatus: draft\n---\n# B\n")
	brief := filepath.Join(dir, "brief.md")
	if err := os.WriteFile(brief, []byte("---\nstatus: draft\n---\n# B\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	// --kind design against a brief.md SUCCEEDS by design.
	if code, _, se := runCmd(t, repo, "set-status", "--kind", "design", brief, "decided"); code != 0 {
		t.Fatalf("enum-only validation: exit=%d stderr=%s", code, se)
	}
}

func Test_StateCmd_SetStatus_UnknownKind_IsUsageError(t *testing.T) {
	repo := makeRepo(t)
	dir := mkSpecDir(t, repo, "0001-x", "---\nstatus: draft\n---\n# S\n")
	spec := filepath.Join(dir, "spec.md")
	before, _ := os.ReadFile(spec)
	code, _, se := runCmd(t, repo, "set-status", "--kind", "bogus", spec, "draft")
	if code == 0 {
		t.Error("an unknown --kind must exit non-zero")
	}
	// The pre-0049 positional parser also exits non-zero here, but because it
	// read "--kind" as the path and "bogus" as the status. Pin the REASON so
	// this is a true RED rather than a coincidental pass.
	if !strings.Contains(se, "unknown artifact kind") {
		t.Errorf("stderr must report the unknown kind, not a status error; got %q", se)
	}
	if after, _ := os.ReadFile(spec); string(before) != string(after) {
		t.Error("an unknown --kind must not mutate the artifact")
	}
}

// Test_StateCmd_SetStatus_KindFlagEmptyValue_ReportsUnknownKind — `--kind=`
// with an empty value must not fall through to the spec default. The empty
// ArtifactKind is an error by construction (AC4) and the flag layer must not
// paper over it.
//
// The assertion pins the REASON, not just the exit code: the pre-0049
// positional parser also exits non-zero here, but only because it read
// "--kind=" as the path and the path as the status. Without the reason check
// this test would pass against the unfixed code.
func Test_StateCmd_SetStatus_KindFlagEmptyValue_ReportsUnknownKind(t *testing.T) {
	repo := makeRepo(t)
	dir := mkSpecDir(t, repo, "0001-x", "---\nstatus: draft\n---\n# S\n")
	spec := filepath.Join(dir, "spec.md")
	before, _ := os.ReadFile(spec)
	code, _, se := runCmd(t, repo, "set-status", "--kind=", spec, "draft")
	if code == 0 {
		t.Error("--kind= with an empty value must exit non-zero, not default to spec")
	}
	if !strings.Contains(se, "unknown artifact kind") {
		t.Errorf("stderr must report the empty kind, not a status error; got %q", se)
	}
	if after, _ := os.ReadFile(spec); string(before) != string(after) {
		t.Error("an empty --kind must not mutate the artifact")
	}
}

// Test_StateCmd_SetStatus_EveryNonZeroPath_WritesStderr — AC2 at the binary
// layer. A silent `return 1` is a defect under this spec: the original bug was
// the caller being unable to tell what happened.
func Test_StateCmd_SetStatus_EveryNonZeroPath_WritesStderr(t *testing.T) {
	repo := makeRepo(t)
	okDir := mkSpecDir(t, repo, "0001-x", "---\nstatus: draft\n---\n# S\n")
	okSpec := filepath.Join(okDir, "spec.md")
	closedDir := mkSpecDir(t, repo, "0002-c", "---\nstatus: closed\n---\n# S\n")
	closedSpec := filepath.Join(closedDir, "spec.md")

	for _, tc := range []struct {
		name string
		args []string
	}{
		{"invalid status", []string{"set-status", okSpec, "bogus"}},
		{"closed artifact", []string{"set-status", closedSpec, "draft"}},
		{"unknown kind", []string{"set-status", "--kind", "nope", okSpec, "draft"}},
		{"missing file", []string{"set-status", filepath.Join(repo, "nope.md"), "draft"}},
		{"too few args", []string{"set-status", okSpec}},
		{"flag after positionals", []string{"set-status", okSpec, "draft", "--kind", "spec"}},
		{"kind/status mismatch", []string{"set-status", "--kind", "design", okSpec, "reviewed"}},
	} {
		code, _, se := runCmd(t, repo, tc.args...)
		if code == 0 {
			t.Errorf("%s: expected non-zero exit", tc.name)
		}
		if strings.TrimSpace(se) == "" {
			t.Errorf("%s: non-zero exit with EMPTY stderr is a defect under AC2", tc.name)
		}
	}
}
