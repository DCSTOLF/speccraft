package runner_test

import (
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/dcstolf/speccraft/tools/internal/speccraft/runner"
)

func write(t *testing.T, root, rel, content string) string {
	t.Helper()
	full := filepath.Join(root, filepath.FromSlash(rel))
	if err := os.MkdirAll(filepath.Dir(full), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(full, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
	return full
}

// touch sets the file's mtime to a fixed value (so subsequent edits change it).
func touch(t *testing.T, path string, when time.Time) {
	t.Helper()
	if err := os.Chtimes(path, when, when); err != nil {
		t.Fatal(err)
	}
}

func TestComputeCrateFingerprint_DeterministicOrder(t *testing.T) {
	root := t.TempDir()
	pinned := time.Date(2026, 1, 2, 3, 4, 5, 0, time.UTC)
	a := write(t, root, "src/a.rs", "// a\n")
	b := write(t, root, "src/b.rs", "// b\n")
	c := write(t, root, "Cargo.toml", "[package]\n")
	touch(t, a, pinned)
	touch(t, b, pinned)
	touch(t, c, pinned)

	fp1, err := runner.ComputeCrateFingerprint(root)
	if err != nil {
		t.Fatal(err)
	}
	fp2, err := runner.ComputeCrateFingerprint(root)
	if err != nil {
		t.Fatal(err)
	}
	if fp1 != fp2 {
		t.Errorf("fingerprint differs across calls: %q vs %q", fp1, fp2)
	}
	if len(fp1) != 64 { // SHA-256 hex
		t.Errorf("expected 64-char hex, got %q (len=%d)", fp1, len(fp1))
	}
}

func TestComputeCrateFingerprint_IncludesCargoToml(t *testing.T) {
	root := t.TempDir()
	now := time.Now()
	cargoPath := write(t, root, "Cargo.toml", "[package]\n")
	write(t, root, "src/lib.rs", "// lib\n")
	touch(t, cargoPath, now)

	before, _ := runner.ComputeCrateFingerprint(root)
	touch(t, cargoPath, now.Add(2*time.Second))
	after, _ := runner.ComputeCrateFingerprint(root)
	if before == after {
		t.Error("Cargo.toml mtime change did not invalidate fingerprint")
	}
}

func TestComputeCrateFingerprint_IncludesCargoLock(t *testing.T) {
	root := t.TempDir()
	now := time.Now()
	write(t, root, "Cargo.toml", "[package]\n")
	lockPath := write(t, root, "Cargo.lock", "# lock\n")
	touch(t, lockPath, now)

	before, _ := runner.ComputeCrateFingerprint(root)
	touch(t, lockPath, now.Add(2*time.Second))
	after, _ := runner.ComputeCrateFingerprint(root)
	if before == after {
		t.Error("Cargo.lock change did not invalidate fingerprint")
	}
}

func TestComputeCrateFingerprint_IncludesRustToolchainTomlIfPresent(t *testing.T) {
	root := t.TempDir()
	write(t, root, "Cargo.toml", "[package]\n")

	before, _ := runner.ComputeCrateFingerprint(root)
	// Now add rust-toolchain.toml.
	write(t, root, "rust-toolchain.toml", `[toolchain]\nchannel = "stable"\n`)
	after, _ := runner.ComputeCrateFingerprint(root)
	if before == after {
		t.Error("adding rust-toolchain.toml did not change fingerprint")
	}
}

func TestComputeCrateFingerprint_IncludesCargoConfigTomlIfPresent(t *testing.T) {
	root := t.TempDir()
	write(t, root, "Cargo.toml", "[package]\n")

	before, _ := runner.ComputeCrateFingerprint(root)
	write(t, root, ".cargo/config.toml", "# cargo config\n")
	after, _ := runner.ComputeCrateFingerprint(root)
	if before == after {
		t.Error("adding .cargo/config.toml did not change fingerprint")
	}
}

func TestComputeCrateFingerprint_WalksAllTrackedRoots(t *testing.T) {
	root := t.TempDir()
	write(t, root, "Cargo.toml", "[package]\n")
	write(t, root, "src/lib.rs", "// lib\n")

	base, _ := runner.ComputeCrateFingerprint(root)

	write(t, root, "examples/x.rs", "// x\n")
	withEx, _ := runner.ComputeCrateFingerprint(root)
	if base == withEx {
		t.Error("examples/ change not picked up")
	}

	write(t, root, "benches/y.rs", "// y\n")
	withBen, _ := runner.ComputeCrateFingerprint(root)
	if withEx == withBen {
		t.Error("benches/ change not picked up")
	}

	write(t, root, "tests/z.rs", "// z\n")
	withTests, _ := runner.ComputeCrateFingerprint(root)
	if withBen == withTests {
		t.Error("tests/ change not picked up")
	}
}

func TestComputeCrateFingerprint_ExcludesTargetDir(t *testing.T) {
	root := t.TempDir()
	write(t, root, "Cargo.toml", "[package]\n")
	write(t, root, "src/lib.rs", "// lib\n")

	before, _ := runner.ComputeCrateFingerprint(root)
	write(t, root, "target/debug/some-output.bin", "binary contents\n")
	after, _ := runner.ComputeCrateFingerprint(root)
	if before != after {
		t.Errorf("target/ change leaked into fingerprint: %q vs %q", before, after)
	}
}

func TestComputeCrateFingerprint_UnrelatedRsChangeInvalidates(t *testing.T) {
	root := t.TempDir()
	now := time.Now()
	write(t, root, "Cargo.toml", "[package]\n")
	write(t, root, "src/a.rs", "// a\n")
	bPath := write(t, root, "src/b.rs", "// b\n")
	touch(t, bPath, now)

	before, _ := runner.ComputeCrateFingerprint(root)
	// Modify b.rs content + mtime; a.rs untouched.
	if err := os.WriteFile(bPath, []byte("// b changed\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	touch(t, bPath, now.Add(2*time.Second))
	after, _ := runner.ComputeCrateFingerprint(root)
	if before == after {
		t.Error("unrelated src/b.rs change did not invalidate fingerprint")
	}
}

func TestComputeCrateFingerprint_EmptyRoot_ReturnsStableFingerprint(t *testing.T) {
	root := t.TempDir()
	fp, err := runner.ComputeCrateFingerprint(root)
	if err != nil {
		t.Fatal(err)
	}
	if len(fp) != 64 {
		t.Errorf("expected 64-char hex even for empty root, got %q", fp)
	}
}
