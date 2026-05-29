package runner

import "testing"

func TestParseLibtestText_PassingTest(t *testing.T) {
	out := "running 1 test\ntest foo::tests::it_works ... ok\n\ntest result: ok. 1 passed; 0 failed\n"
	recs := parseLibtestText(out, "")
	if len(recs) != 1 {
		t.Fatalf("len=%d, want 1: %#v", len(recs), recs)
	}
	if recs[0].TestName != "foo::tests::it_works" || recs[0].Status != "passed" {
		t.Errorf("rec = %+v", recs[0])
	}
}

func TestParseLibtestText_FailingTest(t *testing.T) {
	out := "test foo::tests::it_fails ... FAILED\n"
	recs := parseLibtestText(out, "")
	if len(recs) != 1 || recs[0].Status != "failed" {
		t.Errorf("recs = %+v", recs)
	}
}

func TestParseLibtestText_IgnoredTest(t *testing.T) {
	out := "test foo::tests::it_skipped ... ignored\n"
	recs := parseLibtestText(out, "")
	if len(recs) != 1 || recs[0].Status != "ignored" {
		t.Errorf("recs = %+v", recs)
	}
}

func TestParseLibtestText_IntegrationTestStem(t *testing.T) {
	// Integration tests under tests/<stem>.rs report as `<stem>::<fn>`.
	out := "test foo::it_works ... ok\n"
	recs := parseLibtestText(out, "")
	if len(recs) != 1 {
		t.Fatalf("len=%d", len(recs))
	}
	if recs[0].TestName != "foo::it_works" {
		t.Errorf("TestName = %q", recs[0].TestName)
	}
}

func TestParseLibtestText_StripsCratePrefix(t *testing.T) {
	out := "test mycrate::foo::tests::a ... ok\n"
	recs := parseLibtestText(out, "mycrate")
	if len(recs) != 1 {
		t.Fatalf("len=%d", len(recs))
	}
	if recs[0].TestName != "foo::tests::a" {
		t.Errorf("TestName = %q, want %q (crate prefix stripped)", recs[0].TestName, "foo::tests::a")
	}
}

func TestParseLibtestText_DoesNotStripWhenAbsent(t *testing.T) {
	// Crate prefix to strip is provided but not present in output: no-op.
	out := "test foo::tests::a ... ok\n"
	recs := parseLibtestText(out, "mycrate")
	if recs[0].TestName != "foo::tests::a" {
		t.Errorf("TestName = %q, want %q", recs[0].TestName, "foo::tests::a")
	}
}

func TestParseLibtestText_MultipleTests(t *testing.T) {
	out := `running 3 tests
test a::b::p ... ok
test a::b::f ... FAILED
test a::b::i ... ignored
`
	recs := parseLibtestText(out, "")
	if len(recs) != 3 {
		t.Fatalf("len=%d, want 3", len(recs))
	}
	expect := []struct {
		name, status string
	}{
		{"a::b::p", "passed"},
		{"a::b::f", "failed"},
		{"a::b::i", "ignored"},
	}
	for i, e := range expect {
		if recs[i].TestName != e.name || recs[i].Status != e.status {
			t.Errorf("recs[%d] = %+v, want name=%q status=%q", i, recs[i], e.name, e.status)
		}
	}
}

func TestParseLibtestText_NoRecordsOnEmpty(t *testing.T) {
	recs := parseLibtestText("", "")
	if len(recs) != 0 {
		t.Errorf("expected empty, got %v", recs)
	}
	recs = parseLibtestText("running 0 tests\n\n", "")
	if len(recs) != 0 {
		t.Errorf("expected empty, got %v", recs)
	}
}

func TestParseLibtestText_IgnoresNonTestLines(t *testing.T) {
	out := `Compiling mycrate v0.1.0
test foo::tests::a ... ok
test result: ok. 1 passed; 0 failed; 0 ignored
`
	recs := parseLibtestText(out, "")
	if len(recs) != 1 || recs[0].TestName != "foo::tests::a" {
		t.Errorf("recs = %+v", recs)
	}
}
