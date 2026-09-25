package main

// Spec 0048 T20 (AC10) — the gated write-tool set has one source of truth.
//
// The tool list is currently written out FOUR times: `applyEdit`'s switch, the
// PreToolUse and PostToolUse matchers in hooks/hooks.json, and GATED_TOOLS in
// hooks/pre-tool-use.sh. Nothing connects them, so adding a fifth write tool means
// remembering four places — and the failure is silent: the hook simply never fires
// for the new tool, and every guard rule quietly stops applying to it.
//
// `var gatedWriteTools` becomes the single source, and this file is what makes it
// one: the enumeration is extracted from main.go and every consumer is checked
// against it. The second test is driven OFF that list rather than off a
// hand-written four-case table, so a tool added to the list without post-edit
// modelling fails here instead of being discovered in the field.

import (
	"context"
	"encoding/json"
	"os"
	"regexp"
	"strings"
	"testing"

	"github.com/dcstolf/speccraft/tools/internal/speccraft"
)

// extractGatedWriteTools reads the literal names out of `var gatedWriteTools` in
// main.go. Deliberately source-extracted rather than imported: the point is to
// prove the SOURCE list and the three external consumers agree, so reading the Go
// value would only prove the value agrees with itself.
func extractGatedWriteTools(t *testing.T) []string {
	t.Helper()
	b, err := os.ReadFile("main.go")
	if err != nil {
		t.Fatal(err)
	}
	re := regexp.MustCompile(`(?s)var gatedWriteTools\s*=\s*\[\]string\{(.*?)\}`)
	m := re.FindSubmatch(b)
	if m == nil {
		t.Fatal("`var gatedWriteTools = []string{…}` not found in main.go")
	}
	var out []string
	for _, part := range regexp.MustCompile(`"([^"]+)"`).FindAllStringSubmatch(string(m[1]), -1) {
		out = append(out, part[1])
	}
	if len(out) == 0 {
		t.Fatal("gatedWriteTools is empty")
	}
	return out
}

// applyEditBody returns applyEdit's body, anchored per the spec-0032 rule. A
// whole-file search would find `case "Write"` in some other switch and pass while
// applyEdit itself had no case for it.
func applyEditBody(t *testing.T, src string) string {
	t.Helper()
	i := strings.Index(src, "func applyEdit(")
	if i < 0 {
		t.Fatal("anchor `func applyEdit(` not found — the scan would pass vacuously")
	}
	rest := src[i:]
	if j := strings.Index(rest[1:], "\nfunc "); j >= 0 {
		return rest[:j+1]
	}
	return rest
}

func Test_GatedWriteTools_EnumerationIsTheSingleSource(t *testing.T) {
	tools := extractGatedWriteTools(t)

	mainSrc, err := os.ReadFile("main.go")
	if err != nil {
		t.Fatal(err)
	}
	body := applyEditBody(t, string(mainSrc))

	// (a) every gated tool is modelled by applyEdit.
	for _, tool := range tools {
		if !strings.Contains(body, `case "`+tool+`"`) {
			t.Errorf("applyEdit has no `case %q` — a gated tool with no post-edit modelling "+
				"means the probe would see pre-edit content", tool)
		}
	}

	// (b) both hooks.json matchers equal the pipe-joined list. PostToolUse matters
	// as much as PreToolUse: a tool gated on the way in but not tracked on the way
	// out would leave the session's edited-file bookkeeping incomplete.
	rawHooks, err := os.ReadFile("../../../hooks/hooks.json")
	if err != nil {
		t.Fatal(err)
	}
	var hooksFile map[string]any
	if err := json.Unmarshal(rawHooks, &hooksFile); err != nil {
		t.Fatalf("hooks.json is not valid JSON: %v", err)
	}
	// The event arrays are nested under a top-level "hooks" key.
	hooks, ok := hooksFile["hooks"].(map[string]any)
	if !ok {
		t.Fatal(`hooks.json has no top-level "hooks" object`)
	}
	wantMatcher := strings.Join(tools, "|")
	found := 0
	for _, event := range []string{"PreToolUse", "PostToolUse"} {
		entries, ok := hooks[event].([]any)
		if !ok {
			t.Errorf("hooks.json has no %s array", event)
			continue
		}
		for _, e := range entries {
			m, ok := e.(map[string]any)
			if !ok {
				continue
			}
			matcher, ok := m["matcher"].(string)
			if !ok {
				continue
			}
			// Only the write-tool matcher is in scope; other matchers (e.g. "*")
			// legitimately differ.
			if !strings.Contains(matcher, "Write") {
				continue
			}
			found++
			if matcher != wantMatcher {
				t.Errorf("%s matcher = %q, want %q (gatedWriteTools is the source)", event, matcher, wantMatcher)
			}
		}
	}
	if found < 2 {
		t.Errorf("expected a write-tool matcher in both PreToolUse and PostToolUse, found %d", found)
	}

	// (c) the shell hook's GATED_TOOLS equals the space-joined list.
	rawSh, err := os.ReadFile("../../../hooks/pre-tool-use.sh")
	if err != nil {
		t.Fatal(err)
	}
	shRe := regexp.MustCompile(`GATED_TOOLS="([^"]*)"`)
	sm := shRe.FindSubmatch(rawSh)
	if sm == nil {
		t.Fatal(`GATED_TOOLS="…" not found in hooks/pre-tool-use.sh`)
	}
	if got, want := string(sm[1]), strings.Join(tools, " "); got != want {
		t.Errorf("GATED_TOOLS = %q, want %q (gatedWriteTools is the source)", got, want)
	}
}

// Driven off gatedWriteTools itself. Adding a tool to the list without teaching
// the envelope decoder and applyEdit how to derive its post-edit content fails
// HERE, rather than in the field where the symptom is "the probe judged the wrong
// content".
func Test_BuildProbe_EveryGatedWriteTool_ReachesProberWithDerivedContent(t *testing.T) {
	tools := extractGatedWriteTools(t)
	const pre = "package pkg\n\nfunc Foo() int { return 1 }\n"
	const want = "package pkg\n\nfunc Foo() int { return 2 }\n"

	for _, tool := range tools {
		t.Run(tool, func(t *testing.T) {
			root, prodFile, _ := goModuleFixture(t, true)
			if err := os.WriteFile(prodFile, []byte(pre), 0o644); err != nil {
				t.Fatal(err)
			}

			// Build the envelope the way the harness really delivers each tool.
			env := map[string]any{"tool_name": tool, "cwd": root}
			ti := map[string]any{"file_path": prodFile}
			switch tool {
			case "Write":
				ti["content"] = want
			case "Edit":
				ti["old_string"] = "return 1"
				ti["new_string"] = "return 2"
			case "MultiEdit":
				ti["edits"] = []any{map[string]any{"old_string": "return 1", "new_string": "return 2"}}
			case "NotebookEdit":
				ti["new_source"] = want
			default:
				t.Fatalf("tool %q is in gatedWriteTools but this test does not know how to "+
					"build its envelope — teach it here, do not skip", tool)
			}
			env["tool_input"] = ti
			raw, err := json.Marshal(env)
			if err != nil {
				t.Fatal(err)
			}
			var in HookInput
			if err := json.Unmarshal(raw, &in); err != nil {
				t.Fatal(err)
			}

			// A prober that records exactly what content it was asked to judge.
			rec := &recordingProber{}
			d := deps{
				runnerForLang: fixedRunnerForLang(buildFailedRunner("undefined: missingHelper"), true),
				proberForLang: func(string, speccraft.SpeccraftConfig) (BuildProber, bool) { return rec, true },
			}
			if err := processToolUse(in, d); err != nil {
				t.Fatalf("%s: %v", tool, err)
			}
			if rec.calls != 1 {
				t.Fatalf("%s: prober called %d times, want 1", tool, rec.calls)
			}
			if rec.lastContent != want {
				t.Errorf("%s: prober judged the wrong content:\n got %q\nwant %q", tool, rec.lastContent, want)
			}
		})
	}
}

// recordingProber captures the post-edit content it was handed.
type recordingProber struct {
	calls       int
	lastContent string
}

func (r *recordingProber) Probe(_ context.Context, req buildProbeRequest) (buildProbeResult, error) {
	r.calls++
	r.lastContent = req.PostContent
	return buildProbeResult{Clean: true}, nil
}
