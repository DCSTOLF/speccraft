package speccraft

import (
	"os"
	"path/filepath"
	"strings"
)

// SpeccraftConfig holds settings from .speccraft/speccraft.toml.
type SpeccraftConfig struct {
	TDD TDDConfig
}

type TDDConfig struct {
	// TestRoots are directories (relative to repo root) searched for Python test
	// files when no same-directory sibling is found.
	TestRoots []string
}

// ReadConfig loads .speccraft/speccraft.toml from the repo root.
// Missing file → zero-value config (no error). Parse errors are silently skipped.
func ReadConfig(root string) SpeccraftConfig {
	var cfg SpeccraftConfig
	data, err := os.ReadFile(filepath.Join(root, ".speccraft", "speccraft.toml"))
	if err != nil {
		return cfg
	}
	parseSpeccraftTOML(string(data), &cfg)
	return cfg
}

func parseSpeccraftTOML(content string, cfg *SpeccraftConfig) {
	inTDD := false
	for _, line := range strings.Split(content, "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		if line == "[tdd]" {
			inTDD = true
			continue
		}
		if strings.HasPrefix(line, "[") {
			inTDD = false
			continue
		}
		if inTDD && strings.HasPrefix(line, "test_roots") {
			cfg.TDD.TestRoots = parseTOMLStringArray(line)
		}
	}
}

// parseTOMLStringArray parses a single-line TOML string array value, e.g.:
//
//	test_roots = ["tests", "test"]
func parseTOMLStringArray(line string) []string {
	open := strings.Index(line, "[")
	close := strings.LastIndex(line, "]")
	if open < 0 || close <= open {
		return nil
	}
	inner := line[open+1 : close]
	var result []string
	for _, part := range strings.Split(inner, ",") {
		val := strings.Trim(strings.TrimSpace(part), `"'`)
		if val != "" {
			result = append(result, val)
		}
	}
	return result
}
