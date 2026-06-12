package runner_test

import (
	"context"
	"testing"

	"github.com/dcstolf/speccraft/tools/internal/speccraft"
	"github.com/dcstolf/speccraft/tools/internal/speccraft/runner"
)

func TestOutcome_StringValues(t *testing.T) {
	cases := []struct {
		o    runner.Outcome
		want string
	}{
		{runner.OutcomeBuildFailed, "build_failed"},
		{runner.OutcomeAllPassed, "all_passed"},
		{runner.OutcomeAtLeastOneFailed, "at_least_one_failed"},
	}
	for _, c := range cases {
		if got := c.o.String(); got != c.want {
			t.Errorf("Outcome.String() = %q, want %q", got, c.want)
		}
	}
}

func TestTestRecord_StatusValues(t *testing.T) {
	cases := []struct {
		in   string
		ok   bool
		want string
	}{
		{"passed", true, "passed"},
		{"failed", true, "failed"},
		{"ignored", true, "ignored"},
		{"weird", false, ""},
		{"", false, ""},
	}
	for _, c := range cases {
		s, ok := runner.StatusFromString(c.in)
		if ok != c.ok {
			t.Errorf("StatusFromString(%q) ok=%v, want %v", c.in, ok, c.ok)
		}
		if s != c.want {
			t.Errorf("StatusFromString(%q) = %q, want %q", c.in, s, c.want)
		}
	}
}

// fakeRunner exists only to verify the Runner interface shape at compile time.
type fakeRunner struct{}

func (fakeRunner) Run(_ context.Context, _ runner.Request) (runner.Result, error) {
	return runner.Result{}, nil
}

func TestRunner_InterfaceShape_Compile(t *testing.T) {
	var _ runner.Runner = (*fakeRunner)(nil)
	// Reaching here at all is the assertion; the compiler did the work.
}

// AdapterFor tests (Step 20)

func TestAdapterFor_CargoConfig_ReturnsCargoAdapter(t *testing.T) {
	cfg := speccraft.SpeccraftConfig{}
	cfg.TDD.Rust.Runner = "cargo"
	a := runner.AdapterFor(cfg)
	if _, ok := a.(*runner.CargoAdapter); !ok {
		t.Errorf("AdapterFor cargo = %T, want *runner.CargoAdapter", a)
	}
}

func TestAdapterFor_NextestConfig_ReturnsNextestAdapter(t *testing.T) {
	cfg := speccraft.SpeccraftConfig{}
	cfg.TDD.Rust.Runner = "nextest"
	a := runner.AdapterFor(cfg)
	if _, ok := a.(*runner.NextestAdapter); !ok {
		t.Errorf("AdapterFor nextest = %T, want *runner.NextestAdapter", a)
	}
}

func TestAdapterFor_EmptyConfig_DefaultsToCargo(t *testing.T) {
	cfg := speccraft.SpeccraftConfig{}
	a := runner.AdapterFor(cfg)
	if _, ok := a.(*runner.CargoAdapter); !ok {
		t.Errorf("AdapterFor empty = %T, want *runner.CargoAdapter (default)", a)
	}
}

// --- Spec 0018 T12: AdapterForLanguage factory ---

func cfgWith(jsCmd, tsCmd string) speccraft.SpeccraftConfig {
	var cfg speccraft.SpeccraftConfig
	cfg.TDD.Go.Command = "go test"
	cfg.TDD.Python.Command = "pytest"
	cfg.TDD.JavaScript.Command = jsCmd
	cfg.TDD.TypeScript.Command = tsCmd
	return cfg
}

func Test_AdapterForLanguage_Go(t *testing.T) {
	a, ok := runner.AdapterForLanguage("go", cfgWith("", ""))
	if !ok {
		t.Fatal("expected ok=true for go")
	}
	if _, isGo := a.(*runner.GoAdapter); !isGo {
		t.Errorf("expected *GoAdapter, got %T", a)
	}
}

func Test_AdapterForLanguage_Python(t *testing.T) {
	a, ok := runner.AdapterForLanguage("python", cfgWith("", ""))
	if !ok {
		t.Fatal("expected ok=true for python")
	}
	if _, isPy := a.(*runner.PytestAdapter); !isPy {
		t.Errorf("expected *PytestAdapter, got %T", a)
	}
}

func Test_AdapterForLanguage_JSShared(t *testing.T) {
	a, ok := runner.AdapterForLanguage("js", cfgWith("vitest run", "tsc-test"))
	if !ok {
		t.Fatal("expected ok=true for js with configured command")
	}
	ja, isJS := a.(*runner.JSTSAdapter)
	if !isJS {
		t.Fatalf("expected *JSTSAdapter, got %T", a)
	}
	if ja.Command != "vitest run" {
		t.Errorf("js Command = %q, want from [tdd.javascript]", ja.Command)
	}
}

func Test_AdapterForLanguage_TSShared(t *testing.T) {
	a, ok := runner.AdapterForLanguage("ts", cfgWith("vitest run", "tsc-test"))
	if !ok {
		t.Fatal("expected ok=true for ts with configured command")
	}
	ja, isJS := a.(*runner.JSTSAdapter)
	if !isJS {
		t.Fatalf("expected *JSTSAdapter (shared with JS), got %T", a)
	}
	if ja.Command != "tsc-test" {
		t.Errorf("ts Command = %q, want from [tdd.typescript]", ja.Command)
	}
}

func Test_AdapterForLanguage_JSTS_EmptyCommand_NotOK(t *testing.T) {
	if _, ok := runner.AdapterForLanguage("js", cfgWith("", "")); ok {
		t.Error("expected ok=false for js with empty command (fail-closed, D2)")
	}
	if _, ok := runner.AdapterForLanguage("ts", cfgWith("", "")); ok {
		t.Error("expected ok=false for ts with empty command (fail-closed, D2)")
	}
}

func Test_AdapterForLanguage_UnknownLang_NotOK(t *testing.T) {
	if _, ok := runner.AdapterForLanguage("ruby", cfgWith("x", "x")); ok {
		t.Error("expected ok=false for unknown language")
	}
}
