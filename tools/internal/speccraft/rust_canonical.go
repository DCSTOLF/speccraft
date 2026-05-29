package speccraft

import (
	"regexp"

	"github.com/dcstolf/speccraft/tools/internal/speccraft/rusttok"
)

// CanonicalInlineTestIDs returns canonical Rust test IDs (per spec 0005
// §What.3, fully-qualified `<fileStem>::<mod-path>::<fn>` form) for all
// inline test functions in src. Recognizes top-level `#[cfg(test)] mod`
// blocks and recurses into nested `mod <ident> { ... }` items inside
// them.
//
// The returned slice preserves source order. Duplicates are not removed
// here — callers compute set semantics.
func CanonicalInlineTestIDs(src, fileStem string) []string {
	blocks := FindCfgTestModBlocks(src)
	var ids []string
	for _, b := range blocks {
		body := src[b.BodyStart:b.BodyEnd]
		ids = append(ids, walkModFns(body, fileStem+"::"+b.ModName)...)
	}
	return ids
}

// CanonicalIntegrationTestIDs returns canonical IDs for top-level `fn`
// declarations in an integration-test file (e.g. tests/bar.rs). The
// prefix is `<fileStem>::<fn>` — integration tests do not have a wrapper
// `mod` in the canonical form emitted by `cargo test`.
func CanonicalIntegrationTestIDs(src, fileStem string) []string {
	names := rusttok.ExtractFnNames(src)
	ids := make([]string, 0, len(names))
	for _, n := range names {
		ids = append(ids, fileStem+"::"+n)
	}
	return ids
}

// fnDeclLocal mirrors rusttok's fn-decl regex, used by canonical-ID walking
// inside nested mod bodies (where we need region-level extraction with
// code-mask awareness).
var fnDeclLocal = regexp.MustCompile(`\bfn\s+([A-Za-z_][A-Za-z0-9_]*)\s*[(<]`)

// walkModFns recurses into the body of a test mod, emitting canonical IDs
// for direct `fn` declarations and nested `mod inner { ... }` items.
// prefix is the canonical-form prefix accumulated so far (e.g.
// `foo::tests`).
func walkModFns(body, prefix string) []string {
	spans := rusttok.Tokenize(body)
	codeMask := buildCodeMask(spans, len(body))

	nestedSpans := findNestedModSpans(body, codeMask)

	var ids []string
	for _, n := range extractFnNamesOutside(body, codeMask, nestedSpans) {
		ids = append(ids, prefix+"::"+n)
	}
	for _, ns := range nestedSpans {
		nestedBody := body[ns.bodyStart:ns.bodyEnd]
		ids = append(ids, walkModFns(nestedBody, prefix+"::"+ns.name)...)
	}
	return ids
}

type nestedModSpan struct {
	name               string
	itemStart          int // position of `mod` keyword
	bodyStart, bodyEnd int
}

// findNestedModSpans locates `mod <ident> { ... }` items in body (in code
// regions only) and returns their body spans.
func findNestedModSpans(body string, codeMask []bool) []nestedModSpan {
	var out []nestedModSpan
	for _, m := range modDeclRE.FindAllStringSubmatchIndex(body, -1) {
		if !isCode(codeMask, m[0]) {
			continue
		}
		name := body[m[2]:m[3]]
		bodyStart := m[1]
		bodyEnd, ok := scanMatchingBrace(body, codeMask, bodyStart)
		if !ok {
			continue
		}
		out = append(out, nestedModSpan{
			name:      name,
			itemStart: m[0],
			bodyStart: bodyStart,
			bodyEnd:   bodyEnd,
		})
	}
	return out
}

// extractFnNamesOutside returns fn names found in code regions of body
// that are NOT inside any of the given nested-mod body ranges.
func extractFnNamesOutside(body string, codeMask []bool, nested []nestedModSpan) []string {
	insideNested := make([]bool, len(body))
	for _, ns := range nested {
		for i := ns.itemStart; i < ns.bodyEnd && i < len(body); i++ {
			insideNested[i] = true
		}
	}
	var names []string
	i := 0
	for i < len(body) {
		if !isCode(codeMask, i) || insideNested[i] {
			i++
			continue
		}
		j := i
		for j < len(body) && isCode(codeMask, j) && !insideNested[j] {
			j++
		}
		region := body[i:j]
		for _, m := range fnDeclLocal.FindAllStringSubmatch(region, -1) {
			names = append(names, m[1])
		}
		i = j
	}
	return names
}
