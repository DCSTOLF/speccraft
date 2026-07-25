package main

// Spec 0034 — `speccraft-state test-command`: the effective host-repo test
// command. Precedence: the .speccraft/conventions.md marker (when present and
// non-empty) wins over detection; else the detect-stack fallback. The marker
// value is DATA — emitted verbatim, never shell-evaluated.

import (
	"os"
	"path/filepath"
	"regexp"
	"strings"

	"github.com/dcstolf/speccraft/tools/internal/speccraft"
)

// markerRe matches a single-line conventions.md test-command marker. The body is
// a proper quoted string: each element is an escape pair (\" or \\) or a
// non-quote/non-backslash char, so an UNescaped interior quote cannot match
// (→ malformed → the line is skipped). The character class excludes newlines, so
// the match never spans lines even before the per-line scan.
var markerRe = regexp.MustCompile(`<!--\s*speccraft:test-command\s*=\s*"((?:\\.|[^"\\\n])*)"\s*-->`)

// effectiveTestCommand returns the effective test command and whether it is
// non-empty. Marker (non-empty) → wins; else detect-stack; empty → (,,false).
func effectiveTestCommand(root string, cfg speccraft.SpeccraftConfig) (string, bool) {
	if cmd, ok := readTestCommandMarker(root); ok && cmd != "" {
		return cmd, true
	}
	cmd := speccraft.DetectStack(root, cfg).TestCommand
	return cmd, cmd != ""
}

// readTestCommandMarker scans conventions.md line-by-line and returns the FIRST
// valid marker's unescaped value. ok=false when no line matches (absent file,
// malformed marker). An empty captured value returns ("", true); the caller
// treats empty as "not recorded" and falls back to detection.
func readTestCommandMarker(root string) (string, bool) {
	data, err := os.ReadFile(filepath.Join(root, ".speccraft", "conventions.md"))
	if err != nil {
		return "", false
	}
	for _, line := range strings.Split(string(data), "\n") {
		if m := markerRe.FindStringSubmatch(line); m != nil {
			return unescapeMarker(m[1]), true
		}
	}
	return "", false
}

// unescapeMarker reverses the marker escaping: \" → " and \\ → \ (any \x → x).
func unescapeMarker(s string) string {
	var b strings.Builder
	for i := 0; i < len(s); i++ {
		if s[i] == '\\' && i+1 < len(s) {
			i++
		}
		b.WriteByte(s[i])
	}
	return b.String()
}
