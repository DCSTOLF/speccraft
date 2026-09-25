package main

// Spec 0049 T5 (AC4, AC2) — the `set-status` CLI boundary.
//
// This is the ONLY place the no-`--kind` convenience default is applied. The Go
// API (`speccraft.SetStatus`) takes a typed `ArtifactKind` with no meaningful
// zero value and rejects the empty kind, so a defaulting *wrapper* in the
// library would be the silent-default surface spec 0049 removes. Keeping the
// default here — visible, documented, and one hop from the usage string — is
// the deliberate trade.
//
// Lives in the cmd package behind the `run()` seam (conventions.md), so its
// failure paths are exercised by in-process tests rather than needing a built
// binary.

import (
	"fmt"
	"io"
	"strings"

	"github.com/dcstolf/speccraft/tools/internal/speccraft"
)

const setStatusUsage = "usage: speccraft-state set-status [--kind spec|design|brief] <artifact.md> <status>"

// setStatusCmd parses `[--kind X] <artifact> <status>` and delegates to the
// sanctioned writer. args excludes the subcommand name.
//
// Flags are accepted only BEFORE the positionals. A flag appearing after them
// is a usage error, never a silent ignore: silently ignoring `--kind design`
// would write the spec enum against a design and reproduce exactly the
// "reported success, did the wrong thing" failure this spec exists to remove.
// Every non-zero return writes a diagnostic to stderr (AC2).
func setStatusCmd(args []string, stderr io.Writer) int {
	kind := speccraft.KindSpec // the one and only default, applied here
	i := 0
flags:
	for ; i < len(args); i++ {
		a := args[i]
		switch {
		case a == "--kind":
			if i+1 >= len(args) {
				fmt.Fprintln(stderr, "set-status: --kind needs a value")
				fmt.Fprintln(stderr, setStatusUsage)
				return 1
			}
			kind = speccraft.ArtifactKind(args[i+1])
			i++
		case strings.HasPrefix(a, "--kind="):
			kind = speccraft.ArtifactKind(strings.TrimPrefix(a, "--kind="))
		case strings.HasPrefix(a, "-"):
			fmt.Fprintf(stderr, "set-status: unknown flag %s\n", a)
			fmt.Fprintln(stderr, setStatusUsage)
			return 1
		default:
			break flags // first positional: flag parsing stops here
		}
	}

	rest := args[i:]
	if len(rest) < 2 {
		fmt.Fprintln(stderr, setStatusUsage)
		return 1
	}
	// A flag after the positionals is a usage error, not a silent ignore.
	if len(rest) > 2 {
		fmt.Fprintf(stderr, "set-status: unexpected argument %q after the positionals; "+
			"the --kind flag must precede <artifact.md> <status>\n", rest[2])
		fmt.Fprintln(stderr, setStatusUsage)
		return 1
	}
	if err := speccraft.SetStatus(rest[0], kind, rest[1]); err != nil {
		fmt.Fprintln(stderr, err)
		return 1
	}
	return 0
}
