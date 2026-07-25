package speccraft_test

// Spec 0034 AC6 — the authoring prose must be stack-neutral (recurrence guard).
//
// The planner subagent + the plan/implement/delegate command docs must NOT
// mandate a Go-specific test command as THE action; they reference the project's
// command (`speccraft-state test-command`) instead. A concrete language command
// is allowed ONLY as a clearly-labeled Example or when the line itself invokes
// `speccraft-state test-command`.
//
// Mechanical rule (replaces subjective "mandate vs example"): a line containing a
// concrete test command is a VIOLATION unless (a) it references
// `speccraft-state test-command`, or (b) it sits under an Example label — for a
// fenced block, the nearest non-blank line above the opening fence matches the
// example-label regex; for an inline line, that line or the line above it does.
// The label regex requires "example" to START the (optionally #/>/-, prefixed)
// line, so prose ending in "…for example:" does not exempt anything.

import (
	"path/filepath"
	"regexp"
	"strings"
	"testing"
)

func Test_AuthoringProse_NoUnlabeledConcreteTestCommand(t *testing.T) {
	root := findDocsRoot(t)
	docs := []string{
		filepath.Join(root, "agents", "tdd-planner.md"),
		filepath.Join(root, "commands", "spec", "plan.md"),
		filepath.Join(root, "commands", "spec", "implement.md"),
		filepath.Join(root, "commands", "spec", "delegate.md"),
	}
	cmdRe := regexp.MustCompile(`go test|cargo test|cargo nextest|pytest|npm test|npm run|jest|-name '\*_test\.go'`)
	exampleRe := regexp.MustCompile(`(?i)^\s*(#{1,6}\s*|>\s*|[-*]\s*)?example\b`)

	for _, doc := range docs {
		src := readFile(t, doc)
		lines := strings.Split(src, "\n")
		inFence := false
		labelAbove := "" // nearest non-blank, non-fence line before the open fence
		prevNonBlank := ""
		for _, line := range lines {
			trimmed := strings.TrimSpace(line)
			if strings.HasPrefix(trimmed, "```") {
				if !inFence {
					labelAbove = prevNonBlank
				}
				inFence = !inFence
				continue // do not treat the ``` marker as context
			}
			if cmdRe.MatchString(line) {
				ctx := prevNonBlank
				if inFence {
					ctx = labelAbove
				}
				exempt := strings.Contains(line, "speccraft-state test-command") ||
					exampleRe.MatchString(line) ||
					exampleRe.MatchString(ctx)
				if !exempt {
					t.Errorf("%s: concrete test command mandated outside a labeled Example and not via "+
						"`speccraft-state test-command` (spec 0034 AC6):\n  %s",
						filepath.Base(doc), strings.TrimSpace(line))
				}
			}
			if trimmed != "" {
				prevNonBlank = trimmed
			}
		}
	}
}
