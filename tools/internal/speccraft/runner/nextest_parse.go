package runner

import (
	"encoding/json"
	"strings"
)

// libtestJSONEvent is the subset of nextest's libtest-json event shape we
// care about. Other fields (exec_time, stdout, etc.) are ignored.
type libtestJSONEvent struct {
	Type  string `json:"type"`
	Event string `json:"event"`
	Name  string `json:"name"`
}

// parseLibtestJSON extracts TestRecord entries from nextest's
// `--message-format libtest-json` event stream. Each line is an
// independent JSON object; malformed lines and non-test events are
// silently skipped. Only terminal events (ok/failed/ignored) produce
// records — `"event":"started"` is not a result.
func parseLibtestJSON(stdout, cratePrefixToStrip string) []TestRecord {
	var recs []TestRecord
	prefix := ""
	if cratePrefixToStrip != "" {
		prefix = cratePrefixToStrip + "::"
	}
	for _, line := range strings.Split(stdout, "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		var ev libtestJSONEvent
		if err := json.Unmarshal([]byte(line), &ev); err != nil {
			continue
		}
		if ev.Type != "test" {
			continue
		}
		var status string
		switch ev.Event {
		case "ok":
			status = "passed"
		case "failed":
			status = "failed"
		case "ignored":
			status = "ignored"
		default:
			// "started" and any unknown event types: skip.
			continue
		}
		name := ev.Name
		if prefix != "" && strings.HasPrefix(name, prefix) {
			name = strings.TrimPrefix(name, prefix)
		}
		recs = append(recs, TestRecord{TestName: name, Status: status})
	}
	return recs
}
