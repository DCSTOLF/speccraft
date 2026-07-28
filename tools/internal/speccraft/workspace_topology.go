package speccraft

import (
	"os"
	"path/filepath"
	"strings"
)

// Workspace topology foundation (spec 0037): FindWorkspaceRoot,
// Member/ParseWorkspaceMembers, and ReadFrontmatterField.

// wsError is a local string error type so the parser reports parse errors
// without pulling in a fresh errors/fmt import on the guarded hot path.
type wsError string

func (e wsError) Error() string { return string(e) }

// FindWorkspaceRoot returns the nearest ancestor of dir whose .speccraft/ config
// is kind = "workspace"; when none exists it returns exactly FindRoot(dir)
// (value and error). A lone repo is thus "a workspace of one". Consumed only by
// the arch:* commands and the conductor — never by hooks or the guard (spec 0037
// AC2/AC5).
func FindWorkspaceRoot(dir string) (string, error) {
	start := dir
	if start == "" {
		wd, err := os.Getwd()
		if err != nil {
			return "", err
		}
		start = wd
	}
	d, _ := filepath.Abs(start)
	for {
		if _, err := os.Stat(filepath.Join(d, ".speccraft")); err == nil {
			// Non-strict read: a malformed kind coerces to repo, so it is not
			// treated as a workspace.
			if ReadConfig(d).Kind == "workspace" {
				return d, nil
			}
		}
		parent := filepath.Dir(d)
		if parent == d {
			break
		}
		d = parent
	}
	// No workspace ancestor: fall back to FindRoot for exact value+error parity.
	return FindRoot(dir)
}

// Member is one entry of a workspace.yml members: list. Present records whether
// the path resolves on disk; a missing member is preserved (never dropped) so
// Spec B can render it as a blocked overlay (spec 0037 AC3).
type Member struct {
	Path    string
	Present bool
}

// ParseWorkspaceMembers parses the constrained workspace.yml subset at path and
// returns every listed member with a Present flag (authoritative membership —
// a listed-but-missing path is preserved, never dropped). The accepted grammar
// (spec 0037): `members:` at column 0; each entry exactly `␣␣- path: <value>`;
// a trailing ` #…` inline comment is stripped, then the value is trimmed; the
// value is bare (no interior whitespace, no unescaped `#`) or double-quoted
// (literal); it must be relative (a leading `/` is rejected). Blank lines and
// full-line `#` comments are ignored. Anything outside this subset — another
// top-level key, an entry bearing extra keys, a duplicate `members:`, flow
// style — is a parse error. An empty `members:` is valid (empty set).
func ParseWorkspaceMembers(path string) ([]Member, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	baseDir := filepath.Dir(path)

	members := []Member{}
	sawMembers := false
	const entryPrefix = "  - path:"

	for _, raw := range strings.Split(string(data), "\n") {
		line := strings.TrimRight(raw, "\r")
		trimmed := strings.TrimSpace(line)
		if trimmed == "" || strings.HasPrefix(trimmed, "#") {
			continue // blank / full-line comment
		}

		// Top-level (column 0) line.
		if !strings.HasPrefix(line, " ") && !strings.HasPrefix(line, "\t") {
			if trimmed == "members:" {
				if sawMembers {
					return nil, wsError("workspace.yml: duplicate members: key")
				}
				sawMembers = true
				continue
			}
			return nil, wsError("workspace.yml: unsupported top-level construct: " + trimmed)
		}

		// Indented line — must be a member entry under members:.
		if !sawMembers {
			return nil, wsError("workspace.yml: indented line before members:")
		}
		if !strings.HasPrefix(line, entryPrefix) {
			return nil, wsError("workspace.yml: malformed member entry: " + trimmed)
		}
		value, perr := parsePathValue(line[len(entryPrefix):])
		if perr != nil {
			return nil, perr
		}
		present := false
		if _, statErr := os.Stat(filepath.Join(baseDir, value)); statErr == nil {
			present = true
		}
		members = append(members, Member{Path: value, Present: present})
	}

	if !sawMembers {
		return nil, wsError("workspace.yml: missing members: key")
	}
	return members, nil
}

// parsePathValue extracts the path value from the text after "  - path:".
func parsePathValue(rest string) (string, error) {
	lead := strings.TrimLeft(rest, " ")
	// Double-quoted: literal between the quotes (no escape processing).
	if strings.HasPrefix(lead, "\"") {
		end := strings.Index(lead[1:], "\"")
		if end < 0 {
			return "", wsError("workspace.yml: unterminated quoted path")
		}
		val := lead[1 : 1+end]
		tail := strings.TrimLeft(lead[2+end:], " ")
		if tail != "" && !strings.HasPrefix(tail, "#") {
			return "", wsError("workspace.yml: unexpected text after quoted path")
		}
		return validateRelative(val)
	}
	// Bare: strip a trailing " #…" inline comment, then trim.
	s := rest
	if i := strings.Index(s, " #"); i >= 0 {
		s = s[:i]
	}
	val := strings.TrimSpace(s)
	if val == "" {
		return "", wsError("workspace.yml: empty path value")
	}
	if strings.ContainsAny(val, " \t") {
		return "", wsError("workspace.yml: bare path with interior whitespace (quote it): " + val)
	}
	if strings.Contains(val, "#") {
		return "", wsError("workspace.yml: bare path with unescaped '#' (quote it): " + val)
	}
	return validateRelative(val)
}

func validateRelative(val string) (string, error) {
	if val == "" {
		return "", wsError("workspace.yml: empty path value")
	}
	if strings.HasPrefix(val, "/") {
		return "", wsError("workspace.yml: absolute path not allowed (must be relative): " + val)
	}
	return val, nil
}

// ReadFrontmatterField reads a single frontmatter field from a spec.md via the
// shared spec-0036 frontmatterValue/parseFrontmatterBlock grammar (no second
// parser). Returns (value, found, error); a missing/unreadable file is the
// error, independent of whether the key is present.
func ReadFrontmatterField(specMd, key string) (string, bool, error) {
	b, err := os.ReadFile(specMd)
	if err != nil {
		return "", false, err
	}
	v, ok := frontmatterValue(b, key)
	return v, ok, nil
}
