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
	Mode      string   `toml:"mode"`       // cli | acp | codex-plugin | subagent
	Cmd       []string `toml:"cmd"`        // CLI mode: command + base args
	Input     string   `toml:"input"`      // "stdin" | "argv" | "file"
	ACPAgent  string   `toml:"acp_agent"`  // ACP mode: agent name for acpx
	Strengths []string `toml:"strengths"`
	Enabled   *bool    `toml:"enabled"`    // nil means true

	// Spec 0054. ReferenceRead is opt-out: nil means true, so a registry
	// written before this field existed stays permissive.
	ReferenceRead *bool  `toml:"reference_read"`
	Model         string `toml:"model"`         // subagent: opus|sonnet|haiku|fable|inherit
	Effort        string `toml:"effort"`        // codex-plugin: none..xhigh
	PluginRoot    string `toml:"plugin_root"`   // codex-plugin: explicit root
	SubagentType  string `toml:"subagent_type"` // subagent: default speccraft:reviewer
}

// IsEnabled returns false only if explicitly set to false.
func (a Agent) IsEnabled() bool {
	return a.Enabled == nil || *a.Enabled
}

// IsReferenceRead returns false only if explicitly set to false (spec 0054).
func (a Agent) IsReferenceRead() bool {
	return a.ReferenceRead == nil || *a.ReferenceRead
}

// ValidModes are the dispatch modes a registry entry may name, in the order
// error messages list them.
var ValidModes = []string{"cli", "acp", "codex-plugin", "subagent"}

func isValidMode(m string) bool {
	for _, v := range ValidModes {
		if m == v {
			return true
		}
	}
	return false
}

// joinWith concatenates parts with sep. A local construct rather than a
// `strings` import: conventions §"Avoid a NEW import to dodge the
// import-then-use guard deadlock" — the import line alone is a build-failing
// edit until the using code lands, and the dependency-free form costs nothing.
func joinWith(parts []string, sep string) string {
	out := ""
	for i, p := range parts {
		if i > 0 {
			out += sep
		}
		out += p
	}
	return out
}

// agentKeySets returns, per [[agents]] element in document order, the set of
// keys that element EXPLICITLY defined ("mode", "cmd", …).
//
// This exists because toml.MetaData.IsDefined cannot address array-of-table
// elements: md.IsDefined("agents", "mode") reports false even when an element
// does define mode. md.Keys() does carry the information — it emits keys in
// document order with a bare "agents" key introducing each element — so each
// bare "agents" starts a new set. Needed to tell an ABSENT mode (which
// normalizes to cli) from an explicitly empty one (a named error).
func agentKeySets(md toml.MetaData) []map[string]bool {
	var out []map[string]bool
	for _, k := range md.Keys() {
		if len(k) == 0 || k[0] != "agents" {
			continue
		}
		if len(k) == 1 {
			out = append(out, map[string]bool{})
			continue
		}
		if len(out) == 0 {
			continue
		}
		out[len(out)-1][joinWith(k[1:], ".")] = true
	}
	return out
}

// validateAgents normalizes an omitted mode to cli and rejects an explicitly
// empty or unrecognised one. Modes are case-sensitive: a permissive decode
// would accept "Subagent" and then route on a mode no dispatcher knows.
func validateAgents(cfg *Config, defined []map[string]bool) error {
	for i := range cfg.Agents {
		a := &cfg.Agents[i]
		keys := map[string]bool{}
		if i < len(defined) {
			keys = defined[i]
		}
		if !keys["mode"] {
			a.Mode = "cli"
			continue
		}
		if !isValidMode(a.Mode) {
			return fmt.Errorf(
				"agents.toml: agent %q has mode %q; valid modes are %s",
				a.Name, a.Mode, joinWith(ValidModes, ", "))
		}
	}
	return nil
}

// LoadConfig reads agents.toml from the repo's .speccraft/ directory.
func LoadConfig(root string) (*Config, error) {
	path := filepath.Join(root, ".speccraft", "agents.toml")
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("reading agents.toml: %w", err)
	}
	var cfg Config
	md, err := toml.Decode(string(data), &cfg)
	if err != nil {
		return nil, fmt.Errorf("parsing agents.toml: %w", err)
	}
	if err := validateAgents(&cfg, agentKeySets(md)); err != nil {
		return nil, err
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
