// Package rusttok is a string/comment-aware Rust tokenizer used by
// speccraft-guard's static Rust-test detection (spec 0005 §What.2). It
// is not a full Rust parser: it only classifies bytes as Code, Comment,
// or StringLike so downstream extractors can ignore non-code regions
// when searching for `fn <name>(` declarations.
//
// The package intentionally does not parse `macro_rules!` pattern bodies
// or token-rewriting macros — those produce phantom `fn` extractions
// (spec §Limitations §L2). The runner backstop keeps the system sound.
package rusttok

// Kind classifies a Span as code, comment, or a string-like literal.
type Kind int

const (
	// KindCode: ordinary Rust code outside any literal or comment.
	KindCode Kind = iota
	// KindComment: line comment or (possibly nested) block comment.
	KindComment
	// KindStringLike: string literal, raw string, byte string, byte raw
	// string, or char literal. Lifetime annotations like `'a` are also
	// classified here — harmless for the fn-extractor's purposes.
	KindStringLike
)

// Span is a half-open [Start, End) range of bytes in the source.
type Span struct {
	Start, End int
	Kind       Kind
}

// Tokenize partitions src into non-overlapping ordered spans that fully
// cover the input. Adjacent spans of the same Kind are merged. An empty
// input returns no spans.
func Tokenize(src string) []Span {
	if len(src) == 0 {
		return nil
	}
	var spans []Span
	codeStart := 0
	i := 0
	emit := func(end int) {
		if codeStart < end {
			spans = append(spans, Span{Start: codeStart, End: end, Kind: KindCode})
		}
	}
	for i < len(src) {
		c := src[i]
		// Line comment.
		if c == '/' && i+1 < len(src) && src[i+1] == '/' {
			emit(i)
			start := i
			i += 2
			for i < len(src) && src[i] != '\n' {
				i++
			}
			// Include the newline in the comment span if present, to
			// keep code spans starting on a fresh line.
			if i < len(src) && src[i] == '\n' {
				i++
			}
			spans = append(spans, Span{Start: start, End: i, Kind: KindComment})
			codeStart = i
			continue
		}
		// Block comment (Rust supports nesting).
		if c == '/' && i+1 < len(src) && src[i+1] == '*' {
			emit(i)
			start := i
			i += 2
			depth := 1
			for i < len(src) && depth > 0 {
				if i+1 < len(src) && src[i] == '/' && src[i+1] == '*' {
					depth++
					i += 2
					continue
				}
				if i+1 < len(src) && src[i] == '*' && src[i+1] == '/' {
					depth--
					i += 2
					continue
				}
				i++
			}
			spans = append(spans, Span{Start: start, End: i, Kind: KindComment})
			codeStart = i
			continue
		}
		// Raw string: r"...", r#"..."#, r##"..."##, ..., and byte-raw
		// variants br"...", br#"..."#. The leading char is 'r' or 'b'
		// followed by 'r'.
		if isRawStringStart(src, i) {
			emit(i)
			start := i
			i = consumeRawString(src, i)
			spans = append(spans, Span{Start: start, End: i, Kind: KindStringLike})
			codeStart = i
			continue
		}
		// Byte string: b"...".
		if c == 'b' && i+1 < len(src) && src[i+1] == '"' && !isIdentChar(prevByte(src, i)) {
			emit(i)
			start := i
			i = consumeQuotedString(src, i+1) // skip the 'b', consume from "
			spans = append(spans, Span{Start: start, End: i, Kind: KindStringLike})
			codeStart = i
			continue
		}
		// Double-quoted string.
		if c == '"' {
			emit(i)
			start := i
			i = consumeQuotedString(src, i)
			spans = append(spans, Span{Start: start, End: i, Kind: KindStringLike})
			codeStart = i
			continue
		}
		// Char literal or lifetime. We classify the next 1–3 bytes as
		// StringLike if it looks char-like; otherwise treat ' as code
		// (a lifetime in a type/generic position).
		if c == '\'' {
			if end, ok := consumeCharOrLifetime(src, i); ok {
				emit(i)
				spans = append(spans, Span{Start: i, End: end, Kind: KindStringLike})
				codeStart = end
				i = end
				continue
			}
		}
		i++
	}
	emit(i)
	return mergeAdjacent(spans)
}

// consumeQuotedString returns the index just past the closing `"` of a
// double-quoted string starting at i. Handles `\"` and `\\` escapes.
// If the string is unterminated, returns len(src).
func consumeQuotedString(src string, i int) int {
	// src[i] == '"'.
	i++
	for i < len(src) {
		c := src[i]
		if c == '\\' && i+1 < len(src) {
			i += 2
			continue
		}
		if c == '"' {
			return i + 1
		}
		i++
	}
	return i
}

// isRawStringStart returns true if src[i:] begins a raw or byte-raw
// string: an optional `b`, then `r`, then one or more `#`, then `"`.
// Or `r"` / `br"` with no hashes.
func isRawStringStart(src string, i int) bool {
	j := i
	if j < len(src) && src[j] == 'b' {
		j++
	}
	if j >= len(src) || src[j] != 'r' {
		return false
	}
	j++
	// Must be preceded by a non-ident char (so we don't pick up `foo_r"`).
	if isIdentChar(prevByte(src, i)) {
		return false
	}
	// Zero or more hashes, then a quote.
	for j < len(src) && src[j] == '#' {
		j++
	}
	return j < len(src) && src[j] == '"'
}

// consumeRawString returns the index just past the closing `"#...#` of a
// raw string starting at i. The hash count on the closing side must
// equal the opening hash count.
func consumeRawString(src string, i int) int {
	j := i
	if src[j] == 'b' {
		j++
	}
	// src[j] == 'r'.
	j++
	hashes := 0
	for j < len(src) && src[j] == '#' {
		hashes++
		j++
	}
	// src[j] == '"'.
	j++
	for j < len(src) {
		if src[j] == '"' {
			// Match closing quote + same number of hashes.
			k := j + 1
			n := 0
			for k < len(src) && n < hashes && src[k] == '#' {
				k++
				n++
			}
			if n == hashes {
				return k
			}
		}
		j++
	}
	return j
}

// consumeCharOrLifetime tries to classify src[i:] as a Rust character
// literal. Returns (endIdx, true) if classified, (_, false) if it looks
// like a lifetime and should be left as code.
//
// Accept patterns: 'x', '\n', '\u{1F600}', '\x41', and the generic
// case where the next byte is a non-backslash printable and a closing
// `'` appears within a small window.
func consumeCharOrLifetime(src string, i int) (int, bool) {
	// src[i] == '\''.
	if i+1 >= len(src) {
		return 0, false
	}
	// Escaped char.
	if src[i+1] == '\\' {
		// Look for closing quote within next ~12 bytes (covers \u{...}).
		end := i + 2
		for end < len(src) && end-i < 14 {
			if src[end] == '\'' {
				return end + 1, true
			}
			end++
		}
		return 0, false
	}
	// Simple `'x'` (single byte char).
	if i+2 < len(src) && src[i+2] == '\'' {
		return i + 3, true
	}
	// Otherwise treat as a lifetime token (`'a`, `'static`) — code.
	return 0, false
}

// mergeAdjacent fuses adjacent spans of the same Kind to keep the
// output compact.
func mergeAdjacent(in []Span) []Span {
	if len(in) <= 1 {
		return in
	}
	out := in[:1]
	for _, s := range in[1:] {
		last := &out[len(out)-1]
		if last.Kind == s.Kind && last.End == s.Start {
			last.End = s.End
			continue
		}
		out = append(out, s)
	}
	return out
}

func isIdentChar(b byte) bool {
	return (b >= 'a' && b <= 'z') || (b >= 'A' && b <= 'Z') || (b >= '0' && b <= '9') || b == '_'
}

func prevByte(src string, i int) byte {
	if i == 0 {
		return 0
	}
	return src[i-1]
}
