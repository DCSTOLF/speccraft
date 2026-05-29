package speccraft

import (
	"os"
	"path/filepath"
	"strings"
)

// IsCargoWorkspace returns true if the Cargo.toml at root contains a
// `[workspace]` section. Spec 0005 §What.6 / AC #5: workspaces are out
// of scope and must produce a hard error referencing follow-up spec 0006.
//
// Hybrid `[package] + [workspace]` Cargo.toml is also classified as a
// workspace (the workspace declaration is the disqualifier for single-
// crate support).
//
// Missing Cargo.toml returns (false, nil) — single-crate detection
// happens upstream when no toml is present.
func IsCargoWorkspace(root string) (bool, error) {
	path := filepath.Join(root, "Cargo.toml")
	data, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return false, nil
		}
		return false, err
	}
	for _, line := range strings.Split(string(data), "\n") {
		trimmed := strings.TrimSpace(line)
		if strings.HasPrefix(trimmed, "#") {
			continue
		}
		if trimmed == "[workspace]" || strings.HasPrefix(trimmed, "[workspace.") {
			return true, nil
		}
	}
	return false, nil
}
