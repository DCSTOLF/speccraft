---
id: "0052"
title: "Bound the spec:review reviewer payload: tiered context, a pre-dispatch byte budget, and stdin by default"
status: planned
created: 2026-09-28
revision: 0
authors: [claude]
packages: ["commands/spec", "templates/speccraft", "templates/prompts", "agents", "tests/hooks"]
related-specs: ["0014", "0024", "0035", "0039", "0050"]
domains: [external-tool-boundaries, spec-lifecycle]
---

# Spec 0052 — Bound the spec:review reviewer payload

## Why

`/speccraft:spec:review` pastes the whole of `.speccraft/` into every reviewer's
prompt, and nothing bounds it. Step 3 of `commands/spec/review.md` sends
`spec.md` + `index.md` + `guardrails.md` + `architecture.md` + `conventions.md`
in full to each agent. Those memory files only ever grow — every `spec:close`
appends to `conventions.md` and `architecture.md`, and nothing shrinks them —
so the review payload grows without bound as a project runs.

### The reported failure

Field report from tessera-cdc, 2026-09-25, after ~100 closed specs:

- The composed prompt reached **622 KB per reviewer**: `conventions.md` 339 KB
  and `architecture.md` 227 KB. On 2026-08-15 those same two files were 100 KB
  and 33 KB.
- `claude-p` is registered with `input = "argv"`, so the entire prompt went in
  as one command-line argument. Its working limit is about **70 KB** inside the
  600 s timeout. Reviews **timed out or failed**, and the developer had to
  instruct reviewers by hand to "pass paths, don't paste files."
- `codex` receives the prompt on stdin and so escapes the argument limit, but
  still reads all 622 KB.
- Hand-condensing both memory files brought the prompt to 121 KB — **still over
  the `claude-p` limit**, because `spec.md` plus `guardrails.md` alone are about
  50 KB. Compaction alone does not fix this.

### Why the current shape fails badly rather than gracefully

The failure mode is a 600 s timeout, which is the least informative outcome
available. It costs ten minutes per agent, produces no verdict, and names
neither the cause (payload size) nor the remedy. A developer seeing it has no
way to distinguish "the model is slow" from "the prompt never fit."

Worse, a timeout is indistinguishable at the quorum layer from an agent that
simply had nothing to say. Spec 0035 already established that **a timeout is
not a verdict** (`review.md` step 6); an over-budget agent must be held to the
same standard, or a review can reach quorum having actually consulted fewer
models than the developer believes.

### This repository is already exposed

speccraft dogfoods its own plugin, and `.speccraft/` here is real memory:
`conventions.md` is **121,256 bytes** and `architecture.md` **38,670 bytes**
today. A full-paste review from this repo is ~193 KB before `spec.md` is added
— already ~3× the `claude-p` argv limit. The reported bug is not hypothetical
here; it is latent and one spec away from biting.

This spec's own review measured it: round 1 composed **185,372 bytes** and
round 2 **193,123 bytes** — the payload grew 8 KB between rounds purely because
the spec under review got longer. It succeeded only because this repo has
already hand-patched its `.speccraft/agents.toml` to `input = "stdin"` for
`claude-p`, with the comment *"stdin, not argv: large review payloads overflow
the single-argv exec limit."* The workaround exists locally; the shipped
template does not have it.

### The size asymmetry the fix exploits

Measured against this repository's live memory files:

| file | full bytes | `^##`/`^###` heading index |
|---|---|---|
| `conventions.md` | 121,256 | 3,063 |
| `architecture.md` | 38,670 | 111 |

A reviewer that is handed the **path plus a heading index** can read exactly the
sections it needs with its own tools, at 1/40th the payload cost, and — unlike
section-guessing done ahead of time by the command — it cannot be cut off from a
section the pre-selection failed to anticipate.

### Two hazards found while reviewing this spec

**The reference tier has a prerequisite that was unstated.** Handing a reviewer
a path is only useful if the dispatched process starts in the right repository
*and* the agent can open files. If it cannot, the reviewer critiques a file it
never read and returns a plausible-looking verdict — **a worse failure than the
timeout it replaces**, because a timeout is at least legible. The dispatch
contract, the registry capability flag, and the digest attestation below exist
for this.

An earlier revision of this spec proposed a **read sentinel**: a token placed in
each reference record that the reviewer echoes back. Review round 3 correctly
killed it — the sentinel is *in the prompt*, so echoing it proves only that the
reviewer read the prompt. It would have attested nothing while reading as
though it did, which is the same silent-plausibility failure the tier itself
risks. The replacement is a **content digest the reviewer computes**, with the
expected value deliberately withheld from the payload.

**`awk` interval expressions are silently inert here.** This repo's devcontainer
runs **mawk**, which does not support `{n,m}`:

```
$ printf '## a\n### b\n' | awk '/^#{2,3} /{print "MATCH: "$0}'
(no output)
```

A heading extractor written as `/^#{2,3} /` in awk emits **zero headings** on
this machine and a full index under GNU `grep -E` — with no error either way.
That is exactly the silent cross-environment divergence of spec 0050's BSD-grep
defect. `commands/history/compact.lib.sh:26` already encodes the avoidance
(`[0-9][0-9][0-9][0-9]`, never `{4}`); this spec's helper must follow it and be
pinned against it.

## What

Bound the reviewer payload of `/speccraft:spec:review`, with the deterministic
mechanics added to the existing `commands/spec/review.lib.sh` and unit-tested by
a new `tests/hooks/spec-review-payload.bats`.

### 1. Tiered context assembly

Exactly the five files sent today are classified; **nothing is added to what a
reviewer sees**. `history.md` is deliberately NOT introduced into the payload —
this is a boundary change, not a context expansion.

- **INLINE tier** — pasted verbatim, as today: the spec content (`spec.md`, or
  the frozen `review-snapshot.md` on a `--diff` round), `.speccraft/guardrails.md`,
  `.speccraft/index.md`. These are small, and guardrails must be unmissable.
- **REFERENCE tier** — `.speccraft/architecture.md` and
  `.speccraft/conventions.md` become a **repo-relative path, a byte size, and a
  heading index** (`^##` / `^###` in file order). The composition-time digest is
  computed but **not** emitted into the payload (see §5).

Tier membership is a fixed table in the lib, not a heuristic and not a size
threshold. Any other path is an **error**, not a default. The composer itself
classifies every path it is given and rejects a reference-tier file passed in
the inline list — the payload bound cannot depend on every caller remembering
the policy.

### 2. One composition API for both rounds

`review_compose_payload` is the single composer for the full round *and* the
spec-0035 scoped `--diff` round. It takes the template, the spec content source,
the inline set, the reference set, and — for a scoped round — the diff and
changed-sections values that `review_build_payload` substitutes today. The
existing `{{DIFF}}` / `{{CHANGED_SECTIONS}}` template substitution and the prior
`review.md` evidence attachment move inside it, so there is one place that
decides what bytes are sent and therefore one thing the budget measures.

**This requires changing `aux-delegator`, which composes today.** Its current
step 2 prefixes the review template and inlines each context file under a
`## File:` header — exactly the work moving into the lib. Left as is, a review
round would compose twice: the delegator would re-prefix the template, re-inline
context, and for `input = "file"` write a *second* copy, so the bytes measured
by the budget would not be the bytes dispatched and the materialize-once rule
would be violated by the component furthest from the check.

`review.lib.sh` therefore becomes the **sole byte-producing owner** for review
dispatch. `aux-delegator` gains a precomposed-payload path: given the payload
artifact, the input mode, and the cwd, it dispatches those bytes unmodified and
**must not** re-prefix a template, re-inline context files, or create another
copy. Its non-review modes (`implement`, `analyze`) are unchanged.

### 3. A pre-dispatch byte budget with an actionable refusal

**What "bytes" means:** the byte length of the composed payload exactly as it
would be handed to the CLI — UTF-8, with the `## File:` separators and the
reference records, no locale or line-ending normalization, excluding any quoting
or wrapper the CLI adds.

- `REVIEW_MAX_ARGV_BYTES` (default **65536**) — argv-mode agents only. Derived
  from the ~70 KB field-reported working limit, rounded down to a power of two.
  It is a **conservative policy floor, not a guarantee of process creation**:
  real `ARG_MAX` varies (Linux 128 KB–2 MB, macOS 256 KB) and the environment
  block counts against it.
- `REVIEW_MAX_PAYLOAD_BYTES` (default **262144**) — every agent, every mode.
  Derived from measurement, not taste: the largest payload observed to complete
  successfully against both shipped CLIs is this spec's own round-3 review at
  197,238 bytes, and 262144 is the next power of two above it. A payload beyond
  the largest one ever seen to work is refused rather than attempted.

Both derivations are recorded in comments beside the constants, so a later
contributor cannot raise either without confronting the reason it exists. The
payload comment additionally records a **raise-me protocol**, because a spec
only modestly longer than this one would refuse under it: raise the constant
only alongside a recorded observation of a larger payload completing against
both shipped CLIs, and note that `REVIEW_MAX_PAYLOAD_BYTES` is the documented
escape hatch for a one-off. Discovering the bound by tripping a refusal in CI
is the outcome the comment exists to prevent.

Budget behavior is defined for **every** input mode the registry permits, from
what `aux-delegator` actually does today rather than by assumption:
`argv` (both limits); `stdin` and `file` (payload limit only — neither passes
the prompt as an argument); **ACP**, which `agents/aux-delegator.md` invokes as
`acpx <agent> <prompt>` and is therefore **argv transport, subject to both
limits** — normalizing it to stdin would have exempted the one mode most likely
to overflow; and a CLI entry with no `input` key, which normalizes to `stdin`.

Over budget → that agent is **refused before dispatch**, naming the agent, its
input mode, the measured bytes, the limit hit, the inline files ranked by size,
and a remedy **specific to the limit** — stdin fixes an argv-limit refusal and
does nothing for a payload-limit one, which needs compaction or a smaller spec.
Refusal is per-agent. When both limits bite, both are named in the message even
though one enum value is returned.

### 4. Response completeness and approval quorum are different predicates

`review_quorum` counts **agreeing** agents (`approve` / `approve-with-comments`).
Conflating that with "did every reviewer answer" would break the
`changes-requested` path, which must still persist a review. The two predicates
are separate and gate different things:

- **`responses_complete`** — every required reviewer returned a verdict.
  Refusals, timeouts and failures are not verdicts. This gates synthesis:
  `cross-reviewer` runs, `review.md` is written, and `reviewed_sha256` is
  committed **for any verdict, including `changes-requested`** (spec 0035 AC2,
  unchanged).
- **`approval_quorum_met`** — agreeing verdicts ≥ `review_quorum`. This alone
  gates `status: reviewed`.

When `responses_complete` is false the round is **inert**: no synthesis, no
`review.md` write or replace, no fingerprint commit, no `review-snapshot.md`
rewrite, status stays `draft`, and the report names every refusal *and* every
verdict obtained. That is what stops a refusal-only round wiping the prior
`review.md` and collapsing spec 0035's provenance gate on the next `--diff`.

### 5. Reference reads are attested by digest, not assumed

The composer reads each reference file **once** and derives the byte size, the
heading index, and a **SHA-256 digest** from that single scan. Reviewers are
given the ordinary repo-relative path and read the live file — there is **one**
path in this design, not two.

A snapshot-and-dispatch-against-the-copy variant was considered and rejected:
it introduced a second identity for every reference (the path named in the
payload versus the path actually read), and made reviewer access depend on a
temp location a sandboxed CLI may not be able to open. The residual exposure is
a file changing between composition and review — a window of seconds, in which
the digest simply fails to match and the verdict is **not counted**. That is
the safe direction, and it is the same outcome as an unread reference.

The expected digest is retained by the caller and **never appears in the
payload**. The reviewer result schema gains:

```yaml
reference_access:
  - path: "<repo-relative path as given>"
    sha256: "<digest the reviewer computed after reading>"
reference_access_failures:
  - path: "<path>"
    reason: "<why it could not be read>"
```

Validation is exact: every expected path appears in `reference_access` exactly
once, no unknown path is accepted, and every digest matches the composition-time
value. A verdict that fails any of these, or that reports a non-empty
`reference_access_failures`, **counts toward neither predicate** — the same rule
as a timeout.

A digest cannot be produced without reading the bytes, so this attests access
rather than asking the reviewer to confirm it.

**What it does and does not prove.** A matching digest establishes that a
process with filesystem access at the dispatched cwd obtained the referenced
bytes. It does **not** establish that the model incorporated those bytes into
its reasoning — a reviewer could checksum a path without ever bringing the
content into context. The guarantee is deliberately the weaker one: it converts
"this agent cannot read files at all, and nobody noticed" from an invisible
failure into a mechanical one, which is the failure actually reported from the
field. Claiming it proves the file was *read and used* would overstate it, and
this spec does not rely on that stronger reading anywhere.

The digest primitive must be portable. `sha256sum` is GNU-only and absent from a
default macOS userland; the repo already lost eight CI runs to exactly this
BSD/GNU class (spec 0050). The implementation resolves one primitive once —
preferring `shasum -a 256`, which is present on both — and is pinned on both
polarities, so the attestation cannot be the next silent cross-environment
divergence while `awk` intervals are carefully guarded beside it.

### 6. The payload is materialized once and measured as dispatched

"Bytes exactly as handed to the CLI" cannot be guaranteed through shell command
substitution, which strips trailing newlines. The composer therefore writes the
payload to a single file (mode `0600`) inside the round's temp directory; the
budget is measured over **that file**, and **that same file** is what is piped
to stdin, passed with `--file`, or read for an argv-mode invocation. Measured
bytes and dispatched bytes are the same bytes by construction, not by
convention. The temp directory is removed when the round ends.

This is the *only* materialization permitted. No debug or convenience copy of
the composed payload may be written anywhere else — a cached full prompt would
reintroduce the unbounded artifact by a side channel while the budget check
still reported success.

### 7. stdin by default, and an advisory for repos already installed

`templates/speccraft/agents.toml` changes `claude-p` and `opencode` from
`input = "argv"` to `input = "stdin"`. Existing repos own their
`.speccraft/agents.toml` and are not rewritten, so the argv budget check emits
the concrete migration line.

## Contracts

Pinned signatures, so an implementer does not infer the interface from prose:

```
review_context_tier <path>                     → "inline" | "reference" | error
review_heading_index <file>                    → heading lines on stdout
review_compose_payload <template> <spec-src> \
    --inline <f…> --reference <f…> \
    --digest-out <path> \
    [--diff <diff> --changed <sections>]       → composed bytes on STDOUT
review_budget_check <bytes> <input-mode>       → "ok" | "refuse:<reason>"
review_refusal_message <agent> <mode> <bytes> <reason> <ranked-files>
```

The composition-time digests need a channel that is **not** the payload, since
AC6 forbids them appearing in the bytes the reviewer sees. `--digest-out` names
that channel: the composer writes `<sha256>  <repo-relative-path>` lines there,
one per reference file, from the same single scan (AC8). Without it the contract
would be unimplementable except via a global, a sidecar the spec never named, or
a second scan that AC8 forbids.

`review_compose_payload` writes **no payload file**: it emits the composed bytes
to stdout, and the command driver redirects that stream once into the sole mode-
`0600` artifact. The digest file is the one other thing it writes, and it never
enters the payload. This keeps the lib's helpers free of dispatch-lifecycle side
effects, gives the driver one place to own the temp dir, the cleanup trap, the
budget check and dispatch, and — because the stream is redirected rather than
captured into a variable — avoids the command-substitution trailing-newline
strip that would otherwise make measured and dispatched bytes differ.

## Acceptance criteria

1. `review_context_tier <path>` echoes `inline` for `.speccraft/guardrails.md`
   and `.speccraft/index.md`, `reference` for `.speccraft/architecture.md` and
   `.speccraft/conventions.md`, and exits non-zero with a named error for any
   other path — **including `.speccraft/history.md`**, which this spec does not
   add to the payload. Classification resolves against the root that
   `speccraft-state find-root` reports and matches the full repo-relative
   `.speccraft/<name>`, **not** the trailing basename, so
   `vendor/other/.speccraft/conventions.md` and a spec document named
   `conventions.md` are errors rather than silently `reference`. An absolute
   path, a `./`-prefixed path, and a bare `.speccraft/<name>` classify
   identically.

2. `review_compose_payload` classifies every path it is handed and **rejects a
   tier mismatch**: a reference-tier file passed in the inline set is a named
   error, not a full paste. Asserted by calling the composer with
   `conventions.md` in the inline position and requiring a non-zero exit — so
   the payload bound does not depend on callers remembering the policy.

3. `review_heading_index <file>` emits every `^## ` and `^### ` heading in file
   order and nothing else. Shape is pinned by curated fixtures under
   `tests/hooks/fixtures/spec-review-payload/`, each asserted exactly: no
   headings (empty output, exit 0); `##`-only; `###`-only; `####` (excluded); a
   heading with a `` `code span` ``; a heading with non-ASCII; and a CRLF file
   (headings emitted without the trailing `\r`). No criterion pins a heading
   count of a live `.speccraft/` file, so an unrelated `spec:close` cannot break
   this suite.

4. The fenced-block grammar is defined rather than gestured at, so two
   conforming implementations cannot disagree: a fence opens on a line whose
   first non-space run is **three or more backticks or three or more tildes**,
   may carry an info string, and closes only on a line of the **same character
   at the same or greater length**; a `##` line inside an open fence is never
   emitted; an **unclosed** fence suppresses headings to end of file. One
   fixture per clause — backtick, tilde, a four-char fence not closed by three,
   an info string, an indented fence, an unclosed fence — each asserted exactly.
   This matters because `.speccraft/conventions.md` today has 55 headings and
   **zero** inside fences, so a grammar bug would be invisible on the live
   corpus and would surface only in a host repo whose memory files use fenced
   examples.

5. `review_heading_index` uses no regex interval expression (`{n}` / `{n,m}`) in
   any `awk` or `grep` invocation, following `commands/history/compact.lib.sh:26`.
   Pinned two ways: a source scan over **every `commands/spec/*.lib.sh` this
   spec adds or touches** — so factoring the helper into a sibling file cannot
   move it out from under the guard — rejecting an interval inside an
   `awk`/`grep -E` program, and a **behavioral** test that runs the extractor
   under the environment's own `awk` and requires a non-empty index for the
   `##`-only fixture. The behavioral arm is what bites: under mawk the interval
   form silently emits zero lines, so a test asserting only "no crash" would
   pass on a broken extractor.

6. The composed payload emits, in order: the review template; each inline file
   under its `## File: <path>` header with full contents; then a
   `## Reference files (read these yourself)` section with one record per
   reference file of repo-relative path, byte size and heading index — and **at
   no point the body text of a reference file, nor its composition-time
   digest**. Asserted against a fixture whose body carries a deterministic
   marker the heading grammar cannot produce, and against a separate assertion
   that the expected digest is absent — if it leaked, a reviewer could echo it
   without reading. Both are proved to bite per AC25.

7. Absence and omission are distinguished by **who named the file**, so the two
   cases cannot conflict. A file **passed in the reference set but missing on
   disk** is a named error — a missing `conventions.md` must not quietly shrink
   the payload and leave the reviewer unaware a whole tier is absent. A caller
   passing an **empty reference set** is legitimate: the
   `## Reference files` section is emitted with an explicit "none" marker rather
   than omitted, so a reviewer can distinguish "no reference files were sent"
   from "the section was dropped by a bug". Both arms asserted.

8. `review_compose_payload` — implemented in shell in `review.lib.sh` — reads
   each reference file **once** and derives byte size, heading index and
   SHA-256 digest from that single scan. Pinned **behaviorally** by a
   read-counting fixture (a FIFO or equivalent single-use source yielding
   content on first read and empty thereafter): the naive two-pass shape
   (`wc -c "$f"` then `grep -nE '^## |^### ' "$f"`) produces a record whose size
   and index disagree, and the test fails. A source scan alone is not sufficient
   evidence. The FIFO is a Unix-only proof technique, not part of the shipped
   contract; the test file is gated at the suite level rather than skipping at
   runtime, so a silent skip cannot erode the one-scan proof.

9. The digest primitive works on both BSD and GNU userland. `sha256sum` is
   GNU-only and absent from a default macOS install; the implementation resolves
   one primitive (preferring `shasum -a 256`) and is pinned on both polarities
   alongside the AC5 interval guard — the two traps are the same class, and this
   repo lost eight consecutive CI runs to the other one.

10. The payload is materialized exactly once. `review_compose_payload` writes no
    file; the command driver redirects its stdout into a single mode-`0600`
    artifact in the round's temp directory, `review_budget_check` measures
    **that artifact**, and the same artifact is dispatched (piped to stdin,
    passed via `--file`, or read for argv). Asserted by comparing the measured
    byte count to `wc -c` of the artifact actually handed to dispatch, catching
    the command-substitution trailing-newline strip that would otherwise make
    measured and dispatched bytes differ silently.

11. The no-second-copy invariant is bounded to **named observable seams**, not
    asserted across an unspecified filesystem: every payload-materialization
    call site in `review.lib.sh` and every file creation in `aux-delegator`'s
    review path are instrumented, and the test requires exactly one creation per
    round. An unbounded "no copy anywhere" check would itself be the vacuous
    negative this spec argues against.

12. The round's temp directory is removed on **abnormal exit as well as normal**
    — a trap installed immediately after creation covering `EXIT`, `HUP`, `INT`
    and `TERM`. Asserted for both a clean round and an interrupted one, so a
    crash cannot leave a full review prompt on disk indefinitely.

13. The exact-byte dispatch guarantee has a stated representability boundary.
    The payload domain is **NUL-free, valid UTF-8**; a payload containing a NUL
    byte or an invalid UTF-8 sequence is **rejected before dispatch with a named
    diagnostic naming which of the two failed**, because POSIX argv cannot carry
    an embedded NUL and the measured-equals-dispatched claim would otherwise be
    unimplementable for argv mode. Heading extraction and byte counting run
    under `LC_ALL=C`, so two hosts with different locales cannot compose
    different records from the same inputs. Asserted with a NUL-bearing fixture,
    an invalid-UTF-8 fixture, and a non-ASCII heading fixture composed under two
    locale settings yielding byte-identical output.

13b. The **file-to-argv conversion preserves bytes**. Reading an artifact into a
    shell variable for argv dispatch strips trailing newlines — the same defect
    AC10 closes for composition, arriving one step later. The conversion
    therefore uses a byte-preserving read, pinned by a round-trip test: the
    digest of the bytes reaching the CLI boundary in `argv` and `acp` mode must
    equal the digest of the artifact, for a fixture ending in one newline, in
    several newlines, and in no newline at all.

14. `aux-delegator` is a pure dispatcher for review rounds. Given a precomposed
    payload artifact, an input mode and a cwd, it sends those bytes unmodified
    and **must not** re-prefix the review template, re-inline context files, or
    write another copy for `input = "file"`. Asserted by dispatching a payload
    of known digest and requiring the bytes at the CLI boundary to match
    exactly. Its `implement` and `analyze` modes are asserted **byte-identical
    to today**, not merely described as unchanged.

15. `review_compose_payload` is the single composer for both rounds. On a scoped
    `--diff` round it accepts the diff and changed-sections values and performs
    the `{{DIFF}}` / `{{CHANGED_SECTIONS}}` substitution and prior-`review.md`
    attachment that `review_build_payload` performs today, producing a payload
    satisfying spec 0035's existing scoped-payload assertions. Pinned by
    composing a scoped round and asserting the substituted markers are present
    and no `{{...}}` placeholder survives.

16. The `--diff` single-read transaction is preserved and the budget applies to
    both branches. On `scoped` and `full-review` the inline spec content comes
    from the frozen `review-snapshot.md` and `spec.md` is not re-read (asserted
    with a snapshot and a `spec.md` whose markers differ: snapshot marker
    present, `spec.md` marker absent), and `review_budget_check` runs on the
    composed payload of **both** branches, so a small delta with a large heading
    index still refuses under argv mode.

17. Composing this repository's live `.speccraft/` plus the **largest archived
    `spec.md`, selected dynamically at test time** (no hard-coded path or byte
    count, with a lexicographic-id tiebreaker so two same-sized specs cannot
    make the selection non-deterministic) yields a payload under
    `REVIEW_MAX_ARGV_BYTES`, where a full paste of the same inputs exceeds it by
    more than 2×. Both halves are asserted. When `specs/.archive/` is absent or
    empty — a fresh clone, a shallow CI checkout — the test **skips with a
    stated reason** rather than failing or silently passing. This is the only
    criterion reading live memory files, and it asserts a ratio, never a count.

18. Because AC17 can skip, a **static counterpart** asserts the ratio over
    bundled fixtures of known size and never skips. It is pinned
    **bidirectionally**: the tiered composition must be under the argv limit
    **and** at least 2× smaller than the full paste of the same inputs — so a
    regression eroding the compression ratio while still landing just under the
    limit fails, rather than passing on the absolute bound alone. AC17 proves
    "today's real tree fits"; AC18 proves "the mechanism works" everywhere.

19. `review_budget_check <bytes> <input-mode>` echoes `ok` or `refuse:<reason>`
    and exits 0 in both cases (a refusal is data, not a shell failure). The mode
    matrix is exhaustive and each row is asserted: `argv` — both limits;
    **`acp` — both limits**, because `aux-delegator` invokes it as
    `acpx <agent> <prompt>`, which is argv transport (omitting it would exempt
    the mode most likely to overflow); `stdin` and `file` — payload limit only;
    empty or absent — normalizes to `stdin`. `refuse:argv-limit` above
    `REVIEW_MAX_ARGV_BYTES`, `refuse:payload-limit` above
    `REVIEW_MAX_PAYLOAD_BYTES`, and `refuse:payload-limit` wins deterministically
    when both are exceeded. The reason enum is exhaustively pinned — the test
    enumerates both values and fails on any other. Each boundary is pinned at
    limit-1 / limit / limit+1, with the value **at** the limit accepted.

20. `review_refusal_message <agent> <mode> <bytes> <reason> <ranked-files>`
    contains, each asserted by exact match rather than length: the agent name;
    the input-mode string; the measured bytes; the numeric limit exceeded —
    **derived from the runtime effective value, not the compiled default**, so
    the diagnostic cannot disagree with the behavior when an override is in
    play; and at least one named oversized file. For `refuse:argv-limit` it
    contains the literal migration line `input = "stdin"` and the path
    `.speccraft/agents.toml`. For `refuse:payload-limit` it names the actual
    remedy — compaction of the oversized memory files, or a shorter spec — and
    **must not** contain the migration line. When both limits are exceeded the
    message names both, worded so the argv limit cannot be read as an available
    remedy, asserted against the literal phrasing that a stdin-mode agent would
    still be refused.

21. Environment overrides are validated with one unambiguous behavior:
    `REVIEW_MAX_ARGV_BYTES` / `REVIEW_MAX_PAYLOAD_BYTES` are accepted only as
    positive base-10 integers ≥ `REVIEW_MIN_LIMIT_BYTES` (a named constant,
    1024, documented as "below this the value is definitionally a config bug —
    the compiled default is 64 KB"). An empty, zero, negative, non-numeric or
    below-floor value **emits a named error to stderr naming the offending
    variable and proceeds with the compiled default** — it does not abort the
    review. Asserted for each rejected shape plus the stderr text. The valid
    override is also the sanctioned one-shot escape hatch for an oversized
    round, which is why it must be legible rather than silent.

22. The two predicates are separately observable and gate different things.
    `responses_complete` (every required reviewer returned a verdict) gates
    synthesis, the `review.md` write, and the `reviewed_sha256` commit — and
    holds **for any verdict, including `changes-requested`**, preserving spec
    0035 AC2. `approval_quorum_met` (agreeing verdicts ≥ `review_quorum`) alone
    gates `status: reviewed`. Asserted by a case with two `changes-requested`
    verdicts and quorum 1: `review.md` IS written and stamped, and status stays
    `draft`.

23. When `responses_complete` is false — all agents refused, or some refused and
    some returned verdicts — the round is inert: `cross-reviewer` is not
    invoked; `review.md` is neither written nor replaced; no fingerprint is
    committed; `review-snapshot.md` is not rewritten; status stays `draft`; and
    the report names every refusal and every verdict obtained. Asserted by
    byte-equality of a pre-existing `review.md` **and** zero atomic-rename
    operations targeting it or the snapshot — proved at the seam, not inferred
    from unchanged bytes.

24. The `--diff` snapshot write is ordered against the inert-round rule. Spec
    0035's `review-diff --promote` writes `review-snapshot.md` at the START of a
    round, before any verdict exists, which would mutate the very anchor AC23
    requires unchanged. The round therefore **defers the promote until
    `responses_complete` holds**; an inert round leaves `review-snapshot.md`
    byte-identical and the next `--diff` anchors on the same baseline. Asserted
    by running an all-refused round against a repo with an existing snapshot and
    requiring byte-equality plus zero writes at the seam — without this, a
    refusal-only round silently re-baselines and the following round
    misclassifies.

25. Reference reads are attested by digest. `templates/prompts/review.md`
    requires the reviewer to return `reference_access: [{path, sha256}]` for
    every reference file, computing the digest after reading it, and to report
    any it could not read in `reference_access_failures: [{path, reason}]`.
    Validation is exact and each arm is asserted with a recorded reviewer
    response: every expected path present exactly once (a missing path fails);
    no unknown path accepted; every digest matching the composition-time value
    (a wrong digest fails); duplicate entries for one path rejected; malformed
    or absent `reference_access` rejected; non-empty `reference_access_failures`
    rejected. A verdict failing any arm counts toward neither predicate. The
    validator is exercised against **captured historical reviewer responses**
    from this spec's own review rounds, so a parser too strict for how the
    shipped CLIs actually wrap YAML is caught before it fails every verdict.
    Digest and access failures are reported as their own category in the round
    summary — a chronically failing reviewer must be diagnosable, not merely
    excluded.

26. Reviewer capability is a dispatch contract with **two distinct halves**,
    because the agents that fail in the field are external CLIs configured in
    `.speccraft/agents.toml` and have no `agents/*.md` frontmatter at all:
    - **Subagents** (`agents/*.md`, e.g. `aux-delegator`) — frontmatter `tools:`
      must include `Read`, asserted per-agent.
    - **External CLIs** (`agents.toml` entries) — the registry gains a
      `reference_read` capability flag that is **opt-out: an absent flag means
      `true`**. Only an explicit `reference_read = false` refuses reference-tier
      dispatch, with a named message. Making absence mean "incapable" would have
      been an operationally breaking upgrade — every already-initialized repo
      lacks the key, so every configured reviewer would become ineligible on the
      first `git pull`. Asserted for the flag absent (dispatches), `false`
      (refuses with the named message), and `true` (dispatches).

    Both halves are invoked with cwd set to the root `speccraft-state find-root`
    reports for the active spec — in a workspace, the member repo. This **pins**
    the existing `aux-delegator` behavior recorded at
    `.speccraft/architecture.md:211`; it is not a change.

27. `commands/spec/review.md` and `templates/prompts/review.md` are pinned
    positively, not only negatively. A meta-test locates three named markers —
    the `review.lib.sh` source, the composer call, and the `review_budget_check`
    call — and asserts their **relative order** against the dispatch marker
    (compose → budget-check → dispatch) by comparing found indices rather than
    absolute line numbers, so a legitimate runbook reorganization cannot break
    it without changing behavior. It also asserts the file no longer instructs a
    full paste of any reference-tier file. The prompt template is pinned by
    literal marker strings: that reference files are given by path and must be
    read with the reviewer's own tools, that `reference_access` digests must be
    returned, and that an unreadable reference invalidates the verdict.

28. `templates/speccraft/agents.toml` sets `input = "stdin"` for both `claude-p`
    and `opencode`, and **no** `[[agents]]` entry retains `input = "argv"`.
    Every entry that ships enabled also carries an explicit
    `reference_read = true`, so a fresh `/speccraft:init` produces a template
    whose reviewers can receive reference-tier files rather than one depending
    on the opt-out default. Asserted by parsing the template per-agent, so an
    agent added later with `argv`, or an enabled entry missing the flag, fails
    rather than passing on a whole-file grep.

29. Every negative assertion in this suite is proved to bite by a **checked-in
    artifact**, not by author discipline. Each "X must not appear" check is
    paired with a committed forbidden fixture the check is run against and must
    reject — covering the reference-body-absent and digest-absent checks (AC6),
    the single-materialization check (AC11), and the runbook no-full-paste check
    (AC27). A procedural note that the author briefly reintroduced the offender
    and reverted leaves no artifact and does not satisfy this criterion; the
    repo shipped three inert negatives in one spec (0049) on exactly that basis.

## Notes for the plan

- **Group, do not atomize.** Several criteria share one seam (AC10/AC11/AC14 are
  the materialize-and-dispatch boundary; AC17/AC18 are one ratio assertion over
  two corpora). Prefer compound REDs covering a whole envelope, per spec 0048's
  JSON-envelope technique, over one RED per clause — atomizing inflates the
  override budget without adding coverage.
- **Spot-check before planning edits.** `agents/aux-delegator.md` frontmatter
  already lists `[Bash, Read]`, so AC26's subagent half may pass trivially;
  confirm rather than plan an edit that is not needed.
- **Sequence AC24 early.** The promote-deferral changes round ordering that
  several later criteria assert against.

## Out of scope

- **Bounding the memory files themselves.** Size limits on `conventions.md` and
  `architecture.md`, a `/speccraft:memory:compact` command, and the close-time
  content-routing rules that stop `architecture.md` becoming a second history
  are the companion spec's subject. This spec makes review survive large memory
  files; it does not make the files small.
- **Adding `history.md` to the reviewer payload.** Considered and rejected: it
  is not sent today, and expanding what reviewers see inside a spec whose
  purpose is bounding the payload would be scope creep. AC1 makes it an
  explicit error rather than an accident.
- **Verifying that each aux CLI parses a stdin prompt identically to argv.**
  The template flip is a behavioral change, not a label change, but testing it
  requires live credentialed CLI runs this suite does not have. Mitigation: this
  repository has run `claude -p` on stdin for its own reviews since before this
  spec, including both rounds of this spec's own review at 185 KB and 193 KB.
  Recorded as a known gap, not an untested assumption.
- **Changing `agents.toml` in repos already initialized.** Surfacing a
  still-`argv` `agents.toml` in `/speccraft:sync`'s drift report is the better
  durable nudge and is filed as a follow-up.
- **An auto-fallback from `argv` to `stdin` at dispatch time.** Rejected: it
  would diverge from the configured contract for a CLI that genuinely requires
  argv, and turn a legible refusal into a silent behavior change.
- **Section-scoped excerpting of the reference files.** Rejected in favor of
  path + heading index: a heading-match heuristic that misses a section means a
  guardrail the reviewer never saw, and the failure is silent.
- **A size threshold overriding tier membership.** Rejected: uniform treatment
  keeps tier a fixed property and avoids a payload whose shape depends on the
  day's file sizes.
- **Probing `getconf ARG_MAX` instead of a fixed constant.** Rejected: the
  usable limit is not `ARG_MAX`, and a probe would make the refusal boundary
  vary by machine, so a review that refuses on CI would pass locally.
- `/speccraft:spec:review-code`, `/speccraft:arch:review`, `/speccraft:pm:review`.
  Only `review-code.md` shares the pattern; migrating it is a follow-up once the
  helpers have proven out here.
- Raising or tuning `review_timeout_s`. The budget check exists so the timeout
  stops being how oversize is discovered.

## Open questions

_none_
