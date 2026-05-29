package speccraft

import (
	"os"
	"path/filepath"
	"strings"
)

// RustProdForTest returns the production file that the integration test
// at testRelPath maps to via the stem-mapping rules in spec 0005
// §What.2/AC #3:
//
//   - tests/<stem>.rs → src/<stem>.rs (preferred, Rust 2015/2018 file form)
//   - tests/<stem>.rs → src/<stem>/mod.rs (Rust 2015 directory submodule)
//   - tests/<stem>.rs → src/<stem>.rs paired with src/<stem>/ (Rust 2018+ path form)
//
// `lib.rs` is the library crate root, NOT a stem-mapping target
// (AC #11). Inputs that are not under `tests/` return the empty string.
//
// All paths are relative to root and returned in forward-slash form.
func RustProdForTest(testRelPath, root string) string {
	clean := filepath.ToSlash(testRelPath)
	if !strings.HasPrefix(clean, "tests/") {
		return ""
	}
	stem := strings.TrimSuffix(strings.TrimPrefix(clean, "tests/"), ".rs")
	if stem == "" || stem == "lib" {
		return ""
	}
	// Precedence order: src/<stem>.rs, src/<stem>/mod.rs.
	candidates := []string{
		"src/" + stem + ".rs",
		"src/" + stem + "/mod.rs",
	}
	for _, c := range candidates {
		full := filepath.Join(root, filepath.FromSlash(c))
		if info, err := os.Stat(full); err == nil && !info.IsDir() {
			return c
		}
	}
	return ""
}
