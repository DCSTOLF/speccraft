package speccraft

import (
	"regexp"

	"github.com/dcstolf/speccraft/tools/internal/speccraft/rusttok"
)

// CfgTestModBlock is one `#[cfg(test)] mod <ident> { ... }` block discovered
// in a Rust source file. BodyStart/BodyEnd is the half-open span of the
// content *between* the outer `{` and `}` (exclusive of the braces).
type CfgTestModBlock struct {
	ModName   string
	BodyStart int
	BodyEnd   int
}

// cfgTestAttrRE matches `#[cfg(test)]` or `#[cfg(any(test, ...))]`. It
// tolerates whitespace inside the parentheses. The match position is used
// as the seed for scanning forward to a matching `mod <ident> {`.
var cfgTestAttrRE = regexp.MustCompile(`#\[cfg\((test|any\(\s*test\s*(?:,[^)]*)?\))\)\]`)

// modDeclRE finds a `mod <ident> {` declaration, optionally preceded by
// `pub`. Used at the seed position to confirm the test attribute is
// followed (possibly via intervening attribute lines) by a mod item.
var modDeclRE = regexp.MustCompile(`(?:pub(?:\([^)]*\))?\s+)?mod\s+([A-Za-z_][A-Za-z0-9_]*)\s*\{`)

// FindCfgTestModBlocks returns all `#[cfg(test)] mod <ident> { ... }` blocks
// in src. The detector tolerates zero or more outer-attribute items
// (e.g. `#[allow(...)]`) between the cfg(test) attribute and the `mod`.
// Brace balancing uses the rusttok tokenizer to skip `{`/`}` inside
// strings and comments.
//
// Nested `mod` items inside a discovered block are part of the outer
// block's body span — not returned as separate blocks (the canonical-ID
// extractor handles nesting at a higher layer).
func FindCfgTestModBlocks(src string) []CfgTestModBlock {
	spans := rusttok.Tokenize(src)
	codeMask := buildCodeMask(spans, len(src))

	var blocks []CfgTestModBlock
	for _, attrLoc := range cfgTestAttrRE.FindAllStringIndex(src, -1) {
		// Skip matches that land inside a non-code region (string/comment).
		if !isCode(codeMask, attrLoc[0]) {
			continue
		}
		// From the end of the attribute, walk forward across whitespace
		// and additional outer-attribute lines to the `mod <ident> {`.
		pos := attrLoc[1]
		pos = skipAttributesAndWhitespace(src, codeMask, pos)
		modLoc := modDeclRE.FindStringSubmatchIndex(src[pos:])
		if modLoc == nil {
			continue
		}
		// The match must begin at pos (no skipped non-attribute content).
		if modLoc[0] != 0 {
			continue
		}
		modName := src[pos+modLoc[2] : pos+modLoc[3]]
		// modLoc[1] points just past the `{` — that's the body start.
		bodyStart := pos + modLoc[1]
		bodyEnd, ok := scanMatchingBrace(src, codeMask, bodyStart)
		if !ok {
			continue
		}
		blocks = append(blocks, CfgTestModBlock{
			ModName:   modName,
			BodyStart: bodyStart,
			BodyEnd:   bodyEnd, // index of the closing `}` (exclusive of `}`)
		})
	}
	return blocks
}

// skipAttributesAndWhitespace advances past whitespace and zero or more
// additional `#[...]` attribute items, returning the next code position.
func skipAttributesAndWhitespace(src string, codeMask []bool, pos int) int {
	for pos < len(src) {
		// Skip whitespace (including newlines).
		for pos < len(src) && isWhitespace(src[pos]) {
			pos++
		}
		if pos >= len(src) {
			return pos
		}
		// Skip an outer attribute item: `#[...]` with balanced brackets,
		// but only if we're in code.
		if src[pos] == '#' && pos+1 < len(src) && src[pos+1] == '[' && isCode(codeMask, pos) {
			depth := 0
			end := pos
			for end < len(src) {
				if src[end] == '[' {
					depth++
				} else if src[end] == ']' {
					depth--
					if depth == 0 {
						end++
						break
					}
				}
				end++
			}
			pos = end
			continue
		}
		return pos
	}
	return pos
}

// scanMatchingBrace finds the index of the `}` that closes the outermost
// `{` whose body starts at start. Brace counting respects the code mask
// (string/comment braces don't count). Returns (endIdx, true) where
// endIdx is the position of the closing `}` (so [start, endIdx) is the
// body content), or (0, false) if unbalanced.
func scanMatchingBrace(src string, codeMask []bool, start int) (int, bool) {
	depth := 1
	for i := start; i < len(src); i++ {
		if !isCode(codeMask, i) {
			continue
		}
		switch src[i] {
		case '{':
			depth++
		case '}':
			depth--
			if depth == 0 {
				return i, true
			}
		}
	}
	return 0, false
}

// buildCodeMask returns a byte mask where mask[i] is true iff src[i]
// is in a KindCode span. Indexes past len(src) are false.
func buildCodeMask(spans []rusttok.Span, n int) []bool {
	mask := make([]bool, n)
	for _, s := range spans {
		if s.Kind != rusttok.KindCode {
			continue
		}
		for i := s.Start; i < s.End && i < n; i++ {
			mask[i] = true
		}
	}
	return mask
}

func isCode(mask []bool, i int) bool {
	if i < 0 || i >= len(mask) {
		return false
	}
	return mask[i]
}

func isWhitespace(b byte) bool {
	return b == ' ' || b == '\t' || b == '\n' || b == '\r'
}
