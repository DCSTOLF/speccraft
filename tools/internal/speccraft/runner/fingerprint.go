package runner

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

// trackedRoots lists the directory roots under which `.rs` files are
// included in the crate fingerprint. `target/` is explicitly NOT walked
// regardless of where it appears.
var trackedRoots = []string{"src", "tests", "examples", "benches"}

// trackedSingles lists individual files (at the crate root) whose
// presence and mtime/size feed into the fingerprint. Missing entries
// contribute nothing — they do not produce an error.
var trackedSingles = []string{"Cargo.toml", "Cargo.lock", "rust-toolchain.toml", ".cargo/config.toml"}

// ComputeCrateFingerprint returns a 64-char lowercase hex SHA-256 over
// the sorted set of `(relative-path, mtime-nanos, size)` tuples
// covering every tracked file in the crate at root (spec 0005 §What.4).
//
// Tracked files:
//   - every `.rs` file under `src/`, `tests/`, `examples/`, `benches/`
//   - `Cargo.toml`, `Cargo.lock`, `rust-toolchain.toml`, `.cargo/config.toml` (if present)
//
// `target/` is excluded everywhere. Missing tracked-single files are
// silently skipped (not an error).
//
// The empty-root case returns a deterministic hash of the empty tuple
// list (still 64 hex chars), so callers can compare without special-
// casing.
func ComputeCrateFingerprint(root string) (string, error) {
	type entry struct {
		path string
		mtime int64
		size  int64
	}
	var entries []entry

	for _, sub := range trackedRoots {
		base := filepath.Join(root, sub)
		err := filepath.Walk(base, func(path string, info os.FileInfo, err error) error {
			if err != nil {
				if os.IsNotExist(err) {
					return nil
				}
				return err
			}
			if info.IsDir() {
				if info.Name() == "target" {
					return filepath.SkipDir
				}
				return nil
			}
			if !strings.HasSuffix(path, ".rs") {
				return nil
			}
			rel, err := filepath.Rel(root, path)
			if err != nil {
				return err
			}
			entries = append(entries, entry{
				path:  filepath.ToSlash(rel),
				mtime: info.ModTime().UnixNano(),
				size:  info.Size(),
			})
			return nil
		})
		if err != nil {
			return "", err
		}
	}

	for _, single := range trackedSingles {
		path := filepath.Join(root, filepath.FromSlash(single))
		info, err := os.Stat(path)
		if err != nil {
			if os.IsNotExist(err) {
				continue
			}
			return "", err
		}
		if info.IsDir() {
			continue
		}
		entries = append(entries, entry{
			path:  single,
			mtime: info.ModTime().UnixNano(),
			size:  info.Size(),
		})
	}

	sort.Slice(entries, func(i, j int) bool { return entries[i].path < entries[j].path })

	h := sha256.New()
	for _, e := range entries {
		fmt.Fprintf(h, "%s\x00%d\x00%d\n", e.path, e.mtime, e.size)
	}
	return hex.EncodeToString(h.Sum(nil)), nil
}
