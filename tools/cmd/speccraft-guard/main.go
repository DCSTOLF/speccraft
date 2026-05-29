package main

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"

	"github.com/dcstolf/speccraft/tools/internal/speccraft"
	"github.com/dcstolf/speccraft/tools/internal/speccraft/runner"
)

const version = "1.0.0"

// HookInput is the JSON payload Claude Code sends for PreToolUse hooks.
type HookInput struct {
	ToolName  string    `json:"tool_name"`
	ToolInput ToolInput `json:"tool_input"`
	SessionID string    `json:"session_id"`
	CWD       string    `json:"cwd"`
}

type ToolInput struct {
	FilePath  string `json:"file_path"`
	OldString string `json:"old_string"`
	NewString string `json:"new_string"`
}

// deps is the injection seam for tests. Production callers pass an empty
// deps; tests pass fakes for `exec` (cargo invocation) and `runnerFor`
// (red-check runner) to avoid touching the real toolchain.
type deps struct {
	exec      runner.ExecFunc
	runnerFor func(cfg speccraft.SpeccraftConfig) runner.Runner
	stderr    io.Writer // optional: captures Rust dispatch log messages
}

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, "usage: speccraft-guard pre-tool-use")
		os.Exit(1)
	}

	switch os.Args[1] {
	case "--version", "-v":
		fmt.Println(version)
		return

	case "pre-tool-use":
		if err := preToolUse(); err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(2)
		}

	default:
		fmt.Fprintf(os.Stderr, "unknown subcommand: %s\n", os.Args[1])
		os.Exit(1)
	}
}

func preToolUse() error {
	var input HookInput
	if err := json.NewDecoder(os.Stdin).Decode(&input); err != nil {
		// If we can't parse stdin, allow rather than block.
		return nil
	}
	return processToolUse(input, productionDeps())
}

// productionDeps wires the production exec and runner factory so the
// hook's Rust dispatch hits the real cargo toolchain via the runner
// package's execCmd. Test entrypoints construct deps{} directly with
// fakes.
func productionDeps() deps {
	return deps{
		exec: func(ctx context.Context, name string, args []string, workDir string) ([]byte, []byte, int, error) {
			return runner.ExecCmd(ctx, name, args, workDir)
		},
		runnerFor: runner.AdapterFor,
		stderr:    os.Stderr,
	}
}

// processToolUse is the testable entrypoint: same logic as preToolUse
// but without stdin parsing or os.Exit, so unit tests can drive it
// directly with controlled HookInput and dependency injection.
func processToolUse(input HookInput, d deps) error {
	filePath := input.ToolInput.FilePath
	if filePath == "" {
		return nil
	}

	absPath, err := filepath.Abs(filePath)
	if err != nil {
		return nil
	}

	cwd := input.CWD
	if cwd == "" {
		cwd, _ = os.Getwd()
	}
	root, err := speccraft.FindRoot(cwd)
	if err != nil {
		return nil
	}
	cfg := speccraft.ReadConfig(root)

	rel, err := filepath.Rel(root, absPath)
	if err != nil || (len(rel) >= 2 && rel[:2] == "..") {
		return nil
	}

	if speccraft.IsAlwaysAllowed(root, absPath) {
		return nil
	}

	return dispatchByLanguage(input, absPath, root, cfg, d)
}

// dispatchByLanguage routes the touched file to the appropriate per-
// language guard handler. Adding a new language adds a case here plus
// a new handler — the rest of processToolUse stays untouched.
//
// Order matters only insofar as `.rs` files are not also caught by
// IsTestFile or IsProductionGoFile/Python; the IsRustFile check is
// first to make this explicit.
func dispatchByLanguage(input HookInput, absPath, root string, cfg speccraft.SpeccraftConfig, d deps) error {
	switch {
	case speccraft.IsRustFile(absPath):
		return rustDispatch(input, absPath, root, cfg, d)
	case speccraft.IsTestFile(absPath):
		// Go/Python test files — always allowed.
		return nil
	case speccraft.IsProductionGoFile(absPath), speccraft.IsProductionPythonFile(absPath):
		return goPythonProdGuard(absPath, root, cfg)
	default:
		// Unknown file type — allow.
		return nil
	}
}

// rustDispatch implements the spec-0005 Rust guard flow. Order:
//
//  1. Workspace detection — hard error citing reserved spec 0006 (AC #5).
//  2. Initial-capture if rust_test_baseline is empty (AC #12 (a)).
//  3. Red-check: walk crate (with the proposed edit applied in memory),
//     compute just-added vs baseline, invoke runner per just-added FQTN,
//     classify outcome per AC #4. On accept, append failing-just-added
//     IDs to baseline via PostAcceptUpdateRustBaseline (AC #12 (c)).
//
//  Pre-edit gate integration (T54) lives in front of the red-check.
func rustDispatch(input HookInput, absPath, root string, cfg speccraft.SpeccraftConfig, d deps) error {
	isWorkspace, err := speccraft.IsCargoWorkspace(root)
	if err != nil {
		return nil
	}
	if isWorkspace {
		return fmt.Errorf(
			"Cargo workspace detected at %s/Cargo.toml.\n"+
				"speccraft does not support Cargo workspaces in this release;\n"+
				"single-crate projects only.\n\n"+
				"Workspace support is tracked under reserved spec 0006 (Cargo workspace support).\n"+
				"See specs/ when the follow-up lands.",
			root,
		)
	}

	// Pre-edit gate: compile-check via `cargo check --tests`, gated by the
	// crate fingerprint. Cache hit → zero subprocesses; cache miss →
	// invokes cargo; build failure → reject the edit.
	if d.exec != nil {
		if err := runner.RunPreEditGate(root, d.exec); err != nil {
			return fmt.Errorf("pre-edit gate: %w", err)
		}
	}

	// Initial-capture short-circuit. On the first edit against a Rust
	// crate where the baseline is empty, walk and record; do not invoke
	// the runner.
	captured, count, err := speccraft.CaptureInitialRustBaseline(root)
	if err != nil {
		return nil
	}
	if captured {
		stderr := d.stderr
		if stderr == nil {
			stderr = os.Stderr
		}
		fmt.Fprintf(stderr, "rust_test_baseline captured: %d tests\n", count)
		return nil
	}

	// Red-check: compute post-edit crate state and just-added set.
	justAdded, err := computeJustAddedForEdit(absPath, input.ToolInput, root)
	if err != nil {
		return nil
	}
	if len(justAdded) == 0 {
		// Nothing new being added — allow as a green/refactor edit.
		return nil
	}

	// Run the runner for each just-added FQTN; accept on the first failed
	// record. AC #4 says any failed record whose name is in just-added
	// satisfies the accept branch.
	runnerFor := d.runnerFor
	if runnerFor == nil {
		runnerFor = runner.AdapterFor
	}
	adapter := runnerFor(cfg)

	var failedNames []string
	var accepted bool
	for _, fqtn := range justAdded {
		res, err := adapter.Run(context.Background(), runner.Request{
			WorkDir:                root,
			FullyQualifiedTestName: fqtn,
		})
		if err != nil {
			return fmt.Errorf("red-check runner: %w", err)
		}
		for _, rec := range res.Records {
			if rec.Status == "failed" {
				failedNames = append(failedNames, rec.TestName)
			}
		}
		if res.Outcome == runner.OutcomeAtLeastOneFailed {
			accepted = true
		}
		if res.Outcome == runner.OutcomeBuildFailed {
			return fmt.Errorf("red-check: build failed: %s", res.Stderr)
		}
	}

	if !accepted {
		return fmt.Errorf(
			"red-check: no failing test observed for just-added tests: %v\n"+
				"Add a failing test that exercises the change you're about to make.",
			justAdded,
		)
	}

	// Persist the failing-just-added IDs to the baseline (AC #12 (c)).
	if err := speccraft.PostAcceptUpdateRustBaseline(root, justAdded, failedNames); err != nil {
		return nil
	}
	return nil
}

// computeJustAddedForEdit returns the canonical test IDs that the
// proposed edit would introduce, relative to the current
// rust_test_baseline. It models the post-edit crate state by:
//
//  1. Reading the current file from disk → pre-edit content
//  2. Applying the OldString → NewString swap (or NewString as full
//     content for a Write) to get post-edit content
//  3. Computing pre-edit canonical IDs for the touched file
//  4. Computing post-edit canonical IDs for the touched file
//  5. Walking the rest of the crate via DiscoverRustTests
//  6. Forming postSet = (crateWalk \ thisFilePre) ∪ thisFilePost
//  7. just-added = postSet − baseline
func computeJustAddedForEdit(absPath string, ti ToolInput, root string) ([]string, error) {
	stem := strings.TrimSuffix(filepath.Base(absPath), ".rs")

	preBytes, _ := os.ReadFile(absPath)
	preContent := string(preBytes)
	postContent := applyEdit(preContent, ti)

	relForClassifier, err := filepath.Rel(root, absPath)
	if err != nil {
		relForClassifier = absPath
	}
	relForClassifier = filepath.ToSlash(relForClassifier)

	preIDs := speccraft.CanonicalIDsForFile(relForClassifier, stem, preContent)
	postIDs := speccraft.CanonicalIDsForFile(relForClassifier, stem, postContent)

	crateIDs, err := speccraft.DiscoverRustTests(root)
	if err != nil {
		return nil, err
	}

	// crateWalk \ thisFilePre, then ∪ thisFilePost.
	preFileSet := stringSet(preIDs)
	postSet := map[string]struct{}{}
	for _, id := range crateIDs {
		if _, ok := preFileSet[id]; !ok {
			postSet[id] = struct{}{}
		}
	}
	for _, id := range postIDs {
		postSet[id] = struct{}{}
	}

	baseline, err := speccraft.GetRustBaseline(root)
	if err != nil {
		return nil, err
	}
	baselineSet := stringSet(baseline)

	var justAdded []string
	for id := range postSet {
		if _, ok := baselineSet[id]; !ok {
			justAdded = append(justAdded, id)
		}
	}
	return justAdded, nil
}

// applyEdit models Edit/Write tool semantics in memory. If OldString is
// empty (Write tool), NewString IS the full post-edit content. If
// OldString is non-empty (Edit tool), it's a single search-and-replace.
func applyEdit(preContent string, ti ToolInput) string {
	if ti.OldString == "" {
		return ti.NewString
	}
	return strings.Replace(preContent, ti.OldString, ti.NewString, 1)
}

func stringSet(s []string) map[string]struct{} {
	out := make(map[string]struct{}, len(s))
	for _, v := range s {
		out[v] = struct{}{}
	}
	return out
}

// goPythonProdGuard preserves the original Go/Python production-file flow.
func goPythonProdGuard(absPath, root string, cfg speccraft.SpeccraftConfig) error {
	state, err := speccraft.LoadState(root)
	if err != nil {
		return nil
	}

	if state.ActiveSpec == "" || state.ActiveSpec == "null" {
		return fmt.Errorf(
			"No active spec. Edits to production code are blocked.\n"+
				"Use /spec:new \"<title>\" to start a spec, or set status: in-progress\n"+
				"on an existing spec.\n\n"+
				"File: %s", absPath)
	}

	specFile := filepath.Join(root, "specs", state.ActiveSpec, "spec.md")
	if status := readFrontmatterField(specFile, "status"); status != "in-progress" && status != "" {
		return fmt.Errorf(
			"Active spec %q is in status %q. Move to in-progress before\n"+
				"editing production code.", state.ActiveSpec, status)
	}

	siblings, _ := speccraft.SiblingTestFiles(absPath, root, cfg.TDD.TestRoots)
	dir := filepath.Dir(absPath)
	editedTests := state.Session.EditedTestFiles

	if !hasSiblingTestEdited(siblings, editedTests) {
		siblingList := "(none found)"
		if len(siblings) > 0 {
			siblingList = ""
			for _, s := range siblings {
				siblingList += "\n    - " + s
			}
		}
		return fmt.Errorf(
			"TDD invariant: edit a sibling test in %s/ this session before editing\n"+
				"the production file.\n\n"+
				"If no test exists yet, create one (RED) first.\n"+
				"Sibling test files found:%s\n\n"+
				"Use /spec:override \"<reason>\" for a one-time bypass.",
			dir, siblingList)
	}
	return nil
}

// hasSiblingTestEdited checks if any sibling test was in the session's edited list.
func hasSiblingTestEdited(siblings, editedTests []string) bool {
	for _, sibling := range siblings {
		abs, _ := filepath.Abs(sibling)
		for _, edited := range editedTests {
			if abs == edited {
				return true
			}
		}
	}
	return false
}

// readFrontmatterField reads a YAML frontmatter field from a markdown file.
func readFrontmatterField(path, field string) string {
	data, err := os.ReadFile(path)
	if err != nil {
		return ""
	}
	lines := splitLines(string(data))
	inFrontmatter := false
	for _, line := range lines {
		if line == "---" {
			if !inFrontmatter {
				inFrontmatter = true
				continue
			}
			break
		}
		if !inFrontmatter {
			continue
		}
		prefix := field + ": "
		if strings.HasPrefix(line, prefix) {
			return line[len(prefix):]
		}
	}
	return ""
}

func splitLines(s string) []string {
	var lines []string
	start := 0
	for i, c := range s {
		if c == '\n' {
			lines = append(lines, s[start:i])
			start = i + 1
		}
	}
	if start < len(s) {
		lines = append(lines, s[start:])
	}
	return lines
}
