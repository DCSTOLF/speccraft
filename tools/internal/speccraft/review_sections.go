package speccraft

// Spec 0035 (AC5) — the pure section splitter + diff renderer behind
// changed_sections. A spec.md is parsed into: frontmatter (between the first two
// `---` fences), preamble (everything up to the first `## ` heading — the H1 and
// any rev comments), and level-2 sections. Sections are keyed by
// (trimmed heading text, 1-based ordinal among identical headings) so duplicate
// headings are individually addressable and a `## (frontmatter)` heading is a
// kind:"section" entry that never aliases the reserved kind:"frontmatter".

import (
	"strconv"
	"strings"
)

type docSection struct {
	heading string
	ordinal int
	body    string
}

type parsedSpecDoc struct {
	frontmatter string
	preamble    string
	sections    []docSection
}

// isL2Heading reports whether a line opens a level-2 (`## `) section. `### ` and
// deeper are body, not section boundaries.
func isL2Heading(line string) bool {
	return strings.HasPrefix(line, "## ")
}

func parseSpecDoc(content string) parsedSpecDoc {
	lines := strings.Split(content, "\n")
	i := 0
	var fm strings.Builder
	if len(lines) > 0 && strings.TrimRight(lines[0], "\r") == "---" {
		i = 1
		for i < len(lines) {
			if strings.TrimRight(lines[i], "\r") == "---" {
				i++ // consume closing fence
				break
			}
			fm.WriteString(lines[i])
			fm.WriteByte('\n')
			i++
		}
	}
	var pre strings.Builder
	for i < len(lines) && !isL2Heading(lines[i]) {
		pre.WriteString(lines[i])
		pre.WriteByte('\n')
		i++
	}
	var sections []docSection
	counts := map[string]int{}
	for i < len(lines) {
		if !isL2Heading(lines[i]) {
			i++
			continue
		}
		heading := strings.TrimSpace(strings.TrimPrefix(lines[i], "## "))
		i++
		var body strings.Builder
		for i < len(lines) && !isL2Heading(lines[i]) {
			body.WriteString(lines[i])
			body.WriteByte('\n')
			i++
		}
		counts[heading]++
		sections = append(sections, docSection{heading: heading, ordinal: counts[heading], body: body.String()})
	}
	return parsedSpecDoc{frontmatter: fm.String(), preamble: pre.String(), sections: sections}
}

// renderDiff produces a compact, deterministic textual summary of the changed
// anchors for the envelope's `diff` field and the re-review brief's {{DIFF}}.
func renderDiff(cs []ChangedSection) string {
	var b strings.Builder
	for _, c := range cs {
		switch c.Kind {
		case "frontmatter", "preamble":
			b.WriteString("* " + c.Kind + "\n")
		case "section":
			sym := "~"
			switch c.Side {
			case "added":
				sym = "+"
			case "removed":
				sym = "-"
			}
			b.WriteString(sym + " ## " + c.Heading + " (#" + strconv.Itoa(c.Ordinal) + ")\n")
		}
	}
	return b.String()
}
