// Package drift implements regex-based drift detection for speccraft.
// It reads `<!-- enforce: regex pattern="..." [scope="..."] -->` directives
// from guardrails.md and conventions.md and checks edited files against them.
package drift

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

// Rule is a parsed enforce: directive.
type Rule struct {
	Source  string         // "guardrails.md#section" or "conventions.md#section"
	Pattern *regexp.Regexp
	Scope   string // glob pattern; "!" prefix means exclude; "" means all files
}

// Violation is a single drift finding.
type Violation struct {
	File    string
	Line    int
	Rule    *Rule
	Match   string
}

func (v Violation) String() string {
	return fmt.Sprintf("%s:%d: %s: matches /%s/",
		v.File, v.Line, v.Rule.Source, v.Rule.Pattern.String())
}

// LoadRules reads enforce: directives from .speccraft/guardrails.md and
// .speccraft/conventions.md.
func LoadRules(root string) ([]*Rule, error) {
	var rules []*Rule
	for _, fname := range []string{"guardrails.md", "conventions.md"} {
		path := filepath.Join(root, ".speccraft", fname)
		r, err := parseRulesFile(path, fname)
		if err != nil {
			if os.IsNotExist(err) {
				continue
			}
			return nil, err
		}
		rules = append(rules, r...)
	}
	return rules, nil
}

// parseRulesFile extracts enforce: regex directives from a markdown file.
// Directive format: <!-- enforce: regex pattern="..." [scope="..."] -->
var enforceRe = regexp.MustCompile(
	`<!--\s*enforce:\s*regex\s+pattern="([^"]+)"(?:\s+scope="([^"]*)")?\s*-->`)

func parseRulesFile(path, fname string) ([]*Rule, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()

	var rules []*Rule
	section := ""
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		line := scanner.Text()
		// Track section headings for source attribution.
		if strings.HasPrefix(line, "## ") {
			section = strings.TrimPrefix(line, "## ")
		}
		matches := enforceRe.FindStringSubmatch(line)
		if matches == nil {
			continue
		}
		patStr := matches[1]
		scope := ""
		if len(matches) > 2 {
			scope = matches[2]
		}
		// Unescape one level: \\ in the HTML comment represents \ in the regex.
		// This mirrors JSON escaping conventions used in the directive values.
		patStr = strings.ReplaceAll(patStr, `\\`, `\`)
		pat, err := regexp.Compile(patStr)
		if err != nil {
			return nil, fmt.Errorf("%s: invalid pattern %q: %w", path, patStr, err)
		}
		source := fname
		if section != "" {
			source = fname + "#" + strings.ToLower(strings.ReplaceAll(section, " ", "-"))
		}
		rules = append(rules, &Rule{
			Source:  source,
			Pattern: pat,
			Scope:   scope,
		})
	}
	return rules, scanner.Err()
}

// inScope returns true if path is within the rule's scope.
// scope="" means all files.
// scope="!<pattern>" means exclude files matching <pattern>.
// scope="<pattern>" means include only files matching <pattern>.
// Patterns ending in "/" match as directory prefixes.
// Other patterns use filepath.Match glob semantics.
func inScope(absPath, root, scope string) bool {
	if scope == "" {
		return true
	}
	rel, err := filepath.Rel(root, absPath)
	if err != nil {
		return false
	}
	rel = filepath.ToSlash(rel)

	exclude := strings.HasPrefix(scope, "!")
	pattern := scope
	if exclude {
		pattern = scope[1:]
	}

	var matched bool
	if strings.HasSuffix(pattern, "/") {
		// Directory prefix match: any file under this directory.
		matched = strings.HasPrefix(rel, pattern) || strings.HasPrefix(rel+"/", pattern)
	} else {
		// Glob match.
		matched, _ = filepath.Match(pattern, rel)
		if !matched {
			// Also try matching against each path component for ** patterns.
			matched, _ = filepath.Match(pattern, filepath.Base(rel))
		}
	}

	if exclude {
		return !matched
	}
	return matched
}

// CheckFile scans a single file against all rules whose scope matches.
func CheckFile(absPath, root string, rules []*Rule) ([]Violation, error) {
	// Don't scan .speccraft/ itself.
	if rel, _ := filepath.Rel(root, absPath); strings.HasPrefix(rel, ".speccraft/") {
		return nil, nil
	}

	data, err := os.ReadFile(absPath)
	if os.IsNotExist(err) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}

	var violations []Violation
	lines := strings.Split(string(data), "\n")

	for _, rule := range rules {
		if !inScope(absPath, root, rule.Scope) {
			continue
		}
		for i, line := range lines {
			if loc := rule.Pattern.FindStringIndex(line); loc != nil {
				violations = append(violations, Violation{
					File:  absPath,
					Line:  i + 1,
					Rule:  rule,
					Match: line[loc[0]:loc[1]],
				})
			}
		}
	}
	return violations, nil
}

// CheckAll scans all files in the repo against all rules.
func CheckAll(root string, rules []*Rule) ([]Violation, error) {
	var violations []Violation
	err := filepath.Walk(root, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return nil
		}
		if info.IsDir() {
			// Skip hidden dirs and common non-source dirs.
			name := info.Name()
			if strings.HasPrefix(name, ".") || name == "vendor" || name == "node_modules" {
				return filepath.SkipDir
			}
			return nil
		}
		vs, err := CheckFile(path, root, rules)
		if err != nil {
			return nil
		}
		violations = append(violations, vs...)
		return nil
	})
	return violations, err
}
