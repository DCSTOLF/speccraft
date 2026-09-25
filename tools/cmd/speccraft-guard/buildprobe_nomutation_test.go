package main

// Spec 0048 T18 (AC9) — the probe never mutates the working tree.
//
// This is the property that makes the whole feature safe to run inside a
// PreToolUse hook. The probe compiles content that does not exist on disk, so if it
// could write anything into the repo it would be editing the author's tree behind
// their back, before their own edit had even been applied.
//
// Checked by evidence rather than by assertion: a recursive snapshot of the entire
// root (path → sha256 + mode) taken before and after, across ALL THREE outcomes,
// plus a direct check that every scratch path the probe uses resolves outside the
// root. That last check is why buildProbeResult carries OverlayJSON,
// OverlayContent and GoCache at all — they are not decoration.

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// snapshotTree records relpath → "sha256:mode" for every file under root.
func snapshotTree(t *testing.T, root string) map[string]string {
	t.Helper()
	out := map[string]string{}
	err := filepath.Walk(root, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		rel, relErr := filepath.Rel(root, path)
		if relErr != nil {
			return relErr
		}
		if info.IsDir() {
			out[rel+"/"] = "dir:" + info.Mode().String()
			return nil
		}
		b, readErr := os.ReadFile(path)
		if readErr != nil {
			return readErr
		}
		sum := sha256.Sum256(b)
		out[rel] = hex.EncodeToString(sum[:]) + ":" + info.Mode().String()
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
	return out
}

func diffSnapshots(t *testing.T, before, after map[string]string) {
	t.Helper()
	for k, v := range before {
		av, ok := after[k]
		if !ok {
			t.Errorf("the probe REMOVED %s", k)
			continue
		}
		if av != v {
			t.Errorf("the probe MODIFIED %s:\n before %s\n after  %s", k, v, av)
		}
	}
	for k := range after {
		if _, ok := before[k]; !ok {
			t.Errorf("the probe ADDED %s", k)
		}
	}
}

// goProbeFixture is a real, minimal module the REAL prober can compile.
func goProbeFixture(t *testing.T, broken bool) (root, prodFile string) {
	t.Helper()
	root = t.TempDir()
	if err := os.WriteFile(filepath.Join(root, "go.mod"), []byte("module probe\n\ngo 1.22\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	dir := filepath.Join(root, "pkg")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	prodFile = filepath.Join(dir, "foo.go")
	body := "package pkg\n\nfunc Foo() int { return 1 }\n"
	if broken {
		body = "package pkg\n\nfunc Foo() int { return missingHelper() }\n"
	}
	if err := os.WriteFile(prodFile, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "foo_test.go"),
		[]byte("package pkg\n\nimport \"testing\"\n\nfunc TestFoo(t *testing.T) {}\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	return root, prodFile
}

// AC9 across all three outcomes. The infrastructure-failure case uses an
// already-cancelled context, which is the one path where the probe gives up
// partway — precisely where a stray temp file or a written binary would show up.
func Test_BuildProbe_NeverMutatesWorkingTree(t *testing.T) {
	for _, tc := range []struct {
		name      string
		broken    bool
		post      string
		cancelled bool
	}{
		{"clean overlay", true, "package pkg\n\nfunc Foo() int { return 1 }\n", false},
		{"still-broken overlay", true, "package pkg\n\nfunc Foo() int { return missingHelper() + 1 }\n", false},
		{"infrastructure failure", true, "package pkg\n\nfunc Foo() int { return 1 }\n", true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			root, prodFile := goProbeFixture(t, tc.broken)
			before := snapshotTree(t, root)

			ctx := context.Background()
			if tc.cancelled {
				var cancel context.CancelFunc
				ctx, cancel = context.WithCancel(ctx)
				cancel() // force the probe to fail before it can finish
			}

			_, _ = goBuildProber{}.Probe(ctx, buildProbeRequest{
				ModuleRoot:  root,
				RealPath:    prodFile,
				PostContent: tc.post,
			})

			diffSnapshots(t, before, snapshotTree(t, root))
		})
	}
}

// AC9 — every scratch path resolves OUTSIDE the repo root. `-o <tmpdir>` is the
// load-bearing part: `go build ./...` discards binaries for a multi-package
// pattern, but writes the executable into the CURRENT DIRECTORY when the module
// has exactly one `main` package, which would drop a binary into the author's tree.
func Test_BuildProbe_OverlayAndCacheResolveOutsideRepoRoot(t *testing.T) {
	root, prodFile := goProbeFixture(t, false)

	res, err := goBuildProber{}.Probe(context.Background(), buildProbeRequest{
		ModuleRoot:  root,
		RealPath:    prodFile,
		PostContent: "package pkg\n\nfunc Foo() int { return 2 }\n",
	})
	if err != nil {
		t.Fatalf("probe: %v", err)
	}
	if !res.Clean {
		t.Fatalf("a valid module must probe clean; output:\n%s", res.Output)
	}

	for name, p := range map[string]string{
		"OverlayJSON":    res.OverlayJSON,
		"OverlayContent": res.OverlayContent,
		"GoCache":        res.GoCache,
	} {
		if p == "" {
			t.Errorf("%s must be reported so this assertion is possible at all", name)
			continue
		}
		rel, relErr := filepath.Rel(root, p)
		inside := relErr == nil && rel != ".." && !strings.HasPrefix(rel, ".."+string(filepath.Separator))
		if inside {
			t.Errorf("%s resolves INSIDE the repo root (%s); the probe must never write there", name, rel)
		}
	}
}

// A single-main module is the case where `go build` would otherwise write into the
// CWD. Pinned separately because the failure mode is silent: a stray binary in the
// author's tree, with the probe still reporting clean.
func Test_BuildProbe_SingleMainModule_WritesNoBinaryIntoTree(t *testing.T) {
	root := t.TempDir()
	if err := os.WriteFile(filepath.Join(root, "go.mod"), []byte("module probe\n\ngo 1.22\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	main := filepath.Join(root, "main.go")
	if err := os.WriteFile(main, []byte("package main\n\nfunc main() {}\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	before := snapshotTree(t, root)

	res, err := goBuildProber{}.Probe(context.Background(), buildProbeRequest{
		ModuleRoot:  root,
		RealPath:    main,
		PostContent: "package main\n\nfunc main() { _ = 1 }\n",
	})
	if err != nil {
		t.Fatalf("probe: %v", err)
	}
	if !res.Clean {
		t.Fatalf("this module should probe clean; output:\n%s", res.Output)
	}
	diffSnapshots(t, before, snapshotTree(t, root))
}
