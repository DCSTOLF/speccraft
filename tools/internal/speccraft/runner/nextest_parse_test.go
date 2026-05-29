package runner

import "testing"

func TestParseLibtestJSON_PassingEvent(t *testing.T) {
	out := `{"type":"test","event":"ok","name":"mycrate::foo::tests::it_works"}` + "\n"
	recs := parseLibtestJSON(out, "mycrate")
	if len(recs) != 1 {
		t.Fatalf("len=%d, want 1", len(recs))
	}
	if recs[0].TestName != "foo::tests::it_works" || recs[0].Status != "passed" {
		t.Errorf("rec = %+v", recs[0])
	}
}

func TestParseLibtestJSON_FailingEvent(t *testing.T) {
	out := `{"type":"test","event":"failed","name":"foo::tests::it_fails"}` + "\n"
	recs := parseLibtestJSON(out, "")
	if len(recs) != 1 || recs[0].Status != "failed" {
		t.Errorf("recs = %+v", recs)
	}
}

func TestParseLibtestJSON_IgnoredEvent(t *testing.T) {
	out := `{"type":"test","event":"ignored","name":"foo::tests::it_skipped"}` + "\n"
	recs := parseLibtestJSON(out, "")
	if len(recs) != 1 || recs[0].Status != "ignored" {
		t.Errorf("recs = %+v", recs)
	}
}

func TestParseLibtestJSON_PerBinaryNormalization(t *testing.T) {
	// Multi-binary stream: lib + integration. Records appear in encounter order.
	out := `{"type":"suite","event":"started","test_count":3}
{"type":"test","event":"started","name":"mycrate::lib::a"}
{"type":"test","event":"ok","name":"mycrate::lib::a"}
{"type":"test","event":"failed","name":"foo::it_x"}
{"type":"test","event":"ignored","name":"foo::it_y"}
{"type":"suite","event":"ok"}
`
	recs := parseLibtestJSON(out, "mycrate")
	if len(recs) != 3 {
		t.Fatalf("len=%d, want 3 (3 ok/failed/ignored events): %+v", len(recs), recs)
	}
	want := []struct{ name, status string }{
		{"lib::a", "passed"},
		{"foo::it_x", "failed"},
		{"foo::it_y", "ignored"},
	}
	for i, w := range want {
		if recs[i].TestName != w.name || recs[i].Status != w.status {
			t.Errorf("recs[%d] = %+v, want name=%q status=%q", i, recs[i], w.name, w.status)
		}
	}
}

func TestParseLibtestJSON_IgnoresNonTestEvents(t *testing.T) {
	out := `{"type":"suite","event":"started","test_count":1}
{"type":"test","event":"started","name":"foo::a"}
{"type":"test","event":"ok","name":"foo::a"}
{"type":"suite","event":"ok"}
`
	recs := parseLibtestJSON(out, "")
	if len(recs) != 1 {
		t.Errorf("expected 1 record (only ok terminal event counts), got %d: %+v", len(recs), recs)
	}
}

func TestParseLibtestJSON_BadLinesSkipped(t *testing.T) {
	out := `{"type":"test","event":"ok","name":"foo::a"}
not json at all
{"malformed
{"type":"test","event":"failed","name":"foo::b"}
`
	recs := parseLibtestJSON(out, "")
	if len(recs) != 2 {
		t.Errorf("expected 2 records (bad lines skipped), got %d: %+v", len(recs), recs)
	}
}

func TestParseLibtestJSON_EmptyInput(t *testing.T) {
	if recs := parseLibtestJSON("", ""); len(recs) != 0 {
		t.Errorf("expected empty, got %v", recs)
	}
}
