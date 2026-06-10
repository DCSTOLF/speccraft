package speccraft

import (
	"errors"
	"os"
	"path/filepath"
)

// FindRoot walks up from dir until it finds a directory containing .speccraft/.
// Returns the repo root path or an error if none found.
func FindRoot(dir string) (string, error) {
	if dir == "" {
		var err error
		dir, err = os.Getwd()
		if err != nil {
			return "", err
		}
	}
	dir, _ = filepath.Abs(dir)
	for {
		if _, err := os.Stat(filepath.Join(dir, ".speccraft")); err == nil {
			return dir, nil
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			break
		}
		dir = parent
	}
	return "", errors.New("no .speccraft/ directory found in any parent")
}

// StateFile returns the path to state.json given the repo root.
func StateFile(root string) string {
	return filepath.Join(root, ".speccraft", "state.json")
}

// SpecsDir returns the path to the specs/ directory given the repo root.
func SpecsDir(root string) string {
	return filepath.Join(root, "specs")
}

// ActiveSpecDir returns the path to the active spec's directory, or "" if none.
func ActiveSpecDir(root, activeSpec string) string {
	if activeSpec == "" {
		return ""
	}
	return filepath.Join(root, "specs", activeSpec)
}
