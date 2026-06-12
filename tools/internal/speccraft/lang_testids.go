package speccraft

import (
	"regexp"
	"strings"
)

// Per-language extraction of test-function identifiers from source text.
// These are the non-Rust analog of rust_canonical.go's CanonicalIDsForFile:
// speccraft-guard diffs the pre-edit vs post-edit identifier sets of a touched
// sibling test file to compute the session's "just-added" test set, which the
// red-check requires an observed failure within (spec 0018, Decision D1).
//
// Extraction keys on the OUTER declaration only (func Test…, def test_…,
// test(/it(/describe( call). Subtests, parametrize cases, and template-literal
// names are intentionally not expanded — a false negative shrinks the
// just-added set and therefore over-blocks (fail-closed, safe), never
// fail-open. See spec 0018 plan §Risk.

var (
	goTestRe     = regexp.MustCompile(`(?m)^\s*func\s+(Test\w*)\s*\(`)
	pythonTestRe = regexp.MustCompile(`(?m)^\s*def\s+(test\w*)\s*\(`)
	// JS/TS: test('name', ...), it("name", ...), describe(` + "`name`" + `, ...).
	jsTsTestRe = regexp.MustCompile("(?m)(?:^|[^.\\w])(?:test|it|describe)\\s*\\(\\s*['\"`]([^'\"`]+)")
)

// GoTestIDs returns the names of Go test functions (func Test…) in source
// order, ignoring commented-out declarations.
func GoTestIDs(src string) []string {
	return matchTestIDs(goTestRe, stripCStyleComments(src))
}

// PythonTestIDs returns the names of Python test functions (def test…) in
// source order, ignoring commented-out declarations.
func PythonTestIDs(src string) []string {
	return matchTestIDs(pythonTestRe, stripHashComments(src))
}

// JSTSTestIDs returns the string names passed to test()/it()/describe() in
// source order, ignoring commented-out calls. JavaScript and TypeScript share
// this one extractor (spec 0018: one JS/TS adapter and resolution path).
func JSTSTestIDs(src string) []string {
	return matchTestIDs(jsTsTestRe, stripCStyleComments(src))
}

func matchTestIDs(re *regexp.Regexp, src string) []string {
	matches := re.FindAllStringSubmatch(src, -1)
	if matches == nil {
		return nil
	}
	out := make([]string, 0, len(matches))
	for _, m := range matches {
		out = append(out, m[1])
	}
	return out
}

// stripCStyleComments removes // line comments and /* */ block comments while
// preserving string-literal contents (so JS/TS test names inside quotes are
// kept). It is deliberately small, not a full parser — sufficient for
// identifier extraction.
func stripCStyleComments(s string) string {
	var b strings.Builder
	b.Grow(len(s))
	n := len(s)
	var inStr byte // 0, or the open quote: ' " `
	for i := 0; i < n; {
		c := s[i]
		if inStr != 0 {
			b.WriteByte(c)
			if c == '\\' && i+1 < n {
				b.WriteByte(s[i+1])
				i += 2
				continue
			}
			if c == inStr {
				inStr = 0
			}
			i++
			continue
		}
		if c == '/' && i+1 < n && s[i+1] == '/' {
			for i < n && s[i] != '\n' {
				i++
			}
			continue
		}
		if c == '/' && i+1 < n && s[i+1] == '*' {
			i += 2
			for i < n && !(s[i] == '*' && i+1 < n && s[i+1] == '/') {
				i++
			}
			i += 2
			continue
		}
		if c == '\'' || c == '"' || c == '`' {
			inStr = c
			b.WriteByte(c)
			i++
			continue
		}
		b.WriteByte(c)
		i++
	}
	return b.String()
}

// stripHashComments removes # line comments (Python) while preserving string
// contents within a line. Line-scoped; sufficient for def-name extraction.
func stripHashComments(s string) string {
	lines := strings.Split(s, "\n")
	for li, line := range lines {
		var inStr byte
		cut := -1
		for i := 0; i < len(line); i++ {
			c := line[i]
			if inStr != 0 {
				if c == '\\' {
					i++
					continue
				}
				if c == inStr {
					inStr = 0
				}
				continue
			}
			if c == '\'' || c == '"' {
				inStr = c
				continue
			}
			if c == '#' {
				cut = i
				break
			}
		}
		if cut >= 0 {
			lines[li] = line[:cut]
		}
	}
	return strings.Join(lines, "\n")
}
