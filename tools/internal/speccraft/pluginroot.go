package speccraft

// Plugin-root resolution (spec 0030).
//
// speccraft command docs run bash that must locate the plugin's own install
// directory to source *.lib.sh and reach bin/ and templates/. They cannot rely
// on $CLAUDE_PLUGIN_ROOT: that variable is only contractually exported to hook
// subprocesses, not to the bash a slash command runs, and in the field it has
// resolved to the plugins *parent* directory. This resolver lets the docs call
// `speccraft-state plugin-root` instead (speccraft-state is reliably on PATH via
// the plugin's bin/).
//
// The core, ResolvePluginRootFrom, is pure: it takes the two env values and the
// executable path as arguments so the precedence table and the symlink rule are
// table-testable without touching process state. ResolvePluginRoot is the thin
// wrapper that reads the environment and os.Executable().

import (
	"fmt"
	"os"
	"path/filepath"
)

// IsValidPluginRoot reports whether dir is a speccraft plugin root: it must
// contain the plugin manifest (.claude-plugin/plugin.json) AND the bin/,
// commands/, and templates/ directories. The manifest is the identity anchor —
// a directory that merely has the three subdirs is not accepted.
func IsValidPluginRoot(dir string) bool {
	if dir == "" {
		return false
	}
	if fi, err := os.Stat(filepath.Join(dir, ".claude-plugin", "plugin.json")); err != nil || fi.IsDir() {
		return false
	}
	for _, sub := range []string{"bin", "commands", "templates"} {
		if fi, err := os.Stat(filepath.Join(dir, sub)); err != nil || !fi.IsDir() {
			return false
		}
	}
	return true
}

// ascendToValidRoot walks up from dir (inclusive) to the filesystem root,
// returning the nearest ancestor that satisfies IsValidPluginRoot, or "" if none.
func ascendToValidRoot(dir string) string {
	for {
		if IsValidPluginRoot(dir) {
			return dir
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			return ""
		}
		dir = parent
	}
}

// ResolvePluginRootFrom resolves the plugin root from injected inputs following
// a fixed precedence:
//
//  1. speccraftRoot ($SPECCRAFT_PLUGIN_ROOT) — an explicit override. If set it
//     MUST validate; an invalid override is a hard error (never silently ignored).
//  2. claudeRoot ($CLAUDE_PLUGIN_ROOT) — used only if it validates. An invalid
//     value (e.g. the plugins parent, which has no manifest) is skipped, not fatal.
//  3. self-derivation — EvalSymlinks(exePath), then ascend to the nearest
//     validating ancestor. Handles both <root>/bin/ and <root>/tools/bin/ layouts.
//  4. otherwise, an error naming each source tried.
func ResolvePluginRootFrom(speccraftRoot, claudeRoot, exePath string) (string, error) {
	// 1. Explicit override: validate or hard-error.
	if speccraftRoot != "" {
		if IsValidPluginRoot(speccraftRoot) {
			return speccraftRoot, nil
		}
		return "", fmt.Errorf("SPECCRAFT_PLUGIN_ROOT=%q is not a valid plugin root (needs .claude-plugin/plugin.json, bin/, commands/, templates/)", speccraftRoot)
	}

	// 2. CLAUDE_PLUGIN_ROOT: use only if it validates; otherwise fall through.
	if claudeRoot != "" && IsValidPluginRoot(claudeRoot) {
		return claudeRoot, nil
	}

	// 3. Self-derivation from the invoked binary's own location.
	if exePath != "" {
		resolved := exePath
		if real, err := filepath.EvalSymlinks(exePath); err == nil {
			resolved = real
		}
		if root := ascendToValidRoot(filepath.Dir(resolved)); root != "" {
			return root, nil
		}
	}

	// 4. Nothing resolved — name every source tried.
	return "", fmt.Errorf("could not resolve the speccraft plugin root: "+
		"SPECCRAFT_PLUGIN_ROOT unset, CLAUDE_PLUGIN_ROOT=%q did not validate, "+
		"and self-derivation from %q found no ancestor containing .claude-plugin/plugin.json + bin/ + commands/ + templates/",
		claudeRoot, exePath)
}

// ResolvePluginRoot is the I/O wrapper over ResolvePluginRootFrom: it reads the
// two environment variables and os.Executable(), then delegates.
func ResolvePluginRoot() (string, error) {
	exe, err := os.Executable()
	if err != nil {
		exe = ""
	}
	return ResolvePluginRootFrom(
		os.Getenv("SPECCRAFT_PLUGIN_ROOT"),
		os.Getenv("CLAUDE_PLUGIN_ROOT"),
		exe,
	)
}
