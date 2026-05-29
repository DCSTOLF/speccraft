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
