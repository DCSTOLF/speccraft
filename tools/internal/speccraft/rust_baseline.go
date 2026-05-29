package speccraft

// CaptureInitialRustBaseline implements AC #12 (a)(b): on the first
// guard invocation against a Rust crate where rust_test_baseline is
// empty, walk the crate and write the discovered canonical IDs as the
// initial baseline. Subsequent calls (when baseline is non-empty) are
// no-ops.
//
// Returns (captured=true, count=N) when the baseline was written for
// the first time, where N is the number of IDs captured. Returns
// (captured=false, count=0) when the baseline was already non-empty
// (no mutation occurred).
//
// All writes route through SetRustBaseline (which calls speccraft-state's
// SaveState under the file lock) per the single-writer guardrail.
func CaptureInitialRustBaseline(root string) (captured bool, count int, err error) {
	// Sentinel-based detection: capture has occurred iff the
	// RustBaselineCaptured flag is set, regardless of whether the
	// baseline IDs list is empty (a no-test crate state has captured=true,
	// ids=[]).
	already, err := IsRustBaselineCaptured(root)
	if err != nil {
		return false, 0, err
	}
	if already {
		return false, 0, nil
	}
	ids, err := DiscoverRustTests(root)
	if err != nil {
		return false, 0, err
	}
	if ids == nil {
		ids = []string{}
	}
	if err := SetRustBaseline(root, ids); err != nil {
		return false, 0, err
	}
	return true, len(ids), nil
}

// PostAcceptUpdateRustBaseline implements AC #12 (c): after a red-check
// accept (AC #4 `at_least_one_failed` branch), append the failing tests
// that are also in the just-added set. Tests that failed but are NOT in
// just-added, and tests in just-added that did NOT fail, are excluded.
//
// failedTestNames is the list of TestRecord.TestName values whose Status
// is "failed". The caller (typically speccraft-guard) computes this from
// the runner.Result before calling — keeping this package free of a
// runner-import cycle.
//
// All writes go through AppendRustBaseline (which dedups and sorts).
func PostAcceptUpdateRustBaseline(root string, justAdded, failedTestNames []string) error {
	failed := make(map[string]struct{}, len(failedTestNames))
	for _, n := range failedTestNames {
		failed[n] = struct{}{}
	}
	var toAppend []string
	for _, id := range justAdded {
		if _, ok := failed[id]; ok {
			toAppend = append(toAppend, id)
		}
	}
	return AppendRustBaseline(root, toAppend)
}

// RecaptureRustBaseline implements AC #12 (d): walk the crate and
// overwrite rust_test_baseline with the freshly-discovered canonical
// IDs. Stale entries (tests that no longer exist) are removed.
//
// Returns the number of IDs in the new baseline.
func RecaptureRustBaseline(root string) (int, error) {
	ids, err := DiscoverRustTests(root)
	if err != nil {
		return 0, err
	}
	if ids == nil {
		ids = []string{}
	}
	if err := SetRustBaseline(root, ids); err != nil {
		return 0, err
	}
	return len(ids), nil
}
