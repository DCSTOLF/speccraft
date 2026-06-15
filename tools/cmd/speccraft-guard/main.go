package main

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/dcstolf/speccraft/tools/internal/speccraft"
	"github.com/dcstolf/speccraft/tools/internal/speccraft/runner"
)

const version = "1.1.0"

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
	// runnerForLang resolves the red-check adapter for a non-Rust language
	// ("go"/"python"/"js"/"ts"). ok=false signals the runner is unresolved
	// (e.g. unconfigured JS/TS command) and the guard must fail closed
	// (spec 0018, Decision D2). Production wiring goes through productionDeps().
	runnerForLang func(lang string, cfg speccraft.SpeccraftConfig) (runner.Runner, bool)
	stderr        io.Writer // optional: captures Rust dispatch log messages
}

// redCheckTimeout bounds a single non-Rust red-check adapter invocation so a
// hanging `go test`/`pytest`/`node` process cannot wedge the PreToolUse hook
// indefinitely (spec 0018, AC9). A deadline overrun surfaces as a Go error from
// adapter.Run — not a new Outcome value — and the guard blocks on it.
const redCheckTimeout = 30 * time.Second

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
		runnerFor:     runner.AdapterFor,
		runnerForLang: runner.AdapterForLanguage,
		stderr:        os.Stderr,
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
		// Test files (Go, Python, JS/TS) — always allowed. Capture the set
		// of test ids this edit introduces so the production red-check can
		// require an observed failure within the session's just-added set
		// (spec 0018, Decision D1). Best-effort: a capture error never blocks
		// a test-file edit.
		captureRedCandidates(input.ToolInput, absPath, root)
		return nil
	case speccraft.IsProductionGoFile(absPath), speccraft.IsProductionPythonFile(absPath):
		return goPythonProdGuard(absPath, root, cfg, d)
	case speccraft.IsProductionJSTSFile(absPath):
		return jsTsDispatch(absPath, root, cfg, d)
	default:
		// Unknown file type — allow.
		return nil
	}
}

// rustDispatch implements the spec-0005 Rust guard flow. Order:
//
//  1. Workspace detection — hard error citing reserved spec 0006 (AC #5).
//
//  2. Initial-capture if rust_test_baseline is empty (AC #12 (a)).
//
//  3. Red-check: walk crate (with the proposed edit applied in memory),
//     compute just-added vs baseline, invoke runner per just-added FQTN,
//     classify outcome per AC #4. On accept, append failing-just-added
//     IDs to baseline via PostAcceptUpdateRustBaseline (AC #12 (c)).
//
//     Pre-edit gate integration (T54) lives in front of the red-check.
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

// captureRedCandidates extracts the test ids a sibling-test edit introduces
// (post-edit set minus pre-edit set) and persists them, keyed by the absolute
// test-file path, into the session's RedCandidates. This is the Go/Python/JS-TS
// analog of the Rust just-added computation: these languages have no persisted
// baseline, so the just-added set is captured at test-edit time and consumed by
// siblingRedCheck at production-edit time (spec 0018, Decision D1). Best-effort
// — any error is swallowed; a test-file edit is always allowed.
func captureRedCandidates(ti ToolInput, absPath, root string) {
	preBytes, _ := os.ReadFile(absPath)
	pre := string(preBytes)
	post := applyEdit(pre, ti)

	preIDs := extractTestIDs(absPath, pre)
	postIDs := extractTestIDs(absPath, post)

	preSet := stringSet(preIDs)
	var added []string
	for _, id := range postIDs {
		if _, ok := preSet[id]; !ok {
			added = append(added, id)
		}
	}
	_ = speccraft.SetRedCandidates(root, absPath, added)
}

// extractTestIDs selects the per-language test-identifier extractor by file
// extension. Go → func Test…; Python → def test…; otherwise the JS/TS
// test()/it()/describe() extractor (one extractor for both, per spec 0018).
func extractTestIDs(absPath, content string) []string {
	switch {
	case strings.HasSuffix(absPath, ".go"):
		return speccraft.GoTestIDs(content)
	case strings.HasSuffix(absPath, ".py"):
		return speccraft.PythonTestIDs(content)
	default:
		return speccraft.JSTSTestIDs(content)
	}
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

// prologueDecision is the tri-state result from prodGuardPrologue.
type prologueDecision int

const (
	prologueContinue prologueDecision = iota // all gates passed; caller must do its own sibling check
	prologueAllow                            // override consumed; caller should allow immediately
	prologueBlock                            // a gate failed; caller should return the error
)

// prodGuardPrologue enforces the three shared gates (active-spec, status,
// ConsumeOverride) that apply equally to Go/Python and JS/TS production
// file writes. It returns (prologueAllow, nil) when an override is consumed,
// (prologueContinue, nil) when all gates pass, and (prologueBlock, err) when
// a gate fails.
func prodGuardPrologue(absPath, root string) (prologueDecision, error) {
	state, err := speccraft.LoadState(root)
	if err != nil {
		return prologueBlock, nil
	}

	if state.ActiveSpec == "" {
		return prologueBlock, fmt.Errorf(
			"No active spec. Edits to production code are blocked.\n"+
				"Use /spec:new \"<title>\" to start a spec, or set status: in-progress\n"+
				"on an existing spec.\n\n"+
				"File: %s", absPath)
	}

	specFile := filepath.Join(root, "specs", state.ActiveSpec, "spec.md")
	if status := readFrontmatterField(specFile, "status"); status != "in-progress" && status != "" {
		return prologueBlock, fmt.Errorf(
			"Active spec %q is in status %q. Move to in-progress before\n"+
				"editing production code.", state.ActiveSpec, status)
	}

	if ok, err := speccraft.ConsumeOverride(root); err == nil && ok {
		return prologueAllow, nil
	}

	return prologueContinue, nil
}

// siblingRedCheck is the shared red-check for Go/Python/JS-TS production edits
// (spec 0018). It requires an OBSERVED failing test among the set the session
// just-added to the resolved sibling test file(s) before allowing the edit,
// replacing the pre-0018 "a sibling test was touched this session" check.
//
// Decision D1: unlike Rust (which allows a green/refactor edit when nothing new
// was added, backed by rust_test_baseline), these languages have no baseline,
// so an empty just-added set BLOCKS. Decision D2: an unresolved runner BLOCKS
// (fail-closed), never falls back to the touch-check. AC9: the real adapter
// invocation is deadline-bounded so a hanging runner cannot wedge the hook.
func siblingRedCheck(absPath, root string, cfg speccraft.SpeccraftConfig, lang string, d deps) error {
	siblings := resolveSiblingTests(absPath, root, cfg, lang)
	redCand, _ := speccraft.GetRedCandidates(root)

	justAdded := map[string]struct{}{}
	var justAddedList []string
	for _, sib := range siblings {
		for _, id := range redCand[sib] {
			if _, seen := justAdded[id]; !seen {
				justAdded[id] = struct{}{}
				justAddedList = append(justAddedList, id)
			}
		}
	}
	dir := filepath.Dir(absPath)

	if len(justAdded) == 0 {
		return fmt.Errorf(
			"TDD invariant: no failing test observed for %s.\n\n"+
				"No test was added this session — add a failing test (RED) in a sibling\n"+
				"test file, then edit the production file.\n\n"+
				"Use /speccraft:spec:override \"<reason>\" for a one-time bypass.",
			dir)
	}

	if d.runnerForLang == nil {
		return fmt.Errorf("speccraft-guard: no language runner factory wired")
	}
	adapter, ok := d.runnerForLang(lang, cfg)
	if !ok {
		return fmt.Errorf(
			"TDD invariant: no test runner available for %s.\n\n"+
				"Configure a test command under [tdd.%s] in .speccraft/speccraft.toml,\n"+
				"or use /speccraft:spec:override \"<reason>\" for a one-time bypass.",
			dir, lang)
	}

	ctx, cancel := context.WithTimeout(context.Background(), redCheckTimeout)
	defer cancel()

	for _, sib := range siblings {
		ids := redCand[sib]
		sibDir := filepath.Dir(sib)
		for _, id := range ids {
			res, err := adapter.Run(ctx, runner.Request{WorkDir: sibDir, FullyQualifiedTestName: id})
			if err != nil {
				return fmt.Errorf("red-check runner: %w", err)
			}
			if res.Outcome == runner.OutcomeBuildFailed {
				return fmt.Errorf(
					"red-check: build/collection failed (not a valid RED state):\n%s\n\n"+
						"Fix the build error so the just-added test can run and fail.",
					strings.TrimSpace(res.Stderr))
			}
			for _, rec := range res.Records {
				if rec.Status == "failed" {
					if _, isJustAdded := justAdded[rec.TestName]; isJustAdded {
						return nil // observed RED for a just-added test → allow
					}
				}
			}
		}
	}

	return fmt.Errorf(
		"red-check: no failing test observed among the tests added this session: %v\n\n"+
			"A just-added test must FAIL (RED) before the production edit is allowed.\n"+
			"Use /speccraft:spec:override \"<reason>\" for a one-time bypass.",
		justAddedList)
}

// resolveSiblingTests returns the candidate sibling test-file paths for a
// production file, language-aware. Go/Python use on-disk glob resolution
// (SiblingTestFiles); JS/TS use the computed candidate-path set (the red-check
// then intersects whichever of these the session actually edited via
// RedCandidates).
func resolveSiblingTests(absPath, root string, cfg speccraft.SpeccraftConfig, lang string) []string {
	if lang == "js" || lang == "ts" {
		return jsTsCandidateTestPaths(absPath)
	}
	sibs, _ := speccraft.SiblingTestFiles(absPath, root, cfg.TDD.TestRoots)
	return sibs
}

// goPythonProdGuard gates a Go or Python production-file edit. After the shared
// prologue it runs the spec-0018 red-check: a test the session just-added to a
// sibling test file must be observed to FAIL before the edit is allowed (this
// replaces the pre-0018 "a sibling test was touched this session" check).
func goPythonProdGuard(absPath, root string, cfg speccraft.SpeccraftConfig, d deps) error {
	dec, err := prodGuardPrologue(absPath, root)
	switch dec {
	case prologueBlock:
		return err
	case prologueAllow:
		return nil
	}
	return siblingRedCheck(absPath, root, cfg, langFor(absPath), d)
}

// langFor maps a production file path to the red-check language token used by
// runner.AdapterForLanguage: ".py" → "python", otherwise "go".
func langFor(absPath string) string {
	if strings.HasSuffix(absPath, ".py") {
		return "python"
	}
	return "go"
}

// jsTsDispatch gates a JavaScript/TypeScript production-file edit. After the
// shared prologue it runs the spec-0018 red-check: a test the session just-added
// to a candidate sibling test file must be observed to FAIL before the edit is
// allowed (this replaces the pre-0018 session-membership touch-check). JS and TS
// share one adapter; the language token only selects the configured command.
func jsTsDispatch(absPath, root string, cfg speccraft.SpeccraftConfig, d deps) error {
	dec, err := prodGuardPrologue(absPath, root)
	switch dec {
	case prologueBlock:
		return err
	case prologueAllow:
		return nil
	}
	return siblingRedCheck(absPath, root, cfg, jsTsLangFor(absPath), d)
}

// jsTsLangFor returns "ts" for TypeScript extensions and "js" otherwise, so the
// red-check picks the matching [tdd.typescript] / [tdd.javascript] command.
func jsTsLangFor(absPath string) string {
	switch strings.ToLower(filepath.Ext(absPath)) {
	case ".ts", ".tsx", ".mts", ".cts":
		return "ts"
	default:
		return "js"
	}
}

// jsTsCandidateTestPaths returns the candidate sibling test-file paths for a
// JS/TS production file: same-directory `*.test.<ext>` / `*.spec.<ext>` and the
// `__tests__/` convention, across the 8 JS/TS extensions. These are the keys the
// red-check looks up in the session's RedCandidates (spec 0018).
func jsTsCandidateTestPaths(absPath string) []string {
	dir := filepath.Dir(absPath)
	stem := strings.TrimSuffix(filepath.Base(absPath), filepath.Ext(absPath))
	exts := []string{"js", "ts", "jsx", "tsx", "mjs", "cjs", "mts", "cts"}
	var candidates []string
	for _, ext := range exts {
		candidates = append(candidates,
			filepath.Clean(filepath.Join(dir, stem+".test."+ext)),
			filepath.Clean(filepath.Join(dir, stem+".spec."+ext)),
			filepath.Clean(filepath.Join(dir, "__tests__", stem+".test."+ext)),
			filepath.Clean(filepath.Join(dir, "__tests__", stem+".spec."+ext)),
			filepath.Clean(filepath.Join(dir, "__tests__", stem+"."+ext)),
		)
	}
	return candidates
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
