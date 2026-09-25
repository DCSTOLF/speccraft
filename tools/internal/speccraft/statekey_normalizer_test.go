package speccraft_test

// Spec 0048 T10 (AC15) — one normalizer, pinned by a source-scan.
//
// The defect this guards against is not a wrong normalizer; it is TWO of them.
// Capture writes a state key and the red-check reads one, and if the two derive
// their keys differently then a symlinked or uncleaned repo registers candidates
// under a key the lookup can never see — state.json plainly shows the candidate
// while every production edit is refused. A single entrypoint is the only way
// that stays true as call sites are added.
//
// Follows the spec-0036 single-entrypoint pattern (exactly one definition) and
// the spec-0032 anchored-scan rule: anchor on `func X(` and search WITHIN that
// function's body, never the first textual match in the file.

import (
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
)

// toolsRoot resolves tools/ from this test file's location.
func toolsRoot(t *testing.T) string {
	t.Helper()
	wd, err := os.Getwd() // .../tools/internal/speccraft
	if err != nil {
		t.Fatal(err)
	}
	return filepath.Clean(filepath.Join(wd, "..", ".."))
}

func Test_NormalizeStateKey_IsTheSoleEntrypoint(t *testing.T) {
	root := toolsRoot(t)
	re := regexp.MustCompile(`func NormalizeStateKey\(`)
	count := 0
	var where []string

	err := filepath.Walk(root, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		// _test.go files are excluded, and that is load-bearing rather than
		// convenient: THIS file contains the pattern as a regex literal, so
		// scanning tests would count the scanner as a definition and the
		// assertion could never pass. The rule is about production code.
		if info.IsDir() || !strings.HasSuffix(path, ".go") || strings.HasSuffix(path, "_test.go") {
			return nil
		}
		b, readErr := os.ReadFile(path)
		if readErr != nil {
			return readErr
		}
		if n := len(re.FindAll(b, -1)); n > 0 {
			count += n
			where = append(where, path)
		}
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
	if count != 1 {
		t.Errorf("want exactly one `func NormalizeStateKey(` definition, found %d in %v", count, where)
	}
}

// funcBody returns the source of `func <name>(` up to the next line that starts a
// new top-level declaration. Anchored per spec 0032: a whole-file search would
// match a `NormalizeStateKey(` call in a NEIGHBOURING function and pass while the
// function under test still derived its own key.
func funcBody(t *testing.T, src, name string) string {
	t.Helper()
	anchor := "func " + name + "("
	i := strings.Index(src, anchor)
	if i < 0 {
		t.Fatalf("anchor %q not found — the scan would pass vacuously", anchor)
	}
	rest := src[i+len(anchor):]
	// The body ends at the next top-level `func ` or `}` at column 0 followed by
	// a blank line; `\nfunc ` is sufficient here and keeps the scan simple.
	if j := strings.Index(rest, "\nfunc "); j >= 0 {
		return rest[:j]
	}
	return rest
}

// Test_FuncBodyScan_IsAnchored_NotWholeFile proves the scan below actually
// discriminates. Spec 0032's rule exists because a whole-file search passes as
// soon as ANY function in the file mentions the token — so the scan would report
// a clean bill of health for a function that derives its own key, as long as a
// neighbour was well-behaved. Asserted against a synthetic source rather than
// trusted.
func Test_FuncBodyScan_IsAnchored_NotWholeFile(t *testing.T) {
	src := "" +
		"func Good(p string) string {\n\treturn NormalizeStateKey(p)\n}\n" +
		"\nfunc Bad(p string) string {\n\treturn filepath.Clean(p)\n}\n"

	good := funcBody(t, src, "Good")
	if !strings.Contains(good, "NormalizeStateKey(") {
		t.Error("anchored body of Good should contain the normalizer call")
	}
	bad := funcBody(t, src, "Bad")
	if strings.Contains(bad, "NormalizeStateKey(") {
		t.Error("anchored body of Bad must NOT see Good's normalizer call — the scan is not anchored")
	}
	if !strings.Contains(bad, "filepath.Clean(") {
		t.Error("anchored body of Bad should contain its own bare derivation")
	}
}

func Test_StateKeyConstruction_RoutesThroughNormalizer(t *testing.T) {
	root := toolsRoot(t)

	// THIS package's call sites only. The guard's two (`captureRedCandidates`,
	// `siblingRedCheck`) are scanned by
	// tools/cmd/speccraft-guard/statekey_routing_test.go instead of from here:
	// reaching across packages by file path is brittle, and — the deciding
	// reason — the TDD red-check is package-scoped, so a structural RED in this
	// package cannot authorise an edit to the guard's main.go. Each package pins
	// its own routing.
	targets := []struct {
		file string
		fn   string
	}{
		{filepath.Join(root, "internal", "speccraft", "buildrepair.go"), "CaptureRedCandidates"},
		{filepath.Join(root, "internal", "speccraft", "buildrepair.go"), "RecordBuildRepair"},
	}

	// A bare Abs/Clean inside these functions means a second, divergeable key
	// derivation. NormalizeStateKey itself legitimately uses them, which is
	// exactly why the scan is per-function and NormalizeStateKey is not a target.
	bare := regexp.MustCompile(`filepath\.(Abs|Clean|EvalSymlinks)\(`)

	for _, tc := range targets {
		b, err := os.ReadFile(tc.file)
		if err != nil {
			t.Fatalf("%s: %v", tc.file, err)
		}
		body := funcBody(t, string(b), tc.fn)

		if !strings.Contains(body, "NormalizeStateKey(") {
			t.Errorf("%s: %s does not route its state key through NormalizeStateKey", filepath.Base(tc.file), tc.fn)
		}
		if loc := bare.FindString(body); loc != "" {
			t.Errorf("%s: %s derives a path with a bare %s — use NormalizeStateKey", filepath.Base(tc.file), tc.fn, loc)
		}
	}
}
