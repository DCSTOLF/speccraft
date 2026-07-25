package main

// Spec 0032 AC7 — authoring a sibling RED test via a MultiEdit envelope unblocks
// the production edit WITHOUT an override, the same end-to-end path spec 0031
// established for Write. The driving envelope is decoded from real JSON bytes
// (envelope boundary) so this compiles against the current struct and fails only
// on behavior until the MultiEdit payload is modeled.

import (
	"encoding/json"
	"path/filepath"
	"testing"

	"github.com/dcstolf/speccraft/tools/internal/speccraft"
	"github.com/dcstolf/speccraft/tools/internal/speccraft/runner"
)

func Test_MultiEditSiblingRed_NoOverride_Allows_Go(t *testing.T) {
	root, prodFile := goRedCheckRepo(t, nil) // NOT pre-seeded — capture must come from the MultiEdit
	sib := filepath.Join(root, "pkg", "foo_test.go")

	// Call 1: author the sibling test via a real MultiEdit envelope. In a live run
	// TestNew's body asserts against an already-existing production symbol, so it is
	// a runtime RED (not a compile failure that would trip the spec-0018-AC13 trap);
	// for the guard only the just-added test id matters.
	env := map[string]any{
		"tool_name": "MultiEdit",
		"tool_input": map[string]any{
			"file_path": sib,
			"edits": []map[string]string{
				{"old_string": "package pkg", "new_string": "package pkg\n\nfunc TestNew(t *testing.T) {}"},
			},
		},
		"cwd": root,
	}
	raw, _ := json.Marshal(env)
	var in HookInput
	if err := json.Unmarshal(raw, &in); err != nil {
		t.Fatal(err)
	}
	if err := processToolUse(in, deps{}); err != nil {
		t.Fatalf("MultiEdit to a test file should be allowed, got: %v", err)
	}
	abs, _ := filepath.Abs(sib)
	rc, _ := speccraft.GetRedCandidates(root)
	if !containsStr(rc[abs], "TestNew") {
		t.Fatalf("MultiEdit envelope must capture the just-added TestNew, got %v", rc[abs])
	}

	// Call 2: Edit the production file; the runner reports TestNew failing → the
	// edit is ALLOWED with no override provisioned.
	rec := &recordingRunner{nextResult: runner.Result{
		Outcome: runner.OutcomeAtLeastOneFailed,
		Records: []runner.TestRecord{{TestName: "TestNew", Status: "failed"}},
	}}
	editIn := HookInput{
		ToolName:  "Edit",
		ToolInput: ToolInput{FilePath: prodFile, OldString: "package pkg\n", NewString: "package pkg\n\nfunc Foo() {}\n"},
		CWD:       root,
	}
	if err := processToolUse(editIn, depsWithRunner(rec)); err != nil {
		t.Fatalf("prod edit must be ALLOWED after a MultiEdit-authored RED (no override), got: %v", err)
	}
	if s, _ := speccraft.LoadState(root); s.Session.OverridePending {
		t.Error("override_pending must never have been provisioned on this path")
	}
}
