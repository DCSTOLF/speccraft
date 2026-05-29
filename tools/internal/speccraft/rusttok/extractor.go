package rusttok

import "regexp"

// fnDeclRE matches a `fn <ident>(` declaration. The opening delimiter
// after the identifier may be `(` (no generics) or `<` (generic
// parameter list); both are accepted so generic fns are recognized.
//
// We deliberately do NOT require leading `pub`/`async`/`unsafe`/etc.;
// callers strip non-code spans first, and a bare `fn name(` matches
// regardless of preceding modifiers.
var fnDeclRE = regexp.MustCompile(`\bfn\s+([A-Za-z_][A-Za-z0-9_]*)\s*[(<]`)

// ExtractFnNames returns the names of top-level `fn <name>(` declarations
// found in src, in source order. Occurrences inside string/char literals
// or comments are ignored via tokenizer pre-pass. Duplicates are NOT
// deduplicated — callers compute set semantics if they need them.
//
// This is not a semantic Rust parser: it deliberately accepts any `fn
// <ident>(` regardless of visibility, async-ness, generics, or trait
// context. macro_rules! and quote!{} bodies look like code to this
// extractor; phantom matches are documented in spec 0005 §Limitations §L2.
func ExtractFnNames(src string) []string {
	spans := Tokenize(src)
	var names []string
	for _, s := range spans {
		if s.Kind != KindCode {
			continue
		}
		region := src[s.Start:s.End]
		for _, m := range fnDeclRE.FindAllStringSubmatch(region, -1) {
			names = append(names, m[1])
		}
	}
	return names
}
