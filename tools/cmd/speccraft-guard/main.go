package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"

	"github.com/dcstolf/speccraft/tools/internal/speccraft"
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

	filePath := input.ToolInput.FilePath
	if filePath == "" {
		return nil
	}

	// Resolve absolute path.
	absPath, err := filepath.Abs(filePath)
	if err != nil {
		return nil
	}

	// Find repo root.
	cwd := input.CWD
	if cwd == "" {
		cwd, _ = os.Getwd()
	}
	root, err := speccraft.FindRoot(cwd)
	if err != nil {
		// Not a speccraft repo → allow.
		return nil
	}

	// Rule 1: outside repo → allow.
	rel, err := filepath.Rel(root, absPath)
	if err != nil || len(rel) >= 2 && rel[:2] == ".." {
		return nil
	}

	// Rule 2: always-allowed paths.
	if speccraft.IsAlwaysAllowed(root, absPath) {
		return nil
	}

	// Rule 3: test files → allow, track.
	if speccraft.IsTestFile(absPath) {
		// Tracking is done by post-tool-use.sh; allow here.
		return nil
	}

	// Rule 4: production Go file → check active spec + TDD invariant.
	if speccraft.IsProductionGoFile(absPath) {
		state, err := speccraft.LoadState(root)
		if err != nil {
			return nil
		}

		// Check active spec.
		if state.ActiveSpec == "" || state.ActiveSpec == "null" {
			return fmt.Errorf(
				"No active spec. Edits to production code are blocked.\n"+
					"Use /spec:new \"<title>\" to start a spec, or set status: in-progress\n"+
					"on an existing spec.\n\n"+
					"File: %s", absPath)
		}

		// Check spec status.
		specFile := filepath.Join(root, "specs", state.ActiveSpec, "spec.md")
		if status := readFrontmatterField(specFile, "status"); status != "in-progress" && status != "" {
			return fmt.Errorf(
				"Active spec %q is in status %q. Move to in-progress before\n"+
					"editing production code.", state.ActiveSpec, status)
		}

		// TDD invariant: check sibling tests.
		siblings, _ := speccraft.SiblingTestFiles(absPath)
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
				"TDD invariant: edit a test in %s/ this session before editing\n"+
					"the production file.\n\n"+
					"If no test exists yet, create one (RED) first.\n"+
					"Sibling test files found:%s\n\n"+
					"Use /spec:override \"<reason>\" for a one-time bypass.",
				dir, siblingList)
		}
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
		if len(line) > len(prefix) && line[:len(prefix)] == prefix {
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
