package delegate_test

// Spec 0054 AC4 — the Go half of the reader parity check.
//
// This file and tests/hooks/spec-review-dispatch.bats are driven from the SAME
// corpus (tests/hooks/fixtures/review-dispatch/registries/) via the same
// expected.txt. Two readers validating the same registry independently is the
// only thing that keeps them from drifting: the loader gates `spec:delegate`
// and the shell reader gates the review round, so a disagreement means one
// surface accepts a registry the other refuses.
//
// The corpus is a DIRECTORY, not one file: LoadConfig fails the whole file on
// the first bad entry while review_agent_mode is per-agent, so a single
// parity.toml carrying reject rows could not be driven by both readers.

import (
	"bufio"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/dcstolf/speccraft/tools/internal/delegate"
)

// corpusReasons is the reject-reason set the corpus MUST cover, hardcoded here
// on purpose. Deriving it from expected.txt would make the coverage assertion
// circular — a corpus missing five fixtures would "cover" its own shortened
// list and pass.
var corpusReasons = []string{
	"empty-mode",
	"case-variant",
	"cmd-on-subagent",
	"input-on-codex-plugin",
	"acp-agent-on-subagent",
	"subagent-type-on-codex-plugin",
	"effort-on-subagent",
	"plugin-root-on-subagent",
	"bad-effort",
	"bad-subagent-model",
	"unknown-key-on-new-mode",
}

func corpusDir() string {
	return filepath.Join("..", "..", "..",
		"tests", "hooks", "fixtures", "review-dispatch", "registries")
}

type corpusRow struct {
	path   string // relative to the corpus dir
	accept bool
	reason string
}

// readCorpus parses expected.txt. Blank lines and # comments are skipped; any
// other malformed line is a hard failure rather than a silent skip, because a
// row quietly dropped is a validation case quietly not run.
func readCorpus(t *testing.T) []corpusRow {
	t.Helper()
	f, err := os.Open(filepath.Join(corpusDir(), "expected.txt"))
	if err != nil {
		t.Fatalf("corpus manifest unreadable: %v", err)
	}
	defer f.Close()

	var rows []corpusRow
	sc := bufio.NewScanner(f)
	for n := 1; sc.Scan(); n++ {
		line := strings.TrimSpace(sc.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		parts := strings.Fields(line)
		switch {
		case len(parts) == 2 && parts[1] == "accept":
			rows = append(rows, corpusRow{path: parts[0], accept: true})
		case len(parts) == 3 && parts[1] == "reject":
			rows = append(rows, corpusRow{path: parts[0], reason: parts[2]})
		default:
			t.Fatalf("expected.txt:%d is malformed: %q", n, line)
		}
	}
	if err := sc.Err(); err != nil {
		t.Fatal(err)
	}
	if len(rows) == 0 {
		t.Fatal("corpus manifest parsed to zero rows")
	}
	return rows
}

func Test_LoadConfig_ParityCorpus_AcceptsAcceptAll(t *testing.T) {
	var accepted int
	for _, row := range readCorpus(t) {
		if !row.accept {
			continue
		}
		accepted++
		body, err := os.ReadFile(filepath.Join(corpusDir(), row.path))
		if err != nil {
			t.Fatalf("%s: %v", row.path, err)
		}
		cfg, err := delegate.LoadConfig(writeRegistry(t, string(body)))
		if err != nil {
			t.Fatalf("%s must be accepted, got: %v", row.path, err)
		}

		// Every mode plus the mode-less form must appear, or an "accepts
		// everything" fixture could be three entries wide and still pass.
		seen := map[string]bool{}
		for _, a := range cfg.Agents {
			seen[a.Mode] = true
		}
		for _, want := range delegate.ValidModes {
			if !seen[want] {
				t.Errorf("%s decodes no entry with mode %q; the accept fixture must exercise all four",
					row.path, want)
			}
		}
	}
	if accepted == 0 {
		t.Fatal("the corpus declares no accept row")
	}
}

func Test_LoadConfig_ParityCorpus_RejectsEachRejectFixture(t *testing.T) {
	var rejected int
	for _, row := range readCorpus(t) {
		if row.accept {
			continue
		}
		rejected++
		body, err := os.ReadFile(filepath.Join(corpusDir(), row.path))
		if err != nil {
			t.Fatalf("%s: %v", row.path, err)
		}
		_, err = delegate.LoadConfig(writeRegistry(t, string(body)))
		if err == nil {
			t.Errorf("%s (%s) must be rejected, got nil", row.path, row.reason)
			continue
		}
		// The diagnostic must name the offending agent. Not the reason token —
		// that is the corpus's label, not something the loader emits.
		if !strings.Contains(err.Error(), "bad") {
			t.Errorf("%s: error must name the offending agent, got: %v", row.path, err)
		}
	}
	if rejected == 0 {
		t.Fatal("the corpus declares no reject row")
	}
}

func Test_ParityCorpus_CoversEveryRejectReason(t *testing.T) {
	rows := readCorpus(t)

	declared := map[string]string{} // reason -> path
	for _, row := range rows {
		if row.accept {
			continue
		}
		if prev, dup := declared[row.reason]; dup {
			t.Errorf("reason %q is declared twice (%s and %s)", row.reason, prev, row.path)
		}
		declared[row.reason] = row.path
	}

	for _, want := range corpusReasons {
		path, ok := declared[want]
		if !ok {
			t.Errorf("the corpus covers no fixture for reject reason %q", want)
			continue
		}
		// Declared AND present on disk: a manifest row pointing at a missing
		// file would otherwise satisfy the coverage check while testing nothing.
		if _, err := os.Stat(filepath.Join(corpusDir(), path)); err != nil {
			t.Errorf("reason %q names %s, which is not on disk: %v", want, path, err)
		}
	}

	// And nothing extra: a reason added to the corpus but not to corpusReasons
	// would never be checked for coverage by the shell half either.
	for reason, path := range declared {
		if !contains(corpusReasons, reason) {
			t.Errorf("%s declares reason %q, which is absent from corpusReasons", path, reason)
		}
	}

	// Finally, no reject fixture on disk may be missing from the manifest —
	// otherwise a fixture could sit unused and neither reader would run it.
	onDisk, err := filepath.Glob(filepath.Join(corpusDir(), "reject", "*.toml"))
	if err != nil {
		t.Fatal(err)
	}
	if len(onDisk) == 0 {
		t.Fatal("no reject fixtures found on disk")
	}
	for _, abs := range onDisk {
		rel := filepath.Join("reject", filepath.Base(abs))
		var found bool
		for _, row := range rows {
			if row.path == rel {
				found = true
				break
			}
		}
		if !found {
			t.Errorf("%s exists on disk but no expected.txt row drives it", rel)
		}
	}
}
