package runner

import (
	"regexp"
	"strings"
)

// libtestLine matches a single line of libtest's text output:
//
//	test <fully-qualified-name> ... <status>
//
// where <status> is one of `ok`, `FAILED`, or `ignored`. Other libtest
// suffixes (e.g. `bench`) are not part of the spec and are ignored.
var libtestLine = regexp.MustCompile(`^test (.+) \.\.\. (ok|FAILED|ignored)$`)

// parseLibtestText extracts TestRecord entries from `cargo test`'s libtest
// text output. cratePrefixToStrip, if non-empty, is removed from the
// leading `<crate>::` of each TestName so static-discovery IDs and
// runner IDs compare in the same form (spec 0005 §What.3).
func parseLibtestText(stdout, cratePrefixToStrip string) []TestRecord {
	var recs []TestRecord
	prefix := ""
	if cratePrefixToStrip != "" {
		prefix = cratePrefixToStrip + "::"
	}
	for _, line := range strings.Split(stdout, "\n") {
		m := libtestLine.FindStringSubmatch(strings.TrimSpace(line))
		if m == nil {
			continue
		}
		name := m[1]
		if prefix != "" && strings.HasPrefix(name, prefix) {
			name = strings.TrimPrefix(name, prefix)
		}
		var status string
		switch m[2] {
		case "ok":
			status = "passed"
		case "FAILED":
			status = "failed"
		case "ignored":
			status = "ignored"
		}
		recs = append(recs, TestRecord{TestName: name, Status: status})
	}
	return recs
}
