package speccraft

// Spec 0035 T16 (AC5) — the changed_sections determinism rule. Table-driven over
// diffSections(old,new): structured {kind,heading,ordinal,side} anchors; ordinal
// document-side (removed=old idx, added=new idx, modified=shared k); byte-
// identical bodies NEVER emitted; rename = removed+added; duplicates distinguished
// by ordinal; heading keys whitespace-trimmed; reserved (frontmatter)/(preamble)
// never aliased by a literal `## (frontmatter)` heading. RED against the T9
// skeleton (returns no anchors).

import (
	"sort"
	"strconv"
	"strings"
	"testing"
)

func csKey(c ChangedSection) string {
	return strings.Join([]string{c.Kind, c.Heading, strconv.Itoa(c.Ordinal), c.Side}, "|")
}

func csSet(cs []ChangedSection) []string {
	out := make([]string, 0, len(cs))
	for _, c := range cs {
		out = append(out, csKey(c))
	}
	sort.Strings(out)
	return out
}

func Test_DiffSections_UniqueModify_EmitsModified(t *testing.T) {
	_, got := diffSections([]byte("# T\n\n## Why\n\nA\n"), []byte("# T\n\n## Why\n\nB\n"))
	if len(got) != 1 || got[0].Kind != "section" || got[0].Heading != "Why" || got[0].Side != "modified" {
		t.Errorf("got %v, want one modified section Why", got)
	}
}

func Test_ChangedSections(t *testing.T) {
	cases := []struct {
		name string
		old  string
		new  string
		want []ChangedSection
	}{
		{
			name: "UniqueHeadingModify",
			old:  "# T\n\n## Why\n\nA\n",
			new:  "# T\n\n## Why\n\nB\n",
			want: []ChangedSection{{Kind: "section", Heading: "Why", Ordinal: 1, Side: "modified"}},
		},
		{
			name: "FrontmatterChange",
			old:  "---\nid: \"1\"\n---\n\n# T\n\n## Why\n\nx\n",
			new:  "---\nid: \"2\"\n---\n\n# T\n\n## Why\n\nx\n",
			want: []ChangedSection{{Kind: "frontmatter", Side: "modified"}},
		},
		{
			name: "PreambleChange",
			old:  "# Title One\n\n## Why\n\nx\n",
			new:  "# Title Two\n\n## Why\n\nx\n",
			want: []ChangedSection{{Kind: "preamble", Side: "modified"}},
		},
		{
			name: "Rename_RemovedPlusAdded",
			old:  "# T\n\n## Why\n\nx\n",
			new:  "# T\n\n## Motivation\n\nx\n",
			want: []ChangedSection{
				{Kind: "section", Heading: "Why", Ordinal: 1, Side: "removed"},
				{Kind: "section", Heading: "Motivation", Ordinal: 1, Side: "added"},
			},
		},
		{
			name: "DuplicateHeading_OrdinalDistinguishes",
			old:  "# T\n\n## Note\n\nA\n\n## Note\n\nB\n",
			new:  "# T\n\n## Note\n\nA\n\n## Note\n\nC\n",
			want: []ChangedSection{{Kind: "section", Heading: "Note", Ordinal: 2, Side: "modified"}},
		},
		{
			name: "ByteIdenticalBody_NeverEmitted_UnderNeighbourChange",
			old:  "# T\n\n## A\n\nx\n\n## B\n\ny\n",
			new:  "# T\n\n## A\n\nCHANGED\n\n## B\n\ny\n",
			want: []ChangedSection{{Kind: "section", Heading: "A", Ordinal: 1, Side: "modified"}},
		},
		{
			name: "AddedSide_NewDocumentOrdinal",
			old:  "# T\n\n## A\n\nx\n",
			new:  "# T\n\n## A\n\nx\n\n## B\n\nz\n",
			want: []ChangedSection{{Kind: "section", Heading: "B", Ordinal: 1, Side: "added"}},
		},
		{
			name: "RemovedSide_OldDocumentOrdinal",
			old:  "# T\n\n## A\n\nx\n\n## B\n\nz\n",
			new:  "# T\n\n## A\n\nx\n",
			want: []ChangedSection{{Kind: "section", Heading: "B", Ordinal: 1, Side: "removed"}},
		},
		{
			name: "LiteralFrontmatterHeading_IsKindSection_NoAlias",
			old:  "# T\n\n## (frontmatter)\n\nx\n",
			new:  "# T\n\n## (frontmatter)\n\nY\n",
			want: []ChangedSection{{Kind: "section", Heading: "(frontmatter)", Ordinal: 1, Side: "modified"}},
		},
		{
			name: "HeadingKey_WhitespaceTrimmed_NoSpuriousChange",
			old:  "# T\n\n## Why\n\nx\n",
			new:  "# T\n\n## Why \n\nx\n",
			want: []ChangedSection{},
		},
		{
			name: "Identical_NoChange",
			old:  "# T\n\n## Why\n\nx\n",
			new:  "# T\n\n## Why\n\nx\n",
			want: []ChangedSection{},
		},
		{
			name: "MultipleKinds_FrontmatterAndSection",
			old:  "---\nid: \"1\"\n---\n\n# T\n\n## Why\n\nx\n",
			new:  "---\nid: \"2\"\n---\n\n# T\n\n## Why\n\nCHANGED\n",
			want: []ChangedSection{
				{Kind: "frontmatter", Side: "modified"},
				{Kind: "section", Heading: "Why", Ordinal: 1, Side: "modified"},
			},
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			diff, got := diffSections([]byte(tc.old), []byte(tc.new))
			gotSet := csSet(got)
			wantSet := csSet(tc.want)
			if strings.Join(gotSet, ",") != strings.Join(wantSet, ",") {
				t.Errorf("changed_sections = %v, want %v", gotSet, wantSet)
			}
			// A changed region always produces >=1 anchor; identical → empty diff.
			if len(tc.want) == 0 && diff != "" {
				t.Errorf("expected empty diff for no-change, got %q", diff)
			}
			if len(tc.want) > 0 && diff == "" {
				t.Errorf("expected non-empty diff for a change")
			}
		})
	}
}
