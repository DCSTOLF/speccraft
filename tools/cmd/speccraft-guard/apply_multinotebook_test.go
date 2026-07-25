package main

// Spec 0032 — applyEdit must model MultiEdit (sequential edits[] over the running
// content) and NotebookEdit (new_source as the whole post-edit body).
//
// Envelope-boundary authoring (spec 0031 lineage / spec 0018 AC13 dodge): these
// REDs decode a real tool_input JSON blob into a ToolInput and set ToolName, then
// call applyEdit. No test names ti.Edits or ti.NewSource, so every test COMPILES
// against the current struct (the unknown `edits`/`new_source` keys are dropped
// until the fields exist) and fails only on the behavior assertion — a runtime
// RED, never a build failure that would need an override.

import (
	"encoding/json"
	"testing"
)

// decodeToolInput builds a ToolInput from a raw tool_input JSON object and stamps
// ToolName (which is json:"-", injected at dispatch in production). Unknown keys
// are silently dropped, so this is stable against a struct that does not yet carry
// the field under test.
func decodeToolInput(t *testing.T, toolName, toolInputJSON string) ToolInput {
	t.Helper()
	var ti ToolInput
	if err := json.Unmarshal([]byte(toolInputJSON), &ti); err != nil {
		t.Fatal(err)
	}
	ti.ToolName = toolName
	return ti
}

// AC1 — MultiEdit applies each edits[] entry in ARRAY ORDER, first-occurrence,
// with an exact-string oracle (not a weak inequality). "a c a" → replace first
// "a" with "b" → "b c a"; then replace "c" with "d" → "b d a".
func Test_ApplyEdit_MultiEdit_SequentialDistinct(t *testing.T) {
	ti := decodeToolInput(t, "MultiEdit",
		`{"edits":[{"old_string":"a","new_string":"b"},{"old_string":"c","new_string":"d"}]}`)
	if got := applyEdit("a c a", ti); got != "b d a" {
		t.Errorf("applyEdit(MultiEdit) = %q, want %q", got, "b d a")
	}
}

// AC2 — each entry applies to the RUNNING content, so a later entry sees an
// earlier entry's output: {a→b},{b→c} over "a" yields "c" (independent
// application would yield "b"). This is what makes MultiEdit ≠ N single Edits.
func Test_ApplyEdit_MultiEdit_RunningContentDependency(t *testing.T) {
	ti := decodeToolInput(t, "MultiEdit",
		`{"edits":[{"old_string":"a","new_string":"b"},{"old_string":"b","new_string":"c"}]}`)
	if got := applyEdit("a", ti); got != "c" {
		t.Errorf("applyEdit(MultiEdit running-content) = %q, want %q", got, "c")
	}
}

// AC3a — an empty edits[] is a no-op: the pre-edit content is returned unchanged.
func Test_ApplyEdit_MultiEdit_EmptyEditsReturnsPre(t *testing.T) {
	ti := decodeToolInput(t, "MultiEdit", `{"edits":[]}`)
	if got := applyEdit("PRE", ti); got != "PRE" {
		t.Errorf("applyEdit(MultiEdit empty edits) = %q, want %q", got, "PRE")
	}
}

// AC3b — an entry whose old_string is ABSENT from the running content is a silent
// no-op (best-effort model; the real tool would hard-error, which is out of scope).
func Test_ApplyEdit_MultiEdit_AbsentOldStringNoOp(t *testing.T) {
	ti := decodeToolInput(t, "MultiEdit", `{"edits":[{"old_string":"zzz","new_string":"q"}]}`)
	if got := applyEdit("PRE", ti); got != "PRE" {
		t.Errorf("applyEdit(MultiEdit absent old_string) = %q, want %q", got, "PRE")
	}
}

// AC3c — an entry with an EMPTY old_string is SKIPPED, never prepended. Go's
// strings.Replace(s, "", new, 1) would prepend `new`; the guard must not.
func Test_ApplyEdit_MultiEdit_EmptyOldStringSkipped(t *testing.T) {
	ti := decodeToolInput(t, "MultiEdit", `{"edits":[{"old_string":"","new_string":"X"}]}`)
	if got := applyEdit("PRE", ti); got != "PRE" {
		t.Errorf("applyEdit(MultiEdit empty old_string) = %q, want %q (must NOT prepend)", got, "PRE")
	}
}

// AC4 — NotebookEdit returns new_source as the whole post-edit content.
func Test_ApplyEdit_NotebookEdit_NewSourceReplaces(t *testing.T) {
	ti := decodeToolInput(t, "NotebookEdit", `{"new_source":"X"}`)
	if got := applyEdit("PRE", ti); got != "X" {
		t.Errorf("applyEdit(NotebookEdit) = %q, want %q", got, "X")
	}
}

// AC4 — an emptied cell (new_source:"") returns "", NOT preContent and NOT the
// ignored Content/NewString fields. Because applyEdit switches on ToolName (not
// field presence), the empty-vs-absent zero-value ambiguity is moot.
func Test_ApplyEdit_NotebookEdit_EmptyNewSourceEmpty(t *testing.T) {
	ti := decodeToolInput(t, "NotebookEdit", `{"new_source":"","content":"IGNORED","new_string":"IGNORED"}`)
	if got := applyEdit("PRE", ti); got != "" {
		t.Errorf("applyEdit(NotebookEdit empty new_source) = %q, want %q", got, "")
	}
}
