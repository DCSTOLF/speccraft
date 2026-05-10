// Package delegate loads agents.toml and builds aux-agent invocation commands.
package delegate

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/BurntSushi/toml"
)

// Config is the top-level agents.toml structure.
type Config struct {
	Defaults Defaults  `toml:"defaults"`
	Agents   []Agent   `toml:"agents"`
}

// Defaults holds global settings.
type Defaults struct {
	ReviewQuorum   int `toml:"review_quorum"`
	ReviewTimeoutS int `toml:"review_timeout_s"`
}

// Agent is a single aux-agent entry.
type Agent struct {
	Name      string   `toml:"name"`
	Mode      string   `toml:"mode"`       // "cli" or "acp"
	Cmd       []string `toml:"cmd"`        // CLI mode: command + base args
	Input     string   `toml:"input"`      // "stdin" | "argv" | "file"
	ACPAgent  string   `toml:"acp_agent"`  // ACP mode: agent name for acpx
	Strengths []string `toml:"strengths"`
	Enabled   *bool    `toml:"enabled"`    // nil means true
}

// IsEnabled returns false only if explicitly set to false.
func (a Agent) IsEnabled() bool {
	return a.Enabled == nil || *a.Enabled
}

// LoadConfig reads agents.toml from the repo's .speccraft/ directory.
func LoadConfig(root string) (*Config, error) {
	path := filepath.Join(root, ".speccraft", "agents.toml")
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("reading agents.toml: %w", err)
	}
	var cfg Config
	if _, err := toml.Decode(string(data), &cfg); err != nil {
		return nil, fmt.Errorf("parsing agents.toml: %w", err)
	}
	if cfg.Defaults.ReviewTimeoutS == 0 {
		cfg.Defaults.ReviewTimeoutS = 600
	}
	if cfg.Defaults.ReviewQuorum == 0 {
		cfg.Defaults.ReviewQuorum = 1
	}
	return &cfg, nil
}

// FindAgent returns the agent with the given name, or an error.
func (cfg *Config) FindAgent(name string) (*Agent, error) {
	for i := range cfg.Agents {
		if cfg.Agents[i].Name == name {
			return &cfg.Agents[i], nil
		}
	}
	return nil, fmt.Errorf("agent %q not found in agents.toml", name)
}

// EnabledAgents returns all agents where IsEnabled() is true.
func (cfg *Config) EnabledAgents() []*Agent {
	var out []*Agent
	for i := range cfg.Agents {
		if cfg.Agents[i].IsEnabled() {
			out = append(out, &cfg.Agents[i])
		}
	}
	return out
}
