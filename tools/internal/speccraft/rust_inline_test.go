package speccraft_test

import (
	"strings"
	"testing"

	"github.com/dcstolf/speccraft/tools/internal/speccraft"
)

func TestFindCfgTestModBlocks_BareCfgTest(t *testing.T) {
	src := "#[cfg(test)]\nmod tests {\n    fn a() {}\n}\n"
	blocks := speccraft.FindCfgTestModBlocks(src)
	if len(blocks) != 1 {
		t.Fatalf("len=%d, want 1; %+v", len(blocks), blocks)
	}
	if blocks[0].ModName != "tests" {
		t.Errorf("ModName=%q, want %q", blocks[0].ModName, "tests")
	}
	body := src[blocks[0].BodyStart:blocks[0].BodyEnd]
	if !strings.Contains(body, "fn a()") {
		t.Errorf("body span does not contain fn a(): %q", body)
	}
}

func TestFindCfgTestModBlocks_CfgAny(t *testing.T) {
	src := "#[cfg(any(test, foo))]\nmod t {\n    fn b() {}\n}\n"
	blocks := speccraft.FindCfgTestModBlocks(src)
	if len(blocks) != 1 || blocks[0].ModName != "t" {
		t.Errorf("blocks = %+v", blocks)
	}
}

func TestFindCfgTestModBlocks_MultipleAttributesBetween(t *testing.T) {
	src := "#[cfg(test)]\n#[allow(dead_code)]\nmod tests {\n    fn a() {}\n}\n"
	blocks := speccraft.FindCfgTestModBlocks(src)
	if len(blocks) != 1 {
		t.Fatalf("len=%d, want 1; %+v", len(blocks), blocks)
	}
}

func TestFindCfgTestModBlocks_PubMod(t *testing.T) {
	src := "#[cfg(test)]\npub mod tests {\n    fn a() {}\n}\n"
	blocks := speccraft.FindCfgTestModBlocks(src)
	if len(blocks) != 1 || blocks[0].ModName != "tests" {
		t.Errorf("blocks = %+v", blocks)
	}
}

func TestFindCfgTestModBlocks_NoMatch_PlainModNoCfg(t *testing.T) {
	src := "mod tests {\n    fn a() {}\n}\n"
	blocks := speccraft.FindCfgTestModBlocks(src)
	if len(blocks) != 0 {
		t.Errorf("expected no matches, got %+v", blocks)
	}
}

func TestFindCfgTestModBlocks_NoMatch_CfgTestNoMod(t *testing.T) {
	src := "#[cfg(test)]\nfn x() {}\n"
	blocks := speccraft.FindCfgTestModBlocks(src)
	if len(blocks) != 0 {
		t.Errorf("expected no matches, got %+v", blocks)
	}
}

func TestFindCfgTestModBlocks_NestedMod(t *testing.T) {
	src := "#[cfg(test)]\nmod tests {\n    mod inner {\n        fn x() {}\n    }\n}\n"
	blocks := speccraft.FindCfgTestModBlocks(src)
	if len(blocks) != 1 {
		t.Fatalf("len=%d, want 1 outer block (inner is contained); %+v", len(blocks), blocks)
	}
	body := src[blocks[0].BodyStart:blocks[0].BodyEnd]
	if !strings.Contains(body, "mod inner") || !strings.Contains(body, "fn x()") {
		t.Errorf("outer body span missing nested content: %q", body)
	}
}

func TestFindCfgTestModBlocks_BalancesBracesInStrings(t *testing.T) {
	// A `{` inside a string literal must not affect brace balancing.
	src := `#[cfg(test)]
mod tests {
    let s = "weird { string";
    fn a() {}
}
`
	blocks := speccraft.FindCfgTestModBlocks(src)
	if len(blocks) != 1 {
		t.Fatalf("brace balancing broken by string-literal brace; got %+v", blocks)
	}
}
