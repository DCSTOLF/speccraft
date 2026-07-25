package main

// Spec 0032 AC8/AC9 — dispatch round-trip + preserved unknown-tool fallback.
//
// AC8 pins that dispatchByLanguage injects ToolName for MultiEdit/NotebookEdit so
// applyEdit routes to the modeled case (not the default fallthrough). AC9's
// unknown-tool pin re-establishes the default fallback for the NEXT still-modeled-
// elsewhere tool. The recurrence-grep (added alongside) is the decisive RED that
// forces the stale reserved-slot language out of the package.

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/dcstolf/speccraft/tools/internal/speccraft"
)

// dispatchCapturesTestID drives a write-tool envelope through the full
// processToolUse path (which is where dispatchByLanguage injects ToolName) and
// returns the captured red-candidates for the touched file.
func dispatchCapturesTestID(t *testing.T, toolName string, toolInput map[string]any) ([]string, string) {
	t.Helper()
	root := makeTestRepo(t, "0032-payloads", "in-progress")
	testFile := filepath.Join(root, "pkg", "foo_test.go")
	if err := os.MkdirAll(filepath.Dir(testFile), 0o755); err != nil {
		t.Fatal(err)
	}
	os.WriteFile(testFile, []byte("package pkg\n"), 0o644)
	toolInput["file_path"] = testFile
	env := map[string]any{"tool_name": toolName, "tool_input": toolInput, "cwd": root}
	raw, _ := json.Marshal(env)
	var in HookInput
	if err := json.Unmarshal(raw, &in); err != nil {
		t.Fatal(err)
	}
	if err := processToolUse(in, deps{}); err != nil {
		t.Fatalf("%s to a test file should be allowed, got: %v", toolName, err)
	}
	abs, _ := filepath.Abs(testFile)
	rc, _ := speccraft.GetRedCandidates(root)
	return rc[abs], abs
}

// AC8 — the MultiEdit envelope only captures a candidate if dispatchByLanguage
// injected ToolName (else applyEdit hits default and derives no post-edit content).
func Test_DispatchByLanguage_InjectsToolName_MultiEdit(t *testing.T) {
	got, _ := dispatchCapturesTestID(t, "MultiEdit", map[string]any{
		"edits": []map[string]string{
			{"old_string": "package pkg", "new_string": "package pkg\n\nfunc TestDispatched(t *testing.T) {}"},
		},
	})
	if !containsStr(got, "TestDispatched") {
		t.Errorf("MultiEdit dispatch must inject ToolName so applyEdit routes to its case; got %v", got)
	}
}

// AC8 — same for NotebookEdit's new_source.
func Test_DispatchByLanguage_InjectsToolName_NotebookEdit(t *testing.T) {
	got, _ := dispatchCapturesTestID(t, "NotebookEdit", map[string]any{
		"new_source": "package pkg\n\nfunc TestDispatched(t *testing.T) {}",
	})
	if !containsStr(got, "TestDispatched") {
		t.Errorf("NotebookEdit dispatch must inject ToolName so applyEdit routes to its case; got %v", got)
	}
}

// AC9 — a genuinely unknown tool still falls through to the pre-edit content, so
// the reserved slot remains open for whatever write-tool comes next.
func Test_FutureEditEnvelope_ReturnsPreContentUnchanged(t *testing.T) {
	got := applyEdit("PRE", ToolInput{ToolName: "FutureEdit", NewString: "X", Content: "Y", NewSource: "Z"})
	if got != "PRE" {
		t.Errorf("unknown tool must fall through to pre-content unchanged, got %q", got)
	}
}

// AC9 — the applyEdit default-branch comment must no longer NAME MultiEdit or
// NotebookEdit: they are explicit modeled cases now, not the fallthrough. This
// targets the default branch specifically (complementing the whole-package grep).
func Test_ApplyEditDefaultComment_OmitsModeledTools(t *testing.T) {
	b, err := os.ReadFile("main.go")
	if err != nil {
		t.Fatal(err)
	}
	src := strings.ToLower(string(b))
	fn := strings.Index(src, "func applyedit(")
	if fn < 0 {
		t.Fatal("applyEdit function not found in main.go")
	}
	body := src[fn:]
	def := strings.Index(body, "default:")
	if def < 0 {
		t.Fatal("no default branch found in main.go applyEdit switch")
	}
	seg := body[def:]
	if end := strings.Index(seg, "return precontent"); end > 0 {
		seg = seg[:end]
	}
	for _, tool := range []string{"multiedit", "notebookedit"} {
		if strings.Contains(seg, tool) {
			t.Errorf("applyEdit default branch still names %q; it is a modeled case now (spec 0032)", tool)
		}
	}
}

// AC9 recurrence guard — the reserved-slot slot is CLOSED: no source or comment in
// the guard package may still describe MultiEdit/NotebookEdit payloads as reserved
// or unmodeled. Needles are built from concatenated fragments (and this file is
// self-excluded) so the guard's own source carries no literal phrase; the match is
// case-insensitive and whitespace-tolerant (Fields collapses internal whitespace
// runs) so a cosmetic variant cannot bypass it.
func Test_NoReservedSlotLanguage_ForWriteTools(t *testing.T) {
	needles := []string{
		"reserved " + "spec 0032",
		"reserved for " + "spec 0032",
		"un" + "modeled",
	}
	norm := func(s string) string {
		return strings.Join(strings.Fields(strings.ToLower(s)), " ")
	}
	const self = "reserved_slot_test.go"
	entries, err := os.ReadDir(".")
	if err != nil {
		t.Fatal(err)
	}
	for _, e := range entries {
		if e.IsDir() || !strings.HasSuffix(e.Name(), ".go") || e.Name() == self {
			continue
		}
		b, err := os.ReadFile(e.Name())
		if err != nil {
			t.Fatal(err)
		}
		hay := norm(string(b))
		for _, n := range needles {
			if strings.Contains(hay, n) {
				t.Errorf("%s still contains reserved-slot language %q — the spec-0032 slot is "+
					"closed (MultiEdit/NotebookEdit are modeled); scrub it (AC9)", e.Name(), n)
			}
		}
	}
}
