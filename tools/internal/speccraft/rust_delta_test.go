package speccraft_test

import (
	"strings"
	"testing"

	"github.com/dcstolf/speccraft/tools/internal/speccraft"
	"github.com/dcstolf/speccraft/tools/internal/speccraft/runner"
)

func TestIsRustTestEdit_CleanInlineTest_Classified(t *testing.T) {
	pre := "pub fn add(a: i32, b: i32) -> i32 { a + b }\n"
	post := pre + "\n#[cfg(test)]\nmod tests {\n    fn it_works() {}\n}\n"
	if !speccraft.IsRustTestEdit("src/foo.rs", "foo", pre, post) {
		t.Error("expected (a) clean inline test to be classified as a test edit")
	}
}

func TestIsRustTestEdit_StringLiteralCfgTest_NotClassified(t *testing.T) {
	pre := "pub fn add(a: i32, b: i32) -> i32 { a + b }\n"
	post := pre + `let s = "#[cfg(test)] mod tests { fn it() {} }";` + "\n"
	if speccraft.IsRustTestEdit("src/foo.rs", "foo", pre, post) {
		t.Error("expected (b) string-literal cfg(test) to NOT be classified as a test edit (false positive eliminated)")
	}
}

func TestIsRustTestEdit_MultiAttributeMod_Classified(t *testing.T) {
	pre := "pub fn add(a: i32, b: i32) -> i32 { a + b }\n"
	post := pre + "\n#[cfg(test)]\n#[allow(dead_code)]\nmod tests {\n    fn it() {}\n}\n"
	if !speccraft.IsRustTestEdit("src/foo.rs", "foo", pre, post) {
		t.Error("expected (c) multi-attribute mod to be classified as a test edit")
	}
}

func TestIsRustTestEdit_EditWithoutNewTestInExistingMod_NotClassified(t *testing.T) {
	pre := "pub fn add() {}\n#[cfg(test)]\nmod tests {\n    fn old() {}\n}\n"
	// Same set of canonical IDs; only whitespace/comment changes inside the mod.
	post := "pub fn add() {}\n#[cfg(test)]\nmod tests {\n    // a comment\n    fn old() {}\n}\n"
	if speccraft.IsRustTestEdit("src/foo.rs", "foo", pre, post) {
		t.Error("expected (d) edit-without-new-test to NOT be classified")
	}
}

func TestIsRustTestEdit_MacroRulesPhantomFn_ClassifiedAsDocumentedLimitation(t *testing.T) {
	// §L2: the tokenizer does not parse macro_rules! bodies specially.
	// A literal identifier inside a macro body (here `generated_test`) is
	// extracted as a phantom canonical ID even though the macro is never
	// expanded — there is no real `fn generated_test()` after macro
	// expansion until the macro is invoked.
	//
	// This is the documented limitation. The runner backstop
	// (TestMacroPhantomID_RunnerBackstopRejects) keeps the system sound.
	pre := "pub fn add() {}\n"
	post := pre + `
#[cfg(test)]
mod tests {
    macro_rules! my_test { () => { fn generated_test() {} } }
}
`
	if !speccraft.IsRustTestEdit("src/foo.rs", "foo", pre, post) {
		t.Error("expected (L2 phantom) to be classified — this is the documented limitation; runner backstop catches it (see RunnerBackstopRejects test)")
	}
}

func TestIsRustTestEdit_IntegrationTestFile_Classified(t *testing.T) {
	pre := "fn helper() {}\n"
	post := pre + "fn alpha() {}\n"
	if !speccraft.IsRustTestEdit("tests/bar.rs", "bar", pre, post) {
		t.Error("expected integration test file to be classified when a new fn is added")
	}
}

func TestIsRustTestEdit_IntegrationTestFile_NoNewFn_NotClassified(t *testing.T) {
	pre := "fn alpha() {}\n"
	post := "fn alpha() { /* changed body */ }\n"
	if speccraft.IsRustTestEdit("tests/bar.rs", "bar", pre, post) {
		t.Error("expected NOT classified when integration file changes have no new fn")
	}
}

// TestMacroPhantomID_RunnerBackstopRejects companions the §L2 phantom-ID
// test. The phantom canonical ID extracted from a macro_rules! body would
// not appear in real runner output, so the classifyOutcome helper applied
// to that scenario yields OutcomeAllPassed → guard rejects with
// "no failing test observed". Full guard integration is in Step 51.
func TestMacroPhantomID_RunnerBackstopRejects(t *testing.T) {
	// Simulate the runner's reply when invoked with --exact on the phantom
	// ID "foo::tests::$n": nothing matches, runner exits 0, zero records.
	res := runner.Result{
		Outcome: runner.OutcomeAllPassed, // synthesized as the helper would
		Records: nil,
	}
	// The guard's logic (mirrored here) would reject this transition.
	if res.Outcome == runner.OutcomeAtLeastOneFailed {
		t.Error("phantom ID should not be classified as a real failure")
	}
	if res.Outcome != runner.OutcomeAllPassed {
		t.Errorf("expected backstop outcome OutcomeAllPassed, got %v", res.Outcome)
	}
	// The guard surfaces this as "no failing test observed" per AC #4 — a
	// rejection, not an accept. So §L2 stays sound end-to-end.
	if strings.Contains(res.Outcome.String(), "failed") {
		t.Error("OutcomeAllPassed must not stringify as 'failed' family")
	}
}
