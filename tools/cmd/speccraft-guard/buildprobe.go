package main

// Spec 0048 — the build probe behind build-repair mode.
//
// WHAT IT ANSWERS: "would the PROPOSED edit leave this module buildable?" The
// red-check's rule that a build failure is not a valid RED is correct, but when
// the break is in production code that rule blocks the repair too. The probe
// distinguishes the edit that FIXES the build (allow silently, end repair mode)
// from an edit that leaves it broken (allow, but record it against a bounded
// budget first).
//
// It never touches the working tree. The post-edit content is supplied to the Go
// toolchain through `-overlay`, which maps a real path to a temp file, so the
// probe compiles content that exists nowhere on disk.
//
// TWO COMMANDS, not one — plan correction C1, and the reason matters:
//
//	go build -overlay … ./...              # compiles non-test files
//	go test  -overlay … -run '^$' ./...    # compiles TEST files, runs nothing
//
// `go build ./...` does not compile `_test.go` files at all. A probe using only
// `go build` would call an overlay CLEAN while a sibling test file was
// unbuildable — allowing the edit silently and leaving the tree untestable, which
// is the hole the review spent three rounds closing. The overlay is "clean" only
// if BOTH commands exit zero.
//
// Three invocation details that are load-bearing rather than cosmetic:
//
//   - `-o <tmpdir>` is mandatory. `go build ./...` discards binaries when the
//     pattern matches several packages, but writes the executable into the CURRENT
//     DIRECTORY when the module has exactly one `main` package. Directing output
//     outside the repo makes "the probe never mutates the working tree" true by
//     construction rather than by luck.
//   - `GOFLAGS=-mod=readonly` guarantees the probe can never rewrite go.mod/go.sum.
//   - `GOCACHE` is redirected to a temp dir so a probe cannot poison or be poisoned
//     by the caller's build cache.
//
// No build-tag split, deliberately: `go build -overlay` is portable everywhere Go
// runs. Spec 0047's process-group problem (a grandchild holding the captured pipe
// hangs Wait after a timeout) is real here too, and is solved portably with
// exec.CommandContext + cmd.WaitDelay rather than with unix-only Setpgid. The
// tasks_predicate.go/_other.go pair is NOT mirrored.

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"github.com/dcstolf/speccraft/tools/internal/speccraft"
)

// buildProbeDefaultTimeout bounds a probe so a pathological module cannot wedge
// the hook. Mirrors spec 0047's tasksVerifyTimeout and spec 0045's
// parseLockTimeout.
const buildProbeDefaultTimeout = 30 * time.Second

// buildProbeRequest is one probe: compile <ModuleRoot> as if <RealPath> held
// <PostContent>.
type buildProbeRequest struct {
	ModuleRoot  string
	RealPath    string
	PostContent string
}

// buildProbeResult reports whether the overlay builds, and where the probe put
// its scratch files.
//
// The three path fields are not decoration: AC9 asserts they all resolve OUTSIDE
// the repository root, which is how "the probe never mutates the working tree" is
// checked rather than asserted.
type buildProbeResult struct {
	Clean          bool
	Output         string
	OverlayJSON    string
	OverlayContent string
	GoCache        string
}

// BuildProber decides whether a proposed edit leaves a module buildable.
type BuildProber interface {
	Probe(ctx context.Context, req buildProbeRequest) (buildProbeResult, error)
}

// buildProbeTimeout parses SPECCRAFT_BUILD_PROBE_TIMEOUT. Unset, empty, invalid,
// zero and negative all fall back to the default — a malformed value must not
// silently disable the bound.
func buildProbeTimeout(raw string) time.Duration {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return buildProbeDefaultTimeout
	}
	d, err := time.ParseDuration(raw)
	if err != nil || d <= 0 {
		return buildProbeDefaultTimeout
	}
	return d
}

// moduleRootFor walks up from absPath to the nearest ancestor holding a go.mod,
// bounded by repoRoot. Returns ok == false when there is none — a file outside any
// module cannot be probed, and the caller must then fall back to blocking.
func moduleRootFor(absPath, repoRoot string) (string, bool) {
	dir := filepath.Dir(filepath.Clean(absPath))
	root := filepath.Clean(repoRoot)
	for {
		if _, err := os.Stat(filepath.Join(dir, "go.mod")); err == nil {
			return dir, true
		}
		if dir == root {
			return "", false
		}
		parent := filepath.Dir(dir)
		if parent == dir || !strings.HasPrefix(dir, root) {
			return "", false
		}
		dir = parent
	}
}

// goBuildProber is the only BuildProber implementation.
type goBuildProber struct{}

// Probe writes the post-edit content to a temp file, points an overlay at it, and
// runs the two compile commands. Clean iff both exit zero.
func (goBuildProber) Probe(ctx context.Context, req buildProbeRequest) (buildProbeResult, error) {
	tmp, err := os.MkdirTemp("", "speccraft-build-probe-")
	if err != nil {
		return buildProbeResult{}, fmt.Errorf("build probe: temp dir: %w", err)
	}
	defer os.RemoveAll(tmp)

	// The overlay's replacement content, keyed by the REAL path.
	contentPath := filepath.Join(tmp, "overlay-content"+filepath.Ext(req.RealPath))
	if err := os.WriteFile(contentPath, []byte(req.PostContent), 0o644); err != nil {
		return buildProbeResult{}, fmt.Errorf("build probe: overlay content: %w", err)
	}
	overlay := map[string]map[string]string{
		"Replace": {filepath.Clean(req.RealPath): contentPath},
	}
	overlayJSON, err := json.Marshal(overlay)
	if err != nil {
		return buildProbeResult{}, fmt.Errorf("build probe: overlay json: %w", err)
	}
	overlayPath := filepath.Join(tmp, "overlay.json")
	if err := os.WriteFile(overlayPath, overlayJSON, 0o644); err != nil {
		return buildProbeResult{}, fmt.Errorf("build probe: overlay file: %w", err)
	}

	goCache := filepath.Join(tmp, "gocache")
	outDir := filepath.Join(tmp, "out")
	if err := os.MkdirAll(outDir, 0o755); err != nil {
		return buildProbeResult{}, fmt.Errorf("build probe: out dir: %w", err)
	}

	res := buildProbeResult{
		OverlayJSON:    overlayPath,
		OverlayContent: contentPath,
		GoCache:        goCache,
	}

	// Both commands must pass. `go build` alone would miss a broken _test.go.
	cmds := [][]string{
		{"build", "-overlay", overlayPath, "-o", outDir, "./..."},
		{"test", "-overlay", overlayPath, "-run", "^$", "-count=1", "./..."},
	}
	var combined strings.Builder
	for _, args := range cmds {
		out, runErr := runBuildProbe(ctx, req.ModuleRoot, goCache, args)
		combined.WriteString(out)
		if runErr != nil {
			// A context error is a PROBE failure (the caller must block and say
			// why), not evidence about the module.
			if ctx.Err() != nil {
				res.Output = combined.String()
				return res, fmt.Errorf("build probe: %w", ctx.Err())
			}
			// Non-zero exit: the overlay does not build. That is a RESULT.
			res.Clean = false
			res.Output = combined.String()
			return res, nil
		}
	}
	res.Clean = true
	res.Output = combined.String()
	return res, nil
}

// buildRepairBranch is what replaces the flat "build failed → block" refusal.
//
// Returning nil means ALLOW. The four outcomes, in the order they are decided:
//
//  1. No prober for this language → today's exact error, unchanged (AC7). Repair
//     mode is not extended to a language whose probe has not been designed.
//  2. The probe itself could not complete → BLOCK, naming both the original build
//     error and the probe failure. A probe that cannot answer must not be read as
//     "clean"; that would admit edits on no evidence at all.
//  3. Overlay builds clean → the edit REPAIRS the break. Close repair mode and
//     allow silently.
//  4. Overlay still broken → allow, but RECORD first. Recording before allowing is
//     what makes an admitted-but-unlogged edit impossible; if the record fails, or
//     the session's budget is exhausted, the edit is blocked.
func buildRepairBranch(absPath, root string, cfg speccraft.SpeccraftConfig, lang string, d deps, buildErr string) error {
	buildErr = strings.TrimSpace(buildErr)

	if d.proberForLang == nil {
		return buildFailedBlockError(buildErr, absPath)
	}
	prober, ok := d.proberForLang(lang, cfg)
	if !ok {
		return buildFailedBlockError(buildErr, absPath)
	}

	moduleRoot, ok := moduleRootFor(absPath, root)
	if !ok {
		// Outside any module there is nothing to overlay, so there is no evidence
		// either way — fall back to blocking rather than guessing.
		return buildFailedBlockError(buildErr, absPath)
	}

	preBytes, _ := os.ReadFile(absPath)
	post := applyEdit(string(preBytes), d.toolInput)

	ctx, cancel := context.WithTimeout(context.Background(),
		buildProbeTimeout(os.Getenv("SPECCRAFT_BUILD_PROBE_TIMEOUT")))
	defer cancel()

	res, probeErr := prober.Probe(ctx, buildProbeRequest{
		ModuleRoot:  moduleRoot,
		RealPath:    absPath,
		PostContent: post,
	})
	if probeErr != nil {
		return fmt.Errorf(
			"red-check: build/collection failed (not a valid RED state):\n%s\n\n"+
				"speccraft could not determine whether this edit repairs the build:\n  %v\n\n"+
				"Fix the build error so the just-added test can run and fail.",
			buildErr, probeErr)
	}

	if res.Clean {
		// The edit repairs the module. End repair mode; the log is retained so a
		// clean probe cannot refund budget already spent.
		if err := speccraft.ClearBuildRepairAttestation(root); err != nil {
			return fmt.Errorf("speccraft-guard: could not close build-repair mode: %w", err)
		}
		return nil
	}

	// Still broken: a legitimate mid-repair step. Record it, then allow.
	if _, err := speccraft.RecordBuildRepair(root, absPath, probeErrorText(buildErr, res.Output)); err != nil {
		if errors.Is(err, speccraft.ErrBuildRepairBudgetExhausted) {
			return fmt.Errorf(
				"red-check: build/collection failed, and this session's build-repair budget is spent:\n  %v\n\n"+
					"speccraft admits a bounded number of edits while the build is broken so a\n"+
					"multi-step repair is possible; that bound is now reached.\n\n"+
					"Use /speccraft:spec:override \"<reason>\" to continue, and record why.",
				err)
		}
		return fmt.Errorf("speccraft-guard: could not record this build-repair edit: %w", err)
	}
	return nil
}

// buildFailedBlockError is spec 0018's original refusal, kept byte-identical so
// AC7's "unsupported language is unchanged" is true by construction rather than by
// a second copy that could drift.
func buildFailedBlockError(buildErr, _ string) error {
	return fmt.Errorf(
		"red-check: build/collection failed (not a valid RED state):\n%s\n\n"+
			"Fix the build error so the just-added test can run and fail.",
		buildErr)
}

// probeErrorText prefers the probe's own output — it describes the state the
// overlay is actually in — and falls back to the adapter's stderr.
func probeErrorText(buildErr, probeOutput string) string {
	if s := strings.TrimSpace(probeOutput); s != "" {
		return s
	}
	return buildErr
}

// runBuildProbe is the single place a probe subprocess is started — the call site
// AC16's source-scan counts. Returns combined output, and a non-nil error when the
// command did not exit zero.
func runBuildProbe(ctx context.Context, moduleRoot, goCache string, args []string) (string, error) {
	cmd := exec.CommandContext(ctx, "go", args...)
	cmd.Dir = moduleRoot
	cmd.Env = append(os.Environ(),
		"GOCACHE="+goCache,
		// Guarantees the probe cannot rewrite go.mod or go.sum.
		"GOFLAGS=-mod=readonly",
	)
	// WaitDelay bounds the wait after ctx is cancelled even if a grandchild still
	// holds the captured pipe — spec 0047's hang, solved portably rather than with
	// a unix-only process group.
	cmd.WaitDelay = 5 * time.Second
	out, err := cmd.CombinedOutput()
	return string(out), err
}
